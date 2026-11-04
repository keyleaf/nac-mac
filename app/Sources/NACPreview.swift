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
                .frame(width: 490, height: 560)
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


private enum AppMetadata {
    static var version: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return "开发版" }
        return "v" + value
    }
}

struct MenuPanel: View {
    @EnvironmentObject private var model: PreviewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(model.connectionState.tint)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.status).font(.headline)
                    if !model.account.isEmpty {
                        Text(model.account).font(.callout).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    if let last = model.lastHeartbeat, model.heartbeatCount > 0 {
                        Text("心跳 \(model.heartbeatCount) 次 · 最近 \(last.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(model.connectionHint).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            Divider()

            Button {
                NSApplication.shared.setActivationPolicy(.regular)
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Text("打开窗口")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack {
                Text(AppMetadata.version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
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
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Label("认证服务器", systemImage: "server.rack")
                            .font(.subheadline)
                        Spacer(minLength: 4)
                        Button("设置") { model.openSettings() }
                            .controlSize(.small)
                            .disabled(model.isBusy)
                    }
                    Text(model.server.isEmpty ? "未配置，请先设置" : model.server)
                        .font(.callout)
                        .foregroundStyle(model.server.isEmpty ? Color.orange : Color.primary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    HStack {
                        Label("设备信息", systemImage: "laptopcomputer")
                        Spacer(minLength: 4)
                        Button("查看") { model.openDeviceInfo() }
                            .controlSize(.small)
                    }.font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(15)
                .background(card, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 13) {
                if model.authenticationAccepted && !model.editingCredentials {
                    Text(model.status)
                        .font(.title2.bold())
                        .foregroundStyle(model.connectionState.tint)
                    Text(model.heartbeatCount > 0 ? model.heartbeatSummary : model.connectionHint)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("重新登录") {
                            if model.hasSavedPassword || !model.password.isEmpty { model.confirmLogin = true }
                            else { model.editingCredentials = true }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                        Button("编辑账号") { model.editingCredentials = true }
                            .disabled(model.isBusy)
                        Spacer()
                        Button(model.heartbeating ? "停止连接" : "重新连接") {
                            if model.heartbeating { model.stopHeartbeat() }
                            else { model.startHeartbeat() }
                        }
                        .disabled(!model.heartbeating && !model.canStartHeartbeat)
                    }
                } else {
                Label("账号登录", systemImage: "person.crop.circle")
                    .font(.headline)
                TextField("公司账号", text: $model.account)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isBusy)
                SecureField(model.hasSavedPassword ? "已保存密码，留空即可使用" : "密码", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isBusy)
                Toggle("记住密码", isOn: Binding(
                    get: { model.rememberPassword },
                    set: { enabled in
                        model.rememberPassword = enabled
                        if !enabled { model.forgetPassword() }
                    }))
                    .toggleStyle(.checkbox)
                    .disabled(model.isBusy)
                if !model.credentialNotice.isEmpty {
                    Text(model.credentialNotice).font(.caption).foregroundStyle(.secondary)
                }
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
                    Text(model.authenticationAccepted ? "重新登录" : "登录")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.ready || model.isBusy || model.account.isEmpty || (model.password.isEmpty && !model.hasSavedPassword))
                if model.authenticationAccepted {
                    Button("返回连接状态") {
                        model.password = ""
                        model.editingCredentials = false
                    }.disabled(model.isBusy)
                }
                }
            }
            .padding(17)
            .background(card, in: RoundedRectangle(cornerRadius: 16))

            DisclosureGroup("连接诊断") {
                VStack(alignment: .leading, spacing: 12) {
                    if !model.roleChangeStatus.isEmpty {
                        Text(model.roleChangeStatus).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(model.heartbeatStatus).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("账号认证：\(model.authenticationStatus)").font(.caption)
                    HStack {
                        Text("设备记录：\(model.deviceStatus)").font(.caption)
                        Spacer()
                        Button("刷新设备状态") { model.refreshStatus() }
                            .disabled(!model.ready || model.isBusy)
                    }
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

        }
        .padding(22)
        }
        .preferredColorScheme(.dark)
        .background(Color(red: 0.105, green: 0.12, blue: 0.115))
        .background(ConsoleWindowPresence().frame(width: 0, height: 0))
        .onDisappear { model.password = "" }
        .onChange(of: model.authenticationAccepted) { _, accepted in
            if accepted { model.editingCredentials = false }
        }
        .sheet(isPresented: $model.showDeviceInfo) {
            DeviceInformationView().environmentObject(model)
        }
        .sheet(isPresented: $model.showSettings) {
            VStack(alignment: .leading, spacing: 15) {
                Text("服务器设置").font(.title2.bold())
                TextField("认证服务器地址", text: $model.serverDraft)
                    .textFieldStyle(.roundedBorder)
                Text("保存后自动检查服务器，重启后保留此地址。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.settingsError.isEmpty {
                    Text(model.settingsError).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("取消", role: .cancel) { model.showSettings = false }
                    Button("保存") { model.saveServerSettings() }
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


}

struct DeviceInformationView: View {
    @EnvironmentObject private var model: PreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("设备信息").font(.title2.bold())
                Spacer()
                Button("完成") { model.showDeviceInfo = false }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("当前 Mac") {
                        VStack(alignment: .leading, spacing: 10) {
                            row("电脑名称", model.localDevice.name)
                            row("硬件型号", model.localDevice.model)
                            row("系统", model.localDevice.system)
                            if model.localDevice.addresses.isEmpty {
                                row("IPv4 网络", "未获取到活动地址")
                            }
                            ForEach(model.localDevice.addresses) { address in
                                Divider()
                                row("网卡", address.interface)
                                row("IPv4", address.ip)
                                row("网卡 MAC", address.mac)
                            }
                        }
                    }
                    section("服务器登记资料") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let device = model.deviceRecord {
                                row("设备名称", device.name)
                                row("设备 ID", device.id)
                                row("登记系统", device.recordedOS)
                                row("登记状态", device.registrationDescription)
                                row("登记 IP", device.ip)
                                row("登记 MAC", device.mac)
                                row("部门", device.department)
                                row("位置", device.location)
                                Text("来自最近一次设备检查。当前复用已有记录，登记资料可能与这台 Mac 不同。")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("检查服务器后显示对应的设备登记资料。")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            HStack {
                Button("刷新本机信息") { model.refreshLocalDeviceInfo() }
                Spacer()
                Text("仅展示，不更新服务器登记。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 480, height: 570)
        .preferredColorScheme(.dark)
        .background(Color(red: 0.105, green: 0.12, blue: 0.115))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
            Text(value.isEmpty ? "未提供" : value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }.font(.callout)
    }
}
