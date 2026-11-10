// Exercise the shipped admin script against HTTP/DOM boundaries, without a phone.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function element() {
  return {style:{}, value:'', textContent:'', innerHTML:'', checked:false, children:[],
    replaceChildren() { this.children = []; }, append(child) { this.children.push(child); }};
}
const nodes = new Map();
function node(id) { if (!nodes.has(id)) nodes.set(id, element()); return nodes.get(id); }
let rows = [], configuration = {enabled:false, selectedApps:[], modules:{}}, profiles = [];
let rejectConfiguration = false;
const requests = [];
const context = vm.createContext({
  console, URLSearchParams, location:{search:''}, confirm:() => true,
  document:{getElementById:node, createElement:element,
    querySelectorAll(selector) { return selector === '#spoof-tbody tr[data-key]' ? rows : []; }},
  async fetch(path, options = {}) {
    const method = options.method || 'GET';
    const body = options.body ? JSON.parse(options.body) : undefined;
    requests.push({path, method, body});
    let status = 200, value;
    if (path === '/api/device-info') value = {model:'fixture', ios:'15.8.4'};
    else if (path === '/api/spoof' && method === 'GET') value = structuredClone(configuration);
    else if (path === '/api/spoof' && method === 'POST') {
      if (rejectConfiguration) { status = 400; value = {error:'Fixture validation rejected configuration'}; }
      else { configuration = structuredClone(body); value = {ok:true}; }
    } else if (path === '/api/device-profiles' && method === 'GET') value = {profiles:[...profiles]};
    else if (path === '/api/device-profiles' && body.action === 'save') { profiles.push(body.name); value = {ok:true}; }
    else throw new Error('Unexpected fixture request: ' + method + ' ' + path);
    return {ok:status < 400, async json() { return value; }};
  },
});
vm.runInContext(fs.readFileSync(require.resolve('../webide/frontend/admin.js'), 'utf8'), context);
function row(key, value, enabled = true) {
  return {dataset:{key}, querySelector(selector) {
    return selector === '.spoof-enabled' ? {checked:enabled} : {value};
  }};
}
async function main() {
  await context.loadDashboard();
  node('device-enabled').checked = true;
  node('device-apps').value = 'com.example.Probe\ncom.example.Probe,com.example.Second';
  rows = [row('mnc','01'), row('gps','{"lat":10,"lon":106}'), row('canvas','false'), row('device_name','Phone "A"')];
  assert.equal(await context.saveSpoof(), true);
  assert.equal(configuration.modules.mnc.value, '01');
  assert.deepEqual(configuration.modules.gps.value, {lat:10,lon:106});
  assert.equal(configuration.modules.canvas.value, false);
  assert.deepEqual(configuration.selectedApps, ['com.example.Probe','com.example.Second']);
  assert.equal(requests.filter(r => r.path === '/api/spoof' && r.method === 'POST').length, 1);

  node('device-profile-name').value = 'Work';
  rejectConfiguration = true;
  await context.saveDeviceProfile();
  assert.equal(profiles.length, 0, 'A rejected configuration must not create a snapshot of stale values');
  assert.match(node('device-message').textContent, /Fixture validation rejected/);

  rejectConfiguration = false;
  rows = [row('gps','{"lat":')];
  const before = requests.length;
  assert.equal(await context.saveSpoof(), false);
  assert.equal(requests.length, before, 'Malformed nested field must not send a request');

  rows = [row('mnc','01')];
  await context.saveDeviceProfile();
  assert.deepEqual(profiles, ['Work']);
  assert.equal(node('device-profile-select').value, 'Work');
  assert.equal(node('device-profile-select').children[0].textContent, 'Work');
  console.log('Device UI configuration and profile HTTP contract tests passed');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
