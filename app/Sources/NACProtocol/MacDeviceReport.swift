import Foundation

/// The provisional native device discovery format recovered from the original client.
struct MacDeviceReport {
    let version: String
    let name: String
    let model: String
    let system: String
    let ip: String
    let mac: String
    let subnetMask: String
    let hardwareUUID: UUID
    let processor: String
    let diskBytes: UInt64?

    var fields: [(String, String)] {
        let values = [
            ("AgentVersion", version), ("ComputerName", name), ("DeviceName", model),
            ("OS", system), ("Ip", ip), ("Mac", mac), ("IeVersion", "NACMac/" + version),
            ("DiskSize", formattedDiskSize), ("GateWay", ""),
            ("DiskId", hardwareUUID.uuidString), ("CPU", processor), ("Mark", subnetMask),
            // Only the interface used to reach the authentication server is in report scope.
            ("AllIp", ip), ("AllMark", subnetMask), ("AllMac", mac)
        ]
        let elements = values.map { name, value in "<\(name)>\(Self.xmlText(value))</\(name)>" }.joined()
        let xml = "<?xml version=\"1.0\" encoding=\"gb2312\"?><MSAC>" + elements + "</MSAC>"
        return [("gettype", "control"), ("dev_xml", WebBase64.encode(xml)), ("newMobile", "1"),
                ("is_guest", "0"), ("wechatid", "0"), ("is_mobile", "0"), ("os_platform", "macOS")]
    }

    var formattedDiskSize: String {
        guard let diskBytes else { return "" }
        if diskBytes < 10 { return "0 B" }
        if diskBytes < 1 << 10 { return "< 1 KB" }
        let locale = Locale(identifier: "en_US_POSIX")
        if diskBytes < 1 << 20 {
            return String(format: "%.1f KB", locale: locale, Double(diskBytes) / 1024)
        }
        if diskBytes < 1 << 30 {
            return String(format: "%.1f MB", locale: locale, Double(diskBytes) / 1_048_576)
        }
        return String(format: "%.1f GB", locale: locale, Double(diskBytes) / 1_073_741_824)
    }

    static func xmlText(_ text: String) -> String {
        var escaped = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 38: escaped += "&amp;"
            case 60: escaped += "&lt;"
            case 62: escaped += "&gt;"
            case 32...126: escaped.unicodeScalars.append(scalar)
            case 9, 10, 13, 0x80...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
                escaped += "&#\(scalar.value);"
            default: continue
            }
        }
        return escaped
    }
}
