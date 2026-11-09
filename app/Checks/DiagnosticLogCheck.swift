import Foundation

@main struct DiagnosticLogCheck {
    static func main() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("nac-log-check-" + UUID().uuidString)
        defer { try? fm.removeItem(at: directory) }
        var date = Date(timeIntervalSince1970: 1_790_000_000)
        let log = DiagnosticLog(directory: directory, maximumBytes: 2048, retentionDays: 3, now: { date })
        log.record(.requestFinished, [.stage: "auth/index", .httpStatus: "200", .serverCode: "10000000",
            .reason: "password=synthetic-secret", .trade: "<Token>synthetic-secret</Token>"])
        log.flush()
        var files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let text = try String(contentsOf: files[0], encoding: .utf8)
        precondition(!text.contains("synthetic-secret") && !text.contains("Token") && !text.contains("password"))
        let row = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        precondition((row["httpStatus"] as? NSNumber)?.intValue == 200 && row["stage"] as? String == "auth/index")
        precondition(row["reason"] == nil && row["trade"] == nil && row["time"] != nil && row["session"] != nil)
        for count in 1...100 { log.record(.heartbeatAcknowledged, [.count: String(count), .latency: "0.05"]) }
        log.flush()
        files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        precondition(files.count == 2)
        for file in files {
            let size = (try fm.attributesOfItem(atPath: file.path)[.size] as! NSNumber).intValue
            precondition(size <= 2048)
            for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
                _ = try JSONSerialization.jsonObject(with: Data(line.utf8))
            }
        }
        let foreign = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: foreign)
        date = date.addingTimeInterval(4 * 86400)
        log.record(.systemWake); log.flush()
        let remaining = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }; precondition(remaining.count == 1)
        try log.clear()
        let cleared = try fm.contentsOfDirectory(atPath: directory.path); precondition(cleared == ["keep.txt"])
        log.record(.networkChanged, [.path: "satisfied", .interfaces: "wifi,wiredEthernet"]); log.flush()
        let resumed = try fm.contentsOfDirectory(atPath: directory.path); precondition(resumed.count == 2)
        let file = directory.appendingPathComponent("blocked")
        try Data().write(to: file)
        let broken = DiagnosticLog(directory: file)
        broken.record(.appStarted); broken.flush()
        var failed = false
        do { try broken.prepareForViewing() } catch { failed = true }
        precondition(failed)
        print("PASS: log privacy allowlist, JSONL, bounded rotation, retention, clear preserving unrelated files, resumed logging and write-failure isolation")
    }
}
