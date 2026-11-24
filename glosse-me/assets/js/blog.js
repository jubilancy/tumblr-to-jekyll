/* blog.js - dark/light toggle, masonry/grid tiles, load-more on scroll.
   Small on purpose: no libraries. Tiles reserve their space from the image
   width/height already in each post, so nothing jumps while images load. */
(function () {
  'use strict';
  var B = window.BLOG || { base: '', batch: 24 };
  var root = document.documentElement;

  function store(k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) {} return null; }

  /* ---------- light / dark ---------- */
  var tbtn = document.querySelector('.theme-toggle');
  function paintToggle() { if (tbtn) tbtn.textContent = root.getAttribute('data-theme') === 'dark' ? '☾' : '☀'; }
  paintToggle();
  if (tbtn) tbtn.addEventListener('click', function () {
    var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next); store('blog-theme', next); paintToggle();
  });

  /* ---------- tiles ---------- */
  var box = document.getElementById('tiles');
  if (!box) return;

  var layout = store('blog-layout') === 'grid' ? 'grid' : 'masonry';   // masonry unless you chose grid
  var tiles = [].slice.call(box.querySelectorAll('.tile'));
  var seen = {};
  tiles.forEach(function (t) { seen[t.getAttribute('data-id')] = 1; });
  var cols = [], colH = [];

  function colCount() {
    var w = box.clientWidth || window.innerWidth;
    return w >= 1100 ? 4 : w >= 700 ? 3 : 2;
  }
  function heightOf(t) {            // height relative to column width, from --ar "w / h"
    var m = /([\d.]+)\s*\/\s*([\d.]+)/.exec(t.style.getPropertyValue('--ar'));
    return m ? (+m[2]) / (+m[1]) : 0.55;
  }
  function place(t) {               // masonry: drop the tile into the shortest column
    var k = 0;
    for (var i = 1; i < colH.length; i++) if (colH[i] < colH[k]) k = i;
    cols[k].appendChild(t);
    colH[k] += heightOf(t) + 0.03;
  }
  function build() {
    box.setAttribute('data-layout', layout);
    tiles.forEach(function (t) { if (t.parentNode) t.parentNode.removeChild(t); });
    box.textContent = '';
    cols = []; colH = [];
    if (layout === 'masonry') {
      var n = colCount();
      for (var i = 0; i < n; i++) {
        var c = document.createElement('div'); c.className = 'col';
        box.appendChild(c); cols.push(c); colH.push(0);
      }
      box.classList.add('ready');
      tiles.forEach(place);
    } else {
      box.classList.remove('ready');
      tiles.forEach(function (t) { box.appendChild(t); });
    }
    paintSwitch();
  }

  /* layout switcher (hidden until there are tiles to switch) */
  var sw = document.querySelector('.layout-switch');
  var btns = [].slice.call(document.querySelectorAll('[data-layout-btn]'));
  function paintSwitch() {
    btns.forEach(function (b) { b.setAttribute('aria-pressed', String(b.getAttribute('data-layout-btn') === layout)); });
  }
  if (sw) sw.hidden = false;
  btns.forEach(function (b) {
    b.addEventListener('click', function () {
      var next = b.getAttribute('data-layout-btn');
      if (next === layout) return;
      layout = next; store('blog-layout', layout); build();
    });
  });

  var rz;
  window.addEventListener('resize', function () {
    clearTimeout(rz);
    rz = setTimeout(function () { if (layout === 'masonry' && colCount() !== cols.length) build(); }, 150);
  });

  /* ---------- building tiles from posts.json (keep in step with _includes/tile.html) ---------- */
  var MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  function nice(d) { var p = d.split('-'); return MONTHS[+p[1] - 1] + ' ' + (+p[2]) + ', ' + p[0]; }
  function thumb(url) {
    var tx = /\.gif($|\?)/.test(url) ? 'so_0,c_limit,w_480,f_jpg,q_auto' : 'c_limit,w_480,f_auto,q_auto';
    return url.replace('/image/upload/', '/image/upload/' + tx + '/');
  }
  function makeTile(p) {
    var a = document.createElement('a');
    a.className = 'tile'; a.href = p.u; a.setAttribute('data-id', p.i);
    if (p.c) {
      a.style.setProperty('--ar', p.w + ' / ' + p.h);
      var img = new Image();
      img.loading = 'lazy'; img.decoding = 'async'; img.width = p.w; img.height = p.h; img.alt = '';
      img.src = thumb(p.c);
      a.appendChild(img);
      if (p.n > 1) { var s = document.createElement('span'); s.className = 'badge'; s.textContent = '⧉ ' + p.n; a.appendChild(s); }
    } else {
      a.className += ' tile-text';
      var t = document.createElement('time'); t.textContent = nice(p.d);
      var q = document.createElement('p'); q.textContent = p.x || '';
      a.appendChild(t); a.appendChild(q);
    }
    return a;
  }
  function add(items) {
    items.forEach(function (p) {
      var t = makeTile(p); tiles.push(t);
      if (layout === 'masonry') place(t); else box.appendChild(t);
    });
  }

  build();

  /* ---------- load more as you scroll (home page only) ---------- */
  if (box.getAttribute('data-feed') !== 'posts') return;
  var more = document.getElementById('more');
  var queue = null, busy = false, io = null;

  function withQueue(cb) {
    if (queue) return cb();
    fetch(B.base + '/posts.json').then(function (r) { return r.json(); }).then(function (list) {
      queue = list.filter(function (p) { return !seen[p.i]; });
      cb();
    }).catch(function () { more.textContent = 'could not load more posts'; busy = false; });
  }
  function next() {
    if (busy) return; busy = true;
    withQueue(function () {
      var items = queue.splice(0, B.batch || 24);
      items.forEach(function (p) { seen[p.i] = 1; });
      add(items);
      busy = false;
      if (!queue.length) { more.textContent = '· end ·'; if (io) io.disconnect(); return; }
      io.unobserve(more); requestAnimationFrame(function () { io.observe(more); });   // re-check if still in view
    });
  }
  if ('IntersectionObserver' in window) {
    io = new IntersectionObserver(function (es) { if (es[0].isIntersecting) next(); }, { rootMargin: '1200px 0px' });
    io.observe(more);
  } else {
    more.innerHTML = '<a href="' + B.base + '/archive/">see the archive</a>';
  }
})();
