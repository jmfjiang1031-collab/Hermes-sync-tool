#!/bin/bash
# ============================================================
# Hermes Sync — 公共函数库
# 被所有同步脚本引用，提供统一的日志、配置、Token管理
# ============================================================

# --- 路径常量 ---
HERMES_SYNC_DIR="${HERMES_SYNC_DIR:-$HOME/.hermes-sync}"
HERMES_DIR="${HERMES_DIR:-$HOME/.hermes}"
CONFIG_FILE="${HERMES_SYNC_DIR}/sync.conf"
TOKEN_FILE="${HERMES_SYNC_DIR}/.github-token"
LOG_FILE="${HERMES_SYNC_DIR}/sync.log"
BACKUP_DIR="${HERMES_SYNC_DIR}/backups"
LAST_PULL_FILE="${HERMES_SYNC_DIR}/.last-pull-time"

# 默认配置
DEFAULT_SYNC_INTERVAL=30          # 分钟
DEFAULT_CONFLICT_STRATEGY="backup"  # backup | skip | overwrite
DEFAULT_GIT_BRANCH="main"
DEFAULT_COMMIT_TEMPLATE="自动同步: {timestamp} [{hostname}]"

# --- 日志 ---
LOG_LEVEL="${LOG_LEVEL:-1}"  # 0=quiet 1=normal 2=verbose

log() {
    local level="${2:-1}"
    if [ "$LOG_LEVEL" -ge "$level" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    fi
}

log_error() { log "❌ $1" 0; }
log_warn()  { log "⚠️  $1" 0; }
log_info()  { log "$1" 1; }
log_debug() { log "🔍 $1" 2; }

# --- Token 管理 ---
get_token() {
    # 优先级：环境变量 > 配置文件 > Token文件
    if [ -n "$HERMES_SYNC_TOKEN" ]; then
        echo "$HERMES_SYNC_TOKEN"
        return 0
    fi

    if [ -f "$CONFIG_FILE" ]; then
        local token_from_conf
        token_from_conf=$(grep -E '^GITHUB_TOKEN=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"'"' ")
        if [ -n "$token_from_conf" ]; then
            echo "$token_from_conf"
            return 0
        fi
    fi

    if [ -f "$TOKEN_FILE" ]; then
        cat "$TOKEN_FILE"
        return 0
    fi

    return 1
}

# --- 配置读取 ---
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # 读取配置文件中的变量（安全的 source）
        while IFS='=' read -r key value; do
            key=$(echo "$key" | tr -d ' ')
            value=$(echo "$value" | tr -d '"'"' ")
            case "$key" in
                GITHUB_TOKEN)      : ;;  # Token 由 get_token 处理
                SYNC_INTERVAL)     SYNC_INTERVAL="$value" ;;
                CONFLICT_STRATEGY) CONFLICT_STRATEGY="$value" ;;
                GIT_BRANCH)        GIT_BRANCH="$value" ;;
                COMMIT_TEMPLATE)   COMMIT_TEMPLATE="$value" ;;
                SYNC_ITEMS)        IFS=',' read -ra SYNC_ITEMS <<< "$value" ;;
                EXCLUDE_ITEMS)     IFS=',' read -ra EXCLUDE_ITEMS <<< "$value" ;;
                LOG_LEVEL)         LOG_LEVEL="$value" ;;
                NOTIFY_ON_SUCCESS) NOTIFY_ON_SUCCESS="$value" ;;
                NOTIFY_ON_FAILURE) NOTIFY_ON_FAILURE="$value" ;;
            esac
        done < <(grep -v '^#' "$CONFIG_FILE" | grep -v '^$')
    fi

    # 设置默认值
    SYNC_INTERVAL="${SYNC_INTERVAL:-$DEFAULT_SYNC_INTERVAL}"
    CONFLICT_STRATEGY="${CONFLICT_STRATEGY:-$DEFAULT_CONFLICT_STRATEGY}"
    GIT_BRANCH="${GIT_BRANCH:-$DEFAULT_GIT_BRANCH}"
    COMMIT_TEMPLATE="${COMMIT_TEMPLATE:-$DEFAULT_COMMIT_TEMPLATE}"

    # 默认同步项
    if [ -z "${SYNC_ITEMS[*]}" ]; then
        SYNC_ITEMS=("profiles" "skills" "memories" "cron" "SOUL.md" "config.yaml" ".hermes_history" "hooks")
    fi

    # 默认排除项
    if [ -z "${EXCLUDE_ITEMS[*]}" ]; then
        EXCLUDE_ITEMS=(
            "node_modules/" "venv/" "__pycache__/" "*.pyc"
            ".env" "*.bak" "*.token" "*.key"
            "cache/" "audio_cache/" "image_cache/"
            "logs/" "*.log"
            "state.db" "state.db-*" "kanban.db" "kanban.db-*" "response_store.db*"
            "gateway.pid" "gateway.lock" "gateway_state.json" "processes.json"
            "sessions/" "checkpoints/" "state-snapshots/"
            "sandboxes/" "pairing/"
            "weixin/" "feishu_*"
        )
    fi
}

