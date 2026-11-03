import Foundation

/// Recovered plaintext layout only. No device discovery, randomness or network side effects.
enum SPAContent {
    enum Failure: Error { case invalidPrefix, invalidField, invalidPort }
    enum Transport: String { case tcp, udp }
    struct Port {
        let transport: Transport
        let number: Int
    }

    static func encode(prefix: String, mode: String, authentication: String,
                       device: String, unixSeconds: Int64, ports: [Port],
                       version: String = "3.0.0", field98: String = "1") throws -> Data {
        guard prefix.utf8.count == 16,
              prefix.utf8.allSatisfy({ (48...57).contains($0) }) else { throw Failure.invalidPrefix }
        let fields = [mode, authentication, device, version, field98]
        guard unixSeconds >= 0, !mode.isEmpty,
              fields.allSatisfy({ !$0.contains(":") && !$0.contains("\0") }) else { throw Failure.invalidField }
        guard !ports.isEmpty, ports.allSatisfy({ (1...65535).contains($0.number) }) else {
            throw Failure.invalidPort
        }
        let declaration = "0.0.0.0" + ports.map { ",\($0.transport.rawValue)/\($0.number)" }.joined()
        let encodedPorts = Data(declaration.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return Data([prefix, mode, authentication, device, String(unixSeconds), version, field98, encodedPorts]
            .joined(separator: ":").utf8)
    }
}
