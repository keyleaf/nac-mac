import Foundation
import Combine

enum ConnectionState: Equatable {
    case notLoggedIn, checking, authenticating, needsAction, connecting, connected, stopped, interrupted
    var title: String {
        switch self {
        case .notLoggedIn: return "未登录"
        case .checking: return "检查中"
        case .authenticating: return "认证中"
        case .needsAction: return "待完成认证"
        case .connecting: return "正在连接"
        case .connected: return "连接正常"
        case .stopped: return "已停止保活"
        case .interrupted: return "连接中断"
        }
    }
}

@MainActor
final class PreviewModel: ObservableObject {
    @Published var account = ""
    @Published var password = ""
    @Published var server = "" {
        didSet { if server != oldValue { invalidate() } }
    }
    @Published var showSettings = false
    @Published var confirmLogin = false
    @Published var isBusy = false
    @Published var ready = false
    @Published var verificationCode = ""
    @Published private(set) var connectionState: ConnectionState = .notLoggedIn
    var status: String { connectionState.title }
    @Published private(set) var authenticationAccepted = false
    var canStartHeartbeat: Bool { ready && authenticationAccepted && !isBusy && !heartbeating }
    var connectionHint: String {
        switch connectionState {
        case .notLoggedIn: return ready ? "检查完成，可以登录" : "请先检查服务器并登录"
        case .checking: return "正在读取配置和设备记录"
        case .authenticating: return "正在验证账号"
        case .needsAction: return "请查看下方认证结果"
        case .connecting: return "账号已受理，等待首次心跳应答"
        case .connected: return "本应用心跳已应答"
        case .stopped: return "可手动重新连接"
        case .interrupted: return "保活已停止，请查看连接诊断"
        }
    }
    @Published var authenticationStatus = "未提交"
    @Published var deviceStatus = "未查询"
    @Published var detail = "先检查服务器，将复用当前 IP 的设备记录，不提交新登记。"
    @Published var confirmHeartbeat = false
    @Published var heartbeating = false
    @Published var heartbeatStatus = "连续心跳未开启"
    @Published var monitoring = false
    @Published var lastStatusCheck = "尚未检查"
    private var monitorTask: Task<Void, Never>?
    private let heartbeat = HeartbeatProbe()
    private var heartbeatTask: Task<Void, Never>?
    private var heartbeatGeneration = UUID()
    private var roleRefreshTask: Task<Void, Never>?
    @Published var roleChangeStatus = ""
    private var service: (any NACClient)?
    private let preferences: UserDefaults
    private let makeHeartbeat: @MainActor () -> any ContinuousHeartbeatSession
    private var loginTask: Task<Void, Never>?
    private var loginGeneration = UUID()
    private var loggingIn = false
    private let makeClient: @MainActor (String) throws -> any NACClient
    private var checkTask: Task<Void, Never>?
    private var checkGeneration = UUID()
    @Published var checkingServer = false

    init(preferences: UserDefaults = .standard,
         makeClient: @escaping @MainActor (String) throws -> any NACClient = { try NACService(server: $0) },
         makeHeartbeat: @escaping @MainActor () -> any ContinuousHeartbeatSession = { HeartbeatProbe() }) {
        self.preferences = preferences
        self.makeClient = makeClient
        self.makeHeartbeat = makeHeartbeat
        self.server = preferences.string(forKey: "serverOrigin") ?? ""
    }

    private func resetLogin() {
        loginGeneration = UUID()
        loginTask?.cancel()
        loginTask = nil
        if loggingIn { isBusy = false }
        loggingIn = false
        authenticationAccepted = false
    }

    private func resetCheck() {
        checkGeneration = UUID()
        checkTask?.cancel()
        checkTask = nil
        if checkingServer { isBusy = false }
        checkingServer = false
    }

    func cancelServerCheck() {
        guard checkingServer else { return }
        resetCheck()
        ready = false
        service = nil
        deviceStatus = "未查询"
        connectionState = .notLoggedIn
        detail = "可调整服务器地址后重试。"
    }

