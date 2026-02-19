#!/bin/bash

# SwiftBar plugin: workspace switcher menu bar item
# Refreshes every 5 seconds (per filename convention)
# Install: brew install --cask swiftbar
# Place in SwiftBar plugin directory

# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>

PROJECTS_DIR="${HOME}/.config/workspaces/projects"
NOTES_DIR="${HOME}/.config/workspaces/.state"
WORKSPACE_BIN="${HOME}/bin/workspace"

# Get current AeroSpace workspace
CURRENT_WS=$(aerospace list-workspaces --focused 2>/dev/null || echo "?")

# Find which project maps to the current workspace
CURRENT_PROJECT=""
for f in "${PROJECTS_DIR}"/*.toml; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f" .toml)
  ws=$(grep "^workspace" "$f" | sed 's/.*= *//;s/"//g' | tr -d ' ')
  if [[ "$ws" == "$CURRENT_WS" ]]; then
    CURRENT_PROJECT="$name"
    break
  fi
done

# ── Menu bar title ───────────────────────────────────────────

if [[ -n "$CURRENT_PROJECT" ]]; then
  echo ":desktopcomputer: ${CURRENT_PROJECT} | symbolize=true sfsize=13"
else
  echo ":desktopcomputer: ws:${CURRENT_WS} | symbolize=true sfsize=13"
fi

echo "---"

# ── Show note for current workspace (if any) ────────────────

if [[ -n "$CURRENT_PROJECT" ]]; then
  note_text=""
  in_notes=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^\[notes\] ]]; then
      in_notes=true
      continue
    fi
    if $in_notes; then
      [[ "$line" =~ ^\[.*\] ]] && break
      if [[ "$line" =~ ^text[[:space:]]*= ]]; then
        note_text=$(echo "$line" | sed 's/^[^=]*=[[:space:]]*//;s/^"//;s/"$//')
        break
      fi
    fi
  done < "${PROJECTS_DIR}/${CURRENT_PROJECT}.toml"

  if [[ -n "$note_text" ]]; then
    echo ":note.text: ${note_text} | symbolize=true sfsize=11 color=systemYellow"
    echo "---"
  fi
fi

# ── Project list ─────────────────────────────────────────────

for f in "${PROJECTS_DIR}"/*.toml; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f" .toml)
  ws=$(grep "^workspace" "$f" | sed 's/.*= *//;s/"//g' | tr -d ' ')

  if [[ "$name" == "$CURRENT_PROJECT" ]]; then
    echo ":checkmark.circle.fill: ${name} (workspace ${ws}) | symbolize=true color=systemGreen sfsize=13"
  else
    echo ":circle: ${name} (workspace ${ws}) | symbolize=true sfsize=13 bash=${WORKSPACE_BIN} param1=open param2=${name} terminal=false refresh=true"
  fi
done

echo "---"
echo "Refresh | refresh=true"
