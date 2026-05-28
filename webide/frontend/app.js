'use strict';

// ── State ──────────────────────────────────────────────────────────────────
let _deviceW = 0, _deviceH = 0;
let _liveTimer = null;
let _allApps = [];
let _spoofData = {};
let _dragStart = null;
let _funcsVisible = true;
let _activeTab = 'ide';

const KNOWN_SPOOF_KEYS = [
  'device_model', 'ios_version',
  'screen_width', 'screen_height', 'screen_scale',
  'locale', 'timezone',
  'wifi_ssid', 'carrier_name',
  'gps_lat', 'gps_lng',
  'idfa', 'idfv',
  'user_agent',
];

// ── Tab switching ──────────────────────────────────────────────────────────
function switchTab(name) {
  _activeTab = name;

  document.querySelectorAll('.htab').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.content-panel').forEach(el => el.classList.remove('visible'));

  document.querySelector('.htab-' + name)?.classList.add('active');
  const panel = document.getElementById('panel-' + name);
  if (panel) panel.classList.add('visible');

  if (name === 'apps'   && !_allApps.length) loadApps();
  if (name === 'device')                      loadDevice();
  if (name === 'spoof')                       loadSpoof();
}

// ── Functions panel ────────────────────────────────────────────────────────
function toggleFuncs() {
  _funcsVisible = !_funcsVisible;
  const panel = document.getElementById('funcs-panel');
  const ws    = document.getElementById('workspace');
  const btn   = document.getElementById('btn-funcs-toggle');
  panel.classList.toggle('hidden', !_funcsVisible);
  ws.classList.toggle('no-funcs', !_funcsVisible);
  btn.classList.toggle('active', _funcsVisible);
}

function filterFuncs(q) {
  const lower = q.toLowerCase().trim();
  const items = document.querySelectorAll('#funcs-list .funcs-fn, #funcs-list .funcs-cat');
  let lastCat = null;
  items.forEach(el => {
    if (el.classList.contains('funcs-cat')) {
      lastCat = el;
      el.style.display = '';
    } else {
      const match = !lower || el.textContent.toLowerCase().includes(lower);
      el.style.display = match ? '' : 'none';
    }
  });

  if (lower) {
    // Hide category headers with no visible children
    document.querySelectorAll('#funcs-list .funcs-cat').forEach(cat => {
      let next = cat.nextElementSibling;
      let hasVisible = false;
      while (next && !next.classList.contains('funcs-cat')) {
        if (next.style.display !== 'none') hasVisible = true;
        next = next.nextElementSibling;
      }
      cat.style.display = hasVisible ? '' : 'none';
    });
  }
}

// ── Device info ────────────────────────────────────────────────────────────
async function loadDevice() {
  try {
    const info = await fetch('/api/device-info').then(r => r.json());
    const model = info.model || '—';
    const ios   = info.ios   || '—';

    document.getElementById('device-info').textContent = model + '  iOS ' + ios;
    document.getElementById('dv-model').textContent    = model;
    document.getElementById('dv-ios').textContent      = ios;

    if (_deviceW) {
      document.getElementById('dv-screen').textContent = _deviceW + ' × ' + _deviceH;
    }

    const mcpBadge = document.getElementById('dv-mcp');
    if (mcpBadge) {
      mcpBadge.innerHTML = '<span class="badge badge-green"><span class="badge-dot"></span>Online :8765</span>';
    }
  } catch (_) {}
}

// ── Apps ───────────────────────────────────────────────────────────────────
async function loadApps() {
  const list = document.getElementById('ap-list');
  list.innerHTML = '<li style="color:var(--text-dim);padding:12px">Loading…</li>';
  try {
    _allApps = await fetch('/api/apps').then(r => r.json());
    renderApps(_allApps);
  } catch (e) {
    list.innerHTML = '<li style="color:var(--red);padding:12px">Failed: ' + esc(e.message) + '</li>';
  }
}

