// Markdown-lite 渲染器：转义 → 围栏代码卡片 → 块级（HR/引用/标题/表格/列表）→ 行内
function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

let codeSeq = 0;
const codeStore = new Map<string, string>();
export function getCode(id: string): string | undefined { return codeStore.get(id); }

function renderInline(s: string): string {
  let out = esc(s);
  // 转义符号 \* \` 等 → 字面输出
  out = out.replace(/\\([\\`*_{}\[\]()#+\-.!~>|])/g, '$1');
  out = out.replace(/`([^`]+)`/g, '<code>$1</code>');
  out = out.replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');
  out = out.replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, '$1<i>$2</i>');
  out = out.replace(/~~([^~]+)~~/g, '<s>$1</s>');
  return out;
}

function langLabel(lang: string): string {
  const l = lang.toLowerCase();
  const names: Record<string, string> = {
    html: 'HTML', css: 'CSS', js: 'JavaScript', javascript: 'JavaScript',
    ts: 'TypeScript', typescript: 'TypeScript', py: 'Python', python: 'Python',
    dart: 'Dart', cpp: 'C++', json: 'JSON', xml: 'XML', bash: 'Shell', sql: 'SQL',
  };
  return names[l] || (lang || '代码').toUpperCase();
}

export function renderMarkdown(text: string): string {
  const lines = text.split('\n');
  let html = '';
  let inCode = false;
  let codeLang = '';
  const codeBuf: string[] = [];
  let prevBlank = false;

  const flushCode = () => {
    const code = codeBuf.join('\n');
    const id = `c${++codeSeq}`;
    codeStore.set(id, code);
    const l = codeLang.toLowerCase();
    const runnable = l === 'html' || l === 'javascript' || l === 'js' || code.trimLeft().startsWith('<svg');
    html += `<pre data-code-id="${id}"><div class="code-bar"><span class="code-lang">${esc(langLabel(codeLang))}</span>`
      + `<span class="code-actions">`
      + (runnable ? `<button data-act="run" title="预览运行">▶</button>` : '')
      + `<button data-act="copy" title="复制">⧉</button>`
      + `<button data-act="dl" title="下载">↓</button></span></div>`
      + `<code>${esc(code)}</code></pre>`;
    codeBuf.length = 0;
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.startsWith('```')) {
      if (inCode) { flushCode(); inCode = false; codeLang = ''; }
      else { inCode = true; codeLang = line.slice(3).trim(); }
      continue;
    }
    if (inCode) { codeBuf.push(line); continue; }

    const t = line.trim();
    if (!t) { prevBlank = true; continue; }
    const brk = prevBlank ? '<br>' : '';
    prevBlank = false;

    // 分割线
    if (/^\s*([-*_])(?:\s*\1){2,}\s*$/.test(line)) { html += `${brk}<hr>`; continue; }
    // 引用
    if (line === '>' || line.startsWith('> ')) {
      html += `${brk}<blockquote>${renderInline(line === '>' ? '' : line.slice(2))}</blockquote>`;
      continue;
    }
    // 标题
    const h = /^(#{1,3})\s+(.*)$/.exec(line);
    if (h) {
      const lv = h[1].length;
      html += `${brk}<h${lv + 0}>${renderInline(h[2])}</h${lv + 0}>`;
      continue;
    }
    // 表格
    if (/^\s*\|.+\|\s*$/.test(line) && i + 1 < lines.length && /^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)+\|?\s*$/.test(lines[i + 1])) {
      const cells = (l: string) => l.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
      const head = cells(line);
      let body = '';
      let j = i + 2;
      while (j < lines.length && /^\s*\|.+\|\s*$/.test(lines[j])) {
        body += '<tr>' + cells(lines[j]).map((c) => `<td>${renderInline(c)}</td>`).join('') + '</tr>';
        j++;
      }
      html += `${brk}<table><thead><tr>${head.map((c) => `<th>${renderInline(c)}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table>`;
      i = j - 1;
      continue;
    }
    // 有序/无序列表
    const ol = /^(\d+)\.\s+(.*)$/.exec(line);
    if (ol) { html += `${brk}${ol[1]}. ${renderInline(ol[2])}`; continue; }
    if (/^[-*]\s+/.test(line)) { html += `${brk}• ${renderInline(line.replace(/^[-*]\s+/, ''))}`; continue; }
    // 数学公式 $$...$$ → 行内代码样式的原文展示（浏览器端无 KaTeX，保持可读）
    if (t.startsWith('$$')) {
      html += `${brk}<code>${esc(t)}</code>`;
      continue;
    }
    html += `${brk}${renderInline(line)}`;
  }
  return html;
}

/** 代码卡片动作代理（事件委托由 chat 绑定） */
export function bindCodeActions(root: HTMLElement) {
  root.addEventListener('click', (e) => {
    const btn = (e.target as HTMLElement).closest('button[data-act]') as HTMLElement | null;
    if (!btn) return;
    const pre = btn.closest('pre');
    const id = pre?.getAttribute('data-code-id');
    if (!id) return;
    const code = getCode(id) ?? '';
    const act = btn.getAttribute('data-act');
    if (act === 'copy') {
      navigator.clipboard.writeText(code);
      btn.textContent = '✓';
      setTimeout(() => (btn.textContent = '⧉'), 1200);
    } else if (act === 'dl') {
      const blob = new Blob([code], { type: 'text/plain' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `snippet.${pre?.getAttribute('data-code-lang') || 'txt'}`;
      a.click();
      URL.revokeObjectURL(a.href);
    } else if (act === 'run') {
      const win = window.open('', '_blank');
      win?.document.write(code);
      win?.document.close();
    }
  });
}
