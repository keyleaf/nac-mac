import Foundation

/// Explicit device discovery integration check, excluded from offline protocol checks.
@main
struct ServicePreflightCheck {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 3, CommandLine.arguments[2] == "--discover-this-mac" else {
            fatalError("usage: check <server> --discover-this-mac (may create or update a device record)")
        }
        let service = try NACService(server: CommandLine.arguments[1])
        let device = try await service.prepare()
        precondition(!device.id.isEmpty)
        print("PASS: live configuration, login public key, Mac device discovery; recorded OS: \(device.recordedOS)")
        print("Server state: \(try await service.status())")
        print("No credentials, login, formal registration form, SPA or logout submitted")
    }
}
