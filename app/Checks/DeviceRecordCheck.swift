import Foundation

@main
struct DeviceRecordCheck {
    static func main() {
        let record = DeviceRecord(fields: [
            "DeviceID": "synthetic-device", "OSName": "ios", "Registered": 1,
            "ComputerName": "  Demo Mac  ", "DevName": "fallback", "IP": "192.0.2.10",
            "Mac": "00:00:5e:00:53:01", "AllDepartName": "示例部门", "Location": "示例位置",
            "Token": "synthetic-secret", "Tel": "synthetic-contact", "Hard": "synthetic-hardware"
        ])
        precondition(record.id == "synthetic-device" && record.name == "Demo Mac")
        precondition(record.recordedOS == "ios" && record.registrationDescription == "已登记")
        precondition(record.ip == "192.0.2.10" && record.department == "示例部门" && record.location == "示例位置")
        precondition(DeviceRecord(fields: ["DevName": "fallback", "ComputerName": " "]).name == "fallback")
        let empty = DeviceRecord(fields: ["DeviceID": ["unexpected": true], "Registered": NSNull()])
        precondition(empty.id.isEmpty && empty.name.isEmpty && empty.registrationDescription == "待确认")
        precondition(DeviceRecord(fields: ["Registered": "0"]).registrationDescription == "等待审核")
        precondition(DeviceRecord(fields: ["Registered": "-1"]).registrationDescription == "需要重新登记")
        precondition(DeviceRecord(fields: ["Registered": "-2"]).registrationDescription == "未登记")
        let fields = Set(Mirror(reflecting: record).children.compactMap(\.label))
        precondition(fields == Set(["id", "recordedOS", "registered", "name", "ip", "mac", "department", "location"]))
        print("PASS: whitelisted device metadata, display-name fallback, registration labels and missing/invalid fields")
    }
}
