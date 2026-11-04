import Foundation
import Network

/// Continuous transport is injectable so login transitions can be checked without real credentials.
@MainActor
protocol ContinuousHeartbeatSession: AnyObject {
    func runContinuously(host: String, port: UInt16, deviceID: String,
                         onAcknowledgement: @escaping (Int) -> Void,
                         onRoleChanged: @escaping () -> Void) async throws
}

/// One explicitly owned TCP connection. No automatic reconnect, device update or policy execution.
@MainActor
final class HeartbeatProbe {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    struct Reply {
        let trade: String
        let payloadBytes: Int
        let numericResults: String
    }
    private var activeID: UUID?
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<Reply, Error>?
    private var deadline: Task<Void, Never>?
    private var decoder = ASMFrame.Stream()
    private var nextSend: Task<Void, Never>?
    private var deviceID = ""
    private var expectedSerial: UInt32?
    private var count = 0
    private var maximumHeartbeats: Int? = 1
    private var intervalSeconds = 30.0
    private var timeoutSeconds = 10.0
    private var onAcknowledgement: ((Int) -> Void)?
    private var onRoleChanged: (() -> Void)?
    private var startedAt = ContinuousClock.now
    private var sentAt = ContinuousClock.now
    private var phase = "连接中"
    private var networkError = ""

