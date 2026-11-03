import Foundation
import Security
import CryptoKit

@main
struct SPAPublicEnvelopeCheck {
    static func main() throws {
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                   kSecAttrKeySizeInBits as String: 2048]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            if let error { throw error.takeRetainedValue() }
            fatalError("temporary key generation failed")
        }
        let key = Data("synthetic-hmac-key".utf8)
        for length in [1, 201, 202, 245, 246, 1000] {
            let content = Data(repeating: 65, count: length)
            let packet = try SPAPublicEnvelope.encode(content: content, publicKey: publicKey, hmacKey: key)
            precondition(packet.first == 3)
            let encoded = String(decoding: packet.dropFirst(), as: UTF8.self)
            // SHA-256 HMAC occupies exactly 43 Base64 characters without '='.
            let cipherText = String(encoded.dropLast(43))
            let macText = String(encoded.suffix(43))
            let mac = Data(base64Encoded: macText + "=")!
            precondition(HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: Data(cipherText.utf8),
                using: SymmetricKey(data: key)))
            let cipher = Data(base64Encoded: cipherText + String(repeating: "=", count: (4 - cipherText.count % 4) % 4))!
            precondition(cipher.count % 256 == 0)
            var decoded = Data()
            for start in stride(from: 0, to: cipher.count, by: 256) {
                guard let block = SecKeyCreateDecryptedData(privateKey, .rsaEncryptionPKCS1,
                    cipher.subdata(in: start..<(start + 256)) as CFData, &error) else {
                    fatalError("RSA decryption failed")
                }
                decoded.append(block as Data)
            }
            precondition(decoded.prefix(length) == content)
            precondition(decoded[length] == 58)
            let checksum = Data(base64Encoded: String(decoding: decoded.dropFirst(length + 1), as: UTF8.self) + "=")!
            precondition(checksum == Data(SHA256.hash(data: content)))
            let second = try SPAPublicEnvelope.encode(content: content, publicKey: publicKey, hmacKey: key)
            precondition(packet != second, "RSA padding must be randomized")
        }
        do {
            _ = try SPAPublicEnvelope.encode(content: Data(), publicKey: publicKey, hmacKey: key)
            preconditionFailure("empty content accepted")
        } catch SPAPublicEnvelope.Failure.invalidInput {}
        print("PASS: SPA mode byte, RSA chunk boundaries, plaintext digest, HMAC, randomized padding")
    }
}
