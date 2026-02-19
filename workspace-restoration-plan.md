# macOS Workspace Restoration Plan

A scriptable system for saving, restoring, and switching between multi-project developer workspaces on macOS — combining terminal sessions, browser previews, and tooling like Claude Code.

---

## Problem

When working on multiple projects in parallel, each project needs:
- Multiple terminal tabs/panes (Claude Code, dev server, logs, tests)
- A browser window showing a live preview (`localhost:3000`, etc.)
- Possibly other app windows (editor, database GUI, docs)

Switching between projects means manually rearranging all of this. The goal is **one keystroke** to switch the entire screen to a different project's workspace.

---

## Recommended Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Keyboard Shortcut                  │
│              (alt-1, alt-2, alt-3, ...)              │
└────────────────────────┬────────────────────────────┘
                         │
              ┌──────────▼──────────┐
              │     AeroSpace       │  ← virtual workspace manager
              │  (tiling WM, TOML)  │     no SIP required
              └──────────┬──────────┘
                         │
          ┌──────────────┼──────────────┐
          │              │              │
  ┌───────▼──────┐ ┌────▼─────┐ ┌──────▼──────┐
  │   iTerm2     │ │  Browser │ │  Other Apps │
  │  (profiles,  │ │ (Chrome/ │ │  (editors,  │
  │  arrangements│ │  Safari) │ │   DBs, etc) │
  │  per project)│ │          │ │             │
  └──────────────┘ └──────────┘ └─────────────┘
          │
  ┌───────▼──────────────────────┐
  │  Project launcher script     │  ← `workspace open project-a`
  │  (shell script per project)  │
  └──────────────────────────────┘
```

### Why This Stack

| Component | Role | Why this one |
|-----------|------|-------------|
| **AeroSpace** | Virtual workspace switching | No SIP required, instant switching (no animation), TOML config, CLI-scriptable, works on managed machines |
| **iTerm2** | Terminal sessions | Rich AppleScript/Python API, saved window arrangements, per-project profiles with startup commands |
| **Shell scripts** | Project launchers | Portable, versionable, no dependencies beyond the tools above |
| **Raycast** (optional) | Command palette trigger | Invoke project scripts by name from anywhere |

### Why Not the Alternatives

- **Native macOS Spaces**: No public API. Cannot programmatically create/switch spaces. Animation delay. Spaces reorder themselves.
- **Yabai**: Requires disabling SIP on macOS 15.2+ for space manipulation. Security and corporate policy concerns.
- **Hammerspoon alone**: Spaces module is experimental and flaky. Better as a complement than a foundation.

---

## Implementation Plan

### Phase 1: AeroSpace Setup

Install and configure AeroSpace as the workspace manager.

```bash
brew install --cask nikitabobko/tap/aerospace
```

Create `~/.config/aerospace/aerospace.toml`:

```toml
# AeroSpace configuration for multi-project workspaces

start-at-login = true

# Disable macOS Spaces animations (they interfere)
[gaps]
inner.horizontal = 8
inner.vertical = 8
outer.left = 8
outer.right = 8
outer.top = 8
outer.bottom = 8

# Workspace keybindings
[mode.main.binding]
# Project workspaces (one per project)
alt-1 = 'workspace 1'
alt-2 = 'workspace 2'
alt-3 = 'workspace 3'
alt-4 = 'workspace 4'
alt-5 = 'workspace 5'

# Move focused window to a workspace
alt-shift-1 = 'move-node-to-workspace 1'
alt-shift-2 = 'move-node-to-workspace 2'
alt-shift-3 = 'move-node-to-workspace 3'
alt-shift-4 = 'move-node-to-workspace 4'
alt-shift-5 = 'move-node-to-workspace 5'

# Tiling layout controls
alt-slash = 'layout tiles horizontal vertical'
alt-comma = 'layout accordion horizontal vertical'
alt-f = 'fullscreen'
alt-shift-f = 'layout floating tiling'

# Focus movement
alt-h = 'focus left'
alt-j = 'focus down'
alt-k = 'focus up'
alt-l = 'focus right'

# Resize
alt-shift-h = 'resize width -50'
alt-shift-l = 'resize width +50'
alt-shift-j = 'resize height +50'
alt-shift-k = 'resize height -50'