function renderApps(apps) {
  const list = document.getElementById('ap-list');
  if (!apps.length) {
    list.innerHTML = '<li style="color:var(--text-dim);padding:12px">No apps found</li>';
    return;
  }
  list.innerHTML = apps.map(a =>
    `<li class="ap-row">
      <div class="ap-info">
        <div class="ap-name">${esc(a.name)}</div>
        <div class="ap-bid">${esc(a.bundleId)}</div>
      </div>
      <button class="ap-btn ap-btn-launch" onclick="launchApp('${esc(a.bundleId)}')">Launch</button>
      <button class="ap-btn ap-btn-kill"   onclick="killApp('${esc(a.bundleId)}')">Kill</button>
    </li>`
  ).join('');
}

function filterApps(q) {
  const lower = q.toLowerCase();
  renderApps(_allApps.filter(a =>
    a.name.toLowerCase().includes(lower) || a.bundleId.toLowerCase().includes(lower)
  ));
}

async function launchApp(bundleId) {
  const res = await fetch('/api/apps/launch', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({bundleId}),
  }).then(r => r.json()).catch(() => ({error: 'network error'}));
  if (res.error) alert('Launch failed: ' + res.error);
}

async function killApp(bundleId) {
  const res = await fetch('/api/apps/kill', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({bundleId}),
  }).then(r => r.json()).catch(() => ({error: 'network error'}));
  if (res.error) alert('Kill failed: ' + res.error);
}

// ── Screenshot + Touch ─────────────────────────────────────────────────────
async function captureOnce() {
  try {
    const data = await fetch('/api/screenshot').then(r => r.json());
    if (data.error || !data.image) return;

    _deviceW = data.width;
    _deviceH = data.height;

    const img = document.getElementById('screen-img');
    img.src = 'data:image/png;base64,' + data.image;
    img.style.display = 'block';
    document.getElementById('screen-placeholder').style.display = 'none';

    const dv = document.getElementById('dv-screen');
    if (dv) dv.textContent = _deviceW + ' × ' + _deviceH;

    if (!img._touchWired) {
      img._touchWired = true;
      img.addEventListener('mousedown',  onScreenMouseDown);
      img.addEventListener('mousemove',  onScreenMouseMove);
      img.addEventListener('mouseup',    onScreenMouseUp);
      img.addEventListener('mouseleave', onScreenMouseLeave);
    }
  } catch (e) {
    console.error('Screenshot:', e);
  }
}

function toggleLive() {
  const btn  = document.getElementById('btn-live');
  const dot  = document.getElementById('screen-dot');
  if (_liveTimer) {
    clearInterval(_liveTimer);
    _liveTimer = null;
    btn.classList.remove('on');
    btn.textContent = '● Live';
    if (dot) dot.classList.remove('live');
  } else {
    captureOnce();
    _liveTimer = setInterval(captureOnce, 1000);
    btn.classList.add('on');
    btn.textContent = '◉ Live';
    if (dot) dot.classList.add('live');
  }
}

function mapCoords(img, clientX, clientY) {
  const rect = img.getBoundingClientRect();
  return {
    x: Math.round(((clientX - rect.left) / rect.width)  * (_deviceW || img.naturalWidth)),
    y: Math.round(((clientY - rect.top)  / rect.height) * (_deviceH || img.naturalHeight)),
  };
}

function onScreenMouseDown(e) {
  e.preventDefault();
  _dragStart = {cx: e.clientX, cy: e.clientY};
}

function onScreenMouseMove(e) {
  if (!_deviceW) return;
  const c = mapCoords(e.currentTarget, e.clientX, e.clientY);
  const coord = document.getElementById('screen-coords');
  if (coord) coord.textContent = c.x + ', ' + c.y;
}

