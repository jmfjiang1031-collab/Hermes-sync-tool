#!/bin/bash
# ============================================================
# Hermes Sync — 上传脚本 (本地 → GitHub)
# ============================================================
set -e
set -o pipefail  # 确保管道中任一命令失败都能被捕获

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
    ensure_remote "$USERNAME" "hermes-sync"
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

# 推送（使用认证感知的推送函数，自动选择 SSH 或 HTTPS+Token）
log_info "正在推送到 GitHub..."
if git_push_with_auth "$GIT_BRANCH" | tee -a "$LOG_FILE"; then
    log_info "✅ 上传成功"
else
    log_error "上传失败——远程可能有新提交，尝试拉取合并后重推..."
    if git_pull_merge_with_auth "$GIT_BRANCH" | tee -a "$LOG_FILE"; then
        log_info "合并成功，重新推送..."
        if git_push_with_auth "$GIT_BRANCH" | tee -a "$LOG_FILE"; then
            log_info "✅ 上传成功"
        else
            log_error "上传失败，请检查网络和认证配置"
            exit 1
        fi
    else
        log_error "合并失败，请手动处理冲突"
        exit 1
    fi
fi

log_info "══════════════════════════════════════"
