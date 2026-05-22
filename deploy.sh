#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

if [ -z "$GH_TOKEN" ]; then
    echo "❌ 错误: 未设置 GH_TOKEN 环境变量！"
    echo "💡 请在运行脚本时通过环境变量传入，例如: GH_TOKEN=\"your_token\" ./deploy.sh"
    exit 1
fi

echo "=================================================="
echo "🚀 开始全自动部署与发布 STATUS CTRL v1.4.0"
echo "=================================================="

# 1. 提交本地修改
echo "📦 [Git] 正在暂存本地更改并提交..."
git add AppDelegate.swift DashboardView.swift Makefile PowerMonitor.swift SMCController.swift README.md CHANGELOG.md generate_icns.sh deploy.sh AppIcon.icns run.sh
git commit -m "feat: 🎨 STATUS CTRL 品牌设计焕新与硬件遥测性能升级 (v1.4.0)" || echo "⚠️ 没有检测到需要提交的新更改，继续..."

# 2. 推送至 GitHub main 分支
echo "📤 [Git] 正在推送代码至远程仓库 main 分支..."
git push -u origin main

# 3. 清理并重新构建版本标签 v1.4.0
echo "🏷️ [Git] 正在重建版本标签 v1.4.0..."
git tag -d v1.4.0 >/dev/null 2>&1 || true
git push origin :refs/tags/v1.4.0 >/dev/null 2>&1 || true

git tag v1.4.0
git push origin v1.4.0

# 4. 使用 GitHub CLI 自动创建 Release 并上传 DMG
echo "🎁 [GitHub] 正在通过 GitHub CLI 创建/更新 v1.4.0 发布包，并上传 DMG 附件..."
/usr/local/bin/gh release delete v1.4.0 -y >/dev/null 2>&1 || true
/usr/local/bin/gh release create v1.4.0 "/Users/h-l/Desktop/STATUS CTRL-v1.4.0.dmg" \
    --title "STATUS CTRL v1.4.0" \
    --notes-file CHANGELOG.md

echo "=================================================="
echo "🎉 全自动部署与 GitHub Release 发布完美完成！"
echo "👉 您的项目仓库: https://github.com/HuangLonghlhlhlhlhlhlhl/multitool"
echo "👉 最新发布页面: https://github.com/HuangLonghlhlhlhlhlhlhl/multitool/releases/tag/v1.4.0"
echo "=================================================="