# --- GitHub 操作 ---
get_github_username() {
    local token="$1"
    curl -s --connect-timeout 10 -H "Authorization: token $token" \
        https://api.github.com/user 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('login',''))" 2>/dev/null
}

ensure_remote() {
    local token="$1"
    local username="$2"
    local repo="${3:-hermes-sync}"

    cd "$HERMES_SYNC_DIR"

    if git remote get-url origin &>/dev/null; then
        # 检查是否需要更新
        local current_url
        current_url=$(git remote get-url origin)
        if ! echo "$current_url" | grep -q "$token"; then
            git remote set-url origin "https://${token}@github.com/${username}/${repo}.git"
            log_info "已更新 git remote"
        fi
    else
        git remote add origin "https://${token}@github.com/${username}/${repo}.git"
        log_info "已添加 git remote"
    fi
}

# --- 备份管理 ---
backup_file() {
    local src="$1"
    local item_name="$2"

    if [ ! -e "$src" ]; then
        return 0
    fi

    local backup_name="${item_name//\//_}_$(date '+%Y%m%d_%H%M%S')"
    cp -a "$src" "$BACKUP_DIR/$backup_name" 2>/dev/null && \
        log_debug "备份: $item_name → $backup_name"

    # 清理超过 30 天的备份
    find "$BACKUP_DIR" -type f -mtime +30 -delete 2>/dev/null || true
}

# --- 同步操作 ---
# rsync 封装，带排除列表
sync_copy() {
    local src="$1"
    local dst="$2"
    local delete_flag="${3:-}"

    local exclude_args=()
    for pattern in "${EXCLUDE_ITEMS[@]}"; do
        exclude_args+=(--exclude="$pattern")
    done

    if [ "$delete_flag" = "--delete" ]; then
        rsync -a --delete "${exclude_args[@]}" "$src" "$dst" 2>/dev/null
    else
        rsync -a "${exclude_args[@]}" "$src" "$dst" 2>/dev/null
    fi
}

# 提交信息生成
generate_commit_msg() {
    local msg="$COMMIT_TEMPLATE"
    msg="${msg//\{timestamp\}/$(date '+%Y-%m-%d %H:%M')}"
    msg="${msg//\{hostname\}/$(hostname)}"
    msg="${msg//\{user\}/$(whoami)}"
    echo "$msg"
}

# --- 初始化检查 ---
check_dependencies() {
    local missing=()

    for cmd in git rsync curl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "缺少依赖: ${missing[*]}"
        echo "请安装: sudo apt install ${missing[*]}"
        return 1
    fi
    return 0
}

check_token() {
    local token
    token=$(get_token 2>/dev/null)
    if [ -z "$token" ]; then
        log_error "未找到 GitHub Token"
        echo ""
        echo "请通过以下方式之一配置 Token："
        echo "  1. 环境变量: export HERMES_SYNC_TOKEN=ghp_xxx"
        echo "  2. 配置文件: $CONFIG_FILE 中设置 GITHUB_TOKEN"
        echo "  3. Token文件: $TOKEN_FILE"
        echo ""
        echo "创建 Token: https://github.com/settings/tokens"
        echo "权限: 勾选 'repo'"
        return 1
    fi
    return 0
}

# --- 初始化 ---
mkdir -p "$BACKUP_DIR" 2>/dev/null || true
