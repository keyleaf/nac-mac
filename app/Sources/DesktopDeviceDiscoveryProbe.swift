import Foundation
import Network

/// One connection and one report per explicitly confirmed diagnostic.
@MainActor
final class DesktopDeviceDiscoveryProbe {
    enum Failure: LocalizedError {
        case unavailable, timedOut, closed, malformed

        var errorDescription: String? {
            switch self {
            case .unavailable: return "桌面设备识别的 TCP 连接或传输失败。"
            case .timedOut: return "等待桌面设备识别响应超时。"
            case .closed: return "服务器关闭了 TCP 连接，未收到完整的桌面识别响应。"
            case .malformed: return "桌面设备识别响应格式异常。"
            }
        }
    }

    private var connection: NWConnection?
    private var continuation: CheckedContinuation<DesktopDeviceDiscovery.Reply, Error>?
    private var deadline: Task<Void, Never>?
    private var stream = ASMFrame.Stream()

    func run(host: String, port: UInt16, report: MacDeviceReport,
             serial: UInt32) async throws -> DesktopDeviceDiscovery.Reply {
        try Task.checkCancellation()
        guard connection == nil, let endpointPort = NWEndpoint.Port(rawValue: port), port != 0 else {
            throw Failure.unavailable
        }
        let frame = try DesktopDeviceDiscovery.firstReport(report, serial: serial)
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.connection = connection
                self.continuation = continuation
                stream = ASMFrame.Stream()
                deadline = Task { [weak self, weak connection] in
                    do { try await Task.sleep(for: .seconds(12)) }
                    catch { return }
                    guard let self, let connection, self.connection === connection else { return }
                    self.finish(.failure(Failure.timedOut))
                }
                connection.stateUpdateHandler = { [weak self, weak connection] state in
                    Task { @MainActor in
                        guard let self, let connection, self.connection === connection else { return }
                        switch state {
                        case .ready:
                            guard connection.stateUpdateHandler != nil else { return }
                            connection.stateUpdateHandler = nil
                            connection.send(content: frame, completion: .contentProcessed { [weak self, weak connection] error in
                                Task { @MainActor in
                                    guard let self, let connection, self.connection === connection else { return }
                                    if error != nil { self.finish(.failure(Failure.unavailable)) }
                                    else { self.receive(on: connection, serial: serial) }
                                }
                            })
                        case .waiting, .failed, .cancelled:
                            self.finish(.failure(Failure.unavailable))
                        default:
                            break
                        }
                    }
                }
                connection.start(queue: .main)
            }
        } onCancel: {
            Task { @MainActor in
                guard self.connection === connection else { return }
                self.finish(.failure(CancellationError()))
            }
        }
    }

    private func receive(on connection: NWConnection, serial: UInt32) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self, weak connection] data, _, complete, error in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                do {
                    if let data, let message = try self.stream.feed(data).first {
                        let reply = try DesktopDeviceDiscovery.reply(from: message, serial: serial)
                        self.finish(.success(reply))
                    } else if error != nil {
                        self.finish(.failure(Failure.unavailable))
                    } else if complete {
                        self.finish(.failure(Failure.closed))
                    } else {
                        self.receive(on: connection, serial: serial)
                    }
                } catch let error as DesktopDeviceDiscovery.Failure {
                    self.finish(.failure(error))
                } catch {
                    self.finish(.failure(Failure.malformed))
                }
            }
        }
    }

    private func finish(_ result: Result<DesktopDeviceDiscovery.Reply, Error>) {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        deadline?.cancel()
        deadline = nil
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}
