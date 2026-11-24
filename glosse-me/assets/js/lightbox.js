/* lightbox.js - click a picture on a post to see it full size; arrows / Esc work. */
(function () {
  'use strict';
  var imgs = [].slice.call(document.querySelectorAll('.post-body img[data-full]'));
  if (!imgs.length) return;
  var idx = 0, box = null, big = null, count = null;

  function show(i) {
    idx = (i + imgs.length) % imgs.length;
    big.src = imgs[idx].getAttribute('data-full');
    big.alt = imgs[idx].alt || '';
    count.textContent = (idx + 1) + ' / ' + imgs.length;
  }
  function close() {
    if (!box) return;
    document.removeEventListener('keydown', onKey);
    box.remove(); box = null; document.body.style.overflow = '';
  }
  function onKey(e) {
    if (e.key === 'Escape') close();
    else if (e.key === 'ArrowRight') show(idx + 1);
    else if (e.key === 'ArrowLeft') show(idx - 1);
  }
  function btn(cls, label, text, fn) {
    var b = document.createElement('button');
    b.type = 'button'; b.className = cls; b.setAttribute('aria-label', label); b.textContent = text;
    b.addEventListener('click', function (e) { e.stopPropagation(); fn(); });
    return b;
  }
  function open(i) {
    box = document.createElement('div');
    box.className = 'lightbox'; box.setAttribute('role', 'dialog'); box.setAttribute('aria-modal', 'true');
    big = document.createElement('img');
    count = document.createElement('div'); count.className = 'count';
    box.appendChild(big);
    if (imgs.length > 1) {
      box.appendChild(btn('prev', 'previous image', '‹', function () { show(idx - 1); }));
      box.appendChild(btn('next', 'next image', '›', function () { show(idx + 1); }));
      box.appendChild(count);
    }
    box.appendChild(btn('close', 'close', '×', close));
    box.addEventListener('click', close);
    document.body.appendChild(box);
    document.body.style.overflow = 'hidden';
    document.addEventListener('keydown', onKey);
    show(i);
  }
  imgs.forEach(function (im, i) { im.addEventListener('click', function () { open(i); }); });
})();
