/* ========================================================================
   Terminal + Browser Preview - Renderer
   ======================================================================== */

const { Terminal } = require('@xterm/xterm');
const { FitAddon } = require('@xterm/addon-fit');
const { WebLinksAddon } = require('@xterm/addon-web-links');

// ── Terminal Setup ──────────────────────────────────────────────────────

const term = new Terminal({
  fontSize: 14,
  fontFamily: "'JetBrains Mono', 'Fira Code', 'Cascadia Code', 'SF Mono', 'Consolas', monospace",
  cursorBlink: true,
  cursorStyle: 'bar',
  allowProposedApi: true,
  scrollback: 10000,
  theme: {
    background: '#1e1e2e',
    foreground: '#cdd6f4',
    cursor: '#f5e0dc',
    cursorAccent: '#1e1e2e',
    selectionBackground: '#45475a',
    selectionForeground: '#cdd6f4',
    black: '#45475a',
    red: '#f38ba8',
    green: '#a6e3a1',
    yellow: '#f9e2af',
    blue: '#89b4fa',
    magenta: '#f5c2e7',
    cyan: '#94e2d5',
    white: '#bac2de',
    brightBlack: '#585b70',
    brightRed: '#f38ba8',
    brightGreen: '#a6e3a1',
    brightYellow: '#f9e2af',
    brightBlue: '#89b4fa',
    brightMagenta: '#f5c2e7',
    brightCyan: '#94e2d5',
    brightWhite: '#a6adc8'
  }
});

const fitAddon = new FitAddon();
term.loadAddon(fitAddon);
term.loadAddon(new WebLinksAddon());

const termContainer = document.getElementById('terminal-container');
term.open(termContainer);

requestAnimationFrame(() => {
  fitAddon.fit();
  window.terminalAPI.resize(term.cols, term.rows);
  document.getElementById('terminal-size').textContent = `${term.cols}x${term.rows}`;
});

// Terminal I/O
term.onData((data) => window.terminalAPI.send(data));
window.terminalAPI.onData((data) => term.write(data));
window.terminalAPI.onExit((code) => {
  term.write(`\r\n\x1b[31m[Process exited with code ${code}]\x1b[0m\r\n`);
  document.getElementById('pty-status').style.background = '#f38ba8';
  document.getElementById('pty-label').textContent = 'Disconnected';
});

// Resize handling
const resizeObserver = new ResizeObserver(() => {
  requestAnimationFrame(() => {
    fitAddon.fit();
    window.terminalAPI.resize(term.cols, term.rows);
    document.getElementById('terminal-size').textContent = `${term.cols}x${term.rows}`;
  });
});
resizeObserver.observe(termContainer);

// ── Browser Tab Management ──────────────────────────────────────────────

let tabs = [];
let activeTabId = null;
let nextTabId = 1;

const tabList = document.getElementById('tab-list');
const webviewContainer = document.getElementById('webview-container');
const urlInput = document.getElementById('url-input');

function createTab(url = 'about:blank') {
  const id = nextTabId++;

  const webview = document.createElement('webview');
  webview.setAttribute('src', url);
  webview.setAttribute('allowpopups', '');
  webview.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;display:none;';
  webviewContainer.appendChild(webview);

  const tab = {
    id,
    title: 'New Tab',
    url,
    webview
  };

  // Listen for navigation events
  webview.addEventListener('did-navigate', (e) => {
    tab.url = e.url;
    if (tab.id === activeTabId) urlInput.value = e.url;
  });

  webview.addEventListener('did-navigate-in-page', (e) => {
    tab.url = e.url;
    if (tab.id === activeTabId) urlInput.value = e.url;
  });

  webview.addEventListener('page-title-updated', (e) => {
    tab.title = e.title || 'Untitled';
    renderTabs();
  });

  webview.addEventListener('did-start-loading', () => {
    if (tab.id === activeTabId) {
      document.getElementById('webview-status').textContent = 'Loading...';
    }
  });

  webview.addEventListener('did-stop-loading', () => {
    if (tab.id === activeTabId) {
      document.getElementById('webview-status').textContent = '';
    }
  });

  tabs.push(tab);
  switchToTab(id);
  renderTabs();
  return tab;
}

