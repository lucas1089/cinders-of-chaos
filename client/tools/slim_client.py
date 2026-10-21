#!/usr/bin/env python3
"""Slim the assembled client: remove the files it never uses, and check that every referenced file is still there.

  python3 -I client/tools/slim_client.py prune GAME_DIR [--dry-run]   # apply client/tools/slim_prune.txt
  python3 -I client/tools/slim_client.py check GAME_DIR               # every static file reference resolves
  python3 -I client/tools/slim_client.py refs  GAME_DIR               # list the unresolved references (baseline work)

GAME_DIR is the tree client/tools/assemble_client.sh writes (base client + base-patches + overlay). assemble_client.sh
runs `prune` after the overlay is copied, so the files never reach the pack (pack_client.py packs what is left).

Rules (client/tools/slim_prune.txt): one rule per line, `- GLOB` removes the files that match, `+ GLOB` keeps a file a
`-` rule matched. GLOB is a path relative to GAME_DIR with fnmatch wildcards (`*` also crosses `/`). Lines starting
with `#` are the reason of the rules below them (client/BASE.md "Slim client" lists the groups).

The check reads every .otui/.otml/.otfont/.otmod/.lua file of the tree and collects the static references:
  * otui/otml/otfont values of image-source, icon-source, icon, image, source, texture, font-file;
  * Lua string literals that are a whole resource path ('/images/...', '/data/...', '/sounds/...', '/modules/...',
    '/mods/...', '/fonts/...', '/shaders/...', '/cursors/...', '/game_...'), not glued to a `..` concatenation;
  * otmod `scripts: [ ... ]` and `dofile`/`dofiles`/`importStyle`/`loadUI`/`displayUI` calls with a literal name.
A reference resolves as the engine does (ResourceManager::resolvePath): relative to the file's folder unless it
starts with '/', then under /mods, /data and /modules, with the usual extensions added. Computed paths ('/images/x/'
.. name) are not checked; slim_prune.txt never removes a folder addressed that way.

`check` fails when a reference does not resolve and is not in client/tools/slim_known_missing.txt (references the
base client already had broken: files it never shipped). It also fails when a reference points at a path a prune rule
removes, so a new reference to a pruned file is caught even when the file is gone from the tree being checked.
"""
import argparse
import fnmatch
import os
import posixpath
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RULES_FILE = os.path.join(HERE, 'slim_prune.txt')
KNOWN_MISSING_FILE = os.path.join(HERE, 'slim_known_missing.txt')

SCAN_ROOTS = ('init.lua', 'data', 'modules', 'mods', 'layouts')
SCAN_EXT = ('.lua', '.otui', '.otml', '.otfont', '.otmod')
TRY_EXT = ('', '.png', '.otui', '.lua', '.otfont', '.otml', '.frag', '.apng', '.gif', '.jpg', '.ogg', '.wav', '.json',
           '.ttf', '.otf')
SEARCH_PREFIXES = ('', '/mods', '/data', '/modules')

OTUI_KEYS = {'image-source', 'icon-source', 'icon', 'image', 'source', 'texture', 'font-file', 'image-source-hover',
             'image-source-pressed', 'image-source-disabled'}
LUA_PATH_START = ('/images/', '/data/', '/sounds/', '/modules/', '/mods/', '/fonts/', '/shaders/', '/cursors/',
                  '/game_', '/client_')
# write-dir paths and folders the client creates at run time
RUNTIME_PREFIXES = ('/characterdata/', '/settings/', '/downloads/', '/screenshots', '/minimap.otmm', '/config.otml',
                    '/chaos_update', '/data/things/')
LUA_LIT = re.compile(r"""(\.\.\s*)?(["'])((?:(?!\2)[^\\\n])*)\2(\s*\.\.)?""")
LUA_CALL = re.compile(r"""\b(dofile|dofiles|importStyle|loadUI|displayUI)\s*\(?\s*(["'])([^"'\n]+)\2(?!\s*\.\.)""")
OTMOD_SCRIPTS = re.compile(r"^\s*scripts:\s*\[([^\]]*)\]", re.M)
ONLOAD_CALL = re.compile(r"""^\s*(dofile|dofiles|importStyle)\s*\(?\s*(["'])([^"'\n]+)\2""", re.M)


