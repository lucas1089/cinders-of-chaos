#!/usr/bin/env python3
"""Fail if text files mention other servers or clients by name (project rule: no such references).
base-patches/ is skipped: its context lines are copied from the client tree and cannot be edited.
Art pack names (ART_PACKS) are allowed only in the credits (docs/CREDITS.md and the two files gen_credits.py makes
from it): the owner shows the packs' credits in the game and on the website (2026-10-15).

Names added from 2026-10-16 on are kept only as hashes (DENY_HASHES), so they are not written in the repo either:
the first 16 hex digits of sha256 of the lower-case word. A name of up to 3 words or camelCase humps is hashed
joined without spaces ("path of foo" -> pathoffoo). Words are split at non-letters and at camelCase humps
("onFooBarClick" -> on, foo, bar, click), so a hashed name is found inside identifiers too. To add one:
  python3 -c "import hashlib; print(hashlib.sha256(b'name').hexdigest()[:16])"

  python3 -I tools/ci/check_names.py                 # the repo (git ls-files), run from the repo root
  python3 -I tools/ci/check_names.py --client DIR    # an assembled client tree (client/tools/assemble_client.sh)
--client reads what the player can see in the shipped folders (init.lua, modules/, mods/, data/, layouts/): Lua
string literals with a space, a URL or given to tr(); OTUI/OTML text, tooltip, placeholder, title and description
values and any URL; .otmod name and description; every JSON key and value with a space or a URL. Comments,
identifiers, settings keys, .otmod author / website (attribution) and the C++ sources are not read
(client/BASE.md "Names check of the assembled client")."""
import hashlib, json, os, re, subprocess, sys

DENY = re.compile(r'hellgrave|tenkaiser|drakantos|exodus|evolisca|black ?talon|magic ?heard|luminaris|zerion|fonticak|\bastra(?!l)|archlight|'
                  r'demolidores|crystalserver|fortibia|balrog|rubinot|medivia|ravendawn|otservbr|mordragor|'
                  r'jfranci|'
                  r'amon ?ot|albane|zainox|elythion|\btyron\b|oxygen ?ot|world ?of ?fragment|frontiers? ?of ?fantasy|'
                  r'grand ?line|\bgla\b|vision ?ot|boteq', re.I)
DENY_HASHES = {
    '356d28a3e5895f80',  # the base client's bot (side-bar tooltip, base patch 0059)
    '9a7be5bb26fa4e65',  # the maker of the shared potion pack (pair 30)
    'e5336673bc2fb58f',  # an ARPG named in early docs (three words, found as a run of words)
    '6db7636b5922f26c',  # the short form of that ARPG ("PoE" splits into two words, found as a run of words)
    '8c649a8f85f3d89d',  # another ARPG named in early docs
}
ART_PACKS = re.compile(r'\bwst(_|\b)|raven ?fantasy|pixel ?spellcraft|anime ?ki ?auras|mutter ?pixel|pocket ?cozy|bloom ?pixle|'
                       r'pixel ?(status ?effects|projectiles|fireworks|blood ?vfx)|animated ?vfx', re.I)
CREDITS_FILES = ('docs/CREDITS.md', 'client/overlay/modules/client_chaos_credits/credits_data.lua',
                 'website/overlay/plugins/chaos/credits/credits_data.json')
SKIP = ('client/base-patches/', 'tools/ci/check_names.py')
WORD = re.compile(r'[A-Z]+(?![a-z])|[A-Z]?[a-z]+')


def hashed_hit(text):
    words = [w.lower() for w in WORD.findall(text)]
    return any(hashlib.sha256(''.join(words[i:i + n]).encode()).hexdigest()[:16] in DENY_HASHES
               for i in range(len(words)) for n in (1, 2, 3))


def name_hit(text, art_ok=False):
    return bool(DENY.search(text) or (not art_ok and ART_PACKS.search(text)) or hashed_hit(text))


def check_repo():
    files = subprocess.check_output(['git', 'ls-files'], text=True).split('\n')
    bad = 0
    for f in files:
        if not f or f.startswith(SKIP) or f.endswith(('.png', '.jpg', '.dat', '.spr', '.ico')):
            continue
        try:
            text = open(f, encoding='utf-8').read()
        except (UnicodeDecodeError, FileNotFoundError):
            continue
        for i, line in enumerate(text.split('\n'), 1):
            if name_hit(line, art_ok=f in CREDITS_FILES):
                print(f'{f}:{i}: {line.strip()[:100]}'); bad += 1
        if name_hit(f):
            print(f'{f}: file name'); bad += 1
    return bad


