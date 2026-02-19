#!/usr/bin/env bash
set -euo pipefail

WORKSPACES_DIR="${HOME}/.config/workspaces"
PROJECTS_DIR="${WORKSPACES_DIR}/projects"
STATE_DIR="${WORKSPACES_DIR}/.state"

# ── Helpers ──────────────────────────────────────────────────

usage() {
  cat <<'USAGE'
Usage: workspace <command> [options]

Commands:
  open <project>       Switch to project workspace and launch apps
  close <project>      Tear down project workspace (kill servers, close windows)
  list                 List configured projects
  save <project>       Save current iTerm2 window arrangement for project
  status               Show which workspace/project is active
  note <project> [text] View or set a note for a project workspace
  notes                Show notes for all projects
  ensure <ws-number>   Ensure workspace has its project initialized (used by AeroSpace callback)

Options:
  --no-switch          Skip AeroSpace workspace switch (used when called from AeroSpace binding)

Examples:
  workspace open frontend
  workspace close api
  workspace list
  workspace status
  workspace note frontend "TODO: fix auth bug before deploy"
  workspace note frontend              # view current note
  workspace note frontend ""           # clear the note
  workspace notes                      # show all project notes
USAGE
}

# Parse TOML value under a specific section
# Usage: toml_get <file> <section> <key>
# For top-level keys, use "" as section
toml_get() {
  local file="$1" section="$2" key="$3"
  local in_section=false result=""

  if [[ -z "$section" ]]; then
    # Top-level key (before any section header)
    while IFS= read -r line; do
      # Stop at first section header
      [[ "$line" =~ ^\[.*\] ]] && break
      if [[ "$line" =~ ^${key}[[:space:]]*= ]]; then
        result=$(echo "$line" | sed 's/^[^=]*=[[:space:]]*//;s/^"//;s/"$//')
        break
      fi
    done < "$file"
  else
    while IFS= read -r line; do
      if [[ "$line" =~ ^\[${section}\] ]]; then
        in_section=true
        continue
      fi
      if $in_section; then
        # New section starts — stop
        [[ "$line" =~ ^\[.*\] ]] && break
        if [[ "$line" =~ ^${key}[[:space:]]*= ]]; then
          result=$(echo "$line" | sed 's/^[^=]*=[[:space:]]*//;s/^"//;s/"$//')
          break
        fi
      fi
    done < "$file"
  fi

  echo "$result"
}

