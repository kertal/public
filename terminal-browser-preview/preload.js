const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('terminalAPI', {
  // Create a new PTY shell, returns { id, shell, pid }
  create: (opts) => ipcRenderer.invoke('pty:create', opts),

  // Write data to a specific PTY
  write: (id, data) => ipcRenderer.send('pty:write', id, data),

  // Resize a specific PTY
  resize: (id, cols, rows) => ipcRenderer.send('pty:resize', id, cols, rows),

  // Kill a specific PTY
  kill: (id) => ipcRenderer.send('pty:kill', id),

  // Listen for data from any PTY (callback receives id, data)
  onData: (callback) => ipcRenderer.on('pty:data', (_event, id, data) => callback(id, data)),

  // Listen for PTY exit (callback receives id, exitCode)
  onExit: (callback) => ipcRenderer.on('pty:exit', (_event, id, code) => callback(id, code))
});
