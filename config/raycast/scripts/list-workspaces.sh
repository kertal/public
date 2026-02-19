#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title List Workspaces
# @raycast.mode fullOutput
# @raycast.packageName Workspaces

# Optional parameters:
# @raycast.icon :desktopcomputer:

# Documentation:
# @raycast.description List all configured project workspaces
# @raycast.author workspace-restoration
# @raycast.authorURL https://github.com

~/.config/workspaces/workspace.sh list
echo ""
~/.config/workspaces/workspace.sh status