function switchToTab(id) {
  activeTabId = id;
  tabs.forEach(t => {
    t.webview.style.display = t.id === id ? 'flex' : 'none';
  });
  const tab = tabs.find(t => t.id === id);
  if (tab) urlInput.value = tab.url;
  renderTabs();
}

function closeTab(id) {
  const idx = tabs.findIndex(t => t.id === id);
  if (idx === -1) return;

  const tab = tabs[idx];
  tab.webview.remove();
  tabs.splice(idx, 1);

  if (tabs.length === 0) {
    createTab();
  } else if (activeTabId === id) {
    const newIdx = Math.min(idx, tabs.length - 1);
    switchToTab(tabs[newIdx].id);
  }
  renderTabs();
}

function renderTabs() {
  tabList.innerHTML = '';
  tabs.forEach(tab => {
    const el = document.createElement('div');
    el.className = 'browser-tab' + (tab.id === activeTabId ? ' active' : '');

    const title = document.createElement('span');
    title.className = 'tab-title';
    title.textContent = tab.title;
    el.appendChild(title);

    const close = document.createElement('span');
    close.className = 'tab-close';
    close.textContent = '\u00d7';
    close.addEventListener('click', (e) => {
      e.stopPropagation();
      closeTab(tab.id);
    });
    el.appendChild(close);

    el.addEventListener('click', () => switchToTab(tab.id));
    tabList.appendChild(el);
  });
}

function getActiveWebview() {
  const tab = tabs.find(t => t.id === activeTabId);
  return tab ? tab.webview : null;
}

function navigateTo(input) {
  const wv = getActiveWebview();
  if (!wv) return;

  let url = input.trim();
  if (!url) return;

  // Check if it's a local file path
  if (url.startsWith('/') || url.startsWith('./') || url.startsWith('~')) {
    url = 'file://' + url;
  }
  // Check if it's a URL without protocol
  else if (!url.match(/^[a-zA-Z]+:\/\//)) {
    // Check if it looks like a domain
    if (url.match(/^[\w.-]+\.\w{2,}/)) {
      url = 'https://' + url;
    } else {
      // Treat as search query
      url = 'https://duckduckgo.com/?q=' + encodeURIComponent(url);
    }
  }

  wv.setAttribute('src', url);
  const tab = tabs.find(t => t.id === activeTabId);
  if (tab) tab.url = url;
}

// ── URL Bar Events ──────────────────────────────────────────────────────

urlInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    navigateTo(urlInput.value);
    urlInput.blur();
  }
});

urlInput.addEventListener('focus', () => urlInput.select());

// ── Navigation Buttons ──────────────────────────────────────────────────

document.getElementById('nav-back').addEventListener('click', () => {
  const wv = getActiveWebview();
  if (wv && wv.canGoBack()) wv.goBack();
});

document.getElementById('nav-forward').addEventListener('click', () => {
  const wv = getActiveWebview();
  if (wv && wv.canGoForward()) wv.goForward();
});

document.getElementById('nav-reload').addEventListener('click', () => {
  const wv = getActiveWebview();
  if (wv) wv.reload();
});

document.getElementById('nav-devtools').addEventListener('click', () => {
  const wv = getActiveWebview();
  if (wv) {
    if (wv.isDevToolsOpened()) {
      wv.closeDevTools();
    } else {
      wv.openDevTools();
    }
  }
});

document.getElementById('new-tab-btn').addEventListener('click', () => {
  createTab();
  urlInput.focus();
});

// ── Split Pane Divider ──────────────────────────────────────────────────

const divider = document.getElementById('divider');
const terminalPanel = document.getElementById('terminal-panel');
const browserPanel = document.getElementById('browser-panel');
let isDragging = false;

divider.addEventListener('mousedown', (e) => {
  isDragging = true;
  divider.classList.add('dragging');
  document.body.style.cursor = document.body.classList.contains('vertical') ? 'row-resize' : 'col-resize';
  document.body.style.userSelect = 'none';
  // Prevent webview from capturing mouse events
  webviewContainer.style.pointerEvents = 'none';
  e.preventDefault();
});

