import Foundation
@main
struct RequestFailureSummaryCheck {
    static func main() {
        var request = URLRequest(url: URL(string: "https://example.invalid/access/1.0/mac/json/auth/index")!)
        request.httpBody = AuthenticationRequest.formEncode([("username", "encoded-account"), ("password", "synthetic-ciphertext")])
        request.setValue("synthetic-header-token", forHTTPHeaderField: "Web-Token")
        let result = RequestFailureSummary.describe(request: request, httpStatus: 200, code: "10000000",
            serverMessage: "账号策略拒绝 raw-account synthetic-password encoded-account synthetic-ciphertext synthetic-header-token token=unknown-secret",
            secrets: ["raw-account", "synthetic-password"])
        precondition(result.contains("auth/index") && result.contains("HTTP 200") && result.contains("10000000"))
        precondition(result.contains("账号策略拒绝"))
        for secret in ["raw-account", "synthetic-password", "encoded-account", "synthetic-ciphertext", "synthetic-header-token", "unknown-secret"] {
            precondition(!result.contains(secret))
        }
        request.url = URL(string: "https://example.invalid/access/1.0/mac/json/auth/config")!
        precondition(RequestFailureSummary.stage(request).contains("检查账号策略"))
        print("PASS: request stage, HTTP/code context, credential/ciphertext/token redaction")
    }
}
