#!/bin/bash
# ============================================================
# Hermes Sync — 公共函数库
# 被所有同步脚本引用，提供统一的日志、配置、Token管理
# 支持 SSH 和 HTTPS+Token 两种认证方式
# ============================================================

# --- 路径常量 ---
HERMES_SYNC_DIR="${HERMES_SYNC_DIR:-$HOME/.hermes-sync}"
HERMES_DIR="${HERMES_DIR:-$HOME/.hermes}"
CONFIG_FILE="${HERMES_SYNC_DIR}/sync.conf"
TOKEN_FILE="${HERMES_SYNC_DIR}/.github-token"
LOG_FILE="${HERMES_SYNC_DIR}/sync.log"
BACKUP_DIR="${HOME}/.hermes-sync-backups"
LAST_PULL_FILE="${HERMES_SYNC_DIR}/.last-pull-time"  # shellcheck disable=SC2034

# 默认配置
DEFAULT_SYNC_INTERVAL=30          # 分钟
DEFAULT_CONFLICT_STRATEGY="backup"  # backup | skip | overwrite
DEFAULT_GIT_BRANCH="main"
DEFAULT_AUTH_METHOD="auto"        # auto | ssh | https
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
            AUTH_METHOD)       AUTH_METHOD="$value" ;;
            COMMIT_TEMPLATE)   COMMIT_TEMPLATE="$value" ;;
                SYNC_ITEMS)        IFS=',' read -ra SYNC_ITEMS <<< "$value" ;;
                EXCLUDE_ITEMS)     IFS=',' read -ra EXCLUDE_ITEMS <<< "$value" ;;
                LOG_LEVEL)         LOG_LEVEL="$value" ;;
                NOTIFY_ON_SUCCESS) NOTIFY_ON_SUCCESS="$value" ;;  # shellcheck disable=SC2034
                NOTIFY_ON_FAILURE) NOTIFY_ON_FAILURE="$value" ;;  # shellcheck disable=SC2034
            esac
        done < <(grep -v '^#' "$CONFIG_FILE" | grep -v '^$')
    fi

    # 设置默认值
    SYNC_INTERVAL="${SYNC_INTERVAL:-$DEFAULT_SYNC_INTERVAL}"
    CONFLICT_STRATEGY="${CONFLICT_STRATEGY:-$DEFAULT_CONFLICT_STRATEGY}"
    GIT_BRANCH="${GIT_BRANCH:-$DEFAULT_GIT_BRANCH}"
    AUTH_METHOD="${AUTH_METHOD:-$DEFAULT_AUTH_METHOD}"
    COMMIT_TEMPLATE="${COMMIT_TEMPLATE:-$DEFAULT_COMMIT_TEMPLATE}"

    # 默认同步项（只同步跨机器共享数据）
    # 不包含 config.yaml 和 cron（各平台不同，各管各的）
    if [ -z "${SYNC_ITEMS[*]}" ]; then
        SYNC_ITEMS=("profiles" "skills" "memories" "SOUL.md")
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
            ".usage.json"
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

# --- 认证方式检测 ---
# 返回 "ssh" 或 "https"
detect_auth_method() {
    # 如果用户显式指定了，直接用
    if [ "$AUTH_METHOD" = "ssh" ]; then
        echo "ssh"; return 0
    elif [ "$AUTH_METHOD" = "https" ]; then
        echo "https"; return 0
    fi

    # auto 模式：检测 SSH 配置是否存在
    # 检查常见的 SSH Host 别名
    for host in "github.com-hermes-sync" "github.com"; do
        if ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -T "$host" 2>&1 | grep -q "successfully authenticated"; then
            echo "ssh"; return 0
        fi
    done

    # 如果 SSH 不通，回退到 HTTPS
    echo "https"; return 0
}

# Git 远程仓库管理（支持 SSH 和 HTTPS）
ensure_remote() {
    local username="${1:-}"
    local repo="${2:-hermes-sync}"

    cd "$HERMES_SYNC_DIR" || { log_error "无法进入同步目录: $HERMES_SYNC_DIR"; return 1; }

    local auth_method
    auth_method=$(detect_auth_method)

    local target_url
    if [ "$auth_method" = "ssh" ]; then
        # SSH 方式：干净的 URL
        target_url="git@github.com-hermes-sync:${username}/${repo}.git"
    else
        # HTTPS 方式：URL 不含 Token（Token 在 push/pull 时通过 credential helper 传入）
        target_url="https://github.com/${username}/${repo}.git"
    fi

    if git remote get-url origin &>/dev/null; then
        local current_url
        current_url=$(git remote get-url origin)
        if [ "$current_url" != "$target_url" ]; then
            git remote set-url origin "$target_url"
            log_info "已更新 git remote → $target_url"
        fi
    else
        git remote add origin "$target_url"
        log_info "已添加 git remote → $target_url"
    fi
}

# --- 认证 Git 操作 ---
# 推送（自动选择 SSH 或 HTTPS+Token）
git_push_with_auth() {
    local branch="${1:-$GIT_BRANCH}"

    local auth_method
    auth_method=$(detect_auth_method)

    if [ "$auth_method" = "ssh" ]; then
        git push origin "$branch" 2>&1
    else
        local token
        token=$(get_token 2>/dev/null)
        if [ -z "$token" ]; then
            echo "❌ 未找到 GitHub Token" >&2
            return 1
        fi
        export GIT_TERMINAL_PROMPT=0
        export GIT_ASKPASS=/bin/true
        git -c "credential.helper=" \
            -c "credential.helper=!f() { echo \"password=$token\"; }; f" \
            push origin "$branch" 2>&1
    fi
}

