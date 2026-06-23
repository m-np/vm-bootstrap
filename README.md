# vm-bootstrap

One-command development environment setup for Ubuntu Server VMs and macOS.

```bash
curl -sSL https://raw.githubusercontent.com/m-np/vm-bootstrap/main/setup.sh | bash -s robinhood
```

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
| Anaconda install | root | Shared across all envs on the machine |
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
[root] install system packages
          macOS  → Homebrew (if missing) → brew install git curl wget
          Linux  → apt-get install git curl wget build-essential
[root] install Anaconda (idempotent, picks correct installer for OS/arch)
[root] git clone RobinhoodTrader → ~/projects/RobinhoodTrader
        │
        ├─ leaf found? (.vmsetup.sh exists)
        │       ▼
        │   [leaf] create conda env robinhoodtrader
        │   [leaf] pip install -r requirements.txt
        │   [leaf] install + start PostgreSQL (brew services / systemctl)
        │   [leaf] generate Fernet key → inject into .env
        │   [leaf] warn user to fill in secrets
        │
        └─ no leaf? → root fallback (environment.yml or requirements.txt)
        │
        ▼
[root] register alias in shell profile (~/.zshrc on macOS, ~/.bashrc on Linux)
[root] print summary + activation command
```

### Why a two-layer design?

**The root stays generic.** `setup.sh` never imports project-specific knowledge. Adding a new project to the registry is one line — you don't touch the orchestration logic.

**The leaf stays self-contained.** `.vmsetup.sh` lives inside the project repo, versioned alongside the code it sets up. When the project's dependencies change, the leaf script changes in the same commit. The root doesn't need to be updated.

**Leaf scripts are also standalone.** A contributor who already has Anaconda and a cloned repo can run `.vmsetup.sh` directly without going through `setup.sh` at all. The contract between root and leaf is minimal: working directory is the repo root, `conda` is on `PATH`.

**Safe for others to use.** The root script works for any public repo without credentials. Private repos require `--ssh` and an SSH key on the machine. The root detects the failure and explains what to do — it never silently half-installs.

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
# Public repo, or private repo with an SSH key on the machine
bash setup.sh robinhood --ssh

# Public repo via HTTPS (no SSH key needed)
bash setup.sh robinhood
```

### Arguments

| Argument | Required | Description |
|---|---|---|
| `keyword` | Yes | Short name mapped to a GitHub repo (see REPO_MAP in script) |
| `--ssh` | No | Clone via SSH (`git@github.com:...`) instead of HTTPS |

---

## What it does

| Step | Action |
|---|---|
| 1 | Install system packages (brew or apt-get depending on OS) |
| 2 | Downloads and installs Anaconda to `~/anaconda3` (picks correct binary for OS/arch) |
| 3 | Clones repo to `~/projects/<RepoName>` (or `git pull` if already cloned) |
| 4 | Runs `.vmsetup.sh` in the repo if it exists, otherwise runs a default conda env setup |
| 5 | Registers a shell alias in `~/.zshrc` (macOS) or `~/.bashrc` (Linux) |
| 6 | Prints a summary with the activation command |

After setup completes, activate the environment with:

```bash
# macOS
source ~/.zshrc && robinhood

# Linux
source ~/.bashrc && robinhood
```

This sources conda, activates the named env, and `cd`s into the project directory.

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
