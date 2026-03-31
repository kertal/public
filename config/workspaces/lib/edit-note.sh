#!/bin/bash
# Edit a workspace note via a macOS input dialog
# Called by SwiftBar menu bar plugin
# Usage: edit-note.sh <project-name>

set -euo pipefail

PROJECT="${1:?project name required}"
WORKSPACE_BIN="${HOME}/bin/workspace"

# Get current note text
current_note=$("$WORKSPACE_BIN" note "$PROJECT" 2>/dev/null | sed "s/^${PROJECT}: //" | sed 's/(no note set)//')

# Show macOS input dialog
new_note=$(osascript <<EOF
set currentNote to "$current_note"
set dialogResult to display dialog "Note for workspace '${PROJECT}':" default answer currentNote buttons {"Cancel", "Clear", "Save"} default button "Save" with title "Workspace Note"
set buttonPressed to button returned of dialogResult
if buttonPressed is "Clear" then
  return ""
else if buttonPressed is "Save" then
  return text returned of dialogResult
else
  error number -128
end if
EOF
) || exit 0

# Update the note
"$WORKSPACE_BIN" note "$PROJECT" "$new_note"
