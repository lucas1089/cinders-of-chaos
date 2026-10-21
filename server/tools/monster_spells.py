#!/usr/bin/env python3
"""Monster attacks and defenses that use a player spell by name, and the monster-only form of a retired spell.

usage: python3 -I monster_spells.py DATA_DIR            check: every monster spell name of DATA_DIR exists (exit 1 if not)
       python3 -I monster_spells.py DATA_DIR --refs     lists the spell names the monsters use (built-ins left out)

A monster <attack name="..."> / <defense name="..."> (XML) or {name = "..."} entry of monster.attacks / monster.defenses
(Lua) without a script is looked up by the engine first as a rune or instant spell name (Monsters::deserializeSpell,
g_spells->getSpellByName, case-insensitive), then as a built-in attack type (melee, fire, speed, firecondition, ...).
A name that is neither prints "[Error - Monsters::deserializeSpell] - <monster> - Unknown spell name: <name>" at
startup and the monster loads without that attack. Owner report 2026-10-21: the 15-spell cap (patch_spell_cap.py)
retired Arc Bolt (stock Energy Strike) and Dread (stock Fear) by commenting them out; World Devourer, Nightdweller and
other monsters lost those attacks.

The retire tools (retire_cure_spells.py, patch_spell_cap.py) use this module: a spell a monster names is not commented
out, it gets the monster-only form instead (monster_only() below), the same form as the base server's monster spells
("###1" words, needlearn="1", no vocation):
  * words="###chaos <script name>": the stock and Chaos incantations no longer find it (a player saying them gets the
    plain text), and the Spellbook (spellbook.lua Book.isPlayerSpell) skips "#" words, so no client list shows it;
  * needlearn="1": the engine casts it for a player only when player_spells has its name (Spell::playerSpellCheck
    tests the learned list, not the vocations). rename_spells.py --sql deletes those rows ("###chaos" words);
  * no <vocation> children (player:canLearnSpell refuses it, so no NPC teaches it) and no spellid (the id stays free
    for the Chaos block). An empty vocation list alone would let every class cast it (vocSpellMap empty = any
    vocation): needlearn="1" is what closes it. The client keeps it retired (ChaosCappedSpells, ChaosRetiredSpells);
  * a player saying the "###chaos" words is refused like any needlearn spell not learned;
  * an XML comment with MONSTER_ONLY_MARK just before the tag says why.
A spell that an earlier run commented out (the retire markers) comes back in that form when a monster names it, so a
server installed before this fix is repaired by the same install step (install_all.py --only spells,sql).
"""
import glob
import os
import re
import sys

# Monsters::deserializeSpell (XML) built-in names; the Lua loader also knows "combat" and "condition"
XML_BUILTIN = frozenset((
    'melee', 'physical', 'bleed', 'poison', 'earth', 'fire', 'energy', 'drown', 'ice', 'holy', 'death', 'water',
    'arcane', 'lifedrain', 'manadrain', 'healing', 'speed', 'outfit', 'invisible', 'drunk', 'firefield',
    'poisonfield', 'energyfield', 'firecondition', 'energycondition', 'earthcondition', 'poisoncondition',
    'icecondition', 'freezecondition', 'deathcondition', 'cursecondition', 'holycondition', 'dazzlecondition',
    'drowncondition', 'bleedcondition', 'physicalcondition', 'strength', 'effect'))
LUA_BUILTIN = XML_BUILTIN | {'combat', 'condition'}

MONSTER_ONLY_MARK = 'Chaos: monster-only spell (monster_spells.py): '
RETIRE_MARK = re.compile(r'<!--\s*Chaos: (?:spell cap \(patch_spell_cap\.py\)|cure retired \(retire_cure_spells\.py\)'
                         r'|spell retired \(retire_cure_spells\.py\)): (<instant\b.*?)\s*-->', re.S)
TAG = re.compile(r'<instant\b[^>]*?(?:/>|>.*?</instant>)', re.S)
VOC = re.compile(r'[ \t]*<vocation\b[^>]*/>[ \t]*(?:\r?\n)?')
HERE = os.path.dirname(os.path.abspath(__file__))
NAMES_CSV = os.path.join(HERE, '..', 'data', 'spells', 'spell_names.csv')


def read(path):
    return open(path, encoding='utf-8', errors='surrogateescape', newline='').read()


def attr(tag, name):
    m = re.search(r'\b%s\s*=\s*"([^"]*)"' % name, tag)
    return m.group(1) if m else None


def _xml_refs(text):
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    for m in re.finditer(r'<(attack|defense)\b([^>]*)>', text):
        a = m.group(2)
        if attr(a, 'script'):
            continue
        name = attr(a, 'name')
        if name:
            yield name


