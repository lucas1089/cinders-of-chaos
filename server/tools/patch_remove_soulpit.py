#!/usr/bin/env python3
"""Remove the base server's soul pit and its items from the game (O488, server/README.md "Soul pit removed").

usage: python3 -I patch_remove_soulpit.py DATA_DIR [--dry-run]

Owner, 2026-11-11: "You can remove this mechanic from the game, together with the items." The mechanic: a soul core used
on the pit starts 5 waves of that monster, a win gives +3% experience from that monster for ever, an exalted core turns
one soul core into a random other. This tool changes the installed base data (idempotent, each change once):
  1. scripts/customs/soulpit_system/{soulpit,transform_soulcores,teleport}.lua: each becomes a one-line stub that
     registers nothing (the files stay, so a base update that writes them back is stubbed again by the next run). The
     pit's boss room wiring (patch_base_eventrooms.py wrote it before O488) goes with the old text; the pit's entrance
     step-in tile (action id 5896) then does nothing.
  2. events/scripts/player.lua: the table monsterExpBoosts and its use in Player:onGainExperience are cut out (the
     experience of a monster is no longer x1.03 for a player who finished its pit). The storages 876547.. stay in the
     database, inert.
  3. monster/**: the soul core and exalted core loot entries are cut out of every monster file (Lua `{id = N, chance = C}`
     lines, XML `<item id="N" .../>` lines). The wave monsters ("angry ...", "wrathful ...") are not touched.
  4. npc/scripts/Iletrya.lua: the waystone device step asked for 10 exalted cores (item 28345) and gave the Waystone
     Portal Kit with the quest storage; it now gives the kit and the storage on the first "help", no cores.
  5. scripts/customs/crafting/generalcrafting.lua: the recipe that made an exalted core (40 dust, 15 sliver, 1500 gold)
     is removed.
  6. scripts/eventcallbacks/monster/default_onDropLoot.lua: the 3% drop of dust and sliver (the two materials of that
     recipe, nothing else uses them) is removed.
  7. items/items.xml: the description of each soul core, of the exalted core, of dust and of sliver becomes "No longer
     used." The definitions stay in items.xml and items.otb (the ids stay known to server and client).
The ids: IDS below is the list read from the installed scripts (the pit's table of 36 soul cores, the exalted core). The
tool also reads the stock scripts when they are still there and adds any id they name that IDS lacks (reported). The SQL
file server/sql/chaos_zz_soulpit_removal.sql (the items players own) deletes SQL_IDS: IDS and the two dead materials, dust
and sliver (owner, 2026-11-11: "You can delete dust and sliver too"); the test holds the two together.

A file is changed only when each pattern is there as the stock text has it; otherwise it is listed ("unrecognised") and
left alone. Line endings (LF or CRLF) are kept. Never edit the base data by hand: this is the way.
"""
import os
import re
import sys

MARK = 'Chaos (patch_remove_soulpit.py, O488)'
NOTE = 'No longer used.'

# the 36 soul cores of the pit's table (28326-28342, 28346-28364) and the exalted core
SOUL_CORES = tuple(range(28326, 28343)) + tuple(range(28346, 28365))
EXALTED = 28345
IDS = tuple(sorted(SOUL_CORES + (EXALTED,)))
# the materials of the exalted core recipe: no drop, no use any more
DUST, SLIVER = 28343, 28344
DEAD_MATERIALS = (DUST, SLIVER)
# what server/sql/chaos_zz_soulpit_removal.sql deletes from the players: the cores and the two materials
SQL_IDS = tuple(sorted(IDS + DEAD_MATERIALS))

PIT_DIR = ('scripts', 'customs', 'soulpit_system')
PIT_SCRIPTS = ('soulpit.lua', 'transform_soulcores.lua', 'teleport.lua')
PLAYER = ('events', 'scripts', 'player.lua')
NPC = ('npc', 'scripts', 'Iletrya.lua')
CRAFTING = ('scripts', 'customs', 'crafting', 'generalcrafting.lua')
DROP = ('scripts', 'eventcallbacks', 'monster', 'default_onDropLoot.lua')
ITEMS = ('items', 'items.xml')
MONSTER_DIR = ('monster',)

