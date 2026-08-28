// AI 对话面板：头部/消息流/输入栏/流式请求/模型选择/历史会话
import { state, notify, cfgReady, snapshotSession, setThinking, type ChatMsg } from './store';
import { renderMarkdown, bindCodeActions } from './md';

const $ = <T extends HTMLElement>(sel: string, root: ParentNode = document): T => root.querySelector(sel) as T;

export interface Profile { name: string; url: string; key: string; model: string }
export function profiles(): Profile[] {
  try { return JSON.parse(localStorage.getItem('afloat.profiles') || '[]'); } catch { return []; }
}
export function saveProfiles(p: Profile[]) { localStorage.setItem('afloat.profiles', JSON.stringify(p)); }
export function activeProfile(): Profile | null {
  const ps = profiles();
  if (!state.cfg.url || !state.cfg.model) return ps[0] ?? null;
  return ps.find((p) => p.url === state.cfg.url && p.model === state.cfg.model) ?? null;
}

function brandIcon(model: string): string {
  const l = model.toLowerCase();
  const icon = (f: string) => `<img src="/icons/${f}.svg" width="22" height="22" alt="">`;
  if (l.includes('glm') || l.includes('zhipu') || l.includes('chatglm')) return icon('zhipu');
  if (l.includes('deepseek')) return icon('deepseek');
  if (l.includes('kimi') || l.includes('moonshot')) return icon('kimi');
  if (l.includes('qwen') || l.includes('通义')) return icon('qwen');
  if (l.includes('doubao') || l.includes('豆包')) return icon('doubao');
  if (l.includes('gpt') || l.includes('openai')) return icon('openai');
  return `<div style="width:22px;height:22px;border-radius:50%;background:linear-gradient(135deg,#7c3aed,#8b5cf6);display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800">${esc2(model[0] || 'A').toUpperCase()}</div>`;
}
function esc2(s: string) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;'); }

let abortCtrl: AbortController | null = null;

export function renderChatPanel(root: HTMLElement) {
  root.innerHTML = `
  <div class="chat-panel" id="chatPanel">
    <div class="chat-shell" style="display:flex;flex-direction:column;flex:1;min-height:0">
      <div class="chat-head">
        <span id="chatLogo"></span>
        <span class="model-name" id="modelName"></span>
        <button class="icon-btn" id="btnHistory" title="历史对话">🕘</button>
        <button class="icon-btn" id="btnZen" title="专注全屏">⛶</button>
        <button class="icon-btn" id="btnNew" title="清空对话">⟳</button>
        <button class="icon-btn" id="btnCfg" title="配置">⚙</button>
      </div>
      <div class="chat-list" id="chatList"></div>
      <div class="chat-input">
        <div class="input-shell">
          <textarea id="chatTa" placeholder="今天帮你做些什么？@ 引用文件"></textarea>
          <div class="input-tools">
            <button class="tool-btn" id="btnPlus" title="工具">＋</button>
            <span class="gap"></span>
            <button class="text-btn" id="btnModel"><span id="modelIco"></span><span id="modelLbl"></span> ▾</button>
            <div class="ctx-ring" id="ctxRing" title="上下文占用">
              <svg viewBox="0 0 26 26"><circle cx="13" cy="13" r="10.5" fill="none" stroke="rgba(154,163,175,0.28)" stroke-width="2.6"></circle><circle id="ringArc" cx="13" cy="13" r="10.5" fill="none" stroke="#9aa3af" stroke-width="2.6" stroke-linecap="round" stroke-dasharray="0 66" transform="rotate(-90 13 13)"></circle></svg>
              <span class="pct" id="ringPct">0%</span>
            </div>
            <button class="send-btn" id="btnSend">↑</button>
          </div>
        </div>
      </div>
    </div>
  </div>`;

  refreshHead(root);
  renderMessages(root);
  bindChatEvents(root);
}

