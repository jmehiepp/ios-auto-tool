'use strict';

// ── State ──────────────────────────────────────────────────────────────────
let _deviceW = 0, _deviceH = 0;
let _liveTimer = null;
let _allApps = [];
let _spoofData = {};
let _dragStart = null;

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
  document.querySelectorAll('.a-tab').forEach(el => el.classList.remove('visible'));
  document.querySelectorAll('.a-nav button').forEach(el => el.classList.remove('active'));
  document.getElementById('tab-' + name).classList.add('visible');
  document.getElementById('tab-btn-' + name).classList.add('active');

  if (name === 'apps'   && !_allApps.length) loadApps();
  if (name === 'screen' && !_deviceW)        captureOnce();
  if (name === 'spoof')                       loadSpoof();
}

// ── Dashboard ──────────────────────────────────────────────────────────────
async function loadDashboard() {
  try {
    const info = await fetch('/api/device-info').then(r => r.json());
    document.getElementById('d-model').textContent = info.model || '—';
    document.getElementById('d-ios').textContent   = 'iOS ' + (info.ios || '—');
    document.getElementById('a-device-info').textContent =
      (info.model || '') + '  iOS ' + (info.ios || '');
  } catch (_) {}

  // Screen size comes from first screenshot fetch; check if already known
  if (_deviceW) {
    document.getElementById('d-screen').textContent = _deviceW + ' × ' + _deviceH;
  }

  // Mark services as up (we're already talking to them)
  setBadge('svc-mcp', 'green', '8765 ●');
  setBadge('svc-ide', 'green', '8888 ●');
}

function setBadge(id, color, text) {
  const el = document.getElementById(id);
  el.className = 'badge badge-' + color;
  el.textContent = text;
}

// ── Apps ───────────────────────────────────────────────────────────────────
async function loadApps() {
  const list = document.getElementById('app-list');
  list.innerHTML = '<li style="color:#666;padding:10px">Loading…</li>';
  try {
    _allApps = await fetch('/api/apps').then(r => r.json());
    renderApps(_allApps);
  } catch (e) {
    list.innerHTML = '<li style="color:#c62828;padding:10px">Failed: ' + e.message + '</li>';
  }
}

function renderApps(apps) {
  const list = document.getElementById('app-list');
  if (!apps.length) {
    list.innerHTML = '<li style="color:#666;padding:10px">No apps found</li>';
    return;
  }
  list.innerHTML = apps.map(a =>
    `<li class="app-row" id="app-${CSS.escape(a.bundleId)}">
      <div style="flex:1;overflow:hidden">
        <div class="app-name">${esc(a.name)}</div>
        <div class="app-bid">${esc(a.bundleId)}</div>
      </div>
      <button class="btn-sm btn-launch" onclick="launchApp('${esc(a.bundleId)}')">Launch</button>
      <button class="btn-sm btn-kill"   onclick="killApp('${esc(a.bundleId)}')">Kill</button>
    </li>`
  ).join('');
}

function filterApps(q) {
  const lower = q.toLowerCase();
  const filtered = _allApps.filter(a =>
    a.name.toLowerCase().includes(lower) || a.bundleId.toLowerCase().includes(lower)
  );
  renderApps(filtered);
}

async function launchApp(bundleId) {
  const res = await fetch('/api/apps/launch', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({bundleId}),
  }).then(r => r.json());
  if (res.error) alert('Launch failed: ' + res.error);
}

async function killApp(bundleId) {
  const res = await fetch('/api/apps/kill', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({bundleId}),
  }).then(r => r.json());
  if (res.error) alert('Kill failed: ' + res.error);
}

// ── Screenshot + Touch ─────────────────────────────────────────────────────
async function captureOnce() {
  try {
    const data = await fetch('/api/screenshot').then(r => r.json());
    if (data.error) return;

    _deviceW = data.width;
    _deviceH = data.height;

    const img  = document.getElementById('screen-img');
    const wrap = document.getElementById('screen-wrap');
    img.src = 'data:image/png;base64,' + data.image;
    img.style.display = 'block';
    document.getElementById('screen-placeholder').style.display = 'none';

    // Wire touch handlers once
    if (!img._touchWired) {
      img._touchWired = true;
      img.addEventListener('mousedown',  onScreenMouseDown);
      img.addEventListener('mousemove',  onScreenMouseMove);
      img.addEventListener('mouseup',    onScreenMouseUp);
      img.addEventListener('mouseleave', onScreenMouseLeave);
    }

    // Update dashboard screen size if visible
    const dsEl = document.getElementById('d-screen');
    if (dsEl) dsEl.textContent = _deviceW + ' × ' + _deviceH;
  } catch (e) {
    console.error('Screenshot error:', e);
  }
}

