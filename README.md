# Hermes Sync

> 🔄 **Multi-machine sync for Hermes Agent** — Keep your Profiles, Skills, and Memory in sync across all your computers via GitHub.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![ShellCheck](https://img.shields.io/badge/shell-checked-brightgreen)]()

---

## Why Hermes Sync?

If you use **Hermes Agent** on multiple computers (desktop + laptop), you've probably experienced:

- Creating a Profile on one machine, not available on the other
- Teaching Hermes preferences on desktop, forgotten on laptop
- Manually copying config files between machines

**Hermes Sync solves this.** It uses a **private GitHub repository** as a bridge between your machines:

```
Desktop ──(auto push every 30min)──→  GitHub Repo  ←──(auto push every 30min)── Laptop
    │                                                                          │
    └──(auto pull on startup)────→  GitHub Repo  ←────(auto pull on startup)──┘
```

---

## Quick Start

### 1. Create a GitHub Token

Visit [github.com/settings/tokens](https://github.com/settings/tokens) → Generate new token (classic) → Check **`repo`** → Generate.

### 2. Install

```bash
curl -fsSL https://raw.githubusercontent.com/jmfjiang1031-collab/hermes-sync-tool/main/scripts/setup.sh | bash
```

The installer will guide you through:
- Token configuration
- Repository setup (create new or link existing)
- Auto-backup timer (systemd)

### 3. Done!

Your Hermes data syncs automatically. No manual steps needed.

---

## What Gets Synced?

| Item | Description |
|------|-------------|
| `profiles/` | Custom Agent profiles (researcher, writer, etc.) |
| `skills/` | Custom skills and workflows |
| `memories/` | Cross-session memory |
| `cron/` | Scheduled cron jobs |
| `config.yaml` | Main Hermes configuration |
| `SOUL.md` | Default personality |
| `hooks/` | Custom hooks |

### What's Excluded (by default)?

- **Secrets:** `.env`, `auth.json`, tokens
- **Runtime state:** `state.db`, `kanban.db`, `response_store.db`
- **Caches:** `cache/`, `audio_cache/`, `image_cache/`
- **Dependencies:** `node_modules/`, `venv/`
- **Logs & sessions:** `logs/`, `sessions/`

---

## Configuration

Edit `~/.hermes-sync/sync.conf`:

```ini
SYNC_INTERVAL=30              # Backup every 30 minutes
CONFLICT_STRATEGY=backup      # backup | skip | overwrite
SYNC_ITEMS=profiles,skills    # Customize what to sync
LOG_LEVEL=1                   # 0=quiet 1=normal 2=verbose
```

---

## Manual Commands

```bash
# Push local changes to GitHub
bash ~/.hermes-sync/scripts/sync-push.sh

# Pull latest from GitHub
bash ~/.hermes-sync/scripts/sync-pull.sh
```

---

## Multi-Machine Setup

On each additional machine, run the same install command:

```bash
curl -fsSL https://raw.githubusercontent.com/jmfjiang1031-collab/hermes-sync-tool/main/scripts/setup.sh | bash
```

When prompted, choose **"Use existing private repo"** and enter the same GitHub repo name.

---

## Requirements

- **Git** (`sudo apt install git`)
- **rsync** (pre-installed on most Linux/macOS)
- **curl** (pre-installed)
- **systemd** (Linux/WSL) or cron (macOS)
- **Hermes Agent** (optional — can sync config only)

---

## Architecture

```
~/.hermes-sync/                    # Local git working copy
├── sync.conf                      # Your configuration
├── .github-token                  # GitHub token (600 perms)
├── .git/                          # Git repo → GitHub
├── backups/                       # Pre-overwrite backups
├── profiles/                      # Synced from ~/.hermes/
├── skills/
├── memories/
└── ...

~/.hermes/                         # Hermes Agent data dir
├── profiles/          ←──┐
├── skills/            ←──┤        Auto-synced by scripts
├── memories/          ←──┤
├── config.yaml        ←──┘
└── state.db           (not synced — runtime only)
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Push fails | Check network and Token validity |
| Token expired | Re-run `setup.sh` or update `~/.hermes-sync/.github-token` |
| systemd timer not running | `systemctl --user status hermes-sync.timer` |
| Conflicts on pull | Check `~/.hermes-sync/backups/` for saved versions |

Full guide: [docs/troubleshooting.md](docs/troubleshooting.md)

---

## License

MIT — free to use, modify, and distribute.
