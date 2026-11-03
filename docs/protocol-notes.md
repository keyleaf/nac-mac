# 协议调查：静态初稿

状态：候选规格，未经过真实请求验证，不能据此声称认证可用。

## 已追踪的调用

`createNSTimerForHeart` → `timerFired:` → 非主线程分支调用 `Singleton.longConnectToSocket`。主线程分支转入异步 block，block 内部尚未验证。

`longConnectToSocket` 构造声明 GBK 编码的 XML，含 ASM、TradeCode、AgentID、requestClientType=mobile；以 HeartTest 名称交给 `sub_1000a4778`，再进入 `sub_1000a4f18` 的发送路径。格式字符串存在不证明实际编码已验证，TradeCode/AgentID 的最终填充值待查。

证据：ev_7aea36515893702089a5c9fc559d75761b3338e86287bd2631f815645e0b87b9、ev_a29955608936128a28f892e61a24455f035a827d5efc2f2b52291f4a2159370f。

## TCP 帧候选

发送函数分配消息，负载放在偏移 0x3c（60 字节）以后，随后调用 send。观察到头字段写入：总长度、常量 0x354d5341（小端字节为 ASM5）、偏移 0x14 的 32 字节交易名、偏移 0x34 的参数。部分字段类型及寄存器参数恢复不完整，不能直接实现编码器。

负载先经过一个压缩候选包装函数，再经过循环字节变换；交易名也经过相同变换。字节变换伪代码含缺失寄存器及内联 ARM64 指令，算法尚未确认，不应称为已破解或直接按伪代码实现。

证据：ev_43cd7a5479887db0902936777aa0e8ca8c5ce64748c746321dd50f4f7c9268e2、ev_ce9e138f1bbc588d39cd761f2d0c7ffc3296902e03e47714427dc86dce54e0c3、ev_45adce1a070494aa7664973d09f04a0cd6e94f9ba86553ce39dc362d24a0c311。

## HTTP 状态路径

- `getNetStatusWithCallback:` POST 到 UrlHelper 生成的地址，参数含 deviceId。
- 地址格式包含 `/a/ajax.php?tradecode=get_netstatus&data_type=json&deviceId=...&ip=...&mac=...`。
- `getDeviceAuthStatus:` POST 到 `/access/1.0/ios/json/device/netStatus`，带 deviceId、local_lguage_set、cache 查询参数和生成的请求头。
- 一个名为 getAccessToken 的方法读取本地 Token 并放入 Web-Token 请求头，实际调用的是 getNetProxyConfigUrl；不能仅按方法名推断为登录取令牌。
- getNetStatusUrl 的静态实现根据 IPv4 分段构造 ff:xx:xx:xx:xx:00 格式字段。它不是已确认的真实网卡 MAC，也不是新客户端应直接仿照的设备身份规则。

证据：ev_da982add57644d43bf987408c5039c44c372c9797505b3aa6c9efda033e17401、ev_b05a84de62c0fb6cc79838a8545b93063913bc77f8d8ffd1ff9747881f55787c、ev_81b122b29245290f035e4b0d73967ec81dcc6ee123e3fb41c2ca06eaeb12820b、ev_26a988aac01cf1b0763250e42ed7041003b55069a12cdff71a6dcb22bf25758e、ev_745a8bb655be73e59ad888d812308440c5783a2644874d349038c893a4da789d。

## 尚未解决

1. 账号密码登录真正入口、密码处理和服务端校验。
2. 完整帧结构、变换算法、接收解码与响应码。
3. 定时器间隔、失败恢复和会话退出。
4. 设备标识来源及服务器要求；不得伪造合规结果。
5. 实际使用是否依赖 VPN。MainViewController.connection 的伪代码访问 providerManager 并加载 preferences，但这不是当前路径使用 VPN 的证据。

## 下一轮

读取消息变换函数 ARM64 汇编，追踪账号提交入口及接收分发。取得完整规格后才编写网络协议实现；当前不向服务器发送探测请求、不操作原客户端登录状态。

## 汇编确认与首个 Swift 模块

`0x10000d0b4` 指令确认：取输入字节，与循环密钥字节 XOR，交换高低 4 位，写回。逆变换顺序相反。已在 app/Sources/NACProtocol/ByteTransform.swift 实现，离线检查通过固定向量、全部 256 字节值在 6 种密钥对齐位置的往返、空输入。没有实际服务端互操作验证。

