const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('terminalAPI', {
  send: (data) => ipcRenderer.send('terminal:input', data),
  resize: (cols, rows) => ipcRenderer.send('terminal:resize', { cols, rows }),
  onData: (callback) => ipcRenderer.on('terminal:data', (_event, data) => callback(data)),
  onExit: (callback) => ipcRenderer.on('terminal:exit', (_event, code) => callback(code))
});