def load_rules(path=RULES_FILE):
    rules, reason = [], ''
    with open(path, encoding='utf-8') as fh:
        for no, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line:
                continue
            if line.startswith('#'):
                reason = line.lstrip('#').strip() or reason
                continue
            op, _, glob = line.partition(' ')
            glob = glob.strip()
            if op not in ('-', '+') or not glob or glob.startswith('/') or '..' in glob.split('/'):
                raise SystemExit(f'{path}:{no}: bad rule {line!r} (want "- GLOB" or "+ GLOB", relative)')
            rules.append((op, glob, reason))
    return rules


def pruned(rel, rules):
    """The reason of the `-` rule that removes rel (a path relative to the game dir), or None when it is kept."""
    hit = None
    for op, glob, reason in rules:
        if fnmatch.fnmatchcase(rel, glob):
            hit = reason if op == '-' else None
    return hit


def walk_files(game):
    for root in SCAN_ROOTS:
        top = os.path.join(game, root)
        if os.path.isfile(top):
            yield root
            continue
        for dp, dn, fn in os.walk(top):
            dn.sort()
            for name in sorted(fn):
                yield os.path.relpath(os.path.join(dp, name), game).replace(os.sep, '/')


def prune(game, rules, dry_run=False):
    groups = {}
    for rel in list(walk_files(game)):
        reason = pruned(rel, rules)
        if reason is None:
            continue
        full = os.path.join(game, rel)
        size = os.path.getsize(full)
        g = groups.setdefault(reason, [0, 0])
        g[0] += 1
        g[1] += size
        if not dry_run:
            os.remove(full)
    if not dry_run:
        for root in SCAN_ROOTS:
            top = os.path.join(game, root)
            for dp, dn, fn in os.walk(top, topdown=False):
                if dp != top and not os.listdir(dp):
                    os.rmdir(dp)
    total = sum(v[1] for v in groups.values())
    for reason, (n, size) in sorted(groups.items(), key=lambda kv: -kv[1][1]):
        print(f'  {size / 1048576:8.2f} MB {n:5d} files  {reason}')
    print(f'slim: {"would remove" if dry_run else "removed"} {sum(v[0] for v in groups.values())} files, '
          f'{total / 1048576:.1f} MB')
    return groups


def _refs_of(rel, text):
    """Yield (lineno, ref, kind) for the static references in one file."""
    ext = os.path.splitext(rel)[1]
    if ext in ('.otui', '.otml', '.otfont'):
        for no, line in enumerate(text.splitlines(), 1):
            s = line.strip()
            if s.startswith('//') or ':' not in s or s.startswith('@') or s.startswith('!'):
                continue
            key, _, val = s.partition(':')
            key, val = key.strip(), val.strip()
            if key in OTUI_KEYS and val and val != 'none' and ' ' not in val and not any(c in val for c in '()"\'#'):
                yield no, val, 'res'
    if ext == '.otmod':
        for m in OTMOD_SCRIPTS.finditer(text):
            no = text.count('\n', 0, m.start()) + 1
            for name in m.group(1).split(','):
                name = name.strip()
                if name:
                    yield no, name, 'lua'
        for m in ONLOAD_CALL.finditer(text):
            no = text.count('\n', 0, m.start()) + 1
            kind = {'dofile': 'lua', 'dofiles': 'dir', 'importStyle': 'otui'}[m.group(1)]
            yield no, m.group(3), kind
    if ext == '.lua':
        for no, line in enumerate(text.splitlines(), 1):
            code = line.split('--', 1)[0] if '--' in line and '"--' not in line and "'--" not in line else line
            for m in LUA_CALL.finditer(code):
                kind = {'dofile': 'lua', 'dofiles': 'dir', 'importStyle': 'otui', 'loadUI': 'otui',
                        'displayUI': 'otui'}[m.group(1)]
                yield no, m.group(3), kind
            for m in LUA_LIT.finditer(code):
                lit = m.group(3)
                if m.group(1) or m.group(4) or not lit.startswith(LUA_PATH_START) or lit.endswith('/'):
                    continue
                if any(c in lit for c in '%*?[') or ' ' in lit:
                    continue
                yield no, lit, 'res'


