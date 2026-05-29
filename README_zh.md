# Hermes Sync

> 🔄 **Hermes Agent 多终端同步** — 通过 GitHub 在多台电脑间同步 Skills、Profiles 和 SOUL.md

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## 适用场景

- 家里用台式机，上班用笔记本
- 在一台机器上安装了新技能，另一台也需要
- 希望两台机器的 Hermes 保持一致的技能和定位

## 同步内容

| 内容 | 同步 | 说明 |
|------|------|------|
| `skills/` | ✅ | 技能文件 |
| `profiles/` | ✅ | 自定义 persona |
| `SOUL.md` | ✅ | 人格定义 |
| `memories/` | ❌ | 环境信息不同，不同步 |
| `config.yaml` | ❌ | 配置各机器独立 |
| `.env` | ❌ | 密钥不同步 |
| `cron/` | ❌ | 定时任务各机器独立 |

## 快速开始

### 1. 创建私有仓库

在 GitHub 创建一个**私有**仓库（如 `hermes-sync`）

### 2. 配置 SSH

```bash
bash scripts/setup-ssh.sh
# 将输出的公钥添加到: https://github.com/settings/ssh/new
```

### 3. 安装

```bash
curl -fsSL https://raw.githubusercontent.com/jmfjiang1031-collab/Hermes-sync-tool/main/scripts/setup.sh | bash
```

### 4. 使用

在 Hermes 对话中说：
- **"推送同步"** — 本机 → GitHub
- **"拉取同步"** — GitHub → 本机

或手动执行：
```bash
bash ~/.hermes-sync/sync-push.sh   # 推送
bash ~/.hermes-sync/sync-pull.sh   # 拉取
```

## 冲突处理

- 双向同步，以**后同步的为准**（last-write-wins）
- 拉取前自动备份到 `~/.hermes-sync-backups/`（保留 3 天）
- `profiles/profiles/` 递归嵌套自动清理
