import Foundation

enum HeartbeatMessage {
    static let observedIntervalSeconds = 30
    enum Failure: Error { case invalidIdentifier, invalidClientType }
    static func content(deviceID: String, requestClientType: String) throws -> Data {
        guard !deviceID.isEmpty, deviceID.utf8.count <= 128,
              deviceID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }) else {
            throw Failure.invalidIdentifier
        }
        guard requestClientType == "mobile" else { throw Failure.invalidClientType }
        // Only this source client's mobile-record dialect has been observed.
        let xml = "<?xml version=\"1.0\" encoding=\"gbk\"?><ASM><TradeCode>HeartTest</TradeCode><AgentID>\(deviceID)</AgentID><requestClientType>\(requestClientType)</requestClientType></ASM>"
        return Data(xml.utf8)
    }
    static func frame(deviceID: String, requestClientType: String, serial: UInt32) throws -> Data {
        try ASMFrame.encode(trade: "HeartTest", content: content(deviceID: deviceID, requestClientType: requestClientType), field8: 1, serial: serial)
    }
}
