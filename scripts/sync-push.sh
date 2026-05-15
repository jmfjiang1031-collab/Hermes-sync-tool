#!/bin/bash
# ============================================================
# Hermes Sync — 上传脚本 (本地 → GitHub)
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
load_config

log_info "══════════════════════════════════════"
log_info "  Hermes Sync — 上传 (本地 → GitHub)"
log_info "══════════════════════════════════════"

# 检查依赖
check_dependencies || exit 1
check_token || exit 1

TOKEN=$(get_token)

cd "$HERMES_SYNC_DIR"

# 确保仓库已初始化
if [ ! -d ".git" ]; then
    log_warn "Git 仓库未初始化，正在初始化..."
    git init
    git checkout -b "$GIT_BRANCH" 2>/dev/null || git checkout "$GIT_BRANCH"
fi

# 获取用户名并设置 remote
USERNAME=$(get_github_username "$TOKEN")
if [ -z "$USERNAME" ]; then
    log_warn "无法获取 GitHub 用户名（网络问题），将使用现有 remote"
else
    ensure_remote "$TOKEN" "$USERNAME" "hermes-sync"
fi

# --- 同步文件 ---
log_info "正在同步文件..."

COPIED_COUNT=0
for item in "${SYNC_ITEMS[@]}"; do
    src="$HERMES_DIR/$item"
    dst="$HERMES_SYNC_DIR/"

    if [ -e "$src" ]; then
        if [ -d "$src" ]; then
            sync_copy "$src/" "$dst${item}/" "--delete"
        else
            sync_copy "$src" "$dst${item}"
        fi
        log_debug "  ✓ $item"
        ((COPIED_COUNT++)) || true
    else
        log_debug "  - $item (不存在)"
    fi
done

log_info "已处理 $COPIED_COUNT 个同步项"

# --- Git 操作 ---
# 检查是否有实质性变更
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    log_info "没有新变更，跳过提交"
    log_info "══════════════════════════════════════"
    exit 0
fi

log_info "检测到变更，正在提交..."
git add -A

COMMIT_MSG=$(generate_commit_msg)
git commit -m "$COMMIT_MSG"

# 推送
log_info "正在推送到 GitHub..."
if git push origin "$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
    log_info "✅ 上传成功"
else
    log_error "上传失败，请检查网络和 Token"
    exit 1
fi

log_info "══════════════════════════════════════"
