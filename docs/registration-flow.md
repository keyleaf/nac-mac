# 新设备注册流程：静态分析与实现边界

分析日期：2026-11-03。结论来自原版随包 JavaScript 和内嵌 source map；本轮没有登录、注册、设备信息上报或任何服务器请求，没有修改当前 app。

## 结论

新设备注册可以继续实现，但它不是关闭“复用记录”后直接登录。原版先通过设备信息请求取得服务器分配或识别的 DeviceID，再认证、计算场景、判断是否需要填写注册表，最后按服务器结果进入等待审核或后续准入流程。设备发现可能建立未注册记录；正式注册信息提交是另一笔请求。

当前 Swift app 明确选择 IP 查询并复用已有记录，没有实现完整的新设备发现和注册。这次不把仅找到接口的状态描述为新设备注册已可用。

## 原生 Mac 桌面端补充（2026-11-09）

后续检查了公司提供的原生 Mac 安装包，应用标识 `com.infogo.MAC3`，版本 `6.0.6039.3746.002.08`。DMG SHA-256 为 `748f6ad6e21b13c41f31825a04d33f5e67a5c484a8526ef9922c88371849f309`。REA 清单的父证据为 `ev_0b7f22cce8f44eaafe3f3332c9a88f28a32a76adbfe14631cd12663f07f14b66`。以下是 arm64 切片静态结论，和下文早期 iOS 流程分开。

1. **连接及报告。** `NacSocketInterface` 的 `startSocketService`（0x1840）从 `IsiGetServerIP`、`IsiGetASMServerPort` 取值。端口读取 `ServerPort`，缺失或越界时原版回退到 37527（`IsaManage` 0x7f730）。`socketConnectSuccess`（0x300c）包含调用设备上报的分支。XML 由 `NacDeviceInfo` 的 `getUpdateAgentInfoXml:`（0x8014）生成，`NacSocketInterface` 的 0x4d00 以 `UpdateAgentInfo` 为交易名发到这个套接字。
2. **消息内容与封装。** 桌面设备 XML 片段包含 `ServerID`、`AgentID`、`SubType=mac`、`OSName=MacOS`、网卡和硬件信息，大小写和字段与移动端 `dev_xml` 不同。`NacSocketService` 0x3e30 将片段放在带 `TradeCode` 的 `ASM` 根元素中，追加 `UserID`、`Token`、`DeviceType=300`，转为 GBK。0x68d0 使用 60 字节 ASM5 帧头，偏移 8、12、16 的字段均为 1，序列号在 52，原始内容长度在 56。使用 zlib 等级 9，并对交易名与压缩内容执行既有 `infogo` 字节变换。
3. **取设备 ID。** 桌面原版发送前登记对应序列号的结果回调（`NacSocketService` 0x4174）。更新回调（`NacSocketInterface` 0x34cc）从 XML 结果字典读取 `AgentID`、`ServerID`、`Registered`，检查 `AgentID` 有值且不等于 `0` 后调用 `SaveDeviceID:`。助手网页通过本地 `WebCall_GetClientBaseInfo` 读取 `ASM.AgentID`。
4. **读取登记详情。** 桌面网页发送 `device/info`，传入 `deviceId=<AgentID>`、`form=AgentReg` 及页面入口上下文。正式登记仍由 `register/submit` 处理，使用认证返回的角色、设备和场景信息。

离线用独立 Python 合成样本验证了现有 Swift `ASMFrame` 与上述桌面封装逐字节一致，包括 GBK 原始字节、序列号及分段解码。合成样本只验证帧编码。仍需核对首次识别时空白 ID 和硬件字段的取值、当前服务器配置对应的端点，以及真实响应和重新登记策略。没有向服务器发送桌面设备上报。

桌面发现使用实际试用版 TCP 传输做本机回环检查，运行 `python3 app/check-desktop-discovery.py`。合成请求使用空的初始 ID 和登录字段，只上报选中的网卡。模拟端验证字段及 ASM5 编码，返回分段 GBK 响应。客户端只接受同交易、同序列号且有有效 `AgentID` 的响应，之后仅在内存组装 `device/info` 请求。检查覆盖错误交易或序列号、缺失或零 ID、重复字段和 DTD。0.14.0 试用版在「连接诊断」中提供一次性桌面识别，用户确认后上报设备，收到有效 ID 后仅查询登记资料。该试用版已在公司内网返回有效 AgentID，并成功读取已登记状态。0.14.1 将这条桌面识别路径接入常规登录，确认已登记后才提交账号认证。0.14.1 已在一台已登记的 Mac 上通过公司内网的账号认证与持续心跳验证。首次登记和重新登记仍待联调。

## 1. 如何识别本机设备

