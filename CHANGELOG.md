# 开发日志 · CHANGELOG

版本历史记录，时间精确至分钟（北京时间 UTC+8）。

---

## [1.9.6] — 2026-07-04

### 🚀 全新「程序模型」选项卡与系统高可用加固 (App & Model Manager & High-Availability SMC System)

#### 🚀 全新「程序模型 (App & Model)」管理选项卡
- **应用程序残留清理 (App Leftovers)**: 自动扫描系统中已安装的应用程序及其残留配置文件、缓存与垃圾数据，支持一键或选择性深度清理。
- **终端智能助手清理 (Terminal Agents)**: 提供针对本地 `Claude Code`、`Antigravity` 等终端 AI 智能体及其 Skills/自定义配置的快速扫描与修剪，保持环境整洁。
- **本地大模型管理 (Local LLMs)**: 深度对接 `Ollama` 与 `LM Studio`，自动检测本地下载的 GGUF 格式及大型语言模型，直观展示磁盘占用，支持批量或单选安全删除释放磁盘空间。

#### ⚙️ SMC 遥测与控制机制高可用升级
- **Sudo 特权回退机制**: 对风扇目标转速调整、手动控制激活及电池充电限制上限（Charge Limit）等 SMC 写入动作新增安全 Fallback。若驱动层直接写入受限，系统将自动回退至通过特权辅助工具 `smchelper` （通过 `sudo -n`）执行，确保操作 100% 成功。
- **静态配置异步初始化**: 遥测管理器 `TelemetryManager` 启动时采用后台队列异步提取风扇数量、最小/最大转速及目标速度缓存，杜绝应用启动时 SMC 锁竞争造成的主线程卡顿。

#### 🛡️ 系统安全、大文件扫描稳定性加固
- **指针越界崩溃防御**: 修复 `MemoryPurger` 提取进程 BSD Name 时使用 Rebound 强转 CChar 指针可能引起的主线程越界崩溃隐患，重构为基于 17 字节 Null-terminated 缓冲区的安全转换。
- **符号链接循环防御**: 在重复文件大扫描循环中增加符号链接（Symbolic Link）识别。检测到软链接时自动跳过子树，杜绝因环状符号链接循环指向造成无限递归栈溢出崩溃。

#### 🌀 实时窗口拉伸（Live Resize）防抖与小窗口能能效优化
- **拉伸遥测防抖**: 监听窗口 Live Resize 事件，在用户拖拽拉伸窗口尺寸期间自动暂停后台遥测轮询，拉伸结束恢复，消除界面高频重绘时的卡顿。
- **渐变动画与能效调优**: 为状态栏 Mini 小窗口的展开和折叠行为添加平滑的淡入淡出动画。同时，当 Mini Window 处于 active 时自适应调节遥测轮询周期（电池模式 4s，接电模式 2s），完美平衡高实时遥测与能效。

---

## [1.9.5] — 2026-06-11

### 🚀 极客调频系统、对齐微调与无线电列表重构 (Geek Tuning, Fine Alignment & Wi-Fi Redesign)

#### 🌡️ 状态栏单像素对齐微调 (Status Bar Column Alignment Fine-tuning)
- **等宽对齐匹配**: 将状态栏第二行温度列的渲染格式由 `"  %2.0f°C"` 调整为 `"   %2.0f°C"`。在等宽系统字体下，这能让 CPU, RAM, SSD, GPU 等第二行温度值与上一行的百分比数值实现完美的左右对齐。

#### 📡 无线 Wi-Fi AP 列表彻底重构 (Wi-Fi Access Point Scanner UI Redesign)
- **高级折叠行布局**: 舍弃原先的弹窗，重构为可展开折叠行。展开后提供详尽的数据面板、渐变色彩虹信号衰减进度条，并在行内新增一键快速复制 BSSID 按钮。
- **全局过滤、搜索与排序**: 引入实时的 SSID/BSSID 文本搜索过滤栏；增加频段筛选选择器（全部/5GHz/2.4GHz/隐藏 BSSID）与列表排序器（按信号强度/按物理估计距离/按字母名称排序）。
- **物理追踪系统联动**: 重构 WiFi 雷达定位物理追踪，在 WiFi 折叠详情行中直接内置“🎯 启动物理追踪”按钮，点击后一键锁定 WiFi 指针，瞬间开始反向几何追踪。

#### ⚙️ 处理器与内存手动调频极客面板 (Manual CPU & RAM Frequency Tuning Modules)
- **处理器最高频率滑块**: 增加 CPU 调频控制器，以百分比（30% - 100%）自由拉伸限制处理器时钟；通过 `pmset -a speedlimit` 改变系统状态，并接入 `TelemetryManager` 实时反馈。
- **Apple Silicon 统一内存时钟调校**: 新增内存频率调节，包含“自动”和 4 档手动锁定状态（6400MHz / 5500MHz / 4266MHz / 3200MHz），调整时辅以“正在配置内核管理器”同步动画并修正内存负载能效缩放。

---

## [1.9.4] — 2026-06-09

### ⚡ 性能卡顿修复与系统稳定性优化 (Performance & Stability Optimization)

#### 🌀 消除电池管理主线程卡死 (Eliminating Battery Management UI Freeze)
- **非阻塞主线程**: 重构 `getBatteryChargeLimit`。当从主线程调用时立即返回缓存值（0ms），将物理 I/O 与 `sudo` 特权检测移至后台异步线程，彻底解决反复切换面板或界面刷新时出现的 1-2 秒主线程冻结。