帧头汇编确认：偏移 0 总长度 UInt32，4 为 ASM5，8 为第 6 个参数 UInt32，12 和 16 分别写入 1，20..51 为变换后的交易名，52 为第 7 个参数 UInt32，56 为未压缩长度 UInt32。字段语义、接收方向与边界待验证。证据 ev_659dc5254426e216d98baa15925b9ba38e0e054c91f5bdb507409ddef00d2ee7。

## 网页账号认证入口（静态证据）

包内 dist/static/js/323.c5262e28.js 和 app.f99480de.js 含 webpack eval 模块及内嵌 source map。仅 JSON 解码提取文字，未执行目标脚本。原始提取位于 local/web-source，部分 sourcesContent 位于 local/recovered-sources。

账号表单提交：先 auth/config（username Base64）检查强制改密，再调用 knockPort；成功后 userAuth → auth/index。用户名 user_name Base64，password 经 rsaEncrypt；其实现、密钥、填充方式仍待查。还含 deviceid、验证码、idp/tokenId、autoAuth、hintOver、isRecord、callform、is_mobile 等参数，不能假设全为可省略字段。

URL helper 生成 host/access/1.0/{osType}/{json}/路径，同时追加固定参数。不能把 ios 路径直接硬编码为 Mac 兼容接口。请求体为 form-urlencoded。请求拦截器生成 Session-Num，并设置 Extend-Data、Serial-Num、可选 Web-Token 和 Device-DiskId。Session-Num 的候选算法对拼接后的路径及参数过滤字符后求 MD5，仍需确认参数顺序和精确序列化。

成功 errcode=0 后还会分支处理密码策略、双因子、Token 和原生通知；不可只凭首次成功判定已完成认证。静态代码具有多平台分支，不证明当前运行实际执行了该路径。未操作登录或发起请求。

此前 authenticateUser 候选实际调用 LAContext，是生物识别可用性检查，不是账号密码认证入口；避免沿错误命名继续追踪。

## RSA 与认证后交接

进一步解码单引号 webpack eval 字符串后，定位 authCommon 模块：密码加密调用 JSEncrypt，公钥来自 serveEntiretyConfig.server.pubKey；依赖库的 RSAKey.encrypt 调用 pkcs1pad2，确认 PKCS#1 v1.5，返回 Base64。旧实现失败时退回明文的 Base64 编码；新实现不应自动复制该降级。JSEncrypt 的 UTF-16 编码循环对非 BMP 字符不等价于标准 UTF-8，需要单独测试密码字符兼容性。尚未获取运行时公钥。

AuthSuccess 会先 setLoginRet(LoginRet=0)，再 setLoginRet 默认成功状态。commonUtils.setLoginRet 只在非 Web 且 hasknockVPN API 存在的条件下执行；传 Token、UserID、LoginRet、IPIsInException、isvpn、AllowUserSwitch、SwitchMode、VpnType、ZtpUser 等给原生 IPC。agentApi 注释将该调用标为 37527。不能把这些配置字段设置为任意放行值，应遵从真实服务器响应。

因此已找到 HTTP 认证和原生 TCP 状态交接的静态联系，但当前实际运行是否走该分支、TCP 交易码及设备注册仍待查。

## 请求校验实现

新增 RequestSignature.swift：限定有序标量字符串参数，按网页实现逐项 decodeURIComponent、拼接查询、去除 origin、过滤为指定 ASCII 字符，再计算 MD5。Swift 离线检查通过规范化预期、MD5 标准向量、参数顺序敏感性及非法转义拒绝。此为兼容校验，不提供认证安全性；复杂 qs 数组/对象以及完整真实请求互操作尚未实现。

来源：local/web-source/app.f99480de-full-6.js、chunk-libs.28f6dd39-full-13.js、app.f99480de-4.js、app.f99480de-14.js、app.f99480de-15.js、app.f99480de-16.js。它们为静态包内代码解码副本，不是恢复的完整原始仓库。

## 原生 setLoginRet 处理器（已定位）

字符串 0x1005ad99d → CFString 0x100a39018 → 0x1000243f0，所在函数为 ViewController.registJavaScriptBridge（0x100023c1c）。注册处汇编将栈 block invoke 指向 0x10002750c。

处理器证据 ev_c22db6c223ae60bc2694f6879bb4015bd77ef1caf00f06cc903eb5ec6d7dc2f1：LoginRet=1 时保存 UserID 和 Token，调用 parseNetProxyConfig，并读取 IPIsInException；无例外时调用 ZtpService.spaToServerLoginAuthData:devData:（Token、UserID），安排额外主队列工作。其他 LoginRet 清空本地 Token/UserID 并发送 stopVpn 通知。回调 true 不是服务器放行证明。