STUB_TEXT = '-- %s: the soul pit is removed from the game. This script registers nothing.' % MARK


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def nl_of(text):
    return '\r\n' if '\r\n' in text else '\n'


def alt(ids):
    return '|'.join(str(i) for i in sorted(ids))


# ------------------------------------------------------------------------------------------------ 1. the pit scripts
def stub_script(text):
    """-> (new text, status)"""
    if MARK in text and len(text.strip().splitlines()) == 1:
        return text, 'already done'
    return STUB_TEXT + nl_of(text), 'stubbed'


def discover(texts):
    """ids the stock pit scripts name: the waves table keys, the transform list, the exalted core"""
    found = set()
    pit = texts.get('soulpit.lua', '')
    m = re.search(r'^local event = \{\s*\r?\n\s*waves = \{(.*?)^    \},?\s*\r?\n', pit, re.S | re.M)
    for key in re.findall(r'^[ \t]+\[(\d+)\][ \t]*=[ \t]*\{[ \t]*\r?$', m.group(1) if m else pit, re.M):
        found.add(int(key))
    tr = texts.get('transform_soulcores.lua', '')
    m = re.search(r'local itemsRandom = \{(.*?)\}', tr, re.S)
    if m:
        found.update(int(x) for x in re.findall(r'\d+', m.group(1)))
    m = re.search(r'exaltedCore:id\((\d+)\)', tr)
    if m:
        found.add(int(m.group(1)))
    return found


# ------------------------------------------------------------------------------------------------ 2. player.lua
TABLE_RX = re.compile(r'^local monsterExpBoosts = \{.*?^\}[ \t]*\r?\n', re.S | re.M)
USE_RX = re.compile(
    r'(?P<src>[ \t]*local sourceName = source:getName\(\):lower\(\)[ \t]*\r?\n)?'
    r'[ \t]*local storageValue = monsterExpBoosts\[sourceName\][ \t]*\r?\n'
    r'[ \t]*if storageValue then[ \t]*\r?\n'
    r'[ \t]*if self:getStorageValue\(storageValue\) >= 1 then[ \t]*\r?\n'
    r'[ \t]*exp = exp \* 1\.03[^\r\n]*\r?\n'
    r'[ \t]*end[ \t]*\r?\n'
    r'[ \t]*end[ \t]*\r?\n')


def patch_player(text):
    if 'monsterExpBoosts' not in text:
        return text, 'already done'
    if len(TABLE_RX.findall(text)) != 1 or len(USE_RX.findall(text)) != 1:
        return text, 'unrecognised (monsterExpBoosts table x%d, use x%d, want 1 and 1)' % (
            len(TABLE_RX.findall(text)), len(USE_RX.findall(text)))
    nl = nl_of(text)
    m = USE_RX.search(text)
    # the `sourceName` line goes with it only when nothing else of the function reads it
    keep_src = m.group('src') is not None and text.count('sourceName') > 2
    use = m.group('src') if keep_src else ''
    text = text[:m.start()] + use + text[m.end():]
    text = TABLE_RX.sub(lambda _m: '-- %s: the soul pit\'s +3%% experience per monster is removed.%s' % (MARK, nl), text, count=1)
    if 'monsterExpBoosts' in text:
        return text, 'unrecognised (monsterExpBoosts is read somewhere else)'
    return text, 'patched'


# ------------------------------------------------------------------------------------------------ 3. monster loot
def loot_rx(ids):
    a = alt(ids)
    lua = (r'^[ \t]*\{[ \t]*id[ \t]*=[ \t]*(?:(?:%s)|"[^"\r\n]*(?:soul core|exalted core)")[ \t]*,'
           r'[^{}\r\n]*\}[ \t]*,?[ \t]*(?:--[^\r\n]*)?\r?\n' % a)
    xml = (r'^[ \t]*<item[ \t]+(?:id="(?:%s)"|name="[^"\r\n]*(?:soul core|exalted core)")[^>\r\n]*/>[ \t]*\r?\n' % a)
    return re.compile(lua, re.M), re.compile(xml, re.M)


def clean_loot(text, ids, path):
    lua, xml = loot_rx(ids)
    rx = xml if path.endswith('.xml') else lua
    return rx.subn('', text)


