# Terminal + Browser Preview

A Chromium-based desktop application that combines a fully-featured bash/zsh terminal with an integrated browser preview panel. Built with Electron, xterm.js, and node-pty.

## Features

- **Real terminal** - Full bash/zsh shell via node-pty with 256-color support
- **Browser preview** - Chromium-powered webview with tabs, navigation, and DevTools
- **Split-pane layout** - Horizontal, vertical, terminal-only, or browser-only views
- **Resizable panels** - Drag the divider to adjust the split ratio
- **Multiple browser tabs** - Open, close, and switch between tabs
- **URL bar** - Navigate to URLs, file paths, or search queries
- **Keyboard shortcuts** - Ctrl+T (new tab), Ctrl+W (close tab), Ctrl+L (focus URL bar), Ctrl+1/2/3 (layout modes)

## Setup

```bash
cd terminal-browser-preview
npm install
npx electron-rebuild   # rebuild node-pty for Electron
npm start
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+T` | New browser tab |
| `Ctrl+W` | Close current tab |
| `Ctrl+L` | Focus URL bar |
| `Ctrl+R` | Reload page |
| `Ctrl+1` | Split view |
| `Ctrl+2` | Terminal only |
| `Ctrl+3` | Browser only |

## Architecture

- **main.js** - Electron main process: creates window, spawns PTY shell
- **preload.js** - Secure IPC bridge between main and renderer
- **renderer.js** - Terminal (xterm.js) + browser tab management + layout controls
- **index.html** - UI layout with Catppuccin Mocha theme
