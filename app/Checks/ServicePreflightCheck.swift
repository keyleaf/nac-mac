import Foundation

/// Explicitly invoked read-only integration check, excluded from offline protocol checks.
@main
struct ServicePreflightCheck {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("server origin argument required") }
        let service = try NACService(server: CommandLine.arguments[1])
        let device = try await service.prepare()
        precondition(!device.id.isEmpty)
        print("PASS: live configuration, login public key, existing device lookup; recorded OS: \(device.recordedOS)")
        print("Server state: \(try await service.status())")
        print("No credentials, login, registration, SPA or logout submitted")
    }
}