function onScreenMouseUp(e) {
  if (!_dragStart) return;
  const img   = e.currentTarget;
  const start = mapCoords(img, _dragStart.cx, _dragStart.cy);
  const end   = mapCoords(img, e.clientX, e.clientY);
  _dragStart  = null;

  const dx = end.x - start.x;
  const dy = end.y - start.y;

  if (Math.abs(dx) > 10 || Math.abs(dy) > 10) {
    sendTouch('swipe', start.x, start.y, dx, dy);
  } else {
    sendTouch('tap', start.x, start.y, 0, 0);
  }
}

function onScreenMouseLeave() {
  _dragStart = null;
  const coord = document.getElementById('screen-coords');
  if (coord) coord.textContent = '';
}

function sendTouch(type, x, y, dx, dy) {
  fetch('/api/touch', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({type, x, y, dx, dy}),
  }).catch(console.error);
}

function pressKey(key) {
  fetch('/api/key', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({key}),
  }).catch(console.error);
}

// ── Spoof ──────────────────────────────────────────────────────────────────
async function loadSpoof() {
  try {
    _spoofData = await fetch('/api/spoof').then(r => r.json());
    renderSpoof();
  } catch (e) {
    const tbody = document.getElementById('sp-body');
    if (tbody) tbody.innerHTML =
      '<tr><td colspan="2" style="color:var(--red);padding:12px">Failed: ' + esc(e.message) + '</td></tr>';
  }
}

function renderSpoof() {
  const keys = [...new Set([...KNOWN_SPOOF_KEYS, ...Object.keys(_spoofData)])];
  const anyEnabled = keys.some(k => _spoofData[k]?.enabled);
  const statusEl = document.getElementById('sp-status');
  if (statusEl) {
    statusEl.innerHTML = anyEnabled
      ? '<span class="badge badge-green"><span class="badge-dot"></span>Active</span>'
      : '<span class="badge badge-dim"><span class="badge-dot"></span>Off</span>';
  }

  const tbody = document.getElementById('sp-body');
  if (!tbody) return;
  tbody.innerHTML = keys.map(k => {
    const entry = _spoofData[k] || {};
    const val   = entry.value != null ? String(entry.value) : '';
    return `<tr data-key="${esc(k)}">
      <td class="sp-key">${esc(k)}</td>
      <td><input class="sp-val" type="text" value="${esc(val)}"
          data-orig="${esc(val)}" placeholder="—"></td>
    </tr>`;
  }).join('');
}

async function saveSpoof() {
  const tasks = [];
  document.querySelectorAll('#sp-body tr[data-key]').forEach(row => {
    const key = row.dataset.key;
    const inp = row.querySelector('.sp-val');
    const raw = inp.value.trim();
    if (raw === inp.dataset.orig) return;

    const num = Number(raw);
    const val = raw === 'true' ? true
              : raw === 'false' ? false
              : raw !== '' && !isNaN(num) ? num
              : raw;

    tasks.push(fetch('/api/spoof', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({key, value: val}),
    }));
    inp.dataset.orig = raw;
  });
  await Promise.all(tasks);
  await loadSpoof();
}

async function applyPreset(name) {
  if (!name) return;
  await fetch('/api/spoof/preset', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({name}),
  }).catch(console.error);
  document.getElementById('sp-preset').value = '';
  await loadSpoof();
}

async function resetSpoof() {
  if (!confirm('Reset all spoof settings?')) return;
  await fetch('/api/spoof', {method: 'DELETE'}).catch(console.error);
  await loadSpoof();
}

// ── Log helpers ────────────────────────────────────────────────────────────
function copyLog() {
  const el = document.getElementById('log-output');
  if (!el) return;
  navigator.clipboard.writeText(el.innerText).catch(() => {
    const ta = document.createElement('textarea');
    ta.value = el.innerText;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
  });
}

// ── Helpers ────────────────────────────────────────────────────────────────
function esc(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ── Init ───────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  loadDevice();
  document.getElementById('btn-funcs-toggle').classList.add('active');
});
