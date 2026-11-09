import Foundation
import Darwin
import IOKit
import SystemConfiguration

struct LocalDeviceInformation {
    struct NetworkAddress: Identifiable, Equatable, Sendable {
        let interface: String
        let ip: String
        let mac: String
        var kind: String = ""
        var subnetMask: String = ""
        var id: String { interface + ":" + ip }
    }
    let name: String
    let model: String
    let system: String
    let addresses: [NetworkAddress]

    /// Physical network addresses for the menu; excludes TUN, VPN, and loopback addresses.
    var physicalAddresses: [NetworkAddress] { addresses.filter { !$0.kind.isEmpty } }

    static func read() -> Self {
        var count = 0
        var model = ""
        if sysctlbyname("hw.model", nil, &count, nil, 0) == 0, count > 0, count < 1024 {
            var bytes = [CChar](repeating: 0, count: count)
            if sysctlbyname("hw.model", &bytes, &count, nil, 0) == 0 { model = String(cString: bytes) }
        }
        var hardwareAddresses: [String: String] = [:]
        var interfaceKinds: [String: String] = [:]
        if let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for interface in interfaces {
                guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
                if let mac = SCNetworkInterfaceGetHardwareAddressString(interface) as String? {
                    hardwareAddresses[bsd] = mac
                }
                let type = SCNetworkInterfaceGetInterfaceType(interface) as String?
                if type == (kSCNetworkInterfaceTypeIEEE80211 as String) {
                    interfaceKinds[bsd] = "Wi-Fi"
                } else if type == (kSCNetworkInterfaceTypeEthernet as String) {
                    interfaceKinds[bsd] = "有线"
                }
            }
        }
        var head: UnsafeMutablePointer<ifaddrs>?
        var addresses: [NetworkAddress] = []
        if getifaddrs(&head) == 0 {
            defer { freeifaddrs(head) }
            var item = head
            while let current = item {
                let info = current.pointee
                item = info.ifa_next
                guard let address = info.ifa_addr,
                      Int32(address.pointee.sa_family) == AF_INET,
                      info.ifa_flags & UInt32(IFF_UP) != 0,
                      info.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
                guard let ip = numericAddress(address) else { continue }
                let mask = info.ifa_netmask.flatMap { numericAddress($0) } ?? ""
                let interface = String(cString: info.ifa_name)
                addresses.append(.init(interface: interface, ip: ip, mac: hardwareAddresses[interface] ?? "",
                                       kind: interfaceKinds[interface] ?? "", subnetMask: mask))
            }
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return .init(name: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
                     model: model, system: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                     addresses: addresses.sorted { ($0.interface, $0.ip) < ($1.interface, $1.ip) })
    }

    /// A connected UDP socket selects a local source address without sending a datagram.
    static func addressForServer(_ host: String) async -> NetworkAddress? {
        let source = await Task.detached { sourceIPv4(host) }.value
        guard let source else { return nil }
        let candidates = read().physicalAddresses.filter {
            $0.ip == source && !$0.mac.isEmpty && !$0.subnetMask.isEmpty
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    static func report(for address: NetworkAddress) -> MacDeviceReport? {
        let local = read()
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(entry, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String,
              let uuid = UUID(uuidString: value),
              !local.model.isEmpty else { return nil }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        var size = 0
        var processor = ""
        if sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0, size < 1024 {
            var bytes = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 {
                processor = String(cString: bytes)
            }
        }
        #if arch(arm64)
        if processor.isEmpty { processor = "arm64" }
        #elseif arch(x86_64)
        if processor.isEmpty { processor = "x86_64" }
        #endif
        let filesystem = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        let diskBytes = (filesystem?[.systemSize] as? NSNumber)?.uint64Value
        return MacDeviceReport(version: version, name: ProcessInfo.processInfo.hostName, model: local.model,
            system: local.system, ip: address.ip, mac: address.mac, subnetMask: address.subnetMask,
            hardwareUUID: uuid, processor: processor, diskBytes: diskBytes)
    }

    private static func numericAddress(_ address: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                          nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: host)
    }

    private static func sourceIPv4(_ host: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var addresses: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "9", &hints, &addresses) == 0, let addresses else { return nil }
        defer { freeaddrinfo(addresses) }

        var sources = Set<String>()
        var entry: UnsafeMutablePointer<addrinfo>? = addresses
        while let current = entry {
            let info = current.pointee
            entry = info.ai_next
            let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
            guard descriptor >= 0 else { continue }
            defer { close(descriptor) }
            guard connect(descriptor, info.ai_addr, info.ai_addrlen) == 0 else { continue }
            var address = sockaddr()
            var size = socklen_t(MemoryLayout<sockaddr>.size)
            guard getsockname(descriptor, &address, &size) == 0,
                  let source = withUnsafePointer(to: &address, { numericAddress($0) }) else { continue }
            sources.insert(source)
        }
        return sources.count == 1 ? sources.first : nil
    }
}