    func run(host: String, port: UInt16, deviceID: String, timeoutSeconds: Double = 10,
             intervalSeconds: Double = 30, maximumHeartbeats: Int? = 1,
             onAcknowledgement: ((Int) -> Void)? = nil,
             onRoleChanged: (() -> Void)? = nil) async throws -> Reply {
        guard activeID == nil, !host.isEmpty, port > 0, (0.05...30).contains(timeoutSeconds),
              (0.01...60).contains(intervalSeconds), maximumHeartbeats == nil || maximumHeartbeats! > 0 else {
            throw Failure(message: "心跳验证参数无效或已有验证正在运行")
        }
        try Task.checkCancellation()
        _ = try HeartbeatMessage.content(deviceID: deviceID, requestClientType: "mobile")
        self.deviceID = deviceID
        self.count = 0
        self.startedAt = .now
        self.phase = "连接中"
        self.networkError = ""
        self.maximumHeartbeats = maximumHeartbeats
        self.intervalSeconds = intervalSeconds
        self.timeoutSeconds = timeoutSeconds
        self.onAcknowledgement = onAcknowledgement
        self.onRoleChanged = onRoleChanged
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeID = id
                self.continuation = continuation
                decoder = ASMFrame.Stream()
                let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
                self.connection = connection
                connection.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self, self.activeID == id else { return }
                        switch state {
                        case .ready:
                            self.receive(id)
                            self.send(id)
                        case .failed(let error):
                            self.networkError = String(describing: error)
                            self.finish(id, .failure(Failure(message: "TCP 连接失败，未确认心跳")))
                        case .cancelled:
                            self.finish(id, .failure(CancellationError()))
                        default: break
                        }
                    }
                }
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(timeoutSeconds)) } catch { return }
                    self?.finish(id, .failure(Failure(message: "等待匹配心跳响应超时；不能判定本应用已接管连接")))
                }
                connection.start(queue: .main)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, .failure(CancellationError())) }
        }
    }

    private func send(_ id: UUID) {
        guard activeID == id, let connection else { return }
        let serial = UInt32.random(in: 0..<1_000_000)
        expectedSerial = serial
        sentAt = .now
        phase = count == 0 ? "首次应答" : "后续应答"
        do {
            let frame = try HeartbeatMessage.frame(deviceID: deviceID, requestClientType: "mobile", serial: serial)
            deadline?.cancel()
            deadline = Task { [weak self] in
                guard let delay = self?.timeoutSeconds else { return }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                self?.finish(id, .failure(Failure(message: "心跳应答超时，连接已停止；不会自动重连或重登")))
            }
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                if let error { Task { @MainActor in
                    guard let self, self.activeID == id else { return }
                    self.networkError = String(describing: error)
                    self.finish(id, .failure(Failure(message: "心跳发送失败")))
                } }
            })
        } catch { finish(id, .failure(error)) }
    }

    private func receive(_ id: UUID) {
        guard activeID == id, let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.activeID == id else { return }
                do {
                    if let data, !data.isEmpty {
                        let messages = try self.decoder.feed(data)
                        // RoleChanged is a notification, not a heartbeat acknowledgement. Its
                        // original handler refreshes configuration and requests policies.
                        // Inspect every frame, including coalesced notifications and replies.
                        for other in messages where other.trade != "HeartTest" {
                            if self.onRoleChanged != nil, other.trade == "RoleChanged",
                               HeartbeatAcknowledgement.isRoleChangedNotification(other.content) {
                                self.onRoleChanged?()
                                continue
                            }
                            let safeName = other.trade.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }) ? other.trade : "未识别"
                            let xmlTrade = HeartbeatAcknowledgement.tradeCode(other.content) ?? "未识别"
                            let controls = HeartbeatAcknowledgement.safeControlSummary(other.content)
                            self.finish(id, .failure(Failure(message: "收到非心跳消息：交易=\(safeName)，XML交易=\(xmlTrade)，序号=\(other.header.field52)，负载=\(other.content.count)字节；\(controls)。已停止试验连接，请保留原客户端处理")))
                            return
                        }
                        if let serial = self.expectedSerial,
                           let match = messages.first(where: { $0.trade == "HeartTest" && $0.header.field52 == serial }) {
                            guard HeartbeatAcknowledgement.valid(match.content) else {
                                self.finish(id, .failure(Failure(message: "心跳响应 XML 不符合已确认的协议，连接已停止")))
                                return
                            }
                            self.deadline?.cancel()
                            self.expectedSerial = nil
                            self.count += 1
                            self.phase = "等待下次心跳"
                            self.onAcknowledgement?(self.count)
                            if let limit = self.maximumHeartbeats, self.count >= limit {
                                self.finish(id, .success(Reply(trade: match.trade, payloadBytes: match.content.count,
                                    numericResults: Self.numericResults(match.content))))
                                return
                            }
                            let remaining = max(Duration.zero, .seconds(self.intervalSeconds) - self.sentAt.duration(to: .now))
                            self.nextSend = Task { [weak self] in
                                do { try await Task.sleep(for: remaining) } catch { return }
                                self?.send(id)
                            }
                            self.receive(id)
                            return
                        }
                    }
                    if complete || error != nil {
                        if let error { self.networkError = String(describing: error) }
                        self.finish(id, .failure(Failure(message: error == nil ? "服务器关闭了 TCP 连接" : "TCP 接收失败")))
                    } else { self.receive(id) }
                } catch {
                    self.finish(id, .failure(Failure(message: "响应帧校验或解压失败；未执行服务器返回的任何指令")))
                }
            }
        }
    }

    private static func numericResults(_ data: Data) -> String {
        // Diagnostics only: whitelist short result codes; never expose tokens, arbitrary XML or execute entities.
        let text = String(decoding: data, as: UTF8.self)
        let regex = try! NSRegularExpression(pattern: #"<(RetCode|ErrCode|ErrorCode|ReturnCode|Result)>\s*(-?[0-9]{1,9}|true|false)\s*</\1>"#, options: [.caseInsensitive])
        var values: [String] = []
        regex.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, stop in
            if let match, let nameRange = Range(match.range(at: 1), in: text), let valueRange = Range(match.range(at: 2), in: text) {
                values.append("\(text[nameRange])=\(text[valueRange])")
                if values.count >= 4 { stop.pointee = true }
            }
        }
        return values.isEmpty ? "未识别到结果码" : values.joined(separator: ", ")
    }

    private func finish(_ id: UUID, _ result: Result<Reply, Error>) {
        guard activeID == id else { return }
        var reported = result
        if case .failure(let failure as Failure) = result {
            let components = startedAt.duration(to: .now).components
            let elapsed = Double(components.seconds) + Double(components.attoseconds) / 1e18
            let transport = networkError.isEmpty ? "" : "；网络：\(networkError)"
            reported = .failure(Failure(message: "\(failure.message)（已应答 \(count) 次，运行 \(String(format: "%.1f", elapsed)) 秒，阶段：\(phase)\(transport)）"))
        }
        activeID = nil
        let pending = continuation
        continuation = nil
        deadline?.cancel()
        deadline = nil
        nextSend?.cancel()
        nextSend = nil
        onAcknowledgement = nil
        onRoleChanged = nil
        expectedSerial = nil
        deviceID = ""
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        decoder = ASMFrame.Stream()
        pending?.resume(with: reported)
    }
}

extension HeartbeatProbe: ContinuousHeartbeatSession {
    func runContinuously(host: String, port: UInt16, deviceID: String,
                         onAcknowledgement: @escaping (Int) -> Void,
                         onRoleChanged: @escaping () -> Void) async throws {
        _ = try await run(host: host, port: port, deviceID: deviceID, maximumHeartbeats: nil,
                          onAcknowledgement: onAcknowledgement, onRoleChanged: onRoleChanged)
    }
}
