import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  ArrowUp,
  Check,
  Copy,
  FileCode2,
  FolderTree,
  Mic,
  MicOff,
  Moon,
  ShieldCheck,
  Square,
  Sun,
} from 'lucide-react';
import { HolographicOrb, OrbStatus } from './components/HolographicOrb';

type SectionId = 'assistant' | 'permissions' | 'architecture' | 'files';

interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  text: string;
  sourcePrompt?: string;
  tokens?: number;
  error?: boolean;
}

interface RepoFileEntry {
  path: string;
  sizeBytes: number;
  lines: number;
  category: 'flutter' | 'kotlin' | 'android' | 'ci' | 'test';
}

const PERMISSION_BLUEPRINT = [
  {
    name: 'RECORD_AUDIO',
    category: 'Voice',
    purpose: 'Captures speech commands only when activated or armed with visible privacy indicator.',
    mechanism: 'Android Runtime Permission + Foreground Microphone Service',
  },
  {
    name: 'POST_NOTIFICATIONS',
    category: 'Voice & Alerts',
    purpose: 'Shows persistent foreground listening notice and alarm/reminder confirmations.',
    mechanism: 'Android 13+ Runtime Notification Permission',
  },
  {
    name: 'AccessibilityService',
    category: 'Automation',
    purpose: 'Executes user-authorized UI navigation steps. Never bypasses lock-screen or auth.',
    mechanism: 'Explicit manual toggle in Android Accessibility Settings',
  },
  {
    name: 'NotificationListenerService',
    category: 'Context',
    purpose: 'Reads incoming notifications only when explicitly enabled by the user.',
    mechanism: 'Explicit manual toggle in Android Notification Access Settings',
  },
  {
    name: 'SYSTEM_ALERT_WINDOW',
    category: 'Overlay',
    purpose: 'Displays compact confirmation sheet over active apps during voice handoff.',
    mechanism: 'Special App Access (Display Over Other Apps)',
  },
  {
    name: 'SCHEDULE_EXACT_ALARM',
    category: 'Alarms',
    purpose: 'Creates exact alarms and timers using AlarmClock intents and exact alarm APIs.',
    mechanism: 'Special Alarm & Reminder Access',
  },
];

const PHASE_ROADMAP = [
  { phase: 'Phase 1', title: 'Repository, Identity, Holographic UI & Navigation', status: 'Implemented' },
  { phase: 'Phase 2', title: 'Groq, Gemini & OpenRouter Provider Architecture', status: 'Implemented' },
  { phase: 'Phase 3', title: 'Speech Recognition, TTS & Wake-Word Engine', status: 'Implemented' },
  { phase: 'Phase 4', title: 'Kotlin Permission Center & Verification', status: 'Implemented' },
  { phase: 'Phase 5', title: 'Accessibility, Notifications & Device Automation', status: 'Implemented' },
  { phase: 'Phase 6', title: 'Calls, Messaging, Files (SAF) & Alarms', status: 'Implemented' },
  { phase: 'Phase 7', title: 'Locked-Screen Mode, Encrypted Memory & Privacy', status: 'Implemented' },
  { phase: 'Phase 8', title: 'Full Automated Tests & CI APK/AAB Releases', status: 'Implemented & CI Ready' },
];

