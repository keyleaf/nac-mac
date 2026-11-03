import Foundation

/// Explicit read-only username policy request. Never submits passwords or auth/index.
@main
struct AccountPolicyDiagnosticCheck {
    @MainActor static func main() async throws {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let account = String(data: input, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !account.isEmpty else { fatalError("account required on stdin") }
        let service = try NACService(server: CommandLine.arguments[1])
        do {
            _ = try await service.prepare()
            let mustChange = try await service.accountRequiresPasswordChange(account)
            print("Account policy query succeeded; must change password:", mustChange)
        } catch let error as NACService.Failure { print(error.message) }
        print("No password supplied; auth/index not called")
    }
}
