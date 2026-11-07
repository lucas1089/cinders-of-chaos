#!/usr/bin/env python3
"""python3 -I unity/tools/fetch_3d_assets_test.py : the pure parts of fetch_3d_assets.py on a fake archive (no network):
the file table, the archive root, extraction with hashes, a wrong hash, a missing entry, a size over the limit, a name that
is not in the table, and the --check / fetch round trip through a local archive."""
import contextlib
import hashlib
import importlib.util
import io
import os
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("fetch_3d_assets", os.path.join(HERE, "fetch_3d_assets.py"))
F = importlib.util.module_from_spec(spec)
spec.loader.exec_module(F)

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print("FAIL:", what)


def sha(b):
    return hashlib.sha256(b).hexdigest()


# the real table
table = F.expected_files(F.PACKS)
check(len(table) == sum(len(p["files"]) for p in F.PACKS.values()), "file names are unique over the packs")
check(all(len(d) == 64 and set(d) <= set("0123456789abcdef") for d in table.values()), "every hash is 64 hex digits")
check(all(len(p["sha"]) == 40 for p in F.PACKS.values()), "every pack is pinned to a 40 digit commit")
check(all(os.sep not in n and "/" not in n and not n.startswith(".") for n in table), "file names are plain names")
check(F.archive_url(F.PACKS["skeletons"]).startswith("https://codeload.github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0/zip/15b62b9"), "archive url")
for need in ("Knight.fbx", "Barbarian.fbx", "Mage.fbx", "Rogue.fbx", "RogueHooded.fbx", "Skeleton_Warrior.fbx", "Skeleton_Mage.fbx",
             "Skeleton_Rogue.fbx", "Skeleton_Minion.fbx", "skeleton_texture.png", "knight_texture.png", "LICENSE_Adventurers.txt", "LICENSE_Skeletons.txt"):
    check(need in table, need + " is fetched")

# a fake pack and archive
body_a, body_b, lic = b"fbx-a" * 10, b"png-b" * 5, b"CC0 license"
pack = {"repo": "x/y", "sha": "0" * 40, "base": "addons/pack/", "files": [
    ("Characters/fbx/A.fbx", "A.fbx", sha(body_a)),
    ("Characters/fbx/b.png", "b.png", sha(body_b)),
    ("LICENSE.txt", "LICENSE_Fake.txt", sha(lic)),
]}


def make_zip(entries, root="y-" + "0" * 40 + "/"):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in entries.items():
            z.writestr(root + name, data)
    return buf.getvalue()


good = {"addons/pack/Characters/fbx/A.fbx": body_a, "addons/pack/Characters/fbx/b.png": body_b, "addons/pack/LICENSE.txt": lic,
        "addons/pack/Characters/fbx/Other.fbx": b"not in the table", "README.md": b"x"}
check(F.find_root(zipfile.ZipFile(io.BytesIO(make_zip(good))).namelist()) == "y-" + "0" * 40 + "/", "the archive root is found")
check(F.find_root(["a/x", "b/y"]) == "" and F.find_root(["x"]) == "", "no single root: empty")

with tempfile.TemporaryDirectory() as tmp:
    out = os.path.join(tmp, "out")
    names = F.extract(zipfile.ZipFile(io.BytesIO(make_zip(good))), pack, out)
    check(names == ["A.fbx", "b.png", "LICENSE_Fake.txt"], "extract writes the table's files in order")
    check(sorted(os.listdir(out)) == ["A.fbx", "LICENSE_Fake.txt", "b.png"], "nothing else is written (no Other.fbx, no .part left)")
    check(open(os.path.join(out, "A.fbx"), "rb").read() == body_a, "file content is kept")
    check(F.check_dir(out, {"fake": pack}) == ([], []), "check_dir: all there")
    open(os.path.join(out, "b.png"), "wb").write(b"changed")
    os.remove(os.path.join(out, "A.fbx"))
    check(F.check_dir(out, {"fake": pack}) == (["A.fbx"], ["b.png"]), "check_dir: one missing, one wrong")

    # fetch: repairs only what is wrong, from a local archive; never downloads when a zip is given
    zpath = os.path.join(tmp, "fake.zip")
    open(zpath, "wb").write(make_zip(good))
    logs = []

    def no_net(url, dest):
        raise AssertionError("must not download")

    F.fetch(out, {"fake": pack}, zips={"fake": zpath}, log=logs.append, opener=no_net)
    check(F.check_dir(out, {"fake": pack}) == ([], []), "fetch repairs the missing and the wrong file")
    check("fake: wrote 2 files" in logs, "fetch writes only the files that were wrong")
    logs.clear()
    F.fetch(out, {"fake": pack}, log=logs.append, opener=no_net)
    check(logs == ["fake: all 3 files present"], "a complete folder downloads nothing")

    # fetch through the download hook: the archive is fetched into a temp file and the temp folder is removed
    seen = {}

    def fake_download(url, dest):
        seen["url"], seen["dest"] = url, dest
        open(dest, "wb").write(make_zip(good))
        return 123

    out2 = os.path.join(tmp, "out2")
    F.fetch(out2, {"fake": pack}, log=lambda s: None, opener=fake_download)
    check(seen["url"] == "https://codeload.github.com/x/y/zip/" + "0" * 40, "download url is codeload at the pinned commit")
    check(not os.path.exists(seen["dest"]) and not os.path.exists(os.path.dirname(seen["dest"])), "the temp archive is removed")
    check(F.check_dir(out2, {"fake": pack}) == ([], []), "fetch through the hook fills the folder")

    # errors
    def raises(entries, pk=pack, size=None):
        out3 = os.path.join(tmp, "out3")
        old = F.MAX_FILE
        if size:
            F.MAX_FILE = size
        try:
            F.extract(zipfile.ZipFile(io.BytesIO(make_zip(entries))), pk, out3)
        except ValueError as e:
            return str(e), out3
        finally:
            F.MAX_FILE = old
        return None, out3

    bad = dict(good)
    bad["addons/pack/Characters/fbx/b.png"] = b"tampered"
    msg, out3 = raises(bad)
    check(msg is not None and "wrong sha256" in msg and "b.png" in msg, "a wrong hash is refused")
    check(not os.path.exists(os.path.join(out3, "b.png")), "a wrong file is not written")
    gone = dict(good)
    del gone["addons/pack/LICENSE.txt"]
    msg, _ = raises(gone)
    check(msg is not None and "not in the archive" in msg, "a missing entry is refused")
    msg, _ = raises(good, size=10)
    check(msg is not None and "over the limit" in msg, "a file over the size limit is refused")

    # a hostile archive entry cannot pick the output name: names come from the table only
    evil = dict(good)
    evil["addons/pack/Characters/fbx/../../../../escape.txt"] = b"x"
    F.extract(zipfile.ZipFile(io.BytesIO(make_zip(evil))), pack, os.path.join(tmp, "out4"))
    check(not os.path.exists(os.path.join(tmp, "escape.txt")) and not os.path.exists(os.path.join(tmp, "out4", "escape.txt")), "archive names never become output paths")

    # main --check on an empty and a full folder, with the real table
    with contextlib.redirect_stderr(io.StringIO()):
        rc_empty = F.main(["--check", "--out", os.path.join(tmp, "nothing")])
        rc_bad = F.main(["--zip", "nope=x"])
    check(rc_empty == 1, "main --check on an empty folder fails")
    check(rc_bad == 2, "main refuses an unknown pack")

print("fetch_3d_assets_test: %s" % ("FAILED %d" % failed if failed else "ok"))
sys.exit(1 if failed else 0)
