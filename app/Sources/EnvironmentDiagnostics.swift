import AppKit
import Network

/// Observes OS events only; does not probe servers, read SSIDs, or reconnect sessions.
@MainActor final class EnvironmentDiagnostics {
    private let monitor = NWPathMonitor()
    private var observers: [NSObjectProtocol] = []
    func start() {
        DiagnosticLog.shared.record(.appStarted)
        let events: [(Notification.Name, DiagnosticLog.Event)] = [
            (NSWorkspace.willSleepNotification, .systemSleep), (NSWorkspace.didWakeNotification, .systemWake),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionInactive),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionActive)
        ]
        for (name, event) in events {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                DiagnosticLog.shared.record(event)
            })
        }
        monitor.pathUpdateHandler = { path in
            let state: String
            switch path.status {
            case .satisfied: state = "satisfied"
            case .unsatisfied: state = "unsatisfied"
            case .requiresConnection: state = "requiresConnection"
            @unknown default: state = "unknown"
            }
            let types: [(NWInterface.InterfaceType, String)] = [(.wifi, "wifi"), (.wiredEthernet, "wiredEthernet"), (.cellular, "cellular"), (.loopback, "loopback"), (.other, "other")]
            let interfaces = types.filter { path.usesInterfaceType($0.0) }.map { $0.1 }.joined(separator: ",")
            DiagnosticLog.shared.record(.networkChanged, [.path: state, .interfaces: interfaces, .expensive: path.isExpensive ? "1" : "0"])
        }
        monitor.start(queue: DispatchQueue(label: "io.github.keyleaf.nac-mac.path-observer"))
    }
    func stop() {
        monitor.cancel()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        DiagnosticLog.shared.record(.appTerminated)
        DiagnosticLog.shared.flush()
    }
}
