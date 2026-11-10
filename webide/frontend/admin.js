'use strict';

// ── State ──────────────────────────────────────────────────────────────────
let _deviceW = 0, _deviceH = 0;
let _liveTimer = null;
let _allApps = [];
let _spoofData = {};
let _dragStart = null;

const DEVICE_FIELDS = [
  ['device_model','Model','iPhone14,5'], ['device_family','Device family','iPhone'],
  ['device_name','Device name','Test iPhone'], ['ios_version','iOS version','15.8.4'],
  ['screen_resolution','Screen (points)','{"w":375,"h":667,"scale":2}'],
  ['screen_scale','Screen scale','2'], ['locale','Locale','vi_VN'],
  ['timezone','Time zone','Asia/Ho_Chi_Minh'], ['carrier_name','Carrier','Test Carrier'],
  ['mcc','Mobile country code','452'], ['mnc','Mobile network code','01'],
  ['iso_country','Country','vn'], ['wifi','Wi-Fi','{"ssid":"Test Wi-Fi"}'],
  ['gps','Location','{"lat":10.77,"lon":106.69,"accuracy":10}'],
  ['gps_accuracy','Location accuracy (m)','10'],
  ['idfa','Advertising ID','00000000-0000-0000-0000-000000000000'],
  ['idfv','Vendor ID','00000000-0000-0000-0000-000000000001'],
  ['user_agent','Web user agent','Test Browser'], ['webgl_vendor','WebGL vendor','Apple Inc.'],
  ['webgl_renderer','WebGL renderer','Apple GPU'], ['canvas','Canvas variation','true'],
  ['battery_level','Battery level (0..1)','0.8'], ['battery_state','Battery state (0..3)','1'],
  ['proximity','Proximity','false'], ['accelerometer','Acceleration','{"x":0,"y":0,"z":-1}'],
  ['gyroscope','Rotation','{"x":0,"y":0,"z":0}'],
  ['app_list','Hidden apps','{"hide":["com.example.test"]}'],
];
const DEVICE_NUMBERS = new Set(['screen_scale','gps_accuracy','battery_level','battery_state']);
const DEVICE_OBJECTS = new Set(['screen_resolution','wifi','gps','accelerometer','gyroscope','app_list']);
const DEVICE_BOOLEANS = new Set(['canvas','proximity']);

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
  setBadge('svc-mcp', 'gray', 'localhost:8765 ●');
  setBadge('svc-ide', 'green', '8890 ●');
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
async function deviceRequest(body, method = 'POST', path = '/api/spoof') {
  const response = await fetch(path, {method, headers:{'Content-Type':'application/json'},
    body: body === undefined ? undefined : JSON.stringify(body)});
  const value = await response.json();
  if (!response.ok || value.error) throw new Error(value.error || 'Request failed');
  return value;
}
function deviceMessage(text, failed = false) {
  const el = document.getElementById('device-message');
  el.textContent = text; el.style.color = failed ? '#c62828' : '#16743a';
}
async function loadSpoof() {
  try {
    _spoofData = await deviceRequest(undefined, 'GET');
    renderSpoof();
    await loadDeviceProfiles();
  } catch (e) { deviceMessage(e.message, true); }
}
function renderSpoof() {
  const modules = _spoofData.modules || {};
  const enabled = !!_spoofData.enabled;
  setBadge('spoof-status', enabled ? 'green' : 'gray', enabled ? 'enabled' : 'off');
  document.getElementById('device-enabled').checked = enabled;
  document.getElementById('device-apps').value = (_spoofData.selectedApps || []).join('\n');
  document.getElementById('spoof-tbody').innerHTML = DEVICE_FIELDS.map(([key,label,example]) => {
    const entry = modules[key] || {};
    const value = entry.value == null ? '' : typeof entry.value === 'object' ? JSON.stringify(entry.value) : String(entry.value);
    return `<tr data-key="${key}"><td><input type="checkbox" class="spoof-enabled" ${entry.enabled ? 'checked' : ''}></td>
      <td><label>${esc(label)}</label></td><td><input type="text" class="spoof-val" value="${esc(value)}" placeholder="${esc(example)}"></td></tr>`;
  }).join('');
}
async function saveSpoof() {
  try {
    const modules = {};
    document.querySelectorAll('#spoof-tbody tr[data-key]').forEach(row => {
      const key = row.dataset.key, enabled = row.querySelector('.spoof-enabled').checked;
      const raw = row.querySelector('.spoof-val').value.trim();
      const entry = {enabled};
      if (raw) {
        entry.value = DEVICE_OBJECTS.has(key) || DEVICE_BOOLEANS.has(key) || DEVICE_NUMBERS.has(key) ? JSON.parse(raw) : raw;
      } else if (enabled) throw new Error('Enter a value for ' + key);
      modules[key] = entry;
    });
    const selectedApps = [...new Set(document.getElementById('device-apps').value.split(/[\s,]+/).filter(Boolean))];
    await deviceRequest({enabled:document.getElementById('device-enabled').checked, selectedApps, modules});
    await loadSpoof();
    deviceMessage('Saved. Close and reopen selected apps to apply.');
    return true;
  } catch (e) { deviceMessage(e.message, true); return false; }
}
async function applyPreset(name) {
  if (!name) return;
  try {
    await deviceRequest({name}, 'POST', '/api/spoof/preset');
    document.getElementById('spoof-preset').value = '';
    await loadSpoof(); deviceMessage('Preset saved. Select apps and enable configuration to apply.');
  } catch (e) { deviceMessage(e.message, true); }
}
async function resetSpoof() {
  if (!confirm('Turn off and clear all device configuration?')) return;
  try { await deviceRequest(undefined, 'DELETE'); await loadSpoof(); deviceMessage('Configuration cleared.'); }
  catch (e) { deviceMessage(e.message, true); }
}

async function loadDeviceProfiles() {
  const value = await deviceRequest(undefined, 'GET', '/api/device-profiles');
  const select = document.getElementById('device-profile-select'), previous = select.value;
  select.replaceChildren();
  for (const name of value.profiles) { const option = document.createElement('option'); option.value = name; option.textContent = name; select.append(option); }
  if (value.profiles.includes(previous)) select.value = previous;
}
async function saveDeviceProfile() {
  if (!await saveSpoof()) return;
  try {
    const name = document.getElementById('device-profile-name').value.trim();
    await deviceRequest({action:'save', name}, 'POST', '/api/device-profiles');
    await loadDeviceProfiles(); document.getElementById('device-profile-select').value = name;
    deviceMessage('Device profile saved.');
  } catch (e) { deviceMessage(e.message, true); }
}
async function changeDeviceProfile(action) {
  const name = document.getElementById('device-profile-select').value;
  if (!name || (action === 'delete' && !confirm('Delete saved profile ' + name + '?'))) return;
  try {
    await deviceRequest({action, name}, 'POST', '/api/device-profiles');
    await loadSpoof();
    deviceMessage(action === 'apply' ? 'Profile applied. Reopen selected apps.' : 'Saved profile deleted.');
  } catch (e) { deviceMessage(e.message, true); }
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
if (new URLSearchParams(location.search).get('tab') === 'spoof') switchTab('spoof');
