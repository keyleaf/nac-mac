import Foundation
import CryptoKit

/// Compatibility checksum observed in the bundled web client, not authentication.
/// Accepts ordered scalar strings only. Objects/arrays need separate investigation.
enum RequestSignature {
    enum Failure: Error { case malformedPercentEncoding, emptyURL }

    static func canonical(_ url: String, parameters: [(String, String)]) throws -> String {
        guard !url.isEmpty else { throw Failure.emptyURL }
        var value = url
        for (key, raw) in parameters {
            guard let decoded = raw.removingPercentEncoding else {
                throw Failure.malformedPercentEncoding
            }
            value += (value.contains("?") ? "&" : "?") + key + "=" + decoded
        }
        value = value.replacingOccurrences(of: "^http[s]?://[^/]+", with: "", options: .regularExpression)
        let punctuation = Set("=&()/.?_'\"<>".utf8)
        let bytes = value.utf8.filter { byte in
            (48...57).contains(byte) || (65...90).contains(byte) ||
            (97...122).contains(byte) || punctuation.contains(byte)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func checksum(_ url: String, parameters: [(String, String)]) throws -> String {
        let input = try canonical(url, parameters: parameters)
        return Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
