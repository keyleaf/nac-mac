import Foundation
import Security

final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
protocol NACClient: AnyObject {
    var origin: URL { get }
    var device: NACService.Device? { get }
    var heartbeatPort: UInt16? { get }
    func prepare() async throws -> NACService.Device
    func status() async throws -> String
    func login(account: String, password: String, verificationCode: String) async throws -> NACService.LoginResult
    func refreshAfterRoleChange() async throws -> String
}

@MainActor
final class NACService: NACClient {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    typealias Device = DeviceRecord
    struct LoginResult {
        let message: String
        let requiresFurtherAction: Bool
    }
    let origin: URL
    private let session: URLSession
    private var loginKey: SecKey?
    private var token: String?
    private(set) var device: Device?
    private(set) var heartbeatPort: UInt16?

    init(server: String) throws {
        guard let url = URL(string: server), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(parts.scheme ?? ""), parts.host != nil,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { throw Failure(message: "请填写完整服务器地址，例如 http://192.0.2.10") }
        origin = url
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }

    private func context() -> AuthenticationRequest.Context {
        let serial = session.configuration.httpCookieStorage?.cookies(for: origin)?.first { $0.name == "Serial_Num" }?.value ?? "123"
        return .init(origin: origin, osType: "mac", headerOSType: "mac", language: "zh",
            cacheMilliseconds: Int64(Date().timeIntervalSince1970 * 1000), serialNumber: serial, webToken: token)
    }
    private func fetch(_ request: URLRequest, secrets: [String] = []) async throws -> [String: Any] {
        let rawStage = request.url?.path.components(separatedBy: "/json/").last ?? ""
        let stageName = ["auth/config", "auth/index", "device/infoprocess", "device/netStatus"].contains(rawStage) ? rawStage : "configuration"
        let started = ContinuousClock.now
        var logFields: [DiagnosticLog.Field: String] = [.stage: stageName]
        DiagnosticLog.shared.record(.requestStarted, logFields)
        defer {
            let duration = started.duration(to: .now).components
            logFields[.elapsed] = String(Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
            DiagnosticLog.shared.record(.requestFinished, logFields)
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError {
            logFields[.errorCode] = String(error.code.rawValue)
            throw Failure(message: "\(RequestFailureSummary.stage(request))：网络请求失败（URLError \(error.code.rawValue)）")
        }
        let stage = RequestFailureSummary.stage(request)
        guard data.count <= 2_000_000, let http = response as? HTTPURLResponse else { throw Failure(message: "\(stage)：响应超限或格式异常") }
        logFields[.httpStatus] = String(http.statusCode)
        let json: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure(message: "invalid JSON") }
            json = object
        } catch { throw Failure(message: "\(stage)：服务器未返回有效 JSON（HTTP \(http.statusCode)）") }
        if let code = json["errcode"] { logFields[.serverCode] = Self.scalar(code) }
        if request.url?.path.hasPrefix("/access/") == true && json["errcode"] == nil {
            throw Failure(message: "\(stage)：响应缺少结果码（HTTP \(http.statusCode)）")
        }
        if let code = json["errcode"], Self.scalar(code) != "0" {
            throw Failure(message: RequestFailureSummary.describe(request: request, httpStatus: http.statusCode,
                code: Self.scalar(code), serverMessage: json["errmsg"] as? String, secrets: secrets + [token ?? ""]))
        }
        guard (200...299).contains(http.statusCode) else { throw Failure(message: "\(stage)：HTTP \(http.statusCode)") }
        return json
    }
    private func post(_ route: String, _ fields: [(String, String)]) async throws -> [String: Any] {
        try await fetch(AuthenticationRequest.prepare(route: route, parameters: fields, context: context()))
    }
    static func scalar(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }
    private static func enabled(_ value: Any?) -> Bool {
        let value = scalar(value).lowercased()
        return !value.isEmpty && value != "0" && value != "false" && value != "close"
    }

    func prepare() async throws -> Device {
        token = nil
        device = nil
        loginKey = nil
        try await reloadConfiguration()
        let result = try await post("device/infoprocess", [("gettype", "ipgetmac"), ("newMobile", "1"),
            ("is_guest", "0"), ("wechatid", "0"), ("is_mobile", "0"), ("os_platform", "macOS")])
        guard let fields = result["data"] as? [String: Any] else { throw Failure(message: "服务器未返回现有设备记录") }
        let found = Device(fields: fields)
        guard !found.id.isEmpty, found.id != "0" else { throw Failure(message: "当前 IP 没有可复用的设备记录；未提交新登记") }
        device = found
        return found
    }