ZtpService 证据 ev_58a045d042934da5981b562b1dc09a7fabf4f0b6d2e2c336fad683ac5fa0ae77：向公共 SPA 包装函数传认证模式 Token 及待开放的 TCP/UDP 端口列表；日志列出 TCP 37527、8443、448、1723、6969、16886、44346 和 UDP 500、4500。待开放端口不等于 SPA 数据包实际目的端口，不能按列表直接发包。

PostSPA 证据 ev_f0cfbfaa4f1cd72a2842769640947a7192080902842281e075624f2c150f50ef：读取 ServerIPIn/Ex、SPAPortIn/Ex、ServerPortIn/Ex 和 getPublicKeyFilePath；构造 tcp/udp 端口声明。发送构建入口 0x100047fd8 调用 0x10004842c 生成报文，再使用 SPA 目的地址/端口发送；当前报文算法及密钥语义尚未恢复。部分 C++ 伪代码寄存器不完整，需要汇编或更小函数核实。

当前确认的是受配置控制的分支；未读取真实账号凭据、未发起敲门、未改变服务器或客户端认证状态。不能断言本公司当前登录一定需要所有这些流程。

## Swift RSA 模块

PasswordEncryption.swift 使用 Security.framework 的 rsaEncryptionPKCS1，接受已解析的服务器 SecKey，不自动退回 Base64。用非持久化临时 RSA 密钥验证 ASCII/BMP 中文解密往返、随机填充和超长输入失败。受限沙箱内生成临时密钥失败，允许环境中检查通过；真实服务器公钥解析及非 BMP 兼容性仍未验证。

## SPA 构造和加密进一步追踪

报文入口 0x10004842c 分别调用 0x1000484c0 组装内容、0x1000488f0 包装加密。内容含时间、版本 3.0.0、认证模式与调用者数据、开放端口声明；部分 append 参数在伪代码缺失，尚不可写成完整格式。证据 ev_ed63e13912a8d5e0820869cde676c940d22a7c91e8cfcacdc0c465fbf55f5672。

加密器先追加摘要，再走公钥或对称加密分支，编码后附 HMAC，并设置模式字节。摘要和 HMAC 长度候选为 16/20/32，算法名称需要验证底层函数，不只按长度推断。公钥分支从文件读取公钥并以 RSA_size-11 分块；对称分支含 Salted__ 包装和 16 字节填充。完整加密参数、盐/IV 派生及 HMAC 输入/密钥仍未恢复，不将其直接当作可用 SPA 编码器。证据 ev_f3c51b3d9beeac522739aa8583855bc7babeb313c783aeeb4e98d2c7c0f666a1、ev_7c892ea92d25758387332c1665a0aee75185a3e99cad1919264b7416cd00616e。

构造函数 0x10003d9e0 汇编写入默认 SPA 内外端口 37527；偏移 c8/cc 从常量 0x100577230 加载，直接按 Mach-O 段文件映射只读核对为 UInt32 (1,2)。结合分支判断，默认进入公钥加密路径；运行时可变性和当前实际执行仍未证明。HTTP 登录密码的服务器 pubKey 与 SPA 的 getPublicKeyFilePath 是不同来源，不混用。

传输函数 0x100056a40 使用 sendto；socket 类型由上游初始化决定，不能仅凭 sendto 断言 UDP。目的端口来自 SPA 端口配置，而报文中 tcp/udp 列表是申请开放的服务端口。

## 消息头模块检查

FrameHeader.swift 根据发送端已观察布局读取 60 字节头；未命名字段保留偏移名称，不猜测语义。检查通过小端字段、所有 0..59 字节截断、错误 magic、过小总长及超限。4 MiB 为新版本地防护上限，不是从原客户端恢复的协议上限。尚未确认接收端布局或实现解压与网络收发。

## 认证前 SPA 桥接字段（静态网页证据）

`local/web-source/app.f99480de-4.js:2922` 的 knockPort：Web 平台、clientInfo.online 为真或不存在 hasknockVPN API 时直接返回。其他情况下构造 SPAType=Auth、ServerIP、AuthData、DevData，调用 spaToAuth；不能据此推断当前运行一定敲门。

`formateData`（同文件 3075 行）对数组中的每项先做 Base64，再替换 `+ → _`、`= → -`、`/ → .`，最后以 `|` 拼接。这不是 Base64URL。DevData 则保留标准 Base64，格式为 B64(Ip)|B64(Mac)|B64(HardId)||B64(1)，不能把两种编码混用。非数组 AuthData 直接透传；新 Swift 辅助函数只覆盖显式字符串数组。

