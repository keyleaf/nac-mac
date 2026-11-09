import Foundation

@main
struct MacDeviceReportCheck {
    static func main() throws {
        let report = MacDeviceReport(version: "0.13.6", name: "测试 & <Mac>", model: "Mac16,1",
            system: "macOS 15.1.0", ip: "192.0.2.20", mac: "00:01:02:03:04:05",
            subnetMask: "255.255.255.0", hardwareUUID: UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!,
            processor: "arm64", diskBytes: 256 * (1 << 30))
        let fields = Dictionary(uniqueKeysWithValues: report.fields)
        precondition(fields["gettype"] == "control" && fields["os_platform"] == "macOS")
        let xml = try WebBase64.decode(fields["dev_xml"]!)
        precondition(xml.allSatisfy { $0 < 128 })
        let text = String(decoding: xml, as: UTF8.self)
        precondition(text.contains("<ComputerName>&#27979;&#35797; &amp; &lt;Mac&gt;</ComputerName>"))
        precondition(text.contains("<Ip>192.0.2.20</Ip>") && text.contains("<Mark>255.255.255.0</Mark>"))
        precondition(text.contains("<DiskId>00112233-4455-6677-8899-AABBCCDDEEFF</DiskId>"))
        precondition(text.contains("<DiskSize>256.0 GB</DiskSize><GateWay></GateWay>"))
        precondition(text.contains("<AllIp>192.0.2.20</AllIp><AllMark>255.255.255.0</AllMark><AllMac>00:01:02:03:04:05</AllMac>"))
        let mac = DeviceRecord(fields: ["DeviceID": "synthetic", "OSName": "macOS 15.1", "Mac": "00-01-02-03-04-05"])
        let ios = DeviceRecord(fields: ["DeviceID": "synthetic", "OSName": "ios", "Mac": report.mac])
        precondition(mac.matchesMac(report.mac) && !mac.matchesMac("00:01:02:03:04:06") && !ios.matchesMac(report.mac))
        print("PASS: native Mac report encoding, XML escaping, and Mac record identity matching")
    }
}
