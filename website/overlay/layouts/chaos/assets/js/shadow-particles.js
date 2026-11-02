/* Cinders of Chaos header script (the parent shell loads it by this name; website/README.md "Layout").
 * 1. On narrow screens the menu bar collapses into one Menu button. Without this script the bar stays open.
 * 2. A few faint embers drift up through the header scene. Off for prefers-reduced-motion. */
(function () {
  var nav = document.querySelector('.sh-nav');
  var frame = nav && nav.querySelector('.sh-nav-frame');
  var list = frame && frame.querySelector('.sh-nav-list');
  if (frame && list) {
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'chaos-menu-btn';
    btn.setAttribute('aria-expanded', 'false');
    if (!list.id) list.id = 'chaos-nav-list';
    btn.setAttribute('aria-controls', list.id);
    btn.innerHTML = '<i class="fa fa-bars" aria-hidden="true"></i><span>Menu</span>';
    btn.addEventListener('click', function () {
      var open = nav.classList.toggle('is-open');
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    frame.insertBefore(btn, frame.firstChild);
    document.documentElement.classList.add('chaos-nav-js');
  }
})();

(function () {
  if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  var canvas = document.getElementById('sh-canvas');
  if (!canvas || !canvas.getContext) return;
  var ctx = canvas.getContext('2d'), W = 0, H = 0, embers = [];
  function resize() {
    var hdr = document.getElementById('sh-header');
    W = canvas.width = hdr ? hdr.offsetWidth : window.innerWidth;
    H = canvas.height = hdr ? hdr.offsetHeight : 400;
  }
  function rnd(a, b) { return a + Math.random() * (b - a); }
  function ember(anywhere) {
    return { x: rnd(0, W), y: anywhere ? rnd(H * 0.3, H) : H + rnd(0, 40), vx: rnd(-0.12, 0.12), vy: rnd(-0.45, -0.2),
             r: rnd(0.6, 1.3), life: 0, max: rnd(360, 640), hue: rnd(14, 34), wob: rnd(0.008, 0.02), off: rnd(0, 6.3) };
  }
  resize();
  var t; window.addEventListener('resize', function () { clearTimeout(t); t = setTimeout(resize, 200); });
  var n = window.innerWidth < 760 ? 6 : 14;
  for (var i = 0; i < n; i++) { var e = ember(true); e.life = rnd(0, e.max); embers.push(e); }
  function tick() {
    if (document.hidden) { requestAnimationFrame(tick); return; }
    ctx.clearRect(0, 0, W, H);
    for (var i = 0; i < embers.length; i++) {
      var e = embers[i];
      e.life++; e.x += e.vx + Math.sin(e.life * e.wob + e.off) * 0.15; e.y += e.vy;
      if (e.life > e.max || e.y < -10) { embers[i] = ember(false); continue; }
      var a = Math.sin(Math.PI * Math.min(1, e.life / e.max)) * 0.5;
      ctx.fillStyle = 'hsla(' + e.hue + ',90%,62%,' + a + ')';
      ctx.beginPath(); ctx.arc(e.x, e.y, e.r, 0, 6.2832); ctx.fill();
    }
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
})();