`app.f99480de-14.js:161` 把参数通过 IPC 的 SPAToAuthServer 交给原生层，超时 15000ms。网页对结果检查 status、JSON message.Result；成功后仅设置 portConncet、按返回 ServiceIp 更新 host 并 resetBaseInfo。这些动作不等于账号认证或网络已放行。

新增 SPABridgeFields.swift 仅序列化上述桥接字段，不获取设备身份、不发请求，也不构造加密 SPA 包。固定向量检查覆盖替换字符、填充、中文、空字段和标准 Base64 的设备字段；检查通过。字符串类型/UTF-8 边界以外的 JS 隐式类型转换未实现。

2026-11-03 后续 Hopper 会话在 startup 120000ms 后未能建立桥接连接，close_binary 返回 cleanup_incomplete，未获得新的汇编证据。诊断与会话 Evidence 已保存于 local/spa-analysis-startup-failure.json、local/spa-startup-session-evidence.json。需按恢复指南完成会话释放/重连，再继续分析原生报文；不能把启动成功声明为分析成功。

## Hopper 重连恢复后的汇编核对

REA 新进程启动时间 2026-11-03T08:07:50.343Z，cleanup_pending=false。将本次运行 Hopper startup timeout 调整为 240000ms 后，成功取得 0x1000484c0 汇编（ev_7218cdfad8b9c29ccf03a8f586fef16772e6ce44459052c8b673133c374e2004）。完整本轮 Evidence：local/spa-resumed-evidence.json。

该函数将两次 sub_1000e5934 的返回值相乘并调用 unsigned long to_string；随后 resize(16, '1')，不足时补字符 1，过长时截断。不能未经验证把生成源称为密码学随机数。字段分隔符在 0x1005ac4c3，read_bytes 确认为冒号加 NUL。

按汇编观察到的内容顺序为：16 字节前缀、对象偏移 0x38 的字符串、0x50、0x68、time(NULL) 的十进制文本、0x80、0x98、最后的编码字段，中间使用冒号。0x80 默认值为 3.0.0，0x98 默认值为 1（由构造函数和常量字节联合确认）；其他字段的业务语义还需追踪写入者，不能提前把它们命名为账号或令牌。

最后一项以 snprintf("0.0.0.0%s", object+0xb0) 生成内容，传给 0x1000c6560，第四参数为 1。该辅助函数可观察到删除末尾 '=' 的循环，但底层调用尚未全部命名，暂不只据此认定为某种 Base64 编码。0x100048ef4 是字符串存储分配辅助函数，不是编码函数；其失败分支的异常伪代码也不能当作真实 UI 调用。

本轮是静态分析恢复验证，没有发送 SPA、尝试登录或改变原客户端状态。

## SPA 传输及字段语义确认

本轮完整 Evidence 保存于 local/spa-fields-transport-evidence.json。0x100047fd8 的直接调用者包含 0x10003cc28 和 0x1000c6eb0，当前结论针对已追踪的 PostSPA 路径，不能覆盖所有网络发送。

0x10003cc28 使用静态发送对象 0x100aeb930；其构造链 0x100047f90 → 0x100047f44，以参数 2 调用 0x10005668c。后者明确调用 socket(2, 参数, 0)，所得 fd 存储在发送对象起始位置。结合 macOS SDK sys/socket.h 的 AF_INET=2、SOCK_DGRAM=2，确认该路径建立 IPv4 UDP socket，与后续 sendto 链闭合。报文中的 tcp/udp 服务端口声明不改变 SPA 的 UDP 传输类型。

0x10003d4a0 汇编将第三参数（模式）写入对象偏移 0x38、第一参数写入 0x50、第二参数写入 0x68，再进入 PostSPA。在此前已追踪的 Token 调用链中，第一参数为 Token，第二参数为 UserID；不能把所有模式的第二参数一概理解为完整设备信息。

0x1000c6560 调用 0x10017bc54 和 0x1000fdbe8 取得方法对象，方法表名称指针只读确认为 "base64 encoding" 和 "memory buffer"。结合此前观察的处理链和删除末尾 '=' 循环，确认这是去填充的 Base64 编码。此处没有观察到桥接字段所用的自定义字符替换，不能混用两种编码。

因此 SPA 内容候选格式可以细化为：prefix16:mode:arg0:arg1:unixSeconds:version:field98:Base64NoPadding("0.0.0.0" + portsDeclaration)。默认 version=3.0.0，field98=1。prefix16 来自两个返回值的无符号乘积十进制文本，resize(16, '1')；生成源与溢出行为仍待核对。端口声明由 PostSPA 按 ,tcp/%d 或 ,udp/%d 组装。以上是加密前文本布局，不是完整可发送 SPA 报文；外层摘要、公钥/对称加密、HMAC 及密钥读取仍待确认。

