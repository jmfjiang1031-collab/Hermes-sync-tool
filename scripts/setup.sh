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
║     多终端自动同步 Profiles/Skills/记忆      ║
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

# 检查依赖
MISSING=()
for cmd in git rsync curl; do
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
# GitHub Token
# ==========================================
echo ""
echo -e "${YELLOW}▶ 配置 GitHub Token${NC}"
echo ""
echo "需要 GitHub Personal Access Token 来访问同步仓库。"
echo "如果还没有，请在浏览器打开:"
echo -e "  ${BLUE}https://github.com/settings/tokens${NC}"
echo "  点击 Generate new token (classic)"
echo "  勾选 'repo' 权限即可"
echo ""

read -r -p "请输入 Token (或按回车跳过): " TOKEN

if [ -n "$TOKEN" ]; then
    echo "$TOKEN" > "$HOME/.hermes-sync/.github-token"
    chmod 600 "$HOME/.hermes-sync/.github-token" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Token 已保存${NC}"
else
    echo -e "${YELLOW}  ⚠ 跳过 Token 配置（之后可手动设置）${NC}"
fi

# ==========================================
# 数据仓库
# ==========================================
echo ""
echo -e "${YELLOW}▶ 配置数据仓库${NC}"
echo ""
echo "你的同步数据存在哪里？"
echo "  1) 使用已有私有仓库（已有 hermes-sync）"
echo "  2) 创建新的私有仓库"
echo "  3) 跳过（仅安装脚本）"
echo ""

read -r -p "请选择 [1-3]: " REPO_CHOICE

SYNC_DIR="$HOME/.hermes-sync"
mkdir -p "$SYNC_DIR"

case "$REPO_CHOICE" in
    1)
        read -r -p "GitHub 用户名: " GH_USER
        read -r -p "仓库名 (默认 hermes-sync): " GH_REPO
        GH_REPO="${GH_REPO:-hermes-sync}"

        if [ -n "$TOKEN" ] || [ "$HAS_SSH" = true ]; then
            if [ "$HAS_SSH" = true ]; then
                CLONE_URL="git@github.com-hermes-sync:${GH_USER}/${GH_REPO}.git"
                echo "  使用 SSH 方式..."
            else
                CLONE_URL="https://${TOKEN}@github.com/${GH_USER}/${GH_REPO}.git"
                echo "  使用 HTTPS+Token 方式..."
            fi
            if [ -d "$SYNC_DIR/.git" ]; then
                echo "  已有仓库，正在更新..."
                cd "$SYNC_DIR"
                git remote set-url origin "$CLONE_URL" 2>/dev/null || git remote add origin "$CLONE_URL"
                git pull origin main 2>/dev/null || echo "  拉取失败，将在首次同步时重试"
            else
                git clone "$CLONE_URL" "$SYNC_DIR" 2>/dev/null || echo "  克隆失败，将在首次同步时重试"
            fi
            echo -e "${GREEN}  ✓ 数据仓库已关联${NC}"
        fi
        ;;
    2)
        if [ -z "$TOKEN" ]; then
            echo -e "${RED}  ❌ 需要先配置 Token${NC}"
        else
            read -r -p "新仓库名 (默认 hermes-sync): " NEW_REPO
            NEW_REPO="${NEW_REPO:-hermes-sync}"

            CREATE_RESULT=$(curl -s --connect-timeout 15 -X POST \
                -H "Authorization: token $TOKEN" \
                https://api.github.com/user/repos \
                -d "{\"name\":\"$NEW_REPO\",\"private\":true,\"auto_init\":false}" 2>/dev/null)

            if echo "$CREATE_RESULT" | grep -q "html_url"; then
                echo -e "${GREEN}  ✓ 仓库已创建: $NEW_REPO${NC}"
            else
                echo -e "${YELLOW}  ⚠ 仓库创建可能失败，请手动创建后重试${NC}"
            fi
        fi
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
# 修改后立即生效，无需重启

# GitHub Token（可选，也可用环境变量 HERMES_SYNC_TOKEN）
# GITHUB_TOKEN=ghp_xxxxxxxxxxxx

# 同步间隔（分钟），用于 systemd 定时器
SYNC_INTERVAL=30

# 冲突处理策略: backup(备份旧文件) | skip(跳过) | overwrite(直接覆盖)
CONFLICT_STRATEGY=backup

# Git 分支
GIT_BRANCH=main

# 同步内容（逗号分隔）
SYNC_ITEMS=profiles,skills,memories,cron,SOUL.md,config.yaml,.hermes_history,hooks

# 排除模式（逗号分隔）
EXCLUDE_ITEMS=node_modules/,venv/,__pycache__/,*.pyc,.env,*.bak,cache/,audio_cache/,image_cache/,logs/,state.db*,kanban.db*,response_store.db*,gateway.*,processes.json,sessions/,checkpoints/,state-snapshots/

# 日志级别: 0=安静 1=普通 2=详细
LOG_LEVEL=1

# 认证方式: auto(自动检测) | ssh | https
AUTH_METHOD=auto
CONFEOF

echo -e "${GREEN}  ✓ 配置已生成: $SYNC_DIR/sync.conf${NC}"

# ==========================================
# systemd 定时器
# ==========================================
echo ""
echo -e "${YELLOW}▶ 设置自动备份...${NC}"

if command -v systemctl &>/dev/null && [ "$OS" = "linux" ]; then
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"

    # 检查是否从源码安装（脚本在 scripts/ 子目录）
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/sync-push.sh" ]; then
        PUSH_SCRIPT="$SCRIPT_DIR/sync-push.sh"
    elif [ -f "$SYNC_DIR/scripts/sync-push.sh" ]; then
        PUSH_SCRIPT="$SYNC_DIR/scripts/sync-push.sh"
    else
        PUSH_SCRIPT="$SYNC_DIR/sync-push.sh"
    fi

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

    # 修改 Gateway 服务
    GATEWAY_SERVICE="$SYSTEMD_DIR/hermes-gateway.service"
    if [ -f "$GATEWAY_SERVICE" ]; then
        PULL_SCRIPT="${PUSH_SCRIPT//push/pull}"
        if ! grep -q "ExecStartPre.*sync-pull" "$GATEWAY_SERVICE"; then
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
    echo "  添加: */30 * * * * $SYNC_DIR/scripts/sync-push.sh"
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
echo -e "${GREEN}║    bash ~/.hermes-sync/scripts/sync-push.sh   ║${NC}"
echo -e "${GREEN}║    bash ~/.hermes-sync/scripts/sync-pull.sh   ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
