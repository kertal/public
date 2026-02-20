/* ========================================================================
   Terminal + Browser Preview - Renderer
   3-level tabs: Projects > Terminal tabs + Browser tabs
   ======================================================================== */

const { Terminal } = require('@xterm/xterm');
const { FitAddon } = require('@xterm/addon-fit');
const { WebLinksAddon } = require('@xterm/addon-web-links');

const XTERM_THEME = {
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
};

const PROJECT_COLORS = ['#89b4fa', '#a6e3a1', '#fab387', '#cba6f7', '#f38ba8', '#f9e2af', '#94e2d5', '#f5c2e7'];

// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  PROJECT MANAGEMENT                                                  ║
// ╚═══════════════════════════════════════════════════════════════════════╝

const projects = [];       // Array of project objects
let activeProjectId = null;
let nextProjectId = 1;

const mainEl = document.getElementById('main');
const projectTabList = document.getElementById('project-tab-list');

// A project contains: { id, name, color, layout, workspaceEl,
//   terminalTabs[], activeTerminalId, nextTerminalId,
//   browserTabs[], activeBrowserId, nextBrowserId,
//   dom: { termPanel, termTabList, termContainer, browserPanel, browserTabList,
//          webviewContainer, urlInput, divider } }

function createProjectDOM(project) {
  const ws = document.createElement('div');
  ws.className = 'project-workspace';
  ws.dataset.projectId = project.id;

  ws.innerHTML = `
    <div class="panel-terminal">
      <div class="tab-bar">
        <div class="term-tab-list"></div>
        <button class="new-tab-btn new-term-btn" title="New Terminal">+</button>
      </div>
      <div class="term-container" style="flex:1;overflow:hidden;position:relative;"></div>
    </div>
    <div class="panel-divider"></div>
    <div class="panel-browser">
      <div class="tab-bar">
        <div class="browser-tab-list"></div>
        <button class="new-tab-btn new-browser-btn" title="New Tab">+</button>
      </div>
      <div class="url-bar">
        <button class="nav-btn nav-back" title="Back">&#8592;</button>
        <button class="nav-btn nav-forward" title="Forward">&#8594;</button>
        <button class="nav-btn nav-reload" title="Reload">&#8635;</button>
        <input type="text" class="url-input" placeholder="Enter URL or file path..." spellcheck="false">
        <button class="nav-btn nav-devtools" title="DevTools">&#128295;</button>
      </div>
      <div class="webview-container"></div>
    </div>
  `;

  mainEl.appendChild(ws);

  const dom = {
    workspace: ws,
    termPanel: ws.querySelector('.panel-terminal'),
    termTabList: ws.querySelector('.term-tab-list'),
    termContainer: ws.querySelector('.term-container'),
    browserPanel: ws.querySelector('.panel-browser'),
    browserTabList: ws.querySelector('.browser-tab-list'),
    webviewContainer: ws.querySelector('.webview-container'),
    urlInput: ws.querySelector('.url-input'),
    divider: ws.querySelector('.panel-divider')
  };

  // Wire up new-tab buttons
  ws.querySelector('.new-term-btn').addEventListener('click', () => {
    addTerminalTab(project);
  });

  ws.querySelector('.new-browser-btn').addEventListener('click', () => {
    addBrowserTab(project);
    dom.urlInput.focus();
  });

  // Wire up URL bar
  dom.urlInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      navigateBrowser(project, dom.urlInput.value);
      dom.urlInput.blur();
    }
  });
  dom.urlInput.addEventListener('focus', () => dom.urlInput.select());

  // Wire up nav buttons
  ws.querySelector('.nav-back').addEventListener('click', () => {
    const wv = getActiveWebview(project);
    if (wv && wv.canGoBack()) wv.goBack();
  });
  ws.querySelector('.nav-forward').addEventListener('click', () => {
    const wv = getActiveWebview(project);
    if (wv && wv.canGoForward()) wv.goForward();
  });
  ws.querySelector('.nav-reload').addEventListener('click', () => {
    const wv = getActiveWebview(project);
    if (wv) wv.reload();
  });
  ws.querySelector('.nav-devtools').addEventListener('click', () => {
    const wv = getActiveWebview(project);
    if (wv) {
      if (wv.isDevToolsOpened()) wv.closeDevTools();
      else wv.openDevTools();
    }
  });

  // Wire up divider drag
  setupDividerDrag(project, dom);

  // Wire up panel focus tracking
  dom.termPanel.addEventListener('mousedown', () => { project.focusedPanel = 'terminal'; });
  dom.browserPanel.addEventListener('mousedown', () => { project.focusedPanel = 'browser'; });

  // Resize observer for terminal fitting
  const resizeObs = new ResizeObserver(() => {
    const tt = getActiveTerminalTab(project);
    if (!tt) return;
    requestAnimationFrame(() => {
      tt.fitAddon.fit();
      if (tt.alive) window.terminalAPI.resize(tt.ptyId, tt.term.cols, tt.term.rows);
      if (project.id === activeProjectId) updateStatusBar(project);
    });
  });
  resizeObs.observe(dom.termContainer);

  return dom;
}