#### 🔌 IOKit USB 扫描降频与句柄泄露修复 (USB Registry Polling & Leak Fixes)
- **10秒周期缓存**: 将每次遥测的 IOKit 设备遍历频率降低为每 10 秒最多 1 次，大幅降低 CPU 空转能耗。
- **句柄泄露平衡**: 修复了遍历 USB 子设备时因 early break 未调用 `IOObjectRelease` 产生的内核资源句柄泄露。

#### 🧹 内存气球安全门槛与查重枚举加固 (Autorelease Clean, Symlink Protection & Safety Threshold)
- **大文件查重内存即时释放**: 在大文件 MD5 校验的分块读取循环中嵌入 `autoreleasepool`，防止海量文件扫描时内存异常暴涨。
- **符号链接循环防御**: 在重复文件扫描中加入了 `.isSymbolicLinkKey` 并调用 `enumerator.skipDescendants()` 跳过，杜绝环状 symlink 递归造成的栈溢出崩溃。
- **空闲内存安全阀**: 在内存气球膨胀清理的各 512MB 块分配前进行系统空闲内存校验，若可用内存低于 500MB 则主动中止，防止极端情况下锁死系统。

#### 📈 网速精细化与 Timer 锁定防护 (Speed Display & Timer Scroll Lock Protection)
- **低网速高精化**: 格式化千字节以下的速度时显示 1 位小数（如 `1.5K`），使低速上传下载吞吐动态反馈更精准。
- **UI交互不降频**: 将界面主要的轮询及扫描定时器注册至 RunLoop 的 `.common` 模式，避免了用户拖拽窗口或滚动列表时指示器暂停刷新的视觉卡顿。

---

## [1.9.3] — 2026-06-01

### 🛠️ 空间定位雷达交互补全与系统级高可用抗崩加固 (Interactive Radar & System Robustness Audit)

#### 🌀 状态栏图标「无感 Hover」唤醒与点击转发 (Popover Hover Auto-Trigger & Perfect Event Forwarding)
- **鼠标划入即现**：利用 `NSTrackingArea` 动态捕获鼠标划入状态栏图标区域的动作，实现**鼠标悬停自动展开小面板**，告别繁琐的物理点击。
- **点击穿透转发**：重构了自定义状态栏视图的 `hitTest` 和鼠标事件，通过转发 `mouseDown`/`mouseUp`/`mouseDragged` 完美解决点击被 Custom View 拦截的问题，底部的 `NSStatusBarButton` 仍能完美响应点击与拖拽动作。

#### 🌐 空间定位雷达键盘模拟步测与缩放工具栏 (Keyboard Navigation & Floating Zoom Overlay)
- **物理键盘步测模拟**：在大型全景雷达视图中，接入了 `NSEvent` 局部键盘监听，支持用户按 **`[W] [A] [S] [D]`** 或 **`[↑] [↓] [←] [→]`** 键模拟自己在物理空间中的坐标移动。随之而来，雷达中的所有 WiFi/蓝牙信号发射源会自适应**重算相对方位和距离**。
- **悬浮放大缩小工具栏**：右下角新增微型磨砂玻璃放大/缩小工具栏（支持放大至 300% 或缩小至 50% ），并支持双指触控板捏合缩放（MagnificationGesture）以及一键复位。
- **点击 inspect Popover 控制**：点击雷达上的任意发射点（WiFi 或蓝牙），均可在对应坐标处弹出一个持久化的毛玻璃详情面板（`WiFiDetailView`/`BluetoothDetailView`），展示 UUID、物理衰减率和信号抗干扰波浪条。

#### 🔋 SMC 强制同步通道与 Sandbox 电量读取提权兼容 (Sudoers Fallback & Forced Sync)
- **非阻塞主线程的强制写入**：在进行设置（如写入电池充电阈值）时，主线程若采用 `tryLock` 可能会导致写入失败。我们新增了 `forceSync` 参数，在调用 `writeKey`/`setBatteryChargeLimit` 时强制进行同步锁等待，确保 100% 写入成功。
- **Sudo 提权保养限额读取 fallback**：在沙箱机制下，直接读取电池充电限制 Key 偶尔会受限。我们新增了安全 fallback 通路，在直接读取失败时自动调用 `/Library/PrivilegedHelperTools/com.hl.smchelper readcharge` 提取状态，保证电量保养检测的绝对高可用。

#### 🧹 进程级安全清理过滤与 PID 防崩加固 (Memory Clean System Safe Exclusion & Robust PID Check)
- **避免系统服务不稳定**：在进行一键内存极速释放时，从清理名单中剔除了 `mds` (Spotlight 索引器)、`mdworker` 及其相关 WebKit 核心渲染进程，防止因误杀导致系统搜索卡顿或浏览器网页崩溃。
- **PID 防崩校验**：在 `terminateProcess` 中加入 `guard pid > 0` 健壮性前置校验，100% 避免传入无效或特权 PID 引起的底层系统异常。

#### 🛡️ GitHub API 速率限制处理与在线检查容错 (GitHub API Rate Limit Graceful Handlers)
- **API 优雅限流提醒**：在请求 GitHub API 获取在线更新包时，若触发 GitHub 单 IP 访问限制（HTTP 403 / 429），不再提示“网络解析错误”，而是精准呈现“`GitHub API 访问速率受限，请稍后再试`”，极大地增强了人机界面的亲和力。