export function refreshHead(root: HTMLElement) {
  const p = activeProfile();
  const model = state.cfg.model || '未配置';
  const logo = $('#chatLogo', root);
  logo.innerHTML = cfgReady() ? brandIcon(model) : brandIcon('A');
  $('#modelName', root).textContent = model;
  const mi = $('#modelIco', root);
  if (mi) mi.innerHTML = brandIcon(model);
  const ml = $('#modelLbl', root);
  if (ml) ml.textContent = model;
  const ring = $('#ringArc', root);
  if (ring) {
    const chars = state.chatHistory.reduce((a, m) => a + m.content.length, 0) * 0.6;
    const ratio = Math.min(1, chars / (state.thinking ? 800000 : 160000));
    ring.setAttribute('stroke-dasharray', `${(ratio * 66).toFixed(1)} 66`);
    $('#ringPct', root).textContent = `${Math.round(ratio * 100)}%`;
  }
  const zen = $('#btnZen', root);
  if (zen) zen.style.color = state.zen ? 'var(--brand)' : '';
}

function renderMessages(root: HTMLElement) {
  const list = $('#chatList', root);
  if (!cfgReady()) {
    list.innerHTML = `<div style="padding:30px 10px;text-align:center;color:var(--text-3);font-size:13px">尚未配置 AI 模型<br>点击右上角 ⚙ 填入 API 地址 / Key / 模型</div>`;
    return;
  }
  if (state.chatHistory.length === 0) {
    list.innerHTML = `<div class="msg msg-ai"><div class="msg-meta">${brandIcon(state.cfg.model)} <b>${esc2(state.cfg.model)}</b></div><div class="bubble">Hi! 我是你的 AI 备考助手<br>有问题可以随时问我</div></div>`;
    return;
  }
  list.innerHTML = state.chatHistory.map((m, i) => bubbleHtml(m, i)).join('');
  list.scrollTop = list.scrollHeight;
  bindCodeActions(list);
  bindUserActions(list);
}

function bubbleHtml(m: ChatMsg, i: number): string {
  if (m.role === 'user') {
    return `<div class="msg msg-user" data-idx="${i}"><div class="bubble">${esc2(m.content)}</div></div>`;
  }
  const head = `<div class="msg-meta">${brandIcon(state.cfg.model)} <b>${esc2(state.cfg.model)}</b></div>`;
  return `<div class="msg msg-ai" data-idx="${i}">${head}<div class="bubble">${m.content ? renderMarkdown(m.content) : '<span style="color:var(--text-3)">…</span>'}</div>`
    + (m.content ? `<div class="msg-actions"><button data-copy="${i}" title="复制">⧉</button></div>` : '') + `</div>`;
}

function bindUserActions(list: HTMLElement) {
  list.querySelectorAll('.msg-user').forEach((el0) => { const el = el0 as HTMLElement;
    el.addEventListener('mouseenter', () => {
      if (el.querySelector('.msg-actions')) return;
      const idx = Number((el as HTMLElement).dataset.idx);
      const row = document.createElement('div');
      row.className = 'msg-actions';
      row.innerHTML = `<button data-copy="${idx}" title="复制">⧉</button><button data-edit="${idx}" title="编辑（截断此后对话）">✎</button>`;
      el.appendChild(row);
    });
  });
  list.querySelectorAll('button[data-copy]').forEach((b0) => { const b = b0 as HTMLElement;
    b.addEventListener('click', () => {
      const i = Number(b.getAttribute('data-copy'));
      navigator.clipboard.writeText(state.chatHistory[i].content);
    });
  });
  list.querySelectorAll('button[data-edit]').forEach((b0) => { const b = b0 as HTMLElement;
    b.addEventListener('click', () => {
      const i = Number(b.getAttribute('data-edit'));
      const ta = document.getElementById('chatTa') as HTMLTextAreaElement;
      ta.value = state.chatHistory[i].content;
      state.chatHistory.splice(i);
      if (state.sending) return;
      notify();
    });
  });
}

function bindChatEvents(root: HTMLElement) {
  const ta = $('#chatTa', root) as HTMLTextAreaElement;
  $('#btnSend', root).addEventListener('click', () => send(ta));
  ta.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(ta); }
  });
  $('#btnCfg', root).addEventListener('click', () => dispatchEvent(new CustomEvent('afloat:open-settings')));
  $('#btnNew', root).addEventListener('click', () => { import('./store').then((m) => { m.newSession(); notify(); }); });
  $('#btnZen', root).addEventListener('click', () => { import('./store').then((m) => m.setZen(!m.state.zen)); });
  $('#btnHistory', root).addEventListener('click', () => openHistoryDrawer());
  $('#btnModel', root).addEventListener('click', () => openModelSelector(root));
  $('#ctxRing', root).addEventListener('click', () => {
    const chars = state.chatHistory.reduce((a, m) => a + m.content.length, 0) * 0.6;
    alert(`上下文占用：约 ${(chars / 1000).toFixed(1)}K / ${state.thinking ? '1000.0K（Max 模式）' : '200.0K'}`);
  });
  $('#btnPlus', root).addEventListener('click', () => {
    alert('网页版 v1：工具面板（文件上传 / 技能 / 连接器）规划中');
  });
}