def _lua_entries(block):
    """the depth-1 tables of a Lua table constructor text (without its outer braces)"""
    depth, start = 0, None
    for i, ch in enumerate(block):
        if ch == '{':
            depth += 1
            if depth == 1:
                start = i
        elif ch == '}':
            if depth == 1 and start is not None:
                yield block[start + 1:i]
                start = None
            depth = max(0, depth - 1)


def _lua_refs(text):
    text = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)
    text = re.sub(r'--[^\n]*', '', text)
    for m in re.finditer(r'\.(attacks|defenses)\s*=\s*\{', text):
        depth, i = 1, m.end()
        while i < len(text) and depth:
            depth += {'{': 1, '}': -1}.get(text[i], 0)
            i += 1
        for entry in _lua_entries(text[m.end():i - 1]):
            flat = entry
            while True:
                new = re.sub(r'\{[^{}]*\}', '', flat)
                if new == flat:
                    break
                flat = new
            if re.search(r'\bscript\s*=', flat):
                continue
            n = re.search(r'\bname\s*=\s*(?:"([^"]+)"|\'([^\']+)\')', flat)
            if n:
                yield n.group(1) or n.group(2)


def monster_files(data):
    """(XML files registered in monster/monsters.xml, Lua files the engine loads from data/monster)"""
    mon = os.path.join(data, 'monster')
    xmls = []
    reg = os.path.join(mon, 'monsters.xml')
    if os.path.isfile(reg):
        text = re.sub(r'<!--.*?-->', '', read(reg), flags=re.S)
        for m in re.finditer(r'<monster\b[^>]*\bfile="([^"]+)"', text):
            p = os.path.join(mon, m.group(1).replace('\\', '/'))
            if os.path.isfile(p) and p not in xmls:
                xmls.append(p)
    luas = []
    for p in sorted(glob.glob(os.path.join(mon, '**', '*.lua'), recursive=True)):
        parent = os.path.basename(os.path.dirname(p))
        if '#' in os.path.basename(p) or parent in ('lib', 'events'):
            continue
        luas.append(p)
    return xmls, luas


def references(data, all_xml=False, extra_dirs=()):
    """{lowercased spell name: [files]} of the monster attacks and defenses that are not built-in attack types.
    all_xml: every monster/**/*.xml, registered or not (the retire tools: a monster registered later still counts);
    extra_dirs: more folders of monster XML and Lua (the repo's Chaos monsters, also before the files step copies them)."""
    xmls, luas = monster_files(data)
    if all_xml:
        xmls = sorted(set(xmls) | set(glob.glob(os.path.join(data, 'monster', '**', '*.xml'), recursive=True)))
    for d in extra_dirs:
        xmls += sorted(glob.glob(os.path.join(d, '**', '*.xml'), recursive=True))
        luas += [p for p in sorted(glob.glob(os.path.join(d, '**', '*.lua'), recursive=True))
                 if '#' not in os.path.basename(p)]
    refs = {}
    for p in xmls:
        if os.path.basename(p) == 'monsters.xml':
            continue
        for name in _xml_refs(read(p)):
            if name.lower() not in XML_BUILTIN:
                refs.setdefault(name.lower(), []).append(p)
    for p in luas:
        for name in _lua_refs(read(p)):
            if name.lower() not in LUA_BUILTIN:
                refs.setdefault(name.lower(), []).append(p)
    return refs


def aliases():
    """lowercased stock name <-> Chaos name (spell_names.csv): rename_spells.py renames spells and monsters together,
    so before it runs a monster may name the stock spell and after it the Chaos one"""
    import csv
    out = {}
    if os.path.isfile(NAMES_CSV):
        for r in csv.DictReader(open(NAMES_CSV, encoding='utf-8')):
            a, b = r['old_name'].lower(), r['new_name'].lower()
            out.setdefault(a, set()).add(b)
            out.setdefault(b, set()).add(a)
    return out


def wanted(refs):
    """the set of lowercased instant names that some monster needs (with their stock / Chaos aliases)"""
    al = aliases()
    names = set(refs)
    for n in list(names):
        names |= al.get(n, set())
    return names


def monster_only(tag):
    """the monster-only form of an <instant> tag (idempotent)"""
    head_end = tag.find('>')
    head, body = tag[:head_end + 1], tag[head_end + 1:]
    script = attr(head, 'script') or attr(head, 'name') or 'spell'
    words = '###chaos ' + re.sub(r'[^a-z0-9_]+', '_', os.path.splitext(os.path.basename(script))[0].lower())
    if re.search(r'\bwords="', head):
        head = re.sub(r'\bwords="[^"]*"', 'words="%s"' % words, head, count=1)
    else:
        head = head.replace('<instant', '<instant words="%s"' % words, 1)
    if re.search(r'\bneedlearn="', head):
        head = re.sub(r'\bneedlearn="[^"]*"', 'needlearn="1"', head, count=1)
    else:
        head = re.sub(r'\s*(/?>)$', lambda e: ' needlearn="1"' + (' />' if e.group(1) == '/>' else '>'), head, count=1)
    head = re.sub(r'\s+spellid="[^"]*"', '', head, count=1)
    body = VOC.sub('', body)
    if head.endswith('/>'):
        return head
    if re.fullmatch(r'\s*</instant>', body):
        # nothing left inside: a self-closing tag
        return re.sub(r'\s*>$', ' />', head)
    return head + body


