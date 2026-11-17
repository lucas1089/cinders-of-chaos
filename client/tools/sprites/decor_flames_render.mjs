// Our driver for the pinned pixelfx render (O623). gen_decor_flames.py copies it into a sandbox copy of the pixelfx
// sources (src/, tools/lib/, package.json, LICENSE at the pinned commit) and runs it there with node; nothing else of
// pixelfx runs and nothing is installed. It does what `node tools/render.mjs ID --sheet --no-actor` does, except that the
// sheet holds the COLOUR layer only: the big additive light layer (the halo of the flame on the wall) is left out, the
// game has its own light (the light flag of the item). One PNG per effect, frames in a grid, and a JSON next to it.
//
//   node tools/decor_flames_render.mjs OUT_DIR fire/torch fire/brazier ...
//
// pixelfx: https://github.com/patch-gg/pixelfx, MIT, Copyright (c) 2026 Patch, Hugo Duprez (docs/CREDITS.md).
import { join } from "node:path";
import { mkdirSync, writeFileSync } from "node:fs";
import { loadEffect, renderFrames } from "./lib/fxlib.mjs";
import { encodePNG } from "./lib/png.mjs";

const [out, ...ids] = process.argv.slice(2);
if (!out || !ids.length) {
  console.error("usage: node tools/decor_flames_render.mjs OUT_DIR fire/torch ...");
  process.exit(1);
}
for (const id of ids) {
  const fx = await loadEffect(id);
  const r = renderFrames(fx, { actor: false, bg: "none" });
  const { w, h, n, fps, frames } = r;
  const cols = Math.min(n, Math.max(1, Math.ceil(Math.sqrt((n * h) / w)))), rows = Math.ceil(n / cols);
  const sheet = new Uint32Array(cols * w * rows * h);
  frames.forEach((f, i) => {
    const x0 = (i % cols) * w, y0 = Math.floor(i / cols) * h;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) sheet[(y0 + y) * cols * w + x0 + x] = f.raw[y * w + x];
  });
  const name = id.split("/")[1], dir = join(out, id);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, `${name}.png`), encodePNG(cols * w, rows * h, new Uint8Array(sheet.buffer)));
  writeFileSync(join(dir, `${name}.json`), JSON.stringify({ id, name, frames: n, frameSize: [w, h], columns: cols, fps, loop: !!fx.meta.loop, pivot: fx.meta.origin }, null, 1));
  console.log(`${id}  ${n} frames  ${w}x${h}`);
}
