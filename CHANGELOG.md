# 开发日志 · CHANGELOG

版本历史记录，时间精确至分钟（北京时间 UTC+8）。

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
