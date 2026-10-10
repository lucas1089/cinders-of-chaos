"""PixelLab's public REST API (v2): the token, the balance, Edit images (Pro) and Create image (Pro).

The token: the environment variable PIXELLAB_API_TOKEN, or the first line of the file `.pixellab_token` at the root of
the studio (it is in .gitignore). Never print it. Without either, calls go out with no Authorization header (for a
proxy that injects the credential). Every call is a background job: POST, then poll
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
    return t or None        # none: the session's proxy may add the credential itself (no local token needed)


def call(method, path, body=None, timeout=60):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    t = token()
    if t:
        headers["Authorization"] = "Bearer " + t
    req = urllib.request.Request(API + path, data=data, method=method, headers=headers)
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
