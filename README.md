# vm-bootstrap

One-command development environment setup for Ubuntu Server VMs.

## Usage

```bash
bash setup.sh <keyword> [--ssh]
```

### Examples

```bash
# Public repo or private repo with SSH key on the VM
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
| 1 | `apt-get install git curl wget build-essential` |
| 2 | Downloads and installs Anaconda to `~/anaconda3` (skips if already present) |
| 3 | Clones repo to `~/projects/<RepoName>` (or `git pull` if already cloned) |
| 4 | Runs `.vmsetup.sh` in the repo if it exists, otherwise runs a default conda env setup |
| 5 | Registers a shell alias in `~/.bashrc` |
| 6 | Prints a summary with the activation command |

After setup completes, activate the environment with:

```bash
source ~/.bashrc && robinhood
```

This sources conda, activates the named env, and `cd`s into the project directory.

---

## Private repos

By default the script clones via HTTPS, which works for public repos without any credentials.

For **private repos**, you need an SSH key on the VM added to your GitHub account:

```bash
# 1. Generate a key on the VM (skip if you already have one)
ssh-keygen -t ed25519 -C "your@email.com"

# 2. Print the public key and add it to GitHub → Settings → SSH Keys
cat ~/.ssh/id_ed25519.pub

# 3. Run setup with --ssh
bash setup.sh robinhood --ssh
```

If you run without `--ssh` and the clone fails, the script will print this message and exit cleanly — it will not proceed with a broken state.

---

## Adding a new repo

Open `setup.sh` and add a line to `REPO_MAP`:

```bash
declare -A REPO_MAP
REPO_MAP["robinhood"]="https://github.com/m-np/RobinhoodTrader"
REPO_MAP["myproject"]="https://github.com/m-np/MyProject"   # ← add here
```

The keyword becomes the conda env name and the shell alias.

---

## Default environment setup (no `.vmsetup.sh`)

If the cloned repo does not contain a `.vmsetup.sh`, the script falls back to:

| Repo contains | Action |
|---|---|
| `environment.yml` | `conda env create -n <keyword> -f environment.yml` |
| `requirements.txt` | `conda create -n <keyword> python=3.10 -y` + `pip install -r requirements.txt` |
| Neither | `conda create -n <keyword> python=3.10 -y` (bare env) |

For custom setup logic (system deps, `.env` files, post-install steps), add a `.vmsetup.sh` to your repo. See [VMSETUP_GUIDE.md](VMSETUP_GUIDE.md).