def is_monster_only(tag):
    return (attr(tag, 'words') or '').startswith('###chaos ')


def needs(tag, needed):
    """does a monster name this <instant>?"""
    return (attr(tag, 'name') or '').lower() in needed


def keep_for_monsters(tag, indent='\t'):
    """text that replaces a retired <instant> a monster needs: the marker comment and the monster-only tag"""
    return '<!-- %s%s -->\n%s%s' % (MONSTER_ONLY_MARK, attr(tag, 'name'), indent, monster_only(tag))


def indent_before(text, pos):
    line = text.rfind('\n', 0, pos) + 1
    m = re.match(r'[ \t]*', text[line:pos])
    return m.group(0) if m.end() == pos - line else '\t'


def retire(text, m, mark, needed):
    """replacement of the <instant> match m that a retire tool takes out: the monster-only form when a monster names
    it, else the marked comment (the original tag kept in it)"""
    tag = m.group(0)
    if needs(tag, needed):
        return keep_for_monsters(tag, indent_before(text, m.start()))
    return '<!-- ' + mark + tag.replace('--', '- -') + ' -->'


def restore(text, needed):
    """(new text, number of retired comments a monster needs that came back in the monster-only form); also drops
    the marker comment of a monster-only tag that is gone"""
    count = 0

    def back(m):
        nonlocal count
        tag = m.group(1).replace('- -', '--')
        if not needs(tag, needed):
            return m.group(0)
        count += 1
        return keep_for_monsters(tag, indent_before(m.string, m.start()))
    return tidy(RETIRE_MARK.sub(back, text)), count


ORPHAN = re.compile(r'[ \t]*<!-- %s[^>]*? -->\r?\n(?=([ \t]*))\1(?!<instant\b[^>]*\bwords="###chaos )'
                    % re.escape(MONSTER_ONLY_MARK))


def tidy(text):
    """drops the marker comment of a monster-only tag that is no longer there (a retire tool commented it out)"""
    return ORPHAN.sub(lambda m: m.group(1), text)


REPO_MONSTERS = (os.path.join(HERE, '..', 'data', 'monster', 'monsters', 'chaos'),
                 os.path.join(HERE, '..', 'data', 'monster', 'lua', 'chaos'))


def needed_names(data, extra_dirs=None):
    """the instant names (lower case, stock and Chaos names) that the monsters of DATA_DIR and the repo's Chaos
    monsters use: what a retire tool must keep in the monster-only form"""
    dirs = REPO_MONSTERS if extra_dirs is None else extra_dirs
    return wanted(references(data, all_xml=True, extra_dirs=[d for d in dirs if os.path.isdir(d)]))


def spell_names(data):
    """lowercased names of every rune and instant (also conjure) the engine registers: data/spells/spells.xml outside
    comments and the revscript spells of data/scripts (Spell(...) with :name("..."))"""
    names = set()
    path = os.path.join(data, 'spells', 'spells.xml')
    if os.path.isfile(path):
        text = re.sub(r'<!--.*?-->', '', read(path), flags=re.S)
        for m in re.finditer(r'<(instant|rune|conjure)\b([^>]*)>', text):
            n = attr(m.group(2), 'name')
            if n:
                names.add(n.lower())
    for p in glob.glob(os.path.join(data, 'scripts', '**', '*.lua'), recursive=True):
        if '#' in os.path.basename(p):
            continue
        t = read(p)
        if 'Spell(' not in t:
            continue
        for m in re.finditer(r':name\(\s*["\']([^"\']+)["\']\s*\)', t):
            names.add(m.group(1).lower())
    return names


def unknown(data):
    """[(spell name, [files])] of monster spell names the engine will not find"""
    have = spell_names(data)
    return sorted((n, f) for n, f in references(data).items() if n not in have)


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1 or not os.path.isdir(args[0]):
        print(__doc__)
        return 1
    data = args[0]
    if '--refs' in argv:
        for n, files in sorted(references(data).items()):
            print('%-32s %d file(s)' % (n, len(files)))
        return 0
    bad = unknown(data)
    for n, files in bad:
        print('unknown monster spell name "%s": %s' % (n, ', '.join(sorted(os.path.relpath(f, data) for f in set(files)))))
    print('monster spell names: %d unknown' % len(bad))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
