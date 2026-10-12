# Pixel art studio: creatures, items and floors in Tibia's perspective

> **For the person:** make an empty folder, put this file in it, open your AI agent in that folder (Claude Code is the
> recommended one) and say: **"read PIXEL-ART-STUDIO.md and set up the studio"**. It checks what your machine is
> missing, writes the tools, tests them, and then you use the commands `/creature`, `/item-sheet` and `/floor`.
>
> **For the AI:** this file is your task. Follow the sections in order. Talk to the person in their own language.

---

## 1. What this is

A set of tools and rules for making **beautiful, consistent** pixel art in Tibia's oblique perspective (the 45° camera
from above, height drawn up and to the left, the light coming from the top-left). It all came out of a game project,
was redone many times because the artist rejected it, and each rule below cost at least one round.

| command | what it makes | who draws |
|---|---|---|
| `/creature` | a monster in 4 directions, standing (idle) and walking, on a single sheet | the SHAPE is Python; PixelLab only repaints it; the animation reuses the painting |
| `/item-sheet` | a sheet of up to 16 items (64 or 32 px), cut into one PNG per item | PixelLab, guided by a tested prompt |
| `/floor` | a ground that repeats with no seam, with variation and borders | pure Python |

**The central idea (it is what makes the creatures beautiful):** an image AI creating from scratch forgets the
perspective and draws the frontal RPG view. So the creature is born as a **small 3D model in Python** (signed distance
shapes), drawn with the right projection, the right light and the right outline; PixelLab receives that shape and
**only repaints it** (texture, detail); and the animation asks the AI for no frames at all: each frame takes the posed
shape and fetches each pixel from the standing painting, at the same point of the same part. Nothing "boils" between
frames.

## 2. What the person needs (check each item BEFORE writing files)

| | required? | how to check / get it |
|---|---|---|
| **Python 3.10+** | yes | `python --version` |
| **numpy, scipy, pillow** | yes | `python -m pip install -r requirements.txt` (after creating the file, section 4) |
| **a PixelLab account with an API token** | yes, for `/creature` (the repaint) and `/item-sheet` | <https://www.pixellab.ai> → account → API token. The repaint uses **Edit images (Pro)** and the sheet uses **Create image (Pro)**: check that the person's plan gives access to the Pro models and what each generation costs. Docs: <https://api.pixellab.ai/v2/llms.txt> |
| **the token, stored** | yes | the environment variable `PIXELLAB_API_TOKEN`, or the first line of the file `.pixellab_token` at the studio root (it is in `.gitignore`). **Never print the token**, nor write it into any other file |
| **the PixelLab MCP** | no (recommended) | gives the agent PixelLab's character, animation and tileset tools. In Claude Code: `claude mcp add --transport http pixellab https://api.pixellab.ai/mcp --header "Authorization: Bearer <TOKEN>"` (the person runs it, with their own token), or the guide at <https://www.pixellab.ai/vibe-coding>. ⚠️ The MCP does **not** have the image editing the creature needs: that is why the kit talks to the REST API directly (`kit/pixellab.py`) |
| **an agent that reads images** | yes | the rules say to OPEN the previews and judge them. Claude Code reads PNGs with its file-reading tool |
| **Aseprite** | no | good for retouching by hand and stepping through the GIFs frame by frame |

If the token is missing, set the studio up anyway: the creature's shape and animation preview, and the floors, work
without PixelLab. Tell the person what is on hold until they have the token.

## 3. The folder you will set up

```
<studio folder>/
├── PIXEL-ART-STUDIO.md             # this file (it stays)
├── README.md                       # the summary for the person
├── NOTES.md                        # the journal: one section per creature/set/floor, and every mistake that cost a round
├── requirements.txt
├── .gitignore
├── kit/
│   ├── tibia_view.py               # Tibia's projection, the distance primitives, the colour ramps
│   ├── creature_kit.py             # the creature's SHAPE, the ramp painting, the PixelLab repaint, the review
│   ├── creature_anim.py            # the pose, the reprojection of the painting, the sheet and the GIFs
│   ├── pixellab.py                 # PixelLab's REST API (Edit images Pro, Create image Pro, balance)
│   ├── items.py                    # generate the item sheet, cut it, board
│   └── tiles.py                    # the periodic block of the floors
├── creatures/
│   └── _template.py                # the template of every creature (the example is a beetle)
├── floors/                         # one script per floor (empty at first)
├── prompts/items/                  # the item sheet prompts (empty at first)
├── out/                            # everything generated (in .gitignore or not: the person decides)
└── .claude/skills/
    ├── creature/SKILL.md
    ├── item-sheet/SKILL.md
    ├── item-sheet/base-prompt.md
    └── floor/SKILL.md
```

**Other agents:** the skills are Markdown with a YAML header. In Claude Code they become the commands `/creature`,
`/item-sheet` and `/floor` on their own. In Cursor, put the same text in `.cursor/rules/<name>.mdc`; in Codex and
similar, join the three into an `AGENTS.md` with one heading per command. The text does not change.

## 4. How to set it up (for the AI)

1. Check section 2 and tell the person what is missing, with the command for each thing. Do not ask for the token in
   the chat: ask them to store it themselves in the environment variable or in `.pixellab_token`.
2. Create the folders of section 3.
3. For **each** file of section 6, create the file at the path in its heading with the content of the block **exactly
   as it is** — byte for byte, without summarising, without "improving", without renaming. The content is what lies
   between the opening `~~~~~` line and the closing one (the `~~~~~` lines are not part of it). UTF-8, LF line endings.
   Write long files with your file-writing tool, not with a heredoc in the terminal (long heredocs arrive truncated).
4. `python -m pip install -r requirements.txt`.
5. **The test** (it spends no PixelLab):
   ```
   cp creatures/_template.py creatures/beetle.py
   python creatures/beetle.py shape
   python creatures/beetle.py preview
   ```
   `shape` prints the 4 views at about 23×24 px and writes `out/beetle/beetle_python_4dir_x3.png`; `preview` writes
   `out/beetle/beetle_shape_idle8_walking8.png` and says `idle frame 1 vs the painting: 4 px differ` (a few pixels).
   OPEN both images: a blue six-legged beetle, seen from above on the diagonal, in the four directions, with its legs
   moving in the walking rows. If something fails, the cause is in the copy of some file: compare it with the block.
6. If there is a token: `python -c "import sys; sys.path.insert(0, 'kit'); import pixellab; print(pixellab.balance())"`
   must answer the balance (without printing the token). **Do not spend generations on the test.**
7. Delete `creatures/beetle.py` and `out/beetle/` (they were only the test), and show the person the three commands
   with an example request for each ("/creature a pirate frog with a sabre", "/item-sheet 8 alchemist potions",
   "/floor dark grass with tufts and small flowers").

## 5. The rules for everything

- **Art from scratch.** A commercial game's sprite (Tibia belongs to CipSoft) is a ruler for size, perspective and fit;
  none of its pixels go into the art. It matters if the person ever publishes or sells the game.
- **Judge at real size.** Every preview exists at 1× next to the enlarged one; what only reads well enlarged is not
  done.
- **Show only what is good.** Open every image before showing it; if it is bad, redo the SHAPE or the prompt.
- **The approved is not "improved".** A new variant gets a new name; never overwrite a sheet the person approved.
- **Warn before spending.** Every PixelLab call spends balance: say how many you will make and show the balance
  before and after.
- **The journal.** Each creature, set and floor gets a section in `NOTES.md`: the request, what was chosen, and every
  mistake with its why. The skills' rules grew this way; add the new ones to them too.

## 6. The files

### `README.md`

~~~~~
# Pixel art studio

Three commands, in Tibia's oblique perspective:

| command | example |
|---|---|
| `/creature` | `/creature a pirate frog with a sabre` |
| `/item-sheet` | `/item-sheet 8 alchemist potions` |
| `/floor` | `/floor dark grass with tufts and small flowers` |

What is generated goes to `out/`. The PixelLab token lives in `PIXELLAB_API_TOKEN` or in `.pixellab_token` (never in
git). The why of every rule is in the skills (`.claude/skills/`) and in `PIXEL-ART-STUDIO.md`; the journal, in
`NOTES.md`.

A creature, by hand:

```
cp creatures/_template.py creatures/<name>.py      # and replace the beetle with the creature
python creatures/<name>.py shape                   # the shape
python creatures/<name>.py preview                 # the animation on the shape (no PixelLab)
python creatures/<name>.py edit 3                  # 3 repaints on PixelLab (spends balance)
python creatures/<name>.py pick out/<name>/edit/edit_v2.png
python creatures/<name>.py animate                 # the sheet <name>_idle8_walking8.png and the GIFs
```
~~~~~

### `NOTES.md`

~~~~~
# Studio notes

One section per creature, item set or floor: the request (in the words of whoever asked, with the date), what was
chosen and why, and every mistake that cost a round. A new rule that holds for everything also goes into the skill.
~~~~~

### `requirements.txt`

~~~~~
numpy>=1.24
scipy>=1.10
pillow>=10.0
~~~~~

### `.gitignore`

~~~~~
.pixellab_token
__pycache__/
*.pyc
~~~~~

### `kit/tibia_view.py`

~~~~~
"""The Tibia oblique projection, as a tiny ray-marcher of signed distances.

A point of the world at height h is drawn h/1.5 UP and h/1.5 to the LEFT of where it stands; the ground is seen from
straight above, never squashed; you see the top and the SOUTH and EAST faces of things. The light comes from the
top-left. Everything here works on numpy arrays of points (N, 3): body coordinates u forward, v the creature's right,
h up, in pixels of the frame.
"""
import numpy as np
from PIL import Image

GROUND = np.array((39.5, 40.0))  # where a 1-tile creature stands in a 64 frame (the tile at the bottom-right)
AO_SCALE = 1.3                   # the reach of the ambient occlusion probes


def unit(*v):
    v = np.asarray(v[0] if len(v) == 1 else v, float)
    return v / np.linalg.norm(v)


LIGHT = unit(-0.55, -0.75, 1.0)            # from the top-left of the screen, and above
TOWARD_VIEW = unit(1 / 1.5, 1 / 1.5, 1.0)  # a screen pixel is the ray along this; higher is nearer
HALF = unit(LIGHT + TOWARD_VIEW)
SCR_E = unit(np.array((1.0, 0, 0)) - TOWARD_VIEW[0] * TOWARD_VIEW)       # the world directions of screen right
SCR_S = unit(np.array((0, 1.0, 0)) - TOWARD_VIEW[1] * TOWARD_VIEW)       # and screen down
PAINT_LIGHT = unit(-0.75, -0.30, 0.60)    # screen x, screen y, toward the viewer: the light a pixel artist paints by

FACINGS = {"north": (0, -1), "east": (1, 0), "south": (0, 1), "west": (-1, 0)}   # x east, y south


# ------------------------------------------------------------------ hashes (integers: a sine hash makes blocks)

def hash01(*ints):
    h = np.zeros(np.broadcast(*ints).shape, np.uint64)
    for k, a in enumerate(ints):
        h ^= (np.asarray(a).astype(np.int64).astype(np.uint64) + np.uint64(0x9E3779B97F4A7C15 * (k + 1) & (2 ** 64 - 1)))
        h = (h ^ (h >> np.uint64(30))) * np.uint64(0xBF58476D1CE4E5B9)
        h = (h ^ (h >> np.uint64(27))) * np.uint64(0x94D049BB133111EB)
        h ^= h >> np.uint64(31)
    return (h >> np.uint64(11)).astype(np.float64) / float(2 ** 53)


def value_noise(P, cell, salt=0):
    """Smooth noise in [-1, 1] over 3D points (trilinear value noise)."""
    q = P / cell
    g = np.floor(q).astype(np.int64)
    f = q - g
    f = f * f * (3 - 2 * f)
    out = np.zeros(len(P))
    for ox in (0, 1):
        for oy in (0, 1):
            for oz in (0, 1):
                w = (f[:, 0] if ox else 1 - f[:, 0]) * (f[:, 1] if oy else 1 - f[:, 1]) * (f[:, 2] if oz else 1 - f[:, 2])
                out += w * hash01(g[:, 0] + ox, g[:, 1] + oy, g[:, 2] + oz, np.full(len(P), salt))
    return out * 2 - 1