    func invalidate() {
        resetLogin()
        resetCheck()
        stopHeartbeat()
        stopMonitoring()
        service = nil
        ready = false
        password = ""
        connectionState = .notLoggedIn
        authenticationStatus = "未提交"
        deviceStatus = "未查询"
        detail = "服务器已更改，请重新检查。"
    }
    func checkServer() {
        guard !isBusy else { return }
        let address = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            showSettings = true
            connectionState = .notLoggedIn
            detail = "先填写公司的认证服务器地址，再检查设备记录。"
            return
        }
        resetLogin()
        stopHeartbeat()
        stopMonitoring()
        resetCheck()
        service = nil
        isBusy = true
        checkingServer = true
        ready = false
        deviceStatus = "查询中"
        connectionState = .checking
        detail = "正在读取服务器配置和当前 IP 对应的设备记录…"
        authenticationStatus = "未提交"
        let generation = checkGeneration
        checkTask = Task {
            defer {
                if checkGeneration == generation {
                    isBusy = false
                    checkingServer = false
                    checkTask = nil
                }
            }
            do {
                let client = try makeClient(address)
                // Only the validated server address is persisted; no credentials or device identity.
                preferences.set(client.origin.absoluteString, forKey: "serverOrigin")
                let device = try await client.prepare()
                guard !Task.isCancelled, checkGeneration == generation else { return }
                service = client
                ready = true
                connectionState = .notLoggedIn
                detail = "复用现有记录（系统：\(device.recordedOS)，登记状态：\(device.registered)）。未修改服务器登记信息。"
                do {
                    let state = try await client.status()
                    guard !Task.isCancelled, checkGeneration == generation else { return }
                    deviceStatus = state
                    recordCheck()
                } catch {
                    guard !Task.isCancelled, checkGeneration == generation else { return }
                    deviceStatus = "状态查询失败，可重试"
                }
            } catch {
                guard !Task.isCancelled, checkGeneration == generation else { return }
                ready = false
                service = nil
                deviceStatus = "未取得设备记录"
                connectionState = .notLoggedIn
                fail(error)
            }
        }
    }
    func refreshStatus() {
        guard let service, !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do { deviceStatus = try await service.status(); recordCheck() }
            catch { fail(error) }
        }
    }
    private func recordCheck() {
        lastStatusCheck = Date().formatted(date: .omitted, time: .standard)
    }
    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        monitoring = false
    }
    func toggleMonitoring() {
        if monitoring { stopMonitoring(); return }
        guard let client = service, ready, !isBusy else { return }
        monitoring = true
        monitorTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, !Task.isCancelled, self.service === client else { return }
                if self.isBusy { continue }
                do {
                    let state = try await client.status()
                    guard !Task.isCancelled, self.service === client else { return }
                    failures = 0
                    self.deviceStatus = state
                    self.recordCheck()
                } catch {
                    guard !Task.isCancelled, self.service === client else { return }
                    failures += 1
                    self.deviceStatus = "状态未知（失败 \(failures) 次）"
                    self.recordCheck()
                }
            }
        }
    }
    func probeHeartbeat() {
        guard !heartbeating else { return }
        guard let service, let device = service.device, let host = service.origin.host,
              let port = service.heartbeatPort, port == 37527, ready, !isBusy else {
            detail = "尚未确认可用的心跳端点，请先检查服务器。"
            return
        }
        stopMonitoring()
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let reply = try await heartbeat.run(host: host, port: port, deviceID: device.id)
                detail = "已验证 \(reply.trade) XML 和响应序列号（\(reply.payloadBytes) 字节）。原版心跳不要求额外结果码；独立运行仍待验证。"
            } catch {
                detail = (error as? HeartbeatProbe.Failure)?.message ?? "心跳验证已取消或失败。"
            }
        }
    }
    func stopHeartbeat() {
        heartbeatGeneration = UUID()
        roleRefreshTask?.cancel()
        roleRefreshTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        heartbeating = false
        heartbeatStatus = "连续心跳已停止"
        connectionState = authenticationAccepted ? .stopped : .notLoggedIn
        if authenticationAccepted { detail = "本应用的心跳连接已停止，可重新连接。" }
    }
    func startHeartbeat() {
        guard canStartHeartbeat, let service else { return }
        guard let device = service.device, let host = service.origin.host,
              let port = service.heartbeatPort, port == 37527 else {
            connectionState = .interrupted
            heartbeatStatus = "未取得已验证的心跳端点，请重新检查服务器。"
            detail = heartbeatStatus
            return
        }
        stopMonitoring()
        heartbeating = true
        let generation = UUID()
        heartbeatGeneration = generation
        let connection = makeHeartbeat()
        roleChangeStatus = ""
        connectionState = .connecting
        heartbeatStatus = "正在连接，等待首次心跳应答…"
        detail = "账号认证已受理，正在建立心跳连接。"
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await connection.runContinuously(host: host, port: port, deviceID: device.id,
                    onAcknowledgement: { [weak self] count in
                        guard let self, self.heartbeatGeneration == generation, count > 0 else { return }
                        self.connectionState = .connected
                        self.heartbeatStatus = "心跳已应答 \(count) 次 · \(Date().formatted(date: .omitted, time: .standard))"
                        if count == 1 { self.detail = "账号认证已受理，心跳连接已建立。" }
                    }, onRoleChanged: { [weak self] in
                        self?.refreshRole(service: service, generation: generation)
                    })
                guard self.heartbeatGeneration == generation else { return }
                self.connectionState = .interrupted
                self.heartbeatStatus = "心跳会话已结束，请重新连接。"
                self.detail = self.heartbeatStatus
            } catch is CancellationError {
                guard self.heartbeatGeneration == generation else { return }
                self.connectionState = .stopped
                self.heartbeatStatus = "连续心跳已停止"
                self.detail = "心跳连接已取消，可重新连接。"
            } catch {
                guard self.heartbeatGeneration == generation else { return }
                self.connectionState = .interrupted
                self.heartbeatStatus = (error as? HeartbeatProbe.Failure)?.message ?? "心跳异常，已停止"
                self.detail = "账号认证已受理，但心跳连接已中断；可查看连接诊断或重新连接。"
            }
            guard self.heartbeatGeneration == generation else { return }
            self.heartbeating = false
            self.roleRefreshTask?.cancel()
            self.roleRefreshTask = nil
        }
    }
    private func refreshRole(service: any NACClient, generation: UUID) {
        guard heartbeatGeneration == generation else { return }
        roleChangeStatus = "收到角色变更；策略处理待接通，请保留原客户端。"
        guard roleRefreshTask == nil else { return }
        roleRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.heartbeatGeneration == generation { self.roleRefreshTask = nil } }
            do {
                let refreshed = try await service.refreshAfterRoleChange()
                guard self.heartbeatGeneration == generation, self.service === service else { return }
                self.deviceStatus = refreshed
                self.recordCheck()
                self.roleChangeStatus = "角色变更：配置与状态已刷新；策略处理待接通，请保留原客户端。"
            } catch {
                guard self.heartbeatGeneration == generation else { return }
                self.roleChangeStatus = "角色变更后刷新失败：\(error.localizedDescription)；请保留原客户端。"
                self.stopHeartbeat()
                self.connectionState = .interrupted
                self.heartbeatStatus = "角色变更后刷新失败，心跳已停止。"
                self.detail = self.heartbeatStatus
            }
        }
    }
    func submitLogin() {
        guard let client = service, ready, !isBusy,
              !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else { return }
        resetLogin()
        stopHeartbeat()
        stopMonitoring()
        let submittedPassword = password
        password = ""
        let submittedAccount = account
        let code = verificationCode
        isBusy = true
        loggingIn = true
        connectionState = .authenticating
        authenticationStatus = "认证中"
        detail = "正在验证账号，完成后将自动建立心跳连接。"
        let generation = loginGeneration
        loginTask = Task {
            defer {
                if loginGeneration == generation {
                    isBusy = false
                    loggingIn = false
                    loginTask = nil
                }
            }
            do {
                let result = try await client.login(account: submittedAccount, password: submittedPassword, verificationCode: code)
                guard !Task.isCancelled, loginGeneration == generation, service === client else { return }
                authenticationStatus = result.requiresFurtherAction ? "受理，待后续" : "已受理"
                detail = result.message
                isBusy = false
                if result.requiresFurtherAction {
                    connectionState = .needsAction
                } else {
                    authenticationAccepted = true
                    startHeartbeat()
                }
                do {
                    let state = try await client.status()
                    guard !Task.isCancelled, loginGeneration == generation, service === client else { return }
                    deviceStatus = state
                    recordCheck()
                } catch {
                    guard !Task.isCancelled, loginGeneration == generation, service === client else { return }
                    deviceStatus = "认证后状态待确认"
                }
            } catch {
                guard !Task.isCancelled, loginGeneration == generation, service === client else { return }
                connectionState = .notLoggedIn
                authenticationStatus = "未完成"
                fail(error)
            }
        }
    }
    private func fail(_ error: Error) {
        if let error = error as? NACService.Failure { detail = error.message }
        else if error is LoginPreparation.Failure { detail = "输入为空，或密码含尚未验证兼容性的非 BMP 字符。未完成认证。" }
        else { detail = "请求、配置解析或加密失败。请确认公司内网和服务器地址后重试。" }
    }
}
