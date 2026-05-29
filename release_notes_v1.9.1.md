# STATUS CTRL v1.9.1 ─ 状态栏自适应间距优化与高可用极客遥测看板 (Adaptive Spacing, Speed Test & Power Diagnostics)

在此版本中，我们听取了用户的反馈，重点优化了 **STATUS CTRL** 的顶部状态栏适配细节与防误触体验，并带来了包括**智能测速节点多路选择**、**截图防窥隐私拦截屏蔽**、**物理 MagSafe 3 遥测联动**与**底层特权电池保养限额**等高级重磅更新！

### 💖 重磅亮点功能

- **🌀 状态栏 popover 顶部安全区优化 (Status Bar Safe-Zone Top Spacing)**：
  - **物理像素间距精调**：将 Dashboard 主面板及骨架屏加载视图顶部的安全边距统一调整为 `.padding(.top, 24)`，彻底解决了 macOS 状态栏弹窗物理尖角箭头在系统菜单栏常驻显示时被界面裁剪遮挡的问题，整体界面气场更加完美高级。

- **🌐 独立测速节点选择与 Cloudflare 智能容灾兜底 (High Availability Network Speed Tester)**：
  - **多路高速测速节点**：网速卡片打通测速配置，支持用户自主选择测速服务器（Cloudflare / 中国移动 / 中国联通 / 自定义节点）。
  - **智能故障降级兜底**：当默认的 speed.cloudflare.com 测速服务器发生网络超时或物理连接断开时，系统后台线程毫秒级自动切换至备用 CDN 容灾节点，确保实时网速遥测高可用性与 100% 稳定性。

- **🛡️ 进程级隐私截屏防窥防护与极客滚动安全日志 (Screen Privacy Shield & Log Viewer)**：
  - **系统级截屏与录屏拦截**：打通 macOS 系统安全级别 `sharingType = .none` 以及硬件渲染安全屏障，开启后当第三方软件尝试捕获 STATUS CTRL 窗口、录屏或截图时，自动对画面进行纯黑像素级物理遮罩隔离，100% 杜绝敏感硬件遥测参数与密钥泄露。
  - **高可读实时安全滚动日志**：在隐私中心下方设计了流光彩条包裹的高精度安全日志滚动小组件，实时记录并展现内存 Purge 触发、SMC 校验、提权调用以及插电自维护的底层系统日志，调试诊断一目了然。

- **🔋 电池保养主动控制与 `smchelper` `readcharge` 底层提权打通 (Optimistic Battery Health Limit & Telemetry)**：
  - **电池健康保护百分比控制**：电池 Tab 面板中重磅引入「智能电池保养限额 UI」，支持设定 80% 阶段性保养限额。
  - **底层提权控制**：打通 `smchelper` 并集成 `readcharge` 及 `writecharge` 特权 SMC 操作。允许绕过 macOS 普通应用沙箱，穿透物理 I/O 控制器并直接调节电芯充电阈值，支持关闭电芯供电，防止过充鼓包，保护您的昂贵 MacBook 电池寿命。

- **⌨️ 键盘背光与 MagSafe 3 物理 Telemetry 联动 (Lightweight Ambient Lighting & MagSafe State Engine)**：
  - **高精键盘背光波浪微调**：优化了 CoreAnimation 的渲染曲线，使背光变幻更温润。
  - **MagSafe 3 充电器接头物理图示联动**：智能捕获当前设备的物理充电插口与 MagSafe 3 遥测，实现充电接头微型发光图示的实时显示。

- **⚙️ 设置与退出按钮位置人性化对齐 (Settings & Exit Button UX Optimization)**：
  - **物理按钮防误触交换**：根据广大极客与高频用户的真实反馈，调整了面板顶部常驻操作栏的布局，将「设置」齿轮按钮与「关闭/退出」动作按钮的排布位置进行交换，完美对齐主流 macOS 交互偏好，100% 防误触。

- **☕ 支持与打赏支持**：
  - 在 README、README.en.md 中添加打赏入口，上传了微信支付和支付宝收款二维码，便于其他用户打赏喝咖啡和赞助 AI 助手 Token。
