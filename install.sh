#!/usr/bin/env bash
set -euo pipefail

# Workspace Restoration System — Installer
# Symlinks config files from this repo into ~/.config and ~/bin

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_SRC="${SCRIPT_DIR}/config"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[ok]${NC} $1"; }
warn()  { echo -e "${YELLOW}[skip]${NC} $1"; }
err()   { echo -e "${RED}[error]${NC} $1"; }

# Create a symlink, backing up existing files
link_file() {
  local src="$1" dst="$2"

  if [[ -L "$dst" ]]; then
    local existing
    existing=$(readlink "$dst")
    if [[ "$existing" == "$src" ]]; then
      info "Already linked: ${dst}"
      return
    fi
    rm "$dst"
  elif [[ -e "$dst" ]]; then
    mv "$dst" "${dst}.backup"
    warn "Backed up existing: ${dst} -> ${dst}.backup"
  fi

  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  info "Linked: ${dst} -> ${src}"
}

echo "=== Workspace Restoration System ==="
echo ""

# ── 1. AeroSpace config ─────────────────────────────────────

echo "-- AeroSpace --"
link_file "${CONFIG_SRC}/aerospace/aerospace.toml" "${HOME}/.config/aerospace/aerospace.toml"
echo ""

# ── 2. Workspace configs + scripts ──────────────────────────

echo "-- Workspaces --"
link_file "${CONFIG_SRC}/workspaces/workspace.sh" "${HOME}/.config/workspaces/workspace.sh"
chmod +x "${HOME}/.config/workspaces/workspace.sh"
link_file "${CONFIG_SRC}/workspaces/lib/iterm.scpt" "${HOME}/.config/workspaces/lib/iterm.scpt"

# Link project configs (don't overwrite user's existing ones)
mkdir -p "${HOME}/.config/workspaces/projects"
for f in "${CONFIG_SRC}/workspaces/projects"/*.toml; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f")
  dst="${HOME}/.config/workspaces/projects/${name}"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    warn "Keeping existing project config: ${dst}"
  else
    link_file "$f" "$dst"
  fi
done
echo ""

# ── 3. ~/bin/workspace symlink ───────────────────────────────

echo "-- CLI --"
mkdir -p "${HOME}/bin"
link_file "${HOME}/.config/workspaces/workspace.sh" "${HOME}/bin/workspace"
chmod +x "${HOME}/bin/workspace"

# Check if ~/bin is in PATH
if [[ ":${PATH}:" != *":${HOME}/bin:"* ]]; then
  warn "~/bin is not in your PATH. Add this to your shell profile:"
  echo "    export PATH=\"\$HOME/bin:\$PATH\""
fi
echo ""

# ── 4. SwiftBar plugin ──────────────────────────────────────

echo "-- SwiftBar --"
if command -v swiftbar &>/dev/null || [[ -d "/Applications/SwiftBar.app" ]]; then
  # SwiftBar expects plugins in its configured directory
  SWIFTBAR_DIR="${HOME}/.config/swiftbar"
  mkdir -p "$SWIFTBAR_DIR"
  link_file "${CONFIG_SRC}/swiftbar/workspaces.5s.sh" "${SWIFTBAR_DIR}/workspaces.5s.sh"
  chmod +x "${SWIFTBAR_DIR}/workspaces.5s.sh"
else
  warn "SwiftBar not installed. Install with: brew install --cask swiftbar"
fi
echo ""

# ── 5. Raycast scripts ──────────────────────────────────────

echo "-- Raycast --"
RAYCAST_DIR="${HOME}/.config/raycast/scripts"
mkdir -p "$RAYCAST_DIR"
for f in "${CONFIG_SRC}/raycast/scripts"/*.sh; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f")
  link_file "$f" "${RAYCAST_DIR}/${name}"
  chmod +x "${RAYCAST_DIR}/${name}"
done
echo ""

# ── 6. State directory ──────────────────────────────────────

mkdir -p "${HOME}/.config/workspaces/.state"

# ── Summary ──────────────────────────────────────────────────

echo "=== Installation complete ==="
echo ""
echo "Next steps:"
echo "  1. Install AeroSpace:  brew install --cask nikitabobko/tap/aerospace"
echo "  2. Edit project configs in: ~/.config/workspaces/projects/"
echo "  3. Save iTerm2 arrangements: workspace save <project-name>"
echo "  4. Switch workspaces:  workspace open <project-name>"
echo "  5. (Optional) Install SwiftBar: brew install --cask swiftbar"
echo ""
echo "Quick test:"
echo "  workspace list"
echo "  workspace status"
