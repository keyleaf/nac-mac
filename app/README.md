# 原生协议模块

当前有离线协议模块和账号认证联调界面。已接入手动 HTTP 认证请求，尚未完成 SPA 登录后交接、保活和 VPN。

验证：
```sh
xcrun swiftc -module-cache-path /private/tmp/nac-swift-module-cache Sources/NACProtocol/ByteTransform.swift Checks/ByteTransformCheck.swift -o /private/tmp/nac-byte-transform-check
/private/tmp/nac-byte-transform-check
```

协议来源与限制见 ../docs/protocol-notes.md。不要将字节混淆当成安全加密。

## 菜单栏登录联调版

从项目根目录运行：

```sh
bash app/build-preview.sh
open "local/NAC Preview.app"
```

双击预览 app 会显示控制台，关闭窗口后应用继续留在菜单栏。再次双击 app 或选择菜单栏的“打开控制台”会显示同一个窗口。窗口和菜单栏共享内存中的账号及服务器字段；菜单栏的“退出”会结束应用。

先点击“检查服务器 / 复用设备记录”，读取实时配置、公钥及当前 IP 的现有设备记录；不会提交新设备登记。随后由用户输入账号密码，点击“提交账号认证”并确认后，才会发送一次真实认证请求。不会自动重试登录。已有设备状态可能由原客户端维持，不代表本应用已接管连接。

HTTP 认证被接受后，如服务端要求改密、MFA、绑定、重新登记、SPA 或 VPN，界面显示后续步骤未完成，不标记本应用已连接。当前完整接管尚未实现，不能替代原客户端。刷新状态为单次只读查询，不是保活。

密码不写入磁盘、日志、UserDefaults 或 Keychain；提交时清空输入框，处理中仅在请求准备的内存中短暂保留。令牌和 Cookie 只保存在当前进程的 ephemeral URLSession 中；网络重定向被拒绝，不自动将认证请求转发到另一地址。服务器字段也只保存在本次运行的内存中。

当前服务器配置要求 HTTP，联调 bundle 的 ATS 允许 HTTP 访问；HTTPS 仍使用系统证书校验，不提供忽略证书错误的实现。这是应用内的联调配置，未改变系统网络设置。

手动编译脚本使用系统 `swiftc` 生成本机架构的 `local/NAC Preview.app`，最低运行版本为 macOS 15（启动控制 API 的要求），需要含相应 SwiftUI API 的 SDK。该目录受 `.gitignore` 忽略，不会进入版本控制。

控制台使用单个 `Window` 场景，重复打开会复用窗口；禁用窗口恢复，显式处理应用重新打开事件。密码在提交、取消确认或控制台视图消失时清空，不保证 Swift 字符串底层内存被立即覆写。

请求校验模块离线验证：
```sh
xcrun swiftc -module-cache-path /private/tmp/nac-swift-module-cache Sources/NACProtocol/RequestSignature.swift Checks/RequestSignatureCheck.swift -o /private/tmp/nac-signature-check
/private/tmp/nac-signature-check
```

RSA 模块离线验证（临时内存密钥，不联网）：
```sh
xcrun swiftc -module-cache-path /private/tmp/nac-swift-module-cache Sources/NACProtocol/PasswordEncryption.swift Checks/PasswordEncryptionCheck.swift -o /private/tmp/nac-rsa-check
/private/tmp/nac-rsa-check
```

消息头离线验证：
```sh
xcrun swiftc -module-cache-path /private/tmp/nac-swift-module-cache Sources/NACProtocol/FrameHeader.swift Checks/FrameHeaderCheck.swift -o /private/tmp/nac-frame-check
/private/tmp/nac-frame-check
```

SPA 桥接字段离线验证（在 app 目录运行，不联网）：
```sh
xcrun swiftc -parse-as-library -module-cache-path /private/tmp/nac-swift-module-cache Sources/NACProtocol/SPABridgeFields.swift Checks/SPABridgeFieldsCheck.swift -o /private/tmp/nac-spa-fields-check
/private/tmp/nac-spa-fields-check
```

该模块只覆盖网页与原生层之间的字段格式，不是 SPA 报文加密器。

## 协议核心统一离线检查

```sh
bash app/check-protocol.sh
```

脚本编译全部协议模块并依次运行 10 个检查入口，不联网。RSA 检查使用临时内存密钥；若沙箱不允许 Security.framework 生成密钥，需在普通本机终端运行。临时二进制在脚本退出时删除。

当前已实现加密前 SPA 内容、公钥/SHA256/HMAC-SHA256 分支、PKCS1/SPKI 公钥导入、HTTP 自定义 Base64、表单请求构造和登录请求准备。它们不自动发送请求或选用原客户端设备身份。SPA HMAC 密钥及两种用途的 RSA 公钥均由调用者显式提供。

