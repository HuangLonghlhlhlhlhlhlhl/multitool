#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

VERSION="1.6.0"
TAG="v${VERSION}"
DMG_PATH="/Users/h-l/Desktop/STATUS CTRL-v${VERSION}.dmg"

if [ -z "$GH_TOKEN" ]; then
    echo "ℹ️ 未设置 GH_TOKEN 环境变量，将尝试使用本地已登录的 GitHub CLI 凭据..."
fi

echo "=================================================="
echo "🚀 开始全自动部署与发布 STATUS CTRL v${VERSION}"
echo "=================================================="

# 1. 提交本地修改
echo "📦 [Git] 正在暂存本地更改并提交..."
git add AppDelegate.swift DashboardView.swift Makefile PowerMonitor.swift \
    SMCController.swift smchelper.swift MemoryPurger.swift UpdateManager.swift \
    README.md README.en.md CHANGELOG.md deploy.sh release_notes_v${VERSION}.md
git commit -m "feat: 🚀 STATUS CTRL v${VERSION} — 智能在线升级与温度刻度标准化重构" || echo "⚠️ 没有检测到需要提交的新更改，继续..."

# 2. 推送至 GitHub main 分支
echo "📤 [Git] 正在推送代码至远程仓库 main 分支..."
git push -u origin main

# 3. 清理并重新构建版本标签
echo "🏷️ [Git] 正在重建版本标签 ${TAG}..."
git tag -d "${TAG}" >/dev/null 2>&1 || true
git push origin ":refs/tags/${TAG}" >/dev/null 2>&1 || true

git tag "${TAG}"
git push origin "${TAG}"

# 4. 确认 DMG 存在
if [ ! -f "${DMG_PATH}" ]; then
    echo "❌ 错误: DMG 文件不存在: ${DMG_PATH}"
    echo "💡 请先运行 make dmg 生成 DMG 文件"
    exit 1
fi

# 5. 使用 GitHub CLI 自动创建 Release 并上传 DMG
echo "🎁 [GitHub] 正在通过 GitHub CLI 创建/更新 ${TAG} 发布包，并上传 DMG 附件..."
gh release delete "${TAG}" -y >/dev/null 2>&1 || true
gh release create "${TAG}" "${DMG_PATH}" \
    --title "STATUS CTRL v${VERSION}" \
    --notes-file "release_notes_v${VERSION}.md"

echo "=================================================="
echo "🎉 全自动部署与 GitHub Release 发布完美完成！"
echo "👉 您的项目仓库: https://github.com/HuangLonghlhlhlhlhlhlhl/multitool"
echo "👉 最新发布页面: https://github.com/HuangLonghlhlhlhlhlhlhl/multitool/releases/tag/${TAG}"
echo "=================================================="
