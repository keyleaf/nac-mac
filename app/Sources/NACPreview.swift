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
            StatusLabel()
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

struct StatusLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label("NAC 小助手", systemImage: "network")
            .onReceive(NotificationCenter.default.publisher(for: PreviewAppDelegate.reopenConsole)) { _ in
                openWindow(id: "main")
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
    }
}

@MainActor
final class PreviewModel: ObservableObject {
    @Published var account = ""
    @Published var password = ""
    @Published var server = ""
    @Published var showSettings = false
    @Published var confirmLogin = false
    @Published var isBusy = false
    @Published var ready = false
    @Published var verificationCode = ""
    @Published var status = "尚未检查"
    @Published var authenticationStatus = "未提交"
    @Published var deviceStatus = "未查询"
    @Published var detail = "先检查服务器，将复用当前 IP 的设备记录，不提交新登记。"
    @Published var confirmHeartbeat = false
    @Published var confirmContinuousHeartbeat = false
    @Published var heartbeating = false
    @Published var heartbeatStatus = "连续心跳未开启"
    @Published var monitoring = false
    @Published var lastStatusCheck = "尚未检查"
    private var monitorTask: Task<Void, Never>?
    private let heartbeat = HeartbeatProbe()
    private var heartbeatTask: Task<Void, Never>?
    private var heartbeatGeneration = UUID()
    private var roleRefreshTask: Task<Void, Never>?
    @Published var roleChangeStatus = ""
    private var service: NACService?

