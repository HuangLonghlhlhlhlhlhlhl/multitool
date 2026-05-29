# STATUS CTRL v1.9.2 ─ 网络蓝牙全景空间定位雷达与高精度 BLE 扫频中心 (Panoramic Wireless & BLE Radar Hub)

在此版本中，我们将无线网络遥测中心彻底升级重构为 **“网络蓝牙功能”**，完美接入了原生 **CoreBluetooth BLE 蓝牙外设探测测向引擎**，并提供了两款极其惊艳的 **HUD 磨砂玻璃独立扫频窗口**，打造顶级的无线电可视化体验！

### 💖 重磅亮点功能

- **🌐 网络蓝牙功能一键重构 (Tab & Segment Refactoring)**：
  - 将原“网络功能”选项卡全面更名为 **“网络蓝牙功能”**。
  - 右侧栏设计了 `[ 🌐 无线 Wi-Fi AP ]  [ 💎 蓝牙 BLE 设备 ]` 分栏切换器，轻松单键切换。

- **📄 独立 WiFi 物理定位分析窗口 (WiFi Standalone Window — 800x600)**：
  - 点击 Wi-Fi 卡片右上角图标，即可唤醒一个独立的 HUD 磨砂玻璃大窗口。
  - **全量热点列表**：左半分栏以表格化展示所有扫描到的 WiFi SSID、BSSID、信号强度 dBm、物理信道、频段类型、PHY 协议规范及高精米级距离。
  - **坐标靶向图**：右半分栏实时刷新极坐标分布雷达与估计测距靶图。

- **💎 CoreBluetooth 蓝牙扫描与距离估计 (CoreBluetooth Scan & BLE Distance Formula)**：
  - 接入苹果原生 `CoreBluetooth` 框架，在后台工作线程发起高灵敏度的 BLE 嗅探。
  - **路径损耗距离估计**：基于 $\text{Distance} = 10^{\frac{-59.0 - \text{RSSI}}{22.0}}$ 物理射频衰减公式换算高精米级物理距离。
  - **无缝仿真降级**：在系统蓝牙未开启或未授权时，自动提供高级仿真蓝牙数据，保证演示与可用性 100% 畅通。
  - **详情折叠伸缩**：点击蓝牙设备行，折叠展开获取外设的硬件 UUID 广播标识、连接状态、RSSI 动态强度等高精极客参数。

- **🌀 900x750 沉浸式无线电全景大雷达窗口 (Immersive Panoramic Sweep Radar)**：
  - 点击任何小雷达图，即可唤醒宽大震撼的大荧幕雷达。
  - **同屏双路测向**：在同一个高维度极坐标靶图中，以青色表示 WiFi 热点，以紫色表示蓝牙设备，完美融合同步测向物理分布，并伴有流光 Angular 扫描条与波纹粒子特效。

- **🛡️ 硬件蓝牙合规接入 (Bluetooth Sandbox Compliance)**：
  - 在 `Makefile` Plist 生成阶段自动注入 `NSBluetoothAlwaysUsageDescription` 描述，完全遵循 macOS 沙箱安全规范。
