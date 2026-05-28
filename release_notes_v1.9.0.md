# STATUS CTRL v1.9.0 ─ 智能磁盘深度清理与系统闲置自维护系统 (Smart Storage Deep Cleaner & Idle Optimizer)

在此版本中，我们为 STATUS CTRL 引入了全功能、极客定制的**智能磁盘垃圾清理与重复文件识别系统 (Smart Disk Cleaner & Duplicates Finder)**，并打通了全新设计的**实时磁盘读写双曲线吞吐图表**以及**闲置静默自维护机制 (Idle-Purger)**，助您的 Mac 随时保持极致清爽、火力全开！

### 💖 重磅亮点功能

- **🧹 系统垃圾与应用残留深度清理 (Caches & Leftovers Deep Cleaner)**：
  - **Xcode 编译深度清理**：安全检索 Xcode DerivedData 编译缓存文件夹。
  - **系统与应用缓存全局扫描**：深度解析全局 `/Library/Logs` 系统日志以及 `~/Library/Caches` 应用临时缓存数据。
  - **无感卸载残留扫描**：深度扫描 `~/Library/Application Support`。提取已安装应用 Bundle ID 并进行比对，秒级定位已卸载应用的残留文件夹，为您的 SSD 腾出 G 级宝贵空间。
  - **一键深度整理**：极速后台多线程异步清扫，配合精美的清理流光进度条，体验丝滑流畅。

- **👯 重复文件智能特征比对与识别 (Progressive Duplicate File Finder)**：
  - **首创渐进式哈希校验算法**：采用「文件大小预筛 ── 首部 10KB 快速 MD5 哈希 ── 全文件 MD5 精细哈希」三级流水线引擎，哪怕在数万文件的海量目录下，也能在数秒内精准定位内容完全一致的重复文件，查重率 100%。
  - **支持自定义扫描目录**：支持高频「Downloads 目录一键扫描」及「自定义任意文件夹深度检索」。
  - **安全回收机制**：支持将重复项一键安全移至系统回收站 (`trashItem`) 或物理级彻底删除，提供防误删机制。

- **📈 实时磁盘吞吐发光折线图表 (Live Disk Performance Chart)**：
  - 在「系统健康」Tab 底层，重磅打通 **IOKit 物理存储接口**，采用高频差值计算物理磁盘每秒的 Read/Write 速度。
  - 绘制发光、平滑的**双折线吞吐曲线图 (Disk Speed Chart)**，直观动态监测 SSD 每秒的读写 MB/s 流量，气场拉满。

- **🔌 智能闲置免打扰自维护 (AC/Idle Automation)**：
  - **无感智能 Purge**：自动监听系统空闲状态 (检测到用户 idle 时间 $\ge 5$ 分钟)。若此时 RAM 占用率超过 80%，在后台静默发起 mach 内存整理与页面回收。
  - **插电深度自重构**：当用户闲置 $\ge 5$ 分钟且已连接至交流电源 (AC Power) 时，后台自动发起 APFS preboot 启动引导索引重构 (`diskutil apfs updatePreboot`) 以及全盘静默整理，每次重坐回 Mac 前都拥有最清爽的系统环境。

- **🏗️ 全面编译器架构优化 (Swift Compiler Refactoring)**：
  - 重构了 `DashboardView` 中极复杂的布局闭包，将其完全解耦为微型的 computed property Views (`leftoversEmptyView`, `leftoversScanningView`, `leftoversResultsView`, `duplicatesEmptyView`, `duplicatesScanningView`, `duplicatesResultsView`)。
  - 彻底解决了 Swift 编译器在解析大型 SwiftUI 面板时可能触发的 `type-check expression in reasonable time` 致命编译瓶颈，使得构建与迭代速度翻倍。
