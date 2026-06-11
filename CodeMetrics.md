# STATUS CTRL 代码度量报告 (Code Metrics Report)

此报告详细分析了当前程序的总代码行数、字符数量、以及各个核心功能模块的物理分布，用于评估后续的维护与扩展开发工作。

## 📊 整体度量汇总

| 统计项 | 数值 |
| :--- | :--- |
| **总文件数** | 10 个 |
| **总物理行数 (Lines)** | 11587 行 |
| **总代码字符数 (Characters)** | 517589 字符 |

## 📂 各文件详细统计

| 文件名 | 总行数 | 纯代码行数 | 注释行数 | 空白行数 | 字符数 | 占比 (%) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `AppDelegate.swift` | 1434 | 1204 | 47 | 183 | 63731 | 12.31% |
| `DashboardView.swift` | 7650 | 6570 | 331 | 749 | 360801 | 69.71% |
| `SMCController.swift` | 985 | 802 | 53 | 130 | 32492 | 6.28% |
| `PowerMonitor.swift` | 277 | 228 | 13 | 36 | 11878 | 2.29% |
| `MemoryPurger.swift` | 702 | 567 | 30 | 105 | 30407 | 5.87% |
| `UpdateManager.swift` | 260 | 210 | 8 | 42 | 9474 | 1.83% |
| `smchelper.swift` | 200 | 159 | 11 | 30 | 6349 | 1.23% |
| `main.swift` | 10 | 7 | 1 | 2 | 254 | 0.05% |
| `KeyboardBacklightPrivate.h` | 11 | 5 | 2 | 4 | 263 | 0.05% |
| `KeyboardBacklightPrivate.m` | 58 | 50 | 1 | 7 | 1940 | 0.37% |

## 🛠️ 核心功能模块行数估算

根据对代码结构及 MARK 标注的静态审计，STATUS CTRL 核心功能模块的物理实现行数（包含视图和控制器）估算如下：

| 功能模块 | 主要相关文件 | 估计行数 (LoC) | 功能描述 |
| :--- | :--- | :--- | :--- |
| **SMC 驱动交互与硬件控制** | `SMCController.swift`, `smchelper.swift` | ~1,200 行 | 处理底层 SMC 寄存器读写，提供风扇转速、温度传感器、充电限制等操作。 |
| **电源与电池健康诊断系统** | `PowerMonitor.swift` | ~280 行 | 负责 IOKit 智能电池属性分析、电量百分比、健康度及磁吸 MagSafe 接口连接侦测。 |
| **内存一键释放与进程监控** | `MemoryPurger.swift` | ~450 行 | 结合 `vm_stat` 统计，提供多级压缩释放内存算法，并列出 Bandwidth/CPU/Memory 占用进程。 |
| **Wi-Fi 定位雷达与网络测速** | `DashboardView.swift` (Network tab) | ~1,100 行 | 包含 CoreWLAN 扫描、隐藏 SSID 解析、双轨靶图雷达图、以及多节点宽带测速器。 |
| **实时设备隐私保护系统** | `DashboardView.swift` (Privacy tab) | ~500 行 | 包含防偷窥麦克风/摄像头状态观测器、防截屏滤镜控制、及物理乱码键盘。 |
| **状态栏常驻与轮询切换系统** | `AppDelegate.swift` | ~1,400 行 | 管理 NSStatusItem、轮询配置项、高精 CSS 平滑过渡淡入淡出/弹性宽度缩放动画。 |
| **系统清理与健康卡片 UI** | `DashboardView.swift` (Core UI) | ~3,200 行 | 主面板 Bento Box 玻璃拟态设计、自定义风扇曲线图表、以及关于窗口、快捷菜单组件。 |

## 📝 审计评估建议
1. **模块解耦**：`DashboardView.swift` 包含大量 UI 和少量控制器逻辑，体积达 7,000+ 行，建议将各大 Page 视图抽取为独立的 View 文件，提高项目的可读性与健壮性。
2. **强类型转换**：对 CoreGraphics 与 IOKit 返回的原始字典进行更安全的类型防护，避免使用 `!` 进行强行转换。
