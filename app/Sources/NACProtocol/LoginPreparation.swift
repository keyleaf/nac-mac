import Foundation
import Security

enum LoginPreparation {
    enum Failure: Error { case missingIdentity, unsupportedPasswordCharacters }
    struct Options {
        var idp: String = ""
        var tokenID: String = ""
        var remoteIP: String = ""
        let hintOver: String
        let autoAuth: String
        let verificationCode: String
        let isRecord: String
        let isMobile: String
        var noAuthCode: String? = nil
    }

    static func configurationRequest(account: String, context: AuthenticationRequest.Context) throws -> URLRequest {
        try AuthenticationRequest.prepare(route: "auth/config",
            parameters: [("username", WebBase64.encode(account))], context: context)
    }

    static func loginRequest(account: String, password: String, deviceID: String, publicKey: SecKey,
                             options: Options, context: AuthenticationRequest.Context) throws -> URLRequest {
        guard !account.isEmpty, !password.isEmpty, !deviceID.isEmpty else { throw Failure.missingIdentity }
        // Bundled JSEncrypt encodes UTF-16 surrogate pairs differently; fail until interoperable.
        guard password.unicodeScalars.allSatisfy({ $0.value <= 0xffff }) else {
            throw Failure.unsupportedPasswordCharacters
        }
        let encrypted = try PasswordEncryption.encrypt(password, publicKey: publicKey)
        var fields: [(String, String)] = [
            ("type", "User"), ("user_name", WebBase64.encode(account)), ("deviceid", deviceID),
            ("idp", WebBase64.encode(options.idp)), ("tokenId", WebBase64.encode(options.tokenID)),
            ("remoteIp", options.remoteIP), ("password", encrypted), ("hintOver", options.hintOver),
            ("autoAuth", options.autoAuth), ("verify_code", options.verificationCode),
            ("isRecord", options.isRecord), ("callform", "web"), ("is_mobile", options.isMobile)
        ]
        if let value = options.noAuthCode { fields.append(("noAuthCode", value)) }
        return try AuthenticationRequest.prepare(route: "auth/index", parameters: fields, context: context)
    }

    static func authenticationKnock(account: String, password: String, verificationCode: String,
        ip: String, mac: String, hardwareID: String, prefix: String, unixSeconds: Int64,
        ports: [SPAContent.Port], publicKey: SecKey, hmacKey: Data) throws -> Data {
        let auth = SPABridgeFields.authentication(["User", "", account, password, verificationCode])
        let device = SPABridgeFields.device(ip: ip, mac: mac, hardwareID: hardwareID)
        let content = try SPAContent.encode(prefix: prefix, mode: "Auth", authentication: auth,
            device: device, unixSeconds: unixSeconds, ports: ports)
        return try SPAPublicEnvelope.encode(content: content, publicKey: publicKey, hmacKey: hmacKey)
    }
}
