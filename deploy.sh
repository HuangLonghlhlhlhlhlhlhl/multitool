#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

echo "=========================================="
echo "🚀 开始部署 多功能小助手 v1.3.0 到 GitHub"
echo "=========================================="

# 1. 检查 SSH 连接
echo "🔑 正在测试 GitHub SSH 联通性..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "✅ GitHub SSH 认证成功！"
else
    echo "❌ 认证失败，请确保您已将以下公钥添加到 GitHub 设置 (https://github.com/settings/keys) 中："
    echo "--------------------------------------------------"
    cat ~/.ssh/id_ed25519.pub
    echo "--------------------------------------------------"
    exit 1
fi

# 2. 推送代码
echo "📦 正在推送代码到 main 分支..."
git push -u origin main --force

# 3. 推送 Release 标签
echo "🏷️ 正在推送 v1.3.0 标签..."
git push origin v1.3.0 --force

echo "=========================================="
echo "🎉 部署完成！"
echo "代码和 v1.3.0 的 DMG 文件已成功上传至您的 GitHub 仓库："
echo "👉 git@github.com:HuangLonghlhlhlhlhlhlhl/multitool.git"
echo "=========================================="
