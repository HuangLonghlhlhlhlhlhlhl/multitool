#!/bin/bash
set -e

# Change to the script's directory
cd "$(dirname "$0")"

echo "=========================================="
echo "      macOS 状态栏 STATUS CTRL 构建器      "
echo "=========================================="

echo "[1/3] 清理旧的构建产物..."
make clean

echo "[2/3] 开始编译并构建 .app 包装..."
make

echo "[3/3] 启动应用..."
echo "正在为您打开 HelperStatusBar.app..."
open HelperStatusBar.app

echo "------------------------------------------"
echo "🎉 恭喜！应用程序已在后台启动！"
echo "📌 请检查您屏幕右上角的状态栏，寻找量规仪表盘图标 ⚡️"
echo "⚠️  注意：由于系统安全限制，调节风扇转速需要超级用户权限。"
echo "    如果您需要使用手动风扇转速控制，请在终端以 \`sudo\` 权限启动物理二进制！"
echo "    执行命令：sudo ./HelperStatusBar.app/Contents/MacOS/HelperStatusBar"
echo "=========================================="
