import SwiftUI
import AppKit
import Combine

@main
struct NACPreviewApp: App {
    @StateObject private var model = PreviewModel()
    @NSApplicationDelegateAdaptor(PreviewAppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("NAC 小助手", id: "main") {
            ConsoleView()
                .environmentObject(model)
                .frame(width: 490, height: 750)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            MenuPanel()
                .environmentObject(model)
                .frame(width: 280)
        } label: {
            StatusLabel().environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class PreviewAppDelegate: NSObject, NSApplicationDelegate {
    static let reopenConsole = Notification.Name("NACPreview.reopenConsole")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 26, yRadius: 26).fill()
            let configuration = NSImage.SymbolConfiguration(paletteColors: [.white])
            NSImage(systemSymbolName: "network", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)?
                .draw(in: NSRect(x: 24, y: 24, width: 80, height: 80))
            return true
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.setActivationPolicy(.regular)
        NotificationCenter.default.post(name: Self.reopenConsole, object: nil)
        return false
    }
}

/// Only the console window controls Dock / Command-Tab presence; the menu popover does not.
struct ConsoleWindowPresence: NSViewRepresentable {
    func makeNSView(context: Context) -> PresenceView { PresenceView() }
    func updateNSView(_ nsView: PresenceView, context: Context) {}
    final class PresenceView: NSView {
        private weak var tracked: NSWindow?
        private var closeObserver: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, tracked !== window else { return }
            if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
            tracked = window
            NSApplication.shared.setActivationPolicy(.regular)
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                object: window, queue: .main) { _ in
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
        }
        deinit {
            if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        }
    }
}

private extension ConnectionState {
    var tint: Color {
        switch self {
        case .connected: return .green
        case .interrupted: return .red
        case .needsAction, .stopped: return .orange
        case .checking, .authenticating, .connecting: return .blue
        case .notLoggedIn: return .secondary
        }
    }
}

struct StatusLabel: View {
    @EnvironmentObject private var model: PreviewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label("NAC 小助手", systemImage: "network")
            .help(model.status)
            .onReceive(NotificationCenter.default.publisher(for: PreviewAppDelegate.reopenConsole)) { _ in
                openWindow(id: "main")
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
    }
}


