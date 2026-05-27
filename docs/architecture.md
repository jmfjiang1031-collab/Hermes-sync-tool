# Hermes Sync — 架构说明

## 数据流

```
机器 A (台式机/笔记本)                  机器 B (笔记本/台式机)
─────────────                           ─────────────
~/.hermes/                              ~/.hermes/
    │                                       │
    │ sync-push.sh (每30分钟)                │ sync-push.sh (每30分钟)
    ▼                                       ▼
~/.hermes-sync/   ──git push──→  GitHub  ←──git push──   ~/.hermes-sync/
    ▲                               │                          ▲
    │                               │                          │
    │ sync-pull.sh                  │                          │ sync-pull.sh
    │ (启动时/定时)                  └──── git pull ───────────┘ (启动时/定时)
```

## 同步内容

| 内容 | 是否同步 | 原因 |
|------|---------|------|
| `profiles/` | ✅ | 跨机器通用 |
| `skills/` | ✅ | 跨机器通用 |
| `memories/` | ✅ | 跨机器通用 |
| `SOUL.md` | ✅ | 跨机器通用 |
| `config.yaml` | ❌ | 各平台配置不同 |
| `cron/` | ❌ | 各平台调度系统不同 |
| `.env` | ❌ | 密钥文件，gitignore 排除 |

> **设计原则：** 只同步跨机器共享的静态数据。平台特定的配置文件（config.yaml）和调度任务（cron）各管各的，避免冲突。

## 组件说明

### sync-push.sh（上传）
1. 读取 `sync.conf` 配置
2. 将 `~/.hermes/` 中的同步项复制到 `~/.hermes-sync/`
3. 兼容无 rsync 环境（Windows 原生用 cp），有 rsync 时优先使用
4. 自动排除 `.curator_backups`、缓存等本地文件
5. `git add` + `git commit` + `git push`
6. 推送失败时自动回退代理（`http://127.0.0.1:7897`），用于国内网络环境

### sync-pull.sh（下载）
1. 读取 `sync.conf` 配置
2. `git fetch` + `git reset --hard` 从 GitHub 拉取最新
3. 覆盖前自动备份到 `~/.hermes-sync-backups/`（仓库外，避免占用 Git 空间）
4. 拉取失败时自动回退代理

### setup.sh（安装）
1. 检测操作系统和依赖
2. 交互式引导配置 Token 和仓库
3. 生成 `sync.conf` 配置文件
4. 设置 systemd 定时器或 crontab
5. 修改 Hermes Gateway 服务（添加启动前自动拉取）

### common.sh（函数库）
- 统一的日志系统
- Token 管理（环境变量 > 配置文件 > Token文件）
- 配置解析
- 备份管理（备份存仓库外 `~/.hermes-sync-backups/`，自动清理3天前的备份）
- 认证 Git 操作（SSH 和 HTTPS+Token 两套）
- 代理回退逻辑（直连失败自动用代理）

## Windows 原生支持

v2.0 起 Hermes Sync 原生支持 Windows（不依赖 WSL）：

- **无 rsync 兼容**：使用 `cp -r` 替代 `rsync`，Windows 开箱即用
- **无需 WSL**：直接在 PowerShell、cmd 或 git-bash 中运行
- **Hermes Cron**：Windows 平台使用 Hermes 内置 cron 调度，无需 systemd 或 Windows 任务计划程序

## 安全设计

| 层级 | 措施 |
|------|------|
| 传输层 | HTTPS 加密 |
| 存储层 | GitHub 私有仓库 |
| 认证层 | Personal Access Token（最小权限：仅 repo） |
| 文件层 | `.gitignore` 排除密钥、令牌、运行时数据 |
| 本地层 | Token 文件权限 600，备份机制防覆盖（仓库外保留3天） |
