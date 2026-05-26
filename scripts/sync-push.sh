#!/bin/bash
# ============================================================
# Hermes Sync — 上传脚本 (本地 → GitHub)
# 只同步共享数据（skills, profiles, memories, SOUL.md）
# 兼容 WSL（需代理）和 Windows 原生环境
# ============================================================
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
load_config

log_info "══════════════════════════════════════"
log_info "  Hermes Sync — 上传 (本地 → GitHub)"
log_info "══════════════════════════════════════"

# 检查依赖
check_dependencies || exit 1
check_token || exit 1

# TOKEN 由 git_push_with_auth 内部获取，在此无需重复赋值

cd "$HERMES_SYNC_DIR"

# 确保仓库已初始化
if [ ! -d ".git" ]; then
    log_warn "Git 仓库未初始化，正在初始化..."
    git init
    git checkout -b "$GIT_BRANCH" 2>/dev/null || git checkout "$GIT_BRANCH"
fi

# 先拉取远程变更，避免多设备分支分叉
log_info "正在拉取远程变更..."
if ! git_fetch_with_auth 2>&1 | tee -a "$LOG_FILE"; then
    log_warn "拉取失败（可能网络不通）"
fi
git reset --hard origin/"$GIT_BRANCH" 2>/dev/null || true

# --- 同步文件 ---
log_info "正在同步文件..."

COPIED_COUNT=0
for item in "${SYNC_ITEMS[@]}"; do
    src="$HERMES_DIR/$item"
    dst="$HERMES_SYNC_DIR/"

    if [ -e "$src" ]; then
        if [ -d "$src" ]; then
            # 先删除目标，再用 cp 复制（兼容 Windows 无 rsync）
            rm -rf "$dst${item}" 2>/dev/null || true
            cp -r "$src" "$dst${item}" 2>/dev/null && log_debug "  ✓ $item" || log_warn "  ! $item (复制失败)"
        else
            cp "$src" "$dst${item}" 2>/dev/null && log_debug "  ✓ $item" || log_warn "  ! $item (复制失败)"
        fi
        ((COPIED_COUNT++)) || true
    else
        log_debug "  - $item (不存在)"
    fi
done

log_info "已处理 $COPIED_COUNT 个同步项"

# 排除本地不必要的文件
rm -rf "$HERMES_SYNC_DIR/skills/.curator_backups" 2>/dev/null || true
rm -f "$HERMES_SYNC_DIR/skills/.usage.json" 2>/dev/null || true
rm -f "$HERMES_SYNC_DIR/skills/.curator_state" 2>/dev/null || true
rm -f "$HERMES_SYNC_DIR/skills/.bundled_manifest" 2>/dev/null || true
rm -rf "$HERMES_SYNC_DIR/skills/.hub" 2>/dev/null || true
find "$HERMES_SYNC_DIR/profiles" -name ".curator_backups" -type d -exec rm -rf {} + 2>/dev/null || true

# --- Git 操作 ---
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    log_info "没有新变更，跳过提交"
    log_info "══════════════════════════════════════"
    exit 0
fi

log_info "检测到变更，正在提交..."
git add -A

# 恢复所有 .sh 脚本的可执行权限（Windows Git core.filemode=false 不保存执行位）
fix_sh_permissions "$HERMES_SYNC_DIR" "true"
git add -A  # 重新 add（确保修正后的权限入库）

COMMIT_MSG=$(generate_commit_msg)
git commit -m "$COMMIT_MSG"

# 推送
log_info "正在推送到 GitHub..."
if git_push_with_auth "$GIT_BRANCH" | tee -a "$LOG_FILE"; then
    log_info "✅ 上传成功"
else
    log_warn "推送失败，尝试代理..."
    sleep 2
    export https_proxy=http://127.0.0.1:7897
    export http_proxy=http://127.0.0.1:7897
    if git_push_with_auth "$GIT_BRANCH" | tee -a "$LOG_FILE"; then
        log_info "✅ 上传成功（经代理）"
    else
        log_warn "代理也失败，尝试拉取合并后重推..."
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
fi

log_info "══════════════════════════════════════"
