import Foundation

/// Only the device metadata needed by the UI is retained; no response tokens or personal contact fields.
struct DeviceRecord {
    let id: String
    let recordedOS: String
    let registered: String
    var name = ""
    var ip = ""
    var mac = ""
    var department = ""
    var location = ""

    init(id: String, recordedOS: String, registered: String) {
        self.id = id
        self.recordedOS = recordedOS
        self.registered = registered
    }

    init(fields: [String: Any]) {
        func value(_ key: String) -> String {
            if let text = fields[key] as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let number = fields[key] as? NSNumber { return number.stringValue }
            return ""
        }
        id = value("DeviceID")
        recordedOS = value("OSName")
        registered = value("Registered")
        let computerName = value("ComputerName")
        name = computerName.isEmpty ? value("DevName") : computerName
        ip = value("IP")
        mac = value("Mac")
        department = value("AllDepartName")
        location = value("Location")
    }

    func matchesMac(_ hardwareAddress: String) -> Bool {
        let system = recordedOS.lowercased()
        guard ["mac", "macos", "mac os", "mac os x", "osx"].contains(where: {
            system == $0 || system.hasPrefix($0 + " ")
        }) else { return false }

        func normalized(_ address: String) -> String {
            address.lowercased().filter { !":-.".contains($0) }
        }
        let recorded = normalized(mac)
        return recorded.count == 12 && recorded.allSatisfy { "0123456789abcdef".contains($0) }
            && recorded == normalized(hardwareAddress)
    }

    var registrationDescription: String {
        switch registered {
        case "1": return "已登记"
        case "0": return "等待审核"
        case "-1": return "需要重新登记"
        case "-2": return "未登记"
        default: return "待确认"
        }
    }
}
