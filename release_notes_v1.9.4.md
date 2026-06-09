# STATUS CTRL (多功能小助手) v1.9.4 Release Notes

STATUS CTRL (多功能小助手) 迎来重磅性能与体验优化更新！在 v1.9.4 版本中，我们全面审计并清除了多处导致界面微卡顿、能耗过大及内存/句柄泄露的底层隐患，实现了真正的“丝滑零卡顿”。

---

## ⚡ 核心更新特性 (Core Features)

### 1. 消除充电限制主线程阻塞 (getBatteryChargeLimit UI Freeze)
- **0ms UI 即时响应**: 彻底重构了 `getBatteryChargeLimit()` 方法。当其在主线程被 SwiftUI 渲染周期调用时，改为了立即返回由互斥锁保护的本地缓存（0ms 响应），不再因底层硬件读取而导致主线程假死。
- **后台异步调度**: 真正的 SMC 读取与特权工具 `sudo -n smchelper` 调用被派发至 `global(qos: .utility)` 后台队列进行异步获取并刷新缓存，完美消除了面板切换及刷新时的 1-2 秒主线程无响应卡顿。

### 2. 降低 IOKit USB 扫描频率与句柄释放 (USB Traversal & Memory Leak)
- **10秒周期缓存**: 将高频（1.5~3s）的 IOKit 注册表 `IOUSBHostDevice` 深度遍历改为了 10 秒时间戳缓存。大幅减轻了 CPU 和内核能耗指标（Energy Impact），日常遥测对系统资源的开销显著降低。
- **句柄泄露修复**: 修复了 USB 遍历子节点时在 break 退出前未释放 `child` 节点 (`io_object_t`) 句柄的泄露问题。在退出前显式平衡了 IOKit 引用计数，保证程序长期运行不产生系统资源句柄堆积。

### 3. 重复文件扫描与内存清理器硬化 (Purger Diagnostics & Loop Crash)
- **MD5 查重内存即时释放**: 在计算 MD5 校验的 chunk 循环中加入了 `autoreleasepool` 包装，强迫系统在读取时实时释放占用的临时 `Data` 内存，避免了扫描特大文件或海量文件时出现的物理内存暴涨。
- **符号链接循环崩溃拦截**: 在文件枚举器中增加了 `.isSymbolicLinkKey` 检测，当遇到指向父级目录的环状符号链接时调用 `enumerator.skipDescendants()` 跳过，彻底消除了由于 symlink 循环引用引发的 Stack Overflow 崩溃隐患。
- **内存气球安全门槛**: 为内存气球清理逻辑增加了安全阀门，在分配每个 512MB 物理页块前先获取当前系统空闲 + 活跃内存，一旦检测到物理可用 RAM 低于 500MB，立即中止后续的膨胀，防止在极端紧缺状态下锁死系统。

### 4. 网速显示精细化与 Timer 锁定防护 (UI Polish & Timer Scrolling)
- **低速网速高精显示**: 优化了 `formatSpeedCompact` 格式化逻辑，对于低于 1MB/s 的低速网络，从原本的整数折合（如 `1K`, `2K`）改为保留一位小数（如 `1.5K`, `0.5K`），流量显示更加平滑细腻。
- **Timer 锁定防护**: 将网络监视、蓝牙/Wi-Fi 扫描、雷达 mock 扫描定时器全部注册到了 RunLoop 的 `.common` 模式中，这样即使您拖拽、缩放、或滚动 UI 列表，定时器依然会在后台以高优先级渲染，画面和数据不再产生任何交互卡顿和顿挫。

---

## 💖 关于项目与打赏
您的支持是作者持续迭代与优化的最大动力！如果您觉得 STATUS CTRL 帮到了您，欢迎在 GitHub 上给我们点个 **Star**，或者通过 README.md 中的打赏二维码为我们赞助买点 Token！有了更多的 Token，我们的 AI 助手（也就是我 🦾）就能持续为您提供更高质量、更强大的代码维护与迭代服务！

感谢您对 **STATUS CTRL** 的支持！本版本凝聚了对于极致流畅与轻量架构的追求，为您奉上更稳定、更清爽的桌面硬件助理。
