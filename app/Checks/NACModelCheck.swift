import Foundation

@MainActor
final class FakeNACClient: NACClient {
    let origin: URL
    var device: NACService.Device?
    var heartbeatPort: UInt16? = 37527
    var pending: CheckedContinuation<NACService.Device, Error>?
    var loginPending: CheckedContinuation<NACService.LoginResult, Error>?
    var loginRequests = 0
    var roleError = false
    var waitForPreparation = true
    var lookupRequests = 0
    var lookupResult: NACService.Device? = .init(id: "synthetic", recordedOS: "macOS", registered: "1")
    var suspendLookup = false
    var lookupPending: CheckedContinuation<NACService.Device?, Never>?
    init(_ server: String) { origin = URL(string: server)! }
    func discoverDesktop() async throws -> DeviceRegistrationState {
        let result = try await withCheckedThrowingContinuation { pending = $0 }
        return .parse(response: nil, recorded: result.registered)
    }
    func prepare() async throws -> NACService.Device {
        let result: NACService.Device
        if waitForPreparation {
            result = try await withCheckedThrowingContinuation { pending = $0 }
        } else {
            guard let current = try await verifyDeviceForReconnect() else {
                throw NACService.Failure(message: "synthetic lookup failed")
            }
            result = current
        }
        device = result
        return result
    }
    func verifyDeviceForReconnect() async throws -> NACService.Device? {
        lookupRequests += 1
        if suspendLookup { return await withCheckedContinuation { lookupPending = $0 } }
        return lookupResult
    }
    func status() async throws -> String { "设备在线（测试）" }
    func login(account: String, password: String, verificationCode: String) async throws -> NACService.LoginResult {
        precondition(account == "synthetic" && password == "synthetic-only")
        loginRequests += 1
        return try await withCheckedThrowingContinuation { loginPending = $0 }
    }
    func refreshAfterRoleChange() async throws -> String {
        if roleError { throw NACService.Failure(message: "synthetic role refresh failed") }
        return try await status()
    }
    func completeLogin(needsAction: Bool = false) {
        let continuation = loginPending; loginPending = nil
        continuation?.resume(returning: .init(message: "synthetic login result", requiresFurtherAction: needsAction))
    }
    func failLogin() {
        let continuation = loginPending; loginPending = nil
        continuation?.resume(throwing: NACService.Failure(message: "synthetic authentication failed"))
    }
    func succeed() { let continuation = pending; pending = nil; continuation?.resume(returning: .init(id: "synthetic", recordedOS: "macOS", registered: "1")) }
    func fail() { let continuation = pending; pending = nil; continuation?.resume(throwing: NACService.Failure(message: "synthetic lookup failed")) }
}

