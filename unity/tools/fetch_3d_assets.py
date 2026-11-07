"""Fetches the KayKit 3D characters of the Unity prototype (unity/README.md "3D characters").

The two KayKit packs (CC0, Kay Lousberg, docs/CREDITS.md) are too big to commit: every character FBX is about 20 MB with
about 90 animation takes. This script downloads each upstream repository as a GitHub zip archive at a PINNED commit,
extracts only the files the client uses into unity/Client/Assets/Chaos/Resources/KayKit/ (git-ignored) and checks every
extracted file against the sha256 in the table below. Anything not in the table is never written.

    python3 -I unity/tools/fetch_3d_assets.py            # fetch what is missing or wrong, then check
    python3 -I unity/tools/fetch_3d_assets.py --check    # verify the files already present (exit 1 on a miss)
    python3 -I unity/tools/fetch_3d_assets.py --force    # download again even when everything is present
    python3 -I unity/tools/fetch_3d_assets.py --zip adventurers=PATH --zip skeletons=PATH   # offline: use these archives

Why per-file hashes and no zip hash: a commit pins the content, a GitHub-built zip need not keep its bytes between builds,
so the hash of each used file is the stable check. Stdlib only. The archives are untrusted data: names are looked up in the
table, never joined from the archive, sizes are bounded and nothing is executed.
"""
import argparse
import hashlib
import io
import os
import sys
import tempfile
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "unity", "Client", "Assets", "Chaos", "Resources", "KayKit")
CODELOAD = "https://codeload.github.com/{repo}/zip/{sha}"
MAX_ZIP = 400 * 1024 * 1024        # the largest archive is about 140 MB
MAX_FILE = 64 * 1024 * 1024        # the largest used file is about 23 MB
TIMEOUT = 60