# ------------------------------------------------------------------ distance primitives (body coordinates)

def sd_ellipsoid(P, c, r):
    q = (P - c) / r
    k0 = np.linalg.norm(q, axis=1)
    k1 = np.linalg.norm(q / r, axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_cone(P, a, b, ra, rb):
    """A round cone from `a` (radius ra) to `b` (radius rb): limbs, horns, spikes, tails."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    ab = b - a
    L2 = ab @ ab
    t = np.clip(((P - a) @ ab) / L2, 0, 1)
    d = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
    return (d - (ra + (rb - ra) * t)) * 0.9


def sd_box(P, c, half, round_=0.0):
    """An axis-aligned box (body axes) with rounded edges: blades, planks, plates."""
    q = np.abs(P - np.asarray(c, float)) - (np.asarray(half, float) - round_)
    return np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(q.max(1), 0) - round_


def smin(a, b, k):
    """Smooth union INSIDE one part only; between parts use plain np.minimum (the animation moves them apart)."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


# ------------------------------------------------------------------ the camera

class Facing:
    def __init__(self, name, ground=None):
        f = np.array(FACINGS[name], float)
        self.F = f
        self.R = np.array((-f[1], f[0]))
        self.ground = GROUND if ground is None else np.asarray(ground, float)

    def to_body(self, W):
        d = W[:, :2] - self.ground
        return np.stack([d @ self.F, d @ self.R, W[:, 2]], 1)

    def dir_to_body(self, D):
        return np.stack([D[:, :2] @ self.F, D[:, :2] @ self.R, D[:, 2]], 1)


def march(fc, origins, direction, max_t, sdf, steps=160, eps=0.015):
    """Sphere tracing along `direction` (world) from each origin; returns the hit mask and the distance."""
    t = np.zeros(len(origins))
    hit = np.zeros(len(origins), bool)
    alive = np.ones(len(origins), bool)
    for _ in range(steps):
        idx = np.nonzero(alive)[0]
        if not len(idx):
            break
        X = fc.to_body(origins[idx] + t[idx, None] * direction)
        d = sdf(X)
        done = d < eps
        hit[idx[done]] = True
        t[idx] += np.maximum(d, eps * 0.5) * 0.85
        alive[idx[done | (t[idx] > max_t)]] = False
    return hit, t


def soft_shadow(fc, X0, sdf, k=7.0, max_t=30.0, steps=70):
    """1 lit .. 0 in the shadow, toward the light from body points X0 (already lifted off the surface)."""
    Lb = fc.dir_to_body(LIGHT[None, :])[0]
    res = np.ones(len(X0))
    t = np.full(len(X0), 0.35)
    alive = np.ones(len(X0), bool)
    for _ in range(steps):
        idx = np.nonzero(alive)[0]
        if not len(idx):
            break
        d = sdf(X0[idx] + t[idx, None] * Lb)
        res[idx] = np.minimum(res[idx], np.clip(k * d / t[idx], 0, 1))
        t[idx] += np.clip(d, 0.12, 2.0)
        alive[idx[(res[idx] < 0.02) | (t[idx] > max_t)]] = False
    return res ** 1.3


def normals(X, sdf, e=0.06):
    n = np.zeros_like(X)
    for i in range(3):
        o = np.zeros(3)
        o[i] = e
        n[:, i] = sdf(X + o) - sdf(X - o)
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)


def occlusion(X, n, sdf):
    S = AO_SCALE
    occ = np.zeros(len(X))
    for i, hgt in enumerate((0.5, 1.1, 2.0, 3.2)):
        d = sdf(X + n * hgt * S)
        occ += (hgt * S - np.minimum(d, hgt * S)) / (hgt * S) * (0.5 ** i)
    return np.clip(occ / 1.6, 0, 1)


# ------------------------------------------------------------------ colour ramps (blended in OKLab)

_M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566],
                [0.0883024619, 0.2817188376, 0.6299787005]])
_M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099],
                [0.0259040371, 0.7827717662, -0.8086757660]])


def srgb_to_oklab(rgb):
    c = np.asarray(rgb, float) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return np.cbrt(lin @ _M1.T) @ _M2.T


def oklab_to_srgb(lab):
    lms = (np.asarray(lab, float) @ np.linalg.inv(_M2).T) ** 3
    lin = np.clip(lms @ np.linalg.inv(_M1).T, 0, 1)
    c = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)
    return c * 255.0


def ramp(anchors, n):
    """`n` tones from dark to light through the anchor colours (hue-shift them: cold shade, warm light)."""
    lab = np.array([srgb_to_oklab(c) for c in anchors])
    t = np.linspace(0, len(anchors) - 1, n)
    i = np.clip(np.floor(t).astype(int), 0, len(anchors) - 2)
    f = (t - i)[:, None]
    out = lab[i] * (1 - f) + lab[i + 1] * f
    return np.clip(oklab_to_srgb(out).round(), 0, 255).astype(np.uint8)


# ------------------------------------------------------------------ small helpers

def tidy_silhouette(on):
    """Fill the 1 px notches of an edge (an empty pixel with filled neighbours on three sides)."""
    on = on.copy()
    for _ in range(2):
        P = np.pad(on, 1)
        nb = P[:-2, 1:-1].astype(int) + P[2:, 1:-1] + P[1:-1, :-2] + P[1:-1, 2:]
        on |= (~on) & (nb >= 3)
    return on