`python3 app/prepare-device-probe.py --server http://192.0.2.10` 从 nac-mac 根目录运行，只准备真实 Mac 设备报告，写入 local/prepared-mac-device-probe.json，不发送请求。不要在用户确认设备登记可能影响当前连接之前提交该文件。请求中的 AgentVersion 为实验客户端自身版本 0.3，未伪装原版版本；服务端是否接受仍待验证。

用户已改选复用现有登记记录；设备报告探针不属于当前联调流程，不执行提交。

`Checks/ServicePreflightCheck.swift` 是显式调用的内网只读检查，不包含在 check-protocol.sh 中。它与 GUI 使用同一 NACService，仅读取配置、记录和状态，不提交凭据、登记或 SPA。

## 状态监测与单次心跳验证

检查服务器后，“开始状态监测”每 30 秒只读查询 device/netStatus；关闭窗口后任务仍运行。停止监测或修改服务器会取消任务。失败显示状态未知，不自动重试账号认证，不把查询流量称为心跳保活。

“单次心跳验证…”需要用户在界面确认后才建立独立 TCP 连接，向已经核对的同服务器 37527 端口发送一个 HeartTest，并等待相同交易名及序列号的响应。最多等待 10 秒，然后关闭本次诊断连接。不更新设备记录，不发送 UpdateAgentInfo，也不执行返回策略。它可能影响同设备原客户端的连接，不能在用户未确认时由自动化触发。

收到匹配帧仅证明传输往返，业务成功和独立保活仍未验证。当前不会自动启动连续心跳、退出原客户端或接管其连接。

离线协议检查现在有 11 个入口，新增 ASMFrameCheck 使用独立 Python zlib 样例，并检查 TCP 分片/合包与错误帧。

```sh
python3 app/check-heartbeat-transport.py
```

从项目根目录运行；该检查只使用 127.0.0.1 的合成服务端，验证正常响应、损坏数据、超时和取消，不接触公司服务器。某些沙箱需允许本机回环连接。

## 连续心跳试验（0.5）

原客户端 HeartTest 接收分支只记录应答序列号，随后以序列号核对超时，不要求额外 RetCode。新增 HeartbeatAcknowledgement 校验 XML 中根节点直属的唯一 TradeCode=HeartTest；拒绝 DTD、实体声明、畸形 XML、重复字段及注释伪造。仅凭帧头匹配仍不足以通过新版检查。

“开启连续心跳…”由用户确认后启动同一 TCP 连接，收到合法 XML 和匹配序列号后等待 30 秒再发下一次。显示应答次数和时间，关闭窗口仍运行；“停止连续心跳”立即取消任务及本应用连接。应答超时、远端关闭、异常数据或非心跳消息会停止，不自动重连或重登、不执行策略、不发送设备更新。服务端是否独立维持放行仍待受控验证，计数增长不自动改为已独立入网。

回环测试已覆盖同连接连续三次无额外结果码的应答；离线协议检查现在为 12 个。真实服务器目前只由用户验证了旧版单次帧往返，连续试验需要用户在界面开启，原客户端先保留。

## 窗口与心跳诊断修订（0.6）

控制台打开或再次唤起时使用 regular activation policy，显示 Dock 图标并支持 Command-Tab；控制台关闭时切回 accessory，只留菜单栏。最小化不触发关闭，仍可切换应用。LSUIElement 仍保留为初始菜单栏身份，窗口挂接的观察器负责动态切换；菜单栏弹窗不会触发该切换。

心跳间隔按上一次发送的单调时钟时间计算，而非等应答后再额外等满 30 秒。失败信息保留已应答次数、运行秒数、所在阶段与可用网络错误，明确区分正常 EOF 和接收错误；没有自动重连。新增回环场景验证应答一次后对端关闭，诊断仍显示一次应答和等待下次心跳阶段。真实服务器关闭原因尚未确定，需用户重测；本次没有自动访问真实心跳端点。

0.7 增加非心跳帧的交易名、XML 交易名、序列号、字节数及白名单控制摘要，并提供“复制心跳诊断”。未知消息仍停止处理，不忽略服务端策略。无密码的有限真实诊断不能复现用户重新认证后出现的消息，需要按同一用户操作路径获取类型；本版不宣称已解决该推送分支。


0.8：RoleChanged 通知不会直接终止连续心跳，会刷新配置及设备状态并显示策略处理尚未接通。仍需保留原客户端；未知控制消息仍停止。请勿将设备在线或心跳应答视为已完全替代原客户端。