## 公钥分支编码器与登录请求准备（2026-11-03）

0x1000488f0 汇编固定摘要类型为 2；0x1001b9420 初始化常量为 SHA-256 的八个标准初值，0x10018a5b4 返回的方法表首项为 NID 672，摘要长度 32。0x10006dac4 在 RSA_public_encrypt 调用前将 w4 设为 1，确认 PKCS#1 v1.5；按 RSA_size-11 分块。HMAC 输入来自去填充 Base64 的密文，密钥指针和长度取对象偏移 0xf8/0x100，类型取 0xcc（默认 2）。公钥分支输出 byte(3) + Base64NoPadding(RSA(content + ':' + Base64NoPadding(SHA256(content)))) + Base64NoPadding(HMAC-SHA256(encodedCiphertext))，两段 Base64 之间无分隔符。当前 Swift 仅实现该分支，不实现或自动降级至 AES 分支。此为静态恢复与合成数据验证，尚无服务端 SPA 互操作证明。

新增 SPAContent、SPAPublicEnvelope、RSAPublicKey、WebBase64、AuthenticationRequest、LoginPreparation。统一离线检查共 10 个入口全部通过，涵盖 RSA 分块边界、密文解密、摘要/HMAC、随机填充、PKCS1/SPKI 公钥导入、参数顺序、请求头与字段编码。临时 RSA 密钥生成需在允许 Security.framework 的环境运行，不保存 Keychain。所有模块无网络发送动作。

重要修正：HTTP global.Base64Encode 使用 `+ → ,`、`= → :`、`/ → .`；与 SPA formateData 的 `_-.` 字符表不同。用户名、idp、tokenId 及配置中的 ServerInfoConfig 使用前者。此前仅称“Base64”的说明需据此细化。LoginPreparation 限定 BMP 密码字符，拒绝尚未验证的非 BMP 密码兼容性；不会静默生成与原 JSEncrypt 不同的字节。

原生设备 XML 模板已从 CFString 0x100a3ff18 的内容指针 0x1005b32e8 完整读取；native base64 辅助 0x100082450 同样使用 HTTP 自定义字符表。新客户端的 OS、型号、网卡与硬件标识必须反映真实 Mac，不复制 iOS 的合成 MAC、AgentVersion 或设备 ID，也不声明未经验证的合规结果。

## 已授权的内网配置联调与下一步边界

用户确认当前在公司内网且可准备联调。原进程 PID 66730 的现有 TCP 对端仍为 192.0.2.10:37527；只读获取 /download/android/serviceinfoconfig.ini 返回 HTTP 200。实时 SPAPortIn/Ex=17442，随包旧配置为 37527，不能沿用旧值。配置内公钥为 HTTP 登录公钥，已独立验证导入。

Mac 平台 server/parameter 路径在缺少 Referer 时返回 401/21100006，错误为 no refer；加入同服务器来源 Referer 后返回 200/errcode=0。AuthenticationRequest 已加入同源 Referer。这个结果只证明该参数路径可访问，不等于完整 Mac 登录被支持。

按网页的 gettype=ipgetmac 分支查询 device/infoprocess，返回 200/errcode=0，当前 IP 关联设备 Registered=1、OSName=ios。没有提交凭据、认证敲门、注销、断开或强制下线请求。设备查询返回的 DeviceID 不应直接冒充新 Mac 身份用于登录。

0x1000c73f0/0x1000c7554 确认 SPA 公钥更新路径 /download/public_key.pem.xml 和 /download/public_key.pem。本次只读下载公钥，与原客户端缓存公钥 SHA256 一致，且与随包旧公钥不同；已下载至 local/server-spa-public.pem。HMAC 密钥仍由调用者提供，不把原客户端硬编码的共享材料写入已跟踪源文件。

app/prepare-device-probe.py 仅准备下一轮真实 Mac 设备报告，不发送网络请求。待审阅请求在 local/prepared-mac-device-probe.json（权限 0600），列明 URL、头、表单及报告字段。它包含真实型号、系统版本、活动网卡、IP、子网掩码、IOPlatformUUID；不含账号密码、令牌、文件或应用清单。未照搬原客户端版本号/系统声明，也未填报检查成功、受信任等结果。下一步提交 control 设备报告可能新增设备记录或改变同 IP 的现有 iOS 设备关联，需要用户确认对当前连接的影响后再执行；随后才能确定服务器是否允许原生 Mac 登记及后续认证。

