import Foundation

@main
struct SPAContentCheck {
    static func main() throws {
        let bytes = try SPAContent.encode(prefix: "1234567890111111", mode: "Token",
            authentication: "synthetic", device: "user", unixSeconds: 1700000000,
            ports: [.init(transport: .tcp, number: 443), .init(transport: .udp, number: 500)])
        let fields = String(decoding: bytes, as: UTF8.self).components(separatedBy: ":")
        precondition(fields.count == 8)
        precondition(fields.prefix(7).joined(separator: ":") == "1234567890111111:Token:synthetic:user:1700000000:3.0.0:1")
        var encoded = fields[7]
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        precondition(Data(base64Encoded: encoded) == Data("0.0.0.0,tcp/443,udp/500".utf8))
        for prefix in ["short", "123456789012345x"] {
            do {
                _ = try SPAContent.encode(prefix: prefix, mode: "Token", authentication: "x",
                    device: "y", unixSeconds: 1, ports: [.init(transport: .tcp, number: 443)])
                preconditionFailure("invalid prefix accepted")
            } catch SPAContent.Failure.invalidPrefix {}
        }
        do {
            _ = try SPAContent.encode(prefix: "1234567890123456", mode: "Token", authentication: "x:y",
                device: "y", unixSeconds: 1, ports: [.init(transport: .tcp, number: 443)])
            preconditionFailure("delimiter injection accepted")
        } catch SPAContent.Failure.invalidField {}
        print("PASS: SPA plaintext layout, port encoding, malformed prefix and delimiter rejection")
    }
}
