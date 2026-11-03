import Foundation

@main
struct AuthenticationRequestCheck {
    static func main() throws {
        precondition(WebBase64.encode("a") == "YQ::")
        precondition(WebBase64.encode("~~~") == "fn5,")
        precondition(WebBase64.encode("???") == "Pz8.")
        let decoded = try WebBase64.decode(WebBase64.encode("中文"))
        precondition(decoded == Data("中文".utf8))
        let context = AuthenticationRequest.Context(origin: URL(string: "https://example.invalid:8443")!,
            osType: "mac", headerOSType: "Mac", language: "zh", cacheMilliseconds: 123, serialNumber: "123")
        let request = try AuthenticationRequest.prepare(route: "auth/index",
            parameters: [("user_name", WebBase64.encode("a")), ("password", "a+b/=="), ("verify_code", "")], context: context)
        precondition(request.url!.absoluteString == "https://example.invalid:8443/access/1.0/mac/json/auth/index?local_lguage_set=zh&cache=123")
        precondition(String(data: request.httpBody!, encoding: .utf8) == "user_name=YQ%3A%3A&password=a%2Bb%2F%3D%3D&verify_code=")
        precondition(request.value(forHTTPHeaderField: "Web-Token") == nil)
        precondition(request.value(forHTTPHeaderField: "Extend-Data") == "ostype=Mac;isclient=1")
        let stateRequest = try AuthenticationRequest.prepare(route: "device/netStatus", parameters: [("deviceId", "synthetic")], context: context)
        precondition(String(decoding: stateRequest.httpBody!, as: UTF8.self) == "deviceId=synthetic")
        do {
            _ = try AuthenticationRequest.prepare(route: "device/cutoff", parameters: [], context: context)
            preconditionFailure("unimplemented logout endpoint accepted")
        } catch AuthenticationRequest.Failure.invalidContext {}
        let changed = try AuthenticationRequest.prepare(route: "auth/index",
            parameters: [("password", "a+b/=="), ("user_name", "YQ::"), ("verify_code", "")], context: context)
        precondition(changed.value(forHTTPHeaderField: "Session-Num") != request.value(forHTTPHeaderField: "Session-Num"))
        do {
            _ = try AuthenticationRequest.prepare(route: "auth/index", parameters: [("x", "1"), ("x", "2")], context: context)
            preconditionFailure("duplicate parameter accepted")
        } catch AuthenticationRequest.Failure.invalidParameters {}
        print("PASS: HTTP Base64 alphabet, form escaping, request URL and headers, ordered checksum, duplicate rejection")
    }
}
