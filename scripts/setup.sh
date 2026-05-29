#!/bin/bash
# ============================================================
# Hermes Sync — 一键安装脚本
# 用法: curl -fsSL <raw_url>/setup.sh | bash
# ============================================================
set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BANNER="
╔══════════════════════════════════════════════╗
║          Hermes Sync — 安装向导              ║
║    多终端同步 Skills / Profiles / SOUL.md     ║
╚══════════════════════════════════════════════╝"

echo -e "${BLUE}$BANNER${NC}"
echo ""

# ==========================================
# 环境检测
# ==========================================
echo -e "${YELLOW}▶ 检测系统环境...${NC}"

OS="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
fi

echo "  操作系统: $OS"
echo "  用户目录: $HOME"

# 检查依赖（只需 git 和 curl，不再需要 rsync）
MISSING=()
for cmd in git curl; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING+=("$cmd")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${RED}❌ 缺少依赖: ${MISSING[*]}${NC}"
    echo ""
    echo "请安装后重试:"
    case "$OS" in
        linux) echo "  sudo apt install ${MISSING[*]}" ;;
        macos) echo "  brew install ${MISSING[*]}" ;;
    esac
    exit 1
fi
echo -e "${GREEN}  ✓ 所有依赖已就绪${NC}"

# 检查 SSH 配置
HAS_SSH=false
if [ -f "$HOME/.ssh/config" ] && grep -q "github.com-hermes-sync" "$HOME/.ssh/config" 2>/dev/null; then
    HAS_SSH=true
    echo -e "${GREEN}  ✓ 检测到 SSH 配置（github.com-hermes-sync）${NC}"
elif ssh -o ConnectTimeout=3 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo -e "${YELLOW}  ⚠  GitHub SSH 可用，但未配置 hermes-sync Host 别名${NC}"
    echo "     可运行 scripts/setup-ssh.sh 来配置"
fi

# 检查 Hermes
if [ -d "$HOME/.hermes" ]; then
    echo -e "${GREEN}  ✓ 检测到 Hermes Agent${NC}"
else
    echo -e "${YELLOW}  ⚠ 未检测到 Hermes Agent，同步工具仍可安装${NC}"
fi

# ==========================================
# SSH 配置
# ==========================================
echo ""
echo -e "${YELLOW}▶ 配置 SSH 认证${NC}"
echo ""

if [ "$HAS_SSH" = false ]; then
    echo "推荐使用 SSH 方式连接 GitHub（国内网络更稳定）。"
    echo ""
    echo "请确保已将 SSH 公钥添加到 GitHub:"
    echo -e "  ${BLUE}https://github.com/settings/ssh/new${NC}"
    echo ""
    echo "如果没有 SSH 密钥，可运行: bash scripts/setup-ssh.sh"
    echo ""
fi

# ==========================================
# 数据仓库
# ==========================================
echo ""
echo -e "${YELLOW}▶ 配置数据仓库${NC}"
echo ""
echo "你的同步数据存在哪里？"
echo "  1) 使用已有仓库（已有 hermes-sync）"
echo "  2) 跳过（仅安装脚本）"
echo ""

read -r -p "请选择 [1-2]: " REPO_CHOICE

SYNC_DIR="$HOME/.hermes-sync"
mkdir -p "$SYNC_DIR"

case "$REPO_CHOICE" in
    1)
        read -r -p "GitHub 用户名: " GH_USER
        read -r -p "仓库名 (默认 hermes-sync): " GH_REPO
        GH_REPO="${GH_REPO:-hermes-sync}"

        CLONE_URL="git@github.com-hermes-sync:${GH_USER}/${GH_REPO}.git"

        if [ -d "$SYNC_DIR/.git" ]; then
            echo "  已有仓库，正在更新 remote..."
            cd "$SYNC_DIR"
            git remote set-url origin "$CLONE_URL" 2>/dev/null || git remote add origin "$CLONE_URL"
            git fetch origin 2>/dev/null || echo "  拉取失败，将在首次同步时重试"
            git reset --hard origin/main 2>/dev/null || true
        else
            echo "  正在克隆仓库..."
            git clone "$CLONE_URL" "$SYNC_DIR" 2>/dev/null || echo "  克隆失败，将在首次同步时重试"
        fi
        echo -e "${GREEN}  ✓ 数据仓库已关联${NC}"
        ;;
    *)
        echo "  已跳过"
        ;;
esac

# ==========================================
# 写入配置
# ==========================================
echo ""
echo -e "${YELLOW}▶ 生成配置文件...${NC}"

cat > "$SYNC_DIR/sync.conf" << 'CONFEOF'
# Hermes Sync 配置文件
# 环境变量方式（推荐）：export HERMES_SYNC_REMOTE=git@github.com:YOU/hermes-sync.git

# Git 远程仓库地址
# HERMES_SYNC_REMOTE=git@github.com:YOUR_USERNAME/hermes-sync.git

# Git 分支
# HERMES_SYNC_BRANCH=main

# Hermes 目录（默认 ~/.hermes）
# HERMES_DIR=~/.hermes

# 同步仓库目录（默认 ~/.hermes-sync）
# HERMES_SYNC_DIR=~/.hermes-sync
CONFEOF

echo -e "${GREEN}  ✓ 配置已生成: $SYNC_DIR/sync.conf${NC}"

