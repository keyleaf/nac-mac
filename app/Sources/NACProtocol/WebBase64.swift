import Foundation

/// HTTP helper alphabet from global.Base64Encode, distinct from SPA bridge fields.
enum WebBase64 {
    enum Failure: Error { case invalidEncoding }
    static func encode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: ",")
            .replacingOccurrences(of: "=", with: ":")
            .replacingOccurrences(of: "/", with: ".")
    }
    static func decode(_ value: String) throws -> Data {
        let base64 = value.replacingOccurrences(of: ",", with: "+")
            .replacingOccurrences(of: ":", with: "=")
            .replacingOccurrences(of: ".", with: "/")
        guard let data = Data(base64Encoded: base64),
              data.base64EncodedString() == base64 else { throw Failure.invalidEncoding }
        return data
    }
}
