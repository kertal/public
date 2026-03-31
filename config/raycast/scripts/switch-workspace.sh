#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Switch Workspace
# @raycast.mode fullOutput
# @raycast.packageName Workspaces

# Optional parameters:
# @raycast.icon :desktopcomputer:
# @raycast.argument1 { "type": "text", "placeholder": "project name" }

# Documentation:
# @raycast.description Switch to a project workspace (AeroSpace + iTerm2 + browser)
# @raycast.author workspace-restoration
# @raycast.authorURL https://github.com

~/.config/workspaces/workspace.sh open "$1"