def _exists(game, logical):
    p = os.path.join(game, logical.lstrip('/'))
    return os.path.isfile(p)


def resolve(game, src_rel, ref, kind):
    """The logical path the reference resolves to, or None. Also returns the paths tried."""
    if ref.startswith(RUNTIME_PREFIXES):
        return ref, []
    base = ref if ref.startswith('/') else '/' + posixpath.join(posixpath.dirname(src_rel), ref)
    base = posixpath.normpath(base.replace('//', '/'))
    exts = TRY_EXT
    if kind == 'lua':
        exts = ('.lua', '')
    elif kind == 'otui':
        exts = ('.otui', '')
    tried = []
    for pre in SEARCH_PREFIXES:
        for ext in exts:
            cand = pre + base + ext if not (ext and base.endswith(ext)) else pre + base
            tried.append(cand)
            if kind == 'dir':
                if os.path.isdir(os.path.join(game, cand.lstrip('/'))):
                    return cand, tried
            elif _exists(game, cand) or (kind == 'res' and not ext and
                                         os.path.isdir(os.path.join(game, cand.lstrip('/')))):
                return cand, tried
    return None, tried


def collect(game):
    """Every static reference: list of (src_rel, lineno, ref, kind, resolved_or_None, tried)."""
    out = []
    for rel in walk_files(game):
        if not rel.endswith(SCAN_EXT) or rel.endswith('_test.lua'):
            continue
        try:
            with open(os.path.join(game, rel), encoding='utf-8', errors='replace') as fh:
                text = fh.read()
        except OSError:
            continue
        for no, ref, kind in _refs_of(rel, text):
            got, tried = resolve(game, rel, ref, kind)
            out.append((rel, no, ref, kind, got, tried))
    return out


def load_known_missing(path=KNOWN_MISSING_FILE):
    known = set()
    if os.path.isfile(path):
        with open(path, encoding='utf-8') as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith('#'):
                    known.add(line)
    return known


def missing_key(src_rel, ref):
    return f'{src_rel} {ref}'


def check(game, rules, known):
    errors = []
    unresolved = 0
    for rel, no, ref, kind, got, tried in collect(game):
        if pruned(rel, rules):
            continue  # a file the prune removes (checked before the prune): its references go with it
        if got is None:
            unresolved += 1
            if missing_key(rel, ref) not in known:
                errors.append(f'{rel}:{no}: {ref!r} resolves to no file')
            continue
        if not tried:
            continue
        # a reference to a path a prune rule removes (the file is still in this tree: a check before the prune)
        for cand in tried:
            reason = pruned(cand.lstrip('/'), rules)
            if reason and _exists(game, cand) and cand == got:
                errors.append(f'{rel}:{no}: {ref!r} is removed by slim_prune.txt ({reason})')
                break
    return errors, unresolved


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=('prune', 'check', 'refs'))
    ap.add_argument('game')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--rules', default=RULES_FILE)
    ap.add_argument('--known-missing', default=KNOWN_MISSING_FILE)
    a = ap.parse_args(argv)
    if not os.path.isfile(os.path.join(a.game, 'init.lua')):
        sys.exit(f'not an assembled client tree (no init.lua): {a.game}')
    rules = load_rules(a.rules)
    if a.cmd == 'prune':
        prune(a.game, rules, a.dry_run)
        return 0
    if a.cmd == 'refs':
        for rel, no, ref, kind, got, tried in collect(a.game):
            if got is None:
                print(missing_key(rel, ref))
        return 0
    errors, unresolved = check(a.game, rules, load_known_missing(a.known_missing))
    for e in errors:
        print(e)
    refs = len(collect(a.game))
    print(f'slim check: {refs} references, {unresolved} unresolved, {len(errors)} errors')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