@MainActor
final class FakeHeartbeatSession: ContinuousHeartbeatSession {
    var pending: CheckedContinuation<Void, Error>?
    var acknowledge: ((Int) -> Void)?
    var roleChanged: (() -> Void)?
    func runContinuously(host: String, port: UInt16, deviceID: String,
                         onAcknowledgement: @escaping (Int) -> Void,
                         onRoleChanged: @escaping () -> Void) async throws {
        precondition(host == "192.0.2.20" && port == 37527 && deviceID == "synthetic")
        acknowledge = onAcknowledgement
        roleChanged = onRoleChanged
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func fail(retryable: Bool = false) {
        let continuation = pending; pending = nil
        continuation?.resume(throwing: HeartbeatProbe.Failure(message: "synthetic remote close", allowsReconnect: retryable))
    }
}

@MainActor final class MemoryPasswordStore: PasswordStore {
 var values: [String: String] = [:]
 func read(server: String, account: String) throws -> String? { values[server + "|" + account] }
 func save(_ password: String, server: String, account: String) throws { values[server + "|" + account] = password }
 func remove(server: String, account: String) throws { values.removeValue(forKey: server + "|" + account) }
}

@main
struct NACModelCheck {
    @MainActor static func until(_ condition: () -> Bool) async {
        for _ in 0..<2000 { if condition() { return }; await Task.yield() }
        preconditionFailure("State transition did not finish")
    }
    @MainActor static func main() async {
        let suite = "NACModelCheck." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var clients: [FakeNACClient] = []
        let model = PreviewModel(preferences: preferences, makeClient: { server in
            let client = FakeNACClient(server); clients.append(client); return client
        })
        model.password = "synthetic-only"
        model.checkServer()
        precondition(model.showSettings && !model.ready && !model.isBusy && clients.isEmpty)
        precondition(model.detail.contains("地址"))
        model.server = "http://192.0.2.10"
        model.password = "synthetic-only"
        model.checkServer()
        await until { clients.count == 1 && clients[0].pending != nil }
        precondition(model.isBusy && model.checkingServer && !model.ready)
        clients[0].fail()
        await until { !model.checkingServer }
        precondition(!model.isBusy && !model.ready && model.detail == "synthetic lookup failed")
        precondition(model.password == "synthetic-only")
        model.checkServer()
        await until { clients.count == 2 && clients[1].pending != nil }
        clients[1].succeed()
        await until { !model.checkingServer }
        precondition(!model.ready && !model.isBusy && model.deviceStatus == "已登记")
        precondition(model.deviceRecord == nil && clients[1].device == nil && clients[1].loginRequests == 0)
        precondition(model.detail.contains("AgentID"))
        model.openDeviceInfo()
        precondition(model.showDeviceInfo && model.localDevice.system.hasPrefix("macOS "))
        precondition(PreviewModel(preferences: preferences).server == "http://192.0.2.10")
        precondition(Set(preferences.persistentDomain(forName: suite)!.keys) == Set(["serverOrigin"]))

        // A cancelled, slow previous server must not overwrite a newer check.
        model.checkServer()
        await until { clients.count == 3 && clients[2].pending != nil }
        model.cancelServerCheck()
        precondition(!model.isBusy && !model.checkingServer && !model.ready)
        model.server = "http://192.0.2.11"
        model.checkServer()
        await until { clients.count == 4 && clients[3].pending != nil }
        clients[2].succeed()
        for _ in 0..<20 { await Task.yield() }
        precondition(model.checkingServer && model.isBusy && !model.ready)
        clients[3].succeed()
        await until { !model.checkingServer }
        precondition(!model.ready && !model.isBusy && model.deviceStatus == "已登记")
        precondition(PreviewModel(preferences: preferences).server == "http://192.0.2.11")

        // Changing the address invalidates the old ready state and an in-flight request.
        model.checkServer()
        await until { clients.count == 5 && clients[4].pending != nil }
        model.server = "http://192.0.2.12"
        precondition(!model.ready && !model.isBusy && !model.checkingServer && model.deviceRecord == nil)
        clients[4].succeed()
        for _ in 0..<20 { await Task.yield() }
        precondition(!model.ready && model.server == "http://192.0.2.12")
        // Desktop diagnostics must not create an authenticated session.
        let authClient = FakeNACClient("http://192.0.2.20")
        var sessions: [FakeHeartbeatSession] = []
        let loginModel = PreviewModel(preferences: preferences, makeClient: { _ in authClient }, makeHeartbeat: {
            let session = FakeHeartbeatSession(); sessions.append(session); return session
        })
        loginModel.server = "http://192.0.2.20"
        loginModel.checkServer()
        await until { authClient.pending != nil }
        authClient.succeed()
        await until { !loginModel.checkingServer }
        precondition(loginModel.connectionState == .notLoggedIn && loginModel.deviceStatus == "已登记" && authClient.loginRequests == 0)
        loginModel.startHeartbeat()
        precondition(sessions.isEmpty)
        authClient.waitForPreparation = false
        loginModel.account = "synthetic"

        // MFA/approval/registration follow-up and failed authentication must not start transport.
        loginModel.password = "synthetic-only"
        loginModel.submitLogin()
        precondition(loginModel.connectionState == .checking && loginModel.password.isEmpty)
        await until { authClient.loginPending != nil }
        authClient.completeLogin(needsAction: true)
        await until { !loginModel.isBusy }
        precondition(loginModel.connectionState == .needsAction && sessions.isEmpty && !loginModel.canStartHeartbeat)
        loginModel.password = "synthetic-only"
        loginModel.submitLogin()
        await until { authClient.loginPending != nil }
        authClient.failLogin()
        await until { !loginModel.isBusy }
        precondition(loginModel.connectionState == .notLoggedIn && sessions.isEmpty)

        // Successful authentication starts exactly one session, and only its ACK turns green.
        loginModel.password = "synthetic-only"
        loginModel.submitLogin()
        loginModel.submitLogin()
        await until { authClient.loginPending != nil }
        precondition(authClient.loginRequests == 3)
        authClient.completeLogin()
        await until { sessions.count == 1 && sessions[0].pending != nil }
        precondition(loginModel.connectionState == .connecting && loginModel.heartbeating)
        loginModel.startHeartbeat()
        precondition(sessions.count == 1)
        sessions[0].acknowledge?(1)
        precondition(loginModel.heartbeatCount == 1 && loginModel.lastHeartbeat != nil && loginModel.heartbeatSummary.contains("1 次"))
        loginModel.openSettings()
        loginModel.serverDraft = "invalid origin"
        precondition(loginModel.server == "http://192.0.2.20" && loginModel.heartbeating)
        loginModel.saveServerSettings()
        precondition(!loginModel.settingsError.isEmpty && loginModel.heartbeating && loginModel.connectionState == .connected)
        loginModel.showSettings = false
        precondition(loginModel.connectionState == .connected && loginModel.detail.isEmpty)
        loginModel.stopHeartbeat()
        precondition(loginModel.connectionState == .stopped && !loginModel.heartbeating)
        sessions[0].acknowledge?(2)
        sessions[0].fail()
        for _ in 0..<20 { await Task.yield() }
        precondition(loginModel.connectionState == .stopped && loginModel.heartbeatCount == 1)

        // Manual reconnect verifies the device before reusing accepted authentication.
        loginModel.startHeartbeat()
        await until { sessions.count == 2 && sessions[1].pending != nil }
        precondition(loginModel.heartbeatCount == 0 && loginModel.lastHeartbeat == nil)
        sessions[1].acknowledge?(1)
        precondition(loginModel.connectionState == .connected && authClient.loginRequests == 3)
        sessions[1].fail()
        await until { !loginModel.heartbeating }
        precondition(loginModel.connectionState == .interrupted && sessions.count == 2 && loginModel.canStartHeartbeat)
        precondition(loginModel.heartbeatCount == 1 && loginModel.lastHeartbeat != nil)
        loginModel.startHeartbeat()
        await until { sessions.count == 3 && sessions[2].pending != nil }
        sessions[2].fail()
        await until { !loginModel.heartbeating }
        precondition(loginModel.connectionState == .interrupted)

        loginModel.startHeartbeat()
        await until { sessions.count == 4 && sessions[3].pending != nil }
        sessions[3].acknowledge?(1)
        authClient.roleError = true
        sessions[3].roleChanged?()
        await until { !loginModel.heartbeating }
        precondition(loginModel.connectionState == .interrupted && loginModel.detail.contains("刷新失败"))
        sessions[3].fail()

        // A late login result for a previous server must not silently start its heartbeat.
        loginModel.password = "synthetic-only"
        loginModel.submitLogin()
        await until { authClient.loginPending != nil }
        loginModel.server = "http://192.0.2.21"
        authClient.completeLogin()
        for _ in 0..<20 { await Task.yield() }
        precondition(loginModel.connectionState == .notLoggedIn && !loginModel.ready && sessions.count == 4)
        let previousChecks = clients.count
        model.openSettings()
        model.serverDraft = "http://192.0.2.30"
        precondition(model.server == "http://192.0.2.12")
        model.saveServerSettings()
        precondition(!model.showSettings && !model.checkingServer && !model.ready)
        precondition(clients.count == previousChecks && model.server == "http://192.0.2.30")
        precondition(preferences.string(forKey: "serverOrigin") == "http://192.0.2.30")
        print("PASS: draft editing preserves live connection, invalid save rejected, valid save preserves address without discovery, heartbeat count/time retain and reset")

        let memory = MemoryPasswordStore()
        let savedClient = FakeNACClient("http://192.0.2.20")
        let savedModel = PreviewModel(preferences: preferences, makeClient: { _ in savedClient },
            makeHeartbeat: { FakeHeartbeatSession() }, passwordStore: memory)
        savedModel.server = "http://192.0.2.20"
        savedClient.heartbeatPort = nil // No transport needed to test credential handling.
        savedClient.waitForPreparation = false
        savedModel.account = "synthetic"; savedModel.password = "synthetic-only"; savedModel.rememberPassword = true
        savedModel.submitLogin()
        await until { savedClient.loginPending != nil }; savedClient.failLogin()
        await until { !savedModel.isBusy }
        precondition(memory.values.isEmpty)
        savedModel.password = "synthetic-only"; savedModel.submitLogin()
        await until { savedClient.loginPending != nil }; savedClient.completeLogin()
        await until { !savedModel.isBusy }
        precondition(savedModel.hasSavedPassword && savedModel.password.isEmpty)
        precondition(memory.values["http://192.0.2.20|synthetic"] == "synthetic-only")
        let restored = PreviewModel(preferences: preferences, passwordStore: memory)
        precondition(restored.account == "synthetic" && restored.password.isEmpty && restored.hasSavedPassword)
        savedModel.submitLogin()
        await until { savedClient.loginPending != nil }
        precondition(savedClient.loginRequests == 3)
        savedClient.completeLogin(); await until { !savedModel.isBusy }
        savedModel.rememberPassword = false; savedModel.forgetPassword()
        precondition(memory.values.isEmpty && !savedModel.hasSavedPassword)
        precondition(!(preferences.persistentDomain(forName: suite) ?? [:]).values.contains { ($0 as? String) == "synthetic-only" })
        print("PASS: failed login not saved, opt-in persistence, explicit re-login from store, restoration without plaintext and deletion")
        print("PASS: login follow-up and failures blocked, automatic single heartbeat, ACK-only connected state, stop/reconnect/remote close, stale login isolation")
        // A user can log in without a separate check. Retryable errors are bounded,
        // and stale device lookups cannot restart a logged-out session.
        let retryClient = FakeNACClient("http://192.0.2.20")
        retryClient.waitForPreparation = false
        var retrySessions: [FakeHeartbeatSession] = []
        let retryModel = PreviewModel(preferences: preferences, makeClient: { _ in retryClient },
            makeHeartbeat: {
                let session = FakeHeartbeatSession()
                retrySessions.append(session)
                return session
            }, passwordStore: memory, reconnectDelays: [.zero, .zero, .zero])
        retryModel.server = "http://192.0.2.20"
        retryModel.account = "synthetic"
        retryModel.password = "synthetic-only"
        retryModel.submitLogin()
        await until { retryClient.loginPending != nil }
        precondition(retryClient.lookupRequests == 1)
        retryClient.completeLogin()
        for index in 0..<4 {
            await until { retrySessions.count == index + 1 && retrySessions[index].pending != nil }
            retrySessions[index].fail(retryable: true)
        }
        await until { !retryModel.heartbeating && !retryModel.reconnecting }
        precondition(retryClient.loginRequests == 1 && retryClient.lookupRequests == 4)
        precondition(retryModel.connectionState == .interrupted && retryModel.canStartHeartbeat)

        retryClient.suspendLookup = true
        retryModel.startHeartbeat()
        await until { retryClient.lookupPending != nil }
        retryModel.stopHeartbeat()
        let stoppedLookup = retryClient.lookupPending
        retryClient.lookupPending = nil
        stoppedLookup?.resume(returning: retryClient.lookupResult)
        for _ in 0..<20 { await Task.yield() }
        precondition(retrySessions.count == 4 && retryModel.connectionState == .stopped)

        retryModel.startHeartbeat()
        await until { retryClient.lookupPending != nil }
        retryModel.logout()
        let staleLookup = retryClient.lookupPending
        retryClient.lookupPending = nil
        staleLookup?.resume(returning: retryClient.lookupResult)
        for _ in 0..<20 { await Task.yield() }
        precondition(retrySessions.count == 4 && retryModel.connectionState == .notLoggedIn)
        precondition(!retryModel.authenticationAccepted && !retryModel.reconnecting && retryModel.deviceRecord == nil)

        retryClient.suspendLookup = false
        retryModel.password = "synthetic-only"
        retryModel.submitLogin()
        await until { retryClient.loginPending != nil }
        retryClient.completeLogin()
        await until { retrySessions.count == 5 && retrySessions[4].pending != nil }
        retryClient.lookupResult = .init(id: "different", recordedOS: "macOS", registered: "1")
        retrySessions[4].fail(retryable: true)
        await until { retryModel.connectionState == .needsAction }
        precondition(retrySessions.count == 5 && retryClient.loginRequests == 2 && !retryModel.authenticationAccepted)
        print("PASS: login preflight, bounded device-verified reconnect, manual stop and logout cancellation, device identity mismatch")
        print("PASS: empty-server guidance, visible failure and retry, server persistence without credentials, cancellation and stale-check isolation")
    }
}
