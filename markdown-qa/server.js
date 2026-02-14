const express = require('express');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');

const config = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf-8'));

const REPO_ROOT = path.resolve(__dirname, config.repoRoot);

const app = express();
app.use(express.json());
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

// --- Spawn CLI and stream output as SSE ---

app.post('/api/chat', (req, res) => {
  const { messages, sessionContext } = req.body;

  if (!Array.isArray(messages) || messages.length === 0) {
    return res.status(400).json({ error: 'messages array is required' });
  }

  const prompt = buildPrompt(messages, sessionContext);
  const { command, args = [], env = {} } = config.cli;

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  });

  const child = spawn(command, [...args, prompt], {
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
    if (code !== 0 && stderr) {
      res.write(`data: ${JSON.stringify({ type: 'error', error: stderr.trim() })}\n\n`);
    }
    res.write(`data: ${JSON.stringify({ type: 'done', usage: { totalChars } })}\n\n`);
    res.end();
  });

  child.on('error', (err) => {
    res.write(`data: ${JSON.stringify({ type: 'error', error: `Failed to start "${command}": ${err.message}` })}\n\n`);
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
app.listen(PORT, () => {
  console.log(`Markdown QA Server running on http://localhost:${PORT}`);
  console.log(`Repository root: ${REPO_ROOT}`);
  console.log(`CLI backend: ${config.cli.command} ${config.cli.args.join(' ')}`);
});
