const express = require('express');
const path = require('path');
const fs = require('fs');
const { GoogleGenAI } = require('@google/genai');

const config = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf-8'));

const REPO_ROOT = path.resolve(__dirname, config.repoRoot);
const SKIP_DIRS = new Set(['.git', 'node_modules', 'markdown-qa']);
const ALLOWED_EXTS = new Set(config.allowedFileExtensions);
const VALID_ROLES = new Set(['user', 'assistant']);
const CONTEXT_CACHE_TTL = 60_000;

// --- Restrictive file access ---

function isAllowedPath(relPath) {
  const resolved = path.resolve(REPO_ROOT, relPath);
  if (!resolved.startsWith(REPO_ROOT + path.sep) && resolved !== REPO_ROOT) return false;
  if (resolved.split(path.sep).some(seg => SKIP_DIRS.has(seg))) return false;
  return ALLOWED_EXTS.has(path.extname(resolved).toLowerCase());
}

function indexRepoFiles() {
  const files = [];
  const walk = (dir) => {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
    catch { return; }
    for (const entry of entries) {
      if (entry.name.startsWith('.') || SKIP_DIRS.has(entry.name)) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else {
        const rel = path.relative(REPO_ROOT, full);
        if (!isAllowedPath(rel)) continue;
        try {
          const { size } = fs.statSync(full);
          if (size <= config.maxFileSizeBytes) files.push({ path: rel, size });
        } catch { /* skip unreadable */ }
      }
    }
  };
  walk(REPO_ROOT);
  return files;
}

// --- Cached repo context ---

let contextCache = { text: '', files: [], timestamp: 0 };

function getRepoContext() {
  if (Date.now() - contextCache.timestamp < CONTEXT_CACHE_TTL) return contextCache;

  const files = indexRepoFiles();
  const text = files
    .map(f => {
      try { return `--- File: ${f.path} ---\n${fs.readFileSync(path.resolve(REPO_ROOT, f.path), 'utf-8')}\n`; }
      catch { return null; }
    })
    .filter(Boolean)
    .join('\n');

  contextCache = { text, files, timestamp: Date.now() };
  return contextCache;
}

// --- Lazy Gemini client ---

let ai = null;
function getAI() {
  if (ai) return ai;
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('GEMINI_API_KEY not configured. Set the GEMINI_API_KEY environment variable.');
  ai = new GoogleGenAI({ apiKey });
  return ai;
}

// --- Validation ---

function validateChatBody(body) {
  const { messages } = body;
  if (!Array.isArray(messages) || messages.length === 0) return 'messages array is required';
  for (const msg of messages) {
    if (typeof msg.content !== 'string') return 'Only text messages are allowed';
    if (!VALID_ROLES.has(msg.role)) return 'Invalid message role';
  }
  return null;
}

// --- Express app ---

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

app.get('/api/files', (_req, res) => {
  res.json({ files: getRepoContext().files });
});

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', files: getRepoContext().files.length });
});

app.post('/api/chat', async (req, res) => {
  const error = validateChatBody(req.body);
  if (error) return res.status(400).json({ error });

  let client;
  try { client = getAI(); }
  catch (err) { return res.status(500).json({ error: err.message }); }

  const { messages, sessionContext } = req.body;
  const { text: repoContext } = getRepoContext();

  const systemInstruction = `Du bist ein hilfreicher Assistent, der Fragen zu den Inhalten eines Repositories beantwortet.

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

  const geminiContents = messages.map(m => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.content }],
  }));

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  });

  try {
    const response = await client.models.generateContentStream({
      model: config.gemini.model,
      contents: geminiContents,
      config: { systemInstruction, maxOutputTokens: config.gemini.maxOutputTokens },
    });

    let totalChars = 0;
    for await (const chunk of response) {
      const text = chunk.text;
      if (text) {
        totalChars += text.length;
        res.write(`data: ${JSON.stringify({ type: 'delta', text })}\n\n`);
      }
    }

    res.write(`data: ${JSON.stringify({ type: 'done', usage: { totalChars } })}\n\n`);
  } catch (err) {
    res.write(`data: ${JSON.stringify({ type: 'error', error: err.message })}\n\n`);
  }

  res.end();
});

app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

const PORT = config.port;
app.listen(PORT, () => {
  const { files } = getRepoContext();
  console.log(`Markdown QA Server running on http://localhost:${PORT}`);
  console.log(`Repository root: ${REPO_ROOT}`);
  console.log(`Indexed ${files.length} files: ${files.map(f => f.path).join(', ')}`);
});
