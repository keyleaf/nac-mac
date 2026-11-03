import Foundation

@main
struct HeartbeatTransportCheck {
    @MainActor static func main() async throws {
        let port = UInt16(CommandLine.arguments[1])!
        let mode = CommandLine.arguments[2]
        let probe = HeartbeatProbe()
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
        print("PASS: loopback heartbeat transport \(mode)")
    }
}
