#!/bin/bash
# ============================================================
# Hermes Sync — 下载脚本 (GitHub → 本地)
# ============================================================
set -e
set -o pipefail  # 确保管道中任一命令失败都能被捕获

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
load_config

log_info "══════════════════════════════════════"
log_info "  Hermes Sync — 下载 (GitHub → 本地)"
log_info "══════════════════════════════════════"

# 检查依赖
check_dependencies || exit 1
check_token || exit 1

TOKEN=$(get_token)

cd "$HERMES_SYNC_DIR"

# 如果 git 仓库不存在，跳过
if [ ! -d ".git" ]; then
    log_warn "Git 仓库未初始化，跳过下载"
    exit 0
fi

# 确保 remote 正确
USERNAME=$(get_github_username "$TOKEN")
if [ -n "$USERNAME" ]; then
    ensure_remote "$USERNAME" "hermes-sync"
fi

# --- 拉取（使用认证感知的拉取函数） ---
log_info "正在从 GitHub 拉取..."
if ! git_pull_with_auth "$GIT_BRANCH" | tee -a "$LOG_FILE"; then
    log_warn "拉取失败（网络问题或仓库不存在）"
    exit 0
fi

# 读取上次同步时间
LAST_SYNC="1970-01-01"
if [ -f "$LAST_PULL_FILE" ]; then
    LAST_SYNC=$(cat "$LAST_PULL_FILE")
fi

# --- 还原文件 ---
log_info "正在还原文件..."
RESTORED_COUNT=0

for item in "${SYNC_ITEMS[@]}"; do
    src="$HERMES_SYNC_DIR/$item"
    dst="$HERMES_DIR/$item"

    if [ ! -e "$src" ]; then
        continue
    fi

    # 检查是否需要更新
    if [ -e "$dst" ] && [ "$(find "$src" -newer "$LAST_SYNC" 2>/dev/null | head -1)" = "" ]; then
        log_debug "  - $item (未变更)"
        continue
    fi

    # 冲突处理
    if [ -e "$dst" ]; then
        case "$CONFLICT_STRATEGY" in
            backup)
                backup_file "$dst" "$item"
                ;;
            skip)
                log_debug "  - $item (已跳过，策略=skip)"
                continue
                ;;
            overwrite)
                log_debug "  - $item (覆盖模式)"
                ;;
        esac
    fi

    # 复制
    if [ -d "$src" ]; then
        sync_copy "$src/" "$dst/"
        # 清理目标中源没有的旧文件
        rsync -a --delete --existing --ignore-existing "$src/" "$dst/" 2>/dev/null || true
    else
        cp -a "$src" "$dst"
    fi
    log_debug "  ✓ $item"
    ((RESTORED_COUNT++)) || true
done

# 记录同步时间
date '+%Y-%m-%d %H:%M:%S' > "$LAST_PULL_FILE"

log_info "已还原 $RESTORED_COUNT 个同步项"
log_info "✅ 下载完成"
log_info "══════════════════════════════════════"
