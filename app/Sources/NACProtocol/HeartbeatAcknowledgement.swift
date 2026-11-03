import Foundation

enum HeartbeatAcknowledgement {
    static func valid(_ content: Data) -> Bool {
        tradeCode(content) == "HeartTest"
    }
    static func tradeCode(_ content: Data) -> String? {
        guard let delegate = parse(content), delegate.trades.count == 1,
              let name = delegate.trades.first, !name.isEmpty, name.utf8.count <= 32,
              name.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }) else { return nil }
        return name
    }
    static func isRoleChangedNotification(_ content: Data) -> Bool {
        guard tradeCode(content) == "RoleChanged", let reader = parse(content) else { return false }
        // A role notification must not smuggle a command into this supported branch.
        return reader.controls.isEmpty
    }
    static func safeControlSummary(_ content: Data) -> String {
        guard let reader = parse(content) else { return "控制字段未识别" }
        let allowed = Set(["NoticeNetStateChanged", "LimitedAccessNet", "ShutdownNetwork", "IpRenew", "TokenRecovery", "GetZtpGateways", "ReportTracertRouteInfo", "ZtpConfigChange", "Online", "Offline", "0", "1", "2", "-1"])
        return ["WhatToDo", "StateOfNet"].compactMap { key -> String? in
            guard let values = reader.controls[key], values.count == 1, let value = values.first else { return nil }
            return key + "=" + (allowed.contains(value) ? value : "其他（值未显示）")
        }.joined(separator: ", ")
    }
    private static func parse(_ content: Data) -> TradeReader? {
        guard !content.isEmpty, content.count <= 65_536, !content.contains(0) else { return nil }
        let ascii = String(decoding: content, as: UTF8.self).uppercased()
        guard !ascii.contains("<!DOCTYPE"), !ascii.contains("<!ENTITY") else { return nil }
        let delegate = TradeReader()
        let parser = XMLParser(data: content)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        return parser.parse() && delegate.valid ? delegate : nil
    }
    private final class TradeReader: NSObject, XMLParserDelegate {
        var depth = 0
        var nodes = 0
        var collecting = false
        var field = ""
        var controls: [String: [String]] = [:]
        var text = ""
        var trades: [String] = []
        var valid = true
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            depth += 1; nodes += 1
            guard depth <= 16, nodes <= 128 else { valid = false; parser.abortParsing(); return }
            if ["TradeCode", "WhatToDo", "StateOfNet"].contains(name) && depth == 2 { collecting = true; field = name; text = "" }
            else if collecting { valid = false; parser.abortParsing() }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if collecting {
                text += string
                if text.utf8.count > 64 { valid = false; parser.abortParsing() }
            }
        }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if collecting { valid = false; parser.abortParsing() }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == field && collecting {
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if field == "TradeCode" { trades.append(value) }
                else { controls[field, default: []].append(value) }
                collecting = false
            }
            depth -= 1
        }
    }
}
