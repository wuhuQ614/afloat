// AFloat Web 入口：玻璃背景 + 侧边栏 + 主内容路由 + AI 对话面板
import './styles.css';
import { state, notify, onChange, saveCfg, cfgReady, setZen, setThinking, type ApiConfig } from './store';
import { renderChatPanel, renderAll, refreshHead, profiles, saveProfiles, type Profile } from './chat';
import { renderMarkdown } from './md';
import { dict, zsbDict } from './dict';

const app = document.getElementById('app')!;

const TYPES = [
  { key: 'translation', icon: '文A', name: '翻译题', sub: '中英互译 · 长难句' },
  { key: 'reading', icon: '📖', name: '阅读理解', sub: '细节理解 · 推断题' },
  { key: 'cloze', icon: '❓', name: '语法填空', sub: '时态语态 · 从句' },
  { key: 'choice', icon: '✅', name: '选择题', sub: '单选 / 多选辨析' },
  { key: 'writing', icon: '✏️', name: '写作题', sub: '应用文 · 议论文' },
  { key: 'mixed', icon: '📋', name: '综合模拟套卷', sub: 'AI 混合全题型考卷', tag: 'MIX' },
];
const LEVELS = ['四级', '专升本', '简单', '中等', '困难', '墨墨词库'];

let selectedType = 'translation';
let selectedLevel = '专升本';
let questionCount = 30;
let customReq = '';

function background(): string {
  return `
  <div class="bg-layer">
    <div class="wash wash-1"></div><div class="wash wash-2"></div><div class="wash wash-3"></div>
    <div class="wash wash-4"></div><div class="wash wash-5"></div>
    <div class="ribbon ribbon-1"></div><div class="ribbon ribbon-2"></div><div class="ribbon ribbon-3"></div>
  </div>`;
}

function shell(): void {
  app.innerHTML = `
    ${background()}
    <div id="app">
      <nav class="sidebar" id="sidebar"></nav>
      <main class="main" id="pageRoot"></main>
      <div id="chatRoot" style="display:flex"></div>
    </div>`;
  const chatRoot = document.getElementById('chatRoot')!;
  renderChatPanel(chatRoot);
  renderSidebar();
  renderPage();
  if (state.zen) document.body.classList.add('zen');
}

function renderSidebar(): void {
  const sb = document.getElementById('sidebar')!;
  const items: Array<[string, string, string]> = [
    ['🏠', '学习', 'learn'],
    ['❓', '答题', 'answer'],
    ['📊', '学习报告', 'report'],
    ['🔍', '查询', 'lookup'],
  ];
  sb.innerHTML = `
    ${items.map(([ic, label, p]) => `
      <div class="nav-item ${state.page === p ? 'active' : ''}" data-page="${p}"><span>${ic}</span><span class="nav-label">${label}</span></div>`).join('')}
    <div class="nav-item" id="navMore"><span>🧩</span><span class="nav-label">更多功能</span></div>
    <div class="spacer"></div>
    <div class="nav-item" id="navSettings"><span>⚙️</span><span class="nav-label set-label">设置</span></div>`;
  sb.querySelectorAll('.nav-item[data-page]').forEach((el) => {
    el.addEventListener('click', () => {
      state.page = (el as HTMLElement).dataset.page as 'learn';
      renderSidebar();
      renderPage();
    });
  });
  document.getElementById('navSettings')!.addEventListener('click', () => openSettings());
  document.getElementById('navMore')!.addEventListener('click', () => openMore());
}

function renderPage(): void {
  const root = document.getElementById('pageRoot')!;
  if (state.page === 'learn') root.innerHTML = learnPage();
  else if (state.page === 'lookup') { root.innerHTML = lookupPage(); bindLookup(); }
  else if (state.page === 'report') root.innerHTML = `<div class="page-title">学习报告</div><div class="page-sub">网页版 v1 规划中</div>`;
  else root.innerHTML = `<div class="page-title">答题</div><div class="page-sub">在「学习」页生成题目后，此处进入答题</div>`;
  if (state.page === 'learn') bindLearn();
}