`deviceInfoUtils.getDeviceInfoProcess` 的静态流程：

1. 在原生 app 中调用 `agentApi.getDeviceInfo`，取得设备 XML。
2. 将返回值中的封装标记去除，提交 `device/infoprocess`：`gettype=control`、`dev_xml`、`BrowserFingerprint`。
3. 如果原生获取失败，退回 `gettype=ipgetmac`，并携带浏览器指纹，查询当前 IP 对应记录。
4. 读取服务器响应中的设备资料。非漫游设备还会在原网页写入设备 ID、CoreID 和 MAC Cookie。

`webApi.getDeviceInfo` 另外合入 `newMobile=1`、来宾标志、平台/浏览器信息和网页入口上下文等参数。哪些上下文是当前服务器必需项，静态代码不能证明。

当前 app 直接走第 3 步，因此会得到原版已登记的记录。“不复用”模式需要先以真实 Mac 身份走设备信息发现流程，不能删除设备 ID 后直接提交注册表，也不能把 iOS 的设备字段照搬成 Mac 身份。`control` 对服务器记录的新增/更新行为尚未实测。

## 2. 注册状态与场景规则

以下为该版本页面分支使用的含义，不能扩展为所有厂商版本的完整枚举。

| 字段/取值 | 原版如何处理 |
| --- | --- |
| `detail.Registered=-2` | 未注册；认证后的路由可进入设备注册页。提交后若仍为 -2，提示未注册，不能当作完成。 |
| `detail.Registered=-1` | 要求重新注册；注册页回填已有资料并显示 `ReRegReason`。 |
| `detail.Registered=0` | 待审核；注册后的流程返回状态页并提示等待，不等于已经放行。 |
| `detail.Registered=1` | 正常已登记的已观察值；仍要遵从场景与后续准入结果。 |
| `scene.IsAccess=0` | 禁止接入分支，返回状态页。 |
| `scene.IsRegistered=0` | 注册页走自动提交分支；这里的含义与设备本身的 Registered 字段不同。 |
| `scene.IsRegistered=1` | 非自动注册分支，由表单流程处理。 |

登录成功处理 `AuthSuccess` 会先执行已有的原生登录结果交接，再以登录响应的 `basic.Registered`、`ReRegReason` 更新设备状态。因此不能只看登录前缓存。

特殊情况：`basic.IsAgainReg=1` 的实际赋值是 `Registered=-2`；该处注释与赋值后的路由含义不完全一致。后续实现应按实际字段和流程验证，不能仅依据注释推断为可跳过注册。

场景请求为 `scene/getDeviceScene`，参数 `deviceId`，可选 `userType`；取得有效 `SceneID` 后还会请求 `auth/sceneinfo` 获取详细场景设置。页面内的 online 标志是调用此流程的前置条件，不能把它直接解释为设备已获得网络访问权。

## 3. 注册表单从哪里来

原版进入注册页会获取以下资料。接口相对路径由公共 URL helper 包装为 `/access/1.0/{osType}/json/...`；此处静态可见路径不证明真实服务器已支持相同的 Mac 注册接口。

| 相对接口 | 关键请求参数 | 用途 |
| --- | --- | --- |
| `device/reginfo` | `DeviceID`、`IsGuest=0` | 取得 `regConfig.zh/en`、设备类型、原有设备/扩展资料。 |
| `server/authorization` | `cache` | 检查服务器授权点数信息；不能由此推断每个账号的设备名额。 |
| `depart/default` | `devip` | 查询默认部门；必要时回退到设备原部门。 |
| `depart/list` | `devip`、`parentDepartId`、分页 | 部门选项；隐藏项或自动注册时页面可跳过。 |
| `user/locationList` | `parentLocationId`、分页 | 位置选项；隐藏项或自动注册时页面可跳过。 |

表单不是固定的“姓名 + 手机”。`regConfig` 每项包括 `Column`、`Title`、`InputType`、`Select`、`Rule`、`Remark`、`InputValue` 等；支持文本、多行文本、下拉、单选、多选和树选择。`Select=1` 表示必填；`Rule` 对应原版规则表，不应直接执行服务器提供的任意代码。

标准字段映射：

| 配置列 | 提交字段 |
| --- | --- |
| `RequireDep` | `depart_id` |
| `RequireDevType` | `device_type` |
| `RequireMail` | `email` |
| `RequireUser` | `username` |
| `RequirePos` | `positions` |
| `RequireTel` | `tel` |
| `RequireRem` | `remark` |
| `RequireExpand_<后缀>` | `requireexpand<后缀>` |

设备类型必须使用服务器下发的列表及真实 Mac 类型。该移动客户端在表单类型为空时赋值 `103`，尽管附近注释写 `101`；不能把移动端默认值直接当作 Mac 的正确类型。

