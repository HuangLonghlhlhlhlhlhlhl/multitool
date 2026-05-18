# 开发日志 · CHANGELOG

版本历史记录，时间精确至分钟（北京时间 UTC+8）。

---

## [1.3.0] — 2026-05-18 23:16

### 🆕 新增
- **右键上下文菜单**：状态栏图标支持右键 / 触控板双指点击弹出菜单
  - 「打开主面板」：等同左键单击行为
  - 「设置…」（⌘,）：打开设置窗口
  - 「关于多功能小助手…」：显示版本、兼容性、版权信息
  - 「退出」（⌘Q）：干净终止进程
- **设置窗口**：可独立开关「CPU温度/GPU温度/电池信息/风扇转速」显示项；调整刷新间隔（0.5–5 秒）
- **关于窗口**：展示 App 图标、版本号（自动读取 Info.plist）、芯片支持范围

### 🔧 改进
- DMG 打包格式改为标准 macOS 安装体验：打开 DMG 只显示 App + Applications 文件夹快捷方式，无多余文件
- DMG 输出路径改为直接放到桌面
- `smchelper` 完全内嵌在 App bundle（`Contents/MacOS/smchelper`），用户无需单独安装任何工具
- App 命名统一为「多功能小助手」（原内部名 HelperStatusBar），显示名更友好

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