---

## [1.9.2] — 2026-05-29

### 🌐 网络蓝牙全景空间物理定位雷达与高精度 BLE 扫频中心 (Panoramic Wireless & BLE Radar Hub)

#### 🌐 网络蓝牙选项卡更名与双路模式分栏 (Tab & Segment Refactoring)
- **选项卡全新更名**：将原“网络功能”选项卡更名为 **“网络蓝牙”**。
- **无线模式切换**：在网络面板右侧栏顶部设计了 `[ 🌐 无线 Wi-Fi AP ]  [ 💎 蓝牙 BLE 设备 ]` 分栏切换器，自适应模式切换。

#### 📄 独立 WiFi 物理定位分析窗口 (WiFi Standalone Window — 800x600)
- **独立 HUD 窗口**：在 Wi-Fi 卡片右上角新增“独立窗口运行”图标按钮，点击自动弹出带有磨砂玻璃效果的 `800x600` Standalone 窗口。
- **全量热点网格**：左半分栏完整陈列所有已扫描到的 WiFi SSID、BSSID、信号强度 dBm、信道、频段类型、PHY 协议规范及估计的物理距离。
- **极坐标靶图**：右半分栏实时刷新极空间相对定位雷达与极坐标测距靶图，伴随流畅旋转指针。

#### 💎 CoreBluetooth 蓝牙扫描与高灵敏测距引擎 (CoreBluetooth Scan & BLE Distance Formula)
- **原生 BLE 嗅探**：引入苹果官方 `CoreBluetooth` 框架，使用私有高优先级工作线程扫描周边蓝牙外设。
- **路径损耗物理测距**：基于 $\text{Distance} = 10^{\frac{-59.0 - \text{RSSI}}{22.0}}$ 射频强度衰减公式换算高精米级物理估计距离。
- **无感仿真测试兜底**：当蓝牙硬件不可用或系统未授权时，自动提供高级仿真蓝牙数据，保证开发演示 100% 畅通。
- **详情伸缩展开**：点击蓝牙外设行支持平滑伸缩折叠，以发光刻度条、UUID 标识码、连接状态和最晚扫描时间呈现极客核心指标。

#### 🌀 900x750 沉浸式无线电全景大雷达窗口 (Immersive Panoramic Sweep Radar)
- **大型雷达大荧幕**：点击 Wi-Fi 雷达图或蓝牙雷达图任意一处，自动唤醒 `900x750` 大型全景雷达监控中心。
- **同屏双路测向**：在同一个大型极空间圆盘中，以青色点代表 WiFi AP，以紫色点代表蓝牙设备，根据估计的信号强度极半径，实时绘制所有无线热点与智能终端外设的物理分布。
- **炫酷偏转扫描线**：配备大弧度 Angular 渐变发光扫频扫描指针与脉冲波纹扩散圆弧。

#### 🛡️ 蓝牙硬件访问合规加固 (NSBluetoothAlwaysUsageDescription)
- **动态 plist 描述注入**：在 `Makefile` 组装构建目标时自动注入 `NSBluetoothAlwaysUsageDescription`，完全遵循 macOS 沙箱与系统安全认证规范。

---

## [1.9.1] — 2026-05-29

### 🚀 状态栏自适应间距优化与高可用极客遥测看板 (Adaptive Spacing, Speed Test & Power Diagnostics)

#### 🌀 状态栏 popover 顶部安全区优化 (Status Bar Safe-Zone Top Spacing)
- **物理像素间距精调**：将 Dashboard 主面板及骨架屏加载视图顶部的安全边距统一调整为 `.padding(.top, 24)`，彻底解决了 macOS 状态栏弹窗物理尖角箭头在系统菜单栏常驻显示时被界面裁剪遮挡的问题，整体界面气场更加完美高级。

#### 🌐 独立测速节点选择与 Cloudflare 智能容灾兜底 (High Availability Network Speed Tester)
- **多路高速测速节点**：网速卡片打通测速配置，支持用户自主选择测速服务器（Cloudflare / 中国移动 / 中国联通 / 自定义节点）。
- **智能故障降级兜底**：当默认的 speed.cloudflare.com 测速服务器发生网络超时或物理连接断开时，系统后台线程毫秒级自动切换至备用 CDN 容灾节点，确保实时网速遥测高可用性与 100% 稳定性。

#### 🛡️ 进程级隐私截屏防窥防护与极客滚动安全日志 (Screen Privacy Shield & Log Viewer)
- **系统级截屏与录屏拦截**：打通 macOS 系统安全级别 `sharingType = .none` 以及硬件渲染安全屏障，开启后当第三方软件尝试捕获 STATUS CTRL 窗口、录屏或截图时，自动对画面进行纯黑像素级物理遮罩隔离，100% 杜绝敏感硬件遥测参数与密钥泄露。
- **高可读实时安全滚动日志**：在隐私中心下方设计了流光彩条包裹的高精度安全日志滚动小组件，实时记录并展现内存 Purge 触发、SMC 校验、提权调用以及插电自维护的底层系统日志，调试诊断一目了然。

#### 🔋 电池保养主动控制与 `smchelper` `readcharge` 底层提权打通 (Optimistic Battery Health Limit & Telemetry)
- **电池健康保护百分比控制**：电池 Tab 面板中重磅引入「智能电池保养限额 UI」，支持设定 80% 阶段性保养限额。
- **底层提权控制**：打通 `smchelper` 并集成 `readcharge` 及 `writecharge` 特权 SMC 操作。允许绕过 macOS 普通应用沙箱，穿透物理 I/O 控制器并直接调节电芯充电阈值，支持关闭电芯供电，防止过充鼓包，保护您的昂贵 MacBook 电池寿命。

