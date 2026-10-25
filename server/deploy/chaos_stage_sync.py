#!/usr/bin/env python3
"""The staging copy of a server folder (chaos_kit_update.sh apply, server/README.md "Updating the kit server"): what the
running game changed in the live folder while the update installed into the copy.

usage: python3 -I chaos_stage_sync.py manifest SERVER OUT.json
       python3 -I chaos_stage_sync.py sync LIVE STAGE MANIFEST.json [--ignore REL]... [--dry-run]

manifest  taken from the live folder just before the copy: for every file under SERVER (not data/logs, data/reports,
          not a *.otbm.tmp) its size, modification time and, when it is under 64 MB and not a map, its SHA-1; a link
          by its target. The game writes a few files while it runs (the client services file, a config.lua.before-*
          backup of `chaos-ctl.sh xp-rate`, a report, the switch of `chaos-ctl.sh beta-mode`, ...); the manifest tells
          which ones.
sync      run with the game stopped, before the copy takes the live folder's place: every file the live folder has
          added, changed or removed since the manifest is brought over to STAGE, unless the install changed the same
          file in STAGE too. A file the install changed and the game changed is a conflict: nothing is written, the
          files are listed ("conflict REL") and the exit status is 3, so the caller keeps the live folder. The same
          content on both sides is no conflict. --ignore REL: not looked at (config.lua: the caller handles the XP
          rates itself). --dry-run: only list.
          Lines: "copied REL", "removed REL", "conflict REL", "ignored REL"; last line "synced N file(s)" (exit 0).
Exit: 0 ok, 3 conflict, 1 error.
Python 3 standard library.
"""
import hashlib
import json
import os
import shutil
import sys

SKIP_DIRS = ('data/logs', 'data/reports')
HASH_LIMIT = 64 * 1024 * 1024


def skipped(rel):
    return rel.endswith('.otbm.tmp') or any(rel == d or rel.startswith(d + '/') for d in SKIP_DIRS)


def sha1(path):
    h = hashlib.sha1()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def entry(path, rel, hashed=True):
    """[size, mtime_ns, sha1 or ''] of a file, ['L', target] of a link"""
    if os.path.islink(path):
        return ['L', os.readlink(path)]
    st = os.stat(path)
    digest = ''
    if hashed and st.st_size <= HASH_LIMIT and not rel.endswith('.otbm'):
        digest = sha1(path)
    return [st.st_size, st.st_mtime_ns, digest]


def walk(root, hashed=True):
    out = {}
    for base, dirs, files in os.walk(root):
        rel_base = os.path.relpath(base, root).replace(os.sep, '/')
        rel_base = '' if rel_base == '.' else rel_base
        dirs[:] = sorted(d for d in dirs if not skipped((rel_base + '/' + d).lstrip('/')))
        for name in sorted(files):
            rel = (rel_base + '/' + name).lstrip('/')
            if skipped(rel):
                continue
            try:
                out[rel] = entry(os.path.join(root, rel), rel, hashed)
            except OSError:
                continue  # gone while walking
        for d in dirs:  # links to folders are listed as links
            rel = (rel_base + '/' + d).lstrip('/')
            if os.path.islink(os.path.join(root, rel)):
                out[rel] = ['L', os.readlink(os.path.join(root, rel))]
    return out


def same_file(a, b):
    """the two entries are the same content: links by target, files by SHA-1 (else by size and time)"""
    if a is None or b is None:
        return a is b
    if a[0] == 'L' or b[0] == 'L':
        return a == b
    if a[2] and b[2]:
        return a[2] == b[2]
    return a[0] == b[0] and a[1] == b[1]


def live_changes(live, manifest):
    """rel -> 'added' | 'changed' | 'removed' of the live folder against the manifest"""
    now = walk(live, hashed=False)
    out = {}
    for rel, cur in now.items():
        old = manifest.get(rel)
        if old is None:
            out[rel] = 'added'
        elif cur[0] == 'L' or old[0] == 'L':
            if cur != old:
                out[rel] = 'changed'
        elif cur[0] != old[0] or cur[1] != old[1]:
            # the stat differs: a rewrite with the same content is no change
            if not old[2] or cur[0] != old[0] or sha1(os.path.join(live, rel)) != old[2]:
                out[rel] = 'changed'
    for rel in manifest:
        if rel not in now and not skipped(rel):
            out[rel] = 'removed'
    return out


def stage_entry(stage, rel):
    p = os.path.join(stage, rel)
    if not os.path.lexists(p):
        return None
    return entry(p, rel)


def plan(live, stage, manifest, ignore=()):
    """(actions, conflicts, ignored): actions are (rel, 'copy' | 'remove')"""
    actions, conflicts, ignored = [], [], []
    for rel, kind in sorted(live_changes(live, manifest).items()):
        if rel in ignore:
            ignored.append(rel)
            continue
        old = manifest.get(rel)
        mine = stage_entry(stage, rel)
        theirs = None if kind == 'removed' else entry(os.path.join(live, rel), rel)
        if same_file(mine, theirs):
            continue  # the same on both sides already
        # untouched by the install: absent as it was absent, or equal to what the manifest saw
        untouched = (mine is None) if old is None else (mine is not None and same_file(mine, old))
        if untouched:
            actions.append((rel, 'remove' if kind == 'removed' else 'copy'))
        else:
            conflicts.append(rel)
    return actions, conflicts, ignored


def apply_actions(live, stage, actions):
    for rel, act in actions:
        dst = os.path.join(stage, rel)
        if act == 'remove':
            if os.path.lexists(dst):
                os.remove(dst)
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.lexists(dst):
            os.remove(dst)
        src = os.path.join(live, rel)
        if os.path.islink(src):
            os.symlink(os.readlink(src), dst)
        else:
            shutil.copy2(src, dst)


def main(argv):
    if len(argv) == 3 and argv[0] == 'manifest':
        data = walk(argv[1])
        tmp = argv[2] + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(data, f)
        os.replace(tmp, argv[2])
        print('manifest: %d file(s)' % len(data))
        return 0
    if len(argv) >= 4 and argv[0] == 'sync':
        live, stage, mpath = argv[1:4]
        ignore, dry, i = [], False, 4
        while i < len(argv):
            if argv[i] == '--ignore' and i + 1 < len(argv):
                ignore.append(argv[i + 1])
                i += 2
            elif argv[i] == '--dry-run':
                dry = True
                i += 1
            else:
                print(__doc__)
                return 1
        with open(mpath, encoding='utf-8') as f:
            manifest = json.load(f)
        actions, conflicts, ignored = plan(live, stage, manifest, set(ignore))
        for rel in ignored:
            print('ignored ' + rel)
        if conflicts:
            for rel in conflicts:
                print('conflict ' + rel)
            return 3
        if not dry:
            apply_actions(live, stage, actions)
        for rel, act in actions:
            print(('copied ' if act == 'copy' else 'removed ') + rel)
        print('synced %d file(s)' % len(actions))
        return 0
    print(__doc__)
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
