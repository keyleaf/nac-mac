import Foundation

@main
struct HeartbeatTransportCheck {
    @MainActor static func main() async throws {
        let port = UInt16(CommandLine.arguments[1])!
        let mode = CommandLine.arguments[2]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nac-transport-log-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = DiagnosticLog(directory: directory)
        let probe = HeartbeatProbe(diagnostics: diagnostics)
        var acknowledgements: [Int] = []
        var roleChanges = 0
        let task = Task { try await probe.run(host: "127.0.0.1", port: port, deviceID: "synthetic", timeoutSeconds: 0.5,
            intervalSeconds: 0.02, maximumHeartbeats: ["idleclose", "push"].contains(mode) ? nil : (["continuous", "role"].contains(mode) ? 3 : 1),
            onAcknowledgement: { acknowledgements.append($0) }, onRoleChanged: { roleChanges += 1 }) }
        if mode == "cancel" { try await Task.sleep(for: .milliseconds(50)); task.cancel() }
        do {
            let result = try await task.value
            precondition(["echo", "continuous", "role"].contains(mode) && result.trade == "HeartTest" && result.payloadBytes > 0)
            precondition(acknowledgements == (["continuous", "role"].contains(mode) ? [1,2,3] : [1]))
            precondition(result.numericResults == (mode == "echo" ? "RetCode=0" : "未识别到结果码"))
        } catch is CancellationError {
            precondition(mode == "cancel")
        } catch let error as HeartbeatProbe.Failure {
            precondition((mode == "corrupt" && error.message.contains("校验")) || (mode == "timeout" && error.message.contains("超时")) ||
                (mode == "push" && error.message.contains("交易=SvrMsgToAss") && error.message.contains("XML交易=SvrMsgToAss") && !error.message.contains("synthetic-secret") && acknowledgements == [1]) ||
                (mode == "idleclose" && error.message.contains("服务器关闭") && error.message.contains("已应答 1 次") && error.message.contains("等待下次心跳")))
        }
        precondition(roleChanges == (mode == "role" ? 3 : 0))
        diagnostics.flush()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let text = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        precondition(!text.contains("synthetic-secret") && !text.contains("synthetic"))
        let events = try text.split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        precondition(events.filter { $0["event"] as? String == "heartbeatAcknowledged" }.count == acknowledgements.count)
        let endings = events.filter { $0["event"] as? String == "heartbeatFinished" }
        let reason = ["echo": "completed", "continuous": "completed", "role": "completed", "idleclose": "remote_closed", "push": "unsupported_message", "corrupt": "frame_error", "timeout": "timeout", "cancel": "cancelled"][mode]!
        precondition(endings.count == 1 && endings[0]["reason"] as? String == reason)
        print("PASS: loopback heartbeat transport \(mode)")
    }
}
