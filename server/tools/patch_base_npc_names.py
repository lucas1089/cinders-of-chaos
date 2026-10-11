#!/usr/bin/env python3
"""Give the base NPCs Cinders of Chaos names (server/README.md "Base NPC names").

usage: python3 -I patch_base_npc_names.py DATA_DIR [--names CSV] [--dry-run]

The new names come from server/data/npc/base_npc_names.csv (columns sha256, name, kind, match; see base_rename_lib.py).
The sha256 column is the SHA-256 of the old name in lower case, so the repository holds no old name: the tool reads
the names the base data uses, hashes each one and renames the ones the CSV knows. kind is `npc` (a name an NPC shows,
also used for its dialogue by patch_base_texts.py) or `file` (an NPC file name that is not the shown name).

The engine loads an NPC by file name: a spawn entry <npc name="X"/> loads data/npc/X.xml, whose <npc name="..."> is the
name players see. So:
1. data/npc/*.xml: the name attribute gets the new name, and the file is renamed to the new file name (the row of
   its file name, else the row of its shown name, kept in lower case when the old file name was). The script file it
   names keeps its path (scripts are not seen by players; several tools patch them by path).
2. data/world and data/raids: every <npc name="X"/> of a renamed file gets the new file name.
3. Lua files of the base data (not data/scripts/chaos, not data/lib/chaos_*.lua): a string literal that is exactly
   an old file name (Game.createNpc("X", ...)) gets the new file name.
The NPCs this repository installs (server/data/npc) are ours and are skipped.
Dialogue, keywords and other mentions of the old names are patch_base_texts.py's work (step `worldtexts`).

A file is not renamed when its new name is already taken by another file (listed). Idempotent: a second run finds no
old name and changes nothing. --dry-run writes nothing.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import base_rename_lib as L  # noqa: E402

KINDS = ('npc', 'file')
LUA_DIRS = ('scripts', 'actions', 'creaturescripts', 'globalevents', 'movements', 'talkactions', 'lib', 'events', 'npc',
            'raids', 'spells', 'weapons', 'chatchannels')
SKIP_DIRS = (os.path.join('scripts', 'chaos'), os.path.join('spells', 'chaos'))
NPC_TAG = re.compile(r'(<npc\b[^>]*?\bname=")([^"]*)(")', re.I)


def styled(old, new):
    if old == old.lower():
        return new.lower()
    return new


def plan(npc_dir, rows):
    """-> ([(old path, new path, old shown, new shown)], {old stem: new stem}, notes)"""
    moves, stems, notes = [], {}, []
    own = L.own_npc_files()
    files = sorted(f for f in os.listdir(npc_dir) if f.endswith('.xml') and f not in own) if os.path.isdir(npc_dir) else []
    taken = {f[:-4] for f in files}
    for f in files:
        stem = f[:-4]
        text = L.read(os.path.join(npc_dir, f))
        m = re.search(r'<npc\b[^>]*?\bname="([^"]*)"', text)
        shown = m.group(1) if m else None
        new_shown = shown
        if shown:
            r = rows.get(L.digest(shown))
            if r and r[1] == 'npc':
                new_shown = r[0]
        r = rows.get(L.digest(stem))
        new_stem = styled(stem, r[0]) if r else stem
        if new_stem == stem and shown and stem.lower() == shown.lower() and new_shown != shown:
            new_stem = styled(stem, new_shown)
        if new_stem != stem:
            if new_stem in taken:
                notes.append('npc/%s: new file name %s.xml is taken, file name kept' % (f, new_stem))
                new_stem = stem
            else:
                taken.discard(stem)
                taken.add(new_stem)
                stems[stem] = new_stem
        if new_stem != stem or new_shown != shown:
            moves.append((os.path.join(npc_dir, f), os.path.join(npc_dir, new_stem + '.xml'), shown, new_shown))
    return moves, stems, notes


def lua_files(data):
    for sub in LUA_DIRS:
        for dirpath, dirs, files in os.walk(os.path.join(data, sub)):
            dirs.sort()
            rel = os.path.relpath(dirpath, data)
            if any(rel == d or rel.startswith(d + os.sep) for d in SKIP_DIRS):
                dirs[:] = []
                continue
            for f in sorted(files):
                if f.endswith('.lua') and not (sub == 'lib' and f.startswith('chaos_')):
                    yield os.path.join(dirpath, f)
    g = os.path.join(data, 'global.lua')
    if os.path.isfile(g):
        yield g


def xml_spawn_files(data):
    for sub in ('world', 'raids'):
        for dirpath, dirs, files in os.walk(os.path.join(data, sub)):
            dirs.sort()
            for f in sorted(files):
                if f.endswith('.xml') and not f.endswith('-house.xml'):
                    yield os.path.join(dirpath, f)


def patch_spawns(text, stems):
    n = [0]

    def sub(m):
        new = stems.get(m.group(2))
        if new is None:
            return m.group(0)
        n[0] += 1
        return m.group(1) + new + m.group(3)
    return NPC_TAG.sub(sub, text), n[0]


def patch_lua_names(text, stems):
    n = [0]

    def fn(value):
        new = stems.get(value)
        if new is None:
            return value
        n[0] += 1
        return new
    return L.patch_lua(text, fn), n[0]


def run(data, rows, dry):
    npc_dir = os.path.join(data, 'npc')
    moves, stems, notes = plan(npc_dir, rows)
    writes, removes = {}, []
    shown = 0
    for old, new, s_old, s_new in moves:
        text = L.read(old)
        if s_new != s_old:
            text = re.sub(r'(<npc\b[^>]*?\bname=")[^"]*(")', lambda m: m.group(1) + s_new + m.group(2), text, count=1)
            shown += 1
        writes[new] = text
        if new != old:
            removes.append(old)
    spawns = lua = 0
    # spawn entries name the file; also entries whose file is gone already (an older run) by the CSV
    for p in xml_spawn_files(data):
        t = L.read(p)
        if '<npc' not in t.lower():
            continue
        names = set(m.group(2) for m in NPC_TAG.finditer(t))
        local = dict(stems)
        for n in names:
            if n not in local and not os.path.isfile(os.path.join(npc_dir, n + '.xml')):
                r = rows.get(L.digest(n))
                if r and os.path.isfile(os.path.join(npc_dir, styled(n, r[0]) + '.xml')):
                    local[n] = styled(n, r[0])
        new, k = patch_spawns(t, local)
        if k:
            writes[p] = new
            spawns += k
    if stems:
        for p in lua_files(data):
            t = L.read(p)
            new, k = patch_lua_names(t, stems)
            if k:
                writes[p] = new
                lua += k
    print('npcs: %d file(s) renamed, %d shown name(s) changed, %d spawn entr%s, %d Lua reference(s)'
          % (len(stems), shown, spawns, 'y' if spawns == 1 else 'ies', lua))
    for n in notes:
        print(n)
    for old, new, s_old, s_new in moves[:30]:
        print('  npc/%s -> %s' % (os.path.basename(old), os.path.basename(new)))
    if len(moves) > 30:
        print('  ... and %d more' % (len(moves) - 30))
    if dry:
        print('dry run: nothing written (%d file(s) would change)' % (len(writes) + len(removes)))
        return 0
    for p, t in writes.items():
        L.write(p, t)
    for p in removes:
        if p not in writes and os.path.isfile(p):
            os.remove(p)
    print('%d file(s) written, %d old file(s) removed' % (len(writes), len(removes)))
    return 0


def main(argv):
    dry = '--dry-run' in argv
    names = L.NPC_CSV
    if '--names' in argv:
        k = argv.index('--names')
        if k + 1 >= len(argv):
            print(__doc__)
            return 2
        names = argv[k + 1]
        argv = argv[:k] + argv[k + 2:]
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 2
    data = args[0]
    if not os.path.isdir(os.path.join(data, 'npc')):
        print('not found:', os.path.join(data, 'npc'))
        return 1
    return run(data, L.read_rows(names, KINDS), dry)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
