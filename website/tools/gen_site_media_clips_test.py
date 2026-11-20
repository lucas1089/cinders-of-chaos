#!/usr/bin/env python3
"""Test of the mechanics clips of gen_site_media.py (O687): the check on a synthetic media folder (no clip, a pair, a half
pair, a loop over budget, an unknown file, a wrong hash, the clip total) and the three lists of ids held equal: CLIPS of
gen_site_media.py, the slots of plugins/chaos/media_lib.php and the shots of client/overlay/modules/test_cliptour.

  python3 -I website/tools/gen_site_media_clips_test.py        (the id check needs luajit or lua5.3; without it that part is skipped)
"""
import contextlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_site_media as g  # noqa: E402

REPO = g.REPO
checks = 0
failed = 0


def check(ok, what):
    global checks, failed
    checks += 1
    if not ok:
        failed += 1
        print("FAIL: " + what)


def run_check():
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = g.check()
    return rc, out.getvalue()


def make_tree(tmp):
    """The committed media in a temp folder, g.MEDIA and g.MANIFEST pointing at it."""
    media = os.path.join(tmp, "media")
    shutil.copytree(g.MEDIA, media)
    g.MEDIA = media
    g.MANIFEST = os.path.join(media, "manifest.json")
    return media


def put(media, name, size):
    with open(os.path.join(media, name), "wb") as f:
        f.write(os.urandom(size))


def main():
    real_media, real_manifest = g.MEDIA, g.MANIFEST
    tmp = tempfile.mkdtemp()
    try:
        media = make_tree(tmp)
        rc, text = run_check()
        check(rc == 0 and "0 of 10 recorded" in text, "the committed media pass with no clip: " + text.strip()[:120])
        planned = g.planned_clips()
        check(len(planned) == 20 and all(n.startswith("clip-") for n in planned), "two planned files per clip")

        # two clips recorded: the manifest is written from the files
        for cid in ("rift", "passive-tree"):
            put(media, "clip-%s.mp4" % cid, 400 * 1000)
            put(media, "clip-%s.jpg" % cid, 40 * 1000)
        with contextlib.redirect_stdout(io.StringIO()):
            rc = g.write_manifest()
        check(rc == 0, "two clip pairs and a rewritten manifest pass")
        data = json.load(open(g.MANIFEST))
        check("clip-rift.mp4" in data["files"] and "clip-rift.jpg" in data["files"] and data["total"] == sum(v["size"] for v in data["files"].values()), "the manifest lists the clips and its total adds up")
        rc, text = run_check()
        check("2 of 10 recorded" in text, "the count of recorded clips")

        # a half pair
        os.remove(os.path.join(media, "clip-rift.jpg"))
        rc, text = run_check()
        check(rc == 1 and "clip-rift.jpg" in text, "a video without its poster is a problem: " + text.strip()[:100])
        put(media, "clip-rift.jpg", 40 * 1000)
        with contextlib.redirect_stdout(io.StringIO()):
            g.write_manifest()

        # a loop over its budget
        put(media, "clip-rift.mp4", g.BUDGET_CLIP + 1000)
        with contextlib.redirect_stdout(io.StringIO()):
            rc = g.write_manifest()
        check(rc == 1, "a loop over the budget fails")
        put(media, "clip-rift.mp4", 400 * 1000)

        # the sha256 of a clip must be the manifest's
        with contextlib.redirect_stdout(io.StringIO()):
            g.write_manifest()
        put(media, "clip-passive-tree.mp4", 400 * 1000)  # other bytes, same size
        rc, text = run_check()
        check(rc == 1 and "sha256 differs" in text, "a changed clip is caught by its hash")
        with contextlib.redirect_stdout(io.StringIO()):
            g.write_manifest()

        # a clip the generator does not know
        put(media, "clip-unknown.mp4", 100 * 1000)
        rc, text = run_check()
        check(rc == 1 and "clip-unknown.mp4" in text, "an unknown clip file is a problem")
        os.remove(os.path.join(media, "clip-unknown.mp4"))

        # all ten at their budget are over the clips total
        old = g.BUDGET_CLIPS_TOTAL
        g.BUDGET_CLIPS_TOTAL = 500 * 1000
        rc, text = run_check()
        g.BUDGET_CLIPS_TOTAL = old
        check(rc == 1 and "clips total" in text, "the clips total budget holds")
        rc, _text = run_check()
        check(rc == 0, "and passes again under its budget")
        check(g.BUDGET_CLIP * 10 + g.BUDGET_CLIP_POSTER * 10 <= g.BUDGET_CLIPS_TOTAL + 1000 * 1000, "the clips total fits ten loops and posters")
    finally:
        g.MEDIA, g.MANIFEST = real_media, real_manifest
        shutil.rmtree(tmp, ignore_errors=True)

    # the three lists of ids
    clip_ids = [c[0] for c in g.CLIPS]
    check(len(set(clip_ids)) == len(clip_ids) == 10, "ten distinct clip ids")
    php = open(os.path.join(REPO, "website", "overlay", "plugins", "chaos", "media_lib.php"), encoding="utf-8").read()
    body = php[php.index("function chaos_media_action_slots"):]
    body = body[:body.index("\n}\n")]
    php_ids = re.findall(r"^\t\t'([a-z0-9-]+)' => array\(", body, re.M)
    check(php_ids == clip_ids, "the slots of media_lib.php are the clips of gen_site_media.py, in order: %s" % php_ids)
    lua = None
    for exe in ("luajit", "lua5.3", "lua"):
        if shutil.which(exe):
            lua = exe
            break
    if lua:
        code = "dofile('client/overlay/modules/test_cliptour/cliptourlogic.lua'); print(table.concat(ChaosClipTourLogic.shotIds(), ' '))"
        r = subprocess.run([lua, "-e", code], cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        lua_ids = r.stdout.decode().split()
        check(r.returncode == 0 and lua_ids == clip_ids, "the shots of test_cliptour are the clips of gen_site_media.py, in order: %s" % lua_ids)
        lens = {}
        code = ("dofile('client/overlay/modules/test_cliptour/cliptourlogic.lua'); for _, s in ipairs(ChaosClipTourLogic.SHOTS) do "
                "print(s.id, s.seconds) end")
        r = subprocess.run([lua, "-e", code], cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for line in r.stdout.decode().splitlines():
            cid, secs = line.split()
            lens[cid] = int(secs)
        for cid, start, length, poster in g.CLIPS:
            check(lens.get(cid, 0) >= start + length and 0 < poster < length, "%s: the recorded loop (%ss) holds the cut %.0f + %.0f and the poster is inside it" % (cid, lens.get(cid), start, length))
    else:
        print("no lua: the shot id check is skipped")
    print("gen_site_media_clips_test: %d checks, %d failed" % (checks, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
