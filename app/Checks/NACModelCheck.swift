import Foundation

@MainActor
final class FakeNACClient: NACClient {
    let origin: URL
    var device: NACService.Device?
    var heartbeatPort: UInt16? = 37527
    var pending: CheckedContinuation<NACService.Device, Error>?
    init(_ server: String) { origin = URL(string: server)! }
    func prepare() async throws -> NACService.Device {
        let result = try await withCheckedThrowingContinuation { pending = $0 }
        device = result
        return result
    }
    func status() async throws -> String { "设备在线（测试）" }
    func login(account: String, password: String, verificationCode: String) async throws -> NACService.LoginResult {
        fatalError("This regression check must not submit credentials")
    }
    func refreshAfterRoleChange() async throws -> String { try await status() }
    func succeed() { let continuation = pending; pending = nil; continuation?.resume(returning: .init(id: "synthetic", recordedOS: "macOS", registered: "1")) }
    func fail() { let continuation = pending; pending = nil; continuation?.resume(throwing: NACService.Failure(message: "synthetic lookup failed")) }
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
        precondition(model.ready && !model.isBusy && model.deviceStatus.contains("在线"))
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
        precondition(model.ready && !model.isBusy)
        precondition(PreviewModel(preferences: preferences).server == "http://192.0.2.11")

        // Changing the address invalidates the old ready state and an in-flight request.
        model.checkServer()
        await until { clients.count == 5 && clients[4].pending != nil }
        model.server = "http://192.0.2.12"
        precondition(!model.ready && !model.isBusy && !model.checkingServer)
        clients[4].succeed()
        for _ in 0..<20 { await Task.yield() }
        precondition(!model.ready && model.server == "http://192.0.2.12")
        print("PASS: empty-server guidance, visible failure and retry, server persistence without credentials, cancellation and stale-check isolation")
    }
}
