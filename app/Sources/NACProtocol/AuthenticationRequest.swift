import Foundation

/// Prepares requests without sending them. Platform and device identity must be established by the caller.
enum AuthenticationRequest {
    enum Failure: Error { case invalidContext, invalidParameters }
    struct Context {
        let origin: URL
        let osType: String
        let headerOSType: String
        let language: String
        let cacheMilliseconds: Int64
        let serialNumber: String
        var webToken: String? = nil
        var diskID: String? = nil
    }
    static func formEncode(_ fields: [(String, String)]) -> Data {
        func escape(_ text: String) -> String {
            text.utf8.map { byte in
                if (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                    || [45, 46, 95, 126].contains(byte) { return String(UnicodeScalar(byte)) }
                return String(format: "%%%02X", byte)
            }.joined()
        }
        return Data(fields.map { escape($0.0) + "=" + escape($0.1) }.joined(separator: "&").utf8)
    }
    static func prepare(route: String, parameters: [(String, String)], context: Context) throws -> URLRequest {
        guard let origin = URLComponents(url: context.origin, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(origin.scheme ?? ""), origin.host != nil,
              origin.user == nil, origin.password == nil, origin.query == nil, origin.fragment == nil,
              origin.path.isEmpty || origin.path == "/",
              !context.osType.isEmpty, context.osType.utf8.allSatisfy({ (97...122).contains($0) }),
              !context.language.isEmpty, context.language.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }),
              context.cacheMilliseconds >= 0, ["auth/config", "auth/index", "device/infoprocess", "device/netStatus", "device/info"].contains(route) else { throw Failure.invalidContext }
        let headers = [context.headerOSType, context.serialNumber, context.webToken ?? "", context.diskID ?? ""]
        guard headers.allSatisfy({ !$0.contains("\r") && !$0.contains("\n") && !$0.contains("\0") }) else { throw Failure.invalidContext }
        let names = parameters.map(\.0)
        guard Set(names).count == names.count,
              names.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 } }) else { throw Failure.invalidParameters }
        var components = origin
        components.path = "/access/1.0/\(context.osType)/json/\(route)"
        components.queryItems = [.init(name: "local_lguage_set", value: context.language),
                                 .init(name: "cache", value: String(context.cacheMilliseconds))]
        guard let url = components.url else { throw Failure.invalidContext }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = formEncode(parameters)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var referer = origin
        referer.path = "/"
        request.setValue(referer.url!.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(try RequestSignature.checksum(url.absoluteString, parameters: parameters), forHTTPHeaderField: "Session-Num")
        request.setValue("ostype=\(context.headerOSType);isclient=1", forHTTPHeaderField: "Extend-Data")
        request.setValue(context.serialNumber, forHTTPHeaderField: "Serial-Num")
        if let token = context.webToken, !token.isEmpty { request.setValue(token, forHTTPHeaderField: "Web-Token") }
        if let disk = context.diskID, !disk.isEmpty { request.setValue(disk, forHTTPHeaderField: "Device-DiskId") }
        return request
    }
}
