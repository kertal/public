const express = require('express');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');

const config = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf-8'));

const REPO_ROOT = path.resolve(__dirname, config.repoRoot);
const MAX_CONCURRENT = 3;
let activeProcesses = 0;

const app = express();
app.use(express.json({ limit: '200kb' }));
app.use(express.static(path.join(__dirname, 'public')));

// --- Build prompt from conversation history + context ---

function buildPrompt(messages, sessionContext) {
  const parts = [];

  if (sessionContext) {
    parts.push(`[Session context]\n${sessionContext}\n`);
  }

  // Include prior conversation for multi-turn continuity
  if (messages.length > 1) {
    const history = messages.slice(0, -1).map(m =>
      `[${m.role === 'user' ? 'User' : 'Assistant'}]\n${m.content}`
    ).join('\n\n');
    parts.push(`[Conversation so far]\n${history}\n`);
  }

  // Current question is always last
  const last = messages[messages.length - 1];
  parts.push(last.content);

  return parts.join('\n\n');
}

// --- Validate incoming message structure ---

function validateMessages(messages) {
  const VALID_ROLES = new Set(['user', 'assistant']);

  for (const msg of messages) {
    if (!msg || typeof msg !== 'object') return 'each message must be an object';
    if (!VALID_ROLES.has(msg.role)) return `invalid role: "${msg.role}"`;
    if (typeof msg.content !== 'string') return 'message content must be a string';
    if (msg.content.length === 0) return 'message content must not be empty';
  }
  return null;
}

// --- Spawn CLI and stream output as SSE ---

app.post('/api/chat', (req, res) => {
  const { messages, sessionContext } = req.body;

  if (!Array.isArray(messages) || messages.length === 0) {
    return res.status(400).json({ error: 'messages array is required' });
  }

  const validationError = validateMessages(messages);
  if (validationError) {
    return res.status(400).json({ error: validationError });
  }

  if (sessionContext !== undefined && typeof sessionContext !== 'string') {
    return res.status(400).json({ error: 'sessionContext must be a string' });
  }

  if (activeProcesses >= MAX_CONCURRENT) {
    return res.status(429).json({ error: 'Too many concurrent requests. Try again shortly.' });
  }

  const prompt = buildPrompt(messages, sessionContext);
  const { command, args = [], env = {} } = config.cli;

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  });

  activeProcesses++;
  let finished = false;

  function finish() {
    if (finished) return;
    finished = true;
    activeProcesses--;
  }

  // '--' signals end-of-flags so the prompt is never parsed as a CLI option
  const child = spawn(command, [...args, '--', prompt], {
    cwd: REPO_ROOT,
    env: { ...process.env, ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let totalChars = 0;

  child.stdout.on('data', (chunk) => {
    const text = chunk.toString();
    totalChars += text.length;
    res.write(`data: ${JSON.stringify({ type: 'delta', text })}\n\n`);
  });

  let stderr = '';
  child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });

  child.on('close', (code) => {
    finish();
    if (code !== 0 && stderr) {
      console.error(`CLI stderr (exit ${code}):`, stderr.trim());
      res.write(`data: ${JSON.stringify({ type: 'error', error: `CLI exited with code ${code}` })}\n\n`);
    }
    res.write(`data: ${JSON.stringify({ type: 'done', usage: { totalChars } })}\n\n`);
    res.end();
  });

  child.on('error', (err) => {
    finish();
    console.error('CLI spawn error:', err.message);
    res.write(`data: ${JSON.stringify({ type: 'error', error: 'Failed to start CLI' })}\n\n`);
    res.write(`data: ${JSON.stringify({ type: 'done', usage: { totalChars: 0 } })}\n\n`);
    res.end();
  });

  // Abort on client disconnect
  req.on('close', () => { child.kill(); });
});

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', cli: config.cli.command });
});

// SPA fallback
app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

const PORT = config.port;
const HOST = '127.0.0.1';
app.listen(PORT, HOST, () => {
  console.log(`Markdown QA Server running on http://${HOST}:${PORT}`);
  console.log(`Repository root: ${REPO_ROOT}`);
  console.log(`CLI backend: ${config.cli.command} ${config.cli.args.join(' ')}`);
});