# Find project config by workspace number
find_project_for_workspace() {
  local ws="$1"
  for f in "${PROJECTS_DIR}"/*.toml; do
    [[ -f "$f" ]] || continue
    local project_ws
    project_ws=$(toml_get "$f" "project" "workspace")
    if [[ "$project_ws" == "$ws" ]]; then
      basename "$f" .toml
      return 0
    fi
  done
  return 1
}

# ── Commands ─────────────────────────────────────────────────

cmd_open() {
  local project="$1"
  local no_switch="${2:-false}"
  local config="${PROJECTS_DIR}/${project}.toml"

  if [[ ! -f "$config" ]]; then
    echo "Error: No config found for project '${project}'"
    echo "Expected: ${config}"
    echo ""
    echo "Available projects:"
    cmd_list
    exit 1
  fi

  local ws dir url arrangement
  ws=$(toml_get "$config" "project" "workspace")
  dir=$(toml_get "$config" "project" "directory")
  url=$(toml_get "$config" "browser" "url")
  arrangement=$(toml_get "$config" "terminal" "arrangement")
  dir="${dir/#\~/$HOME}"

  echo "-> Switching to workspace ${ws} (${project})"

  # 1. Switch AeroSpace workspace (unless called from AeroSpace itself)
  if [[ "$no_switch" != "true" ]]; then
    if command -v aerospace &>/dev/null; then
      aerospace workspace "$ws" 2>/dev/null || true
    else
      echo "   [skip] aerospace not found"
    fi
  fi

  # 2. Restore iTerm2 arrangement (if configured)
  if [[ -n "$arrangement" ]]; then
    if command -v osascript &>/dev/null; then
      osascript "${WORKSPACES_DIR}/lib/iterm.scpt" restore "$arrangement" 2>/dev/null || true
      echo "   [ok] iTerm2 arrangement '${arrangement}'"
    else
      echo "   [skip] osascript not available"
    fi
  fi

  # 3. Open browser preview (if configured)
  if [[ -n "$url" ]]; then
    if command -v open &>/dev/null; then
      open "$url" 2>/dev/null || true
      echo "   [ok] Browser: ${url}"
    else
      echo "   [skip] 'open' command not available"
    fi
  fi

  # 4. Mark workspace as initialized
  mkdir -p "$STATE_DIR"
  echo "$project" > "${STATE_DIR}/ws-${ws}"

  echo "=> Workspace '${project}' active on workspace ${ws}"

  # 5. Show workspace note (if any)
  local note
  note=$(toml_get "$config" "notes" "text")
  if [[ -n "$note" ]]; then
    echo ""
    echo "   Note: ${note}"
  fi
}

cmd_close() {
  local project="$1"
  local config="${PROJECTS_DIR}/${project}.toml"

  if [[ ! -f "$config" ]]; then
    echo "Error: No config found for project '${project}'"
    exit 1
  fi

  local ws dir
  ws=$(toml_get "$config" "project" "workspace")
  dir=$(toml_get "$config" "project" "directory")
  dir="${dir/#\~/$HOME}"

  echo "-> Closing workspace ${ws} (${project})"

  # Kill dev server processes running in project directory
  if [[ -n "$dir" && -d "$dir" ]]; then
    # Find processes with cwd in project directory (common dev server ports)
    local pids
    pids=$(lsof -ti tcp:3000,3001,4000,5000,5173,8000,8080 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
      for pid in $pids; do
        local proc_cwd
        proc_cwd=$(lsof -p "$pid" -Fn 2>/dev/null | grep '^n.*'"$dir" || true)
        if [[ -n "$proc_cwd" ]]; then
          kill "$pid" 2>/dev/null && echo "   [ok] Killed process ${pid}" || true
        fi
      done
    fi
  fi

  # Close iTerm2 windows for this arrangement
  if command -v osascript &>/dev/null; then
    local arrangement
    arrangement=$(toml_get "$config" "terminal" "arrangement")
    if [[ -n "$arrangement" ]]; then
      osascript "${WORKSPACES_DIR}/lib/iterm.scpt" close "$arrangement" 2>/dev/null || true
      echo "   [ok] Closed iTerm2 windows"
    fi
  fi

  # Clear state
  rm -f "${STATE_DIR}/ws-${ws}"

  echo "=> Workspace '${project}' closed"
}

cmd_list() {
  echo "Configured projects:"
  for f in "${PROJECTS_DIR}"/*.toml; do
    [[ -f "$f" ]] || continue
    local name ws dir
    name=$(basename "$f" .toml)
    ws=$(toml_get "$f" "project" "workspace")
    dir=$(toml_get "$f" "project" "directory")
    echo "  ${name}  (workspace ${ws})  ${dir}"
  done
}

cmd_save() {
  local project="$1"
  if command -v osascript &>/dev/null; then
    osascript "${WORKSPACES_DIR}/lib/iterm.scpt" save "$project"
    echo "Saved iTerm2 arrangement '${project}'"
  else
    echo "Error: osascript not available (macOS only)"
    exit 1
  fi
}

cmd_status() {
  local current_ws
  if command -v aerospace &>/dev/null; then
    current_ws=$(aerospace list-workspaces --focused 2>/dev/null || echo "unknown")
  else
    current_ws="unknown"
  fi
  echo "Active workspace: ${current_ws}"

  for f in "${PROJECTS_DIR}"/*.toml; do
    [[ -f "$f" ]] || continue
    local name ws
    name=$(basename "$f" .toml)
    ws=$(toml_get "$f" "project" "workspace")
    if [[ "$ws" == "$current_ws" ]]; then
      echo "Active project: ${name}"
      return
    fi
  done
  echo "Active project: (none mapped)"
}

cmd_ensure() {
  local ws="$1"
  local state_file="${STATE_DIR}/ws-${ws}"

  # Already initialized this session — skip
  if [[ -f "$state_file" ]]; then
    return 0
  fi

  # Find which project owns this workspace
  local project
  if project=$(find_project_for_workspace "$ws"); then
    cmd_open "$project" "true"
  fi
}

cmd_note() {
  local project="$1"
  local config="${PROJECTS_DIR}/${project}.toml"

  if [[ ! -f "$config" ]]; then
    echo "Error: No config found for project '${project}'"
    exit 1
  fi

  if [[ $# -lt 2 ]]; then
    # View mode: show current note
    local note
    note=$(toml_get "$config" "notes" "text")
    if [[ -n "$note" ]]; then
      echo "${project}: ${note}"
    else
      echo "${project}: (no note set)"
    fi
    return
  fi

  # Set mode: update the note in the TOML file
  local new_note="$2"

  if grep -q '^\[notes\]' "$config"; then
    # [notes] section exists — update text line
    if grep -q '^text' "$config"; then
      sed -i.bak "s|^text[[:space:]]*=.*|text = \"${new_note}\"|" "$config"
    else
      sed -i.bak "/^\[notes\]/a\\
text = \"${new_note}\"" "$config"
    fi
  else
    # No [notes] section — append it
    printf '\n[notes]\ntext = "%s"\n' "$new_note" >> "$config"
  fi
  rm -f "${config}.bak"

  if [[ -n "$new_note" ]]; then
    echo "Note set for ${project}: ${new_note}"
  else
    echo "Note cleared for ${project}"
  fi
}

cmd_notes() {
  local found=false
  for f in "${PROJECTS_DIR}"/*.toml; do
    [[ -f "$f" ]] || continue
    local name note
    name=$(basename "$f" .toml)
    note=$(toml_get "$f" "notes" "text")
    if [[ -n "$note" ]]; then
      echo "  ${name}: ${note}"
      found=true
    fi
  done
  if ! $found; then
    echo "  (no notes set for any project)"
  fi
}

# ── Main ─────────────────────────────────────────────────────

NO_SWITCH=false
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --no-switch) NO_SWITCH=true ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

case "${1:-}" in
  open)   cmd_open "${2:?project name required}" "$NO_SWITCH" ;;
  close)  cmd_close "${2:?project name required}" ;;
  list)   cmd_list ;;
  save)   cmd_save "${2:?project name required}" ;;
  status) cmd_status ;;
  note)
    if [[ -z "${3+x}" ]]; then
      cmd_note "${2:?project name required}"
    else
      cmd_note "${2:?project name required}" "$3"
    fi
    ;;
  notes)  cmd_notes ;;
  ensure) cmd_ensure "${2:?workspace number required}" ;;
  -h|--help) usage ;;
  *)      usage ;;
esac
