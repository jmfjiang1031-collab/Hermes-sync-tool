# Hermes Sync — 架构说明

## 数据流

```
机器 A (台式机/笔记本)                  机器 B (笔记本/台式机)
─────────────                           ─────────────
~/.hermes/                              ~/.hermes/
    │                                       │
    │ sync-push.sh                          │ sync-push.sh
    ▼                                       ▼
~/.hermes-sync/   ──git push──→  GitHub  ←──git push──   ~/.hermes-sync/
    ▲                               │                          ▲
    │                               │                          │
    │ sync-pull.sh                  │                          │ sync-pull.sh
    │ (启动时/手动)                  └──── git pull ───────────┘ (启动时/手动)
```

## 同步内容

| 内容 | 是否同步 | 原因 |
|------|---------|------|
| `skills/` | ✅ | 跨机器通用 |
| `profiles/` | ✅ | 跨机器通用 |
| `SOUL.md` | ✅ | 跨机器通用 |
| `memories/` | ❌ | 环境信息不同，不同步 |
| `config.yaml` | ❌ | 各平台配置不同 |
| `cron/` | ❌ | 各平台调度系统不同 |
| `.env` | ❌ | 密钥文件，gitignore 排除 |

> **设计原则：** 只同步跨机器共享的静态数据（skills、profiles、SOUL.md）。平台特定的配置文件（config.yaml）、记忆数据（memories）和调度任务（cron）各管各的，避免冲突。

## 组件说明

### sync-push.sh（推送 — 本机 → GitHub）
1. 从 `~/.hermes/` 复制同步项到 `~/.hermes-sync/`
2. 清理运行时文件（`.curator_backups`、`.usage.json`、`.hub`、`apple/` 等）
3. 清理 `profiles/profiles/` 递归嵌套
4. `git add -A` + `git commit` + `git push`

### sync-pull.sh（拉取 — GitHub → 本机）
1. `git fetch` + `git reset --hard` 从 GitHub 拉取最新
2. 清理运行时文件
3. 备份本地版本到 `~/.hermes-sync-backups/`（保留 3 天）
4. 用 `cp -r` 覆盖本地文件
5. 清理 `profiles/profiles/` 递归嵌套

### setup.sh（安装）
1. 检测操作系统和依赖（git、curl）
2. 交互式引导配置 Token 和仓库
3. 创建 `.gitignore`（白名单模式）
4. 生成 `sync.conf` 配置文件
5. 设置 systemd 定时器或 crontab

## 认证方式

| 方式 | 说明 | 适用场景 |
|------|------|---------|
| SSH（推荐） | 通过 SSH 密钥认证 | 国内网络环境更稳定 |
| HTTPS | HTTPS + Token 方式 | 通用，无需 SSH 配置 |

配置 SSH：
```bash
bash scripts/setup-ssh.sh
# 将输出的公钥添加到: https://github.com/settings/ssh/new
```

## 备份机制

- 备份位置：`~/.hermes-sync-backups/`（仓库外，不占用 Git 空间）
- 保留策略：自动清理 3 天前的旧备份
- 备份时机：拉取同步覆盖本地文件前自动备份

## profiles/profiles 递归嵌套防护

已知 bug：`profiles/profiles/` 递归嵌套会导致同步异常。两处防护：
1. `.gitignore` 中排除 `profiles/profiles/`
2. `sync-push.sh` 和 `sync-pull.sh` 中主动删除该目录

## .gitignore 白名单模式

同步仓库使用白名单模式的 `.gitignore`：
- 默认忽略所有文件（`*`）
- 仅取消忽略需要同步的内容（`!skills/`、`!profiles/`、`!SOUL.md`）
- 排除运行时文件、缓存和敏感文件

## 安全设计

| 层级 | 措施 |
|------|------|
| 传输层 | SSH 加密 或 HTTPS 加密 |
| 存储层 | GitHub 私有仓库 |
| 文件层 | `.gitignore` 白名单模式，排除密钥、令牌、运行时数据 |
| 本地层 | 备份存仓库外，保留 3 天自动清理 |
