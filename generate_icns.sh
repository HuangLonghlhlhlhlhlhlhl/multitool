#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

INPUT_IMG="/Users/h-l/.gemini/antigravity-ide/brain/d5843b57-5566-495a-b2e6-ee60ad17c30e/media__1779420129039.jpg"
WORKSPACE="/Users/h-l/Desktop/多功能小助手"

echo "🎨 [AppIcon] 开始为 STATUS CTRL 压制官方 AppIcon.icns..."
mkdir -p "$WORKSPACE/AppIcon.iconset"

# 生成 10 个标准尺寸的 PNG 图像，强制转换为 PNG 格式 (-s format png)
sips -s format png -z 16 16 "$INPUT_IMG" --out "$WORKSPACE/AppIcon.iconset/icon_16x16.png" > /dev/null 2>&1
sips -s format png -z 32 32 "$INPUT_IMG" --out "$WORKSPACE/AppIcon.iconset/icon_16x16@2x.png" > /dev/null 2>&1
sips -s format png -z 32 32 "$INPUT_IMG" --out "$WORKSPACE/AppIcon.iconset/icon_32x32.png" > /dev/null 2>&1
sips -s format png -z 64 64 "$INPUT_IMG" --out "$WORKSPACE/AppIcon.iconset/icon_32x32@2x.png" > /dev/null 2>&1
sips -s format png -z 128 128 "$INPUT_IMG" --out "$WORKSPACE/AppIcon.iconset/icon_128x128.png" > /dev/null 2>&1
sips -s format png -z 256 256 "$INPUT_IMG" --out "$WORKSPACE/AppIcon.iconset/icon_128x128@2x.png" > /dev/null 2>&1
sips -s format png -z 256 256 "$INPUT_IMG" --out "$WORKSPACE/AppIcon.iconset/icon_256x256.png" > /dev/null 2>&1
sips -s format png -z 512 512 "$INPUT_IMG" --out "$WORKSPACE/AppIcon.iconset/icon_256x256@2x.png" > /dev/null 2>&1
sips -s format png -z 512 512 "$INPUT_IMG" --out "$WORKSPACE/AppIcon.iconset/icon_512x512.png" > /dev/null 2>&1
sips -s format png -z 1024 1024 "$INPUT_IMG" --out "$WORKSPACE/AppIcon.iconset/icon_512x512@2x.png" > /dev/null 2>&1

echo "📦 [AppIcon] 正在编译图标集为 AppIcon.icns..."
iconutil -c icns "$WORKSPACE/AppIcon.iconset"

# 清理临时文件
rm -rf "$WORKSPACE/AppIcon.iconset"
echo "✅ [AppIcon] 图标文件 AppIcon.icns 成功生成于: $WORKSPACE/AppIcon.icns"