def grass_tile(w, h):
    """A plain grass ground to judge a sprite on (a flat field with a little noise)."""
    yy, xx = np.mgrid[0:h, 0:w]
    nz = hash01(yy // 2, xx // 2, np.full_like(yy, 3)) * 0.5 + hash01(yy // 5, xx // 5, np.full_like(yy, 4)) * 0.5
    base = np.array((62, 104, 46))
    col = base[None, None, :] * (0.86 + 0.24 * nz[..., None])
    a = np.dstack([np.clip(col, 0, 255), np.full((h, w), 255)]).astype(np.uint8)
    return Image.fromarray(a, "RGBA")
~~~~~

### `kit/pixellab.py`

~~~~~
"""PixelLab's public REST API (v2): the token, the balance, Edit images (Pro) and Create image (Pro).

The token: the environment variable PIXELLAB_API_TOKEN, or the first line of the file `.pixellab_token` at the root of
the studio (it is in .gitignore). Never print it. Every call is a background job: POST, then poll
GET /background-jobs/<id> every 5 s until `completed`. The account runs a few jobs at once (HTTP 429 = wait).
Docs: https://api.pixellab.ai/v2/llms.txt and https://api.pixellab.ai/v2/docs
"""
import base64
import io
import json
import os
import time
import urllib.error
import urllib.request

import numpy as np
from PIL import Image

API = "https://api.pixellab.ai/v2"
STUDIO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAX_DESCRIPTION = 2000          # the REST API cuts the description here: keep the prompt under it


def token():
    t = os.environ.get("PIXELLAB_API_TOKEN", "").strip()
    path = os.path.join(STUDIO, ".pixellab_token")
    if not t and os.path.exists(path):
        t = open(path, encoding="utf-8").readline().strip()
    if not t:
        raise SystemExit("No PixelLab token: set PIXELLAB_API_TOKEN or write it in %s" % path)
    return t


def call(method, path, body=None, timeout=60):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def balance():
    """The whole answer of GET /balance (generations left, credits): print it before and after a round."""
    return call("GET", "/balance")


def png_b64(rgba):
    buf = io.BytesIO()
    Image.fromarray(np.ascontiguousarray(rgba), "RGBA").save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def decode(im, w, h):
    """An image of a job's answer: a PNG in base64, raw RGBA bytes, or a URL."""
    if isinstance(im, str):
        im = {"base64": im} if not im.startswith("http") else {"url": im}
    if im.get("url") or im.get("image_url"):
        with urllib.request.urlopen(im.get("url") or im.get("image_url"), timeout=60) as r:
            return np.asarray(Image.open(io.BytesIO(r.read())).convert("RGBA"))
    raw = base64.b64decode(str(im["base64"]).split(",")[-1])
    if raw[:8] == b"\x89PNG\r\n\x1a\n":
        return np.asarray(Image.open(io.BytesIO(raw)).convert("RGBA"))
    w, h = int(im.get("width") or w), int(im.get("height") or h)
    if w * h * 4 != len(raw):
        w = h = int(round((len(raw) / 4) ** 0.5))
    return np.frombuffer(raw, np.uint8).reshape(h, w, 4).copy()


def _images_in(node):
    """Every image a job's `last_response` holds, wherever it is nested (its shape differs between endpoints)."""
    found = []
    if isinstance(node, dict):
        if node.get("base64") or node.get("url") or node.get("image_url"):
            return [node]
        for k in ("images", "results", "image", "frames", "edited_images"):
            if k in node:
                found += _images_in(node[k])
        if not found:
            for v in node.values():
                if isinstance(v, (dict, list)):
                    found += _images_in(v)
    elif isinstance(node, list):
        for v in node:
            found += _images_in(v)
    elif isinstance(node, str) and (node.startswith("data:image") or len(node) > 200):
        found.append({"base64": node})
    return found


def run_job(path, body, label, w, h, timeout=600):
    """POST a job (waiting on 429), poll it, and return its images as RGBA arrays."""
    job = None
    for attempt in range(10):
        try:
            job = call("POST", path, body)["background_job_id"]
            break
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(25)
                continue
            raise SystemExit("%s: HTTP %d %s" % (label, e.code, e.read()[:400]))
    if job is None:
        raise SystemExit(label + ": the account stayed busy (429)")
    t0 = time.time()
    while time.time() - t0 < timeout:
        time.sleep(5)
        try:
            d = call("GET", "/background-jobs/" + job)
        except Exception:  # noqa: BLE001 -- a hiccup while polling
            continue
        if d.get("status") == "completed":
            ims = _images_in(d.get("last_response") or {})
            print("  %s: %d image(s) in %ds" % (label, len(ims), time.time() - t0), flush=True)
            return [decode(im, w, h) for im in ims]
        if d.get("status") in ("failed", "error", "cancelled"):
            raise SystemExit("%s: %s" % (label, json.dumps(d)[:400]))
    raise SystemExit(label + ": timeout")


def edit_image_pro(rgba, prompt, seed=None, no_background=True, label="edit"):
    """Edit images (Pro), text mode, over ONE image (up to 512x512): it repaints and keeps the structure."""
    if len(prompt) > MAX_DESCRIPTION:
        raise SystemExit("the prompt has %d characters; the API takes %d" % (len(prompt), MAX_DESCRIPTION))
    h, w = rgba.shape[:2]
    body = {"method": "edit_with_text", "description": prompt, "no_background": no_background,
            "edit_images": [{"image": {"type": "base64", "base64": png_b64(rgba), "format": "png"},
                             "width": w, "height": h}],
            "image_size": {"width": w, "height": h}}
    if seed is not None:
        body["seed"] = int(seed)
    return run_job("/edit-images-v2", body, label, w, h)


def create_image_pro(prompt, width, height, seed=None, no_background=True, label="create"):
    """Create image (Pro): a new image from text (item sheets). The smaller the canvas, the more images it returns."""
    body = {"description": prompt[:MAX_DESCRIPTION], "image_size": {"width": width, "height": height},
            "no_background": no_background}
    if seed is not None:
        body["seed"] = int(seed)
    return run_job("/generate-image-v2", body, label, width, height)
~~~~~

### `kit/creature_kit.py`

~~~~~
"""The CREATURE KIT: from a creature's SHAPE (Python) to its PixelLab painting.

    from creature_kit import Shape
    SHAPE = Shape("crab", parts, ramps, outline, frame=64, ...)     # a creature file: creatures/<name>.py

The way: the SHAPE from Python, a small model of signed distances seen by the Tibia projection (tibia_view.py), lit
from the top-left and read off ramps of discrete tones per material; then PixelLab's Edit images (Pro) only REPAINTS it
(its Create, from scratch, goes back to its own frontal RPG view); then the painting is put on the posed shape, frame
by frame (creature_anim.py).

Each material goes in the shading class it needs:

    mottle    a soft noise of feathers, fur, shell                 painter   thin upright parts (legs, spikes, ribs):
    gloss     a specular spot (beak, horn, eye, wet shell)                   their visible faces turn away from the
    glow      lit by itself (glowing eyes, magic)                            top-left light, so they get the light a
                                                                             pixel artist paints by (screen left)
`shade_hook(ctx)` may change the values after that (a gradient along a part: dark pincer tips).
"""
import os
import random
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tibia_view as pt  # noqa: E402
from tibia_view import hash01, value_noise  # noqa: E402
import pixellab  # noqa: E402

STUDIO = os.path.dirname(HERE)


def out_dir(name):
    """Where everything of a creature goes: out/<name>/ at the root of the studio."""
    path = os.path.join(STUDIO, "out", name)
    os.makedirs(path, exist_ok=True)
    return path


VIEWS = ("north", "east", "south", "west")


class Shape:
    """A creature's shape. `parts`: name -> (material, distance of body points: u forward, v its right, h up, pixels).
    `ground`: where it stands in the frame -- (39.5, 40) in a 64 frame; in a bigger frame the creature stands in the
    bottom-right tile (+32 per 32 more: (71.5, 72) in a 96) and grows up and to the left."""

    def __init__(self, name, parts, ramps, outline, frame=64, ground=None, top=30.0, ss=6,
                 mottle=(), mottle_cell=2.0, gloss=(), glow=(), painter=(), painter_base=0.10,
                 shadow_reach=30.0, rim_drop=3, grain=0.3, grain_salt=9, glint=(), shade_hook=None,
                 folder=None):
        self.name, self.parts, self.names = name, parts, list(parts)
        self.ramps, self.outline = ramps, outline
        self.frame, self.top, self.ss = frame, top, ss
        self.ground = np.asarray(ground if ground is not None else (frame - 24.5, frame - 24.0), float)
        self.mottle, self.mottle_cell, self.gloss, self.glow = mottle, mottle_cell, gloss, glow
        self.painter, self.painter_base = painter, painter_base
        self.shadow_reach, self.rim_drop, self.grain, self.grain_salt = shadow_reach, rim_drop, grain, grain_salt
        self.glint, self.shade_hook = glint, shade_hook
        self.out = out_dir(folder or name)

    def sdf(self, X, with_parts=False):
        ds = np.stack([self.parts[n][1](X) for n in self.names], 1)
        total = ds.min(1)
        return (total, ds) if with_parts else total

    # ---------------------------------------------------------------- the render

    def render(self, view):
        """Per pixel of the frame: covered, the part, the light value (0..1), the height."""
        fc = pt.Facing(view, self.ground)
        n, SS, top = self.frame, self.ss, self.top
        W = n * SS
        jj, ii = np.meshgrid(np.arange(W), np.arange(W))
        sx, sy = (jj.ravel() + 0.5) / SS, (ii.ravel() + 0.5) / SS
        origins = np.stack([sx + top / 1.5, sy + top / 1.5, np.full(sx.shape, top)], 1)
        direction = -pt.TOWARD_VIEW
        hit, t = pt.march(fc, origins, direction, max_t=(top + 1) / pt.TOWARD_VIEW[2], sdf=self.sdf)
        idx = np.nonzero(hit)[0]
        Pw = origins[idx] + t[idx, None] * direction
        X = fc.to_body(Pw)
        nb = pt.normals(X, sdf=self.sdf)
        _, ds = self.sdf(X, with_parts=True)
        part = np.argmin(ds, 1)
        mat = np.array([self.parts[self.names[p]][0] for p in part])
        nw = np.stack([nb[:, 0] * fc.F[0] + nb[:, 1] * fc.R[0], nb[:, 0] * fc.F[1] + nb[:, 1] * fc.R[1], nb[:, 2]], 1)
        lam = np.clip(nw @ pt.LIGHT, 0, 1)
        sh = pt.soft_shadow(fc, X + nb * 0.25, sdf=self.sdf, max_t=self.shadow_reach)
        ao = pt.occlusion(X, nb, sdf=self.sdf)
        sky = 0.5 + 0.5 * nw[:, 2]
        front = np.clip(nw @ pt.TOWARD_VIEW, 0, 1)
        spec = np.clip(nw @ pt.HALF, 0, 1) ** 30
        v = 0.06 + 0.70 * lam * sh + 0.12 * sky + 0.18 * front - 0.28 * ao
        m = np.isin(mat, self.mottle)
        v[m] += value_noise(X[m], self.mottle_cell, 7) * 0.04
        m = np.isin(mat, self.gloss)
        v[m] += 0.25 * spec[m]
        m = np.isin(mat, self.glow)
        v[m] = 0.55 + 0.45 * front[m]
        m = np.isin(mat, self.painter)
        ns = np.stack([nw[m] @ pt.SCR_E, nw[m] @ pt.SCR_S, nw[m] @ pt.TOWARD_VIEW], 1)
        v[m] = self.painter_base + 0.80 * np.clip(ns @ pt.PAINT_LIGHT * 0.6 + 0.4, 0, 1) - 0.12 * ao[m]
        if self.shade_hook:
            v = self.shade_hook(dict(shape=self, X=X, mat=mat, part=part, v=v, nw=nw, lam=lam, sh=sh, ao=ao,
                                     spec=spec, front=front))
        v = np.clip(v, 0, 1)
        blk = (idx // W // SS) * n + (idx % W) // SS
        cov = np.bincount(blk, minlength=n * n)
        on = cov >= 0.45 * SS * SS
        cnt = np.zeros((n * n, len(self.names)))
        np.add.at(cnt, (blk, part), 1)
        pmain = np.argmax(cnt, 1)
        sel = part == pmain[blk]
        vs = np.bincount(blk[sel], weights=v[sel], minlength=n * n) / np.maximum(np.bincount(blk[sel], minlength=n * n), 1)
        hs = np.full(n * n, -np.inf)
        np.maximum.at(hs, blk, Pw[:, 2])
        return on.reshape(n, n), pmain.reshape(n, n), vs.reshape(n, n), hs.reshape(n, n)

    def paint(self, on, part, val, dep):
        """The ramps (discrete tones, a small grain), the rim of a part in front of another, the dark outline."""
        n = self.frame
        on = pt.tidy_silhouette(on)
        mats = np.array([self.parts[self.names[p]][0] for p in part.ravel()]).reshape(n, n)
        yy, xx = np.mgrid[0:n, 0:n]
        grain = (hash01(yy, xx, np.full_like(yy, self.grain_salt)) - 0.5) * self.grain
        rgba = np.zeros((n, n, 4), np.uint8)
        idx = np.zeros((n, n), int)
        for mname, rp in self.ramps.items():
            m = on & (mats == mname)
            k = np.clip(np.round(val * (len(rp) - 1) + grain), 0, len(rp) - 1).astype(int)
            idx = np.where(m, k, idx)
            rgba[m, :3] = rp[k[m]]
            rgba[m, 3] = 255

        def nbr(a, dy, dx, fillv):
            P = np.pad(a, 1, constant_values=fillv)
            return P[1 + dy:n + 1 + dy, 1 + dx:n + 1 + dx]
        rim = np.zeros((n, n), bool)
        sil = np.zeros((n, n), bool)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            non = nbr(on, dy, dx, False)
            sil |= on & ~non
            rim |= on & non & (nbr(part, dy, dx, -1) != part) & (nbr(dep, dy, dx, -np.inf) < dep - 0.9)
        for mname, rp in self.ramps.items():
            m = mats == mname
            k = np.clip(idx - self.rim_drop, 0, len(rp) - 1)
            r = rim & m & ~sil
            rgba[r, :3] = rp[k[r]]
            rgba[sil & m, :3] = self.outline[mname]
        for gm in self.glint:                     # a dark eye's glint: its top-left pixel
            eye = on & (mats == gm)
            glint = eye & ~nbr(eye, -1, 0, False) & ~nbr(eye, 0, -1, False)
            rgba[glint, :3] = (236, 236, 244)
        return rgba

    def view(self, v):
        return self.paint(*self.render(v))

    # ---------------------------------------------------------------- the files

    def save_shape(self, views=("north", "south")):
        """<name>_python.png (the views PixelLab will paint, side by side), the x5 on magenta, all four at x3."""
        frames = {v: self.view(v) for v in VIEWS}
        sheet = np.concatenate([frames[v] for v in views], 1)
        path = os.path.join(self.out, self.name + "_python.png")
        Image.fromarray(sheet, "RGBA").save(path)
        magenta(sheet, 5).save(os.path.join(self.out, self.name + "_python_x5.png"))
        magenta(np.concatenate([frames[v] for v in VIEWS], 1), 3).save(os.path.join(self.out, self.name + "_python_4dir_x3.png"))
        for v in VIEWS:
            ys, xs = np.nonzero(frames[v][..., 3])
            print("%-5s %dx%d px" % (v, xs.max() - xs.min() + 1, ys.max() - ys.min() + 1))
        print(path)
        return path


def magenta(rgba, zoom):
    im = Image.new("RGBA", (rgba.shape[1], rgba.shape[0]), (255, 0, 255, 255))
    im.alpha_composite(Image.fromarray(np.ascontiguousarray(rgba), "RGBA"))
    return im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)


def ramp(anchors, n):
    return pt.ramp(anchors, n)


# ------------------------------------------------------------------ PixelLab: the repaint over the shape

EDIT_PROMPT = """Improve and refine the texture quality of this existing {WHAT} creature sprite sheet: the same creature in {N} views, {CELLS}, idle.

Do NOT redesign it.
Do NOT change the silhouettes, proportions, positions, the perspective, or where its parts are.

THE CREATURE:
{DESIGN}

LIGHTING / DEPTH:
Maintain Tibia-style 45-degree oblique top-down 2.5D perspective: height goes up and to the left.
Light from the upper-left. Deeper shadows on the lower-right.

OUTLINE:
A thin 1-pixel dark outline around each silhouette, tinted toward the creature's own colors, not pure black.

PIXEL ART QUALITY:
Crisp, detailed fantasy game sprite, in the style of the classic Tibia creatures.
Rich tonal variation with hue shifting, texture in readable pixel clusters.
No blurry upscale appearance.
No smooth vector gradients.
No anti-aliasing.
No ground shadow.

IMPORTANT:
Preserve each view's silhouette as closely as possible: the same {WHAT}, only with significantly improved texture, shading and detail.
"""


def edit_prompt(what, design, views=("north", "south"), size=64):
    where = {"north": "facing up (north, seen from behind)", "south": "facing down (south, toward the viewer)",
             "east": "facing right (east)", "west": "facing left (west)"}
    pos = ("left", "right") if len(views) == 2 else ["#%d" % (i + 1) for i in range(len(views))]
    cells = ", ".join("the %s %dx%d cell %s" % (p, size, size, where[v]) for p, v in zip(pos, views))
    return EDIT_PROMPT.format(WHAT=what.upper(), N=len(views), CELLS=cells, DESIGN=design)


def pixellab_edit(src_path, prompt, out_dir_, variants=3):
    """Edit images (Pro) over the shape, `variants` times (different seeds): out_dir_/edit_v<k>.png. Check the
    balance before and after the first round to learn what one costs on your plan; 3 jobs run at once."""
    os.makedirs(out_dir_, exist_ok=True)
    src = np.ascontiguousarray(np.asarray(Image.open(src_path).convert("RGBA")))

    def one(k):
        for attempt in range(4):
            try:
                imgs = pixellab.edit_image_pro(src, prompt, seed=random.randint(1, 2 ** 30), label="v%d" % k)
                break
            except SystemExit as e:
                print("  v%d failed: %s" % (k, e), flush=True)
                imgs = []
                if "402" in str(e) or "422" in str(e):
                    return
        for i, a in enumerate(imgs):
            Image.fromarray(a, "RGBA").save(os.path.join(out_dir_, "edit_v%d%s.png" % (k, "" if i == 0 else "_%d" % (i + 1))))

    with ThreadPoolExecutor(3) as ex:
        list(ex.map(one, range(1, variants + 1)))


def cut_alpha(a):
    """The game draws 0 or 255: the alpha cut at half."""
    a = np.asarray(a).copy()
    on = a[..., 3] >= 128
    a[..., 3] = np.where(on, 255, 0)
    a[~on, :3] = 0
    return a


def review(shape_png, edit_dir, frame, views=("north", "south")):
    """How much of each variant's silhouette is the shape's (1.00 = the same): under ~0.9 PixelLab redrew it."""
    b = np.asarray(Image.open(shape_png).convert("RGBA"))[..., 3] > 0
    rows = [("shape", Image.open(shape_png).convert("RGBA"))]
    for f in sorted(x for x in os.listdir(edit_dir) if x.startswith("edit_v") and x.endswith(".png")):
        a = cut_alpha(Image.open(os.path.join(edit_dir, f)).convert("RGBA"))
        on = a[..., 3] > 0
        if on.shape == b.shape:
            ious = [(on[:, i * frame:(i + 1) * frame] & b[:, i * frame:(i + 1) * frame]).sum() /
                    max((on[:, i * frame:(i + 1) * frame] | b[:, i * frame:(i + 1) * frame]).sum(), 1)
                    for i in range(len(views))]
            print(f, "  ".join("%s %.2f" % (v, x) for v, x in zip(views, ious)))
        rows.append((f, Image.fromarray(a, "RGBA")))
    z = 4 if frame <= 64 else 3
    w, h = rows[0][1].size
    out = Image.new("RGBA", (w * z + 10, len(rows) * (h * z + 10)), (34, 36, 40, 255))
    for r, (_, im) in enumerate(rows):
        bg = Image.new("RGBA", im.size, (255, 0, 255, 255))
        bg.alpha_composite(im)
        out.alpha_composite(bg.resize((w * z, h * z), Image.NEAREST), (5, r * (h * z + 10) + 5))
    path = os.path.join(os.path.dirname(edit_dir.rstrip("/\\")), "edit_compare.png")
    out.save(path)
    print(path)


def pick(path, out_path):
    Image.fromarray(cut_alpha(Image.open(path).convert("RGBA")), "RGBA").save(out_path)
    print(out_path)
~~~~~

### `kit/creature_anim.py`

~~~~~
"""Animating a PixelLab painting without repainting it.

PixelLab repaints a creature's Python shape and keeps its silhouette, so each pixel of the painting belongs to a part of
the shape. A frame poses the shape -- a rigid transform per part, X_posed = R @ (X_rest - c) + c + t -- ray-marches it
in the Tibia projection, and every pixel takes its colour from the pixel of the painting where the SAME point of its
part sat at rest (or the nearest pixel of that part, when it was hidden there). A part moved by whole pixels comes out
identical, only shifted; the silhouette is outlined again with the painting's own dark, and a lone pixel goes. Where the
painting left the shape's silhouette (ragged feathers), `exact` keeps the painting's: its fringe moves with the nearest
part, its gaps stay gaps.

The sheet: a column per direction -- north, east, south, west -- and the frames going down, the idle on top and the
walk below, named <creature>_idle<frames>_walking<frames>.png.
"""
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tibia_view as pt  # noqa: E402

ORDER = ("north", "east", "south", "west")


class Model:
    """A creature's shape: its parts (name -> (material, distance of rest body points)), its frame and where it
    stands in it, and how high its rays start (above everything it has)."""

    def __init__(self, parts, names, frame=64, ground=None, top=30.0, ss=4):
        self.parts, self.names = parts, names
        self.frame, self.top, self.ss = frame, top, ss
        self.ground = pt.GROUND if ground is None else np.asarray(ground, float)
        self.mats = np.array([parts[n][0] for n in names])

    def rest(self):
        return {n: (np.eye(3), np.zeros(3), np.zeros(3)) for n in self.names}


def rotation(axis, ang):
    a = np.asarray(axis, float)
    a = a / np.linalg.norm(a)
    K = np.array(((0, -a[2], a[1]), (a[2], 0, -a[0]), (-a[1], a[0], 0)))
    return np.eye(3) + math.sin(ang) * K + (1 - math.cos(ang)) * K @ K


def posed_sdf(model, T):
    def inv(name, X):
        R, c, t = T[name]
        return (X - c - t) @ R + c          # R orthonormal: R^-1 = R^T, and (R^T v) as rows is v @ R

    def sdf(X, with_parts=False):
        ds = np.stack([model.parts[n][1](inv(n, X)) for n in model.names], 1)
        total = ds.min(1)
        return (total, ds) if with_parts else total
    return sdf, inv


def render_map(model, view, T):
    """Per pixel: covered, the part, and the mean REST position (body coordinates) of the part's samples there."""
    fc = pt.Facing(view, model.ground)
    sdf, inv = posed_sdf(model, T)
    n, SS, top = model.frame, model.ss, model.top
    W = n * SS
    jj, ii = np.meshgrid(np.arange(W), np.arange(W))
    sx, sy = (jj.ravel() + 0.5) / SS, (ii.ravel() + 0.5) / SS
    origins = np.stack([sx + top / 1.5, sy + top / 1.5, np.full(sx.shape, top)], 1)
    direction = -pt.TOWARD_VIEW
    hit, t = pt.march(fc, origins, direction, max_t=(top + 1) / pt.TOWARD_VIEW[2], sdf=sdf)
    idx = np.nonzero(hit)[0]
    X = fc.to_body(origins[idx] + t[idx, None] * direction)
    _, ds = sdf(X, with_parts=True)
    part = np.argmin(ds, 1)
    rest = np.zeros_like(X)
    for p in np.unique(part):
        m = part == p
        rest[m] = inv(model.names[p], X[m])
    blk = (idx // W // SS) * n + (idx % W) // SS
    cov = np.bincount(blk, minlength=n * n)
    on = cov >= 0.45 * SS * SS
    cnt = np.zeros((n * n, len(model.names)))
    np.add.at(cnt, (blk, part), 1)
    pmain = np.argmax(cnt, 1)
    sel = part == pmain[blk]
    k = np.maximum(np.bincount(blk[sel], minlength=n * n), 1)
    mean = np.stack([np.bincount(blk[sel], weights=rest[sel, i], minlength=n * n) / k for i in range(3)], 1)
    return on.reshape(n, n), pmain.reshape(n, n), mean.reshape(n, n, 3), fc


def rest_pixel(model, fc, Xr):
    """Where a rest point of the body is drawn (the frame's pixel)."""
    wx = model.ground[0] + Xr[..., 0] * fc.F[0] + Xr[..., 1] * fc.R[0] - Xr[..., 2] / 1.5
    wy = model.ground[1] + Xr[..., 0] * fc.F[1] + Xr[..., 1] * fc.R[1] - Xr[..., 2] / 1.5
    return np.floor(wx).astype(int), np.floor(wy).astype(int)


def lum(c):
    return 0.299 * c[..., 0] + 0.587 * c[..., 1] + 0.114 * c[..., 2]


def posed_pixel(model, fc, T, name, Xr):
    """Where a rest point of a part is drawn once the part is posed."""
    R, c, t = T[name]
    return rest_pixel(model, fc, (Xr - c) @ R.T + c + t)


def posed_paint(shape, model, view, T, own=(), drop=()):
    """The SHAPE's own painting of a pose (creature_kit.Shape), for the parts the painting never had (`own`), and
    where they come out in front. `drop`: parts left out of it -- features PixelLab painted somewhere else than the
    shape has them (eyes that sat lower in the shape than in the painting)."""
    import copy
    _, inv = posed_sdf(model, T)
    s2 = copy.copy(shape)
    s2.names = [n for n in shape.names if n not in drop]
    s2.parts = {n: (shape.parts[n][0], (lambda X, n=n: shape.parts[n][1](inv(n, X)))) for n in s2.names}
    on, part, val, dep = s2.render(view)
    return s2.paint(on, part, val, dep), on & np.isin(part, [s2.names.index(n) for n in own if n in s2.names])


def animate(model, view, painting, poses, exact=False, thin=(), own=None, hook=None, post=None):
    """The frames of one view in these poses (`painting`: PixelLab's frame of it, standing).

    `exact`: the painting's own silhouette, where it left the shape's -- the ragged feathers PixelLab drew past it move
    with the part nearest them, and the gaps it left inside the shape stay empty (the seagull; the crab's painting
    matched its shape, and goes the plain way). `thin`: parts the painter drew a little off the shape (a gull's legs):
    no gaps in them, the shape's pixels take the nearest painted pixel of the part, so the leg comes with its foot.
    `own`: (shape, part names, frame indices[, parts to drop, or {view: parts to drop}]) -- parts the painting never
    shows (a tongue): in those frames they are painted by the shape itself (its ramps), over the reprojected frame.
    `hook(view, frame index, rgba) -> rgba`: a 2D touch on the painting before the own parts.
    `post(ctx) -> rgba`: the last touch of a frame, with its part map, the source pixel of each pixel and the pose
    (ctx: view, fi, out, part, on, src, T, fc) -- the frog's sword pasted whole instead of resampled."""
    n = model.frame
    paint_on = painting[..., 3] >= 128
    on0, part0, mean0, fc0 = render_map(model, view, model.rest())
    known = paint_on & on0
    fringe = []
    if exact:
        # each pixel of the fringe goes with the part of the shape nearest it, painted there or not
        _, (fy, fx) = ndimage.distance_transform_edt(~on0, return_indices=True)
        for y, x in zip(*np.nonzero(paint_on & ~on0)):
            sy, sx = fy[y, x], fx[y, x]
            fringe.append((y, x, sy, sx, model.names[part0[sy, sx]], mean0[sy, sx]))
    # for every part: the nearest pixel of the painting that is that part, from anywhere
    nearest = {}
    for p in np.unique(part0[known]):
        m = known & (part0 == p)
        _, (iy, ix) = ndimage.distance_transform_edt(~m, return_indices=True)
        nearest[p] = (iy, ix)
    # the painting's outline colour per material: the darkest of its silhouette pixels
    P = np.pad(paint_on, 1)
    sil0 = paint_on & ~(P[:-2, 1:-1] & P[2:, 1:-1] & P[1:-1, :-2] & P[1:-1, 2:])
    mats = model.mats
    outline = {}
    for mname in set(mats):
        m = sil0 & known & (mats[part0] == mname)
        cols = painting[m][:, :3].astype(int) if m.any() else painting[sil0][:, :3].astype(int)
        outline[mname] = cols[np.argsort(lum(cols))[: max(1, len(cols) // 3)]].mean(0).round().astype(np.uint8)
    frames = []
    # (exact) which pixels of the painting were edge, and which stood alone: those stay as the painter left them
    alone0 = paint_on & (ndimage.convolve(paint_on.astype(int), np.ones((3, 3), int), mode="constant") == 1)
    for fi, T in enumerate(poses):
        on, part, mean, fc = render_map(model, view, T)
        if not exact:
            on = pt.tidy_silhouette(on)
        px, py = rest_pixel(model, fc, mean)
        out = np.zeros((n, n, 4), np.uint8)
        src = np.full((n, n, 2), -1, int)
        for y, x in zip(*np.nonzero(on)):
            p = part[y, x]
            sx, sy = px[y, x], py[y, x]
            if (exact and model.names[p] not in thin and 0 <= sx < n and 0 <= sy < n and on0[sy, sx]
                    and part0[sy, sx] == p and not paint_on[sy, sx]):
                continue                                # a gap the painting left: it stays a gap
            if not (0 <= sx < n and 0 <= sy < n and known[sy, sx] and part0[sy, sx] == p):
                if p not in nearest:
                    continue
                iy, ix = nearest[p]
                cy, cx = min(max(sy, 0), n - 1), min(max(sx, 0), n - 1)
                sy, sx = iy[cy, cx], ix[cy, cx]
            out[y, x, :3] = painting[sy, sx, :3]
            out[y, x, 3] = 255
            src[y, x] = (sy, sx)
        # the painting's fringe, moved as the pixel of the shape nearest it moves
        for y, x, sy, sx, name, Xr in fringe:
            ox, oy = rest_pixel(model, fc, Xr)
            px2, py2 = posed_pixel(model, fc, T, name, Xr)
            ty, tx = y + (py2 - oy), x + (px2 - ox)
            if 0 <= ty < n and 0 <= tx < n and out[ty, tx, 3] == 0:
                out[ty, tx, :3] = painting[y, x, :3]
                out[ty, tx, 3] = 255
                src[ty, tx] = (y, x)
        if hook is not None:
            out = hook(view, fi, out)
        # the parts the painting never had, painted by the shape where they come out in front
        if own is not None and fi in own[2]:
            drop = own[3] if len(own) > 3 else ()
            drop = drop.get(view, ()) if isinstance(drop, dict) else drop
            rgba, m = posed_paint(own[0], model, view, T, own[1], drop)
            out[m] = rgba[m]
            src[m] = -1
        # a lone pixel (the tip of a moved limb, cut off by the coverage) goes
        o = out[..., 3] > 0
        lone = o & (ndimage.convolve(o.astype(int), np.ones((3, 3), int), mode="constant") == 1)
        if exact:
            ok = src[..., 0] >= 0
            lone &= ~(ok & alone0[np.clip(src[..., 0], 0, n - 1), np.clip(src[..., 1], 0, n - 1)])
        out[lone] = 0
        # the silhouette outlined again, with the painting's own dark: a moved limb brings its inside to the edge
        o = out[..., 3] > 0
        Q = np.pad(o, 1)
        sil = o & ~(Q[:-2, 1:-1] & Q[2:, 1:-1] & Q[1:-1, :-2] & Q[1:-1, 2:])
        for y, x in zip(*np.nonzero(sil)):
            if exact and src[y, x, 0] >= 0 and sil0[src[y, x, 0], src[y, x, 1]]:
                continue                                # an edge of the painting: already the painter's edge
            oc = outline[mats[part[y, x]]]
            if lum(out[y, x, :3].astype(int)) > lum(oc.astype(int)) + 18:
                out[y, x, :3] = oc
        if post is not None:
            out = post(dict(view=view, fi=fi, out=out, part=part, on=on, src=src, T=T, fc=fc))
        frames.append(out)
    return frames


def flip(f):
    """The flip on the main diagonal: the Tibia projection's own symmetry (east is south transposed)."""
    return np.ascontiguousarray(f.transpose(1, 0, 2))


def save_gif(out_dir, cols, name, durations, zoom=4):
    """The four directions side by side, on grass, one palette for every frame (nothing blinks)."""
    n = cols["north"][0].shape[0]
    frames = []
    for r in range(len(durations)):
        im = pt.grass_tile(4 * n, n)
        for i, d in enumerate(ORDER):
            im.alpha_composite(Image.fromarray(cols[d][r], "RGBA"), (n * i, 0))
        frames.append(im.resize((4 * n * zoom, n * zoom), Image.NEAREST).convert("RGB"))
    montage = Image.new("RGB", (frames[0].width, frames[0].height * len(frames)))
    for i, f in enumerate(frames):
        montage.paste(f, (0, i * f.height))
    pal = montage.quantize(255, method=Image.Quantize.MEDIANCUT)
    gif = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    gif[0].save(os.path.join(out_dir, name + "_x4.gif"), save_all=True, append_images=gif[1:],
                duration=list(durations), loop=0, disposal=1)


def save_sheet(out_dir, cols, name, cell=128):
    """The sheet (a column per direction, the frames down) and the same on grass, each frame `cell` pixels wide."""
    n = cols["north"][0].shape[0]
    rows = len(cols["north"])
    sheet = np.concatenate([np.concatenate([cols[d][r] for d in ORDER], 1) for r in range(rows)], 0)
    Image.fromarray(sheet, "RGBA").save(os.path.join(out_dir, name + ".png"))
    strip = Image.new("RGBA", (4 * (cell + 4) - 4, rows * (cell + 4) - 4), (34, 36, 40, 255))
    for i, d in enumerate(ORDER):
        for r in range(rows):
            g = pt.grass_tile(n, n)
            g.alpha_composite(Image.fromarray(cols[d][r], "RGBA"))
            strip.alpha_composite(g.resize((cell, cell), Image.NEAREST), (i * (cell + 4), r * (cell + 4)))
    strip.save(os.path.join(out_dir, name + "_frames_x2.png"))
    print(os.path.join(out_dir, name + ".png"))


# ------------------------------------------------------------------ for a creature file (creatures/<name>.py)

def compose(outer, inner):
    """The rigid transform `inner`, then `outer`, as one (R, c, t): X -> R (X - c) + c + t."""
    Ro, co, to = outer
    Ri, ci, ti = inner
    return Ro @ Ri, ci, Ro @ (ci + ti - co) + co + to - ci


def turn(axis, degrees, about, then=None):
    """A part turned `degrees` about the line through `about` along `axis` (body axes: (1,0,0) forward, (0,1,0) its
    right, (0,0,1) up), and then moved as `then` (the body it hangs from). TEST the sign (render it
    and look): which way a positive angle goes depends on the axis."""
    t = (rotation(axis, math.radians(degrees)), np.asarray(about, float), np.zeros(3))
    return compose(then, t) if then is not None else t


def lifted(pixels=0, forward=0):
    """A whole-pixel move (it comes out identical, only shifted): `pixels` up the diagonal (1.5 of height each),
    `forward` along its facing."""
    return np.eye(3), np.zeros(3), np.array((float(forward), 0.0, 1.5 * pixels))


def by_movement(frames, walks="forward"):
    """A column per direction of MOVEMENT from PixelLab's two views (north, south) and their flips on the main
    diagonal (east is south transposed). "forward": the creature faces where it goes. "sideways" (the crab): it goes
    the way its RIGHT flank points, so moving east is the north view."""
    if walks == "sideways":
        return {"north": [flip(f) for f in frames["north"]], "east": frames["north"],
                "south": [flip(f) for f in frames["south"]], "west": frames["south"]}
    return {"north": frames["north"], "east": [flip(f) for f in frames["south"]],
            "south": frames["south"], "west": [flip(f) for f in frames["north"]]}


def make_sheet(model, painting, idle_poses, walk_poses, name, out_dir, idle_ms, walk_ms, walks="forward",
               exact=True, thin=(), cell=None, own_idle=None, own_walk=None, idle_hook=None, walk_hook=None,
               idle_post=None, walk_post=None):
    """The whole thing: `painting` = the north | south sheet (PixelLab's, or the shape's own to judge the motion
    first). Writes <name>_idle<N>_walking<N>.png (the idle on top, the walk below) and the GIFs.
    `idle_poses`/`walk_poses` may be {view: poses}: a painting that put a part somewhere else in one view (a
    north view painted with the tail where the shape has the sword) gets that view's own poses."""
    n = model.frame
    per_view = lambda poses, v: poses[v] if isinstance(poses, dict) else poses     # noqa: E731
    count = lambda poses: len(poses["north"] if isinstance(poses, dict) else poses)  # noqa: E731
    a = np.asarray(painting).copy()
    a[..., 3] = np.where(a[..., 3] >= 128, 255, 0)
    a[a[..., 3] == 0, :3] = 0
    views = {"north": a[:, :n], "south": a[:, n:2 * n]}
    idle = by_movement({v: animate(model, v, views[v], per_view(idle_poses, v), exact, thin, own_idle, idle_hook, idle_post)
                        for v in views}, walks)
    walk = by_movement({v: animate(model, v, views[v], per_view(walk_poses, v), exact, thin, own_walk, walk_hook, walk_post)
                        for v in views}, walks)
    sheet = "%s_idle%d_walking%d" % (name, count(idle_poses), count(walk_poses))
    save_sheet(out_dir, {d: idle[d] + walk[d] for d in ORDER}, sheet, cell=cell or (128 if n <= 64 else 144))
    zoom = 4 if n <= 64 else 3
    save_gif(out_dir, idle, "%s_idle%d" % (name, count(idle_poses)), idle_ms, zoom=zoom)
    save_gif(out_dir, walk, "%s_walking%d" % (name, count(walk_poses)), walk_ms, zoom=zoom)
    for v in ("north", "south"):
        d = int((idle[v][0] != views[v]).any(-1).sum())
        print(v, "idle frame 1 vs the painting: %d px differ" % d)
    return os.path.join(out_dir, sheet + ".png")
~~~~~

### `kit/items.py`

~~~~~
"""ITEM SHEETS: PixelLab draws many items in one image (Create image Pro); here they are cut into one sprite each.

    python kit/items.py gen <prompt.md> <name> [size]    # the sheet(s): out/items/<name>/sheet_<k>.png
    python kit/items.py split <sheet.png> <name> [cell]  # one PNG per item: out/items/<name>/item_<row>_<col>.png
    python kit/items.py board <name>                     # every cut item at x1 and x4 on grass, to judge them

The prompt file is the one the skill /item-sheet writes (the prompt inside a ```text block). The cut finds each item
as a blob of opaque pixels (small specks join the nearest blob), crops it, and centres it in a `cell` square with its
foot at the bottom-right like the game draws items; the alpha is cut at half (the game draws 0 or 255).
"""
import os
import re
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pixellab  # noqa: E402
import tibia_view as pt  # noqa: E402

STUDIO = os.path.dirname(HERE)


def out_dir(name):
    path = os.path.join(STUDIO, "out", "items", name)
    os.makedirs(path, exist_ok=True)
    return path


def read_prompt(path):
    text = open(path, encoding="utf-8").read()
    m = re.search(r"```text\s*\n(.*?)```", text, re.S)
    return (m.group(1) if m else text).strip()


def cut_alpha(a):
    a = np.asarray(a).copy()
    on = a[..., 3] >= 128
    a[..., 3] = np.where(on, 255, 0)
    a[~on, :3] = 0
    return a


def split(sheet, cell=64, min_px=40):
    """The items of a sheet, in reading order (rows top to bottom, then left to right): a list of (row, col, rgba)."""
    a = cut_alpha(sheet)
    on = a[..., 3] > 0
    lab, n = ndimage.label(on, np.ones((3, 3)))
    sizes = ndimage.sum(on, lab, range(1, n + 1))
    big = [i + 1 for i, s in enumerate(sizes) if s >= min_px]
    if not big:
        return []
    # a speck joins the nearest big blob (a loose spark, a dot of a gem)
    keep = np.isin(lab, big)
    _, (iy, ix) = ndimage.distance_transform_edt(~keep, return_indices=True)
    owner = np.where(on, lab[iy, ix], 0)
    boxes = ndimage.find_objects(owner)
    items = []
    for b in big:
        sl = boxes[b - 1]
        if sl is None:
            continue
        cy = (sl[0].start + sl[0].stop) / 2
        cx = (sl[1].start + sl[1].stop) / 2
        crop = a[sl].copy()
        crop[owner[sl] != b] = 0
        items.append((cy, cx, crop))
    # rows: blobs whose centres are within half a cell vertically
    items.sort(key=lambda t: t[0])
    rows, cur = [], [items[0]]
    for it in items[1:]:
        if abs(it[0] - cur[0][0]) < cell / 2:
            cur.append(it)
        else:
            rows.append(cur)
            cur = [it]
    rows.append(cur)
    out = []
    for r, row in enumerate(rows):
        for c, (_, _, crop) in enumerate(sorted(row, key=lambda t: t[1])):
            out.append((r, c, fit(crop, cell)))
    return out


def fit(crop, cell):
    """A cropped item in a `cell` square: shrunk (nearest) only if it does not fit, then centred, resting low-right."""
    h, w = crop.shape[:2]
    if h > cell or w > cell:
        k = cell / max(h, w)
        crop = np.asarray(Image.fromarray(crop).resize((max(1, int(w * k)), max(1, int(h * k))), Image.NEAREST))
        h, w = crop.shape[:2]
    out = np.zeros((cell, cell, 4), np.uint8)
    y0 = min(cell - h, (cell - h + 1) // 2 + (cell - h) // 4)
    x0 = min(cell - w, (cell - w + 1) // 2 + (cell - w) // 4)
    out[y0:y0 + h, x0:x0 + w] = crop
    return out


def board(name, zoom=4):
    folder = out_dir(name)
    files = sorted(f for f in os.listdir(folder) if f.startswith("item_") and f.endswith(".png"))
    if not files:
        raise SystemExit("no item_*.png in " + folder)
    ims = [Image.open(os.path.join(folder, f)).convert("RGBA") for f in files]
    cell = ims[0].width
    cols = min(6, len(ims))
    rows = (len(ims) + cols - 1) // cols
    W = cols * (cell * (zoom + 1) + 12)
    out = Image.new("RGBA", (W, rows * (cell * zoom + 12)), (34, 36, 40, 255))
    for i, im in enumerate(ims):
        x = (i % cols) * (cell * (zoom + 1) + 12)
        y = (i // cols) * (cell * zoom + 12)
        g = pt.grass_tile(cell, cell)
        g.alpha_composite(im)
        out.alpha_composite(g, (x, y))
        out.alpha_composite(g.resize((cell * zoom, cell * zoom), Image.NEAREST), (x + cell + 4, y))
    path = os.path.join(folder, "board.png")
    out.save(path)
    print(path)


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else ""
    if what == "gen":
        prompt, name = read_prompt(sys.argv[2]), sys.argv[3]
        size = int(sys.argv[4]) if len(sys.argv) > 4 else 256
        print(pixellab.balance())
        ims = pixellab.create_image_pro(prompt, size, size, label=name)
        for k, im in enumerate(ims, 1):
            path = os.path.join(out_dir(name), "sheet_%d.png" % k)
            Image.fromarray(im, "RGBA").save(path)
            print(path)
        print(pixellab.balance())
    elif what == "split":
        sheet, name = sys.argv[2], sys.argv[3]
        cell = int(sys.argv[4]) if len(sys.argv) > 4 else 64
        for r, c, rgba in split(Image.open(sheet).convert("RGBA"), cell):
            path = os.path.join(out_dir(name), "item_%d_%d.png" % (r + 1, c + 1))
            Image.fromarray(rgba, "RGBA").save(path)
            print(path)
        board(name)
    elif what == "board":
        board(sys.argv[2])
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
~~~~~

### `kit/tiles.py`

~~~~~
"""FLOORS: a floor is ONE periodic block of the world (256 px = 4x4 tiles of 64, or 512 = 8x8) cut into tiles; the
tile at map position (x, y) is the window of the block at (x % P, y % P). Every variant of a floor family cuts the
SAME block, so no two tiles ever show a seam.

    from tiles import wrap_blur, wrap_noise, cut, tiled, seam_score
    block = ...                                 # paint it in a floors/<name>.py script (numpy, RGBA uint8, P x P)
    tiles = cut(block, 64)                      # {(col, row): 64x64 RGBA}
    tiled(block, 3).save("out/floors/<name>/preview.png")   # 3x3 blocks side by side: look for seams and lines

Every filter goes with mode="wrap" (or an FFT), or the block stops tiling.
"""
import numpy as np
from PIL import Image
from scipy import ndimage

from tibia_view import hash01


def wrap_blur(a, sigma):
    return ndimage.gaussian_filter(a, sigma, mode="wrap")


def wrap_noise(P, cell, salt=0):
    """Smooth periodic noise in [-1, 1] on a P x P block (`cell` must divide P)."""
    n = P // cell
    yy, xx = np.mgrid[0:P, 0:P] / cell
    gy, gx = np.floor(yy).astype(int), np.floor(xx).astype(int)
    fy, fx = yy - gy, xx - gx
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)

    def h(y, x):
        return hash01(y % n, x % n, np.full_like(y, salt))
    top = h(gy, gx) * (1 - fx) + h(gy, gx + 1) * fx
    bot = h(gy + 1, gx) * (1 - fx) + h(gy + 1, gx + 1) * fx
    return (top * (1 - fy) + bot * fy) * 2 - 1


def cut(block, tile=64):
    P = block.shape[0]
    return {(c, r): np.ascontiguousarray(block[r * tile:(r + 1) * tile, c * tile:(c + 1) * tile])
            for r in range(P // tile) for c in range(P // tile)}


def tiled(block, reps=3):
    return Image.fromarray(np.tile(block, (reps, reps, 1)), "RGBA" if block.shape[2] == 4 else "RGB")


def seam_score(block):
    """The mean colour jump across the block's own wrap, against the mean jump inside it (1 or less = no seam)."""
    a = block[..., :3].astype(float)
    inner = np.abs(np.diff(a, axis=1)).mean() + np.abs(np.diff(a, axis=0)).mean()
    wrap = np.abs(a[:, 0] - a[:, -1]).mean() + np.abs(a[0] - a[-1]).mean()
    return wrap / max(inner, 1e-9)
~~~~~

### `creatures/_template.py`

~~~~~
"""BEETLE (the template's example: replace it): <what the creature is, in one line>. Asked on <date>: "<the user's words>".

    python creatures/<name>.py shape              # the shape: <name>_python.png (north | south) + the 4 views
    python creatures/<name>.py preview            # the idle and the walk on the SHAPE itself (no PixelLab):
                                                          #   judge the motion before spending generations
    python creatures/<name>.py edit [3]           # PixelLab repaints the shape: edit/edit_v<k>.png (20 gen. each)
    python creatures/<name>.py review             # how much of each variant's silhouette is the shape's
    python creatures/<name>.py pick <edit_vN.png> # the chosen one -> <name>_pixellab.png
    python creatures/<name>.py animate            # <name>_idle<N>_walking<N>.png and the GIFs, from the pick

The way (the skill /creature): the SHAPE here, in the Tibia projection; PixelLab only repaints it; the painting is
put on the posed shape frame by frame. Kit: kit/creature_kit.py (shape, PixelLab) and kit/creature_anim.py (motion,
sheet); the projection and the distance primitives in kit/tibia_view.py.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

KIT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "kit")
sys.path.insert(0, KIT)
import creature_anim as ca  # noqa: E402
import creature_kit as ck  # noqa: E402
from tibia_view import sd_ellipsoid, sd_cone, sd_box, smin  # noqa: E402

NAME = "beetle"       # the files: <NAME>_idle8_walking8.png (the sheet rule); the folder out/<NAME>/
FRAME = 64            # one tile; 96 for a bigger creature (it stands in the bottom-right tile and grows up-left)
K = 1.0               # every length: tune until `shape` prints the size asked (~40 px tall for a 64 frame, ~60 for a 96)
WALKS = "forward"     # "forward": it faces where it goes; "sideways": the crab (its right flank leads)


def P3(u, v, h):
    """Body coordinates: u forward, v its right, h up -- pixels of the frame before K."""
    return np.array((u, v, h), float) * K


# ------------------------------------------------------------------ the shape
# One distance per part, and PLAIN min between parts (the animation moves parts apart: no smin across them).
# A HUMANOID FACE (two eyes, a mouth) nods ~22 degrees DOWN about the top of the neck, the whole head with it, or it
# reads as looking up the diagonal: wrap every head part's distance in nodded() (and tilt a hat back ~40 on top of it).
# A part's material picks its ramp. Keep every part >= 2 px thick on screen, or it becomes a line of outline.

LEGS = {}           # leg -> (hip, foot): where it hinges on the body, where it touches the ground


def nodded(sdf, pivot, degrees=22.0):
    """A part of a head nodded DOWN by `degrees` about `pivot` (the top of the neck): the face looks down toward the
    viewer. Usage: P["eye_r"] = ("eye", nodded(lambda X: sd_ellipsoid(X, ...), NECK))."""
    R = ca.rotation((0, 1, 0), math.radians(degrees))    # about its right: the front goes DOWN (check_signs)
    return lambda X: sdf((X - pivot) @ R + pivot)


def parts():
    P = {}
    P["body"] = ("shell", lambda X: np.maximum(sd_ellipsoid(X, P3(-1, 0, 4.5), P3(9, 7, 4.5)), P3(0, 0, 2.5)[2] - X[:, 2]))
    P["head"] = ("skin", lambda X: sd_ellipsoid(X, P3(8.5, 0, 4.0), P3(3.2, 3.6, 2.6)))
    for side, sg in (("r", 1), ("l", -1)):
        P["eye_" + side] = ("eye", lambda X, sg=sg: sd_ellipsoid(X, P3(10.6, sg * 1.9, 5.2), P3(0.9, 0.9, 0.9)))
        for i, (u, fwd) in enumerate(((4.0, 0.8), (-1.0, 0.0), (-6.0, -0.8))):
            hip, foot = P3(u, sg * 5.5, 3.0), P3(u + fwd * 4, sg * 11.0, 0.4)
            LEGS["leg%d_%s" % (i, side)] = (hip, foot)
            P["leg%d_%s" % (i, side)] = ("leg", lambda X, a=hip, b=foot: sd_cone(X, a, b, 1.3 * K, 0.6 * K))
    return P


PARTS = parts()
RAMPS = {                                               # dark -> light, hue-shifted (cold shade, warm light)
    "shell": ck.ramp([(10, 16, 30), (20, 36, 64), (34, 62, 104), (56, 96, 146), (90, 136, 184), (140, 182, 220),
                      (200, 226, 246)], 11),
    "skin": ck.ramp([(18, 12, 10), (40, 28, 22), (70, 52, 40), (104, 82, 64), (140, 116, 92)], 7),
    "leg": ck.ramp([(14, 10, 10), (34, 26, 24), (62, 50, 44), (96, 82, 70), (132, 116, 100)], 7),
    "eye": ck.ramp([(4, 4, 8), (20, 20, 26), (50, 50, 60)], 3),
}
OUTLINE = {"shell": (6, 10, 22), "skin": (10, 6, 4), "leg": (8, 6, 6), "eye": (2, 2, 4)}
SHAPE = ck.Shape(NAME, PARTS, RAMPS, OUTLINE, frame=FRAME, top=30.0 * max(K, 1.0),
                 mottle=("shell",), gloss=("shell", "eye"), painter=("leg",), glint=("eye",))

# what PixelLab is told the creature is (the shape keeps the silhouette; this says the materials and the details)
WHAT = "giant beetle"
DESIGN = ("A giant beetle with a glossy dark-blue shell with a lighter sheen on its upper-left, small dark head with "
          "two shiny black eyes, six thin jointed black legs.")


# ------------------------------------------------------------------ the motion
# A pose = one rigid transform per part (creature_anim: X -> R (X - c) + c + t). Move whole bodies by WHOLE pixels
# (ca.lifted): they come out identical, only shifted. Turn limbs about their hinge (ca.turn) and TEST the sign.

def pose(bob=0, legs=None):
    """bob: the body up, whole pixels. legs: leg name -> degrees swung forward."""
    body = ca.lifted(bob)
    T = {}
    for name in PARTS:
        if name in LEGS:
            hip, _ = LEGS[name]
            sg = -1 if name.endswith("_r") else 1          # about the vertical, +angle turns forward -> right:
            T[name] = ca.turn((0, 0, 1), sg * (legs or {}).get(name, 0.0), hip, then=body)   # so a right leg is -
        else:
            T[name] = body
    return T


def walk_pose(k, n=8):
    s = 18 * math.sin(2 * math.pi * k / n)              # the alternating tripod: legs 0 and 2 of one side with 1 of
    a = {"leg0_r": s, "leg2_r": s, "leg1_l": s, "leg1_r": -s, "leg0_l": -s, "leg2_l": -s}   # the other
    return pose(bob=1 if k % (n // 2) == 1 else 0, legs=a)


IDLE = [pose() for _ in range(2)] + [pose(bob=1), pose(bob=1)] + [pose() for _ in range(4)]
IDLE_MS = [400, 120, 120, 120, 120, 120, 120, 200]
WALK = [walk_pose(k) for k in range(8)]
WALK_MS = [110] * 8
THIN = ()            # parts PixelLab may draw a little off the shape's (thin legs): no gaps, nearest painted colour

def check_signs():
    """Every rotation's sign, TESTED and not trusted (a wing with the sign swapped became an EAR; a leg that should go
    forward went back). Add one assert per new kind of move."""
    T = pose(legs={n: 20 for n in LEGS})
    for name, (hip, foot) in LEGS.items():
        R, c, t = T[name]
        assert (R @ (foot - c) + c + t)[0] > foot[0], name + ": +degrees must swing the foot FORWARD"
    face = P3(10, 0, 4)
    moved = nodded(lambda X: X[:, 2], P3(7, 0, 5))      # the height a point of the LEVEL head lands at, read back
    assert moved(face[None])[0] > face[2], "the nod must bring the face DOWN (a level point is found higher up)"


MODEL = ca.Model(PARTS, list(PARTS), frame=FRAME, ground=SHAPE.ground, top=SHAPE.top, ss=4)


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else ""
    out = SHAPE.out
    check_signs()
    shape_png = os.path.join(out, NAME + "_python.png")
    if what == "shape":
        SHAPE.save_shape()
    elif what == "preview":                 # the motion on the shape's own render: no PixelLab spent
        if not os.path.exists(shape_png):
            SHAPE.save_shape()
        ca.make_sheet(MODEL, Image.open(shape_png).convert("RGBA"), IDLE, WALK, NAME + "_shape", out,
                      IDLE_MS, WALK_MS, walks=WALKS, exact=False)
    elif what == "edit":
        ck.pixellab_edit(shape_png, ck.edit_prompt(WHAT, DESIGN, size=FRAME), os.path.join(out, "edit"),
                         int(sys.argv[2]) if len(sys.argv) > 2 else 3)
        ck.review(shape_png, os.path.join(out, "edit"), FRAME)
    elif what == "review":
        ck.review(shape_png, os.path.join(out, "edit"), FRAME)
    elif what == "pick":
        ck.pick(sys.argv[2], os.path.join(out, NAME + "_pixellab.png"))
    elif what == "animate":
        painting = Image.open(os.path.join(out, NAME + "_pixellab.png")).convert("RGBA")
        ca.make_sheet(MODEL, painting, IDLE, WALK, NAME, out, IDLE_MS, WALK_MS, walks=WALKS, exact=True, thin=THIN)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
~~~~~

### `.claude/skills/creature/SKILL.md`

~~~~~
---
name: creature
description: Creates a new CREATURE (monster, beast, enemy, mob) in pixel art in Tibia's oblique perspective — the SHAPE modelled in Python (signed distances), PixelLab only REPAINTING that shape (Edit images Pro, 3 variants, silhouette review), and the animation (idle + walking) made by dressing the posed shape in the painting, never repainting frame by frame. Delivers ONE sheet with a column per direction (north, east, south, west), the idle on top and the walking below. Use when the user asks for a creature, monster, beast, enemy or mob, a new version of one, its animation, or runs /creature.
argument-hint: "[name and idea of the creature]"
---

# A new creature

Request: **$ARGUMENTS**

The way (it is what holds the perspective — PixelLab alone does not):

1. **the SHAPE in Python**, one file per creature (`creatures/<name>.py`, copied from `creatures/_template.py`):
   parts made of signed distances, seen through the Tibia projection, lit from the top-left, read off ramps of tones
   per material, with a dark outline;
2. **PixelLab only REPAINTS** that shape (Edit images Pro), in 3 variants, and the silhouette of each is reviewed;
3. **the animation dresses the posed shape in the painting**: each frame puts the parts in a rigid pose and each pixel
   takes the colour of the same point of the same part in the standing painting. What only moves comes out IDENTICAL,
   just shifted; nothing "boils".

The kit: `kit/tibia_view.py` (the projection, the primitives), `kit/creature_kit.py` (shape, painting, PixelLab),
`kit/creature_anim.py` (pose, reprojection, sheet, GIF), `kit/pixellab.py` (the API).

## What to ask (only what the request did not say; everything else has a default)

| | default |
|---|---|
| **the name** (it names the files) | what the user called it, ASCII, with `_` (`zombie_seagull`) |
| **the idea** | suggest a twist that escapes the ordinary (the tortoise gets spikes, the seagull turns zombie, the frog turns pirate) |
| **the size** | a 64 frame and a creature of ~40 px; "bigger" = a 96 frame and ~60 px |
| **how it walks** | forward; SIDEWAYS only what walks sideways (a crab); flying/hovering is a variant of the walking |
| **the directions** | the 4 of the sheet come from TWO painted views (north and south): east and west are south and north mirrored on the diagonal |

A reference image from the user (concept art) is the best input: read it and turn it into parts.

## The steps

1. **The file.** Copy `creatures/_template.py` to `creatures/<name>.py`. Replace the example (the beetle): `NAME`,
   `FRAME`, `K`, `WALKS`, the parts in `parts()`, `RAMPS`, `OUTLINE`, the `Shape` classes (`mottle`, `gloss`, `glow`,
   `painter`), `WHAT` and `DESIGN` (what PixelLab will hear), the poses and `check_signs`. The docstring at the top
   holds the request in the user's words and the date.
2. **The shape**: `python creatures/<name>.py shape`. It prints the size of each view and writes into `out/<name>/`:
   `<name>_python.png` (north | south), `_python_x5.png` and `_python_4dir_x3.png`. OPEN the previews (read the image)
   and fix the SHAPE until it reads well in all four views — PixelLab copies its defects (table below). Tune `K` to the
   size asked.
3. **The motion on the shape**: `python creatures/<name>.py preview` animates the shape itself
   (`<name>_shape_idle8_walking8.png` and the GIFs). Judge the rhythm and the poses HERE, before spending PixelLab.
4. **PixelLab**: `python creatures/<name>.py edit 3` (3 variants). Before the first round, tell the user it costs
   generations and check the balance
   (`python -c "import sys; sys.path.insert(0,'kit'); import pixellab; print(pixellab.balance())"`) before and after.
   The command prints the review: how much of each variant's silhouette overlaps the shape's (1.00 = the same). Under
   ~0.90 PixelLab REDREW it; also check that north and south stayed CONSISTENT with each other. Show the candidates to
   the user (`out/<name>/edit_compare.png`) with your recommendation; they choose.
5. **The chosen one**: `python creatures/<name>.py pick out/<name>/edit/edit_vN.png` → `<name>_pixellab.png`.
6. **The sheet**: `python creatures/<name>.py animate` → `<name>_idle8_walking8.png` (4 columns × 16 rows),
   `<name>_idle8_x4.gif`, `<name>_walking8_x4.gif`, `<name>_idle8_walking8_frames_x2.png`. It prints how many pixels
   the 1st idle frame differs from the painting (0 to a few). Check the frames ENLARGED: a loose limb, a floating foot,
   a stray pixel, a shell that boils.
7. **Record it**: in `NOTES.md` at the studio root, one section per creature (the request, the shape, the variants and
   the choice, the poses, every mistake that cost a round). That is how the studio learns.

## The sheet (not negotiable)

| | |
|---|---|
| **columns** | one per direction of MOVEMENT: 1 north, 2 east (to the right), 3 south, 4 west (to the left) |
| **rows** | the frames going down: the IDLE on top and the WALKING below, on the SAME sheet |
| **name** | `<creature>_idle<N>_walking<N>.png` (a 1-frame idle = `idle1`). A new variant gets a new name (`_hovering_`, `walking16`): NEVER overwrite an approved sheet |
| **sideways** | a creature that walks sideways (a crab): `WALKS = "sideways"`, always the right flank leading |

## The rules of the shape (each one cost a rejection or a round)

| | |
|---|---|
| **art from SCRATCH** | a commercial game's sprite (Tibia's or any other) is a ruler for SIZE, fit and parts; none of its pixels go into the art |
| **the perspective** | a point at height h is drawn h/1.5 up and h/1.5 to the left; the ground seen from above, never squashed; you see the top and the south and east faces. A 1-tile creature stands at (39.5, 40) of a 64 frame; in a bigger frame, in the bottom-right tile ((71.5, 72) in a 96) and it grows up and to the left |
| **NO Create from scratch** | PixelLab creating from nothing, even with a reference, goes back to the symmetric frontal RPG view and fills the tile. Always shape + Edit |
| **PixelLab copies the defect** | a shell that is a whole ellipsoid comes out a BALL (use only the top half, with an edge); a leg with a high knee becomes a parallel STROKE (lower it, thicken it, fan the legs out). Fix the shape before spending |
| **upright parts come out dark** | spike, thin leg, rib: their visible faces (south and east) turn away from the light and become dark holes. Put the material in `painter` (the light a pixel artist paints by, in screen terms) |
| **≥ 2 px thick** | a thinner part becomes just outline; a cone's tip radius ≥ 0.5 px |
| **test the SIGN** | a wing with the tilt swapped became an EAR; a leg that should go forward went back. Every new rotation gets an `assert` in `check_signs` |
| **south shrinks** | going south (down the screen) cancels height (up-left): a head too far forward DROPS below the body in the front view. An upright creature: the head almost above the chest. North and west read longer, south and east more compact: that is the projection |
| **a HUMANOID FACE looks DOWN** | two eyes and a mouth on a level head read as "looking up the diagonal". The WHOLE head (hat, eyes, mouth) nods ~22° down about the top of the neck (the template's `nodded()`); a HAT tilts back ~40° relative to it, or the brim covers the face; and `DESIGN` tells PixelLab "head bowed slightly forward and DOWN: the face looks down toward the viewer, never up" |
| **biped: chibi proportions** | short legs and trunk, a BIG head, the face on the FRONT of the head (where the south view sees it) |
| **plain min between parts** | `np.minimum` between parts (`smin` only inside one part): the animation moves the parts apart |
| **what sits under a BRIM vanishes** | the view comes from above and the south: whatever is under a brim (a hammerhead, a hat, a snout) must stick out in front of it ~1 unit per 1.5 of height |
| **a plate in PROFILE** | a blade, fin or flat wing facing northeast/southwest comes out edge-on. Put the plate in the plane of the front-right diagonal (flat in north and south) |
| **a weapon: by the HANDLE, the blade HANGING** | the hand at the END of the haft, the haft forward almost level, the blade at the tip hanging STRAIGHT down (the only direction north and south both see wide) |
| **a thin weapon comes out JAGGED** | PixelLab draws a 2 px blade in a crooked staircase: redraw the weapon in clean pixel art over the chosen painting (~5 px, outline, light edge, dark spine), starting BELOW the hand |
| **quality** | compare at 1× and enlarged; texture with volume, never flat; show only what is really good |
| **the approved is not "improved"** | what the user approved comes back pixel for pixel; an automatic cleanup that eats a spike's tip is a regression |

## The rules of the animation

| | |
|---|---|
| **the body by WHOLE pixels** | `ca.lifted(px, forward)`: 1 px of height = 1.5 along the diagonal. The body comes out identical, only shifted |
| **limbs about their hinge** | `ca.turn(axis, degrees, hinge, then=body)`; groups: body, head (base of the neck), jaw (inside the head: `ca.compose`), each limb |
| **the WEAPON arm does not swing** | turning a limb resamples what it holds and the weapon "boils": the armed arm moves WHOLE with the body (whole pixels); only the other one swings |
| **a short step** | a chest or shell hides the top of the leg: a long step leaves the foot LOOSE. ~14° instead of 24° |
| **`exact` + `THIN`** | PixelLab's painting goes past the shape (loose feathers): in `exact` mode the fringe moves with the nearest part; thin legs it drew off their place go in `THIN` |
| **per-view poses** | if the painting put a part somewhere else in one view (a tail painted where the shape has the sword), pass `{view: poses}` to `make_sheet` and give that view its own poses |
| **the walk** | quadruped: diagonal pairs; insect/crab: alternating tripod; biped: alternating legs, the body rises where they cross, the head leads mid-step |
| **an idle with charm** | snapping pincers, a scream with a twitch, pawing the ground; eyes STILL. A rest pause at the start (~400 ms) |
| **fly/hop** | a variant of the walking: rise by whole pixels with the wings beating, or little steps + a short flight that lands (`walking16`) |
| **DO NOT animate the FACE** | PixelLab keeps the silhouette, not where the eyes and the mouth are. A tongue, a blink, an opening mouth came out ugly and were rejected. The idle animates what is RIGID and in the same place on the shape and the painting (limb, weapon, wing, pincer, the whole body), or it is just the standing frame (`idle1`) |
| **a shape part over the WRONG place of the painting** | moving a part moves the PAINTED pixels that fall on it: if the shape's throat falls on the painting's scarf, the CLOTHES jump. Only animate a part whose place is the same on the shape and the painting |

## What to say when delivering

- the sheet (the path), the size of each view, the GIFs;
- the variant chosen and why, and how much the balance dropped;
- what you did not see (the GIF playing: you see the frames) and the numbers to tune (height, angle, ms).
~~~~~

### `.claude/skills/item-sheet/SKILL.md`

~~~~~
---
name: item-sheet
description: Makes an ITEM SHEET in pixel art (64x64 by default, or 32x32 in Tibia's painterly style) — builds the PixelLab prompt with the approved texture and oblique perspective, generates the sheet through the API (Create image Pro), cuts one PNG per item and builds a board to judge them. Use when the user asks for items, inventory icons, weapons, armour, potions, equipment, loot, "an item sheet", or runs /item-sheet.
argument-hint: "<items or theme; 'variations' for several versions of each; '32' for the classic size>"
---

# Item sheet

Items requested: **$ARGUMENTS**

If it came empty, ask which items (or the theme) before anything else. This is the item's ICON (what lies on the
ground and in the inventory); a piece worn on a character's body is a different sprite.

## 1. Build the prompt

Read ALL of `.claude/skills/item-sheet/base-prompt.md`: the **PIXELLAB BASE PROMPT** block is the real prompt, and the
`{...}` blocks under it are the pieces you fit in.

- **Size:** 64 by default. If the request says **32**, apply the whole 32x32 VARIANT section, including the rule that
  the item FILLS the tile.
- **Layout:** LIST by default. VARIATIONS if the request says "variations", "versions", "options of each", or if it is
  a single item.
- **Up to ~16 items per sheet.** Above that, split into sheets and say why.
- Each item in **English**: a short name, the main material with its colour, and 2 to 4 CONCRETE details (stitching,
  patch, buckle, rune, gem, crack). "Very detailed old metal" says nothing; "tarnished iron edges with small dents"
  does.
- The style, the perspective and the Avoid line are **never summarised or cut**: they are what made the sheet good.
- No `{...}` may be left. The final prompt must fit in **2000 characters** (the API's limit): cut item details, never
  the STYLE.

Save it to `prompts/items/<slug>.md` (kebab-case, ASCII): the prompt in a ```text block and, below it, the list of
items (the name shown in the game → the item on the sheet), so whoever cuts it knows what each cell is.

## 2. Generate

Show the prompt to the user and tell them it will spend generations. Then:

```
python kit/items.py gen prompts/items/<slug>.md <slug> 256
```

256×256 = a sheet of 4×4 cells of 64 (for 32 px: 128×128 with up to 16 items, or 256×256 with more). The command
prints the balance before and after and writes `out/items/<slug>/sheet_<k>.png`.

## 3. Cut and judge

```
python kit/items.py split out/items/<slug>/sheet_1.png <slug> 64
```

One PNG per item (`item_<row>_<col>.png`, alpha cut to 0/255) and `board.png` (each item at 1× and 4× on grass). OPEN
the board and check: an item that was not asked for, an item cut in half, two items stuck into one (the cut finds each
item as an opaque blob: if PixelLab made two touch, separate them by hand), an item too small for its cell (at 32 it
must fill the cell).

What came out wrong goes back into the prompt: the **Avoid** line gains the word for the problem that appeared (e.g.
`open books`, `human figure`), not a preventive list.

## 4. Deliver

The board, the list "name → file", how much the balance dropped, and what would call for another round.
~~~~~

### `.claude/skills/item-sheet/base-prompt.md`

~~~~~
# PixelLab — the item sheet base

It came from an approved sheet of 15 pieces of equipment: the right texture and shading. Changing the style of EVERY
future sheet means editing the PIXELLAB BASE PROMPT block below.

## INSTRUCTIONS FOR THE AI (they do not go into the prompt)

- Create image has **no negative field**: everything negative goes in the `Avoid:` line at the end.
- **A long, detailed prompt is welcome** in this mode (up to 2000 characters through the API).
- **Two layouts:** LIST (different items, one per cell: `{LAYOUT_LIST}`) and VARIATIONS (up to 6 items, one ROW per
  item, the columns are the versions: `{LAYOUT_ROWS}`, and the items become `Row 1:`, `Row 2:`…).
- **How to put each kind in the cell:** body clothing `laid flat` (or it comes with a body inside; at 32: `short wide …
  robe laid flat in a square shape, sleeves spread out sideways`); hood and hat `shown empty`; boots `pair of …`; book
  `closed thick book`; wand, staff, long weapon `lying diagonally`.
- **Tiers (`{TIERS}`)** only when the sheet mixes common and rare. Without tiers, delete the whole paragraph.

## PIXELLAB BASE PROMPT

```text
High-quality 64x64 pixel art item sprite sheet: {LAYOUT}

STYLE: richly rendered pixel art in the classic Tibia 45 degree oblique top-down perspective, showing the top surface and the front face at the same time. Strong light from the top-left. Every material uses a wide 10 to 12 tone color ramp with hue shifting: warm bright highlights, rich mid tones, cool deep shadows. Smooth tonal blending inside each material, soft reflected light on the lower-right edges, deep self-shadows inside folds, cavities and under overlapping parts. Fine material texture: {TEXTURES}. Thin dark outline around each item, tinted toward the item's own color.

{TIERS}

ITEMS:
{ITEMS}

Avoid: flat colors, limited palette, posterized or banded shading, blocky chunky pixels, jagged staircase edges, low detail, blurry or smudged areas, noisy random pixels, photorealism, 3D render look, vector art, flat mobile-game icons, text, letters, labels, numbers, ground, floor, grass, base platforms, cast shadows or drop shadows under the items, {EXTRA_AVOID}extra items not in the list.
```

### The blocks

`{LAYOUT_LIST}` (N = how many items):

```text
a clean grid of separate {THEME} items on a transparent background, one item centered in each cell, each item filling most of its cell, nothing overlapping. Exactly these N items, in this order, and nothing else.
```

`{LAYOUT_ROWS}`:

```text
each ROW is one item and the COLUMNS are design variations of that same item, on a transparent background, one item centered per cell, nothing overlapping. Exactly N rows, and nothing else.
```

`{TEXTURES}` — only the materials on the sheet, for example: `velvet sheen, leather grain and creases, wool fibers,
stitched seams, linen weave, worn brass and gold with small scratches, gems with inner light and a bright specular dot`.

`{TIERS}` (an example; adapt it to the game):

```text
TWO TIERS that must read at a glance: COMMON items are humble and worn, made of undyed wool, brown leather, rough linen and moss-green cloth, with patches and frayed edges, and they have NO gems. RARE items are midnight-blue velvet with gold embroidery and exactly one glowing violet gem.
```

`{EXTRA_AVOID}` — empty, or comma-separated terms ending in `, ` (e.g. `gems on common items, `).

## The 32x32 VARIANT

- `64x64` becomes `32x32` at the start, and the layout says `one item centered in each 32x32 cell`.
- **The ITEM FILLS THE CELL.** In Tibia a 32 item takes almost the whole tile. Right after `nothing overlapping.`:

  ```text
  SIZE RULE: every item is drawn BIG but lives ENTIRELY inside ONE square 32x32 cell: it fills the square almost edge to edge in width AND in height, with at most 1 pixel of margin, like classic Tibia inventory items, and no pixel ever crosses into the next cell. No item is taller than one cell or spans two cells. Long items are reshaped to fit the square: robes, capes and coats are drawn short and wide with the sleeves spread out to the sides; wands and staffs lie diagonally from corner to corner.
  ```

  And the Avoid line gains `small items, empty space around the items, wide margins inside the cells, items crossing the cell borders, items taller than one cell, long elongated robes, `.
  The rule is SQUARE ("width AND height"), not "longest side": with "longest side" it stretched the robes over two cells.
- The whole STYLE paragraph is replaced by this one. The classic 32 item is PAINTED AND SHRUNK, not clean pixel art
  (measured: ~0.6 distinct colours per pixel, soft gradients with fine noise, a 1 px near-black outline, FEW dark lines
  inside):

  ```text
  STYLE: authentic Tibia item sprite style, a painterly pre-rendered look, as if a small detailed painting was shrunk down to 32x32, in the classic Tibia 45 degree oblique top-down perspective showing the top surface and the front face. Almost every pixel is a slightly different shade: soft smooth gradients with fine per-pixel color noise over every surface, hundreds of colors per item, no flat color areas, no posterized bands, no clean cel-shaded clusters. Vivid saturated colors, high contrast, strong light from the top-left with soft glowing highlights and deep shadows. Forms are shaped by light and color, with very few dark inner lines. Bold 1 pixel near-black outline around the whole silhouette.
  ```

- **1 or 2 details per item**, not 2 to 4: a tiny rune or a seam vanishes at 32.
- **Do not lengthen the STYLE** to ask for a stronger outline: a long outline paragraph made the sheet lose its order,
  gain items that were not asked for and shrink the items. A stronger outline is done afterwards, on the PNG.
- The Avoid line swaps `blocky chunky pixels, jagged staircase edges` for `clean cel-shaded pixel clusters, limited palette, modern indie pixel art style, thick dark inner lines, pillow shading, blurry edges, micro-detail that turns into noise`.
~~~~~

### `.claude/skills/floor/SKILL.md`

~~~~~
---
name: floor
description: Paints a FLOOR (map ground — grass, dirt, stone, marble, planks, sand) in PYTHON as ONE periodic block of the world cut into 64 px tiles, with variation by an X/Y pattern and borders as transitions. Use when the user asks for a ground, floor, lawn, dirt, paving, boards, a ground tileset, the borders of a floor, or runs /floor.
argument-hint: "[the floor and what it should have]"
---

# A floor in Python

Request: **$ARGUMENTS**

The helper is `kit/tiles.py` (periodic block, noise that wraps around, cutting, preview, seam measure). Each floor's
script lives in `floors/<name>.py` and writes into `out/floors/<name>/`.

## The rules that are not negotiable (each one cost a rejection)

| | |
|---|---|
| **a floor is PYTHON, not PixelLab** | PixelLab flattens grass into a plain green, invents bushes, and with `no_background` on it ERASES the ground (takes it for background). At most it refines pieces with an outline (border stones), never the middle that repeats |
| **a BLOCK OF THE WORLD** | paint one periodic block (256 px = 4×4 tiles; 512 = 8×8) and each tile is its window at the world position (`x % P`, `y % P`). Every variant of a family uses the SAME block: there is no seam between them. Filters, blur and noise with `mode="wrap"` (`tiles.wrap_blur`, `tiles.wrap_noise`) |
| **variation by the X/Y pattern** | 4×4 at least; 8×8 when it repeats a lot. The game engine picks the tile by position |
| **64 px pixel art** | paint straight at 64 px (a crisp 1 px grass blade) or 8× bigger and shrink by the mean. No smooth gradients: stepped shading, dithering only inside one surface |
| **light from the top-left** | relief (stone, plank) with the top-left edge light and the bottom-right one dark; the cast shadow goes down-right and does NOT wrap around (no `np.roll` on the shadow) |
| **the change must SHOW** | judge at real size, tiled 3×3 (`tiles.tiled`), not on an enlarged preview |
| **do not invent dirt** | stains and broken slabs were rejected. Damage only when asked, and LIGHT |
| **no BLACK outline** | a stone's outline is a dark tone of its OWN material |

## The borders (one floor passing into another)

| | |
|---|---|
| **a transition, not a frame** | a border of another texture glued onto the floor was rejected. The border is the passage: the outside material only at the edge (~7 px), the FLOOR at the same world pixel from there inward, and the stones between them stay or go WHOLE |
| **4 shapes** | tile (x, y) uses shape `(x + 3y) % 4`: straight, set back, advancing with loose tufts, wavy; the shape changes only away from the tile's edge, or the neighbour does not fit |
| **dithering becomes a LINE** | thinning by a Bayer pattern leaves a regular band parallel to the border. Thin by WHOLE pieces, with a hash of the place |

## Step by step

1. Ask what is missing: the material, the tone (a reference or colours), the block size (4×4 or 8×8), whether there
   are borders.
2. Write `floors/<name>.py`: the `P×P` RGBA block in numpy; the colour ramp with `tibia_view.ramp` (cold shadow, warm
   light); the pieces (stones, planks, tufts) painted by position with `tibia_view.hash01` (an integer hash, never a
   sine hash: it comes out in BLOCKS).
3. Save `block.png`, the tiles (`tiles.cut` → `tile_<col>_<row>.png`) and `preview.png` (`tiles.tiled(block, 3)`).
4. Measure `tiles.seam_score(block)` (1 or less = no seam) and OPEN the preview: seam, repeated line, a square that
   stands out, tone.
5. Deliver: the preview, the seam number, and the list of tiles.
~~~~~

---

The end. If a file above looks cut off, stop and tell the person: do not invent the rest.
