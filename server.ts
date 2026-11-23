import express, { Request, Response } from 'express';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';
import { GoogleGenAI } from '@google/genai';

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PORT = Number(process.env.PORT || 3000);

const ALLOWED_ROOTS = [
  'lib',
  'android',
  'test',
  '.github',
  'pubspec.yaml',
  'analysis_options.yaml',
];

interface FileEntry {
  path: string;
  sizeBytes: number;
  lines: number;
  category: 'flutter' | 'kotlin' | 'android' | 'ci' | 'test';
}

function classifyFile(relPath: string): FileEntry['category'] {
  if (relPath.startsWith('test/')) return 'test';
  if (relPath.startsWith('.github/')) return 'ci';
  if (relPath.endsWith('.kt')) return 'kotlin';
  if (relPath.startsWith('android/')) return 'android';
  return 'flutter';
}

async function collectRepoFiles(baseDir: string): Promise<FileEntry[]> {
  const entries: FileEntry[] = [];

  async function walk(relPath: string) {
    const absPath = path.resolve(baseDir, relPath);
    if (!absPath.startsWith(baseDir)) return;
    let stat;
    try {
      stat = await fs.stat(absPath);
    } catch {
      return;
    }

    if (stat.isDirectory()) {
      const children = await fs.readdir(absPath);
      for (const child of children.sort()) {
        if (child === '.gradle' || child === 'build' || child === '.dart_tool') {
          continue;
        }
        await walk(path.posix.join(relPath, child));
      }
    } else if (stat.isFile()) {
      const content = await fs.readFile(absPath, 'utf8');
      const lines = content.split('\n').length;
      entries.push({
        path: relPath,
        sizeBytes: stat.size,
        lines,
        category: classifyFile(relPath),
      });
    }
  }

  for (const root of ALLOWED_ROOTS) {
    await walk(root);
  }
  return entries;
}

function isAllowedRelativePath(relPath: string): boolean {
  const normalized = path.posix.normalize(relPath).replace(/^\/+/, '');
  if (normalized.includes('..')) return false;
  return ALLOWED_ROOTS.some(
    (root) => normalized === root || normalized.startsWith(`${root}/`),
  );
}

async function createServer() {
  const app = express();
  app.use(express.json({ limit: '1mb' }));

  app.get('/api/health', (_req: Request, res: Response) => {
    res.json({
      ok: true,
      app: 'HEY DANE',
      geminiConfigured: Boolean(process.env.GEMINI_API_KEY),
    });
  });

  app.get('/api/project/files', async (_req: Request, res: Response) => {
    try {
      const files = await collectRepoFiles(__dirname);
      res.json({ files });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unable to scan repository';
      res.status(500).json({ error: message });
    }
  });

  app.get('/api/project/file', async (req: Request, res: Response) => {
    const requestedPath = String(req.query.path ?? '');
    if (!requestedPath || !isAllowedRelativePath(requestedPath)) {
      res.status(400).json({ error: 'Invalid or restricted file path.' });
      return;
    }

    const absPath = path.resolve(__dirname, requestedPath);
    if (!absPath.startsWith(__dirname)) {
      res.status(403).json({ error: 'Path traversal rejected.' });
      return;
    }

    try {
      const content = await fs.readFile(absPath, 'utf8');
      res.json({ path: requestedPath, content });
    } catch {
      res.status(404).json({ error: 'File not found.' });
    }
  });

  app.post('/api/ai/chat', async (req: Request, res: Response) => {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      res.status(503).json({
        error:
          'GEMINI_API_KEY is not configured on the backend proxy. Add it in Settings > Secrets to stream live Gemini responses.',
      });
      return;
    }

    const prompt = typeof req.body?.prompt === 'string' ? req.body.prompt.trim() : '';
    const history = Array.isArray(req.body?.history) ? req.body.history : [];
    const attachments = Array.isArray(req.body?.attachments) ? req.body.attachments : [];
    const requestedModel =
      typeof req.body?.model === 'string' && req.body.model.trim()
        ? req.body.model.trim()
        : 'gemini-4-hydrogen';

    const allowedModels = new Set([
      'gemini-4-hydrogen',
      'gemini-3.1-flash-lite',
    ]);
    const model = allowedModels.has(requestedModel)
      ? requestedModel
      : 'gemini-4-hydrogen';

    if (!prompt) {
      res.status(400).json({ error: 'Prompt must not be empty.' });
      return;
    }

    res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
    res.setHeader('Cache-Control', 'no-cache, no-transform');
    res.setHeader('Connection', 'keep-alive');

    try {
      const ai = new GoogleGenAI({
        apiKey,
        httpOptions: {
          headers: {
            'User-Agent': 'aistudio-build',
          },
        },
      });

      const formattedHistory = history
        .slice(-8)
        .map((m: { role?: string; text?: string }) => {
          const role = m.role === 'user' ? 'User' : 'Dane';
          return `${role}: ${String(m.text ?? '')}`;
        })
        .join('\n');

      const textPrompt = formattedHistory
        ? `${formattedHistory}\nUser: ${prompt}`
        : prompt;

      const parts: Array<Record<string, unknown>> = [];
      for (const att of attachments) {
        if (
          att &&
          typeof att.mimeType === 'string' &&
          typeof att.base64Data === 'string'
        ) {
          parts.push({
            inlineData: {
              mimeType: att.mimeType,
              data: att.base64Data,
            },
          });
        }
      }
      parts.push({ text: textPrompt });

      const stream = await ai.models.generateContentStream({
        model,
        contents: { parts },
        config: {
          systemInstruction:
            'You are Dane, the personal AI assistant inside HEY DANE (Your Personal AI. Your Digital Power.). ' +
            'Be concise, helpful, accurate, and security-conscious. Never claim to have executed an Android system action unless a native execution result is explicitly confirmed; instead propose structured actions clearly.',
        },
      });

      let latestUsage: {
        promptTokens: number;
        completionTokens: number;
        totalTokens: number;
      } | null = null;

      for await (const chunk of stream) {
        const text = chunk.text ?? '';
        const meta = chunk.usageMetadata;
        if (meta) {
          latestUsage = {
            promptTokens: meta.promptTokenCount ?? 0,
            completionTokens: meta.candidatesTokenCount ?? 0,
            totalTokens: meta.totalTokenCount ?? 0,
          };
        }
        if (text) {
          res.write(`data: ${JSON.stringify({ text })}\n\n`);
        }
      }

      res.write(`data: ${JSON.stringify({ done: true, usage: latestUsage })}\n\n`);
      res.end();
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Upstream Gemini request failed.';
      res.write(`data: ${JSON.stringify({ error: message })}\n\n`);
      res.end();
    }
  });

  if (process.env.NODE_ENV !== 'production') {
    const { createServer: createViteServer } = await import('vite');
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    const distDir = path.resolve(__dirname, 'dist');
    app.use(express.static(distDir));
    app.get('*', (_req: Request, res: Response) => {
      res.sendFile(path.join(distDir, 'index.html'));
    });
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`HEY DANE proxy and companion listening on port ${PORT}`);
  });
}

createServer().catch((err) => {
  console.error('Failed to start HEY DANE server:', err);
  process.exit(1);
});