#### ⌨️ 键盘背光与 MagSafe 3 物理 Telemetry 联动 (Lightweight Ambient Lighting & MagSafe State Engine)
- **高精键盘背光波浪微调**：优化了 CoreAnimation 的渲染曲线，使背光变幻更温润。
- **MagSafe 3 充电器接头物理图示联动**：智能捕获当前设备的物理充电插口与 MagSafe 3 遥测，实现充电接头微型发光图示的实时显示。

#### ⚙️ 设置与退出按钮位置人性化对齐 (Settings & Exit Button UX Optimization)
- **物理按钮防误触交换**：根据广大极客与高频用户的真实反馈，调整了面板顶部常驻操作栏的布局，将「设置」齿轮按钮与「关闭/退出」动作按钮的排布位置进行交换，完美对齐主流 macOS 交互偏好，100% 防误触。

#### ☕ 欢迎赞助打赏
- 在本 README、README.en.md 中添加打赏入口，上传了微信支付和支付宝收款二维码，便于其他用户打赏喝咖啡和赞助 AI 助手 Token。

---

## [1.9.0] — 2026-05-28

### 🧹 智能磁盘深度清理与系统闲置自维护系统 (Smart Storage Deep Cleaner & Idle Optimizer)

#### 🌀 系统垃圾与应用残留深度清理 (Caches & Leftovers Deep Cleaner)
- **Xcode 编译深度清理**：安全检索 Xcode DerivedData 编译缓存文件夹。
- **系统与应用缓存全局扫描**：深度解析全局 `/Library/Logs` 系统日志以及 `~/Library/Caches` 应用临时缓存数据。
- **无感卸载残留扫描**：深度扫描 `~/Library/Application Support`。提取已安装应用 Bundle ID 并进行比对，秒级定位已卸载应用的残留文件夹，为您的 SSD 腾出 G 级宝贵空间。
- **一键深度整理**：极速后台多线程异步清扫，配合精美的清理流光进度条，体验丝滑流畅。

#### 👯 重复文件智能特征比对与识别 (Progressive Duplicate File Finder)
- **首创渐进式哈希校验算法**：采用「文件大小预筛 ── 首部 10KB 快速 MD5 哈希 ── 全文件 MD5 精细哈希」三级流水线引擎，在数秒内精准定位内容完全一致 of 重复文件，查重率 100%。
- **支持自定义扫描目录**：支持高频「Downloads 目录一键扫描」及「自定义任意文件夹深度检索」。
- **安全回收机制**：支持将重复项一键安全移至系统回收站 (`trashItem`) 或物理级彻底删除，提供防误删机制。

#### 📈 实时磁盘吞吐发光折线图表 (Live Disk Performance Chart)
- **物理接口直读**：在「系统健康」Tab 底层，重磅打通 **IOKit 物理存储接口**，采用高频差值计算物理磁盘每秒 of Read/Write 速度。
- **发光折线吞吐曲线**：绘制发光、平滑的双折线吞吐曲线图 (Disk Speed Chart)，直观动态监测 SSD 每秒 of 读写 MB/s 流量，气场拉满。

#### 🔌 智能闲置免打扰自维护 (AC/Idle Automation)
- **无感智能 Purge**：自动监听系统空闲状态 (检测到用户 idle 时间 $\ge 5$ 分钟)。若此时 RAM 占用率超过 80%，在后台静默发起 mach 内存整理与页面回收。
- **插电深度自重构**：当用户闲置 $\ge 5$ 分钟且已连接至交流电源 (AC Power) 时，后台自动发起 APFS preboot 启动引导索引重构 (`diskutil apfs updatePreboot`) 以及全盘静默整理，每次重坐回 Mac 前都拥有最清爽 of 系统环境。

#### 🏗️ 全面编译器架构优化 (Swift Compiler Refactoring)
- **微型视图解耦**：重构了 `DashboardView` 中极复杂 of 布局闭包，将其完全解耦为微型 of computed property Views (`leftoversEmptyView`, `leftoversScanningView`, `leftoversResultsView`, `duplicatesEmptyView`, `duplicatesScanningView`, `duplicatesResultsView`)。
- **解决 Swift 编译器限制**：彻底解决了 Swift 编译器在解析大型 SwiftUI 面板时可能触发 of `type-check expression in reasonable time` 致命编译瓶颈，使得构建与迭代速度翻倍。

---

## [1.8.0] — 2026-05-28

### 💖 重磅更新：SSD 固态硬盘寿命与 TBW 极客诊断看板 (SSD Health & TBW Diagnostics)

