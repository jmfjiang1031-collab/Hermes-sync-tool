# Hermes Sync

> 🔄 **Multi-machine sync for Hermes Agent** — Sync Skills, Profiles, and SOUL.md across all your computers via GitHub.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Why Hermes Sync?

If you use **Hermes Agent** on multiple computers (desktop + laptop), you've probably experienced:

- Creating a Skill on one machine, not available on the other
- Teaching Hermes preferences on desktop, forgotten on laptop
- Manually copying config files between machines

**Hermes Sync solves this.** It uses a **private GitHub repository** as a bridge between your machines:

```
Desktop ──(push)──→  GitHub Repo  ←──(push)── Laptop
   │                                       │
   └──(pull)────→  GitHub Repo  ←──(pull)──┘
```

---

## What Gets Synced?

| Item | Description | Sync? |
|------|-------------|-------|
| `skills/` | Custom skills and workflows | ✅ |
| `profiles/` | Custom Agent personas | ✅ |
| `SOUL.md` | Default personality | ✅ |
| `memories/` | Cross-session memory | ❌ Environment-specific |
| `config.yaml` | Main Hermes configuration | ❌ Platform-specific |
| `cron/` | Scheduled cron jobs | ❌ Platform-specific |
| `.env` | Secrets | ❌ Never synced |

---

## Quick Start

### 1. Create a Private Repository

Create a **private** repo on GitHub (e.g. `hermes-sync`)

### 2. Configure SSH

```bash
bash scripts/setup-ssh.sh
# Then add the printed public key to: https://github.com/settings/ssh/new
```

### 3. Install

```bash
curl -fsSL https://raw.githubusercontent.com/jmfjiang1031-collab/Hermes-sync-tool/main/scripts/setup.sh | bash
```

### 4. Done!

In Hermes, say:
- **"推送同步"** — Push local → GitHub
- **"拉取同步"** — Pull GitHub → local

Or run manually:
```bash
bash ~/.hermes-sync/sync-push.sh   # Push
bash ~/.hermes-sync/sync-pull.sh   # Pull
```

---

## Conflict Handling

- Bidirectional sync with **last-write-wins** strategy
- Auto-backup before pull to `~/.hermes-sync-backups/` (retained 3 days)
- `profiles/profiles/` recursive nesting auto-cleaned

---

## Architecture

```
~/.hermes-sync/                    # Local git working copy
├── .gitignore                     # Whitelist mode
├── sync-push.sh                   # Push script
├── sync-pull.sh                   # Pull script
├── .git/                          # Git repo → GitHub
├── skills/                        # Synced from ~/.hermes/
├── profiles/
└── SOUL.md

~/.hermes-sync-backups/            # Backups (outside repo, 3-day retention)
```

See [docs/architecture.md](docs/architecture.md) for details.

---

## Requirements

| Dependency | Install |
|------------|---------|
| Git | `sudo apt install git` |
| curl | Usually pre-installed |
| SSH key | `bash scripts/setup-ssh.sh` |

---

## License

MIT — free to use, modify, and distribute.
