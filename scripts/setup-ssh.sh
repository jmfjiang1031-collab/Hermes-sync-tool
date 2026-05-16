#!/bin/bash
# ============================================================
# Hermes Sync — SSH 密钥配置
# 为 hermes-sync 配置 GitHub SSH 认证
# 适用于国内网络环境（SSH 比 HTTPS 更稳定）
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Hermes Sync — SSH 密钥配置                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""

SSH_KEY="$HOME/.ssh/id_ed25519_hermes"
SSH_CONFIG="$HOME/.ssh/config"
HOST_ALIAS="github.com-hermes-sync"

# 1. 生成 SSH 密钥（如果不存在）
if [ -f "$SSH_KEY" ]; then
    echo -e "${GREEN}  ✓ SSH 密钥已存在: $SSH_KEY${NC}"
else
    echo -e "${YELLOW}▶ 生成新的 SSH 密钥...${NC}"
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "hermes-sync@$(hostname)" -f "$SSH_KEY" -N ""
    echo -e "${GREEN}  ✓ 密钥已生成${NC}"
fi

# 2. 显示公钥
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  请将以下公钥添加到 GitHub${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}  打开: https://github.com/settings/ssh/new${NC}"
echo ""
echo "  $(cat "${SSH_KEY}.pub")"
echo ""

# 3. 配置 SSH config
if grep -q "$HOST_ALIAS" "$SSH_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}  ✓ SSH config 已配置${NC}"
else
    echo -e "${YELLOW}▶ 配置 SSH config...${NC}"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    cat >> "$SSH_CONFIG" << EOF

# Hermes Sync — GitHub SSH
Host $HOST_ALIAS
    HostName github.com
    User git
    IdentityFile $SSH_KEY
    IdentitiesOnly yes
EOF
    chmod 600 "$SSH_CONFIG"
    echo -e "${GREEN}  ✓ SSH config 已添加${NC}"
fi

# 4. 测试连接
echo ""
echo -e "${YELLOW}▶ 测试 GitHub SSH 连接...${NC}"
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -T "$HOST_ALIAS" 2>&1 | grep -q "successfully authenticated"; then
    echo -e "${GREEN}  ✅ SSH 认证成功！${NC}"
    echo ""
    echo "现在可以运行同步了："
    echo "  bash ~/.hermes-sync/scripts/sync-push.sh"
else
    echo -e "${RED}  ❌ SSH 认证失败${NC}"
    echo "  请确认已将公钥添加到 GitHub: https://github.com/settings/ssh/new"
    echo "  公钥内容:"
    echo "  $(cat "${SSH_KEY}.pub")"
fi

echo ""