function toggleLive() {
  const btn = document.getElementById('live-btn');
  if (_liveTimer) {
    clearInterval(_liveTimer);
    _liveTimer = null;
    btn.textContent = 'Live: OFF';
    btn.className = 'btn-secondary';
  } else {
    captureOnce();
    _liveTimer = setInterval(captureOnce, 1000);
    btn.textContent = 'Live: ON';
    btn.className = 'btn-primary';
  }
}

function mapCoords(img, clientX, clientY) {
  const rect = img.getBoundingClientRect();
  const rx = (clientX - rect.left) / rect.width;
  const ry = (clientY - rect.top)  / rect.height;
  return {
    x: Math.round(rx * (_deviceW || img.naturalWidth)),
    y: Math.round(ry * (_deviceH || img.naturalHeight)),
  };
}

function onScreenMouseDown(e) {
  e.preventDefault();
  _dragStart = {cx: e.clientX, cy: e.clientY};
}

function onScreenMouseMove(e) {
  if (!_deviceW) return;
  const img = document.getElementById('screen-img');
  const c = mapCoords(img, e.clientX, e.clientY);
  document.getElementById('screen-coords').textContent = c.x + ', ' + c.y;
}

function onScreenMouseUp(e) {
  if (!_dragStart) return;
  const img   = document.getElementById('screen-img');
  const start = mapCoords(img, _dragStart.cx, _dragStart.cy);
  const end   = mapCoords(img, e.clientX, e.clientY);
  const dx    = end.x - start.x;
  const dy    = end.y - start.y;
  _dragStart  = null;

  if (Math.abs(dx) > 10 || Math.abs(dy) > 10) {
    sendTouch('swipe', start.x, start.y, dx, dy);
  } else {
    sendTouch('tap', start.x, start.y, 0, 0);
  }
}

function onScreenMouseLeave() {
  document.getElementById('screen-coords').textContent = '';
}

function sendTouch(type, x, y, dx, dy) {
  fetch('/api/touch', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({x, y, type, dx, dy}),
  }).catch(console.error);
}

async function sendKey(key) {
  await fetch('/api/key', {
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
    document.getElementById('spoof-tbody').innerHTML =
      '<tr><td colspan="3" style="color:#c62828;padding:10px">Failed: ' + e.message + '</td></tr>';
  }
}

function renderSpoof() {
  // Merge known keys + any extra keys from current config
  const keys = [...new Set([...KNOWN_SPOOF_KEYS, ...Object.keys(_spoofData)])];
  const anyEnabled = keys.some(k => _spoofData[k]?.enabled);
  setBadge('spoof-status', anyEnabled ? 'green' : 'gray', anyEnabled ? 'active' : 'off');

  document.getElementById('spoof-tbody').innerHTML = keys.map(k => {
    const entry   = _spoofData[k] || {};
    const enabled = !!entry.enabled;
    const value   = entry.value != null ? String(entry.value) : '';
    return `<tr data-key="${esc(k)}">
      <td><input type="checkbox" class="spoof-enabled" ${enabled ? 'checked' : ''}
          onchange="onSpoofCheckbox(this,'${esc(k)}')"></td>
      <td><span class="spoof-key">${esc(k)}</span></td>
      <td><input type="text" class="spoof-val" value="${esc(value)}"
          placeholder="value" data-orig="${esc(value)}"></td>
    </tr>`;
  }).join('');
}

function onSpoofCheckbox(cb, key) {
  // If unchecking, immediately disable the key
  if (!cb.checked) {
    fetch('/api/spoof', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({key, value: null}),
    }).catch(console.error);
  }
}

async function saveSpoof() {
  const rows = document.querySelectorAll('#spoof-tbody tr[data-key]');
  const tasks = [];
  rows.forEach(row => {
    const key     = row.dataset.key;
    const cb      = row.querySelector('.spoof-enabled');
    const valInp  = row.querySelector('.spoof-val');
    const enabled = cb.checked;
    const value   = valInp.value.trim();

    if (!enabled) return; // disabled keys handled by onSpoofCheckbox immediately
    if (!value)   return;

    // Try to cast to number if it looks numeric
    const numVal = Number(value);
    const finalVal = value === 'true'  ? true
                   : value === 'false' ? false
                   : !isNaN(numVal) && value !== '' ? numVal
                   : value;

    tasks.push(
      fetch('/api/spoof', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({key, value: finalVal}),
      })
    );
    valInp.dataset.orig = value;
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
  });
  document.getElementById('spoof-preset').value = '';
  await loadSpoof();
}

async function resetSpoof() {
  if (!confirm('Reset all spoof settings?')) return;
  await fetch('/api/spoof', {method: 'DELETE'});
  await loadSpoof();
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
loadDashboard();
