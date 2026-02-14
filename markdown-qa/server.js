const express = require('express');
const path = require('path');
const fs = require('fs');
const Anthropic = require('@anthropic-ai/sdk');

const config = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf-8'));

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const REPO_ROOT = path.resolve(__dirname, config.repoRoot);

// --- Restrictive file access ---

function isAllowedFile(filePath) {
  const resolved = path.resolve(REPO_ROOT, filePath);
  if (!resolved.startsWith(REPO_ROOT)) return false;
  const ext = path.extname(resolved).toLowerCase();
  if (!config.allowedFileExtensions.includes(ext)) return false;
  if (resolved.includes('node_modules')) return false;
  if (resolved.includes('.git')) return false;
  return true;
}

function indexRepoFiles() {
  const files = [];
  function walk(dir) {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
    catch { return; }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.name.startsWith('.')) continue;
      if (entry.name === 'node_modules') continue;
      if (entry.name === 'markdown-qa') continue;
      if (entry.isDirectory()) {
        walk(full);
      } else {
        const rel = path.relative(REPO_ROOT, full);
        if (isAllowedFile(rel)) {
          const stat = fs.statSync(full);
          if (stat.size <= config.maxFileSizeBytes) {
            files.push({ path: rel, size: stat.size });
          }
        }
      }
    }
  }
  walk(REPO_ROOT);
  return files;
}

function readRepoFile(relPath) {
  if (!isAllowedFile(relPath)) return null;
  const full = path.resolve(REPO_ROOT, relPath);
  try {
    const content = fs.readFileSync(full, 'utf-8');
    return content;
  } catch {
    return null;
  }
}

function buildRepoContext() {
  const files = indexRepoFiles();
  const parts = [];
  for (const file of files) {
    const content = readRepoFile(file.path);
    if (content) {
      parts.push(`--- File: ${file.path} ---\n${content}\n`);
    }
  }
  return parts.join('\n');
}

// --- API Routes ---

// List available repo files
app.get('/api/files', (_req, res) => {
  const files = indexRepoFiles();
  res.json({ files });
});

// Chat endpoint with streaming (SSE)
app.post('/api/chat', async (req, res) => {
  const { messages, sessionContext } = req.body;

  if (!messages || !Array.isArray(messages) || messages.length === 0) {
    return res.status(400).json({ error: 'messages array is required' });
  }

  // Validate messages contain only text
  for (const msg of messages) {
    if (typeof msg.content !== 'string') {
      return res.status(400).json({ error: 'Only text messages are allowed' });
    }
    if (!['user', 'assistant'].includes(msg.role)) {
      return res.status(400).json({ error: 'Invalid message role' });
    }
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'ANTHROPIC_API_KEY not configured' });
  }

  const client = new Anthropic({ apiKey });
  const repoContext = buildRepoContext();

  const systemPrompt = `Du bist ein hilfreicher Assistent, der Fragen zu den Inhalten eines Repositories beantwortet.

Du hast Zugriff auf folgende Dateien aus dem Repository:

<repository-content>
${repoContext}
</repository-content>

Regeln:
- Beantworte Fragen ausschließlich basierend auf dem Inhalt des Repositories.
- Wenn die Antwort nicht in den Repository-Dateien zu finden ist, sage das ehrlich.
- Zitiere relevante Dateien und Abschnitte in deinen Antworten.
- Antworte in der Sprache, in der die Frage gestellt wird.
- Du darfst keine externen URLs aufrufen oder Informationen aus externen Quellen verwenden, außer diese sind explizit in der Whitelist: ${JSON.stringify(config.whitelistedUrls)}
${sessionContext ? `\nKontext dieser Session: ${sessionContext}` : ''}`;

  // Set up SSE
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  });

  try {
    const stream = await client.messages.stream({
      model: config.claude.model,
      max_tokens: config.claude.maxTokens,
      system: systemPrompt,
      messages: messages.map(m => ({ role: m.role, content: m.content })),
    });

    for await (const event of stream) {
      if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
        res.write(`data: ${JSON.stringify({ type: 'delta', text: event.delta.text })}\n\n`);
      }
    }

    const finalMessage = await stream.finalMessage();
    res.write(`data: ${JSON.stringify({
      type: 'done',
      usage: {
        input_tokens: finalMessage.usage.input_tokens,
        output_tokens: finalMessage.usage.output_tokens,
      }
    })}\n\n`);
  } catch (err) {
    res.write(`data: ${JSON.stringify({ type: 'error', error: err.message })}\n\n`);
  }

  res.end();
});

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', files: indexRepoFiles().length });
});

// Serve frontend for all other routes
app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

const PORT = config.port;
app.listen(PORT, () => {
  const files = indexRepoFiles();
  console.log(`Markdown QA Server running on http://localhost:${PORT}`);
  console.log(`Repository root: ${REPO_ROOT}`);
  console.log(`Indexed ${files.length} files: ${files.map(f => f.path).join(', ')}`);
});