实时响应及公钥仅位于 Git 忽略的 local/；未将用户设备标识、令牌或原始返回内容写入本节。界面仍是预览，不能输入密码后声称已真实登录。

## 复用登记记录与 GUI 账号认证联调版

用户明确选择先复用服务器已有设备登记；不执行准备好的 Mac control 设备报告探针。复用是重新按当前 IP 查询服务器返回的 DeviceID，不复制原客户端 Token、密码或硬件身份，不改写服务器记录的 OS/合规字段。请求平台仍声明 mac，不冒充 iOS 系统。

新增 NACService：ephemeral URLSession、禁用重定向，手动读取实时配置和登录公钥；gettype=ipgetmac 查询现有登记；device/netStatus 的参数按网页代码确认为大小写敏感的 deviceId（区别于 auth/index 的 deviceid）。只读 Swift 集成检查成功读取实时配置、公钥和已登记 iOS 记录，并得到设备在线。该在线状态可能由原客户端维持，不能归功于新应用。

GUI 已接入“检查服务器 / 复用设备记录”“提交账号认证”“刷新设备状态”。不会启动时自动请求或自动提交密码；单次用户确认只提交一次登录。改密、额外认证、绑定、重新登记、SPA/VPN 等未接通分支会明确显示尚未完成，不假装入网。未添加注销、踢下线、客户端接管保活或新登记动作。

提交时先调用 auth/config 检查 isMustChangePasswrod，再发送 auth/index；拒绝缺失 errcode、无 data 等不完整结果。根据原版 passPolicy 补充 pwdCheckResCode=0 的改密提示。确认对话框说明将向指定服务器提交账号和加密密码，可能影响原客户端会话。认证前的 SPA 报文暂未发送；当前内网已可直接读取 HTTP 接口，如服务器另要求 SPA，不自动重试或降级。

目前已完成构建、10 项离线协议回归与 Swift 服务只读内网验证；真实账号凭据尚未提交，需要用户在 GUI 亲自操作后才能确认服务器对该流程的接受情况。SPA 登录后交接、保活、VPN、MFA 尚未完整实现，联调版不能宣称完整替代原客户端。

## 用户账号认证结果及心跳静态恢复

用户已在联调 GUI 亲自提交凭据，截图显示“账号认证已受理”分支。按代码路径可推导此次 errcode=0 且未进入已实现的后续要求提示；原始响应未落盘，不能扩展为已经独立入网。截图中的设备在线在登录前就已存在，仍可能由原客户端维持。

