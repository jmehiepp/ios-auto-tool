const LOG_COLORS = {
  INFO:  '#4fc3f7',
  WARN:  '#ffb74d',
  ERROR: '#ef5350',
  LUA:   '#a5d6a7',
};
const LOG_LIMIT = 1000;

let logContainer = null;

document.addEventListener('DOMContentLoaded', () => {
  logContainer = document.getElementById('log-output');
});

function appendLog(level, text) {
  if (!logContainer) logContainer = document.getElementById('log-output');
  const line = document.createElement('div');
  line.className = 'log-line';
  line.style.color = LOG_COLORS[level] || '#ccc';

  const ts = new Date().toLocaleTimeString('en-GB', { hour12: false });
  line.textContent = `${ts} [${level}] ${text}`;

  logContainer.appendChild(line);
  logContainer.scrollTop = logContainer.scrollHeight;

  // Keep at most LOG_LIMIT lines
  while (logContainer.childElementCount > LOG_LIMIT) {
    logContainer.removeChild(logContainer.firstElementChild);
  }
}

function clearLog() {
  if (!logContainer) logContainer = document.getElementById('log-output');
  logContainer.innerHTML = '';
}

function initLogSocket() {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const url = `${proto}//${location.host}/ws/logs`;
  let ws;

  function connect() {
    ws = new WebSocket(url);

    ws.onopen = () => appendLog('INFO', 'Log stream connected');

    ws.onmessage = (e) => {
      try {
        const msg = JSON.parse(e.data);
        const level = msg.level || 'INFO';
        const data  = msg.data  || '';
        appendLog(level, data);
        // Detect script finish to re-enable Run button
        if (level === 'INFO' && data.startsWith('Script finished')) {
          setRunning(false);
        }
      } catch (_) {
        appendLog('INFO', e.data);
      }
    };

    ws.onclose = () => {
      appendLog('WARN', 'Log stream disconnected — reconnecting in 3s...');
      setTimeout(connect, 3000);
    };

    ws.onerror = () => ws.close();
  }

  connect();
}