async function createProject(name) {
  const id = nextProjectId++;
  const color = PROJECT_COLORS[(id - 1) % PROJECT_COLORS.length];

  const project = {
    id,
    name: name || `Project ${id}`,
    color,
    layout: 'split',
    focusedPanel: 'terminal',
    terminalTabs: [],
    activeTerminalId: null,
    nextTerminalId: 1,
    browserTabs: [],
    activeBrowserId: null,
    nextBrowserId: 1,
    dom: null
  };

  project.dom = createProjectDOM(project);
  projects.push(project);

  // Create initial terminal + browser tab
  await addTerminalTab(project);
  addBrowserTab(project, 'https://duckduckgo.com');

  switchProject(id);
  renderProjectTabs();
  return project;
}

function switchProject(id) {
  activeProjectId = id;
  projects.forEach(p => {
    p.dom.workspace.classList.toggle('active', p.id === id);
  });

  const proj = getActiveProject();
  if (proj) {
    applyLayout(proj, proj.layout);
    // Refit active terminal
    const tt = getActiveTerminalTab(proj);
    if (tt) {
      requestAnimationFrame(() => {
        tt.fitAddon.fit();
        if (tt.alive) window.terminalAPI.resize(tt.ptyId, tt.term.cols, tt.term.rows);
        tt.term.focus();
      });
    }
    updateStatusBar(proj);
  }
  renderProjectTabs();
}

function closeProject(id) {
  const idx = projects.findIndex(p => p.id === id);
  if (idx === -1) return;

  const proj = projects[idx];

  // Kill all PTY processes
  for (const tt of proj.terminalTabs) {
    if (tt.alive) window.terminalAPI.kill(tt.ptyId);
    tt.term.dispose();
  }

  // Remove DOM
  proj.dom.workspace.remove();
  projects.splice(idx, 1);

  if (projects.length === 0) {
    createProject();
  } else if (activeProjectId === id) {
    const newIdx = Math.min(idx, projects.length - 1);
    switchProject(projects[newIdx].id);
  }
  renderProjectTabs();
}

function getActiveProject() {
  return projects.find(p => p.id === activeProjectId) || null;
}

function renderProjectTabs() {
  projectTabList.innerHTML = '';
  projects.forEach(proj => {
    const el = document.createElement('div');
    el.className = 'project-tab' + (proj.id === activeProjectId ? ' active' : '');

    const dot = document.createElement('span');
    dot.className = 'color-dot';
    dot.style.background = proj.color;
    el.appendChild(dot);

    const title = document.createElement('span');
    title.className = 'tab-title';
    title.textContent = proj.name;
    title.addEventListener('dblclick', (e) => {
      e.stopPropagation();
      renameProject(proj);
    });
    el.appendChild(title);

    const close = document.createElement('span');
    close.className = 'tab-close';
    close.textContent = '\u00d7';
    close.addEventListener('click', (e) => {
      e.stopPropagation();
      closeProject(proj.id);
    });
    el.appendChild(close);

    el.addEventListener('click', () => switchProject(proj.id));
    projectTabList.appendChild(el);
  });
}

