# Adding `.vmsetup.sh` to Your Repo

When `setup.sh` clones your repo, it looks for a `.vmsetup.sh` file in the repo root. If found, it delegates all environment setup to that script. This lets each repo control its own install logic — including cross-platform differences.

---

## When do you need it?

The default fallback (conda + `environment.yml` / `requirements.txt`) covers most cases. Add `.vmsetup.sh` when you need any of the following:

- Extra system packages (`apt-get` on Linux, `brew` on macOS)
- Creating or copying `.env` / config files
- A database (PostgreSQL, etc.)
- Non-conda dependencies (Node, Docker, system-level tools)
- Post-install validation or data downloads
- Multiple conda envs or custom env names

---

## Minimal template

Copy this into your repo at `.vmsetup.sh`:

```bash
#!/usr/bin/env bash
set -e

ENV_NAME="myproject"        # change to match your keyword / desired env name
PYTHON_VERSION="3.11"

echo "[vmsetup] Setting up conda environment: $ENV_NAME"

source "$HOME/anaconda3/etc/profile.d/conda.sh"

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

## Full-featured template (cross-platform)

```bash
#!/usr/bin/env bash
set -e

ENV_NAME="myproject"
PYTHON_VERSION="3.11"
OS="$(uname -s)"

# ── System packages ──────────────────────────────────────────────────────────
echo "[vmsetup] Installing system packages..."
if [ "$OS" = "Darwin" ]; then
    brew install libpq          # macOS equivalent — add what your project needs
else
    sudo apt-get install -y libpq-dev ffmpeg
fi

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
if [ ! -f ".env" ]; then
    echo "[vmsetup] Creating .env from .env.example..."
    cp .env.example .env
    echo "[vmsetup] ⚠  Fill in secrets in .env before running the app."
fi

# ── sed -i is not portable: macOS requires an explicit backup extension ──────
inject_env() {
    local pattern="$1" replacement="$2" file="$3"
    if [ "$OS" = "Darwin" ]; then
        sed -i '' "s|${pattern}|${replacement}|" "$file"
    else
        sed -i "s|${pattern}|${replacement}|" "$file"
    fi
}

# Example: inject a generated key
# MY_KEY="$(conda run -n "$ENV_NAME" python -c "import secrets; print(secrets.token_hex(32))")"
# inject_env "^MY_KEY=.*" "MY_KEY=${MY_KEY}" .env

# ── Post-install steps ───────────────────────────────────────────────────────
echo "[vmsetup] Running post-install checks..."
conda run -n "$ENV_NAME" python -c "import torch; print('torch:', torch.__version__)"

echo "[vmsetup] Done."
```

---

## PostgreSQL snippet (cross-platform)

If your project needs a local database, use this pattern:

```bash
OS="$(uname -s)"

if command -v psql &>/dev/null; then
    echo "PostgreSQL already installed — skipping."
else
    if [ "$OS" = "Darwin" ]; then
        brew install postgresql@14
        brew services start postgresql@14
        export PATH="$(brew --prefix postgresql@14)/bin:$PATH"
    else
        sudo apt-get install -y postgresql postgresql-contrib
        sudo systemctl start postgresql
        sudo systemctl enable postgresql
    fi
fi

# Create the database
if [ "$OS" = "Darwin" ]; then
    # Homebrew postgres creates a role matching $USER — createdb works directly
    createdb myproject 2>/dev/null || echo "Database already exists — skipping."
else
    # On Linux, $USER may not have a PostgreSQL role yet
    if ! createdb myproject 2>/dev/null; then
        sudo -u postgres createuser --superuser "$USER" 2>/dev/null || true
        createdb myproject || true
    fi
fi
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
- `conda` is available (`source ~/anaconda3/etc/profile.d/conda.sh` already ran in the root)
- `git`, `curl`, `wget` are installed
- On Linux: `build-essential` is installed
- On macOS: Homebrew is installed and on `PATH`

Your script is **not** responsible for:

- Cloning the repo (already done by root)
- Registering the shell alias (handled by root)
- Printing the final summary (handled by root)

---

## Portability rules for leaf scripts

| Pattern | Linux | macOS | Portable alternative |
|---|---|---|---|
| `sed -i "s/a/b/" f` | ✅ | ❌ | `sed -i '' "s/a/b/" f` on macOS; use an `if [ OS = Darwin ]` branch |
| `apt-get install x` | ✅ | ❌ | `brew install x` on macOS; use an OS branch |
| `systemctl start x` | ✅ | ❌ | `brew services start x` on macOS |
| `declare -A map` | bash 4+ only | ❌ bash 3.2 | Use `case` statements instead |
| `[[ ]]` | ✅ bash | ✅ bash | Safe if shebang is `#!/usr/bin/env bash` |
| `sudo -u postgres` | ✅ | ❌ (homebrew postgres) | OS branch; macOS uses `$USER` role directly |

---

## Checklist before committing `.vmsetup.sh`

- [ ] `chmod +x .vmsetup.sh`
- [ ] Shebang is `#!/usr/bin/env bash` (not `/bin/sh`)
- [ ] Script is idempotent — safe to run twice (check for existing env/files before creating)
- [ ] `set -e` at the top so failures don't silently continue
- [ ] `sed -i` uses the OS-aware pattern (or the `inject_env` helper above)
- [ ] System package installs have both a `brew` and an `apt-get` branch
- [ ] `.env` or secrets are never committed — only `.env.example`
- [ ] Tested on a clean machine or at minimum a fresh shell