# Auto-assign apps to workspaces (optional defaults)
[[on-window-detected]]
if.app-id = 'com.apple.finder'
run = 'layout floating'
```

**Key design choice**: Each numbered workspace (1-5) maps to a project. `alt-1` through `alt-5` switch instantly between them. No animation, no SIP, no macOS Spaces involved.

### Phase 2: iTerm2 Project Profiles

Create an iTerm2 profile for each project. Each profile sets:
- **Working directory** to the project root
- **Badge text** to the project name (visual identifier)
- **Tab color** unique per project (instant visual feedback)
- **Initial command** (optional, e.g., `claude` or a startup script)

Profiles can be created in iTerm2 Settings > Profiles, or via the Python API.

Example profiles:
| Profile Name | Working Dir | Badge | Tab Color | Startup Command |
|-------------|-------------|-------|-----------|-----------------|
| `project-a` | `~/code/project-a` | `PROJECT-A` | Blue | `claude` |
| `project-a-server` | `~/code/project-a` | `PROJECT-A:dev` | Blue | `npm run dev` |
| `project-b` | `~/code/project-b` | `PROJECT-B` | Green | `claude` |
| `project-b-server` | `~/code/project-b` | `PROJECT-B:dev` | `yarn dev` | Green |

Then save iTerm2 Window Arrangements per project:
1. Open tabs/panes with the right profiles
2. **Window > Save Window Arrangement** as `project-a`, `project-b`, etc.

### Phase 3: Project Launcher Scripts

Create a `workspace` CLI tool. This is a shell script that orchestrates everything.

#### Directory structure

```
~/.config/workspaces/
├── workspace.sh          # Main CLI script (symlinked to ~/bin/workspace)
├── projects/
│   ├── project-a.toml    # Project config
│   ├── project-b.toml    # Project config
│   └── project-c.toml    # Project config
└── lib/
    └── iterm.scpt        # Shared AppleScript helpers
```

#### Project config format (`projects/project-a.toml`)

```toml
[project]
name = "project-a"
workspace = 1                  # AeroSpace workspace number
directory = "~/code/project-a"

[terminal]
arrangement = "project-a"     # iTerm2 saved arrangement name
# OR define tabs inline:
tabs = [
  { profile = "project-a", command = "claude" },
  { profile = "project-a-server", command = "npm run dev" },
  { profile = "project-a", command = "npm run test -- --watch" },
]

[browser]
url = "http://localhost:3000"
app_mode = true               # Open as standalone window (no browser chrome)

[extras]
# Additional apps to open/focus
apps = ["Visual Studio Code"]
```

#### Main launcher script (`workspace.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

WORKSPACES_DIR="${HOME}/.config/workspaces"
PROJECTS_DIR="${WORKSPACES_DIR}/projects"

usage() {
  echo "Usage: workspace <command> [project]"
  echo ""
  echo "Commands:"
  echo "  open <project>    Switch to project workspace and launch apps"
  echo "  list              List configured projects"
  echo "  save <project>    Save current iTerm2 arrangement for project"
  echo "  status            Show which workspace is active"
  echo ""
  echo "Examples:"
  echo "  workspace open project-a"
  echo "  workspace list"
}

# Parse TOML value (basic — for simple key = "value" pairs)
toml_get() {
  local file="$1" key="$2"
  grep "^${key}" "$file" | sed 's/.*= *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d ' '
}

cmd_open() {
  local project="$1"
  local config="${PROJECTS_DIR}/${project}.toml"

  if [[ ! -f "$config" ]]; then
    echo "Error: No config found for project '${project}'"
    echo "Expected: ${config}"
    exit 1
  fi

  local ws=$(toml_get "$config" "workspace")
  local dir=$(toml_get "$config" "directory")
  local url=$(toml_get "$config" "url")
  local arrangement=$(toml_get "$config" "arrangement")
  dir="${dir/#\~/$HOME}"

  echo "→ Switching to workspace ${ws} (${project})"

  # 1. Switch AeroSpace workspace
  aerospace workspace "$ws" 2>/dev/null || true

  # 2. Restore iTerm2 arrangement (if configured)
  if [[ -n "$arrangement" ]]; then
    osascript <<EOF
      tell application "iTerm2"
        activate
        -- Try to restore saved arrangement
        try
          restore window arrangement "${arrangement}"
        end try
      end tell
EOF
  fi

  # 3. Open browser preview (if configured)
  if [[ -n "$url" ]]; then
    open "$url"
  fi

  echo "✓ Workspace '${project}' active"
}

