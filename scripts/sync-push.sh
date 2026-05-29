#!/bin/bash
# ============================================================
# Hermes Sync — 推送同步（本机 → GitHub）
# 同步内容：skills, profiles, SOUL.md
# ============================================================
set -e
set -o pipefail

SYNC_DIR="${HERMES_SYNC_DIR:-$HOME/.hermes-sync}"
HERMES_DIR="${HERMES_DIR:-$HOME/.hermes}"
SYNC_ITEMS=("skills" "profiles" "SOUL.md")
REMOTE="${HERMES_SYNC_REMOTE:-git@github.com:YOUR_USERNAME/hermes-sync.git}"
BRANCH="${HERMES_SYNC_BRANCH:-main}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "═══ 推送同步（本机 → GitHub）═══"

cd "$SYNC_DIR"

# 复制同步项
log "正在复制..."
for item in "${SYNC_ITEMS[@]}"; do
    src="$HERMES_DIR/$item"
    if [ -e "$src" ]; then
        rm -rf "$SYNC_DIR/$item" 2>/dev/null || true
        cp -r "$src" "$SYNC_DIR/$item"
        log "  ✓ $item"
    fi
done

# 清理运行时文件
rm -rf "$SYNC_DIR/skills/.curator_backups" "$SYNC_DIR/skills/.usage.json" \
       "$SYNC_DIR/skills/.curator_state" "$SYNC_DIR/skills/.bundled_manifest" \
       "$SYNC_DIR/skills/.hub" "$SYNC_DIR/skills/apple" 2>/dev/null || true
rm -rf "$SYNC_DIR/profiles/profiles" 2>/dev/null || true
find "$SYNC_DIR/profiles" -name ".curator_backups" -type d -exec rm -rf {} + 2>/dev/null || true

# Git 操作
git add -A

if git diff --cached --quiet; then
    log "没有新变更"
    log "═══ 推送完成（无变更）═══"
    exit 0
fi

COMMIT_MSG="同步: $(date '+%Y-%m-%d %H:%M') [$(hostname)]"
git commit -m "$COMMIT_MSG"
log "  已提交: $COMMIT_MSG"

if git push "$REMOTE" "$BRANCH" 2>&1; then
    log "✅ 推送成功"
else
    log "❌ 推送失败，请检查 SSH 连接和代理状态"
    exit 1
fi

log "═══ 推送完成 ═══"
