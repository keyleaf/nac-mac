import Foundation

/// Local bounded JSONL diagnostics. No free-form messages, payloads or credential fields.
final class DiagnosticLog {
    enum Event: String { case appStarted, appTerminated, connectionState, loginRequested, loginResult, requestStarted, requestFinished, heartbeatStarted, tcpReady, heartbeatSent, heartbeatAcknowledged, heartbeatFinished, serverMessage, systemSleep, systemWake, sessionInactive, sessionActive, networkChanged }
    enum Field: String { case stage, httpStatus, serverCode, errorCode, reason, state, count, elapsed, latency, sequence, phase, mode, trade, path, interfaces, expensive }
    static let shared = DiagnosticLog(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NACMac", isDirectory: true), enabled: ["io.github.keyleaf.nac-mac", "local.nac.preview"].contains(Bundle.main.bundleIdentifier ?? ""))
    let directory: URL
    private let queue = DispatchQueue(label: "io.github.keyleaf.nac-mac.diagnostics")
    private let session = UUID().uuidString
    private let enabled: Bool
    private let maximumBytes: Int
    private let retentionDays: Int
    private let now: () -> Date
    private let day: DateFormatter
    private let timestamp: ISO8601DateFormatter
    private var lastDay = ""
    private var writeFailure: Error?

    init(directory: URL, maximumBytes: Int = 2 * 1024 * 1024, retentionDays: Int = 7, enabled: Bool = true, now: @escaping () -> Date = Date.init) {
        self.enabled = enabled
        self.directory = directory; self.maximumBytes = maximumBytes; self.retentionDays = retentionDays; self.now = now
        day = DateFormatter(); day.calendar = Calendar(identifier: .gregorian); day.locale = Locale(identifier: "en_US_POSIX"); day.timeZone = .current; day.dateFormat = "yyyy-MM-dd"
        timestamp = ISO8601DateFormatter(); timestamp.timeZone = .current; timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
    private static let numbers: Set<Field> = [.httpStatus, .serverCode, .errorCode, .count, .elapsed, .latency, .sequence, .expensive]
    private static let categories: [Field: Set<String>] = [
        .stage: ["configuration", "auth/config", "auth/index", "device/infoprocess", "device/netStatus", "device/info"],
        .reason: ["accepted", "needs_action", "auth_failed", "completed", "cancelled", "timeout", "connect_failed", "send_failed", "receive_failed", "remote_closed", "unsupported_message", "invalid_xml", "frame_error", "failure", "stop_requested"],
        .state: ["notLoggedIn", "checking", "authenticating", "needsAction", "connecting", "connected", "stopped", "interrupted"],
        .phase: ["连接中", "首次应答", "后续应答", "等待下次心跳"],
        .mode: ["single", "continuous"], .trade: ["HeartTest", "RoleChanged", "SvrMsgToAss", "SvrNoticeToAgent"],
        .path: ["satisfied", "unsatisfied", "requiresConnection"]
    ]
    func record(_ event: Event, _ fields: [Field: String] = [:]) {
        guard enabled else { return }
        queue.async { [self] in
            do {
                var row: [String: Any] = ["time": timestamp.string(from: now()), "event": event.rawValue, "session": session]
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
                row["version"] = version.range(of: #"^[0-9]+(\.[0-9]+){0,3}$"#, options: .regularExpression) != nil ? version : "development"
                for (key, value) in fields {
                    if Self.numbers.contains(key) {
                        if value.utf8.count <= 32, let number = Double(value), number.isFinite { row[key.rawValue] = number }
                    } else if key == .interfaces {
                        let types = value.split(separator: ",").map(String.init)
                        if !types.isEmpty, types.count <= 5, types.allSatisfy({ ["wifi", "wiredEthernet", "cellular", "loopback", "other"].contains($0) }) { row[key.rawValue] = types.joined(separator: ",") }
                    } else if Self.categories[key]?.contains(value) == true { row[key.rawValue] = value }
                }
                var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]); data.append(10)
                try append(data)
                writeFailure = nil
            } catch { writeFailure = error }
        }
    }
    private func ownedFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]).filter {
            $0.lastPathComponent.range(of: #"^nac-[0-9]{4}-[0-9]{2}-[0-9]{2}(\.1)?\.jsonl$"#, options: .regularExpression) != nil
        }
    }
    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
    }
    private func append(_ data: Data) throws {
        try prepare()
        let date = now(), today = day.string(from: date)
        let file = directory.appendingPathComponent("nac-" + today + ".jsonl")
        if lastDay != today {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = day.timeZone
            let cutoff = day.string(from: calendar.date(byAdding: .day, value: -(retentionDays - 1), to: date)!)
            for item in try ownedFiles() {
                let name = String(item.lastPathComponent.dropFirst(4).prefix(10))
                if name < cutoff || name > today { try FileManager.default.removeItem(at: item) }
            }
            lastDay = today
        }
        if FileManager.default.fileExists(atPath: file.path) {
            guard try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
            let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
            if size + data.count > maximumBytes {
                let rotated = directory.appendingPathComponent("nac-" + today + ".1.jsonl")
                if FileManager.default.fileExists(atPath: rotated.path) { try FileManager.default.removeItem(at: rotated) }
                try FileManager.default.moveItem(at: file, to: rotated)
            }
        }
        if !FileManager.default.fileExists(atPath: file.path) {
            guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        }
        let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data)
    }
    func flush() { queue.sync {} }
    func prepareForViewing() throws {
        try queue.sync { try prepare(); if let writeFailure { throw writeFailure } }
    }
    func clear() throws {
        try queue.sync {
            try prepare()
            for file in try ownedFiles() { try FileManager.default.removeItem(at: file) }
            lastDay = ""; writeFailure = nil
        }
    }
}