async function send(ta: HTMLTextAreaElement) {
  const text = ta.value.trim();
  if ((!text && !state.sending) || !cfgReady()) return;
  if (state.sending) { abortCtrl?.abort(); return; }
  ta.value = '';
  state.chatHistory.push({ role: 'user', content: text });
  const placeholder: ChatMsg = { role: 'ai', content: '' };
  state.chatHistory.push(placeholder);
  state.sending = true;
  snapshotSession();
  renderAll();

  abortCtrl = new AbortController();
  const history = state.chatHistory.slice(0, -1).slice(-16).map((m) => ({ role: m.role === 'ai' ? 'assistant' : 'user', content: m.content }));
  const sys = '你是一个专业的英语学习助手（AFloat 备考助手），可以回答任何关于英语的问题（语法、词汇、翻译、写作、阅读理解等），用简体中文回答，代码块使用 markdown。';
  try {
    const resp = await fetch(state.cfg.url.replace(/\/$/, '') + '/chat/completions', {
      method: 'POST',
      signal: abortCtrl.signal,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${state.cfg.key}` },
      body: JSON.stringify({
        model: state.cfg.model,
        messages: [{ role: 'system', content: sys }, ...history],
        stream: true,
        ...(state.thinking ? {} : {}),
      }),
    });
    if (!resp.ok || !resp.body) throw new Error(`HTTP ${resp.status}`);
    const reader = resp.body.getReader();
    const dec = new TextDecoder();
    let buf = '';
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      const lines = buf.split('\n');
      buf = lines.pop() ?? '';
      for (const line of lines) {
        const s = line.trim();
        if (!s.startsWith('data:')) continue;
        const payload = s.slice(5).trim();
        if (payload === '[DONE]') continue;
        try {
          const j = JSON.parse(payload);
          const delta = j.choices?.[0]?.delta?.content;
          if (delta) {
            placeholder.content += delta;
            renderAll();
          }
        } catch { /* 跳过不完整行 */ }
      }
    }
  } catch (e: any) {
    if (e?.name !== 'AbortError') {
      placeholder.content += `\n\n⚠️ 请求失败：${e?.message ?? e}\n（浏览器直连 API 可能受 CORS 限制，请确认服务商允许网页跨域调用）`;
    }
  } finally {
    state.sending = false;
    snapshotSession();
    renderAll();
  }
}

export function renderAll() {
  const panel = document.getElementById('chatPanel');
  if (panel) {
    refreshHead(panel);
    renderMessages(panel);
    const btn = document.getElementById('btnSend');
    if (btn) {
      btn.classList.toggle('stop', state.sending);
      btn.textContent = state.sending ? '■' : '↑';
    }
  }
}

function openModelSelector(root: HTMLElement) {
  const ps = profiles();
  const existing = document.getElementById('modelMenu');
  if (existing) { existing.remove(); return; }
  const menu = document.createElement('div');
  menu.id = 'modelMenu';
  menu.style.cssText = 'position:fixed;z-index:70;';
  const rect = $('#btnModel', root).getBoundingClientRect();
  menu.style.right = `${window.innerWidth - rect.right}px`;
  menu.style.bottom = `${window.innerHeight - rect.top + 8}px`;
  menu.innerHTML = `
    <div style="width:210px;background:#17171c;border:1px solid #2d2d35;border-radius:14px;box-shadow:0 16px 40px rgba(0,0,0,0.4);overflow:hidden">
      <div style="display:flex;justify-content:space-between;align-items:center;padding:12px 14px">
        <span style="font-size:11.5px;font-weight:700;color:#fff">Max 模式（1M 上下文）</span>
        <div id="maxSwitch" class="switch ${state.thinking ? 'on' : ''}" style="transform:scale(0.8)"></div>
      </div>
      <div style="height:1px;background:#24242b"></div>
      ${ps.map((p, i) => `
        <div class="model-row" data-i="${i}" style="padding:10px 14px;cursor:pointer;font-size:11.5px;font-weight:600;color:${p.model === state.cfg.model ? '#4cc38a' : '#fff'};display:flex;align-items:center;gap:8px">
          ${brandIcon(p.model)}<span style="flex:1">${esc2(p.model.toUpperCase())}</span>
        </div>`).join('')}
      <div style="height:1px;background:#24242b"></div>
      <div id="addModel" style="padding:12px 14px;cursor:pointer;font-size:11.5px;font-weight:600;color:#fff">⚙ 配置自定义模型</div>
    </div>`;
  document.body.appendChild(menu);
  menu.querySelector('#maxSwitch')!.addEventListener('click', () => {
    setThinking(!state.thinking);
    (menu.querySelector('#maxSwitch') as HTMLElement).classList.toggle('on', state.thinking);
  });
  menu.querySelectorAll('.model-row').forEach((r) => {
    r.addEventListener('click', () => {
      const p = ps[Number((r as HTMLElement).dataset.i)];
      state.cfg = { url: p.url, key: p.key, model: p.model };
      import('./store').then((m) => m.saveCfg());
      menu.remove();
      renderAll();
    });
  });
  menu.querySelector('#addModel')!.addEventListener('click', () => {
    menu.remove();
    dispatchEvent(new CustomEvent('afloat:open-settings'));
  });
  setTimeout(() => {
    const close = (e: MouseEvent) => {
      if (!menu.contains(e.target as Node)) { menu.remove(); document.removeEventListener('click', close); }
    };
    document.addEventListener('click', close);
  });
}

function openHistoryDrawer() {
  const old = document.getElementById('histDrawer');
  if (old) { old.remove(); return; }
  const mask = document.createElement('div');
  mask.id = 'histDrawer';
  mask.innerHTML = `
    <div class="drawer-mask" id="drawerMask"></div>
    <div class="drawer">
      <div class="drawer-head"><span>历史对话</span><button class="icon-btn" id="drawerClose">✕</button></div>
      <div class="drawer-list" id="drawerList"></div>
    </div>`;
  document.body.appendChild(mask);
  const renderList = () => {
    const list = $('#drawerList', mask);
    const pinned = state.sessions.filter((s) => s.pinned);
    const rest = state.sessions.filter((s) => !s.pinned);
    const item = (s: any) => `
      <div class="session-item ${s.id === state.activeSessionId ? 'active' : ''}" data-id="${s.id}">
        ${s.pinned ? '<span class="pin">📌</span>' : ''}
        <span style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc2(s.title)}</span>
        <button class="session-more" data-pin="${s.id}" title="置顶/取消置顶">📌</button>
        <button class="session-more" data-del="${s.id}" title="删除">✕</button>
      </div>`;
    let html = '';
    if (pinned.length) html += `<div class="session-group">📌 已置顶</div>` + pinned.map(item).join('');
    const groups: Record<string, any[]> = { 今天: [], 更早: [] };
    for (const s of rest) {
      const d = new Date(s.createdAt);
      const today = new Date().toDateString() === d.toDateString();
      groups[today ? '今天' : '更早'].push(s);
    }
    for (const k of ['今天', '更早']) {
      if (groups[k].length) html += `<div class="session-group">${k}</div>` + groups[k].map(item).join('');
    }
    list.innerHTML = html || `<div style="padding:60px 20px;text-align:center;color:#85859a;font-size:13px">还没有历史对话</div>`;
    list.querySelectorAll('.session-item').forEach((el) => {
      el.addEventListener('click', (e) => {
        if ((e.target as HTMLElement).closest('button')) return;
        import('./store').then((m) => { m.loadSession((el as HTMLElement).dataset.id!); renderList(); renderAll(); });
      });
    });
    list.querySelectorAll('button[data-pin]').forEach((b0) => { const b = b0 as HTMLElement;
      b.addEventListener('click', () => { import('./store').then((m) => { m.togglePin(b.dataset.pin!); renderList(); }); });
    });
    list.querySelectorAll('button[data-del]').forEach((b0) => { const b = b0 as HTMLElement;
      b.addEventListener('click', () => { import('./store').then((m) => { m.deleteSession(b.dataset.del!); renderList(); renderAll(); }); });
    });
  };
  renderList();
  $('#drawerClose', mask).addEventListener('click', () => mask.remove());
  $('#drawerMask', mask).addEventListener('click', () => mask.remove());
}