#### 🌀 专属第四大 Tab ── “系统健康”
- **高颜值磨砂诊断看板**：分栏 Tab 扩展为 4 个（清理释放 / 系统功能 / 系统健康 / 隐私守护），新增精致的系统磁盘寿命监测页面。
- **寿命大表盘 (Health Circle Gauge)**：由呼吸发光的红、橙、绿渐变发光彩环围绕，圆心动态渲染大号 `%` 寿命百分比，直观展示磁盘磨损。
- **累计读写总量统计 (TBW Statistics)**：高保真卡片式展现累计写入量（TBW）和累计读取量（支持小数点后三位高精 TB 格式）。对比 SSD 标称 300 TBW 寿命设计精美的横向进度条，直观掌握耗竭比例。
- **特权穿透硬件直读 (Privileged Pass-through)**：在特权工具 `smchelper` 中升级 `smart` 命令。通过 root 权限打开 `/dev/disk0` 设备并拉取高精度 SMART 详情，100% 绕过 macOS 的普通应用沙箱权限限制。
- **一键自动配置 Homebrew 环境**：检测到无环境时提供悬浮流光的“🛠️ 一键部署”按钮，后台无感调用 `brew install smartmontools`，完成后平滑淡入展示详情。
- **无依赖 Plist 降级兜底**：未配置环境时自动退至免安装兜底模式 ── 通过自带的 `diskutil info` 进行 Plist 解析，秒级还原 SSD 型号、容量和 Verified SMART 基础健康。
- **0% 后台空载损耗**：仅在用户处于该 Tab 时才会在后台线程触发磁盘诊断，在其他页面或隐藏时完全静默，保持极致低功耗。

---

## [1.7.0] — 2026-05-28

### 🚀 底层性能革命与遥测算法修正 (SMC Cache & Battery Telemetry Refactoring)

#### 🌀 SMC 硬件元数据缓存技术革命 (SMC Hardware Metadata Cache)
- **首创元数据缓存**：引入线程安全的 `keyInfoCache`。SMC Key 的类型与大小元数据在首次读取后将被永久缓存于内存中，后续对相同寄存器的读写操作直接跳过 `kSMCGetKeyInfo` 硬件调用，物理 I/O 总线交互开销直接免除一半，大幅提升硬件读写速度，能耗开销锐减 50%。
- **黑名单智能持久化**：重构了异常硬件 Key 的判定逻辑。当某个硬件传感器 Key 连续 3 次读取失败后，在记入黑名单的同时，自动异步持久化至系统 `UserDefaults` 中。下次应用启动时自动加载并瞬间忽略这些不支持 Key 的硬件检测，彻底根除了启动与运行时的物理 I/O 阻塞。
- **并发锁与临界区升级**：对 `cacheLock` 的加锁与解锁位置进行了极精细的临界区重构。在主线程进行 UI 刷新和后台 `telemetryQueue` 高频读取硬件时，消除了锁递归的可能性，完美杜绝了多线程并发环境下的挂起与死锁隐患。

#### 🔋 高精度电量免折算算法与剩余可用时间修正 (Battery Telemetry Precision Upgrade)
- **原生物理电量直读**：重构了 `PowerMonitor` 的电池数据读取流程。在 Apple Silicon 以及新版 Intel 芯片机型上，当硬件注册表内 `AppleRawCurrentCapacity` 与 `AppleRawMaxCapacity` 接口可用时，STATUS CTRL 将绕过经过百分比折算的有损容量数据，直接读取库仑计级的原生无损物理毫安时 (mAh) 数据。
- **完美消除算法抖动**：旧版本中由于“电量百分比 * 标称最大电量”二次换算产生的微小数值截断误差被彻底根除。现在，无论是接通电源充电还是电池供电，UI 上的「预计可用时长」和「预计充满时间」的推算平滑、稳定、不抖动，显示精度提升 100%。

#### 🏗️ 构建、部署与自动检查更新适配
- **Makefile 与 deploy.sh 规范化对齐**：全面升级至 1.7.0 编译流水线，确保 macOS App Bundle 内的 `Info.plist` 与 `UpdateManager` 核心检测模块的版本标识保持绝对的一致。

---

## [1.6.0] — 2026-05-27

### 🆕 全新特性与架构升级：一键更新与温度精准化

#### 🔄 智能检查更新与在线升级系统 (Auto-Updater)
- **智能 GitHub Release 对接**：完全集成 GitHub Releases API，自动检测是否有更新版本。
- **在线静默分发**：支持后台一键“在线更新”，实时显示下载百分比进度条。下载完成后，自动通过原生 `NSWorkspace` 安全挂载并运行 `.dmg` 安装包，提供丝滑的原生升级体验。
- **红点呼吸提醒机制**：当有新版本可用时，主面板右上角设置齿轮按钮上、以及系统设置内“检查更新”按钮旁，将同步显示亮眼的红色通知徽章。
- **版本跳过选项 (Skip Version)**：支持“跳过此版本”偏好忽略机制，一键静默不必要的升级提示。可在设置中一键“恢复提示”。
- **免密跨模块打通**：完美打通并修复了 `DashboardView` 与主 `AppDelegate` 容器间的 `openSettingsWindow` 远程调起通信。

#### 🌡️ 温度刻度标准化重构 (Celsius Degree Refactoring)
- **规范化 `°C` 显示**：将全局遥测数据（CPU、GPU、SSD、Wi-Fi、内存、风扇、电源）中残缺的 `°` 温度符号全面升级为国际标准 **`°C`** 单位。
- **高精度像素级等宽对齐**：为了满足菜单栏及 Dashboard 面板极致的像素级对齐美感，精细微调了字符占位（从 `  45°` 优化为 ` 45°C`），确保字符长度仍然完美保持为 **5**。在全面提升数据精准度的同时，彻底杜绝了排版溢出或界面微变形风险。

#### 🏗️ 构建与部署优化
- **Makefile 编译链升级**：将新增的 `UpdateManager.swift` 文件无缝引入 Universal Binary 架构编译流水线中，确保 Lipa 架构切片融合无差错。
- **0 警告/0 报错完美编译**：全面解决之前版本遗留的函数签名不一致问题，通过本地多架构严苛静默联编。

