let _recording = false;
let _recPoller = null;

async function toggleRecord() {
  if (_recording) {
    await stopRecord();
  } else {
    await startRecord();
  }
}

async function startRecord() {
  try {
    const r = await fetch('/api/recorder/start', { method: 'POST' });
    if (!r.ok) { alert('Start failed'); return; }
    _recording = true;
    document.getElementById('btn-record').classList.add('recording');
    document.getElementById('btn-record').textContent = '■ Stop Rec';
    document.getElementById('rec-indicator').classList.add('visible');
    pollRecorder();
  } catch (e) {
    alert('Start failed: ' + e.message);
  }
}

async function stopRecord() {
  _recording = false;
  if (_recPoller) { clearInterval(_recPoller); _recPoller = null; }
  document.getElementById('btn-record').classList.remove('recording');
  document.getElementById('btn-record').textContent = '● Record';
  document.getElementById('rec-indicator').classList.remove('visible');

  try {
    const r = await fetch('/api/recorder/stop', { method: 'POST' });
    const data = await r.json();
    if (!r.ok) { alert('Stop failed'); return; }

    if (data.count === 0) {
      alert('Không có thao tác nào được ghi.');
      return;
    }

    const name = prompt(
      'Ghi xong ' + data.count + ' thao tác. Tên file lưu (không cần .lua):',
      'recorded-' + Date.now()
    );
    if (!name) return;
    const filename = name.endsWith('.lua') ? name : name + '.lua';

    const save = await fetch('/api/files/' + encodeURIComponent(filename), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content: data.code }),
    });
    if (!save.ok) { alert('Lưu file thất bại'); return; }

    if (typeof refreshFileList === 'function') refreshFileList();
    if (typeof loadFile === 'function') loadFile(filename);
    switchTab('ide');
    alert('Đã lưu ' + filename);
  } catch (e) {
    alert('Stop failed: ' + e.message);
  }
}

function pollRecorder() {
  _recPoller = setInterval(async () => {
    if (!_recording) return;
    try {
      const r = await fetch('/api/recorder/events');
      const data = await r.json();
      document.getElementById('rec-count').textContent = (data.events || []).length;
    } catch (_) {}
  }, 800);
}
