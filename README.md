# vm-bootstrap

One-command development environment setup for Ubuntu Server VMs and macOS.

```bash
curl -sSL https://raw.githubusercontent.com/m-np/vm-bootstrap/main/setup.sh | bash -s robinhood
```

The script is **fully idempotent** — safe to re-run at any time. Each stage checks whether the desired state is already met before doing anything.

---

## How it works — root and leaf

This repo is the **root node** of a two-layer bootstrap system. Every other project repo is a **leaf node**.

```
vm-bootstrap/          ← root node (this repo)
  setup.sh             ← orchestrator: knows about all projects, handles shared infra
  REPO_MAP             ← registry: keyword → GitHub URL

RobinhoodTrader/       ← leaf node (any project repo)
  .vmsetup.sh          ← leaf script: knows only about itself
```

The split exists because responsibilities differ:

| Concern | Handled by | Why here |
|---|---|---|
| System packages (`git`, `curl`, `build-essential`) | root | Same on every machine, regardless of project |
| Homebrew install (macOS) | root | Shared prerequisite, not project-specific |
| Conda install | root | Shared across all envs on the machine |
| Cloning / pulling the repo | root | Needs the registry to know where to clone from |
| SSH vs HTTPS decision | root | Machine-level credential concern, not project-specific |
| Shell alias registration | root | Knows the keyword and repo name |
| Conda env creation | leaf | Project knows its own Python version and dependencies |
| System libs the project needs (`libpq-dev`, etc.) | leaf | Project-specific |
| `.env` scaffolding and secret injection | leaf | Project knows its own config schema |
| Post-install validation | leaf | Project knows what "working" looks like |

### Execution flow

```
curl setup.sh | bash -s robinhood
        │
        ▼
[root] detect OS (macOS or Linux) and CPU arch
[root] sudo -v upfront (Linux only) — prompts once, keeps timestamp alive
        │
        ▼
[1/6] System packages
        already installed? → skip
        macOS  → Homebrew (if missing) → brew install git curl wget
        Linux  → apt-get install git curl wget build-essential
        │
        ▼
[2/6] Conda
        already on PATH?          → use it, skip install
        found at common location? → use it, skip install
        not found anywhere?       → install Anaconda (picks correct binary for OS/arch)
        │
        ▼
[3/6] Clone / pull repo
        ~/projects/RobinhoodTrader exists? → git pull
        otherwise                          → git clone (HTTPS or SSH)
        │
        ├─ .vmsetup.sh found in repo?
        │       ▼
        │   [leaf] create conda env (skips if already exists)
        │   [leaf] pip install -r requirements.txt
        │   [leaf] install + start PostgreSQL (brew services / systemctl)
        │   [leaf] generate Fernet key → inject into .env
        │   [leaf] warn user to fill in secrets
        │
        └─ no leaf? → root fallback (environment.yml → requirements.txt → bare env)
        │
        ▼
[5/6] Shell alias
        alias already in shell profile? → skip
        otherwise                       → append to ~/.zshrc (macOS) or ~/.bashrc (Linux)
        │
        ▼
[6/6] Print summary + activation command
```

### Idempotency — what each stage checks

| Stage | "Already done" condition | Behaviour |
|---|---|---|
| Homebrew | `command -v brew` succeeds | Skip install |
| System packages | `command -v git/curl/wget` all succeed | Skip apt-get / brew |
| Conda | Found on PATH **or** at any of 6 common install locations | Skip install, use existing |
| Conda shell init | Init line already in shell profile | Skip append |
| Repo clone | `~/projects/<RepoName>/.git` exists | `git pull` instead |
| Conda env (fallback) | Env name appears in `conda env list` | Skip creation |
| Shell alias | Alias line already in shell profile | Skip append |

The leaf script (`.vmsetup.sh`) is responsible for its own idempotency — see [VMSETUP_GUIDE.md](VMSETUP_GUIDE.md).

---

## Platform support