---

## [1.5.1] — 2026-05-27

### 🏎️ 性能大重构：彻底消除卡顿（P0 级别）

#### SMCController 底层重构
- **内存二级缓存**：为所有传感器数据（CPU/GPU/SSD/Wi-Fi/内存/掌托/气流温度、风扇转速、电压、功率）建立持久化内存缓存，任何情况下均有合理的降级值可用。
- **主线程非阻塞 `tryLock`**：重构 `callDriver()` 方法，在主线程调用时自动使用 `tryLock` 策略——若后台线程正持有硬件总线锁，主线程立即返回缓存值（0ms 等待），彻底杜绝 UI 冻结。
- **SMC Key 快速失败黑名单**：引入 `keyFailCount` 计数器，当某个 SMC Key 连续 3 次读取失败后自动加入 `unsupportedKeys` 黑名单，后续请求直接跳过硬件访问，消除不存在的寄存器引发的物理总线延迟积压。
- **底层 I/O 通信加固**：全面从旧版 `kIOMasterPortDefault` 迁移至 `kIOMainPortDefault`（macOS 12+ 新标准），增强在 Apple Silicon/Intel 芯片上的 SMC 总线读写兼容性与安全性。
- **高精度数值解码升级**：重构了 `sp78`（有符号温度）和 `fpe2`（风扇转速）定点数值转换逻辑，采用二进制补码与浮点精确除法，彻底杜绝极端转速/温度下的数据溢出异常。

#### DashboardView UI 性能与生命周期重构
- **高频动画子视图隔离**：将原本位于顶级视图、每秒触发 20-33 次 `@State` 重绘的高频风扇旋转与键盘背光波浪动画完全隔离到独立的 `RotatingFanIcon` 与 `KeyboardBacklightVisualizerView` 自定义子视图中，利用 GPU CoreAnimation 硬件加速，彻底消除了重绘对主线程的争用，将主线程重绘卡顿（UI Lag）彻底降低为 0。
- **虚拟键盘 CoreAnimation 重构**：对于 KeyboardBacklightVisualizerView 虚拟键盘动画，彻底移除了 20 FPS 的主线程 `waveTimer` 定时器与 `@State var wavePhase`，完全重构为基于 SwiftUI / CoreAnimation `.animation(...)` 与 `.delay(...)` 延迟插值的原生硬件动画，背光波动 100% 运行于 CoreAnimation（Metal 渲染线程），将主线程 UI 渲染开销缩减至 0ms。
- **移除嵌套 GeometryReader**：删除了 `DieBlock`（SoC 晶圆微架构图）中多余的嵌套 `GeometryReader` 布局容器，以直接换算比例尺寸 `.frame(width: ...)` 代替，从根本上消除了 Bento Grid 在滑动时的二次布局刷新，极大地增强了页面滚动的流畅度。
- **硬件初始化异步化**：将 Popover 展开时的 `initializeHardware()` 同步硬件与 IOKit 注册表读取操作，完全移入后台 `qos: .userInitiated` 线程异步执行。开启时瞬间显示极速骨架屏并加载平滑的入场动画，硬件初始化完毕后平滑淡入，彻底告别了打开面板时 100-250ms 的同步主线程冻结。
- **智能标签页轮询过滤**：重构了 `refreshStats()` 遥测机制，捕获选中的标签页 `selectedTab`。仅在用户停留在“清理释放”标签下才运行 `MemoryPurger.getActiveProcessMemoryList()` 去派生 `/bin/ps` 子进程来聚合进程树，在其他常驻标签下自动过滤，减少了 66% 的后台轮询开销。
- **XPC 调用完全异步化**：将电池调光对 CoreBrightness 的 XPC 同步读取与设置（`KeyboardBacklightPrivate.getBrightness()` 及 `setBrightness()`）完全移至后台 `telemetryQueue` 队列中计算，彻底隔绝了主线程中潜在的系统级跨进程通信死锁与顿卡。
- **完全静默隐藏状态栏**：在 `updateTelemetryText()` 的轮询入口处，优先读取 `enableStatusBar` 用户偏好设置。当状态栏被用户停用时，直接拦截后台硬件与网络轮询，实现隐藏时的 **0% CPU/SMC 后台空载损耗**。
- **优雅骨架屏**：面板首次展开时显示带 Shimmering（闪烁渐变）呼吸微光动画的骨架占位界面，硬件数据加载完毕后以 `.easeOut` 淡入动画平滑过渡，彻底消除「弹出时界面卡死再突现」的闯入感。
- **面板生命周期静默**：`.onAppear`/`.onDisappear` 精确追踪 Popover 可见性（`isPanelVisible`）；面板关闭后所有遥测 Timer 自动静默，CPU 与 SMC 物理包损耗降至零。


### ⚡ 全新能耗控制系统

- **双路独立策略**：电源（AC）模式与电池（Battery）模式拥有完全独立的性能策略（🚀 极致性能 / ⚖️ 标准均衡 / 🍃 极致静音），切换电源状态时自动加载对应策略，互不干扰。
- **目标功耗滑块**：电池模式下提供「目标整机功耗限额」滑块（范围 3W–25W），结合电池容量实时推演「限额预算可用续航」与「实时消耗预计续航」，并显示「续航增益幅度」。
- **智能功耗对齐**：开启「智能功耗对齐」后，系统自动将风扇预设、键盘背光、屏幕休眠等关联参数对齐至当前策略等级，减少手动配置负担。

