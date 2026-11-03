import Foundation

enum RequestFailureSummary {
    static func stage(_ request: URLRequest) -> String {
        switch request.url?.path.components(separatedBy: "/json/").last {
        case "auth/config": return "检查账号策略（auth/config）"
        case "auth/index": return "提交账号认证（auth/index）"
        case "device/infoprocess": return "查询现有设备记录（device/infoprocess）"
        case "device/netStatus": return "查询设备状态（device/netStatus）"
        default: return "读取服务器配置"
        }
    }

    static func describe(request: URLRequest, httpStatus: Int, code: String,
                         serverMessage: String?, secrets: [String]) -> String {
        var terms = secrets
        if let token = request.value(forHTTPHeaderField: "Web-Token") { terms.append(token) }
        if let body = request.httpBody, let form = String(data: body, encoding: .utf8),
           let fields = URLComponents(string: "https://example.invalid/?" + form)?.queryItems {
            let privateNames = Set(["username", "user_name", "password", "token", "tokenId", "deviceid", "deviceId", "idp"])
            terms += fields.filter { privateNames.contains($0.name) }.compactMap(\.value)
        }
        var message = serverMessage ?? ""
        if message.utf8.count > 8192 { message = "服务器说明过长，已省略" }
        for term in Set(terms).filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            message = message.replacingOccurrences(of: term, with: "[已隐藏]")
        }
        message = message.replacingOccurrences(of: #"(?i)[\"']?(password|passwd|pwd|token|secret|authorization|cookie)[\"']?\s*[:=]\s*[\"']?[^\s,;，。\"'}]+"#,
            with: "$1=[已隐藏]", options: .regularExpression)
        message = String(String.UnicodeScalarView(message.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        let numeric = !code.isEmpty && code.count <= 12 && code.utf8.allSatisfy { (48...57).contains($0) || $0 == 45 }
        let suffix = message.isEmpty ? "服务器未提供具体说明" : String(message.prefix(300))
        return "\(stage(request))失败：HTTP \(httpStatus)，错误码 \(numeric ? code : "未知")。\(suffix)"
    }
}
