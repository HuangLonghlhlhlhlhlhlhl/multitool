# STATUS CTRL

<div align="center">

**macOS 状态栏硬件监控与风扇控制工具**

实时温度/电池监测 · 双风扇独立调速 · 能耗策略控制 · 键盘背光特效 · 零卡顿流畅体验

![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue)
![架构](https://img.shields.io/badge/架构-Apple%20Silicon%20%7C%20Intel-green)
![版本](https://img.shields.io/badge/版本-1.5.0-orange)
![大小](https://img.shields.io/badge/体积-约%206MB-lightgrey)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

</div>

---

## 📦 安装方法

1. **下载** [最新 Release](https://github.com/HuangLonghlhlhlhlhlhlhl/multitool/releases/latest) 中的 `STATUS CTRL-v1.5.0.dmg`
2. 打开 DMG，将 **`STATUS CTRL.app`** 拖入右侧 **`Applications`** 文件夹
3. 打开 Launchpad 或 Applications，找到「STATUS CTRL」点击启动
4. **首次运行**：系统弹出「无法打开未经验证的开发者」时，前往  
   「系统设置 → 隐私与安全性」→ 点「仍要打开」

> App 会出现在屏幕右上角**状态栏**（菜单栏），没有 Dock 图标。

---

## ✨ 功能一览

| 功能 | 说明 |
|------|------|
| 🌡️ CPU / GPU 温度 | 实时监测芯片 die 核心温度，Apple Silicon 和 Intel 均支持 |
| 🔋 电池监测 | 电量百分比、充电功率、电压、电芯温度、充电/续航时间精确预测 |
| 🌀 双风扇控制 | 独立查看左/右风扇转速，支持静音/均衡/极致三档预设 + 自定义温控曲线 |
| 🔗 联动/独立模式 | 一键切换：两台风扇同步联调或各自独立控制 |
| ⌨️ 键盘背光 | 亮度调节 + 常亮/呼吸灯/波浪三种特效 |
| ⚡ 能耗策略控制 | 极静/均衡/极致三档一键切换，电池/电源供电独立策略 |
| 📊 续航推演面板 | 根据当前功耗实时推算剩余续航，并与设定限额进行对比 |
| 🧹 内存一键清理 | 一键释放系统占用的物理内存，精确显示释放量（MB） |
| 🖥️ 系统高级遥测 | 温度矩阵、电压/功耗、CPU/GPU 频率估算、风扇负荷等深度指标 |
| 🖱️ 右键菜单 | 状态栏图标右键弹出：设置、关于、退出 |
| ⚙️ 设置面板 | 语言切换（中/英）、开机自启动、捐赠支持 |

---

## 🖱️ 使用方式

| 操作 | 效果 |
|------|------|
| **左键单击**图标 | 展开 / 收起主面板 |
| **右键单击**图标 | 弹出菜单（设置 / 关于 / 退出） |
| **触控板双指点击**图标 | 同右键，弹出菜单 |
| **上下滑动**面板 | 在主面板（系统遥测/风扇/能耗）与第二面板（电池保养/键盘背光）之间翻页 |

---

## 🔐 风扇手动调速授权

手动调节风扇转速需要写入 SMC 硬件寄存器，须 root 权限。**首次使用流程：**

1. 打开主面板 → 「风扇控制」→ 开启「手动控制」
2. 弹窗输入**管理员密码**一次
3. 程序自动将加固版 `smchelper` 拷贝至系统固定安全目录  
   `/Library/PrivilegedHelperTools/com.hl.smchelper` 并配置特权策略
4. 后续运行即使移动、重命名或更新 App，**免密调速功能永久有效，无需重复授权**

> 授权范围仅限 App 专用的 `com.hl.smchelper` 工具，代码全开源审计，安全合规。

---

## ⚡ 能耗控制策略

v1.5.0 引入全新的双路独立能耗控制系统：

- **🔌 电源模式**：🚀 极致性能 / ⚖️ 标准均衡 / 🍃 极致静音 三档
- **🔋 电池模式**：独立于电源模式的三档策略 + 目标功耗限额滑块
- **续航推演**：根据目标功耗限额，实时推算「设定可用时长」与「当前消耗预计时长」的对比
- **智能对齐**：开启后自动将风扇预设、键盘背光、屏幕休眠等关联设置同步匹配

---

## 🌡️ 温度说明

- **CPU 温度**：读取 CPU die 核心（`Tp0b` / `TC0F`），正常范围 **35–90°C**
- **GPU 温度**：读取 GPU die 核心（`Tg05`），正常范围 **35–80°C**
- Apple Silicon VR 调压器热点（`Tp05`）空载可达 90–100°C，属正常现象，已自动过滤
- **温度矩阵**包含：性能核/能效核/SSD/Wi-Fi/内存/掌托/气流 7 路传感器

---

## 🏎️ 性能架构（v1.5.0 重构）

v1.5.0 对底层进行了系统性重构，彻底消除了卡顿：

- **主线程 0ms 等待**：SMC 硬件 I/O 全部在后台线程异步执行
- **非阻塞 tryLock**：主线程调用 SMC 时采用 `tryLock` + 缓存兜底，绝不阻塞 UI
- **Key 黑名单机制**：连续读取失败 3 次的 SMC Key 自动加入黑名单，消除硬件延迟
- **二级内存缓存**：所有传感器数据均有内存缓存，读取失败时自动降级使用缓存值
- **面板关闭静默**：关闭 Popover 后所有遥测计时器自动暂停，CPU 占用归零

---

## 🖥️ 系统要求

| 项目 | 要求 |
|------|------|
| 系统版本 | macOS 12 Monterey 或更高 |
| 处理器 | Apple Silicon (M1/M2/M3/M4) 或 Intel x86_64 |
| 内存占用 | 约 30 MB |
| 安装体积 | 约 6 MB |

---

## ⚠️ 已知限制

- Intel Mac 键盘背光控制依赖私有 API，部分早期机型可能不生效
- 无风扇 MacBook（如 M1/M2 MacBook Air）风扇控制区域会自动隐藏
- 系统大版本升级（如 macOS 15 → 16）后可能需重新授权 sudo 规则
- 未经 Apple 公证（Ad-Hoc 签名），首次启动需手动允许

---

## 🛠️ 从源码构建

```bash
git clone https://github.com/HuangLonghlhlhlhlhlhlhl/multitool.git
cd multitool

# 编译 Universal Binary App
make

# 打包 DMG（输出至桌面）
make dmg
```

要求：Xcode Command Line Tools（`xcode-select --install`）

---

## 🤝 支持与赞助

如果 STATUS CTRL 对你有帮助，欢迎通过支付宝或微信赞助支持持续开发！  
打开 App → 设置 → 赞助与支持 扫码即可。

---

*由 HL 开发 · 2026 · 仅供学习与个人使用*
