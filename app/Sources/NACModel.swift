import Foundation
import Combine

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
    @Published var status = "尚未检查"
    @Published var authenticationStatus = "未提交"
    @Published var deviceStatus = "未查询"
    @Published var detail = "先检查服务器，将复用当前 IP 的设备记录，不提交新登记。"
    @Published var confirmHeartbeat = false
    @Published var confirmContinuousHeartbeat = false
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
    private let makeClient: @MainActor (String) throws -> any NACClient
    private var checkTask: Task<Void, Never>?
    private var checkGeneration = UUID()
    @Published var checkingServer = false

    init(preferences: UserDefaults = .standard,
         makeClient: @escaping @MainActor (String) throws -> any NACClient = { try NACService(server: $0) }) {
        self.preferences = preferences
        self.makeClient = makeClient
        self.server = preferences.string(forKey: "serverOrigin") ?? ""
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
        status = "检查已取消"
        detail = "可调整服务器地址后重试。"
    }

    func invalidate() {
        resetCheck()
        stopHeartbeat()
        stopMonitoring()
        service = nil
        ready = false
        password = ""
        status = "尚未检查"
        authenticationStatus = "未提交"
        deviceStatus = "未查询"
        detail = "服务器已更改，请重新检查。"
    }
    func checkServer() {
        guard !isBusy else { return }
        let address = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            showSettings = true
            status = "请设置服务器"
            detail = "先填写公司的认证服务器地址，再检查设备记录。"
            return
        }
        stopHeartbeat()
        stopMonitoring()
        resetCheck()
        service = nil
        isBusy = true
        checkingServer = true
        ready = false
        deviceStatus = "查询中"
        status = "检查中"
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
                status = "可以测试账号认证"
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
    }
    func startHeartbeat() {
        guard !heartbeating, ready, !isBusy, let service, let device = service.device,
              let host = service.origin.host, let port = service.heartbeatPort, port == 37527 else { return }
        heartbeating = true
        let generation = UUID()
        heartbeatGeneration = generation
        let connection = HeartbeatProbe()
        roleChangeStatus = ""
        heartbeatStatus = "建立心跳连接，独立运行待验证"
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await connection.run(host: host, port: port, deviceID: device.id,
                    maximumHeartbeats: nil, onAcknowledgement: { [weak self] count in
                        guard self?.heartbeatGeneration == generation else { return }
                        self?.heartbeatStatus = "心跳已应答 \(count) 次 · \(Date().formatted(date: .omitted, time: .standard))"
                    }, onRoleChanged: { [weak self] in
                        self?.refreshRole(service: service, generation: generation)
                    })
            } catch is CancellationError {
                guard self.heartbeatGeneration == generation else { return }
                self.heartbeatStatus = "连续心跳已停止"
            } catch {
                guard self.heartbeatGeneration == generation else { return }
                self.heartbeatStatus = (error as? HeartbeatProbe.Failure)?.message ?? "心跳异常，已停止"
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
            }
        }
    }
    func submitLogin() {
        guard let service, ready, !isBusy else { return }
        let submittedPassword = password
        password = ""
        let submittedAccount = account
        let code = verificationCode
        isBusy = true
        status = "正在认证"
        authenticationStatus = "认证中"
        Task {
            defer { isBusy = false }
            do {
                let result = try await service.login(account: submittedAccount, password: submittedPassword, verificationCode: code)
                status = result.requiresFurtherAction ? "认证后仍需后续步骤" : "账号认证已受理"
                authenticationStatus = result.requiresFurtherAction ? "受理，待后续" : "已受理"
                detail = result.message
                do { deviceStatus = try await service.status(); recordCheck() }
                catch { deviceStatus = "认证后状态待确认" }
            } catch { authenticationStatus = "未完成"; fail(error) }
        }
    }
    private func fail(_ error: Error) {
        status = "操作未完成"
        if let error = error as? NACService.Failure { detail = error.message }
        else if error is LoginPreparation.Failure { detail = "输入为空，或密码含尚未验证兼容性的非 BMP 字符。未完成认证。" }
        else { detail = "请求、配置解析或加密失败。请确认公司内网和服务器地址后重试。" }
    }
}