# name -> (repo, pinned commit, folder inside the archive, [(path in that folder, file name written, sha256)])
PACKS = {
    "adventurers": {
        "repo": "KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0",
        "sha": "672074b73ba276876a19e8816ecdc5241817ab47",
        "base": "addons/kaykit_character_pack_adventures/",
        "files": [
            ("Characters/fbx/Knight.fbx", "Knight.fbx", "b25e35cc7eaaa3c7c103f10a4f41fde1cbd81936fede9aa9ae4efbd29d40ba1b"),
            ("Characters/fbx/Barbarian.fbx", "Barbarian.fbx", "902a7c0092714c21f148b42ca8921ba7ac66e74f16c8af5088a3d224663ed597"),
            ("Characters/fbx/Mage.fbx", "Mage.fbx", "93b401d56e2547316f8841a4ac0086011c64d79185c9cb7623567c2dbf125c7d"),
            ("Characters/fbx/Rogue.fbx", "Rogue.fbx", "93a9ee0a67ae69b2d815050234acad2004c3b8af7d294b916e52609c8195eb71"),
            ("Characters/fbx/RogueHooded.fbx", "RogueHooded.fbx", "4a773f074695c6c089cc6f059eed85da080928a4a4137af4e38b177139d4cc27"),
            ("Characters/fbx/knight_texture.png", "knight_texture.png", "5d250ccc5da020e6126bfa3839f83bd9a465a951ed223e4d13c08b1925e154d4"),
            ("Characters/fbx/barbarian_texture.png", "barbarian_texture.png", "7329b2ff9709e8d54c886d5ef49c08bd42b12be3bbb2facb1488a6b48b1e8a80"),
            ("Characters/fbx/mage_texture.png", "mage_texture.png", "ea49f094b960402635fe51db9f1864960c97271b17f2e3554e5aca1b2bbba144"),
            ("Characters/fbx/rogue_texture.png", "rogue_texture.png", "a4032e877c3b91939f5cdbb630349c1998fdbc3211bbd587c111125500fe4cc5"),
            ("LICENSE.txt", "LICENSE_Adventurers.txt", "ae322141814056dda0deea7540d74c41d87aee1da319977cd1bd84ee5a923629"),
        ],
    },
    "skeletons": {
        "repo": "KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0",
        "sha": "15b62b9bad122f72926c10fb14d622c73819fa54",
        "base": "addons/kaykit_character_pack_skeletons/",
        "files": [
            ("Characters/fbx/Skeleton_Warrior.fbx", "Skeleton_Warrior.fbx", "783d88baface5b5aec4be3a1bdfe360e12e091dae753b3968161e7a69bd0c279"),
            ("Characters/fbx/Skeleton_Mage.fbx", "Skeleton_Mage.fbx", "a5b6a9e9c690b2c23f52aa7a18aef411b56e9c660229c7e2d0f217f78752573c"),
            ("Characters/fbx/Skeleton_Rogue.fbx", "Skeleton_Rogue.fbx", "2961f9cb6640f4627db4b9213b7b349270dc737a4c9b5f7aa5f078203887f78d"),
            ("Characters/fbx/Skeleton_Minion.fbx", "Skeleton_Minion.fbx", "440381230027cb691d8a57c923b41d90ed66236f7a867fff86f5fb51a5315723"),
            ("Characters/fbx/skeleton_texture.png", "skeleton_texture.png", "15741a25c53e04fa9bf3beac3bc0de442359404b1ff9be863b892cb551ad3657"),
            ("Assets/fbx/Skeleton_Blade.fbx", "Skeleton_Blade.fbx", "16c3d747dcbb0fc12902f4d99a31edee06c02348815308dc19a02ac1955ee515"),
            ("Assets/fbx/Skeleton_Axe.fbx", "Skeleton_Axe.fbx", "b921180f7cc55306c4907e51676d3f7b6cecf0ab2f90095e269ba807e023f55c"),
            ("Assets/fbx/Skeleton_Staff.fbx", "Skeleton_Staff.fbx", "7b9fa1ec537d6c5d609e83c2e3d13e247ca252716cab36a6fa83a63100145457"),
            ("Assets/fbx/Skeleton_Crossbow.fbx", "Skeleton_Crossbow.fbx", "51f4262edab36a36a854f63d96ed7085de818cc606e91e5b48c4a5028eae0491"),
            ("Assets/fbx/Skeleton_Shield_Small_A.fbx", "Skeleton_Shield_Small_A.fbx", "5bec95be571aa131bda1c66eefcfd172b84ccb7d710e635d2eca0064dcaea256"),
            ("Assets/fbx/Skeleton_Shield_Large_A.fbx", "Skeleton_Shield_Large_A.fbx", "af3716e0e3fe2f3a32e23a8c367bd556f75c208566c5b47c30cdba8bd19c1764"),
            ("LICENSE.txt", "LICENSE_Skeletons.txt", "5d822abca4e08c5a91d329e5372b3dc605cba8d994f752cb0f7dfdb7a0a79954"),
        ],
    },
}


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def archive_url(pack):
    return CODELOAD.format(repo=pack["repo"], sha=pack["sha"])


def expected_files(packs):
    """Every file the client expects: file name -> sha256 (names must be unique over all packs)."""
    out = {}
    for key, pack in packs.items():
        for _src, name, digest in pack["files"]:
            if name in out:
                raise ValueError("duplicate file name " + name + " in " + key)
            out[name] = digest
    return out


def check_dir(out_dir, packs):
    """The names that are missing and the names whose hash differs, in the table's order."""
    missing, wrong = [], []
    for name, digest in expected_files(packs).items():
        path = os.path.join(out_dir, name)
        if not os.path.isfile(path):
            missing.append(name)
        elif sha256_file(path) != digest:
            wrong.append(name)
    return missing, wrong


def find_root(names):
    """The folder every entry of a GitHub archive sits in ("REPO-SHA/"), or "" when there is none."""
    firsts = {n.split("/", 1)[0] for n in names if "/" in n}
    return next(iter(firsts)) + "/" if len(firsts) == 1 else ""


