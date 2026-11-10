// Global editor instance and current file state
let editor = null;
let currentFile = null;
let isDirty = false;

function initEditor() {
  if (editor) return;
  if (!window.monaco) {
    const textarea = document.createElement('textarea');
    textarea.spellcheck = false;
    textarea.setAttribute('aria-label', 'Lua script editor');
    textarea.style.cssText = 'box-sizing:border-box;width:100%;height:100%;resize:none;border:0;padding:20px;background:#10131c;color:#e8edff;font:14px/1.6 monospace;outline:none;tab-size:2';
    document.getElementById('editor-container').replaceChildren(textarea);
    textarea.addEventListener('input', () => { isDirty = true; updateCompatibilityMode(textarea.value); });
    textarea.addEventListener('keydown', e => {
      if ((e.ctrlKey || e.metaKey) && e.key === 's') { e.preventDefault(); saveCurrentFile(); }
      if (e.key === 'F5') { e.preventDefault(); runScript(); }
      if (e.key === 'F6') { e.preventDefault(); stopScript(); }
    });
    editor = { getValue: () => textarea.value, setValue: v => { textarea.value = v; }, setScrollPosition: () => { textarea.scrollTop = 0; }, focus: () => textarea.focus() };
  } else {
  editor = monaco.editor.create(document.getElementById('editor-container'), {
    language: 'lua',
    theme: 'vs-dark',
    fontSize: 14,
    minimap: { enabled: false },
    automaticLayout: true,
    wordWrap: 'on',
    scrollBeyondLastLine: false,
  });

  editor.onDidChangeModelContent(() => {
    isDirty = true;
    updateCompatibilityMode(editor.getValue());
  });

  // Keyboard shortcuts
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, saveCurrentFile);
  editor.addCommand(monaco.KeyCode.F5, runScript);
  editor.addCommand(monaco.KeyCode.F6, stopScript);
  }

  // Load initial file list
  loadFileList();

  // Load device info in header
  fetch('/api/device-info')
    .then(r => r.json())
    .then(d => {
      document.getElementById('device-info').textContent =
        `${d.model} · iOS ${d.ios}`;
    })
    .catch(() => {});

  // Connect WebSocket log stream
  initLogSocket();
}

async function saveCurrentFile() {
  if (!currentFile || !editor) return;
  await saveFile(currentFile, editor.getValue());
  isDirty = false;
}

async function runScript() {
  if (!editor) return;
  if (isDirty) { try { await saveCurrentFile(); } catch (_) { return; } }

  const code = editor.getValue();
  const name = currentFile || 'untitled.lua';

  document.getElementById('btn-run').disabled = true;
  document.getElementById('btn-stop').disabled = false;
  clearLog();

  try {
    const response = await fetch('/api/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, code }),
    });
    if (!response.ok) {
      const body = await response.json();
      throw new Error(body.error || `HTTP ${response.status}`);
    }
  } catch (e) {
    appendLog('ERROR', 'Failed to send run request: ' + e.message);
    setRunning(false);
  }
}

async function stopScript() {
  try {
    await fetch('/api/stop', { method: 'POST' });
  } catch (e) {
    appendLog('ERROR', 'Failed to send stop request: ' + e.message);
  }
  setRunning(false);
}

function setRunning(running) {
  document.getElementById('btn-run').disabled = running;
  document.getElementById('btn-stop').disabled = !running;
}

function setCurrentFile(name, content) {
  currentFile = name;
  isDirty = false;
  if (editor) {
    editor.setValue(content || '');
    editor.setScrollPosition({ scrollTop: 0 });
  }
  updateCompatibilityMode(content || '');
  document.querySelectorAll('#file-list li').forEach(li => {
    li.classList.toggle('active', li.dataset.name === name);
  });
}

function updateCompatibilityMode(content) {
  const field = document.getElementById('compatibility-mode');
  if (field) field.value = /^(?:\uFEFF)?--!iosautomate(?:\r?\n|$)/.test(content) ? 'legacy' : 'native';
  document.querySelectorAll('.funcs-fn[data-native]').forEach(row => {
    row.textContent = field?.value === 'legacy' ? (row.dataset.legacy || row.dataset.native) : row.dataset.native;
  });
}

function setCompatibilityMode(mode) {
  if (!editor) return;
  let code = editor.getValue().replace(/^\uFEFF/, '');
  code = code.replace(/^--!iosautomate(?:\r?\n|$)/, '');
  if (mode === 'legacy') code = '--!iosautomate\n' + code;
  editor.setValue(code);
  isDirty = true;
  updateCompatibilityMode(code);
}

function getCurrentFileName() {
  return currentFile;
}

document.addEventListener('DOMContentLoaded', () => setTimeout(initEditor, 700));
