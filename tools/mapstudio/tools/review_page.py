"""Writes areas/<batch>/index.html: a review viewer for a batch of rendered maps (tools/batch.py).

python -B run.py tools/review_page.py <batch>
Open the file in a browser: zoom with the wheel, drag to pan, hover for tile coordinates, click to add a note.
Notes stay in the browser (localStorage) and the Export box gives them as text to paste back.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from common import ROOT

PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Map Review</title>
<style>
:root { --bg:#f6f5f2; --panel:#ffffff; --ink:#1d1d1f; --muted:#6b6b70; --line:#dcdad5; --accent:#2f6fde;
        --pin:#e2483d; --sel:#e8eefb; }
@media (prefers-color-scheme: dark) { :root { --bg:#161618; --panel:#1f1f22; --ink:#ececee; --muted:#9a9aa0;
        --line:#333338; --accent:#6c9cff; --pin:#ff6b5f; --sel:#25304a; } }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font:14px/1.4 system-ui, sans-serif; display:grid;
       grid-template-columns: 300px 1fr; height:100vh; overflow:hidden; }
aside { background:var(--panel); border-right:1px solid var(--line); display:flex; flex-direction:column; min-height:0; }
aside h1 { font-size:15px; margin:14px 14px 4px; }
aside .hint { color:var(--muted); font-size:12px; margin:0 14px 10px; }
.maps { overflow:auto; flex:0 0 auto; max-height:42vh; border-top:1px solid var(--line); }
.map { padding:8px 14px; border-bottom:1px solid var(--line); cursor:pointer; }
.map.on { background:var(--sel); }
.map b { font-size:13px; } .map small { display:block; color:var(--muted); font-size:11px; word-break:break-word; }
.notes { flex:1; overflow:auto; border-top:1px solid var(--line); padding:8px 14px; min-height:0; }
.note { display:flex; gap:6px; align-items:flex-start; padding:4px 0; border-bottom:1px dashed var(--line); font-size:12px; }
.note span { flex:1; cursor:pointer; } .note button { border:0; background:none; color:var(--muted); cursor:pointer; }
.export { border-top:1px solid var(--line); padding:8px 14px 14px; }
.export textarea { width:100%; height:90px; font:11px/1.3 ui-monospace, monospace; background:var(--bg); color:var(--ink);
       border:1px solid var(--line); border-radius:6px; }
.export button, .bar button { background:var(--accent); color:#fff; border:0; border-radius:6px; padding:5px 10px; cursor:pointer; }
main { position:relative; overflow:hidden; cursor:crosshair; }
#stage { position:absolute; left:0; top:0; transform-origin:0 0; }
#stage img { display:block; image-rendering:pixelated; user-select:none; -webkit-user-drag:none; }
.pin { position:absolute; width:14px; height:14px; margin:-7px 0 0 -7px; border-radius:50%; background:var(--pin);
       border:2px solid #fff; box-shadow:0 0 0 1px #0006; }
.bar { position:absolute; left:12px; top:12px; display:flex; gap:8px; align-items:center; background:var(--panel);
       border:1px solid var(--line); border-radius:8px; padding:6px 10px; font-size:12px; }
.bar code { font-size:12px; }
.box { position:absolute; outline:2px solid var(--accent); pointer-events:none; }
@media (max-width: 760px) { body { grid-template-columns:1fr; grid-template-rows: 40vh 1fr; }
  aside { overflow:auto; border-right:0; border-bottom:1px solid var(--line); }
  .maps { max-height:none; overflow:visible; } .notes { overflow:visible; } .map small:last-child { display:none; } }
</style></head><body>
<aside>
  <h1>Map review: __BATCH__</h1>
  <p class="hint">Wheel to zoom, drag to pan, click a spot to note an issue. Coordinates are ground-floor tiles; a
  spot on a raised top of level k is drawn k tiles up-left of its tile.</p>
  <div class="maps" id="maps"></div>
  <div class="notes" id="notes"></div>
  <div class="export"><button id="copy">Copy notes</button> <span class="hint" id="count"></span>
    <textarea id="out" readonly></textarea></div>
</aside>
<main id="view"><div id="stage"><img id="img" alt=""></div>
  <div class="bar"><code id="pos">hover the map</code><button id="fit">Fit</button></div></main>
<script>
const MAPS = __MAPS__, BATCH = "__BATCH__", TILE = 32;
const KEY = "map-review-" + BATCH;
let notes = []; try { notes = JSON.parse(localStorage.getItem(KEY) || "[]"); } catch (e) {}
const save = () => { try { localStorage.setItem(KEY, JSON.stringify(notes)); } catch (e) {} };
let cur = 0, scale = 1, ox = 0, oy = 0;
const view = document.getElementById("view"), stage = document.getElementById("stage"), img = document.getElementById("img");
const box = document.createElement("div"); box.className = "box"; stage.appendChild(box);
function apply() { stage.style.transform = `translate(${ox}px,${oy}px) scale(${scale})`; }
function fit() { const r = view.getBoundingClientRect(); scale = Math.min(r.width / img.naturalWidth, r.height / img.naturalHeight);
  ox = (r.width - img.naturalWidth * scale) / 2; oy = (r.height - img.naturalHeight * scale) / 2; apply(); }
function tileAt(ev) { const r = view.getBoundingClientRect(); const px = (ev.clientX - r.left - ox) / scale,
  py = (ev.clientY - r.top - oy) / scale; const m = MAPS[cur];
  return { px, py, x: m.x0 + Math.floor(px / TILE), y: m.y0 + Math.floor(py / TILE),
           inside: px >= 0 && py >= 0 && px < img.naturalWidth && py < img.naturalHeight }; }
function load(i) { cur = i; img.onload = fit; img.src = MAPS[i].img; renderList(); renderNotes(); }
function renderList() { document.getElementById("maps").innerHTML = MAPS.map((m, i) =>
  `<div class="map ${i === cur ? "on" : ""}" data-i="${i}"><b>${m.name}</b> <small>${m.knobs}</small><small>${m.summary}</small></div>`).join("");
  document.querySelectorAll(".map").forEach(el => el.onclick = () => load(+el.dataset.i)); }
function renderNotes() { const m = MAPS[cur];
  stage.querySelectorAll(".pin").forEach(p => p.remove());
  notes.forEach((n, k) => { if (n.map !== m.name) return; const p = document.createElement("div"); p.className = "pin";
    p.style.left = n.px + "px"; p.style.top = n.py + "px"; p.title = n.text; stage.appendChild(p); });
  document.getElementById("notes").innerHTML = notes.map((n, k) => n.map !== m.name ? "" :
    `<div class="note"><span data-k="${k}">${n.x},${n.y}: ${n.text.replace(/</g, "&lt;")}</span><button data-d="${k}" title="Delete">x</button></div>`).join("")
    || '<p class="hint">No notes on this map yet.</p>';
  document.querySelectorAll(".note span").forEach(el => el.onclick = () => { const n = notes[+el.dataset.k];
    const r = view.getBoundingClientRect(); scale = Math.max(scale, 1); ox = r.width / 2 - n.px * scale; oy = r.height / 2 - n.py * scale; apply(); });
  document.querySelectorAll(".note button").forEach(el => el.onclick = () => { notes.splice(+el.dataset.d, 1); save(); renderNotes(); });
  const all = notes.map(n => `${n.map} @ ${n.x},${n.y}: ${n.text}`).join("\\n");
  document.getElementById("out").value = all; document.getElementById("count").textContent = notes.length + " notes in all"; }
view.addEventListener("wheel", ev => { ev.preventDefault(); const r = view.getBoundingClientRect();
  const mx = ev.clientX - r.left, my = ev.clientY - r.top, f = ev.deltaY < 0 ? 1.2 : 1 / 1.2;
  const ns = Math.min(8, Math.max(0.05, scale * f)); ox = mx - (mx - ox) * ns / scale; oy = my - (my - oy) * ns / scale; scale = ns; apply(); }, { passive: false });
let drag = null;
view.addEventListener("mousedown", ev => { drag = { x: ev.clientX, y: ev.clientY, ox, oy, moved: false }; });
window.addEventListener("mousemove", ev => { const t = tileAt(ev);
  if (t.inside) { document.getElementById("pos").textContent = `tile ${t.x},${t.y}`;
    box.style.left = Math.floor(t.px / TILE) * TILE + "px"; box.style.top = Math.floor(t.py / TILE) * TILE + "px";
    box.style.width = box.style.height = TILE + "px"; }
  if (!drag) return; const dx = ev.clientX - drag.x, dy = ev.clientY - drag.y;
  if (Math.abs(dx) + Math.abs(dy) > 4) drag.moved = true; ox = drag.ox + dx; oy = drag.oy + dy; apply(); });
window.addEventListener("mouseup", ev => { const d = drag; drag = null; if (!d || d.moved) return; const t = tileAt(ev);
  if (!t.inside) return; const text = prompt(`Note for ${MAPS[cur].name} at ${t.x},${t.y}:`); if (!text) return;
  notes.push({ map: MAPS[cur].name, x: t.x, y: t.y, px: t.px, py: t.py, text }); save(); renderNotes(); });
document.getElementById("fit").onclick = fit;
document.getElementById("copy").onclick = () => { const o = document.getElementById("out"); o.select();
  navigator.clipboard ? navigator.clipboard.writeText(o.value) : document.execCommand("copy"); };
window.addEventListener("resize", fit);
load(0);
</script></body></html>
"""


