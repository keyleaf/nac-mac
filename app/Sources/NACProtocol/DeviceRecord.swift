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
