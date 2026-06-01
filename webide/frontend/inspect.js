let _inspectOn = false;

async function toggleInspect() {
  _inspectOn = !_inspectOn;
  const btn = document.getElementById('btn-inspect');
  const overlay = document.getElementById('inspect-overlay');

  if (!_inspectOn) {
    btn.classList.remove('on');
    overlay.innerHTML = '';
    overlay.classList.remove('visible');
    return;
  }

  btn.classList.add('on');
  overlay.innerHTML = '<div class="inspect-loading">Đang quét chữ trên màn hình…</div>';
  overlay.classList.add('visible');

  try {
    const r = await fetch('/api/inspect');
    const data = await r.json();
    if (!r.ok || !data.items) {
      overlay.innerHTML = '<div class="inspect-error">Quét thất bại</div>';
      return;
    }
    renderInspectBoxes(data);
  } catch (e) {
    overlay.innerHTML = '<div class="inspect-error">Lỗi: ' + e.message + '</div>';
  }
}

function renderInspectBoxes(data) {
  const overlay = document.getElementById('inspect-overlay');
  const img = document.getElementById('screen-img');
  overlay.innerHTML = '';

  if (!img.naturalWidth) return;

  const rect = img.getBoundingClientRect();
  const wrap = img.parentElement.getBoundingClientRect();
  const offsetLeft = rect.left - wrap.left;
  const offsetTop  = rect.top  - wrap.top;
  const scaleX = rect.width  / data.width;
  const scaleY = rect.height / data.height;

  data.items.forEach(it => {
    if (!it.text || !it.text.trim()) return;
    const box = document.createElement('div');
    box.className = 'inspect-box';
    box.style.left   = (offsetLeft + it.x * scaleX) + 'px';
    box.style.top    = (offsetTop  + it.y * scaleY) + 'px';
    box.style.width  = (it.w * scaleX) + 'px';
    box.style.height = (it.h * scaleY) + 'px';
    box.title = it.text + ' (' + Math.round(it.confidence * 100) + '%)';
    box.innerHTML = '<span class="inspect-box-label">' +
      it.text.replace(/&/g,'&amp;').replace(/</g,'&lt;') + '</span>';
    box.onclick = (e) => {
      e.stopPropagation();
      const snippet = 'tapText("' + it.text.replace(/"/g,'\\"') + '")';
      navigator.clipboard.writeText(snippet);
      box.classList.add('copied');
      setTimeout(() => box.classList.remove('copied'), 700);
    };
    overlay.appendChild(box);
  });
}
