# Terminal + Browser Preview

A Chromium-based desktop application that combines bash/zsh terminals with browser preview tabs, organized into project workspaces. Built with Electron, xterm.js, and node-pty.

## 3-Level Tab Architecture

```
[Project A] [Project B] [Project C] [+]          <-- project tabs (top level)
  ┌──────────────────────┬──────────────────────┐
  │ [bash#1] [zsh#2] [+] │ [Tab1] [Tab2] [+]    │ <-- terminal & browser tabs
  │                      │ [< > ↻ URL bar    🔧] │
  │  Terminal content    │  Browser content      │
  │                      │                       │
  └──────────────────────┴──────────────────────┘
```

Each project is an independent workspace with its own:
- Multiple terminal tabs (each running a separate shell session)
- Multiple browser tabs (each with its own webview)
- Independent layout (split, terminal-only, browser-only, vertical)
- Resizable split divider

## Features

- **Project workspaces** - Color-coded, renamable (double-click), independent
- **Multiple terminals** - Each tab spawns its own bash/zsh PTY process
- **Multiple browser tabs** - Chromium webviews with navigation, DevTools
- **Split-pane layouts** - Horizontal, vertical, terminal-only, browser-only (per project)
- **Resizable panels** - Drag divider to adjust split ratio
- **URL intelligence** - Detects URLs, file paths, and search queries
- **Catppuccin Mocha** dark theme

## Setup

```bash
cd terminal-browser-preview
npm install
npx electron-rebuild   # rebuild node-pty for Electron
npm start
```

## Keyboard Shortcuts

### Projects
| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+P` | New project |
| `Ctrl+Shift+W` | Close project |
| `Ctrl+PageUp/Down` | Cycle projects |

### Terminals
| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+T` | New terminal tab |
| `Ctrl+W` | Close focused tab |
| `Ctrl+Tab` | Next tab (in focused panel) |
| `Ctrl+Shift+Tab` | Previous tab |

### Browser
| Shortcut | Action |
|----------|--------|
| `Ctrl+T` | New browser tab |
| `Ctrl+L` | Focus URL bar |
| `Ctrl+R` | Reload page |

### Layout
| Shortcut | Action |
|----------|--------|
| `Ctrl+1` | Split view |
| `Ctrl+2` | Terminal only |
| `Ctrl+3` | Browser only |

## Architecture

```
main.js      Electron main process - manages PTY pool via IPC
preload.js   Secure context bridge - ID-based terminal API
renderer.js  3-level tab manager: projects > terminals + browsers
index.html   UI layout with Catppuccin Mocha theme
```