    func invalidate() {
        stopHeartbeat()
        stopMonitoring()
        service = nil
        ready = false
        password = ""
        status = "尚未检查"
        authenticationStatus = "未提交"
        deviceStatus = "未查询"
        detail = "服务器已更改，请重新检查。"
    }
    func checkServer() {
        guard !isBusy else { return }
        stopHeartbeat()
        stopMonitoring()
        isBusy = true
        ready = false
        status = "检查中"
        authenticationStatus = "未提交"
        Task {
            defer { isBusy = false }
            do {
                let client = try NACService(server: server)
                let device = try await client.prepare()
                service = client
                ready = true
                status = "可以测试账号认证"
                detail = "复用现有记录（系统：\(device.recordedOS)，登记状态：\(device.registered)）。未修改服务器登记信息。"
                do { deviceStatus = try await client.status(); recordCheck() }
                catch { deviceStatus = "状态查询失败" }
            } catch { fail(error) }
        }
    }
    func refreshStatus() {
        guard let service, !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do { deviceStatus = try await service.status(); recordCheck() }
            catch { fail(error) }
        }
    }
    private func recordCheck() {
        lastStatusCheck = Date().formatted(date: .omitted, time: .standard)
    }
    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        monitoring = false
    }
    func toggleMonitoring() {
        if monitoring { stopMonitoring(); return }
        guard let client = service, ready, !isBusy else { return }
        monitoring = true
        monitorTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, !Task.isCancelled, self.service === client else { return }
                if self.isBusy { continue }
                do {
                    let state = try await client.status()
                    guard !Task.isCancelled, self.service === client else { return }
                    failures = 0
                    self.deviceStatus = state
                    self.recordCheck()
                } catch {
                    guard !Task.isCancelled, self.service === client else { return }
                    failures += 1
                    self.deviceStatus = "状态未知（失败 \(failures) 次）"
                    self.recordCheck()
                }
            }
        }
    }
    func probeHeartbeat() {
        guard !heartbeating else { return }
        guard let service, let device = service.device, let host = service.origin.host,
              let port = service.heartbeatPort, port == 37527, ready, !isBusy else {
            detail = "尚未确认可用的心跳端点，请先检查服务器。"
            return
        }
        stopMonitoring()
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let reply = try await heartbeat.run(host: host, port: port, deviceID: device.id)
                detail = "已验证 \(reply.trade) XML 和响应序列号（\(reply.payloadBytes) 字节）。原版心跳不要求额外结果码；独立运行仍待验证。"
            } catch {
                detail = (error as? HeartbeatProbe.Failure)?.message ?? "心跳验证已取消或失败。"
            }
        }
    }
    func stopHeartbeat() {
        heartbeatGeneration = UUID()
        roleRefreshTask?.cancel()
        roleRefreshTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        heartbeating = false
        heartbeatStatus = "连续心跳已停止"
    }
    func startHeartbeat() {
        guard !heartbeating, ready, !isBusy, let service, let device = service.device,
              let host = service.origin.host, let port = service.heartbeatPort, port == 37527 else { return }
        heartbeating = true
        let generation = UUID()
        heartbeatGeneration = generation
        let connection = HeartbeatProbe()
        roleChangeStatus = ""
        heartbeatStatus = "建立心跳连接，独立运行待验证"
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await connection.run(host: host, port: port, deviceID: device.id,
                    maximumHeartbeats: nil, onAcknowledgement: { [weak self] count in
                        guard self?.heartbeatGeneration == generation else { return }
                        self?.heartbeatStatus = "心跳已应答 \(count) 次 · \(Date().formatted(date: .omitted, time: .standard))"
                    }, onRoleChanged: { [weak self] in
                        self?.refreshRole(service: service, generation: generation)
                    })
            } catch is CancellationError {
                guard self.heartbeatGeneration == generation else { return }
                self.heartbeatStatus = "连续心跳已停止"
            } catch {
                guard self.heartbeatGeneration == generation else { return }
                self.heartbeatStatus = (error as? HeartbeatProbe.Failure)?.message ?? "心跳异常，已停止"
            }
            guard self.heartbeatGeneration == generation else { return }
            self.heartbeating = false
            self.roleRefreshTask?.cancel()
            self.roleRefreshTask = nil
        }
    }
    private func refreshRole(service: NACService, generation: UUID) {
        guard heartbeatGeneration == generation else { return }
        roleChangeStatus = "收到角色变更；策略处理待接通，请保留原客户端。"
        guard roleRefreshTask == nil else { return }
        roleRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.heartbeatGeneration == generation { self.roleRefreshTask = nil } }
            do {
                let refreshed = try await service.refreshAfterRoleChange()
                guard self.heartbeatGeneration == generation, self.service === service else { return }
                self.deviceStatus = refreshed
                self.recordCheck()
                self.roleChangeStatus = "角色变更：配置与状态已刷新；策略处理待接通，请保留原客户端。"
            } catch {
                guard self.heartbeatGeneration == generation else { return }
                self.roleChangeStatus = "角色变更后刷新失败：\(error.localizedDescription)；请保留原客户端。"
                self.stopHeartbeat()
            }
        }
    }
    func submitLogin() {
        guard let service, ready, !isBusy else { return }
        let submittedPassword = password
        password = ""
        let submittedAccount = account
        let code = verificationCode
        isBusy = true
        status = "正在认证"
        authenticationStatus = "认证中"
        Task {
            defer { isBusy = false }
            do {
                let result = try await service.login(account: submittedAccount, password: submittedPassword, verificationCode: code)
                status = result.requiresFurtherAction ? "认证后仍需后续步骤" : "账号认证已受理"
                authenticationStatus = result.requiresFurtherAction ? "受理，待后续" : "已受理"
                detail = result.message
                do { deviceStatus = try await service.status(); recordCheck() }
                catch { deviceStatus = "认证后状态待确认" }
            } catch { authenticationStatus = "未完成"; fail(error) }
        }
    }
    private func fail(_ error: Error) {
        status = "操作未完成"
        if let error = error as? NACService.Failure { detail = error.message }
        else if error is LoginPreparation.Failure { detail = "输入为空，或密码含尚未验证兼容性的非 BMP 字符。未完成认证。" }
        else { detail = "请求、配置解析或加密失败。请确认公司内网和服务器地址后重试。" }
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
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.status).font(.headline)
                    Text("公司内网认证").font(.caption).foregroundStyle(.secondary)
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
                summary(title: "账号认证", value: model.authenticationStatus, detail: "不代表已独立入网")
                summary(title: "设备状态", value: model.deviceStatus, detail: "在线状态可能由原客户端维持")
            }

            VStack(alignment: .leading, spacing: 13) {
                Label("账号登录", systemImage: "person.crop.circle")
                    .font(.headline)
                TextField("公司账号", text: $model.account)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isBusy)
                SecureField("密码", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isBusy || !model.ready)
                TextField("验证码（服务端要求时填写）", text: $model.verificationCode)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isBusy)
                Button("检查服务器 / 复用设备记录") { model.checkServer() }
                    .disabled(model.isBusy)
                Button {
                    model.confirmLogin = true
                } label: {
                    Text("提交账号认证")
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
                Button(monitoringTitle) { model.toggleMonitoring() }
                    .disabled(!model.ready || model.isBusy)
                Button("单次心跳验证…") { model.confirmHeartbeat = true }
                    .disabled(!model.ready || model.isBusy || model.heartbeating)
            }
            HStack {
                Button(model.heartbeating ? "停止连续心跳" : "开启连续心跳…") {
                    if model.heartbeating { model.stopHeartbeat() }
                    else { model.confirmContinuousHeartbeat = true }
                }
                .disabled(!model.heartbeating && (!model.ready || model.isBusy))
            }
            if !model.roleChangeStatus.isEmpty {
                Text(model.roleChangeStatus).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(model.heartbeatStatus).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("复制心跳诊断") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.heartbeatStatus, forType: .string)
            }
            .font(.caption)
            Text("状态更新时间：\(model.lastStatusCheck) · 监测间隔 30 秒；状态查询不等于保活")
                .font(.caption).foregroundStyle(.secondary)

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
            Text(model.detail)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button("复制请求诊断") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.detail, forType: .string)
            }
            .font(.caption)
            Text("密码不保存。设备在线不代表本应用已接管保活；SPA / VPN 交接尚未接通。")
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
        .onChange(of: model.server) { _, _ in model.invalidate() }
        .sheet(isPresented: $model.showSettings) {
            VStack(alignment: .leading, spacing: 15) {
                Text("服务器设置").font(.title2.bold())
                TextField("认证服务器地址", text: $model.server)
                    .textFieldStyle(.roundedBorder)
                Text("设置只保存在本次运行。检查及认证请求将发送到此服务器。")
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
            Text("将向 \(model.server) 提交账号及加密密码，并复用已有设备记录。可能改变现有会话、影响原客户端连接。本轮不提交新设备登记。")
        }
        .confirmationDialog("单次心跳验证", isPresented: $model.confirmHeartbeat, titleVisibility: .visible) {
            Button("建立连接并发送一次心跳") { model.probeHeartbeat() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将向当前服务器的 37527 端口建立独立 TCP 连接，为复用记录发送一次 HeartTest。可能影响原客户端连接。不会更新设备信息或执行服务器策略，收到匹配帧也不等于独立保活已成功。")
        }
        .confirmationDialog("开启连续心跳试验", isPresented: $model.confirmContinuousHeartbeat, titleVisibility: .visible) {
            Button("开启 30 秒间隔心跳") { model.startHeartbeat() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将保持同一 TCP 连接，每次收到匹配的 HeartTest XML 与序列号后等待 30 秒再发送。可能影响原客户端；关闭窗口不会停止，可随时点击停止。超时或收到非心跳消息时停止，不自动重连、重新认证或执行策略。请先保留原客户端。")
        }
    }

    private var monitoringTitle: String { model.monitoring ? "停止状态监测" : "开始状态监测" }

    private func summary(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(size: 23, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(card, in: RoundedRectangle(cornerRadius: 16))
    }
}
