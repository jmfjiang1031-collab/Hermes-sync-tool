#!/bin/bash
# ============================================================
# Hermes Sync — 拉取同步（GitHub → 本机）
# 同步内容：skills, profiles, SOUL.md
# ============================================================
set -e
set -o pipefail

SYNC_DIR="${HERMES_SYNC_DIR:-$HOME/.hermes-sync}"
HERMES_DIR="${HERMES_DIR:-$HOME/.hermes}"
BACKUP_DIR="${HOME}/.hermes-sync-backups"
SYNC_ITEMS=("skills" "profiles" "SOUL.md")
REMOTE="${HERMES_SYNC_REMOTE:-git@github.com:YOUR_USERNAME/hermes-sync.git}"
BRANCH="${HERMES_SYNC_BRANCH:-main}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "═══ 拉取同步（GitHub → 本机）═══"

cd "$SYNC_DIR"

log "正在从 GitHub 拉取..."
BEFORE=$(git rev-parse HEAD 2>/dev/null || echo "none")

if ! git fetch origin "$BRANCH" 2>&1; then
    log "❌ 拉取失败，请检查 SSH 连接和代理状态"
    exit 1
fi

git reset --hard "origin/$BRANCH" 2>&1

AFTER=$(git rev-parse HEAD 2>/dev/null || echo "none")
if [ "$BEFORE" != "$AFTER" ]; then
    log "✅ 已更新到最新版本"
else
    log "✅ 已是最新版本"
fi

# 清理运行时文件
rm -rf "$SYNC_DIR/skills/.curator_backups" "$SYNC_DIR/skills/.usage.json" \
       "$SYNC_DIR/skills/apple" "$SYNC_DIR/profiles/profiles" 2>/dev/null || true

# 备份 + 复制
mkdir -p "$BACKUP_DIR"
find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +3 -exec rm -rf {} + 2>/dev/null || true

log "正在更新本地文件..."
for item in "${SYNC_ITEMS[@]}"; do
    src="$SYNC_DIR/$item"
    dst="$HERMES_DIR/$item"
    [ ! -e "$src" ] && continue

    if [ -e "$dst" ]; then
        cp -r "$dst" "$BACKUP_DIR/${item}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi

    rm -rf "$dst" 2>/dev/null || true
    cp -r "$src" "$dst"
    log "  ✓ $item"
done

rm -rf "$HERMES_DIR/profiles/profiles" 2>/dev/null || true

log "✅ 拉取完成"
log "═══ 拉取完成 ═══"
