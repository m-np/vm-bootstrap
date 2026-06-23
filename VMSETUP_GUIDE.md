# Adding `.vmsetup.sh` to Your Repo

When `setup.sh` clones your repo, it looks for a `.vmsetup.sh` file in the repo root. If found, it delegates all environment setup to that script. This lets each repo control its own install logic.

---

## When do you need it?

The default fallback (conda + `environment.yml` / `requirements.txt`) covers most cases. Add `.vmsetup.sh` when you need any of the following:

- Extra system packages (`apt-get install ...`)
- Creating or copying `.env` / config files
- Non-conda dependencies (Node, Docker, system-level tools)
- Post-install validation or data downloads
- Multiple conda envs or custom env names

---

## Minimal template

Copy this into your repo at `.vmsetup.sh`:

```bash
#!/usr/bin/env bash
set -e

ENV_NAME="robinhood"        # change to match your keyword / desired env name
PYTHON_VERSION="3.10"

echo "[vmsetup] Creating conda environment: $ENV_NAME"

if conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
    echo "[vmsetup] Env '$ENV_NAME' already exists — skipping."
else
    conda env create -n "$ENV_NAME" -f environment.yml
fi

echo "[vmsetup] Done."
```

Make it executable before committing:

```bash
chmod +x .vmsetup.sh
git add .vmsetup.sh
git commit -m "add .vmsetup.sh for VM bootstrap"
```

---

## Full-featured template

```bash
#!/usr/bin/env bash
set -e

ENV_NAME="myproject"
PYTHON_VERSION="3.11"

# ── System packages ──────────────────────────────────────────────────────────
echo "[vmsetup] Installing system packages..."
sudo apt-get install -y libpq-dev ffmpeg   # add what your project needs

# ── Conda env ────────────────────────────────────────────────────────────────
echo "[vmsetup] Setting up conda environment: $ENV_NAME"

source "$HOME/anaconda3/etc/profile.d/conda.sh"

if conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
    echo "[vmsetup] Env '$ENV_NAME' already exists — updating."
    conda env update -n "$ENV_NAME" -f environment.yml --prune
else
    conda env create -n "$ENV_NAME" -f environment.yml
fi

# ── .env file ────────────────────────────────────────────────────────────────
if [[ ! -f ".env" ]]; then
    echo "[vmsetup] Creating .env from .env.example..."
    cp .env.example .env
    echo "[vmsetup] ⚠  Fill in secrets in .env before running the app."
fi

# ── Post-install steps ───────────────────────────────────────────────────────
echo "[vmsetup] Running post-install checks..."
conda run -n "$ENV_NAME" python -c "import torch; print('torch:', torch.__version__)"

echo "[vmsetup] Done."
```

---

## Contract with `setup.sh`

`setup.sh` calls your script like this:

```bash
cd ~/projects/<RepoName>
bash .vmsetup.sh
```

Your script can rely on:

- Working directory is the repo root
- `~/anaconda3` is installed and on `PATH`
- `conda` command is available (`source ~/anaconda3/etc/profile.d/conda.sh` already ran)
- `git`, `curl`, `wget`, `build-essential` are installed

Your script is **not** responsible for:

- Cloning the repo (already done)
- Registering the shell alias (handled by `setup.sh`)
- Printing the final summary (handled by `setup.sh`)

---

## Checklist before committing `.vmsetup.sh`

- [ ] `chmod +x .vmsetup.sh`
- [ ] Script is idempotent — safe to run twice (check for existing env/files before creating)
- [ ] `set -e` at the top so failures don't silently continue
- [ ] `.env` or secrets are never committed — only `.env.example`
- [ ] Tested on a clean VM or at minimum a fresh shell
