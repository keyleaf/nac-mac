# 调查记录

## 已知事实

- 目标：NAC Client 2.7，com.infogo.liuft，iOS ARM64，经 PlayCover 运行。
- 原始路径：~/Applications/PlayCover/NAC client.app。
- 主程序 SHA-256：aaa17497bfddc0fc73eda0a04df09da5c6bcace1d1f48ba96e2b9f3de539839e。
- 运行副本位于 PlayCover 容器，主程序摘要一致。
- 先前进程快照观察到服务器 TCP 连接与本地 36600 端口；不等于已解释协议。
- 包含 PacketTunnel/OpenVPN 组件，不代表当前认证依赖 VPN。

## 待回答

- [ ] 登录请求与响应、密码变换和会话标识。
- [ ] TCP 帧格式、心跳及重连。
- [ ] 状态查询与退出。
- [ ] 设备字段与服务器强制要求。
- [ ] 当前使用路径是否需要 VPN。

## 证据边界

包结构与字符串为静态证据；连接快照为时点观测。未捕获登录交换，未验证服务器行为，不把候选方法名当成调用链。

## 2026-11-03：首次 Hopper 分析

- 已成功加载实际运行副本并完成原生函数搜索。
- 搜索证据 ev_a8ed121bb84f6700037d1022b88adaa975b2ca714561d7a25df432ae86c35513，筛选结果包含 8 个候选条目，不代表完整功能覆盖。
- `-[ViewController createNSTimerForHeart]` 地址 `0x10002f45c`：伪代码证据 ev_429bb052f66543d287428158cd5156e590c21b715615b9adc0b674d676e14f04 显示检查 SocketTimer 有效性，创建重复 NSTimer，以 timerFired: 为回调，并立即 fire。
- 定时间隔在该伪代码中只显示 s0，不能确定秒数；尚未分析 timerFired:，不能声称已恢复心跳数据。
- 另有 `+[InterfaceService logoutOldDevice]` 地址 `0x10001969c`，名称不能证明它是当前会话退出逻辑。
- 下一步：定位 timerFired:、账号认证请求构造和 Socket 收发，验证与 TCP 连接的关联。