| | macOS (Intel) | macOS (Apple Silicon) | Ubuntu / Debian Linux |
|---|---|---|---|
| Package manager | Homebrew | Homebrew | apt-get |
| Anaconda installer | MacOSX-x86_64 | MacOSX-arm64 | Linux-x86_64 |
| PostgreSQL (leaf) | `brew services` | `brew services` | `systemctl` |
| Shell profile | `~/.zshrc` | `~/.zshrc` | `~/.bashrc` |

---

## Usage

```bash
bash setup.sh <keyword> [--ssh]
```

### Examples

```bash
# Public repo via HTTPS (no SSH key needed)
bash setup.sh robinhood

# Private repo — requires an SSH key on this machine added to GitHub
bash setup.sh robinhood --ssh
```

### Arguments

| Argument | Required | Description |
|---|---|---|
| `keyword` | Yes | Short name mapped to a GitHub repo (see REPO_MAP in script) |
| `--ssh` | No | Clone via SSH (`git@github.com:...`) instead of HTTPS |

---

## Sudo and the curl pipe

When piped through `curl | bash`, sudo prompts can appear with no visible terminal, causing the script to hang silently. The script handles this automatically on Linux by calling `sudo -v` upfront (before any work begins) and keeping the sudo timestamp alive with a background heartbeat.

If you still have issues, download first and run directly — this guarantees the sudo prompt appears in your terminal:

```bash
curl -sSL https://raw.githubusercontent.com/m-np/vm-bootstrap/main/setup.sh -o setup.sh
bash setup.sh robinhood
```

Or prime sudo manually before the pipe:

```bash
sudo -v && curl -sSL https://raw.githubusercontent.com/m-np/vm-bootstrap/main/setup.sh | bash -s robinhood
```

---

## Private repos

By default the script clones via HTTPS, which works for public repos without any credentials.

For **private repos**, you need an SSH key on the machine added to your GitHub account:

```bash
# 1. Generate a key (skip if you already have one)
ssh-keygen -t ed25519 -C "your@email.com"

# 2. Print the public key and add it to GitHub → Settings → SSH Keys
cat ~/.ssh/id_ed25519.pub

# 3. Run setup with --ssh
bash setup.sh robinhood --ssh
```

If you run without `--ssh` and the clone fails, the script prints a clear explanation and exits without leaving a broken state.

---

## Adding a new project

**Step 1** — add a line to `REPO_MAP` in `setup.sh`:

```bash
repo_url() {
    case "$1" in
        robinhood) echo "https://github.com/m-np/RobinhoodTrader" ;;
        myproject) echo "https://github.com/m-np/MyProject" ;;   # ← add here
        *)         echo "" ;;
    esac
}

repo_keywords() {
    echo "  robinhood  →  https://github.com/m-np/RobinhoodTrader"
    echo "  myproject  →  https://github.com/m-np/MyProject"      # ← add here
}
```

The keyword becomes the conda env name and the shell alias.

**Step 2** — add a `.vmsetup.sh` to the project repo (optional but recommended).

See [VMSETUP_GUIDE.md](VMSETUP_GUIDE.md) for a template and the full contract between root and leaf.

---

## Default environment setup (no `.vmsetup.sh`)

If the cloned repo does not contain a `.vmsetup.sh`, the root falls back to:

| Repo contains | Action |
|---|---|
| `environment.yml` | `conda env create -n <keyword> -f environment.yml` |
| `requirements.txt` | `conda create -n <keyword> python=3.10 -y` + `pip install -r requirements.txt` |
| Neither | `conda create -n <keyword> python=3.10 -y` (bare env) |

The fallback is intentionally minimal. If a project needs system packages, `.env` files, or a database, it should provide a `.vmsetup.sh`.

---

## Current project registry

| Keyword | Repo | Leaf script |
|---|---|---|
| `robinhood` | [m-np/RobinhoodTrader](https://github.com/m-np/RobinhoodTrader) | `.vmsetup.sh` — conda env, PostgreSQL, Fernet key, `.env` scaffold |
