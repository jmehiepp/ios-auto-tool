async function loadFileList() {
  try {
    const res = await fetch('/api/files');
    const files = await res.json();
    renderFileList(files);
    if (files.length > 0 && !currentFile) openFile(files[0]);
  } catch (e) {
    appendLog('ERROR', 'Failed to load file list: ' + e.message);
  }
}

function renderFileList(files) {
  const ul = document.getElementById('file-list');
  ul.innerHTML = '';
  files.sort().forEach(name => {
    const li = document.createElement('li');
    li.textContent = name;
    li.dataset.name = name;
    if (name === currentFile) li.classList.add('active');
    li.onclick = () => openFile(name);
    ul.appendChild(li);
  });
}

async function openFile(name) {
  try {
    const res = await fetch(`/api/files/${encodeURIComponent(name)}`);
    const data = await res.json();
    if (data.error) { appendLog('ERROR', data.error); return; }
    setCurrentFile(name, data.content);
  } catch (e) {
    appendLog('ERROR', 'Failed to open file: ' + e.message);
  }
}

async function saveFile(name, content) {
  try {
    await fetch(`/api/files/${encodeURIComponent(name)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content }),
    });
  } catch (e) {
    appendLog('ERROR', 'Failed to save file: ' + e.message);
  }
}

async function newFile() {
  const name = prompt('File name (e.g. script.lua):');
  if (!name) return;
  const filename = name.endsWith('.lua') ? name : name + '.lua';
  await saveFile(filename, '-- New script\n');
  await loadFileList();
  openFile(filename);
}

async function deleteCurrentFile() {
  if (!currentFile) return;
  if (!confirm(`Delete "${currentFile}"?`)) return;
  try {
    await fetch(`/api/files/${encodeURIComponent(currentFile)}`, {
      method: 'DELETE',
    });
    setCurrentFile(null, '');
    await loadFileList();
  } catch (e) {
    appendLog('ERROR', 'Failed to delete file: ' + e.message);
  }
}