Hopper close_binary 重试仍返回 cleanup_incomplete，保留资源 /tmp/rea-wdNfhK。不再启动依赖该会话的新查询，改用系统 xcrun llvm-objdump 的显式地址范围只读核对同一已哈希二进制。地址名称来自已保存的 REA 符号清单；局部范围输出在 local/*-llvm.txt。LLVM 输出中的 dyld_stub_binder 伪标签不作为语义证据。

0x10002f4e0 明确 fmov d0,30，随后 scheduledTimer... 并立即 fire，确认定时心跳间隔 30 秒。0x1000a429c 载入的 CFString 0x100a36038 是 DeviceID；0x1005b1e6c 为 HeartTest。完整 XML 模板与静态字节保存于 local/heartbeat-static-literals.json，requestClientType=mobile，不能未经验证假设 Mac 存在其他心跳方言。

0x1000a0cd8 使用 socket(AF_INET,SOCK_STREAM,0)，5 秒连接超时，接收回调启动后调用 0x1000a1518。该函数会首先发送 Information.getUpdateAgentInfoStr，交易名位于 0x1005b3f5b；因此不能简单把原客户端所有启动消息照搬给复用记录，避免改写设备信息。

0x10001fff4 → 0x1000bb3d8/0x1000bb3f4 的调用参数为 level=9、method=8、windowBits=15、memLevel=8、strategy=0，版本字符串为 zlib 1.2.5，确认使用 zlib 包装的 DEFLATE，不是裸 DEFLATE 或 gzip。0x1000a3270 先读取 60 字节头，再读取 total-60 负载；偏移 16 决定是否逆字节变换，偏移 12 决定是否解压。新增解码器支持 0/1 标志，其他标志拒绝；4 MiB 上限是新实现自身约束，不声称与原客户端接收边界完全一致。

新增 ASMFrame/HeartbeatMessage，及显式单次 HeartbeatProbe。独立 Python 帧样例解码、字节级分片、合包、损坏压缩与异常标志检查通过；回环网络检查通过 echo/corrupt/timeout/cancel。该组件默认不连接真实服务器，GUI 用户确认后才尝试一次。只接受交易名与序列号匹配的帧作为传输诊断，不执行策略、不发送设备更新、不把匹配帧等同于业务成功。

GUI 增加可停止的 30 秒服务器状态监测，与真实心跳区分；状态失败显示未知而非擅自判定离线，不自动提交凭据或注销。完整接管仍需业务结果核对及受控原客户端退出验证，当前尚未执行真实 TCP 心跳测试。

补充：原生静态证据的目标 SHA256、工具版本和局部汇编文件摘要已保存于 local/keepalive-native-evidence-manifest.json。单次诊断输出仅白名单 RetCode/ErrCode/ErrorCode/ReturnCode/Result 中的短整数或布尔值，不显示任意 XML、Token 等字段。回环测试响应同时注入 RetCode=0 与合成 Token，已验证只有结果码进入诊断输出；这不证明真实服务器使用同一业务字段。

## HeartTest 确认语义与连续试验

用户截图显示真实单次测试返回相同交易名/序列号的 148 字节响应，无白名单结果码。此时只证明旧版帧级往返，不拥有原始 XML。

进一步只读检查完整接收函数：0x1000a1e30..0x1000a1e4c 将 XML 解析出的 TradeCode 与 CFString 0x100a40978（HeartTest）比较，匹配后把收到的序列号 w19 保存到 0x100b26c20，跳转后续处理。0x1000a5174 延迟检查发送日志序列号与该应答序列号，未匹配时才进入关闭连接分支。该路径不读取额外 RetCode。因此“不含结果码”本身不是 HeartTest 失败证据。

完整接收汇编、常量映射、超时检查输出都保存于 local/heartbeat-*-llvm.txt 及 heartbeat-receive-constants.json，静态只读核对同一目标 SHA256。非 ASCII CFString 的简易提取可能不完整，本结论只使用已确认为 ASCII 的 TradeCode/HeartTest 常量与对应指令。

新实现增加 XML 校验：仅认可根节点直属的唯一 TradeCode=HeartTest，加上帧头交易名与序列号匹配。拒绝畸形、DTD、实体声明、NUL、重复或注释伪造，不执行任何服务器指令。连续试验保持同一连接，逐次确认后间隔 30 秒发送下一条；每条应答超时 10 秒。未知服务器消息、异常或关闭立即停止，重启须用户操作，不自动重新认证。

回环测试通过同连接连续三次不含 RetCode 的 HeartTest 应答，既有损坏帧、超时、取消、敏感输出过滤检查继续通过；12 项离线检查通过。GUI 开始/停止使用代际标识隔离旧取消任务的回调，防止快速停止重启后旧任务改写新状态。连续真实服务器测试及原客户端退出后的独立性尚未执行，交由用户在界面确认开启。

## 用户连续测试后的诊断修订

用户新截图显示连续试验停止，提示“连接已关闭，未取得匹配心跳响应”。旧版这条通用提示没有保留此前应答次数或阶段，因此不能从截图推断零次应答、固定断开时长或服务器主动策略的具体原因，不能声称连续保活已成功。

0.6 修正发送周期：用 ContinuousClock 记录发送时间，从 30 秒间隔中扣除应答延迟；这与原版固定定时器更接近，但未证明原先间隔差异就是实际关闭原因。错误补充应答次数、单调运行时间、阶段及 NWError，并区分正常 EOF 与接收错误，不记录 DeviceID、Token、密码或完整 XML。回环新增 idleclose 场景，验证一条应答后对端关闭仍保留“已应答 1 次”和等待阶段，其余五种运输检查继续通过。

按用户最新偏好修订激活策略：仅控制台存在时 regular（Dock/Command-Tab），关闭后 accessory（菜单栏）。此更改不涉及任何服务器请求，实际桌面交互仍需本机用户点验。

## 登录后异步推送与 0.7 诊断

用户截图进一步明确：1 次合法心跳应答后约 4.8 秒，收到非 HeartTest 帧，应用按保护逻辑主动停止。此前笼统关闭提示不能代表心跳未通过。用户随后确认该轮在开启心跳之前重新提交过账号密码。

为复现同一已授权记录，执行无密码、无更新、无策略处理的有限诊断：首次最多 12 秒，1 次应答，到期取消；第二次最多 45 秒，1 次应答，对端在 23.7 秒关闭 TCP，未捕获另一类消息。两次均只建立本实现的试验连接，结束关闭，不操作原 NAC 进程。它们未走新的账号认证动作，不能替代用户“登录后开启心跳”路径，也不能说明两种停止原因相同。实际非心跳交易类型仍未知。

0.7 为未处理帧显示经过格式限制的帧头交易名、XML TradeCode、序列号、负载字节数，并对白名单 WhatToDo/StateOfNet 取值显示控制摘要；未知值隐藏，不显示 Token、Msg 自由文本或完整 XML。仍停止而非跳过未知策略；新增复制诊断按钮只复制这些元数据。回环新增心跳后推送场景，验证已应答计数、交易名和隐私过滤。

进一步恢复 getUpdateAgentInfoStr（0x100097078..0x100097858）的完整模板，保存于 local/agent-session-initial-message-literals.json 及对应 LLVM 文件。首包确实包含 ServerID/AgentID、uptade_source、IP/MAC、磁盘/CPU/内存、OSName=ios、原版本号等，会涉及设备信息更新。当前用户选择复用且不改写已有登记，因此未盲目发送该模板。是否需要其中的会话绑定步骤、以及它与 23.7 秒关闭的关系，仍待验证，不能以缩短心跳间隔或自动重连代替确认。


## RoleChanged 分支与 0.8 修正

用户正确账号登录后截图显示：HeartTest 已应答一次，0.7 秒后收到帧头及 XML TradeCode 均为 RoleChanged、负载 132 字节的推送。此前的停止来自本工具未支持分支，不能由此证明双客户端冲突。

同一原版二进制静态读取：接收函数 0x1000a1fdc..0x1000a2024 匹配 RoleChanged 后调用 downServerConfig，再 dispatch_async 全局 block 0x100a10820；block invoke 0x1000a3ff8 尾调用 0x1000a3914。后者引用 GetAgentPolicyList 字符串 0x1005b1e59 并通过 0x1000a4778 发送请求。对应原始及符号注释汇编保存 local/role-changed-handler-llvm.txt、local/role-changed-followup-llvm.txt；前者仅尾调用，不能误当完整业务体。这是静态路径证据，未证明实际策略内容及执行要求。

0.8 对帧头和有界 XML TradeCode 均匹配、且无 WhatToDo/StateOfNet 的 RoleChanged 支持通知回调。收到通知保持当前连接、原定发送时间与应答超时，不计入心跳成功；同一批中的 HeartTest 仍需序列号和 XML 校验。配置刷新保留内存 token 与原设备 ID，不调用重置身份的 prepare，不登记新设备。刷新后查询设备状态；并发通知合并刷新。端点变更或刷新失败停止心跳并显示原因。策略列表获取/执行尚未接通，界面持续明确要求保留原客户端，不能把通知兼容等同完整策略支持。

未知交易、头/XML 不匹配、RoleChanged 携带控制字段仍停止；未执行下发指令。单次探测没有通知处理回调时仍停止 RoleChanged。新增回环通知+应答合包及重复通知测试，三次通知、三次心跳均通过；原有未知控制推送、断连、损坏、超时、取消测试保留。测试不访问公司服务器。

此版本同时打包此前源代码中的认证阶段诊断、动态认证卡片及复制请求诊断；凭据不写入诊断。窗口打开时进入 Dock/CmdTab、关闭后回到菜单栏的现有行为保留。


## 0.8 用户后续测试：68.5 秒关闭

用户报告连续心跳已应答 3 次、运行 68.5 秒，在“等待下次心跳”阶段由服务器关闭 TCP。用户明确原版仍在运行。随后只读 lsof 确认原版 NAC client PID 66730 仍有到认证控制器 TCP 37527 的 ESTABLISHED 连接；新 app 试验已结束。pgrep 在当前沙盒无法读取进程清单，不将该失败解释为进程不存在。

这证明当前会话收到多个合法心跳响应后仍被关闭；不能确认固定 60/90 秒超时，也不能断言双连接或遗漏首包就是根因。尚未完成只运行新 app 的对照，下一步由用户在方便短暂网络中断时退出原版、亲自认证并观察至少两分钟；如失败恢复原版，避免同时调整协议变量。

继续静态读取原版 GetAgentPolicyList 请求构造 0x1000a3914..0x1000a3b18（local/role-changed-followup-full-llvm.txt 包含后续独立函数，不混为同一业务体）。格式字符串 0x1005b42c6 为 `<?xml version="1.0" encoding="gbk"?><ASM><TradeCode>GetAgentPolicyList</TradeCode><AgentID>%s</AgentID><requestClientType></requestClientType><DeviceType>400</DeviceType></ASM>`，AgentID 来源为 DeviceID，传入发送器 field8=1。该只读策略查询尚未实装；后续须对应响应处理，不能仅发送后将未应用策略显示为接管成功。本轮未新增真实网络探测、未修改原设备登记、未启用自动重连。
