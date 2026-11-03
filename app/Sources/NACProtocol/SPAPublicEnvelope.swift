import Foundation
import Security
import CryptoKit

/// The observed public-key / SHA-256 branch only. Keys are supplied by the caller.
/// No fallback to symmetric encryption, no key discovery, and no network traffic.
enum SPAPublicEnvelope {
    enum Failure: Error { case invalidInput, unsupportedKey, encryptionFailed, packetTooLarge }

    static func base64WithoutPadding(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    static func encode(content: Data, publicKey: SecKey, hmacKey: Data) throws -> Data {
        guard !content.isEmpty, content.count <= 48_000, !hmacKey.isEmpty else { throw Failure.invalidInput }
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, .rsaEncryptionPKCS1),
              SecKeyGetBlockSize(publicKey) > 11 else { throw Failure.unsupportedKey }
        let digest = Data(SHA256.hash(data: content))
        var plaintext = content
        plaintext.append(Data((":" + base64WithoutPadding(digest)).utf8))
        let chunkSize = SecKeyGetBlockSize(publicKey) - 11
        var encrypted = Data()
        for start in stride(from: 0, to: plaintext.count, by: chunkSize) {
            let end = min(start + chunkSize, plaintext.count)
            var error: Unmanaged<CFError>?
            guard let block = SecKeyCreateEncryptedData(publicKey, .rsaEncryptionPKCS1,
                plaintext.subdata(in: start..<end) as CFData, &error) else {
                if let error { throw error.takeRetainedValue() }
                throw Failure.encryptionFailed
            }
            encrypted.append(block as Data)
        }
        let encodedCiphertext = base64WithoutPadding(encrypted)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(encodedCiphertext.utf8),
            using: SymmetricKey(data: hmacKey))
        var packet = Data([3])
        packet.append(Data((encodedCiphertext + base64WithoutPadding(Data(mac))).utf8))
        guard packet.count <= 65_507 else { throw Failure.packetTooLarge }
        return packet
    }
}