    // Refresh without resetting the authenticated token or reused device identity.
    private func reloadConfiguration() async throws {
        var request = URLRequest(url: origin.appendingPathComponent("download/android/serviceinfoconfig.ini"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let configuration = try await fetch(request)
        guard let encoded = configuration["ServerInfoConfig"] as? String,
              let server = try JSONSerialization.jsonObject(with: WebBase64.decode(encoded)) as? [String: Any],
              let pem = server["pubKey"] as? String else { throw Failure(message: "认证配置中缺少登录公钥") }
        let refreshedKey = try RSAPublicKey.parsePEM(pem)
        let ztp = configuration["ZtpConfig"] as? [String: Any] ?? [:]
        let controller = Self.scalar(ztp["ControllerAddrIn"])
        let refreshedPort = controller == origin.host ? UInt16(Self.scalar(ztp["ControllerPortIn"])) : nil
        loginKey = refreshedKey
        heartbeatPort = refreshedPort
    }

    func refreshAfterRoleChange() async throws -> String {
        let previousPort = heartbeatPort
        try await reloadConfiguration()
        guard heartbeatPort == previousPort, heartbeatPort != nil else {
            throw Failure(message: "服务器心跳端点配置已变更，请停止心跳并重新检查服务器")
        }
        return try await status()
    }

    func status() async throws -> String {
        guard let device else { throw Failure(message: "请先检查现有设备记录") }
        let result = try await post("device/netStatus", [("deviceId", device.id)])
        guard let data = result["data"] as? [String: Any] else { throw Failure(message: "服务器未返回设备状态") }
        switch Self.scalar(data["deviceStatus"]) {
        case "1": return "设备在线（复用记录）"
        case "0": return "设备未入网"
        default: return "服务器状态待确认"
        }
    }

    func login(account: String, password: String, verificationCode: String) async throws -> LoginResult {
        guard let device, let loginKey else { throw Failure(message: "请先检查服务器与设备记录") }
        // Never retry login automatically: one click means one credential submission.
        let secrets = [account, password, WebBase64.encode(account), WebBase64.encode(password)]
        if try await accountRequiresPasswordChange(account) {
            throw Failure(message: "服务器要求先修改密码，请使用原客户端处理")
        }
        let options = LoginPreparation.Options(hintOver: "0", autoAuth: "0", verificationCode: verificationCode,
            isRecord: "0", isMobile: "0")
        let result = try await fetch(LoginPreparation.loginRequest(account: account, password: password,
            deviceID: device.id, publicKey: loginKey, options: options, context: context()), secrets: secrets)
        guard let data = result["data"] as? [String: Any] else { throw Failure(message: "认证响应缺少结果，不能确认登录完成") }
        token = Self.scalar(data["Token"])
        if Self.scalar(data["pwdCheckResCode"]) == "0" {
            return .init(message: "服务器要求修改密码，请使用原客户端处理，尚未完成入网。", requiresFurtherAction: true)
        }
        if Self.enabled(data["FactorAuth"]) || Self.enabled(data["BindAuth"]) || Self.enabled(data["IsAgainReg"]) {
            return .init(message: "服务器要求额外认证、账号绑定或重新登记。请使用原客户端完成，尚未确认入网。", requiresFurtherAction: true)
        }
        let registration = DeviceRegistrationState.parse(
            response: data["Registered"].map { Self.scalar($0) }, recorded: device.registered)
        switch registration {
        case .awaitingApproval:
            return .init(message: "设备登记仍在等待审核；尚未建立连接。", requiresFurtherAction: true)
        case .registrationRequired:
            return .init(message: "服务器要求完成设备注册或重新登记；请使用原客户端处理。", requiresFurtherAction: true)
        case .unknown:
            return .init(message: "设备登记状态待确认；请重新检查服务器。", requiresFurtherAction: true)
        case .registered: break
        }
        if Self.scalar(data["IPIsInException"]) != "1" || Self.enabled(data["isvpn"]) {
            return .init(message: "登录后的 SPA / VPN 交接尚未接通，不能确认本应用已完成入网。", requiresFurtherAction: true)
        }
        return .init(message: "", requiresFurtherAction: false)
    }

    func accountRequiresPasswordChange(_ account: String) async throws -> Bool {
        let flag = try await fetch(LoginPreparation.configurationRequest(account: account, context: context()),
            secrets: [account, WebBase64.encode(account)])
        guard let data = flag["data"] as? [String: Any] else {
            throw Failure(message: "检查账号策略（auth/config）：服务器缺少策略数据，尚未提交密码")
        }
        return Self.enabled(data["isMustChangePasswrod"])
    }
}