// ===== 学习页（题型选择 → 难度 → 题量 → 生成） =====
function learnPage(): string {
  return `
    <div class="page-title">AI 智能出题</div>
    <div class="page-sub">选择题型与难度，AI 生成练习题（生成内容会输出到右侧对话）</div>
    <div class="section-header"><span class="dot"></span>01. 题型选择</div>
    <div class="type-grid">
      ${TYPES.map((t) => `
        <div class="type-card ${selectedType === t.key ? 'selected' : ''}" data-type="${t.key}">
          ${t.tag ? `<span class="tc-tag">${t.tag}</span>` : ''}
          <div class="tc-icon">${t.icon}</div>
          <div class="tc-name">${t.name}</div>
          <div class="tc-sub">${t.sub}</div>
        </div>`).join('')}
    </div>
    <div class="section-header"><span class="dot"></span>02. 目标难度等级</div>
    <div class="glass-card"><div class="chip-row">
      ${LEVELS.map((l) => `<div class="chip ${selectedLevel === l ? 'selected' : ''}" data-level="${l}">${l}</div>`).join('')}
    </div></div>
    <div class="section-header"><span class="dot"></span>03. 题目规模</div>
    <div class="glass-card"><div class="slider-row">
      <div class="slider-big">${questionCount}<small>题量</small></div>
      <input type="range" id="countRange" min="1" max="100" value="${questionCount}">
    </div></div>
    <div class="section-header"><span class="dot"></span>04. 自定义要求（可选）</div>
    <div class="glass-card"><input id="customReq" placeholder="例如：要求 50 词以内、中译英方向、侧重商务话题…" style="width:100%;border:none;outline:none;background:transparent;font-size:13.5px;color:var(--text)"></div>
    <div style="margin-top:26px">
      <button class="btn-primary" id="btnGenerate">✨ 生成题目（输出到右侧对话）</button>
    </div>`;
}

function bindLearn(): void {
  document.querySelectorAll('.type-card').forEach((el) => {
    el.addEventListener('click', () => {
      selectedType = (el as HTMLElement).dataset.type!;
      renderPage();
    });
  });
  document.querySelectorAll('.chip[data-level]').forEach((el) => {
    el.addEventListener('click', () => {
      selectedLevel = (el as HTMLElement).dataset.level!;
      renderPage();
    });
  });
  const range = document.getElementById('countRange') as HTMLInputElement;
  range.addEventListener('input', () => {
    questionCount = Number(range.value);
    (document.querySelector('.slider-big') as HTMLElement).innerHTML = `${questionCount}<small>题量</small>`;
  });
  const req = document.getElementById('customReq') as HTMLInputElement;
  req.value = customReq;
  req.addEventListener('input', () => (customReq = req.value));
  document.getElementById('btnGenerate')!.addEventListener('click', () => {
    if (!cfgReady()) { alert('请先在 ⚙ 设置中配置 AI 接口'); return; }
    const typeName = TYPES.find((t) => t.key === selectedType)?.name ?? selectedType;
    const ta = document.getElementById('chatTa') as HTMLTextAreaElement;
    ta.value = `请生成 ${questionCount} 道${selectedLevel}${typeName}（${customReq || '无自定义要求'}），用 markdown 输出题目与答案解析。`;
    renderAll();
    // 复用对话面板的发送：模拟输入并触发
    (document.getElementById('btnSend') as HTMLButtonElement).click();
  });
}

// ===== 查词页（解析 dict.bin 二进制词库） =====
function lookupPage(): string {
  const status = dict.ready ? `通用词库 ${dict.size} 词 · 专升本 ${zsbDict.size} 词` : '词库加载中…';
  return `
    <div class="page-title">单词查询</div>
    <div class="page-sub">${status} · 与桌面版共用同一份二进制词库</div>
    <div style="height:18px"></div>
    <div class="lookup-row">
      <input id="lookupInput" placeholder="输入英文单词查询释义…" />
      <button id="lookupBtn">查询</button>
    </div>
    <div id="lookupResult"></div>`;
}

function bindLookup(): void {
  void Promise.all([dict.load('/dict.bin'), zsbDict.load('/zsb-dict.bin')]).then(() => renderPage());
  const input = document.getElementById('lookupInput') as HTMLInputElement;
  const btn = document.getElementById('lookupBtn') as HTMLButtonElement;
  const run = () => {
    const w = input.value.trim().toLowerCase();
    if (!w) return;
    let e = dict.lookup(w) ?? zsbDict.lookup(w);
    let src = dict.lookup(w) ? '通用词库' : (e ? '专升本词库' : '');
    if (!e) {
      const cand = dict.searchPrefix(w, 12);
      document.getElementById('lookupResult')!.innerHTML = cand.length
        ? `<div class="page-sub">未精确收录，近似词：</div>` + cand.map((c) => `
            <div class="word-entry"><span class="w">${c.word}</span><span class="p">${c.entry.pos}</span><span class="t">${c.entry.trans}</span></div>`).join('')
        : `<div class="page-sub">词典未收录：${w}</div>`;
      return;
    }
    void src;
    document.getElementById('lookupResult')!.innerHTML = `
      <div class="word-entry">
        <div><span class="w">${w}</span><span class="p">${e.pos}</span><span class="t">${e.trans}</span></div>
        <div style="margin-top:6px"><span class="p">${e.phonetic}</span></div>
        <div class="o">${e.other}</div>
      </div>`;
  };
  btn.addEventListener('click', run);
  input.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') run(); });
}