原版会按账号、设备资料和管理员配置回填部门、姓名/账号、电话、邮箱及扩展字段；回填不代表服务器允许提交任意账号身份。

## 4. 提交和返回结果

提交接口是 `register/submit`。普通表单字段之外追加：

- `roleid`：认证响应中的 RoleID。
- `device_id`：服务器返回的设备 ID。
- `sceneId`：当前场景 ID。

数组字段先以英文逗号连接。请求使用已有公共请求器的表单编码、请求校验、Cookie/Token 和平台上下文。注册表没有单独输入密码的步骤，但通常依赖前面的账号认证上下文。

原版 `postForm` 检查 `errcode=0` 和 `data.Registered`，随后只更新本地 `detail.Registered`，交给流程控制器继续判断。这里有一个必须避免照抄的边界：JavaScript 对数字 `0` 与字符串 `"0"` 的 truthiness 不同，不能用真假值代替显式注册状态解析。缺失、未知状态应显示待确认，待审核必须单独处理。

若 `Registered=0`，注册后的路由返回状态页等待审核；正常路径还会重新读取场景，并可能进入检查结果上报、准入提交、配置交接或 VPN。因此注册请求成功不等于已经入网，也不等于新的心跳会话已经建立。

自动动作有两处：场景开启自动注册时，页面初始化后提交；即便没有表单字段，原版也存在直接提交的分支。新实现应把“读取表单”和“发送注册”明确分开，避免仅预览页面就改变服务器登记。

协议弹窗由 `ADMINISTRATORINFO.ShowAgreement` 控制，内容来自管理员配置；人工提交时可以要求阅读并同意。不能将下发的 HTML 直接作为本机可执行内容。

## 5. 新 app 下一步实现顺序

1. 加入明确的“复用现有记录 / 登记本机”模式；现有稳定路径继续保留。
2. 先做纯离线的设备报告预览，展示真实 Mac 系统、网卡和硬件标识，以及预计上报字段；不伪造已通过检查的结果。
3. 在测试条件具备后提交设备发现请求，保留服务器返回的 ID 和注册状态。此请求可能建立/更新记录，不能归类为普通只读查询。
4. 认证后重新解析 Registered、场景、表单和授权信息；实现动态表单、条款和等待审核状态。
5. 用户确认可审阅的注册内容后才提交一次；明确处理错误、重复提交、待审核、重注册和未知状态。
6. 单独验证注册后的网络准入及心跳。失败时保留诊断，不自动重新注册或伪造策略结果。

本轮只完成分析与实现说明，没有加入可发送注册请求的 UI 或网络代码。

## 6. 已回答与尚未验证

已通过静态代码回答：设备发现入口、注册页面触发条件、表单配置来源、字段映射、提交接口、待审核/重注册/自动注册分支、注册后的流程衔接。

仍需真实测试：Mac 设备报告被接受的具体条件、识别为新记录还是更新旧记录、Mac 注册接口及权限、公司实际表单和审批规则、错误码、重复请求效果，以及新登记后的独立联网。

当前机器已稳定联网，不用为了取得这些结论删除登记、修改硬件标识或重新登录。真实联调可等公司允许的测试设备或管理员可清理的测试条件。

## 证据与复核

- REA 父 Evidence：`ev_70b16992ce66def30c57a7acae9fcb3202defa54fdb383a649df52397af734d7`；摘要：`ev_a1c6b43a324188fde45fe3befeb912c06f5c05b5e60adb13624b4d694d2d6ab4`。本轮 REA 源码选择仅为主 bundle 和注册页面 chunk，图关系覆盖为 partial；不声称覆盖整个原版应用或运行时行为。
- 原版 `app.f99480de.js` SHA256：`aec46812f322e1f895c53b206b651fb2d126b94e32ae32c49d47553f1656936a`。
- 原版 `5213.04d40477.js` SHA256：`8ea98b5bc189cf286c31eec4fad21b5ff571dae71b204848e2b3fb7e513cef7e`。
- 注册页 source-map 源内容 SHA256：`dc72197da26d0b4eb0c8bbb70583b49a5554c645a32aa599abdbdaaa91c58641`。重点函数 `setupForm`、`getRegInfo`、`postForm`、`regNext`。
- 同包 `deviceInfoUtils.js`、`authCommon.js`、`processController.js`、`scene.js`、`regUtil.js`、`webApi.js` 共同建立调用路径；原文只在本机被忽略的 `local/registration-sources/` 保留，manifest 记录模块名、内容哈希和来源。
- 完整本轮 REA Evidence 已导出到 `local/registration-rea-evidence.json`，摘要在 `local/registration-rea-summary.json`。原版源码和分析原始资料不提交 Git。