# 拉取（自动选择 SSH 或 HTTPS+Token）
git_pull_with_auth() {
    local branch="${1:-$GIT_BRANCH}"

    local auth_method
    auth_method=$(detect_auth_method)

    if [ "$auth_method" = "ssh" ]; then
        git pull origin "$branch" 2>&1
    else
        local token
        token=$(get_token 2>/dev/null)
        if [ -z "$token" ]; then
            echo "⚠️  未找到 GitHub Token" >&2
            return 1
        fi
        export GIT_TERMINAL_PROMPT=0
        export GIT_ASKPASS=/bin/true
        git -c "credential.helper=" \
            -c "credential.helper=!f() { echo \"password=$token\"; }; f" \
            pull origin "$branch" 2>&1
    fi
}

# 拉取合并（处理 divergent branches）
git_pull_merge_with_auth() {
    local branch="${1:-$GIT_BRANCH}"

    local auth_method
    auth_method=$(detect_auth_method)

    if [ "$auth_method" = "ssh" ]; then
        git pull --no-rebase origin "$branch" 2>&1
    else
        local token
        token=$(get_token 2>/dev/null)
        if [ -z "$token" ]; then
            echo "⚠️  未找到 GitHub Token" >&2
            return 1
        fi
        export GIT_TERMINAL_PROMPT=0
        export GIT_ASKPASS=/bin/true
        git -c "credential.helper=" \
            -c "credential.helper=!f() { echo \"password=$token\"; }; f" \
            pull --no-rebase origin "$branch" 2>&1
    fi
}

# 仅拉取（不合并）
git_fetch_with_auth() {
    local branch="${1:-$GIT_BRANCH}"

    local auth_method
    auth_method=$(detect_auth_method)

    if [ "$auth_method" = "ssh" ]; then
        git fetch origin "$branch" 2>&1
    else
        local token
        token=$(get_token 2>/dev/null)
        if [ -z "$token" ]; then
            echo "⚠️  未找到 GitHub Token" >&2
            return 1
        fi
        export GIT_TERMINAL_PROMPT=0
        export GIT_ASKPASS=/bin/true
        git -c "credential.helper=" \
            -c "credential.helper=!f() { echo \"password=$token\"; }; f" \
            fetch origin "$branch" 2>&1
    fi
}

# --- 权限修复（跨平台关键！Windows Git core.filemode=false 不保存执行位） ---
fix_sh_permissions() {
    local target_dir="${1:-$HERMES_SYNC_DIR}"
    local fix_git_index="${2:-false}"  # true = 同时修复 Git 索引

    if [ ! -d "$target_dir" ]; then
        log_debug "目录不存在，跳过权限修复: $target_dir"
        return
    fi

    # 1. 修复文件系统执行权限
    find "$target_dir" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    log_info "  ✅ 恢复 $target_dir 下 .sh 脚本执行权限"

    # 2. 修复 Git 索引中的执行位（推送脚本用）
    if [ "$fix_git_index" = "true" ] && [ -d "$target_dir/.git" ]; then
        local repo_dir="$target_dir"
        # 如果是文件而非目录，用其父目录
        [ -f "$target_dir" ] && repo_dir=$(dirname "$target_dir")

        # 检查是否在 Git 仓库内
        if git -C "$repo_dir" rev-parse --git-dir &>/dev/null; then
            local fixed=0
            while IFS=$' \t' read -r mode _ _ file; do
                if [ "${mode:3:1}" != "7" ]; then
                    git -C "$repo_dir" update-index --chmod=+x "$file" 2>/dev/null || true
                    ((fixed++)) || true
                fi
            done < <(git -C "$repo_dir" ls-files -s '*.sh' 2>/dev/null)
            [ "$fixed" -gt 0 ] && log_info "  🔧 修复 Git 索引中 $fixed 个 .sh 文件权限"
        fi
    fi
}

# --- 备份管理 ---
backup_file() {
    local src="$1"
    local item_name="$2"

    if [ ! -e "$src" ]; then
        return 0
    fi

    local backup_name
    backup_name="${item_name//\//_}_$(date '+%Y%m%d_%H%M%S')"
    cp -a "$src" "$BACKUP_DIR/$backup_name" 2>/dev/null && \
        log_debug "备份: $item_name → $backup_name"

    # 清理超过 3 天的旧备份
    find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +3 -exec rm -rf {} + 2>/dev/null || true
}

# --- 同步操作 ---
# 文件复制（兼容无 rsync 环境，如原生 Windows）
sync_copy() {
    local src="$1"
    local dst="$2"
    local delete_flag="${3:-}"

    local exclude_args=()
    for pattern in "${EXCLUDE_ITEMS[@]}"; do
        exclude_args+=(--exclude="$pattern")
    done

    if command -v rsync &>/dev/null; then
        if [ "$delete_flag" = "--delete" ]; then
            rsync -a --delete "${exclude_args[@]}" "$src" "$dst" 2>/dev/null
        else
            rsync -a "${exclude_args[@]}" "$src" "$dst" 2>/dev/null
        fi
    else
        # 无 rsync 时用 cp
        local parent
        parent=$(dirname "$dst" 2>/dev/null)
        mkdir -p "$parent" 2>/dev/null || true
        cp -r "$src" "$dst" 2>/dev/null
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

    for cmd in git curl; do
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
