function updateSchedFields() {
  const t = document.getElementById('sched-type').value;
  document.getElementById('sched-daily-row').style.display    = (t === 'daily')    ? '' : 'none';
  document.getElementById('sched-interval-row').style.display = (t === 'interval') ? '' : 'none';
  document.getElementById('sched-once-row').style.display     = (t === 'once')     ? '' : 'none';
}

async function refreshSchedule() {
  await fillScheduleScriptList();
  await loadScheduleList();
}

async function fillScheduleScriptList() {
  const sel = document.getElementById('sched-script');
  const cur = sel.value;
  sel.innerHTML = '';
  try {
    const r = await fetch('/api/files');
    const files = await r.json();
    files.filter(f => f.endsWith('.lua')).forEach(f => {
      const o = document.createElement('option');
      o.value = f; o.textContent = f;
      sel.appendChild(o);
    });
    if (cur) sel.value = cur;
  } catch (_) {}
}

async function loadScheduleList() {
  const ul = document.getElementById('sched-list');
  ul.innerHTML = '';
  try {
    const r = await fetch('/api/schedule');
    const jobs = await r.json();
    if (!jobs.length) {
      ul.innerHTML = '<li class="sched-empty">Chưa có lịch nào.</li>';
      return;
    }
    jobs.forEach(j => ul.appendChild(renderJob(j)));
  } catch (_) {
    ul.innerHTML = '<li class="sched-empty">Không tải được danh sách.</li>';
  }
}

function describeJob(j) {
  if (j.type === 'daily')    return `Mỗi ngày ${pad2(j.hour)}:${pad2(j.minute)}`;
  if (j.type === 'interval') return `Mỗi ${j.interval_minutes} phút`;
  if (j.type === 'once')     return `1 lần lúc ${new Date(j.at * 1000).toLocaleString()}`;
  return j.type;
}
function pad2(n) { return String(n).padStart(2, '0'); }
function fmtTime(ts) { return ts ? new Date(ts * 1000).toLocaleString() : '—'; }

function renderJob(j) {
  const li = document.createElement('li');
  li.className = 'sched-item' + (j.enabled ? '' : ' disabled');
  li.innerHTML = `
    <div class="sched-item-main">
      <div class="sched-item-name">${j.script}</div>
      <div class="sched-item-when">${describeJob(j)}</div>
      <div class="sched-item-meta">
        Kế tiếp: ${fmtTime(j.next_run)} · Chạy lần cuối: ${fmtTime(j.last_run)}
      </div>
    </div>
    <div class="sched-item-actions">
      <button class="sched-btn sched-btn-toggle">${j.enabled ? 'Tạm dừng' : 'Bật lại'}</button>
      <button class="sched-btn sched-btn-del">Xoá</button>
    </div>
  `;
  li.querySelector('.sched-btn-toggle').onclick = () => toggleSchedule(j.id);
  li.querySelector('.sched-btn-del').onclick    = () => deleteSchedule(j.id);
  return li;
}

async function addSchedule() {
  const script = document.getElementById('sched-script').value;
  const type   = document.getElementById('sched-type').value;
  if (!script) { alert('Chọn file script trước'); return; }

  const body = { script, type };
  if (type === 'daily') {
    body.hour   = +document.getElementById('sched-hour').value;
    body.minute = +document.getElementById('sched-minute').value;
  } else if (type === 'interval') {
    body.interval_minutes = +document.getElementById('sched-interval').value;
  } else if (type === 'once') {
    const v = document.getElementById('sched-at').value;
    if (!v) { alert('Chọn thời điểm'); return; }
    body.at = Math.floor(new Date(v).getTime() / 1000);
  }

  const r = await fetch('/api/schedule/add', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!r.ok) { alert('Thêm lịch thất bại'); return; }
  await loadScheduleList();
}

async function toggleSchedule(id) {
  await fetch('/api/schedule/toggle', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id }),
  });
  await loadScheduleList();
}

async function deleteSchedule(id) {
  if (!confirm('Xoá lịch này?')) return;
  await fetch('/api/schedule/delete', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id }),
  });
  await loadScheduleList();
}