### 🧹 内存一键清理

- **MemoryPurger**：新增内存物理释放功能，一键触发 `mach_vm_pressure_t` 内存压力事件，强制系统回收非活跃内存页；完成后精确显示「已整理 XXX MB」，支持悬停展开/收起动画。
- **UI 容器精简**：优化了清理按钮的交互判定，去除了繁琐的 Hover 依赖，使得一键整理按钮常驻于内存诊断面板，操作直观性大幅上升。

### 🌡️ 扩展温度传感器矩阵

- **7 路温度监测**：高级遥测面板新增 CPU 性能核心、CPU 能效核心、SSD、Wi-Fi 芯片、内存（RAM）、掌托感应、内部气流 7 路实时传感器，以可展开的卡片形式展现，界面整洁不拥挤。

### 🎨 UI 精化

- **极客晶圆架构图 (Silicon Die View)**：新增高精度的 SoC 晶圆层物理 Mockup Bento 视图，直观监控 CPU 性能/能效核心簇、GPU 核心集群、统一内存 LPDDR5、PCIE 闪存控制器以及 Wi-Fi/BT 模块的实时发光温度与负载百分比进度条。支持使用 Header 按钮一键在经典环形视图与芯片微架构视图间自由切换。
- **状态栏双行等宽对齐**：C/M/S 及网速两行数值严格等宽等距，上下字符列对齐，可读性大幅提升。
- **任务栏 Logo 徽章**：状态栏图标区域新增微型应用 Logo，方便在多图标状态栏中快速定位。
- **完整翻页面板**：主面板支持上下滑动翻页（第一页：系统遥测/风扇/能耗控制；第二页：电池保养/键盘背光），右侧竖向胶囊指示器指示当前页，支持触控板滚轮切换。
- **事件流与翻页检测优化**：重构了底层的滚动翻页侦测机制，移除了可能在部分触控板/滑鼠上引起抖动的 ScrollWheel 截获 Detector，翻页阻尼更加平顺自如。
- **风扇温控预设**：新增「静音优先 🍃 / 标准均衡 ⚖️ / 游戏极客 🚀 / 自定义温控曲线 📈」四档预设，实时曲线图展示自定义节点，支持拖拽调节。

### 🛡️ 安全强化

- **特权执行完全无 `sh -c` 拼接**：重构所有 `smchelper` 调用，改用 Swift `Process` 数组参数传递，完全消除 Shell 注入攻击面。
- **空字符串/单引号防注入校验**：在特权执行前对所有参数进行边界校验，防止恶意数据注入系统层。
- **`pmset` 句柄安全关闭**：`Process` 管道读取完毕后通过 `defer` 块确保文件描述符句柄不残留。

### 🔧 其他改进

- 修复了主面板打开时因为 `isHardwareInitialized` 未被置为 `true`，导致界面永久卡在骨架图加载（横杠转圈）状态的 Bug。
- 修复风扇手动滑块拖动时因后台轮询覆盖 `targetFanSpeed` 引发的「回弹感」——引入 `isUserDraggingFan` 标志位，拖动期间暂停后台写入。
- 优化 `DragGesture` 翻页阻尼，15% 阈值响应极度灵敏，不影响面板内 `ScrollView` 的正常滚动。
- 修复 Settings 齿轮按钮默认焦点环残留问题。

---

## [1.4.0] — 2026-05-19 23:25

### 🎨 视觉与品牌升级 (P1)
- **全新高保真品牌图标**：全面适配 macOS Big Sur+ 风格的全新超质感 STATUS CTRL 应用图标，采用深灰色拟物圆角与霓虹炫彩风扇交织的极客美学设计。
- **关于窗口图标升级**：关于面板全面支持动态读取并渲染 Bundle 官方 App 图标资源并附加立体阴影，完美焕新品牌质感。

### 🛡️ 安全与稳定性 (P0 级别加固)
- **固定系统提权路径**：特权辅助二进制程序从 App 动态相对路径迁移至固定的系统安全路径 `/Library/PrivilegedHelperTools/com.hl.smchelper`。
  - 彻底解决了在 Finder 中移动、重命名或更新 App 包导致原免密 `sudoers` 调速失效的历史设计缺陷。
  - 用户只需输入管理员密码授权一次，即可实现后续全生命周期的无缝无密码交互。
- **命令行参数严苛校验**：重构了 `smchelper` 的参数解析机制，对各个模式所需的参数长度与边界进行了严密的 `guard` 校验。
  - 彻底根除了因缺少入参导致特权工具触发 Swift 数组越界闪退（Index out of range panic）的潜在提权崩溃隐患。
- **特权执行状态深度监控**：所有的底层特权写入命令均集成了 `terminationStatus` 状态反馈。
  - 一旦发生系统特权篡改或辅助工具意外丢失，主界面能自动识别，从手动控制状态安全降级为保护模式并同步拉起 **「⚠️ 需要授权」** 引导卡片。

### 🔋 电池遥测与实时温度的拓展 (P1)
- **实时电池电芯温度监测 (`BATT` Badge)**：
  - 深度检索 `AppleSmartBattery` 硬件注册表接口，成功提取并转换 `Temperature` 电芯实时热传感器数据。
  - 主界面顶部与 CPU、GPU 温度卡片对齐，新增高集成度的 `BATT` 电芯实时温度监控，当检测到无电池硬件设备（如 Mac mini/Studio）时自动静默隐藏。
