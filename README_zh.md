# Hermes Sync（赫姆斯同步）

> 🔄 **Hermes Agent 多终端同步工具** — 通过 GitHub 私有仓库，让多台电脑上的 Profiles、Skills、Memory 自动保持同步。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![中文文档](https://img.shields.io/badge/文档-中文-red)]()

---

## 为什么需要它？

如果你在**多台电脑**上使用 Hermes Agent（台式机 + 笔记本），你一定遇到过：

- 😤 在台式机上创建的角色，笔记本上没有
- 😤 教给 Hermes 的偏好设置，换台电脑就忘了
- 😤 手动复制配置文件，搞不清楚哪个是最新的

**Hermes Sync 解决了这一切。** 它把 **GitHub 私有仓库** 当作两台电脑之间的"中转站"：

```
台式机 ──(每30分钟自动上传)──→  GitHub 私有仓库  ←──(每30分钟自动上传)── 笔记本
   │                                                                    │
   └──(启动时自动下载)────→  GitHub 私有仓库  ←────(启动时自动下载)──┘
```

---

## 快速开始

### 1. 选择认证方式

**SSH 密钥（国内推荐）**：在国内网络环境下更稳定。
```bash
bash scripts/setup-ssh.sh
# 然后将打印的公钥添加到: https://github.com/settings/ssh/new
```

**HTTPS + Token**：通用方式，无需 SSH 配置。
打开 [github.com/settings/tokens](https://github.com/settings/tokens) → Generate new token (classic) → 勾选 **`repo`** →  Generate → 复制 Token。

### 2. 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/jmfjiang1031-collab/hermes-sync-tool/main/scripts/setup.sh | bash
```

安装向导会引导你：
- 输入 Token
- 设置数据仓库（新建或关联已有）
- 配置自动备份定时器

### 3. 完成！

之后无需任何手动操作，一切自动运行。

---

## 同步哪些内容？

| 内容 | 说明 | 是否同步？ |
|------|------|-----------|
| `profiles/` | 自定义角色（researcher、writer 等） | ✅ |
| `skills/` | 自定义技能和工作流 | ✅ |
| `memories/` | 跨会话记忆 | ✅ |
| `SOUL.md` | 默认人格描述 | ✅ |
| `config.yaml` | 主配置文件 | ❌ 平台特有 |
| `cron/` | 定时任务 | ❌ 平台特有 |
| `hooks/` | 自定义钩子脚本 | ❌ 平台特有 |

### 默认排除的内容（安全考虑）

- 🔐 **密钥/令牌：** `.env`、`auth.json`、各种 token 文件
- 📊 **运行时数据：** `state.db`、`kanban.db`（太大且频繁变化）
- 🗂️ **缓存：** `cache/`、`audio_cache/`、`image_cache/`
- 📦 **依赖包：** `node_modules/`、`venv/`
- 📝 **日志和会话：** `logs/`、`sessions/`

---

## 配置文件

编辑 `~/.hermes-sync/sync.conf`：

```ini
# 同步间隔（分钟）
SYNC_INTERVAL=30

# 冲突处理: backup(备份) | skip(跳过) | overwrite(覆盖)
CONFLICT_STRATEGY=backup

# 同步内容（只同步跨机器共享数据）
# config.yaml 和 cron 各平台不同，各管各的
SYNC_ITEMS=profiles,skills,memories,SOUL.md

# 日志级别: 0=安静 1=普通 2=详细
LOG_LEVEL=1
```

---

## 手动命令

```bash
# 立即上传本地改动
bash ~/.hermes-sync/scripts/sync-push.sh

# 立即从 GitHub 下载最新
bash ~/.hermes-sync/scripts/sync-pull.sh
```

---

## 多台电脑部署

每台新电脑只要运行同一句命令：

```bash
curl -fsSL https://raw.githubusercontent.com/jmfjiang1031-collab/hermes-sync-tool/main/scripts/setup.sh | bash
```

提示时选择 **"使用已有私有仓库"**，填入同一个仓库名即可。

---

## 环境要求

| 依赖 | 安装方式 |
|------|----------|
| Git | `sudo apt install git` |
| rsync | 通常已预装 |
| curl | 通常已预装 |
| systemd | Linux/WSL 自带 |
| Hermes Agent | 可选（仅同步配置也可用） |

---

## 架构说明

```
~/.hermes-sync/                    # 本地 git 工作副本
├── sync.conf                      # 你的配置
├── .github-token                  # Token（权限 600）
├── .git/                          # Git 仓库 → GitHub
├── backups/                       # 覆盖前的备份
├── profiles/                      # 从 ~/.hermes/ 同步而来
├── skills/
├── memories/
└── ...

~/.hermes/                         # Hermes 数据目录
├── profiles/          ←──┐
├── skills/            ←──┤        脚本自动同步
├── memories/          ←──┤
└── state.db           (不同步 — 运行时数据)
```

---

## 常见问题

| 问题 | 解决方法 |
|------|----------|
| 推送失败: `[rejected] main -> main (fetch first)` | **分支分叉** — 另一台设备在你离线时推送了变更。脚本现在会自动先拉取再推送，但如果冲突较深，需手动处理：`cd ~/.hermes-sync && git pull --no-rebase origin main`，解决冲突后重新运行同步 |
| 推送失败（国内网络） | 切换为 SSH：`bash scripts/setup-ssh.sh` |
| 推送显示成功但对方没收到 | 升级到 v1.2+（修复了管道吞退出码） |
| Token 过期 | 重新运行安装脚本或手动更新 `~/.hermes-sync/.github-token` |
| SSH 连接超时 | 可能是端口 22 被封，改用 HTTPS+Token |
| systemd 定时器没运行 | `systemctl --user status hermes-sync.timer` |
| 拉取时有冲突 | 旧文件被备份到 `~/.hermes-sync/backups/` |
| WSL 重启后 cron 不运行 | `sudo service cron start`（一次性）或运行 `setup-sudoers.sh` |
| `.usage.json` 合并冲突 | v1.2 已修复 — 该文件已移出同步列表 |

详细文档：[docs/troubleshooting.md](docs/troubleshooting.md)

---

## 参与贡献

欢迎提交 Issue 和 Pull Request！

- 🐛 报告问题：[GitHub Issues](https://github.com/jmfjiang1031-collab/hermes-sync-tool/issues)
- 💡 功能建议：同上
- 🔧 代码贡献：Fork → PR

---

## 许可证

MIT — 自由使用、修改和分发。