function renameProject(proj) {
  const tabEl = projectTabList.querySelector(`.project-tab:nth-child(${projects.indexOf(proj) + 1}) .tab-title`);
  if (!tabEl) return;
  const input = document.createElement('input');
  input.type = 'text';
  input.value = proj.name;
  input.style.cssText = 'width:100px;background:var(--overlay);border:1px solid var(--accent);color:var(--text);font-size:12px;font-family:inherit;border-radius:3px;padding:0 4px;outline:none;';
  tabEl.replaceWith(input);
  input.focus();
  input.select();

  const finish = () => {
    proj.name = input.value.trim() || proj.name;
    renderProjectTabs();
  };
  input.addEventListener('blur', finish);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') input.blur();
    if (e.key === 'Escape') { input.value = proj.name; input.blur(); }
  });
}

// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  TERMINAL TAB MANAGEMENT (per project)                              ║
// ╚═══════════════════════════════════════════════════════════════════════╝

async function addTerminalTab(project) {
  const tabId = project.nextTerminalId++;

  const containerEl = document.createElement('div');
  containerEl.className = 'terminal-instance';
  project.dom.termContainer.appendChild(containerEl);

  const term = new Terminal({
    fontSize: 14,
    fontFamily: "'JetBrains Mono', 'Fira Code', 'Cascadia Code', 'SF Mono', 'Consolas', monospace",
    cursorBlink: true,
    cursorStyle: 'bar',
    allowProposedApi: true,
    scrollback: 10000,
    theme: XTERM_THEME
  });

  const fitAddon = new FitAddon();
  term.loadAddon(fitAddon);
  term.loadAddon(new WebLinksAddon());
  term.open(containerEl);

  const { id: ptyId, shell } = await window.terminalAPI.create();

  const tab = {
    id: tabId,
    ptyId,
    shell,
    title: `${shell} #${tabId}`,
    term,
    fitAddon,
    containerEl,
    alive: true
  };

  term.onData((data) => {
    if (tab.alive) window.terminalAPI.write(ptyId, data);
  });

  project.terminalTabs.push(tab);
  switchTerminalTab(project, tabId);

  requestAnimationFrame(() => {
    fitAddon.fit();
    window.terminalAPI.resize(ptyId, term.cols, term.rows);
    if (project.id === activeProjectId) updateStatusBar(project);
  });

  return tab;
}

function switchTerminalTab(project, tabId) {
  project.activeTerminalId = tabId;
  project.terminalTabs.forEach(t => {
    const isActive = t.id === tabId;
    t.containerEl.classList.toggle('active', isActive);
    if (isActive) {
      requestAnimationFrame(() => {
        t.fitAddon.fit();
        if (t.alive) window.terminalAPI.resize(t.ptyId, t.term.cols, t.term.rows);
        t.term.focus();
        if (project.id === activeProjectId) updateStatusBar(project);
      });
    }
  });
  renderTerminalTabs(project);
}

function closeTerminalTab(project, tabId) {
  const idx = project.terminalTabs.findIndex(t => t.id === tabId);
  if (idx === -1) return;

  const tab = project.terminalTabs[idx];
  if (tab.alive) window.terminalAPI.kill(tab.ptyId);
  tab.term.dispose();
  tab.containerEl.remove();
  project.terminalTabs.splice(idx, 1);

  if (project.terminalTabs.length === 0) {
    addTerminalTab(project);
  } else if (project.activeTerminalId === tabId) {
    const newIdx = Math.min(idx, project.terminalTabs.length - 1);
    switchTerminalTab(project, project.terminalTabs[newIdx].id);
  }
  renderTerminalTabs(project);
}