def extract(zf, pack, out_dir, only=None):
    """Writes the files of `pack` found in the open zip into out_dir, each checked against its hash. Returns the names written.
    Raises ValueError on a missing entry, a size over MAX_FILE or a wrong hash; nothing is written for that file then."""
    root = find_root(zf.namelist())
    infos = {i.filename: i for i in zf.infolist()}
    written = []
    os.makedirs(out_dir, exist_ok=True)
    for src, name, digest in pack["files"]:
        if only is not None and name not in only:
            continue
        entry = root + pack["base"] + src
        info = infos.get(entry)
        if info is None:
            raise ValueError("not in the archive: " + entry)
        if info.file_size > MAX_FILE:
            raise ValueError(entry + " is " + str(info.file_size) + " bytes, over the limit")
        data = zf.read(info)
        if sha256_bytes(data) != digest:
            raise ValueError(entry + " has the wrong sha256 (" + sha256_bytes(data) + ")")
        tmp = os.path.join(out_dir, name + ".part")
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, os.path.join(out_dir, name))
        written.append(name)
    return written


def download(url, dest):
    """Streams url to the file dest (at most MAX_ZIP bytes)."""
    req = urllib.request.Request(url, headers={"User-Agent": "chaos-fetch-3d-assets"})
    total = 0
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r, open(dest, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_ZIP:
                raise ValueError("archive over " + str(MAX_ZIP) + " bytes")
            f.write(chunk)
    return total


def fetch(out_dir, packs, zips=None, force=False, log=print, opener=download):
    """Fetches every pack that has a missing or wrong file (all of them with force). `zips` maps a pack key to a local archive."""
    zips = zips or {}
    for key, pack in packs.items():
        need = list(expected_files({key: pack}))
        missing, wrong = check_dir(out_dir, {key: pack})
        todo = need if force else missing + wrong
        if not todo:
            log(key + ": all " + str(len(need)) + " files present")
            continue
        path = zips.get(key)
        tmpdir = None
        try:
            if path is None:
                tmpdir = tempfile.mkdtemp(prefix="kaykit_")
                path = os.path.join(tmpdir, key + ".zip")
                url = archive_url(pack)
                log(key + ": downloading " + url)
                n = opener(url, path)
                log(key + ": " + str(n) + " bytes")
            with zipfile.ZipFile(path) as zf:
                done = extract(zf, pack, out_dir, only=set(todo))
            log(key + ": wrote " + str(len(done)) + " files")
        finally:
            if tmpdir is not None:
                for f in os.listdir(tmpdir):
                    os.remove(os.path.join(tmpdir, f))
                os.rmdir(tmpdir)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true", help="only verify the files already present")
    ap.add_argument("--force", action="store_true", help="download again even when everything is present")
    ap.add_argument("--zip", action="append", default=[], metavar="PACK=PATH", help="use a local archive for a pack (adventurers, skeletons)")
    ap.add_argument("--out", default=OUT_DIR, help="output folder (default: Resources/KayKit)")
    a = ap.parse_args(argv)
    if not a.check:
        zips = {}
        for z in a.zip:
            k, _, p = z.partition("=")
            if k not in PACKS or not p:
                print("--zip wants PACK=PATH with PACK one of " + ", ".join(PACKS), file=sys.stderr)
                return 2
            zips[k] = p
        try:
            fetch(a.out, PACKS, zips=zips, force=a.force)
        except (OSError, ValueError, zipfile.BadZipFile) as e:
            print("fetch failed: " + str(e), file=sys.stderr)
            return 1
    missing, wrong = check_dir(a.out, PACKS)
    for n in missing:
        print("missing: " + n, file=sys.stderr)
    for n in wrong:
        print("wrong sha256: " + n, file=sys.stderr)
    if missing or wrong:
        return 1
    print("KayKit: " + str(len(expected_files(PACKS))) + " files in " + os.path.relpath(a.out, ROOT) + ", sha256 ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
