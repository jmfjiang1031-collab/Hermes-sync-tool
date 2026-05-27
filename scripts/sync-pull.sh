#!/bin/bash
# ============================================================
# Hermes Sync — 下载脚本 (GitHub → 本地)
# 只同步共享数据（skills, profiles, memories, SOUL.md）
# 兼容 WSL（需代理）和 Windows 原生环境
# ============================================================
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
load_config

log_info "══════════════════════════════════════"
log_info "  Hermes Sync — 下载 (GitHub → 本地)"
log_info "══════════════════════════════════════"

check_dependencies || exit 1
check_token || exit 1

cd "$HERMES_SYNC_DIR"

# 拉取最新
log_info "正在从 GitHub 拉取..."
BEFORE=$(git rev-parse HEAD 2>/dev/null || echo "none")

if ! git_fetch_with_auth 2>&1 | tee -a "$LOG_FILE"; then
    log_warn "直连失败，尝试代理..."
    export https_proxy=http://127.0.0.1:7897
    export http_proxy=http://127.0.0.1:7897
    if ! git_fetch_with_auth 2>&1 | tee -a "$LOG_FILE"; then
        log_error "拉取失败——网络不通"
        exit 1
    fi
fi

git reset --hard origin/"$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"

# 恢复所有 .sh 脚本的可执行权限（Windows Git core.filemode=false 不保存执行位）
fix_sh_permissions "$HERMES_SYNC_DIR" "false"

AFTER=$(git rev-parse HEAD 2>/dev/null || echo "none")
if [ "$BEFORE" != "$AFTER" ]; then
    log_info "✅ 已更新到最新版本"
else
    log_info "✅ 已是最新版本"
fi

mkdir -p "$BACKUP_DIR"

# 只同步共享数据
COPIED_COUNT=0
for item in "${SYNC_ITEMS[@]}"; do
    src="$HERMES_SYNC_DIR/$item"
    dst="$HERMES_DIR/$item"
    [ ! -e "$src" ] && continue

    # 备份本地版本
    if [ -e "$dst" ]; then
        cp -r "$dst" "$BACKUP_DIR/${item}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi

    log_info "  更新: $item"
    rm -rf "$dst" 2>/dev/null || true
    cp -r "$src" "$dst"
    ((COPIED_COUNT++)) || true
done

# ★★★ 防止 profiles 递归嵌套 ★★★
rm -rf "$HERMES_DIR/profiles/profiles" 2>/dev/null || true

# 清理 3 天前的旧备份
find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +3 -exec rm -rf {} + 2>/dev/null || true
log_debug "  🧹 清理旧备份（保留3天）"

log_info "已更新 $COPIED_COUNT 个同步项"
log_info "✅ 下载完成"
log_info "══════════════════════════════════════"
