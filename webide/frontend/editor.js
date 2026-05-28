// Global editor instance and current file state
let editor = null;
let currentFile = null;
let isDirty = false;

function initEditor() {
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
  });

  // Keyboard shortcuts
  editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, saveCurrentFile);
  editor.addCommand(monaco.KeyCode.F5, runScript);
  editor.addCommand(monaco.KeyCode.F6, stopScript);

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
  if (isDirty) await saveCurrentFile();

  const code = editor.getValue();
  const name = currentFile || 'untitled.lua';

  document.getElementById('btn-run').disabled = true;
  document.getElementById('btn-stop').disabled = false;
  clearLog();

  try {
    await fetch('/api/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, code }),
    });
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
  document.querySelectorAll('#file-list li').forEach(li => {
    li.classList.toggle('active', li.dataset.name === name);
  });
}

function getCurrentFileName() {
  return currentFile;
}
