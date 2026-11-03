import Foundation

/// Static web-to-native bridge serialization, not the encrypted SPA packet format.
/// Inputs must come from the caller; this module does not discover or invent device identity.
enum SPABridgeFields {
    static func authentication(_ fields: [String]) -> String {
        fields.map {
            Data($0.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "_")
                .replacingOccurrences(of: "=", with: "-")
                .replacingOccurrences(of: "/", with: ".")
        }.joined(separator: "|")
    }

    static func device(ip: String, mac: String, hardwareID: String) -> String {
        let encoded = [ip, mac, hardwareID].map { Data($0.utf8).base64EncodedString() }
        return encoded.joined(separator: "|") + "||MQ=="
    }
}