function getActiveTerminalTab(project) {
  return project.terminalTabs.find(t => t.id === project.activeTerminalId) || null;
}

function renderTerminalTabs(project) {
  const list = project.dom.termTabList;
  list.innerHTML = '';
  project.terminalTabs.forEach(tab => {
    const el = document.createElement('div');
    el.className = 'tab-item' + (tab.id === project.activeTerminalId ? ' active' : '');

    const title = document.createElement('span');
    title.className = 'tab-title';
    title.textContent = tab.title;
    el.appendChild(title);

    const close = document.createElement('span');
    close.className = 'tab-close';
    close.textContent = '\u00d7';
    close.addEventListener('click', (e) => {
      e.stopPropagation();
      closeTerminalTab(project, tab.id);
    });
    el.appendChild(close);

    el.addEventListener('click', () => switchTerminalTab(project, tab.id));
    list.appendChild(el);
  });
}

// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  BROWSER TAB MANAGEMENT (per project)                               ║
// ╚═══════════════════════════════════════════════════════════════════════╝

function addBrowserTab(project, url = 'about:blank') {
  const id = project.nextBrowserId++;

  const webview = document.createElement('webview');
  webview.setAttribute('src', url);
  webview.setAttribute('allowpopups', '');
  webview.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;display:none;';
  project.dom.webviewContainer.appendChild(webview);

  const tab = { id, title: 'New Tab', url, webview };

  webview.addEventListener('did-navigate', (e) => {
    tab.url = e.url;
    if (tab.id === project.activeBrowserId && project.id === activeProjectId) {
      project.dom.urlInput.value = e.url;
    }
  });

  webview.addEventListener('did-navigate-in-page', (e) => {
    tab.url = e.url;
    if (tab.id === project.activeBrowserId && project.id === activeProjectId) {
      project.dom.urlInput.value = e.url;
    }
  });

  webview.addEventListener('page-title-updated', (e) => {
    tab.title = e.title || 'Untitled';
    renderBrowserTabs(project);
  });

  webview.addEventListener('did-start-loading', () => {
    if (tab.id === project.activeBrowserId && project.id === activeProjectId) {
      document.getElementById('webview-status').textContent = 'Loading...';
    }
  });

  webview.addEventListener('did-stop-loading', () => {
    if (tab.id === project.activeBrowserId && project.id === activeProjectId) {
      document.getElementById('webview-status').textContent = '';
    }
  });

  project.browserTabs.push(tab);
  switchBrowserTab(project, id);
  renderBrowserTabs(project);
  return tab;
}

function switchBrowserTab(project, id) {
  project.activeBrowserId = id;
  project.browserTabs.forEach(t => {
    t.webview.style.display = t.id === id ? 'flex' : 'none';
  });
  const tab = project.browserTabs.find(t => t.id === id);
  if (tab) project.dom.urlInput.value = tab.url;
  renderBrowserTabs(project);
}

function closeBrowserTab(project, id) {
  const idx = project.browserTabs.findIndex(t => t.id === id);
  if (idx === -1) return;

  project.browserTabs[idx].webview.remove();
  project.browserTabs.splice(idx, 1);

  if (project.browserTabs.length === 0) {
    addBrowserTab(project);
  } else if (project.activeBrowserId === id) {
    const newIdx = Math.min(idx, project.browserTabs.length - 1);
    switchBrowserTab(project, project.browserTabs[newIdx].id);
  }
  renderBrowserTabs(project);
}