# ------------------------------------------------------------------------------------------------ 4. Iletrya
GREETING_OLD = 'To repair it you need to {help} me with a small task. Are you interested?'
GREETING_NEW = 'To repair it you only need to {help} me. Are you interested?'


def patch_npc(text):
    if str(EXALTED) not in text and GREETING_OLD not in text:
        return text, 'already done'
    nl = nl_of(text)
    lines = text.splitlines(True)
    new = text
    if str(EXALTED) in text:
        start = None
        for i, line in enumerate(lines):
            if re.match(r'^[ \t]*if player:removeItem\(%d, \d+\) then[ \t]*\r?$' % EXALTED, line):
                if start is not None:
                    return text, 'unrecognised (the exalted core check twice)'
                start = i
        if start is None:
            return text, 'unrecognised (no `if player:removeItem(%d, N) then` line)' % EXALTED
        ind = re.match(r'[ \t]*', lines[start]).group(0)
        other = ind + 'else'
        close = ind + 'end'
        els = next((i for i in range(start + 1, len(lines)) if lines[i].rstrip('\r\n') == other), None)
        end = next((i for i in range(els + 1, len(lines)) if lines[i].rstrip('\r\n') == close), None) if els else None
        if els is None or end is None:
            return text, 'unrecognised (no else / end of the exalted core check)'
        body = [(l[4:] if l.startswith(ind + '    ') else l) for l in lines[start + 1:els]]
        comment = '%s-- %s: no exalted cores are asked for any more.%s' % (ind, MARK, nl)
        lines[start:end + 1] = [comment] + body
        new = ''.join(lines)
        if str(EXALTED) in new:
            return text, 'unrecognised (the exalted core id is read somewhere else)'
    new = new.replace(GREETING_OLD, GREETING_NEW)
    return new, 'patched'


# ------------------------------------------------------------------------------------------------ 5. recipe
RECIPE_RX = re.compile(r'^([ \t]*)\{[ \t]*\r?\n[ \t]*id = %d,[ \t]*\r?\n.*?^\1\},?[ \t]*\r?\n' % EXALTED, re.S | re.M)


def patch_crafting(text):
    n = len(RECIPE_RX.findall(text))
    if n == 0 and str(EXALTED) not in text:
        return text, 'already done'
    if n != 1:
        return text, 'unrecognised (exalted core recipe x%d, want 1)' % n
    new = RECIPE_RX.sub('', text, count=1)
    if re.search(r'\bid = %d\b' % EXALTED, new):
        return text, 'unrecognised (the exalted core is a material somewhere else)'
    return new, 'patched'


# ------------------------------------------------------------------------------------------------ 6. dust and sliver drop
DROP_RX = re.compile(
    r'^([ \t]*)if math\.random\(1, 100\) <= \d+ then[ \t]*\r?\n[ \t]*local quantity%d = .*?^\1end[ \t]*\r?\n(?:[ \t]*\r?\n)?' % DUST,
    re.S | re.M)


def patch_drop(text):
    n = len(DROP_RX.findall(text))
    if n == 0 and str(DUST) not in text:
        return text, 'already done'
    if n != 1:
        return text, 'unrecognised (dust and sliver drop x%d, want 1)' % n
    new = DROP_RX.sub('', text, count=1)
    if str(DUST) in new or str(SLIVER) in new:
        return text, 'unrecognised (dust or sliver is read somewhere else)'
    return new, 'patched'


# ------------------------------------------------------------------------------------------------ 7. items.xml
def describe_items(text, ids):
    """-> (new text, changed count, missing ids)"""
    seen = set()
    changed = [0]
    rx = re.compile(r'(<item id="(%s)"[^>\r\n]*[^/>\r\n]>)(.*?)(</item>)' % alt(ids), re.S)
    desc = re.compile(r'(<attribute key="description" value=")[^"]*("[ \t]*/>)')
    nl = nl_of(text)

    def one(m):
        seen.add(int(m.group(2)))
        inner = m.group(3)
        if desc.search(inner):
            new_inner = desc.sub(lambda d: d.group(1) + NOTE + d.group(2), inner, count=1)
        else:
            new_inner = nl + '\t\t<attribute key="description" value="%s"/>' % NOTE + inner
        if new_inner != inner:
            changed[0] += 1
        return m.group(1) + new_inner + m.group(4)

    new = rx.sub(one, text)
    return new, changed[0], sorted(set(ids) - seen)


