// 应用状态：设置 + 会话，localStorage 持久化
export interface ApiConfig { url: string; key: string; model: string }
export interface ChatMsg {
  role: 'user' | 'ai' | 'system';
  content: string;
  reasoning?: string;
}
export interface Session {
  id: string;
  title: string;
  createdAt: string;
  pinned?: boolean;
  messages: ChatMsg[];
}

const K = {
  cfg: 'afloat.cfg',
  sessions: 'afloat.sessions',
  active: 'afloat.activeSession',
  thinking: 'afloat.thinking',
  zen: 'afloat.zen',
};

export interface AppState {
  cfg: ApiConfig;
  chatHistory: ChatMsg[];
  sessions: Session[];
  activeSessionId: string | null;
  thinking: boolean;
  zen: boolean;
  page: 'learn' | 'answer' | 'report' | 'lookup';
  // 运行时
  sending: boolean;
  abort: ((v: boolean) => void) | null;
}

function load<T>(key: string, def: T): T {
  try {
    const raw = localStorage.getItem(key);
    return raw ? { ...def, ...JSON.parse(raw) } : def;
  } catch {
    return def;
  }
}

export const state: AppState = {
  cfg: load<ApiConfig>(K.cfg, { url: '', key: '', model: '' }),
  chatHistory: [],
  sessions: JSON.parse(localStorage.getItem(K.sessions) || '[]'),
  activeSessionId: localStorage.getItem(K.active),
  thinking: localStorage.getItem(K.thinking) !== '0',
  zen: localStorage.getItem(K.zen) === '1',
  page: 'learn',
  sending: false,
  abort: null,
};

const listeners = new Set<() => void>();
export function onChange(fn: () => void) { listeners.add(fn); }
export function notify() { listeners.forEach((f) => f()); }

export function saveCfg() { localStorage.setItem(K.cfg, JSON.stringify(state.cfg)); }

export function cfgReady() { return !!(state.cfg.url && state.cfg.key && state.cfg.model); }

export function snapshotSession() {
  if (state.chatHistory.length === 0) return;
  const id = state.activeSessionId ?? Date.now().toString();
  const firstUser = state.chatHistory.find((m) => m.role === 'user' && m.content.trim());
  const title = (firstUser?.content || '(空)').replace(/\n/g, ' ').slice(0, 40);
  const existing = state.sessions.findIndex((s) => s.id === id);
  const snap: Session = {
    id,
    title,
    createdAt: existing >= 0 ? state.sessions[existing].createdAt : new Date().toISOString(),
    pinned: existing >= 0 ? state.sessions[existing].pinned : false,
    messages: state.chatHistory.map((m) => ({ role: m.role, content: m.content })),
  };
  if (existing >= 0) state.sessions[existing] = snap;
  else state.sessions.unshift(snap);
  state.sessions = state.sessions.slice(0, 50);
  state.activeSessionId = id;
  localStorage.setItem(K.sessions, JSON.stringify(state.sessions));
  localStorage.setItem(K.active, id);
}

export function loadSession(id: string) {
  const s = state.sessions.find((x) => x.id === id);
  if (!s) return;
  state.chatHistory = s.messages.map((m) => ({ role: m.role, content: m.content }));
  state.activeSessionId = id;
  localStorage.setItem(K.active, id);
  notify();
}

export function newSession() {
  snapshotSession();
  state.chatHistory = [];
  state.activeSessionId = null;
  localStorage.removeItem(K.active);
  notify();
}

export function deleteSession(id: string) {
  const i = state.sessions.findIndex((s) => s.id === id);
  if (i >= 0) {
    state.sessions.splice(i, 1);
    localStorage.setItem(K.sessions, JSON.stringify(state.sessions));
  }
  if (state.activeSessionId === id) state.activeSessionId = null;
  notify();
}

export function togglePin(id: string) {
  const s = state.sessions.find((x) => x.id === id);
  if (!s) return;
  if (!s.pinned && state.sessions.filter((x) => x.pinned).length >= 10) return;
  s.pinned = !s.pinned;
  localStorage.setItem(K.sessions, JSON.stringify(state.sessions));
  notify();
}

export function setThinking(v: boolean) {
  state.thinking = v;
  localStorage.setItem(K.thinking, v ? '1' : '0');
}

export function setZen(v: boolean) {
  state.zen = v;
  localStorage.setItem(K.zen, v ? '1' : '0');
  document.body.classList.toggle('zen', v);
  notify();
}
