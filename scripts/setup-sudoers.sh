#!/bin/bash
# ============================================================
# Hermes Sync — WSL sudoers 配置
# 允许当前用户无密码执行 sudo service cron start/status
# 用于 WSL 重启后自动启动 cron 服务
# ============================================================

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║       Hermes Sync — sudoers 权限配置             ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "此脚本将为当前用户添加无密码执行以下命令的权限："
echo "  sudo service cron start"
echo "  sudo service cron status"
echo ""
echo "（在 WSL 中，每次重启后 cron 服务需要手动启动，"
echo "  此配置让自动同步脚本可以自行启动 cron。）"
echo ""

# 检查是否为 WSL
if ! grep -qi "microsoft" /proc/version 2>/dev/null; then
    echo "⚠️  未检测到 WSL 环境，此脚本专为 WSL 设计"
    echo "   如果你确实需要配置 sudoers，请手动编辑 /etc/sudoers.d/"
    exit 0
fi

SUDOERS_FILE="/etc/sudoers.d/hermes-cron"

# 检查是否已配置
if [ -f "$SUDOERS_FILE" ]; then
    echo "✅ sudoers 已配置，无需重复操作"
    echo ""
    echo "当前配置内容："
    sudo cat "$SUDOERS_FILE" 2>/dev/null || echo "（需要 sudo 权限查看）"
    exit 0
fi

# 创建临时文件
TMP_SUDOERS=$(mktemp)
cat > "$TMP_SUDOERS" << EOF
$USER ALL=(ALL) NOPASSWD: /usr/sbin/service cron start
$USER ALL=(ALL) NOPASSWD: /usr/sbin/service cron status
EOF

# 验证语法
if ! visudo -cf "$TMP_SUDOERS" 2>/dev/null; then
    echo "❌ sudoers 语法错误，取消配置"
    rm -f "$TMP_SUDOERS"
    exit 1
fi

# 安装
echo "需要输入一次 sudo 密码来添加配置..."
if sudo cp "$TMP_SUDOERS" "$SUDOERS_FILE" && sudo chmod 440 "$SUDOERS_FILE"; then
    rm -f "$TMP_SUDOERS"
    echo ""
    echo "✅ sudoers 配置完成！"
    echo "   文件: $SUDOERS_FILE"
    echo ""
    echo "现在可以无密码执行："
    echo "  sudo service cron start"
    echo "  sudo service cron status"
    echo ""
    echo "测试：sudo service cron status"
else
    rm -f "$TMP_SUDOERS"
    echo "❌ 配置失败，请检查 sudo 权限"
    exit 1
fi
