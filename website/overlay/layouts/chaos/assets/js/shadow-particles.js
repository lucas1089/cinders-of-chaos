/* Project Chaos: embers rising through the header (replaces the parent layout's violet motes). */
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
    return { x: rnd(0, W), y: anywhere ? rnd(0, H) : H + rnd(0, 40), vx: rnd(-0.25, 0.25), vy: rnd(-0.9, -0.3),
             r: rnd(0.6, 2.2), life: 0, max: rnd(240, 520), hue: rnd(8, 38), wob: rnd(0.01, 0.03), off: rnd(0, 6.3) };
  }
  resize();
  var t; window.addEventListener('resize', function () { clearTimeout(t); t = setTimeout(resize, 200); });
  var n = window.innerWidth < 760 ? 24 : 46;
  for (var i = 0; i < n; i++) { var e = ember(true); e.life = rnd(0, e.max); embers.push(e); }
  function tick() {
    if (document.hidden) { requestAnimationFrame(tick); return; }
    ctx.clearRect(0, 0, W, H);
    ctx.globalCompositeOperation = 'lighter';
    for (var i = 0; i < embers.length; i++) {
      var e = embers[i];
      e.life++; e.x += e.vx + Math.sin(e.life * e.wob + e.off) * 0.3; e.y += e.vy;
      var a = Math.sin(Math.PI * Math.min(1, e.life / e.max)) * 0.85;
      if (e.life > e.max || e.y < -10) { embers[i] = ember(false); continue; }
      var g = ctx.createRadialGradient(e.x, e.y, 0, e.x, e.y, e.r * 4);
      g.addColorStop(0, 'hsla(' + e.hue + ',100%,70%,' + a + ')');
      g.addColorStop(0.4, 'hsla(' + e.hue + ',100%,50%,' + a * 0.5 + ')');
      g.addColorStop(1, 'hsla(' + e.hue + ',100%,40%,0)');
      ctx.fillStyle = g;
      ctx.beginPath(); ctx.arc(e.x, e.y, e.r * 4, 0, 6.2832); ctx.fill();
    }
    ctx.globalCompositeOperation = 'source-over';
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
})();
