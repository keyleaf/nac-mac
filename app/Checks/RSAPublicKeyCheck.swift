import Foundation
import Security

@main
struct RSAPublicKeyCheck {
    static func tlv(_ tag: UInt8, _ data: Data) -> Data {
        let count = data.count
        let length: [UInt8] = count < 128 ? [UInt8(count)] : count < 256 ? [0x81, UInt8(count)] : [0x82, UInt8(count >> 8), UInt8(count & 255)]
        return Data([tag] + length) + data
    }
    static func pem(_ bytes: Data, _ label: String) -> String {
        "-----BEGIN \(label)-----\n" + bytes.base64EncodedString() + "\n-----END \(label)-----"
    }
    static func main() throws {
        var error: Unmanaged<CFError>?
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        guard let privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let exported = SecKeyCopyExternalRepresentation(publicKey, &error) else {
            if let error { throw error.takeRetainedValue() }; fatalError("key generation failed")
        }
        let pkcs1 = exported as Data
        let algorithm = tlv(0x30, tlv(6, Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,1,1,1])) + Data([5,0]))
        let spki = tlv(0x30, algorithm + tlv(3, Data([0]) + pkcs1))
        for input in [pem(pkcs1, "RSA PUBLIC KEY"), pem(spki, "PUBLIC KEY")] {
            let parsed = try RSAPublicKey.parsePEM(input)
            let message = Data("synthetic roundtrip".utf8)
            let cipher = SecKeyCreateEncryptedData(parsed, .rsaEncryptionPKCS1, message as CFData, &error)!
            let decoded = SecKeyCreateDecryptedData(privateKey, .rsaEncryptionPKCS1, cipher, &error)! as Data
            precondition(decoded == message)
        }
        for invalid in [pem(spki + Data([0]), "PUBLIC KEY"), pem(Data([0x30,0x80]), "PUBLIC KEY"), "not a key"] {
            do { _ = try RSAPublicKey.parsePEM(invalid); preconditionFailure("malformed key accepted") } catch {}
        }
        if CommandLine.arguments.count == 2 {
            let input = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
            let key = try RSAPublicKey.parsePEM(input)
            precondition(SecKeyGetBlockSize(key) > 11)
            print("PASS: supplied public key imported (key material not logged)")
        }
        print("PASS: PKCS1/SPKI key import, encryption roundtrip, malformed DER rejection")
    }
}