# 创建 .gitignore（白名单模式，防止 profiles 递归嵌套等问题）
if [ ! -f "$SYNC_DIR/.gitignore" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/../config/gitignore.example" ]; then
        cp "$SCRIPT_DIR/../config/gitignore.example" "$SYNC_DIR/.gitignore"
    else
        # 内联创建 .gitignore（curl | bash 场景下没有 repo 文件）
        cat > "$SYNC_DIR/.gitignore" << 'GITEOF'
# ===== 白名单模式：默认忽略所有，只同步指定内容 =====
*

!.gitignore
!skills/
!skills/**
!profiles/
!profiles/**
!SOUL.md
!sync-push.sh
!sync-pull.sh

skills/.curator_backups/
skills/.usage.json
skills/.curator_state
skills/.bundled_manifest
skills/.hub/
skills/apple/

profiles/*/.curator_backups/
profiles/*/.usage.json
profiles/*/.curator_state

profiles/profiles/

.env
*.token
*.key
auth.json
GITEOF
    fi
    echo -e "${GREEN}  ✓ .gitignore 已创建${NC}"
fi

# 复制同步脚本到同步目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/sync-push.sh" ] && [ -f "$SCRIPT_DIR/sync-pull.sh" ]; then
    cp "$SCRIPT_DIR/sync-push.sh" "$SYNC_DIR/sync-push.sh"
    cp "$SCRIPT_DIR/sync-pull.sh" "$SYNC_DIR/sync-pull.sh"
    chmod +x "$SYNC_DIR/sync-push.sh" "$SYNC_DIR/sync-pull.sh"
    echo -e "${GREEN}  ✓ 同步脚本已安装${NC}"
fi

# ==========================================
# systemd 定时器
# ==========================================
echo ""
echo -e "${YELLOW}▶ 设置自动备份...${NC}"

# 读取配置中的间隔（如果有）
SYNC_INTERVAL=30

if command -v systemctl &>/dev/null && [ "$OS" = "linux" ]; then
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"

    PUSH_SCRIPT="$SYNC_DIR/sync-push.sh"

    # 创建服务
    cat > "$SYSTEMD_DIR/hermes-sync.service" << SERVICEEOF
[Unit]
Description=Hermes Sync — 自动备份到 GitHub
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$PUSH_SCRIPT
WorkingDirectory=$SYNC_DIR
Environment="HOME=$HOME"
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
SERVICEEOF

    # 创建定时器
    cat > "$SYSTEMD_DIR/hermes-sync.timer" << TIMEREOF
[Unit]
Description=Hermes Sync 定时器 — 自动备份
Requires=hermes-sync.service

[Timer]
OnCalendar=*:0/${SYNC_INTERVAL}
OnBootSec=2min
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable hermes-sync.timer 2>/dev/null || true
    systemctl --user start hermes-sync.timer 2>/dev/null || true

    echo -e "${GREEN}  ✓ systemd 定时器已启用（每${SYNC_INTERVAL}分钟）${NC}"

    # 修改 Gateway 服务（如果存在）
    GATEWAY_SERVICE="$SYSTEMD_DIR/hermes-gateway.service"
    if [ -f "$GATEWAY_SERVICE" ]; then
        PULL_SCRIPT="$SYNC_DIR/sync-pull.sh"
        if ! grep -q "ExecStartPre.*sync-pull" "$GATEWAY_SERVICE" 2>/dev/null; then
            cp "$GATEWAY_SERVICE" "${GATEWAY_SERVICE}.bak.hermes-sync"
            sed -i '/^ExecStart=/i ExecStartPre='"$PULL_SCRIPT" "$GATEWAY_SERVICE"
            systemctl --user daemon-reload 2>/dev/null || true
            echo -e "${GREEN}  ✓ Gateway 启动前自动拉取已配置${NC}"
        fi
    fi
else
    echo -e "${YELLOW}  ⚠ 未检测到 systemd（非 Linux 或 WSL）${NC}"
    echo "  请手动设置定时任务:"
    echo "  crontab -e"
    echo "  添加: */30 * * * * $SYNC_DIR/sync-push.sh"
fi

# ==========================================
# WSL 特殊处理：配置 sudoers（cron 免密启动）
# ==========================================
if grep -qi "microsoft" /proc/version 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}▶ WSL 环境检测到，配置 sudoers...${NC}"
    SUDOERS_FILE="/etc/sudoers.d/hermes-cron"
    if [ ! -f "$SUDOERS_FILE" ]; then
        echo "$USER ALL=(ALL) NOPASSWD: /usr/sbin/service cron start, /usr/sbin/service cron status" | sudo tee "$SUDOERS_FILE" > /dev/null 2>&1
        sudo chmod 440 "$SUDOERS_FILE" 2>/dev/null && \
            echo -e "${GREEN}  ✓ sudoers 已配置（cron 免密启动）${NC}" || \
            echo -e "${YELLOW}  ⚠ sudoers 配置失败，请手动运行: bash ~/.hermes/scripts/setup-sudoers.sh${NC}"
    fi
fi

# ==========================================
# 完成
# ==========================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅  安装完成！                   ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║  同步目录: ~/.hermes-sync/                   ║${NC}"
echo -e "${GREEN}║  配置文件: ~/.hermes-sync/sync.conf           ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║  手动同步:                                    ║${NC}"
echo -e "${GREEN}║    bash ~/.hermes-sync/sync-push.sh           ║${NC}"
echo -e "${GREEN}║    bash ~/.hermes-sync/sync-pull.sh           ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