export default function App() {
  const [darkMode, setDarkMode] = useState(true);
  const [activeSection, setActiveSection] = useState<SectionId>('assistant');
  const [orbStatus, setOrbStatus] = useState<OrbStatus>('idle');
  const [selectedModel, setSelectedModel] = useState<string>('gemini-4-hydrogen');
  const [sessionTokens, setSessionTokens] = useState<number>(0);
  const [prompt, setPrompt] = useState('');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [geminiConfigured, setGeminiConfigured] = useState<boolean | null>(null);
  const [repoFiles, setRepoFiles] = useState<RepoFileEntry[]>([]);
  const [fileFilter, setFileFilter] = useState<string>('all');
  const [selectedFilePath, setSelectedFilePath] = useState<string>('lib/main.dart');
  const [selectedFileContent, setSelectedFileContent] = useState<string>('');
  const [loadingFile, setLoadingFile] = useState<boolean>(false);

  const abortRef = useRef<AbortController | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    const root = document.documentElement;
    if (darkMode) {
      root.classList.add('dark');
    } else {
      root.classList.remove('dark');
    }
  }, [darkMode]);

  useEffect(() => {
    fetch('/api/health')
      .then((res) => res.json())
      .then((data) => {
        setGeminiConfigured(Boolean(data.geminiConfigured));
      })
      .catch(() => {
        setGeminiConfigured(false);
      });

    fetch('/api/project/files')
      .then((res) => res.json())
      .then((data) => {
        if (Array.isArray(data.files)) {
          setRepoFiles(data.files);
        }
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    if (!selectedFilePath) return;
    setLoadingFile(true);
    fetch(`/api/project/file?path=${encodeURIComponent(selectedFilePath)}`)
      .then((res) => res.json())
      .then((data) => {
        setSelectedFileContent(typeof data.content === 'string' ? data.content : '');
      })
      .catch(() => {
        setSelectedFileContent('Unable to load file preview.');
      })
      .finally(() => {
        setLoadingFile(false);
      });
  }, [selectedFilePath]);

  const filteredFiles = useMemo(() => {
    if (fileFilter === 'all') return repoFiles;
    return repoFiles.filter((f) => f.category === fileFilter);
  }, [repoFiles, fileFilter]);

  const totalLines = useMemo(
    () => repoFiles.reduce((acc, f) => acc + f.lines, 0),
    [repoFiles],
  );

  async function handleSendPrompt(overrideText?: string) {
    const text = (overrideText ?? prompt).trim();
    if (!text || orbStatus === 'thinking') return;
    if (!overrideText) setPrompt('');

    const userMsg: ChatMessage = {
      id: crypto.randomUUID(),
      role: 'user',
      text,
    };
    const assistantId = crypto.randomUUID();
    const initialAssistantMsg: ChatMessage = {
      id: assistantId,
      role: 'assistant',
      text: '',
      sourcePrompt: text,
    };

    const nextHistory = [...messages.filter((m) => !m.error), userMsg];
    setMessages([...messages, userMsg, initialAssistantMsg]);
    setOrbStatus('thinking');

    const controller = new AbortController();
    abortRef.current = controller;

    try {
      const response = await fetch('/api/ai/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          prompt: text,
          model: selectedModel,
          history: nextHistory.slice(0, -1).map((m) => ({ role: m.role, text: m.text })),
        }),
        signal: controller.signal,
      });

      if (!response.ok) {
        const errPayload = await response.json().catch(() => ({}));
        throw new Error(errPayload.error || `Request failed (${response.status})`);
      }

      const reader = response.body?.getReader();
      if (!reader) {
        throw new Error('Streaming response unavailable.');
      }

      const decoder = new TextDecoder();
      let buffer = '';
      let accumulated = '';
      setOrbStatus('speaking');

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n\n');
        buffer = lines.pop() ?? '';

        for (const chunk of lines) {
          if (!chunk.startsWith('data: ')) continue;
          const payload = JSON.parse(chunk.slice(6));
          if (payload.error) {
            throw new Error(payload.error);
          }
          if (payload.text) {
            accumulated += payload.text;
            setMessages((prev) =>
              prev.map((m) => (m.id === assistantId ? { ...m, text: accumulated } : m)),
            );
          }
          if (payload.usage?.totalTokens) {
            const turnTokens = Number(payload.usage.totalTokens);
            setSessionTokens((prev) => prev + turnTokens);
            setMessages((prev) =>
              prev.map((m) => (m.id === assistantId ? { ...m, tokens: turnTokens } : m)),
            );
          }
        }
      }
      setOrbStatus('idle');
    } catch (error) {
      if ((error as Error).name === 'AbortError') {
        setOrbStatus('idle');
        return;
      }
      const message =
        error instanceof Error ? error.message : 'Unable to reach HEY DANE proxy.';
      setMessages((prev) =>
        prev.map((m) =>
          m.id === assistantId ? { ...m, text: message, error: true } : m,
        ),
      );
      setOrbStatus('idle');
    } finally {
      abortRef.current = null;
    }
  }

  function handleStopGeneration() {
    abortRef.current?.abort();
    setOrbStatus('idle');
  }

  function handleCopy(id: string, text: string) {
    navigator.clipboard.writeText(text).then(() => {
      setCopiedId(id);
      setTimeout(() => setCopiedId(null), 1800);
    });
  }

  function toggleVoicePreview() {
    if (orbStatus === 'listening') {
      setOrbStatus('idle');
    } else {
      setOrbStatus('listening');
      inputRef.current?.focus();
    }
  }

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900 dark:bg-[#050814] dark:text-[#F0F6FF] transition-colors duration-200">
      {/* Three-Zone Top Bar Contract */}
      <header className="sticky top-0 z-30 border-b border-slate-200/80 dark:border-cyan-400/15 bg-white/85 dark:bg-[#050814]/85 backdrop-blur-md">
        <div className="max-w-7xl mx-auto px-6 h-16 flex items-center justify-between gap-8">
          <a
            href="#top"
            onClick={(e) => {
              e.preventDefault();
              setActiveSection('assistant');
            }}
            className="font-display text-lg font-bold tracking-wider whitespace-nowrap shrink-0 text-slate-900 dark:text-white"
          >
            HEY DANE
          </a>

          <nav className="hidden md:flex items-center gap-6 text-sm font-medium text-slate-600 dark:text-slate-300">
            {(
              [
                ['assistant', 'Assistant'],
                ['permissions', 'Permissions'],
                ['architecture', 'Architecture'],
                ['files', 'Source Files'],
              ] as const
            ).map(([id, label]) => (
              <button
                key={id}
                type="button"
                onClick={() => setActiveSection(id)}
                className={`whitespace-nowrap shrink-0 py-1 border-b-2 transition-colors cursor-pointer ${
                  activeSection === id
                    ? 'border-cyan-500 text-slate-900 dark:text-cyan-300'
                    : 'border-transparent hover:text-slate-900 dark:hover:text-white'
                }`}
              >
                {label}
              </button>
            ))}
          </nav>

          <div className="flex items-center gap-3 shrink-0">
            <button
              type="button"
              onClick={() => setDarkMode((prev) => !prev)}
              aria-label="Toggle color theme"
              className="min-h-[40px] min-w-[40px] inline-flex items-center justify-center rounded-xl border border-slate-200 dark:border-cyan-400/20 text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-[#101836] transition-colors cursor-pointer"
            >
              {darkMode ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
            </button>
            <button
              type="button"
              onClick={() => {
                setActiveSection('assistant');
                inputRef.current?.focus();
              }}
              className="px-4 py-2 text-sm font-semibold rounded-xl bg-blue-600 text-white hover:bg-blue-500 transition-colors whitespace-nowrap shrink-0 cursor-pointer"
            >
              Ask Dane
            </button>
          </div>
        </div>

        {/* Mobile navigation row */}
        <div className="md:hidden border-t border-slate-200/70 dark:border-cyan-400/10 px-4 py-2 flex items-center gap-2 overflow-x-auto">
          {(
            [
              ['assistant', 'Assistant'],
              ['permissions', 'Permissions'],
              ['architecture', 'Architecture'],
              ['files', 'Source Files'],
            ] as const
          ).map(([id, label]) => (
            <button
              key={id}
              type="button"
              onClick={() => setActiveSection(id)}
              className={`px-3 py-1.5 text-xs font-medium rounded-lg whitespace-nowrap shrink-0 cursor-pointer ${
                activeSection === id
                  ? 'bg-cyan-500/15 text-cyan-600 dark:text-cyan-300'
                  : 'text-slate-600 dark:text-slate-300'
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-6 py-8">
        {activeSection === 'assistant' && (
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
            {/* Left column: Holographic Core & Identity */}
            <section className="lg:col-span-5 rounded-2xl border border-slate-200 dark:border-cyan-400/20 bg-white dark:bg-[#0A1026]/90 p-6 flex flex-col items-center text-center">
              <HolographicOrb
                status={orbStatus}
                size={204}
                onActivate={toggleVoicePreview}
              />

              <h1 className="mt-4 font-display text-2xl font-bold tracking-wide">
                Your Personal AI. Your Digital Power.
              </h1>
              <p className="mt-2 text-sm text-slate-600 dark:text-slate-300 max-w-md">
                Phase 1–8 Android Flutter &amp; Kotlin codebase paired with the live Gemini backend proxy.
              </p>

              <div className="mt-4 flex flex-wrap items-center justify-center gap-2 text-xs text-slate-500 dark:text-slate-400">
                <span>State: {orbStatus}</span>
                <span aria-hidden="true">·</span>
                <span>
                  Proxy: {geminiConfigured === null ? 'Checking' : geminiConfigured ? 'Gemini Ready' : 'Key Not Set'}
                </span>
                <span aria-hidden="true">·</span>
                <span className="font-mono tabular-nums">{repoFiles.length} files</span>
                {sessionTokens > 0 && (
                  <>
                    <span aria-hidden="true">·</span>
                    <span className="font-mono tabular-nums">{sessionTokens} tokens</span>
                  </>
                )}
              </div>

              <div className="mt-6 flex flex-wrap items-center justify-center gap-3">
                <button
                  type="button"
                  onClick={toggleVoicePreview}
                  className="min-h-[44px] px-4 py-2 rounded-xl border border-slate-200 dark:border-cyan-400/25 bg-slate-100 dark:bg-[#101836] text-sm font-medium inline-flex items-center gap-2 hover:border-cyan-400 transition-colors whitespace-nowrap shrink-0 cursor-pointer"
                >
                  {orbStatus === 'listening' ? (
                    <>
                      <MicOff className="w-4 h-4 text-cyan-400" />
                      Stop Listening
                    </>
                  ) : (
                    <>
                      <Mic className="w-4 h-4 text-cyan-400" />
                      Wake Preview
                    </>
                  )}
                </button>
                <button
                  type="button"
                  onClick={() => setActiveSection('files')}
                  className="min-h-[44px] px-4 py-2 rounded-xl border border-slate-200 dark:border-cyan-400/20 text-sm font-medium inline-flex items-center gap-2 hover:bg-slate-100 dark:hover:bg-[#101836] transition-colors whitespace-nowrap shrink-0 cursor-pointer"
                >
                  <FolderTree className="w-4 h-4" />
                  Inspect Codebase
                </button>
              </div>
            </section>

            {/* Right column: Live Streaming Assistant Console */}
            <section className="lg:col-span-7 rounded-2xl border border-slate-200 dark:border-cyan-400/20 bg-white dark:bg-[#0A1026]/90 p-6 flex flex-col min-h-[520px]">
              <div className="flex flex-wrap items-center justify-between gap-4 pb-4 border-b border-slate-200 dark:border-cyan-400/15">
                <div>
                  <h2 className="font-display text-lg font-semibold">
                    Dane Proxy Conversation
                  </h2>
                  <p className="text-xs text-slate-500 dark:text-slate-400">
                    Server-side Gemini streaming · Model: {selectedModel}
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <select
                    aria-label="Select Gemini model"
                    value={selectedModel}
                    onChange={(e) => setSelectedModel(e.target.value)}
                    className="px-3 py-1.5 text-xs font-mono rounded-lg border border-slate-200 dark:border-cyan-400/20 bg-slate-50 dark:bg-[#101836] cursor-pointer"
                  >
                    <option value="gemini-4-hydrogen">gemini-4-hydrogen</option>
                    <option value="gemini-3.1-flash-lite">gemini-3.1-flash-lite</option>
                  </select>
                  {messages.length > 0 && (
                    <button
                      type="button"
                      onClick={() => setMessages([])}
                      className="px-3 py-1.5 text-xs font-medium rounded-lg border border-slate-200 dark:border-slate-700 hover:bg-slate-100 dark:hover:bg-[#101836] cursor-pointer"
                    >
                      Clear
                    </button>
                  )}
                </div>
              </div>

              <div className="flex-1 py-4 space-y-4 overflow-y-auto max-h-[380px]">
                {messages.length === 0 ? (
                  <div className="py-10 text-center space-y-4">
                    <p className="text-sm text-slate-600 dark:text-slate-300 max-w-md mx-auto">
                      Send a prompt to test the HEY DANE secure backend proxy or inspect the full Phase 1–8 Flutter and Kotlin architecture.
                    </p>
                    <div className="flex flex-wrap justify-center gap-2">
                      {[
                        'Propose an alarm action for 6:00 AM',
                        'Explain Android AccessibilityService boundaries',
                        'Summarize Phase 2 AI provider routing',
                      ].map((sample) => (
                        <button
                          key={sample}
                          type="button"
                          onClick={() => handleSendPrompt(sample)}
                          className="px-3 py-2 text-xs font-medium rounded-xl border border-slate-200 dark:border-cyan-400/20 hover:border-cyan-400 transition-colors cursor-pointer"
                        >
                          {sample}
                        </button>
                      ))}
                    </div>
                  </div>
                ) : (
                  messages.map((msg) => (
                    <div
                      key={msg.id}
                      className={`p-4 rounded-xl border ${
                        msg.role === 'user'
                          ? 'ml-8 border-cyan-500/30 bg-cyan-500/5'
                          : msg.error
                            ? 'mr-8 border-red-500/40 bg-red-500/5 text-red-600 dark:text-red-300'
                            : 'mr-8 border-slate-200 dark:border-slate-700/80 bg-slate-50 dark:bg-[#101836]/75'
                      }`}
                    >
                      <div className="flex items-center justify-between gap-4 mb-1.5">
                        <span className="text-xs font-semibold text-slate-500 dark:text-cyan-300">
                          {msg.role === 'user' ? 'You' : 'Dane'}
                          {msg.tokens ? ` · ${msg.tokens} tokens` : ''}
                        </span>
                        {msg.text && (
                          <button
                            type="button"
                            onClick={() => handleCopy(msg.id, msg.text)}
                            aria-label="Copy message"
                            className="p-1 text-slate-400 hover:text-slate-700 dark:hover:text-white cursor-pointer"
                          >
                            {copiedId === msg.id ? (
                              <Check className="w-3.5 h-3.5 text-emerald-500" />
                            ) : (
                              <Copy className="w-3.5 h-3.5" />
                            )}
                          </button>
                        )}
                      </div>
                      <p className="text-sm leading-relaxed whitespace-pre-wrap">
                        {msg.text || (orbStatus === 'thinking' ? 'Thinking...' : '')}
                      </p>
                      {msg.error && msg.sourcePrompt && (
                        <button
                          type="button"
                          onClick={() => handleSendPrompt(msg.sourcePrompt)}
                          className="mt-2 text-xs font-medium underline cursor-pointer"
                        >
                          Retry prompt
                        </button>
                      )}
                    </div>
                  ))
                )}
              </div>

              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  handleSendPrompt();
                }}
                className="pt-4 border-t border-slate-200 dark:border-cyan-400/15 flex items-center gap-3"
              >
                <input
                  ref={inputRef}
                  type="text"
                  value={prompt}
                  onChange={(e) => setPrompt(e.target.value)}
                  placeholder="Ask Dane anything..."
                  className="flex-1 min-h-[44px] px-4 rounded-xl border border-slate-200 dark:border-cyan-400/20 bg-slate-50 dark:bg-[#101836] text-sm focus:outline-none focus:border-cyan-400"
                />
                {orbStatus === 'thinking' || orbStatus === 'speaking' ? (
                  <button
                    type="button"
                    onClick={handleStopGeneration}
                    className="min-h-[44px] px-4 rounded-xl bg-red-600 text-white text-sm font-medium inline-flex items-center gap-2 hover:bg-red-500 cursor-pointer"
                  >
                    <Square className="w-4 h-4" />
                    Stop
                  </button>
                ) : (
                  <button
                    type="submit"
                    disabled={!prompt.trim()}
                    aria-label="Send prompt"
                    className="min-h-[44px] min-w-[44px] inline-flex items-center justify-center rounded-xl bg-blue-600 text-white hover:bg-blue-500 disabled:opacity-40 cursor-pointer"
                  >
                    <ArrowUp className="w-4 h-4" />
                  </button>
                )}
              </form>
            </section>
          </div>
        )}

        {activeSection === 'permissions' && (
          <section className="space-y-6">
            <div className="max-w-2xl">
              <h1 className="font-display text-2xl font-bold">
                Android Permission Center Blueprint
              </h1>
              <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
                Implemented in Flutter (`PermissionsScreen`) with real `permission_handler` status verification and native Kotlin Settings intents in `MainActivity.kt`.
              </p>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
              {PERMISSION_BLUEPRINT.map((perm) => (
                <div
                  key={perm.name}
                  className="rounded-2xl border border-slate-200 dark:border-cyan-400/20 bg-white dark:bg-[#0A1026]/90 p-5 space-y-2"
                >
                  <div className="flex items-center justify-between gap-2 text-xs text-slate-500 dark:text-cyan-300">
                    <span>{perm.category}</span>
                    <ShieldCheck className="w-4 h-4" />
                  </div>
                  <h2 className="font-mono text-sm font-semibold">{perm.name}</h2>
                  <p className="text-sm text-slate-600 dark:text-slate-300">{perm.purpose}</p>
                  <p className="text-xs text-slate-500 dark:text-slate-400 pt-1">
                    {perm.mechanism}
                  </p>
                </div>
              ))}
            </div>
          </section>
        )}

        {activeSection === 'architecture' && (
          <section className="space-y-6">
            <div className="max-w-2xl">
              <h1 className="font-display text-2xl font-bold">
                Phased Engineering Roadmap
              </h1>
              <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
                All 8 engineering phases are implemented across Flutter Material 3, native Android Kotlin bridges (`MainActivity.kt`, `DaneAccessibilityService`, `DaneNotificationListenerService`, `DaneForegroundService`, `FileAutomationManager`), encrypted storage, automated tests, and the GitHub Actions APK/AAB workflow.
              </p>
            </div>
            <div className="rounded-2xl border border-slate-200 dark:border-cyan-400/20 bg-white dark:bg-[#0A1026]/90 overflow-hidden">
              <table className="w-full text-left text-sm">
                <thead className="border-b border-slate-200 dark:border-cyan-400/15 text-xs text-slate-500 dark:text-slate-400">
                  <tr>
                    <th className="py-3.5 px-5 font-medium">Phase</th>
                    <th className="py-3.5 px-5 font-medium">Scope</th>
                    <th className="py-3.5 px-5 font-medium text-right">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-200/70 dark:divide-slate-800">
                  {PHASE_ROADMAP.map((row) => (
                    <tr key={row.phase}>
                      <td className="py-3.5 px-5 font-mono text-xs font-semibold text-cyan-600 dark:text-cyan-300 whitespace-nowrap">
                        {row.phase}
                      </td>
                      <td className="py-3.5 px-5">{row.title}</td>
                      <td className="py-3.5 px-5 text-right text-xs text-slate-500 dark:text-slate-300 whitespace-nowrap">
                        {row.status}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        )}

        {activeSection === 'files' && (
          <section className="space-y-6">
            <div className="flex flex-wrap items-end justify-between gap-4">
              <div>
                <h1 className="font-display text-2xl font-bold">
                  HEY DANE Flutter &amp; Kotlin Codebase
                </h1>
                <p className="mt-1 text-sm text-slate-600 dark:text-slate-300 font-mono tabular-nums">
                  {repoFiles.length} files · {totalLines} lines indexed directly from repository
                </p>
              </div>
              <div className="flex items-center gap-1 p-1 rounded-xl bg-slate-200/70 dark:bg-[#101836]">
                {(['all', 'flutter', 'kotlin', 'android', 'ci', 'test'] as const).map((cat) => (
                  <button
                    key={cat}
                    type="button"
                    onClick={() => setFileFilter(cat)}
                    className={`px-3 py-1.5 text-xs font-medium rounded-lg capitalize cursor-pointer ${
                      fileFilter === cat
                        ? 'bg-white dark:bg-[#050814] text-slate-900 dark:text-cyan-300 shadow-sm'
                        : 'text-slate-600 dark:text-slate-300'
                    }`}
                  >
                    {cat}
                  </button>
                ))}
              </div>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
              <div className="lg:col-span-5 rounded-2xl border border-slate-200 dark:border-cyan-400/20 bg-white dark:bg-[#0A1026]/90 max-h-[540px] overflow-y-auto divide-y divide-slate-200/70 dark:divide-slate-800">
                {filteredFiles.map((file) => (
                  <button
                    key={file.path}
                    type="button"
                    onClick={() => setSelectedFilePath(file.path)}
                    className={`w-full text-left px-4 py-3 flex items-center justify-between gap-3 hover:bg-slate-50 dark:hover:bg-[#101836] transition-colors cursor-pointer ${
                      selectedFilePath === file.path
                        ? 'bg-cyan-500/10 text-cyan-700 dark:text-cyan-300'
                        : ''
                    }`}
                  >
                    <span className="inline-flex items-center gap-2 min-w-0">
                      <FileCode2 className="w-4 h-4 shrink-0" />
                      <span className="font-mono text-xs truncate">{file.path}</span>
                    </span>
                    <span className="font-mono text-xs tabular-nums text-slate-500 shrink-0">
                      {file.lines}L
                    </span>
                  </button>
                ))}
              </div>

              <div className="lg:col-span-7 rounded-2xl border border-slate-200 dark:border-cyan-400/20 bg-white dark:bg-[#0A1026]/90 overflow-hidden">
                <div className="px-4 py-3 border-b border-slate-200 dark:border-cyan-400/15 flex items-center justify-between">
                  <span className="font-mono text-xs font-semibold truncate">
                    {selectedFilePath}
                  </span>
                </div>
                <pre className="p-4 text-xs font-mono leading-relaxed overflow-auto max-h-[490px] text-slate-800 dark:text-slate-200">
                  {loadingFile ? 'Loading file...' : selectedFileContent}
                </pre>
              </div>
            </div>
          </section>
        )}
      </main>
    </div>
  );
}
