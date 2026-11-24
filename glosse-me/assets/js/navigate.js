/* navigate.js - search over /posts.json (loaded the first time you type). */
(function () {
  'use strict';
  var B = window.BLOG || { base: '' };
  var q = document.getElementById('q'), out = document.getElementById('results'), st = document.getElementById('status');
  if (!q) return;
  var data = null, timer;

  function load(cb) {
    if (data) return cb();
    st.textContent = 'loading…';
    fetch(B.base + '/posts.json').then(function (r) { return r.json(); }).then(function (d) {
      data = d; st.textContent = ''; cb();
    }).catch(function () { st.textContent = 'could not load the search index'; });
  }
  function hay(p) {
    return [p.x, (p.g || []).join(' '), (p.t || []).join(' '), (p.k || []).join(' '), p.d, p.y].join(' ').toLowerCase();
  }
  function run() {
    var s = q.value.trim().toLowerCase();
    out.textContent = '';
    if (!s) { st.textContent = ''; return; }
    load(function () {
      var words = s.split(/\s+/);
      var hits = data.filter(function (p) {
        var h = p._h || (p._h = hay(p));
        return words.every(function (w) { return h.indexOf(w) > -1; });
      });
      st.textContent = hits.length + ' result' + (hits.length === 1 ? '' : 's') + (hits.length > 60 ? ' (showing 60)' : '');
      hits.slice(0, 60).forEach(function (p) {
        var li = document.createElement('li'), a = document.createElement('a');
        a.href = p.u;
        var when = document.createElement('span'); when.className = 'when'; when.textContent = p.d;
        var txt = document.createElement('span'); txt.textContent = p.x || '(' + p.y + ')';
        var kind = document.createElement('span'); kind.className = 'kind'; kind.textContent = p.n ? '⧉ ' + p.n : p.y;
        a.appendChild(when); a.appendChild(txt); a.appendChild(kind);
        li.appendChild(a); out.appendChild(li);
      });
    });
  }
  q.addEventListener('input', function () { clearTimeout(timer); timer = setTimeout(run, 150); });
  var m = /[?&]q=([^&]+)/.exec(location.search);
  if (m) { q.value = decodeURIComponent(m[1].replace(/\+/g, ' ')); run(); }
  q.focus();
})();
