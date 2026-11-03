import Foundation

/// Explicit, bounded integration diagnostic. Never part of offline checks.
@main
struct HeartbeatDiagnosticCheck {
    @MainActor static func main() async throws {
        let client = try NACService(server: CommandLine.arguments[1])
        let record = try await client.prepare()
        guard let port = client.heartbeatPort, port == 37527, let host = client.origin.host else { fatalError("Unverified endpoint") }
        let probe = HeartbeatProbe()
        let seconds = CommandLine.arguments.count > 2 ? min(60, max(1, Int(CommandLine.arguments[2]) ?? 12)) : 12
        let task = Task {
            try await probe.run(host: host, port: port, deviceID: record.id, maximumHeartbeats: nil,
                onAcknowledgement: { print("Heartbeat acknowledged:", $0) })
        }
        let limit = Task { try? await Task.sleep(for: .seconds(seconds)); task.cancel() }
        defer { limit.cancel() }
        do { _ = try await task.value }
        catch is CancellationError { print("Bounded diagnostic stopped after \(seconds) seconds") }
        catch let failure as HeartbeatProbe.Failure { print(failure.message) }
        print("Diagnostic connection closed; no login, device update or server command executed")
    }
}
