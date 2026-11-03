import Foundation
import Security
@main
struct PasswordEncryptionCheck {
    static func main() throws {
        // Ephemeral generated key; no user credentials or Keychain writes.
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                       kSecAttrKeySizeInBits as String: 2048]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else { fatalError("key generation failed") }
        for text in ["synthetic-password", "测试密码"] {
            let first = try PasswordEncryption.encrypt(text, publicKey: publicKey)
            let second = try PasswordEncryption.encrypt(text, publicKey: publicKey)
            precondition(first != second, "PKCS1 encryption requires randomized padding")
            let plain = SecKeyCreateDecryptedData(privateKey, .rsaEncryptionPKCS1,
                Data(base64Encoded: first)! as CFData, &error)! as Data
            precondition(String(data: plain, encoding: .utf8) == text)
        }
        do {
            _ = try PasswordEncryption.encrypt(String(repeating: "x", count: 246), publicKey: publicKey)
            preconditionFailure("oversized plaintext must fail")
        } catch {}
        print("PASS: RSA roundtrip, randomized padding, oversized input rejection")
    }
}