cmd_list() {
  echo "Configured projects:"
  for f in "${PROJECTS_DIR}"/*.toml; do
    [[ -f "$f" ]] || continue
    local name=$(basename "$f" .toml)
    local ws=$(toml_get "$f" "workspace")
    echo "  ${name} (workspace ${ws})"
  done
}

cmd_save() {
  local project="$1"
  osascript -e "
    tell application \"iTerm2\"
      save window arrangement \"${project}\"
    end tell
  "
  echo "Saved iTerm2 arrangement '${project}'"
}

cmd_status() {
  local current_ws
  current_ws=$(aerospace list-workspaces --focused 2>/dev/null || echo "unknown")
  echo "Active workspace: ${current_ws}"

  for f in "${PROJECTS_DIR}"/*.toml; do
    [[ -f "$f" ]] || continue
    local name=$(basename "$f" .toml)
    local ws=$(toml_get "$f" "workspace")
    if [[ "$ws" == "$current_ws" ]]; then
      echo "Active project: ${name}"
      return
    fi
  done
  echo "Active project: (none mapped)"
}

# Main
case "${1:-}" in
  open)   cmd_open "${2:?project name required}" ;;
  list)   cmd_list ;;
  save)   cmd_save "${2:?project name required}" ;;
  status) cmd_status ;;
  *)      usage ;;
esac
```

### Phase 4: Keyboard Shortcut Integration

Bind workspace switching to keyboard shortcuts that also trigger the launcher. Two approaches:

#### Option A: AeroSpace callbacks (simpler)

In `aerospace.toml`, combine workspace switch with a script:

```toml
[mode.main.binding]
# alt-1 switches workspace AND ensures project-a is initialized
alt-1 = ['workspace 1', 'exec-and-forget ~/.config/workspaces/workspace.sh open project-a --no-switch']
```

(Add a `--no-switch` flag to skip the `aerospace workspace` call when triggered from AeroSpace itself.)

#### Option B: Raycast script commands

Create Raycast script commands in `~/.config/raycast/scripts/`:

```bash
#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Project A
# @raycast.mode silent
# @raycast.packageName Workspaces

~/.config/workspaces/workspace.sh open project-a
```

This lets you type "Project A" in Raycast to switch workspaces.

### Cmd+Tab and Workspace Switching

macOS Cmd+Tab shows apps from **all** AeroSpace workspaces (since AeroSpace uses a single macOS Space, not native Spaces). No Cmd+Tab replacement (AltTab, Contexts, Witch) currently supports AeroSpace workspace filtering.

#### Recommended: Alt+Tab bindings in AeroSpace

Add these to your `aerospace.toml`:

```toml
[mode.main.binding]
# Toggle between last two workspaces (feels like Cmd+Tab between projects)
alt-tab = 'workspace-back-and-forth'

# Cycle windows within the current workspace
alt-grave = 'focus --boundaries-action wrap-around-the-workspace dfs-next'
alt-shift-grave = 'focus --boundaries-action wrap-around-the-workspace dfs-prev'
```

This gives you two levels of switching:
- **`alt-tab`**: Flip between your two most recent project workspaces
- **`alt-backtick`**: Cycle through windows within the current workspace

#### If you want literal Cmd+Tab

macOS intercepts Cmd+Tab at the system level before AeroSpace sees it. To reclaim it, use [Karabiner-Elements](https://karabiner-elements.pqrs.org/) to remap Cmd+Tab to a key AeroSpace can handle:

```json
{
  "description": "Remap cmd+tab to alt+tab for AeroSpace",
  "manipulators": [{
    "type": "basic",
    "from": { "key_code": "tab", "modifiers": { "mandatory": ["command"], "optional": ["shift"] } },
    "to": [{ "key_code": "tab", "modifiers": ["option"] }]
  }]
}
```

Then AeroSpace's `alt-tab = 'workspace-back-and-forth'` binding handles Cmd+Tab presses.

> **Note**: This disables the native macOS app switcher. Most AeroSpace users find `alt-tab` sufficient and skip Karabiner.

### Phase 5: Git Worktrees for Parallel Claude Work

When working on multiple branches of the same repo simultaneously:

```bash
# Create isolated worktrees for each branch/feature
cd ~/code/my-repo
git worktree add ../my-repo-feature-x feature-x
git worktree add ../my-repo-bugfix-y bugfix-y

# Each worktree gets its own workspace
# project config points directory to the worktree path
```

This pairs with the workspace system — each worktree becomes a separate "project" with its own terminal layout, Claude Code session, and browser preview.

---

## Example: Full Setup for Two Projects

### Project A: React frontend

```
Workspace 1 (alt-1)
┌──────────────────────┬──────────────────────┐
│                      │                      │
│  iTerm2: claude      │  Chrome: localhost    │
│  (Claude Code)       │  :3000               │
│                      │                      │
│                      │                      │
├──────────────────────┤                      │
│                      │                      │
│  iTerm2: npm run dev │                      │
│  (dev server)        │                      │
│                      │                      │
└──────────────────────┴──────────────────────┘
```

Config: `~/.config/workspaces/projects/frontend.toml`
```toml
[project]
name = "frontend"
workspace = 1
directory = "~/code/frontend"

[terminal]
arrangement = "frontend"

[browser]
url = "http://localhost:3000"
```

### Project B: Python API

```
Workspace 2 (alt-2)
┌──────────────────────┬──────────────────────┐
│                      │                      │
│  iTerm2: claude      │  Chrome: localhost    │
│  (Claude Code)       │  :8000/docs          │
│                      │  (API docs / Swagger)│
│                      │                      │
├──────────────────────┤                      │
│                      │                      │
│  iTerm2: uvicorn     │                      │
│  (API server)        │                      │
│                      │                      │
└──────────────────────┴──────────────────────┘
```

Config: `~/.config/workspaces/projects/api.toml`
```toml
[project]
name = "api"
workspace = 2
directory = "~/code/api"

[terminal]
arrangement = "api"

[browser]
url = "http://localhost:8000/docs"
```

### Switching between them

```
alt-1  →  instant switch to frontend (terminal + browser + layout)
alt-2  →  instant switch to API (terminal + browser + layout)
```

---

## Phase 6: Menu Bar UI for Workspace Switching

A persistent, clickable UI in the macOS menu bar showing the active workspace and a dropdown to switch between projects.

### Approach Comparison

| Approach | Setup | Persistent Menu Bar | Search/Filter | Language | Extra App |
|----------|-------|-------------------|---------------|----------|-----------|
| **SwiftBar plugin** | Low | Yes | No | Bash | SwiftBar |
| **Raycast extension** | Medium | No (invoke to use) | Yes | TypeScript | Raycast |
| **Alfred workflow** | Medium | No (invoke to use) | Yes (fuzzy) | Bash | Alfred |
| **Hammerspoon menubar** | Low-Med | Yes | No | Lua | Hammerspoon |
| **rumps (Python)** | Low-Med | Yes | No | Python | None |
| **SwiftUI MenuBarExtra** | High | Yes | Possible | Swift | None |

### Recommended: SwiftBar Plugin (lowest friction)

Install SwiftBar:

```bash
brew install --cask swiftbar
```

Create `~/.config/swiftbar/workspaces.5s.sh` (refreshes every 5 seconds):

```bash
#!/bin/bash

# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>

PROJECTS_DIR="${HOME}/.config/workspaces/projects"
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

# Menu bar title: show current project name
if [[ -n "$CURRENT_PROJECT" ]]; then
  echo ":desktopcomputer: ${CURRENT_PROJECT} | symbolize=true sfsize=13"
else
  echo ":desktopcomputer: ws:${CURRENT_WS} | symbolize=true sfsize=13"
fi

echo "---"

# List all projects as menu items
for f in "${PROJECTS_DIR}"/*.toml; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f" .toml)
  ws=$(grep "^workspace" "$f" | sed 's/.*= *//;s/"//g' | tr -d ' ')

  if [[ "$name" == "$CURRENT_PROJECT" ]]; then
    echo ":checkmark.circle.fill: ${name} (workspace ${ws}) | symbolize=true color=systemGreen sfsize=13"
  else
    echo ":circle: ${name} (workspace ${ws}) | symbolize=true sfsize=13 bash=${HOME}/bin/workspace param1=open param2=${name} terminal=false refresh=true"
  fi
done

echo "---"
echo "Refresh | refresh=true"
```

```bash
chmod +x ~/.config/swiftbar/workspaces.5s.sh
```

This gives you:
- A menu bar item showing the current project name
- A dropdown listing all configured projects with a checkmark on the active one
- Click any project to switch (runs `workspace open <name>` silently)
- Auto-refreshes every 5 seconds to reflect keyboard-driven switches

### Alternative: Raycast Extension (for search-driven switching)

If you have many projects (6+), a searchable list is better than a dropdown. A Raycast extension provides:
- Fuzzy search across all workspace names
- Status indicators (green dot = active)
- Secondary actions (Cmd+Enter to just switch terminal, Shift+Enter to open browser only)

```typescript
// src/switch-workspace.tsx — Raycast extension entry point
import { List, ActionPanel, Action, Icon, Color, showToast, Toast } from "@raycast/api";
import { execSync } from "child_process";
import { readdirSync } from "fs";
import { join, basename } from "path";

export default function Command() {
  const home = process.env.HOME!;
  const projectsDir = join(home, ".config/workspaces/projects");
  let currentWs = "";
  try {
    currentWs = execSync("aerospace list-workspaces --focused", { encoding: "utf-8" }).trim();
  } catch {}

  const projects = readdirSync(projectsDir)
    .filter((f) => f.endsWith(".toml"))
    .map((f) => {
      const name = basename(f, ".toml");
      const content = require("fs").readFileSync(join(projectsDir, f), "utf-8");
      const wsMatch = content.match(/^workspace\s*=\s*(\S+)/m);
      const ws = wsMatch ? wsMatch[1].replace(/"/g, "") : "?";
      return { name, ws, isActive: ws === currentWs };
    });

  return (
    <List searchBarPlaceholder="Switch workspace...">
      {projects.map((p) => (
        <List.Item
          key={p.name}
          title={p.name}
          subtitle={`workspace ${p.ws}`}
          icon={p.isActive
            ? { source: Icon.CircleFilled, tintColor: Color.Green }
            : { source: Icon.Circle, tintColor: Color.SecondaryText }}
          actions={
            <ActionPanel>
              <Action
                title="Switch Workspace"
                onAction={() => {
                  execSync(`${home}/bin/workspace open ${p.name}`);
                  showToast({ style: Toast.Style.Success, title: `Switched to ${p.name}` });
                }}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
```

Scaffold with `npx create-raycast-extension`, paste this in, and `npm run dev`.

### Both Together (recommended for power users)

SwiftBar for at-a-glance status + click switching, Raycast for keyboard-driven fuzzy search when you have many projects. They complement each other — SwiftBar is always visible, Raycast is always one hotkey away.

---

## Installation Checklist

1. **Install AeroSpace**: `brew install --cask nikitabobko/tap/aerospace`
2. **Create AeroSpace config**: `~/.config/aerospace/aerospace.toml` (see Phase 1)
3. **Set up iTerm2 profiles**: One profile per project role (claude, server, tests)
4. **Save iTerm2 arrangements**: One arrangement per project
5. **Create workspace configs**: `~/.config/workspaces/projects/<name>.toml`
6. **Install the launcher script**: Copy `workspace.sh` to `~/bin/workspace` and `chmod +x`
7. **Bind shortcuts**: Wire AeroSpace keybindings to workspace launcher (Phase 4)
8. **(Optional) Install SwiftBar**: `brew install --cask swiftbar` for menu bar UI
9. **(Optional) Install Raycast**: For command-palette access to workspace switching

---

## Extensions and Future Ideas

- **Auto-detect running projects**: Check which `localhost` ports are active and show status
- **Teardown command**: `workspace close project-a` — kill dev servers, close browser tabs, free the workspace
- **Monitor-aware layouts**: Different tiling configurations for laptop-only vs. external monitor
- **Session persistence**: Save/restore Claude Code conversation context per workspace
- **MCP integration**: Use an MCP server to let Claude Code itself trigger workspace switches
- **Dotfiles integration**: Check all configs into a dotfiles repo for portability across machines