document.addEventListener('mousemove', (e) => {
  if (!isDragging) return;
  const main = document.getElementById('main');
  const rect = main.getBoundingClientRect();

  if (document.body.classList.contains('vertical')) {
    const y = e.clientY - rect.top;
    const pct = (y / rect.height) * 100;
    const clamped = Math.max(15, Math.min(85, pct));
    terminalPanel.style.flex = 'none';
    terminalPanel.style.height = clamped + '%';
    browserPanel.style.flex = 'none';
    browserPanel.style.height = (100 - clamped) + '%';
  } else {
    const x = e.clientX - rect.left;
    const pct = (x / rect.width) * 100;
    const clamped = Math.max(15, Math.min(85, pct));
    terminalPanel.style.flex = 'none';
    terminalPanel.style.width = clamped + '%';
    browserPanel.style.flex = 'none';
    browserPanel.style.width = (100 - clamped) + '%';
  }
});

document.addEventListener('mouseup', () => {
  if (!isDragging) return;
  isDragging = false;
  divider.classList.remove('dragging');
  document.body.style.cursor = '';
  document.body.style.userSelect = '';
  webviewContainer.style.pointerEvents = '';
  fitAddon.fit();
  window.terminalAPI.resize(term.cols, term.rows);
});

// ── Layout Buttons ──────────────────────────────────────────────────────

const layoutButtons = {
  split: document.getElementById('btn-layout-split'),
  terminal: document.getElementById('btn-layout-terminal'),
  browser: document.getElementById('btn-layout-browser'),
  vertical: document.getElementById('btn-layout-vertical')
};

function setLayout(mode) {
  document.body.classList.remove('terminal-only', 'browser-only', 'vertical');

  // Reset inline styles from dragging
  terminalPanel.style.flex = '';
  terminalPanel.style.width = '';
  terminalPanel.style.height = '';
  browserPanel.style.flex = '';
  browserPanel.style.width = '';
  browserPanel.style.height = '';

  Object.values(layoutButtons).forEach(b => b.classList.remove('active'));

  switch (mode) {
    case 'terminal':
      document.body.classList.add('terminal-only');
      layoutButtons.terminal.classList.add('active');
      break;
    case 'browser':
      document.body.classList.add('browser-only');
      layoutButtons.browser.classList.add('active');
      break;
    case 'vertical':
      document.body.classList.add('vertical');
      layoutButtons.vertical.classList.add('active');
      break;
    default:
      layoutButtons.split.classList.add('active');
      break;
  }

  requestAnimationFrame(() => {
    fitAddon.fit();
    window.terminalAPI.resize(term.cols, term.rows);
  });
}

layoutButtons.split.addEventListener('click', () => setLayout('split'));
layoutButtons.terminal.addEventListener('click', () => setLayout('terminal'));
layoutButtons.browser.addEventListener('click', () => setLayout('browser'));
layoutButtons.vertical.addEventListener('click', () => setLayout('vertical'));

// ── Keyboard Shortcuts ──────────────────────────────────────────────────

document.addEventListener('keydown', (e) => {
  const mod = e.ctrlKey || e.metaKey;

  if (mod && e.key === 't') {
    e.preventDefault();
    createTab();
    urlInput.focus();
  } else if (mod && e.key === 'w') {
    e.preventDefault();
    if (activeTabId) closeTab(activeTabId);
  } else if (mod && e.key === 'l') {
    e.preventDefault();
    urlInput.focus();
    urlInput.select();
  } else if (mod && e.key === '1') {
    e.preventDefault();
    setLayout('split');
  } else if (mod && e.key === '2') {
    e.preventDefault();
    setLayout('terminal');
  } else if (mod && e.key === '3') {
    e.preventDefault();
    setLayout('browser');
  } else if (mod && e.key === 'r') {
    e.preventDefault();
    const wv = getActiveWebview();
    if (wv) wv.reload();
  }
});

// ── Initialize ──────────────────────────────────────────────────────────

// Detect shell name from the process
const shellName = document.getElementById('shell-name');
// Will be updated from terminal output if possible

// Create initial tab
createTab('https://duckduckgo.com');

// Focus terminal on start
term.focus();