// ===== 设置弹窗 =====
function openSettings(): void {
  const mask = document.createElement('div');
  mask.className = 'modal-mask';
  const ps = profiles();
  const p = activeProfileOr(state.cfg);
  mask.innerHTML = `
    <div class="modal">
      <h3>⚙ 设置</h3>
      <div class="field"><label>API 地址（OpenAI 兼容，填到 /v1）</label><input id="setUrl" value="${p?.url ?? ''}" placeholder="https://api.example.com/v1"></div>
      <div class="field"><label>API Key</label><input id="setKey" type="password" value="${p?.key ?? ''}" placeholder="sk-..."></div>
      <div class="field"><label>模型名称</label><input id="setModel" value="${p?.model ?? ''}" placeholder="glm-5.2 / deepseek-v4-flash..."></div>
      <div class="set-row"><div><div class="label">深度思考 / Max 模式（1M 上下文）</div><div class="sub">关闭可加速响应；开启后上下文窗口扩展到 1M</div></div><span class="spacer"></span><div class="switch ${state.thinking ? 'on' : ''}" id="setThink"></div></div>
      <div class="set-row"><div><div class="label">专注全屏（纯净对话）</div><div class="sub">隐藏侧栏与主内容，专注与 AI 对话；重启后保持</div></div><span class="spacer"></span><div class="switch ${state.zen ? 'on' : ''}" id="setZen"></div></div>
      <div class="row-end">
        <button class="btn-ghost" id="setCancel">取消</button>
        <button class="btn-save" id="setSave">保存</button>
      </div>
    </div>`;
  document.body.appendChild(mask);
  mask.querySelector('#setCancel')!.addEventListener('click', () => mask.remove());
  mask.querySelector('#setThink')!.addEventListener('click', (e) => {
    setThinking(!state.thinking);
    (e.currentTarget as HTMLElement).classList.toggle('on', state.thinking);
  });
  mask.querySelector('#setZen')!.addEventListener('click', (e) => {
    setZen(!state.zen);
    (e.currentTarget as HTMLElement).classList.toggle('on', state.zen);
  });
  mask.querySelector('#setSave')!.addEventListener('click', () => {
    const cfg: ApiConfig = {
      url: (mask.querySelector('#setUrl') as HTMLInputElement).value.trim(),
      key: (mask.querySelector('#setKey') as HTMLInputElement).value.trim(),
      model: (mask.querySelector('#setModel') as HTMLInputElement).value.trim(),
    };
    state.cfg = cfg;
    saveCfg();
    const ps = profiles();
    const i = ps.findIndex((x) => x.model === cfg.model);
    const prof: Profile = { name: cfg.model, ...cfg };
    if (i >= 0) ps[i] = prof; else ps.push(prof);
    saveProfiles(ps);
    mask.remove();
    renderAll();
    refreshHead(document.getElementById('chatPanel')!);
  });
}

function activeProfileOr(def: ApiConfig): ApiConfig {
  const ps = profiles();
  return ps.find((x) => x.url === def.url && x.model === def.model) ?? { name: def.model, ...def };
}

function openMore(): void {
  const mask = document.createElement('div');
  mask.className = 'modal-mask';
  mask.innerHTML = `
    <div class="modal">
      <h3>🧩 更多功能</h3>
      <div class="set-row"><div><div class="label">单词默写</div><div class="sub">词库选择 · 中英默写 · AI 批改</div></div></div>
      <div class="set-row"><div><div class="label">语法学习</div><div class="sub">语法课程与练习</div></div></div>
      <div class="set-row"><div><div class="label">错题本 / 生词本</div><div class="sub">本地学习数据（网页版规划中）</div></div></div>
      <div class="set-row" style="border:none"><div><div class="label">贪吃蛇 / 五子棋</div><div class="sub">桌面版专属小游戏</div></div></div>
      <div class="row-end"><button class="btn-ghost" id="moreClose">关闭</button></div>
    </div>`;
  document.body.appendChild(mask);
  mask.querySelector('#moreClose')!.addEventListener('click', () => mask.remove());
  mask.addEventListener('click', (e) => { if (e.target === mask) mask.remove(); });
}

// ===== 启动 =====
shell();
onChange(() => { /* 状态变化时由各 render* 自行刷新 */ });
// 快捷键：Ctrl+Enter 生成
document.addEventListener('keydown', (e) => {
  if (e.key === 'F11') { e.preventDefault(); setZen(!state.zen); }
});
void renderMarkdown; void notify;
