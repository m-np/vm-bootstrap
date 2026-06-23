#!/usr/bin/env bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
# REPO MAP — add entries here: [keyword]="https://github.com/owner/repo"
# ─────────────────────────────────────────────────────────────────────────────
declare -A REPO_MAP
REPO_MAP["robinhood"]="https://github.com/m-np/RobinhoodTrader"
# REPO_MAP["myproject"]="https://github.com/m-np/MyProject"

# ─────────────────────────────────────────────────────────────────────────────
# Argument parsing
# ─────────────────────────────────────────────────────────────────────────────
USE_SSH=false
KEYWORD=""

for arg in "$@"; do
    case "$arg" in
        --ssh) USE_SSH=true ;;
        -*) echo "Unknown flag: $arg"; exit 1 ;;
        *) KEYWORD="$arg" ;;
    esac
done

if [[ -z "$KEYWORD" ]]; then
    echo "Usage: bash setup.sh <keyword> [--ssh]"
    echo ""
    echo "Available keywords:"
    for k in "${!REPO_MAP[@]}"; do
        echo "  $k  →  ${REPO_MAP[$k]}"
    done
    exit 1
fi

if [[ -z "${REPO_MAP[$KEYWORD]+_}" ]]; then
    echo "Error: unknown keyword '$KEYWORD'"
    echo ""
    echo "Available keywords:"
    for k in "${!REPO_MAP[@]}"; do
        echo "  $k  →  ${REPO_MAP[$k]}"
    done
    exit 1
fi

HTTPS_URL="${REPO_MAP[$KEYWORD]}"
# Derive SSH URL from HTTPS URL: https://github.com/owner/repo → git@github.com:owner/repo.git
SSH_URL="git@github.com:$(echo "$HTTPS_URL" | sed 's|https://github.com/||').git"
REPO_NAME="$(basename "$HTTPS_URL")"
PROJECTS_DIR="$HOME/projects"
REPO_DIR="$PROJECTS_DIR/$REPO_NAME"
ANACONDA_DIR="$HOME/anaconda3"

echo "═════════════════════════════════════════════════════════════════════════════"
echo " VM Bootstrap: $KEYWORD → $REPO_NAME"
echo "═════════════════════════════════════════════════════════════════════════════"

# ─────────────────────────────────────────────────────────────────────────────
# [1/6] System packages
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[1/6] Installing system packages ────────────────────────────────────────────"
sudo apt-get update -qq
sudo apt-get install -y git curl wget build-essential

# ─────────────────────────────────────────────────────────────────────────────
# [2/6] Anaconda
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[2/6] Setting up Anaconda ───────────────────────────────────────────────────"

if [[ -d "$ANACONDA_DIR" ]]; then
    echo "  Anaconda already installed at $ANACONDA_DIR — skipping download."
else
    ANACONDA_INSTALLER="$HOME/anaconda_installer.sh"
    ANACONDA_URL="https://repo.anaconda.com/archive/Anaconda3-2024.02-1-Linux-x86_64.sh"
    echo "  Downloading Anaconda installer..."
    wget -q --show-progress -O "$ANACONDA_INSTALLER" "$ANACONDA_URL"
    echo "  Installing Anaconda to $ANACONDA_DIR ..."
    bash "$ANACONDA_INSTALLER" -b -p "$ANACONDA_DIR"
    rm -f "$ANACONDA_INSTALLER"
    echo "  Anaconda installed."
fi

CONDA_INIT_LINE="source \$HOME/anaconda3/etc/profile.d/conda.sh"
if ! grep -qF "$CONDA_INIT_LINE" "$HOME/.bashrc"; then
    echo "" >> "$HOME/.bashrc"
    echo "# Anaconda" >> "$HOME/.bashrc"
    echo "$CONDA_INIT_LINE" >> "$HOME/.bashrc"
    echo "  Added conda init to ~/.bashrc"
fi

# Export PATH for current session
export PATH="$ANACONDA_DIR/bin:$PATH"
# shellcheck disable=SC1090
source "$ANACONDA_DIR/etc/profile.d/conda.sh"

