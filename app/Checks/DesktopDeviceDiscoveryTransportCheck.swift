import Foundation

@main
struct DesktopDeviceDiscoveryTransportCheck {
    @MainActor static func main() async throws {
        let port = UInt16(CommandLine.arguments[1])!
        let scenario = CommandLine.arguments[2]
        let serial: UInt32 = 7241
        let report = MacDeviceReport(version: "0.13.9", name: "测试 & <Mac>", model: "Mac16,1",
            system: "macOS 15.1.0", ip: "192.0.2.20", mac: "00:01:02:03:04:05",
            subnetMask: "255.255.255.0", hardwareUUID: UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!,
            processor: "arm64", diskBytes: 256 * (1 << 30))
        do {
            let reply = try await DesktopDeviceDiscoveryProbe().run(
                host: "127.0.0.1", port: port, report: report, serial: serial)
            precondition(scenario == "valid")
            precondition(reply.agentID == "4831" && reply.serverID == "server-test")
            precondition(reply.registration == .reregistrationRequired)
            let registered = try reply.deviceRecord(from: ["Registered": "1", "IP": "192.0.2.20"])
            precondition(registered.id == reply.agentID && registered.registered == "1" && registered.ip == "192.0.2.20")
            let pending = try reply.deviceRecord(from: ["DeviceID": 4831, "Registered": "0"])
            precondition(pending.registered == "0")
            let fallback = try reply.deviceRecord(from: ["DeviceID": 4831])
            precondition(fallback.registered == "-1")
            do {
                _ = try reply.deviceRecord(from: ["DeviceID": 4832, "Registered": "1"])
                preconditionFailure("Different record must not be used for login")
            } catch DesktopDeviceDiscovery.Failure.mismatchedRecord {}
            let context = AuthenticationRequest.Context(origin: URL(string: "http://192.0.2.10")!,
                osType: "mac", headerOSType: "mac", language: "zh", cacheMilliseconds: 1, serialNumber: "123")
            let query = try reply.registrationQuery(context: context)
            precondition(query.url?.path == "/access/1.0/mac/json/device/info")
            precondition(query.httpMethod == "POST")
            precondition(query.httpBody == Data("deviceId=4831&form=AgentReg&basIP=&UrlAscid=".utf8))
        } catch let failure as DesktopDeviceDiscovery.Failure {
            let expected: [String: DesktopDeviceDiscovery.Failure] = [
                "wrong-serial": .mismatchedReply, "wrong-trade": .mismatchedReply,
                "missing-id": .invalidAgentID, "zero-id": .invalidAgentID,
                "duplicate-id": .invalidXML, "doctype": .invalidXML
            ]
            precondition(expected[scenario] == failure, "\(scenario): \(failure)")
        }
        print("PASS: desktop discovery loopback \(scenario)")
    }
}
