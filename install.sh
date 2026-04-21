#!/bin/bash
# install.sh — wire this repo's pi/ and hermes/plugins/ into live locations.
#
# What this does:
#   1. Creates symlinks from ~/.pi/agent, ~/.pi/agents, ~/.hermes/plugins/bd-gate
#      pointing INTO this repo.
#   2. Backs up any pre-existing live content to ~/.pi-*.bak-<timestamp> and
#      ~/.hermes-bd-gate.bak-<timestamp> BEFORE replacing it — never clobbers
#      silently.
#   3. Idempotent: if a live path is already a symlink into this repo, skip it.
#
# Rerun this after `git pull` to re-verify symlinks. Edits to the live symlinks
# land in the repo automatically (that's the whole point).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)

link() {
    local src="$1"   # inside the repo
    local dst="$2"   # live path, e.g. ~/.pi/agent

    # Expand ~
    dst="${dst/#~/$HOME}"

    # Already the right symlink? Skip.
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        echo "  ✓ $dst → already linked"
        return 0
    fi

    # Live path exists and is NOT the right link — back it up.
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        local bak="${dst}.bak-${TS}"
        echo "  ⚠ $dst exists — backing up to $bak"
        mv "$dst" "$bak"
    fi

    # Ensure parent dir exists.
    mkdir -p "$(dirname "$dst")"

    ln -s "$src" "$dst"
    echo "  ✓ $dst → $src"
}

echo "Installing dev-team configs from: $REPO_DIR"
echo

echo "Pi agent config:"
link "$REPO_DIR/pi/agent"  "$HOME/.pi/agent"
link "$REPO_DIR/pi/agents" "$HOME/.pi/agents"
echo

echo "Hermes plugins:"
link "$REPO_DIR/hermes/plugins/bd-gate" "$HOME/.hermes/plugins/bd-gate"
echo

echo "Done. Verify with:"
echo "  hermes plugins list | grep bd-gate"
echo "  pi --print --provider ollama --model qwen3:8b -q 'hi'"