# ---------------------------------------------------------------- assembled client tree
CLIENT_ROOTS = ('init.lua', 'modules', 'mods', 'data', 'layouts')
# base files no module reads (checked with grep on the assembled tree, 2026-10-16)
CLIENT_UNUSED = {'data/json/hunting_places.json'}
# strings that match a name but are not one: a creature the helper matches by name (never shown)
CLIENT_ALLOW = {('mods/game_helper/spelldata.json', 'balrog minion')}
# the credits module shows the art packs' names on purpose (gen_credits.py)
CLIENT_ART_OK = {'modules/client_chaos_credits/credits_data.lua'}
LUA_TOKENS = re.compile(r'--\[(=*)\[.*?\]\1\]|--[^\n]*|"((?:\\.|[^"\\\n])*)"|\'((?:\\.|[^\'\\\n])*)\'|\[(=*)\[(.*?)\]\4\]',
                        re.S)
OTUI_PROP = re.compile(r'^\s*!?(text|tooltip|placeholder|title|description)\s*:', re.I)
OTMOD_PROP = re.compile(r'^\s*(name|description)\s*:', re.I)
SHOWN = re.compile(r'\s|://|www\.')


def lua_strings(text):
    """(line, string) for every string literal of a Lua source outside comments."""
    line, pos = 1, 0
    for m in LUA_TOKENS.finditer(text):
        if m.group(0).startswith('--'):
            continue
        line, pos = line + text.count('\n', pos, m.start()), m.start()
        s = m.group(2) if m.group(2) is not None else m.group(3) if m.group(3) is not None else m.group(5)
        before = text[max(0, m.start() - 8):m.start()].replace(' ', '')
        yield line, s, before.endswith('tr(')


def json_strings(node):
    if isinstance(node, dict):
        for k, v in node.items():
            yield k
            yield from json_strings(v)
    elif isinstance(node, list):
        for v in node:
            yield from json_strings(v)
    elif isinstance(node, str):
        yield node


def client_file_hits(rel, text):
    art_ok = rel in CLIENT_ART_OK
    ext = os.path.splitext(rel)[1].lower()
    if ext == '.lua':
        for line, s, in_tr in lua_strings(text):
            if (in_tr or SHOWN.search(s)) and name_hit(s, art_ok):
                yield line, s
    elif ext in ('.otui', '.otml', '.otmod'):
        otmod = ext == '.otmod'
        for i, line in enumerate(text.split('\n'), 1):
            shown = OTMOD_PROP.search(line) if otmod else (OTUI_PROP.search(line) or '://' in line)
            if shown and name_hit(line, art_ok):
                yield i, line.strip()
    elif ext == '.json':
        try:
            data = json.loads(text)
        except ValueError:
            data = None
        if data is None:
            for i, line in enumerate(text.split('\n'), 1):
                if name_hit(line, art_ok):
                    yield i, line.strip()
            return
        for s in json_strings(data):
            if SHOWN.search(s) and name_hit(s, art_ok) and (rel, s) not in CLIENT_ALLOW:
                yield 0, s


def check_client(root):
    if not os.path.isfile(os.path.join(root, 'init.lua')):
        print(f'not an assembled client tree (no init.lua): {root}')
        return 1
    bad = 0
    for top in CLIENT_ROOTS:
        start = os.path.join(root, top)
        paths = [start] if os.path.isfile(start) else []
        for dp, dn, fn in os.walk(start):
            dn.sort()
            paths += [os.path.join(dp, f) for f in sorted(fn)]
        for p in paths:
            rel = os.path.relpath(p, root).replace(os.sep, '/')
            if rel in CLIENT_UNUSED or not rel.endswith(('.lua', '.otui', '.otml', '.otmod', '.json')):
                continue
            try:
                text = open(p, encoding='utf-8').read()
            except UnicodeDecodeError:
                text = open(p, encoding='latin-1').read()
            for line, s in client_file_hits(rel, text):
                print(f'{rel}:{line}: {s.strip()[:100]}'); bad += 1
    return bad


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--client':
        bad = check_client(sys.argv[2])
    elif len(sys.argv) == 1:
        bad = check_repo()
    else:
        sys.exit(__doc__)
    print('names check:', 'OK' if not bad else f'{bad} hit(s)')
    sys.exit(1 if bad else 0)