struct MenuPanel: View {
    @EnvironmentObject private var model: PreviewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(model.connectionState.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.status).font(.headline)
                    Text(model.connectionHint).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            HStack {
                Label("账号", systemImage: "person")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.account.isEmpty ? "未填写" : model.account)
                    .lineLimit(1)
            }
            .font(.callout)

            Button {
                NSApplication.shared.setActivationPolicy(.regular)
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("打开控制台", systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Divider()

            HStack {
                Text("登录联调版")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .preferredColorScheme(.dark)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ConsoleView: View {
    @EnvironmentObject private var model: PreviewModel
    private let card = Color.white.opacity(0.055)

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NAC 小助手").font(.title2.bold())
                    Text(model.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("联调")
                    .font(.caption)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.08), in: Capsule())
            }

            HStack(spacing: 12) {
                summary(title: "连接状态", value: model.status, detail: model.connectionHint, tint: model.connectionState.tint)
                summary(title: "设备记录", value: model.deviceStatus, detail: "服务器记录，不代表本应用已连接")
            }

            VStack(alignment: .leading, spacing: 13) {
                Label("账号登录", systemImage: "person.crop.circle")
                    .font(.headline)
                TextField("公司账号", text: $model.account)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isBusy)
                SecureField("密码", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isBusy)
                TextField("验证码（服务端要求时填写）", text: $model.verificationCode)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isBusy)
                HStack {
                    Button(model.checkingServer ? "正在检查…" : "检查服务器 / 复用设备记录") { model.checkServer() }
                        .disabled(model.isBusy)
                    if model.checkingServer {
                        ProgressView().controlSize(.small)
                        Button("取消检查") { model.cancelServerCheck() }
                    }
                }
                Text(model.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    model.confirmLogin = true
                } label: {
                    Text("登录并连接")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.ready || model.isBusy || model.account.isEmpty || model.password.isEmpty)
            }
            .padding(17)
            .background(card, in: RoundedRectangle(cornerRadius: 16))

            HStack {
                Button(model.heartbeating ? "停止连接" : "重新连接") {
                    if model.heartbeating { model.stopHeartbeat() }
                    else { model.startHeartbeat() }
                }
                .disabled(!model.heartbeating && !model.canStartHeartbeat)
                Text(model.heartbeatStatus)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.roleChangeStatus.isEmpty {
                Text(model.roleChangeStatus).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("连接诊断") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("账号认证：\(model.authenticationStatus)").font(.caption)
                    HStack {
                        Button(monitoringTitle) { model.toggleMonitoring() }
                            .disabled(!model.ready || model.isBusy)
                        Button("单次心跳验证…") { model.confirmHeartbeat = true }
                            .disabled(!model.ready || model.isBusy || model.heartbeating)
                    }
                    Text("状态更新时间：\(model.lastStatusCheck) · 状态监测仅查询服务器记录")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("复制心跳诊断") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.heartbeatStatus, forType: .string)
                    }
                    Button("复制请求诊断") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.detail, forType: .string)
                    }
                }.padding(.top, 8)
            }

            VStack(spacing: 11) {
                HStack {
                    Label("认证服务器", systemImage: "server.rack")
                    Spacer()
                    Text(model.server.isEmpty ? "尚未设置" : model.server)
                        .lineLimit(1)
                }
                Divider()
                HStack {
                    Label("本机网络", systemImage: "globe")
                    Spacer()
                    Button("刷新设备状态") { model.refreshStatus() }.disabled(!model.ready || model.isBusy)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(15)
            .background(card, in: RoundedRectangle(cornerRadius: 16))

            HStack {
                Button {
                    model.showSettings = true
                } label: {
                    Label("服务器设置", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .disabled(model.isBusy)
                Spacer()
                Text("关闭窗口后，菜单栏仍保留")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            Text("密码不保存。连接状态依据本应用心跳，访问权限以服务器策略为准。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        }
        .preferredColorScheme(.dark)
        .background(Color(red: 0.105, green: 0.12, blue: 0.115))
        .background(ConsoleWindowPresence().frame(width: 0, height: 0))
        .onDisappear { model.password = "" }
        .sheet(isPresented: $model.showSettings) {
            VStack(alignment: .leading, spacing: 15) {
                Text("服务器设置").font(.title2.bold())
                TextField("认证服务器地址", text: $model.server)
                    .textFieldStyle(.roundedBorder)
                Text("检查时会保存有效的服务器地址，重启后自动填入。账号密码不保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("完成") { model.showSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
            .frame(width: 360)
            .preferredColorScheme(.dark)
        }
        .alert("提交账号认证？", isPresented: $model.confirmLogin) {
            Button("取消", role: .cancel) { model.password = "" }
            Button("提交认证") { model.submitLogin() }
        } message: {
            Text("将向 \(model.server) 提交账号及加密密码，并复用已有设备记录。可能改变现有会话、影响原客户端连接。认证完成后会自动建立心跳连接，关闭窗口仍保持。")
        }
        .confirmationDialog("单次心跳验证", isPresented: $model.confirmHeartbeat, titleVisibility: .visible) {
            Button("建立连接并发送一次心跳") { model.probeHeartbeat() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将向当前服务器的 37527 端口建立独立 TCP 连接，为复用记录发送一次 HeartTest。可能影响原客户端连接。不会更新设备信息或执行服务器策略，收到匹配帧也不等于独立保活已成功。")
        }
    }

    private var monitoringTitle: String { model.monitoring ? "停止状态监测" : "开始状态监测" }

    private func summary(title: String, value: String, detail: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(size: 23, weight: .semibold)).foregroundStyle(tint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(card, in: RoundedRectangle(cornerRadius: 16))
    }
}