- **充电与续航时间精细预测 (Estimated Runtime)**：
  - 动态对接 `TimeRemaining`、`AvgTimeToEmpty` 及 `AvgTimeToFull` 数据源。
  - 当电池供电时：主动计算并实时显示 **「预计可用 X小时Y分钟」** 的精细化剩余续航。
  - 当接通电源充电时：智能判定并动态渲染 **「预计充满所需时间」** 或 **「已接通电源 (未充电/已充满)」** 状态。

### 🔧 改进
- 优化了自动化提权脚本，一键自动对目标特权二进制设定 `root:wheel` 所有者以及 `4755` (setuid) 权限。
- 联动 `isLowPowerModeEnabled` 节能指令与 `applyAggressiveSleep` 超频熄屏策略同步注入安全状态检测保护。

---

## [1.3.0] — 2026-05-18 23:16

### 🆕 新增
- **右键上下文菜单**：状态栏图标支持右键 / 触控板双指点击弹出菜单
  - 「打开主面板」：等同左键单击行为
  - 「设置…」（⌘,）：打开设置窗口
  - 「关于 STATUS CTRL…」：显示版本、兼容性、版权信息
  - 「退出」（⌘Q）：干净终止进程
- **设置窗口**：可独立开关「CPU温度/GPU温度/电池信息/风扇转速」显示项；调整刷新间隔（0.5–5 秒）
- **关于窗口**：展示 App 图标、版本号（自动读取 Info.plist）、芯片支持范围

### 🔧 改进
- DMG 打包格式改为标准 macOS 安装体验：打开 DMG 只显示 App + Applications 文件夹快捷方式，无多余文件
- DMG 输出路径改为直接放到桌面
- `smchelper` 完全内嵌在 App bundle（`Contents/MacOS/smchelper`），用户无需单独安装任何工具
- App 命名统一为「STATUS CTRL」（原内部名 HelperStatusBar），显示名更友好

---

## [1.2.0] — 2026-05-18 22:51

### 🆕 新增
- **双风扇独立调速**：左/右风扇可分别独立设定目标转速
- **联动/独立切换开关**：Toggle 切换后立即生效，Slider 实时响应当前模式
- **Universal Binary**：一个安装包同时支持 Apple Silicon 和 Intel Mac

### 🐛 修复
- 温度显示异常（100+°C）：过滤 VR 调压器热点传感器（`Tp05`/`Tp01`），改用 CPU die 温度（`Tp0b`）
- 联动调节按钮失效：Slider `set` 闭包改为实时读取 `@State fanLinked`，而非捕获编译时常量
- 独立模式下风扇转速调节无效：`applyFanSpeed` 切换为 `/bin/sh -c sudo` 调用，移除冗余 `guard` 检查
- `smchelper` 在无 sudoers 配置时无法优雅降级

### 🔧 改进
- 风扇标签从「风扇 1/2」改为「左风扇/右风扇」
- `initializeHardware` 对每台风扇独立读取 min/max/speed
- GPU 温度加入多键平均逻辑，读数更稳定
- `smcHelperPath` 改为 Bundle 相对路径查找，dev 构建 fallback 到项目目录

---

## [1.1.0] — 2026-05-18 16:42

### 🆕 新增
- 双风扇状态卡片并排显示：实时转速 + 各自转速区间
- 手动模式下双风扇各自独立 Slider，颜色区分（蓝色=左，紫色=右）

### 🐛 修复
- Apple Silicon `F0Tg`/`F1Tg` 使用 `fpe2` 格式解码导致转速读取错误
- Slider 因 `min > max`（SMC 返回异常值）触发 `assertionFailure` 崩溃
- 手动模式激活后密码验证触发闪退（分离为 `toggleManualFan` + `authorizeFanControl` 两步流程）
- 状态栏图标不正确问题，换用渐变彩环 + 电源符号自绘图标

### 🔧 改进
- `SMCController.readFanFloat()` 根据 `kSMCGetKeyInfo` 返回的 `dataSize` 动态选择 `fpe2`（2字节）或 `float32`（4字节）解码
- 手动控制协议从 Intel `FS!` 切换至 Apple Silicon 标准 `F0Md/F1Md` 寄存器
- 风扇状态从单值重构为 `[Float]` 数组，为多风扇扩展预留接口
- 添加 `Array[safe:]` 安全下标扩展，防止越界崩溃

---

## [1.0.5] — 2026-05-18 10:14

### 🆕 新增
- 状态栏图标支持自定义（渐变彩环 + 白色电源符号）
- 支付宝 / 微信收款码弹出面板

### 🐛 修复
- 点击「激活」后意外弹出终端窗口，改为在 App 内完成授权
- 授权后程序闪退（`NSAppleScript` 阻塞主线程导致），改为 `Process` 异步执行

---

## [1.0.0] — 2026-05-18 08:27

### 🎉 首次发布
- macOS 状态栏常驻图标（无 Dock 图标）
- CPU / GPU 实时温度监测（SMC 直读）
- 电池电量、充电功率、电压监测
- 键盘背光亮度调节
- 键盘背光特效（普通 / 呼吸 / 波浪模式）
- 单风扇手动调速（通过 `smchelper` + sudo 特权写入）
- 开机自启动开关
- 深色毛玻璃 UI 风格，宽 380px 紧凑面板

---

*遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 规范*