def main():
    batch = sys.argv[1]
    folder = ROOT / "areas" / batch
    maps = []
    for d in sorted(p for p in folder.iterdir() if p.is_dir()):
        renders = sorted(d.glob("render*.png"), key=lambda p: p.stat().st_mtime)
        if not renders or not (d / "area.txt").exists():
            continue
        meta = json.loads((d / "area.txt").read_text(encoding="utf-8").splitlines()[0][1:])
        text = (d / "summary.txt").read_text(encoding="utf-8", errors="ignore") if (d / "summary.txt").exists() else ""
        lines = [ln.strip() for ln in text.splitlines()]
        knobs = lines[0].removeprefix("knobs:").strip() if lines else ""
        land = next((ln.split(" ", 1)[1] for ln in lines if " land " in ln), "")
        acc = next((ln for ln in lines if ln.startswith("access:")), "")
        maps.append({"name": d.name, "img": f"{d.name}/{renders[-1].name}", "x0": 1000, "y0": 1000,
                     "knobs": knobs, "summary": (land + " | " + acc)[:400]})
    html = PAGE.replace("__MAPS__", json.dumps(maps)).replace("__BATCH__", batch)
    (folder / "index.html").write_text(html, encoding="utf-8")
    print(folder / "index.html", len(maps), "maps")


if __name__ == "__main__":
    main()
