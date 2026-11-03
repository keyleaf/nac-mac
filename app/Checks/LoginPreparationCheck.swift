import Foundation
import Security

@main
struct LoginPreparationCheck {
    static func main() throws {
        var error: Unmanaged<CFError>?
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        guard let privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            if let error { throw error.takeRetainedValue() }; fatalError("key generation failed")
        }
        let context = AuthenticationRequest.Context(origin: URL(string: "https://example.invalid")!,
            osType: "mac", headerOSType: "mac", language: "zh", cacheMilliseconds: 123, serialNumber: "123")
        let options = LoginPreparation.Options(hintOver: "0", autoAuth: "0", verificationCode: "",
            isRecord: "0", isMobile: "0")
        let request = try LoginPreparation.loginRequest(account: "synthetic", password: "临时密码",
            deviceID: "synthetic-device", publicKey: publicKey, options: options, context: context)
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        let fields = URLComponents(string: "https://example.invalid/?" + body)!.queryItems!
        let dict = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value ?? "") })
        precondition(dict["noAuthCode"] == nil)
        precondition(dict["is_mobile"] == "0")
        let decodedUser = try WebBase64.decode(dict["user_name"]!)
        precondition(decodedUser == Data("synthetic".utf8))
        let cipher = Data(base64Encoded: dict["password"]!)!
        let plain = SecKeyCreateDecryptedData(privateKey, .rsaEncryptionPKCS1, cipher as CFData, &error)! as Data
        precondition(plain == Data("临时密码".utf8))
        precondition(request.value(forHTTPHeaderField: "Referer") == "https://example.invalid/")
        for bad in ["", "😀"] {
            do {
                _ = try LoginPreparation.loginRequest(account: "synthetic", password: bad,
                    deviceID: "synthetic-device", publicKey: publicKey, options: options, context: context)
                preconditionFailure("unsupported password accepted")
            } catch LoginPreparation.Failure.missingIdentity {} catch LoginPreparation.Failure.unsupportedPasswordCharacters {}
        }
        let packet = try LoginPreparation.authenticationKnock(account: "synthetic", password: "temporary",
            verificationCode: "", ip: "192.0.2.1", mac: "00:00:00:00:00:01", hardwareID: "synthetic-device",
            prefix: "1234567890123456", unixSeconds: 1700000000,
            ports: [.init(transport: .tcp, number: 443)], publicKey: publicKey, hmacKey: Data("synthetic-key".utf8))
        precondition(packet.first == 3)
        print("PASS: login preparation, credential encryption, custom username encoding, Referer, required identity, SPA composition")
    }
}
