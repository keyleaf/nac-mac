import Foundation
import Security

enum PasswordEncryption {
    enum Failure: Error { case unsupportedKey, encryptionFailed }

    /// Server-provided RSA key. No Base64-plaintext fallback is permitted.
    /// Non-BMP compatibility with the bundled JavaScript still needs validation.
    static func encrypt(_ password: String, publicKey: SecKey) throws -> String {
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, .rsaEncryptionPKCS1) else {
            throw Failure.unsupportedKey
        }
        var error: Unmanaged<CFError>?
        guard let ciphertext = SecKeyCreateEncryptedData(
            publicKey, .rsaEncryptionPKCS1, Data(password.utf8) as CFData, &error
        ) else {
            if let error { throw error.takeRetainedValue() }
            throw Failure.encryptionFailed
        }
        return (ciphertext as Data).base64EncodedString()
    }
}