function renderBrowserTabs(project) {
  const list = project.dom.browserTabList;
  list.innerHTML = '';
  project.browserTabs.forEach(tab => {
    const el = document.createElement('div');
    el.className = 'tab-item' + (tab.id === project.activeBrowserId ? ' active' : '');

    const title = document.createElement('span');
    title.className = 'tab-title';
    title.textContent = tab.title;
    el.appendChild(title);

    const close = document.createElement('span');
    close.className = 'tab-close';
    close.textContent = '\u00d7';
    close.addEventListener('click', (e) => {
      e.stopPropagation();
      closeBrowserTab(project, tab.id);
    });
    el.appendChild(close);

    el.addEventListener('click', () => switchBrowserTab(project, tab.id));
    list.appendChild(el);
  });
}

function getActiveWebview(project) {
  const tab = project.browserTabs.find(t => t.id === project.activeBrowserId);
  return tab ? tab.webview : null;
}

function navigateBrowser(project, input) {
  const wv = getActiveWebview(project);
  if (!wv) return;

  let url = input.trim();
  if (!url) return;

  if (url.startsWith('/') || url.startsWith('./') || url.startsWith('~')) {
    url = 'file://' + url;
  } else if (!url.match(/^[a-zA-Z]+:\/\//)) {
    if (url.match(/^[\w.-]+\.\w{2,}/)) {
      url = 'https://' + url;
    } else {
      url = 'https://duckduckgo.com/?q=' + encodeURIComponent(url);
    }
  }

  wv.setAttribute('src', url);
  const tab = project.browserTabs.find(t => t.id === project.activeBrowserId);
  if (tab) tab.url = url;
}

// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  PTY DATA/EXIT ROUTING                                              ║
// ╚═══════════════════════════════════════════════════════════════════════╝

window.terminalAPI.onData((ptyId, data) => {
  for (const proj of projects) {
    const tab = proj.terminalTabs.find(t => t.ptyId === ptyId);
    if (tab) { tab.term.write(data); return; }
  }
});

window.terminalAPI.onExit((ptyId, exitCode) => {
  for (const proj of projects) {
    const tab = proj.terminalTabs.find(t => t.ptyId === ptyId);
    if (tab) {
      tab.alive = false;
      tab.term.write(`\r\n\x1b[31m[Process exited with code ${exitCode}]\x1b[0m\r\n`);
      tab.title = `(exited) ${tab.shell}`;
      renderTerminalTabs(proj);
      if (proj.id === activeProjectId) updateStatusBar(proj);
      return;
    }
  }
});

// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  DIVIDER DRAG (per project)                                         ║
// ╚═══════════════════════════════════════════════════════════════════════╝

function setupDividerDrag(project, dom) {
  let dragging = false;

  dom.divider.addEventListener('mousedown', (e) => {
    dragging = true;
    dom.divider.classList.add('dragging');
    const isVert = dom.workspace.classList.contains('layout-vertical');
    document.body.style.cursor = isVert ? 'row-resize' : 'col-resize';
    document.body.style.userSelect = 'none';
    dom.webviewContainer.style.pointerEvents = 'none';
    e.preventDefault();
  });

  document.addEventListener('mousemove', (e) => {
    if (!dragging) return;
    const rect = dom.workspace.getBoundingClientRect();

    if (dom.workspace.classList.contains('layout-vertical')) {
      const pct = ((e.clientY - rect.top) / rect.height) * 100;
      const clamped = Math.max(15, Math.min(85, pct));
      dom.termPanel.style.flex = 'none';
      dom.termPanel.style.height = clamped + '%';
      dom.browserPanel.style.flex = 'none';
      dom.browserPanel.style.height = (100 - clamped) + '%';
    } else {
      const pct = ((e.clientX - rect.left) / rect.width) * 100;
      const clamped = Math.max(15, Math.min(85, pct));
      dom.termPanel.style.flex = 'none';
      dom.termPanel.style.width = clamped + '%';
      dom.browserPanel.style.flex = 'none';
      dom.browserPanel.style.width = (100 - clamped) + '%';
    }
  });

  document.addEventListener('mouseup', () => {
    if (!dragging) return;
    dragging = false;
    dom.divider.classList.remove('dragging');
    document.body.style.cursor = '';
    document.body.style.userSelect = '';
    dom.webviewContainer.style.pointerEvents = '';
    const tt = getActiveTerminalTab(project);
    if (tt) {
      tt.fitAddon.fit();
      if (tt.alive) window.terminalAPI.resize(tt.ptyId, tt.term.cols, tt.term.rows);
    }
  });
}

// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  LAYOUT                                                             ║
// ╚═══════════════════════════════════════════════════════════════════════╝

const layoutButtons = {
  split: document.getElementById('btn-layout-split'),
  terminal: document.getElementById('btn-layout-terminal'),
  browser: document.getElementById('btn-layout-browser'),
  vertical: document.getElementById('btn-layout-vertical')
};

function applyLayout(project, mode) {
  const ws = project.dom.workspace;
  ws.classList.remove('layout-terminal-only', 'layout-browser-only', 'layout-vertical');

  // Reset inline drag styles
  const { termPanel, browserPanel } = project.dom;
  termPanel.style.flex = '';
  termPanel.style.width = '';
  termPanel.style.height = '';
  browserPanel.style.flex = '';
  browserPanel.style.width = '';
  browserPanel.style.height = '';

  switch (mode) {
    case 'terminal': ws.classList.add('layout-terminal-only'); break;
    case 'browser': ws.classList.add('layout-browser-only'); break;
    case 'vertical': ws.classList.add('layout-vertical'); break;
  }

  project.layout = mode;

  // Update toolbar buttons
  Object.values(layoutButtons).forEach(b => b.classList.remove('active'));
  if (layoutButtons[mode]) layoutButtons[mode].classList.add('active');
  else layoutButtons.split.classList.add('active');

  requestAnimationFrame(() => {
    const tt = getActiveTerminalTab(project);
    if (tt) {
      tt.fitAddon.fit();
      if (tt.alive) window.terminalAPI.resize(tt.ptyId, tt.term.cols, tt.term.rows);
      updateStatusBar(project);
    }
  });
}

function setLayoutForActiveProject(mode) {
  const proj = getActiveProject();
  if (proj) applyLayout(proj, mode);
}

layoutButtons.split.addEventListener('click', () => setLayoutForActiveProject('split'));
layoutButtons.terminal.addEventListener('click', () => setLayoutForActiveProject('terminal'));
layoutButtons.browser.addEventListener('click', () => setLayoutForActiveProject('browser'));
layoutButtons.vertical.addEventListener('click', () => setLayoutForActiveProject('vertical'));

// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  STATUS BAR                                                         ║
// ╚═══════════════════════════════════════════════════════════════════════╝

function updateStatusBar(project) {
  const tt = getActiveTerminalTab(project);
  const dot = document.getElementById('pty-status');
  const label = document.getElementById('pty-label');
  const sizeEl = document.getElementById('terminal-size');

  if (tt && tt.alive) {
    dot.style.background = '#a6e3a1';
    label.textContent = `${tt.shell} (pty:${tt.ptyId})`;
    sizeEl.textContent = `${tt.term.cols}x${tt.term.rows}`;
  } else if (tt) {
    dot.style.background = '#f38ba8';
    label.textContent = 'Exited';
    sizeEl.textContent = `${tt.term.cols}x${tt.term.rows}`;
  } else {
    dot.style.background = '#585b70';
    label.textContent = 'No terminal';
    sizeEl.textContent = '';
  }
}

// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  NEW PROJECT BUTTON                                                 ║
// ╚═══════════════════════════════════════════════════════════════════════╝

document.getElementById('new-project-btn').addEventListener('click', () => {
  createProject();
});

// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  KEYBOARD SHORTCUTS                                                 ║
// ╚═══════════════════════════════════════════════════════════════════════╝

document.addEventListener('keydown', (e) => {
  const mod = e.ctrlKey || e.metaKey;
  const proj = getActiveProject();
  if (!proj) return;

  // Ctrl+Shift+P = new project
  if (mod && e.shiftKey && e.key === 'P') {
    e.preventDefault();
    createProject();
    return;
  }

  // Ctrl+Shift+T = new terminal tab
  if (mod && e.shiftKey && e.key === 'T') {
    e.preventDefault();
    addTerminalTab(proj);
    return;
  }

  // Ctrl+T = new browser tab
  if (mod && !e.shiftKey && e.key === 't') {
    e.preventDefault();
    addBrowserTab(proj);
    proj.dom.urlInput.focus();
    return;
  }

  // Ctrl+W = close active tab in focused panel
  if (mod && !e.shiftKey && e.key === 'w') {
    e.preventDefault();
    if (proj.focusedPanel === 'terminal' && proj.activeTerminalId) {
      closeTerminalTab(proj, proj.activeTerminalId);
    } else if (proj.focusedPanel === 'browser' && proj.activeBrowserId) {
      closeBrowserTab(proj, proj.activeBrowserId);
    }
    return;
  }

  // Ctrl+Shift+W = close project
  if (mod && e.shiftKey && e.key === 'W') {
    e.preventDefault();
    closeProject(proj.id);
    return;
  }

  // Ctrl+L = focus URL bar
  if (mod && e.key === 'l') {
    e.preventDefault();
    proj.dom.urlInput.focus();
    proj.dom.urlInput.select();
    return;
  }

  // Ctrl+1/2/3 = layout modes
  if (mod && !e.shiftKey && e.key === '1') { e.preventDefault(); setLayoutForActiveProject('split'); return; }
  if (mod && !e.shiftKey && e.key === '2') { e.preventDefault(); setLayoutForActiveProject('terminal'); return; }
  if (mod && !e.shiftKey && e.key === '3') { e.preventDefault(); setLayoutForActiveProject('browser'); return; }

  // Ctrl+R = reload browser
  if (mod && e.key === 'r') {
    e.preventDefault();
    const wv = getActiveWebview(proj);
    if (wv) wv.reload();
    return;
  }

  // Ctrl+Tab / Ctrl+Shift+Tab = cycle tabs in focused panel
  if (mod && e.key === 'Tab') {
    e.preventDefault();
    if (proj.focusedPanel === 'terminal' && proj.terminalTabs.length > 1) {
      const idx = proj.terminalTabs.findIndex(t => t.id === proj.activeTerminalId);
      const next = e.shiftKey
        ? (idx - 1 + proj.terminalTabs.length) % proj.terminalTabs.length
        : (idx + 1) % proj.terminalTabs.length;
      switchTerminalTab(proj, proj.terminalTabs[next].id);
    } else if (proj.focusedPanel === 'browser' && proj.browserTabs.length > 1) {
      const idx = proj.browserTabs.findIndex(t => t.id === proj.activeBrowserId);
      const next = e.shiftKey
        ? (idx - 1 + proj.browserTabs.length) % proj.browserTabs.length
        : (idx + 1) % proj.browserTabs.length;
      switchBrowserTab(proj, proj.browserTabs[next].id);
    }
    return;
  }

  // Ctrl+PageUp / Ctrl+PageDown = cycle projects
  if (mod && (e.key === 'PageUp' || e.key === 'PageDown')) {
    e.preventDefault();
    if (projects.length > 1) {
      const idx = projects.findIndex(p => p.id === activeProjectId);
      const next = e.key === 'PageDown'
        ? (idx + 1) % projects.length
        : (idx - 1 + projects.length) % projects.length;
      switchProject(projects[next].id);
    }
    return;
  }
});

// ╔═══════════════════════════════════════════════════════════════════════╗
// ║  INITIALIZE                                                         ║
// ╚═══════════════════════════════════════════════════════════════════════╝

createProject('Project 1');
