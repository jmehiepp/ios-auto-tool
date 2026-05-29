const _chatHistory = [];

function appendMessage(role, text, code) {
  const wrap = document.getElementById('chat-messages');
  const empty = wrap.querySelector('.chat-empty');
  if (empty) empty.remove();

  const div = document.createElement('div');
  div.className = 'chat-msg chat-msg-' + role;
  div.innerHTML = '<div class="chat-msg-body"></div>';
  div.querySelector('.chat-msg-body').textContent = text;

  if (code) {
    const codeWrap = document.createElement('div');
    codeWrap.className = 'chat-code';

    const pre = document.createElement('pre');
    pre.className = 'chat-code-text';
    pre.textContent = code;
    codeWrap.appendChild(pre);

    const actions = document.createElement('div');
    actions.className = 'chat-code-actions';
    actions.innerHTML = `
      <button class="chat-code-btn chat-code-run">▶ Run</button>
      <button class="chat-code-btn chat-code-save">↓ Lưu thành file</button>
      <button class="chat-code-btn chat-code-copy">Copy</button>
    `;
    actions.querySelector('.chat-code-run').onclick = () => runChatCode(code);
    actions.querySelector('.chat-code-save').onclick = () => saveChatCode(code);
    actions.querySelector('.chat-code-copy').onclick = () => navigator.clipboard.writeText(code);
    codeWrap.appendChild(actions);

    div.appendChild(codeWrap);
  }
  wrap.appendChild(div);
  wrap.scrollTop = wrap.scrollHeight;
}

function setChatLoading(loading) {
  const btn = document.getElementById('chat-send');
  const input = document.getElementById('chat-input');
  btn.disabled = loading;
  input.disabled = loading;
  btn.textContent = loading ? '...' : 'Gửi';
}

async function sendChat() {
  const input = document.getElementById('chat-input');
  const msg = input.value.trim();
  if (!msg) return;

  appendMessage('user', msg);
  _chatHistory.push({ role: 'user', content: msg });
  input.value = '';
  setChatLoading(true);

  try {
    const resp = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: msg, history: _chatHistory.slice(0, -1) }),
    });
    const data = await resp.json();
    if (!resp.ok) {
      appendMessage('assistant', '⚠ Lỗi: ' + (data.error || resp.statusText));
      return;
    }
    appendMessage('assistant', data.reply || '', data.code || '');
    _chatHistory.push({ role: 'assistant', content: data.reply || '' });
  } catch (e) {
    appendMessage('assistant', '⚠ Mạng lỗi: ' + e.message);
  } finally {
    setChatLoading(false);
  }
}

async function runChatCode(code) {
  switchTab('ide');
  try {
    const resp = await fetch('/api/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'chat-run', code }),
    });
    if (!resp.ok) {
      const e = await resp.json().catch(() => ({}));
      alert('Run failed: ' + (e.error || resp.statusText));
    }
  } catch (e) {
    alert('Run failed: ' + e.message);
  }
}

async function saveChatCode(code) {
  const name = prompt('Tên file (không cần .lua):', 'untitled');
  if (!name) return;
  const filename = name.endsWith('.lua') ? name : name + '.lua';
  try {
    const resp = await fetch('/api/files/' + encodeURIComponent(filename), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content: code }),
    });
    if (resp.ok) {
      if (typeof refreshFileList === 'function') refreshFileList();
      alert('Đã lưu ' + filename);
    } else {
      alert('Save failed');
    }
  } catch (e) {
    alert('Save failed: ' + e.message);
  }
}