# ─────────────────────────────────────────────────────────────────────────────
# [3/6] Clone or update repo
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[3/6] Cloning/updating repository ──────────────────────────────────────────"

mkdir -p "$PROJECTS_DIR"

if [[ -d "$REPO_DIR/.git" ]]; then
    echo "  Repo already exists at $REPO_DIR — pulling latest changes."
    git -C "$REPO_DIR" pull
else
    if [[ "$USE_SSH" == true ]]; then
        echo "  Cloning via SSH: $SSH_URL"
        git clone "$SSH_URL" "$REPO_DIR"
    else
        echo "  Cloning via HTTPS: $HTTPS_URL"
        if ! git clone "$HTTPS_URL" "$REPO_DIR"; then
            echo ""
            echo "  ⚠  Clone failed. The repo may be private."
            echo "  If you have an SSH key configured on this VM, re-run with:"
            echo ""
            echo "      bash setup.sh $KEYWORD --ssh"
            echo ""
            exit 1
        fi
    fi
    echo "  Cloned to $REPO_DIR"
fi

# ─────────────────────────────────────────────────────────────────────────────
# [4/6] Delegate to leaf setup or run default fallback
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[4/6] Setting up environment ────────────────────────────────────────────────"

cd "$REPO_DIR"

if [[ -f ".vmsetup.sh" ]]; then
    echo "  Found .vmsetup.sh — delegating to repo-specific setup."
    bash .vmsetup.sh
else
    echo "  No .vmsetup.sh found — running default conda environment setup."
    ENV_NAME="$KEYWORD"

    if conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
        echo "  Conda env '$ENV_NAME' already exists — skipping creation."
    else
        if [[ -f "environment.yml" ]]; then
            echo "  Creating conda env from environment.yml ..."
            conda env create -n "$ENV_NAME" -f environment.yml
        elif [[ -f "requirements.txt" ]]; then
            echo "  Creating conda env '$ENV_NAME' with Python 3.10 ..."
            conda create -n "$ENV_NAME" python=3.10 -y
            echo "  Installing dependencies from requirements.txt ..."
            # shellcheck disable=SC1090
            source "$ANACONDA_DIR/etc/profile.d/conda.sh"
            conda run -n "$ENV_NAME" pip install -r requirements.txt
        else
            echo "  No environment.yml or requirements.txt found — creating bare env."
            conda create -n "$ENV_NAME" python=3.10 -y
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# [5/6] Register alias in ~/.bashrc
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[5/6] Registering alias ─────────────────────────────────────────────────────"

ALIAS_NAME="$KEYWORD"
ALIAS_LINE="alias ${ALIAS_NAME}='source \$HOME/anaconda3/etc/profile.d/conda.sh && conda activate ${KEYWORD} && cd \$HOME/projects/${REPO_NAME}'"

if grep -qF "alias ${ALIAS_NAME}=" "$HOME/.bashrc"; then
    echo "  Alias '$ALIAS_NAME' already exists in ~/.bashrc — skipping."
else
    echo "" >> "$HOME/.bashrc"
    echo "# $KEYWORD alias" >> "$HOME/.bashrc"
    echo "$ALIAS_LINE" >> "$HOME/.bashrc"
    echo "  Alias '$ALIAS_NAME' registered."
fi

# ─────────────────────────────────────────────────────────────────────────────
# [6/6] Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "═════════════════════════════════════════════════════════════════════════════"
echo " Setup complete!"
echo "─────────────────────────────────────────────────────────────────────────────"
echo "  Repo cloned to : $REPO_DIR"
echo "  Conda env      : $KEYWORD"
echo "  Alias          : $ALIAS_NAME"
echo "─────────────────────────────────────────────────────────────────────────────"
echo "  To activate, run:"
echo ""
echo "      source ~/.bashrc && $ALIAS_NAME"
echo ""
echo "═════════════════════════════════════════════════════════════════════════════"
