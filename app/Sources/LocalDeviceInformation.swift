import Foundation
import Darwin
import SystemConfiguration

struct LocalDeviceInformation {
    struct NetworkAddress: Identifiable {
        let interface: String
        let ip: String
        let mac: String
        var kind: String = ""
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
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                                  nil, 0, NI_NUMERICHOST) == 0 else { continue }
                let interface = String(cString: info.ifa_name)
                addresses.append(.init(interface: interface, ip: String(cString: host), mac: hardwareAddresses[interface] ?? "",
                                       kind: interfaceKinds[interface] ?? ""))
            }
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return .init(name: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
                     model: model, system: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                     addresses: addresses.sorted { ($0.interface, $0.ip) < ($1.interface, $1.ip) })
    }
}
