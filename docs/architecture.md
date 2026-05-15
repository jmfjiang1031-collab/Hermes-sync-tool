# Hermes Sync — 架构说明

## 数据流

```
机器 A (台式机)                          机器 B (笔记本)
─────────────                           ─────────────
~/.hermes/                              ~/.hermes/
    │                                       │
    │ sync-push.sh (每30分钟)                │ sync-push.sh (每30分钟)
    ▼                                       ▼
~/.hermes-sync/   ──git push──→  GitHub  ←──git push──   ~/.hermes-sync/
    ▲                               │                          ▲
    │                               │                          │
    │ sync-pull.sh                  │                          │ sync-pull.sh
    │ (Gateway启动时)                └──── git pull ───────────┘ (Gateway启动时)
```

## 组件说明

### sync-push.sh（上传）
1. 读取 `sync.conf` 配置
2. 使用 `rsync` 将 `~/.hermes/` 中的同步项复制到 `~/.hermes-sync/`
3. 自动排除 `node_modules/`、`venv/`、缓存、密钥等
4. `git add` + `git commit` + `git push`

### sync-pull.sh（下载）
1. 读取 `sync.conf` 配置
2. `git pull` 从 GitHub 拉取最新
3. 比较文件时间戳，仅更新变更的文件
4. 根据 `CONFLICT_STRATEGY` 处理冲突
5. 覆盖前自动备份到 `backups/`

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
- 备份管理（自动清理30天前的备份）

## 安全设计

| 层级 | 措施 |
|------|------|
| 传输层 | HTTPS 加密 |
| 存储层 | GitHub 私有仓库 |
| 认证层 | Personal Access Token（最小权限：仅 repo） |
| 文件层 | `.gitignore` 排除密钥、令牌、运行时数据 |
| 本地层 | Token 文件权限 600，备份机制防覆盖 |
