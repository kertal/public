const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const os = require('os');
const pty = require('node-pty');

let mainWindow;
const ptyProcesses = new Map(); // id -> pty process
let nextPtyId = 1;

function getShell() {
  if (process.platform === 'win32') return 'powershell.exe';
  return process.env.SHELL || '/bin/bash';
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    minWidth: 800,
    minHeight: 500,
    title: 'Terminal + Browser Preview',
    backgroundColor: '#1e1e2e',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      webviewTag: true
    }
  });

  mainWindow.loadFile('index.html');

  // ── Create a new PTY process ──────────────────────────────────────────
  ipcMain.handle('pty:create', (_event, opts = {}) => {
    const id = nextPtyId++;
    const shell = getShell();
    const cwd = opts.cwd || process.env.HOME || os.homedir();

    const proc = pty.spawn(shell, [], {
      name: 'xterm-256color',
      cols: opts.cols || 80,
      rows: opts.rows || 24,
      cwd,
      env: {
        ...process.env,
        TERM: 'xterm-256color',
        COLORTERM: 'truecolor'
      }
    });

    proc.onData((data) => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('pty:data', id, data);
      }
    });

    proc.onExit(({ exitCode }) => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('pty:exit', id, exitCode);
      }
      ptyProcesses.delete(id);
    });

    ptyProcesses.set(id, proc);

    const shellName = path.basename(shell);
    return { id, shell: shellName, pid: proc.pid };
  });

  // ── Write to a PTY ────────────────────────────────────────────────────
  ipcMain.on('pty:write', (_event, id, data) => {
    const proc = ptyProcesses.get(id);
    if (proc) proc.write(data);
  });

  // ── Resize a PTY ──────────────────────────────────────────────────────
  ipcMain.on('pty:resize', (_event, id, cols, rows) => {
    const proc = ptyProcesses.get(id);
    if (proc) {
      try { proc.resize(cols, rows); } catch (_) {}
    }
  });

  // ── Kill a PTY ────────────────────────────────────────────────────────
  ipcMain.on('pty:kill', (_event, id) => {
    const proc = ptyProcesses.get(id);
    if (proc) {
      proc.kill();
      ptyProcesses.delete(id);
    }
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
    for (const proc of ptyProcesses.values()) proc.kill();
    ptyProcesses.clear();
  });
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  for (const proc of ptyProcesses.values()) proc.kill();
  ptyProcesses.clear();
  app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});