# ------------------------------------------------------------------------------------------------ the run
def walk_files(root, exts):
    for base, dirs, files in os.walk(root):
        dirs.sort()
        for name in sorted(files):
            if name.endswith(exts):
                yield os.path.join(base, name)


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1 or not os.path.isdir(args[0]):
        print(__doc__.strip().splitlines()[2])
        return 2
    data = args[0]
    out = []
    suffix = ' (dry run, not written)' if dry else ''

    def rel(p):
        return 'data/' + os.path.relpath(p, data).replace(os.sep, '/')

    def file_step(parts, fn, label=None):
        path = os.path.join(data, *parts)
        if not os.path.isfile(path):
            out.append('%s: not found (nothing to do)' % rel(path))
            return
        text = read(path)
        new, st = fn(text)
        if st in ('patched', 'stubbed') and not dry:
            write(path, new)
        out.append('%s: %s%s' % (rel(path), st, suffix if st in ('patched', 'stubbed') else ''))

    ids = set(IDS)
    # the pit scripts: read what they name before they are stubbed
    pit_texts = {}
    for name in PIT_SCRIPTS:
        p = os.path.join(data, *PIT_DIR, name)
        if os.path.isfile(p):
            pit_texts[name] = read(p)
    extra = sorted(discover(pit_texts) - ids)
    if extra:
        out.append('the stock scripts name %d id(s) that IDS lacks: %s (cleaned too; add them to IDS and to '
                   'server/sql/chaos_zz_soulpit_removal.sql)' % (len(extra), ', '.join(str(i) for i in extra)))
        ids.update(extra)
    for name in PIT_SCRIPTS:
        file_step(PIT_DIR + (name,), stub_script)

    file_step(PLAYER, patch_player)

    # monster loot
    total = files_n = 0
    mdir = os.path.join(data, *MONSTER_DIR)
    if os.path.isdir(mdir):
        for path in walk_files(mdir, ('.lua', '.xml')):
            text = read(path)
            new, n = clean_loot(text, ids, path)
            if n:
                total += n
                files_n += 1
                if not dry:
                    write(path, new)
    out.append('data/monster: %s' % ('%d loot line(s) removed in %d file(s)%s' % (total, files_n, suffix) if total
                                     else 'already done (no soul core or exalted core in any loot list)'))

    file_step(NPC, patch_npc)
    file_step(CRAFTING, patch_crafting)
    file_step(DROP, patch_drop)

    path = os.path.join(data, *ITEMS)
    if os.path.isfile(path):
        text = read(path)
        new, n, missing = describe_items(text, sorted(ids | set(DEAD_MATERIALS)))
        if n and not dry:
            write(path, new)
        out.append('%s: %s%s' % (rel(path), ('%d description(s) set to "%s"' % (n, NOTE)) if n else 'already done',
                                 suffix if n else ''))
        if missing:
            out.append('data/items/items.xml: no definition for id(s) %s (nothing to describe)' % ', '.join(str(i) for i in missing))
    else:
        out.append('data/items/items.xml: not found (nothing to do)')

    # what still names an id in the scripts (a warning for the owner of the step, never a failure)
    left = []
    rx = re.compile(r'(?<![\w.])(?:%s)(?![\w.])' % alt(ids))
    for sub in ('scripts', 'npc', 'lib', 'events', 'monster'):
        d = os.path.join(data, sub)
        if not os.path.isdir(d):
            continue
        for p in walk_files(d, ('.lua',)):
            if os.path.basename(p) in PIT_SCRIPTS and os.sep + 'soulpit_system' + os.sep in p:
                continue
            if dry:
                continue
            for line in read(p).splitlines():
                if rx.search(line) and 'chance' not in line:
                    left.append(rel(p))
                    break
    if left:
        out.append('WARNING: an item id of the removed items is still named in: %s' % ', '.join(sorted(set(left))[:8]))
    print('\n'.join(out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
