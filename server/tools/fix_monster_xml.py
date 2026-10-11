#!/usr/bin/env python3
"""Rewrite imported monster XML so the TFS 1.4.2 base loads every entry (idempotent).

usage: python3 -I fix_monster_xml.py [FILE_OR_DIR ...]   (default: data/monster/monsters/chaos, run from server/)

  * a loot list <item id="a;b;c" chance="C" .../> becomes one <item> per id with chance C/N (other attributes kept);
    the base reads only the first number of such an id and drops the entry ("Unknown loot item id", "Cant load loot")
  * monster spells the base does not know are replaced by built-in attacks of the same role (SPELL_FIX below);
    interval, chance, range, min and max are kept
  * flags the base does not know (and no src-patch adds) are removed
  * element attributes get the case the base expects (PhysicalPercent -> physicalPercent)
  * stray text inside <attacks>/<defenses> such as "</defense>>" is removed (the base fails to load a spell there)
  * unknown area effects in AREA_FIX are renamed
Prints one line per changed file. tools/ci/check_content.py rejects anything this script would change.
"""
import os, re, sys

# flags the base reads (monsters.cpp loadMonster); src-patches may add more, see known_flags()
BASE_FLAGS = {'summonable', 'attackable', 'hostile', 'ignorespawnblock', 'illusionable', 'challengeable',
              'convinceable', 'pushable', 'isboss', 'canpushitems', 'canpushcreatures', 'staticattack', 'lightlevel',
              'lightcolor', 'targetdistance', 'runonhealth', 'hidehealth', 'canwalkonenergy', 'canwalkonfire',
              'canwalkonpoison'}
ELEMENTS = ['physicalPercent', 'icePercent', 'poisonPercent', 'earthPercent', 'firePercent', 'energyPercent',
            'holyPercent', 'deathPercent', 'waterPercent', 'arcanePercent', 'drownPercent', 'lifedrainPercent',
            'manadrainPercent']
AREA_FIX = {'purplesd': 'purpleenergy'}

# monster spell names the base resolves without a spells.xml entry (monsters.cpp deserializeSpell)
BUILTIN_SPELLS = {'melee', 'physical', 'bleed', 'poison', 'earth', 'fire', 'energy', 'drown', 'ice', 'holy', 'death',
                  'water', 'arcane', 'lifedrain', 'manadrain', 'healing', 'speed', 'outfit', 'invisible', 'drunk',
                  'firefield', 'poisonfield', 'energyfield', 'firecondition', 'energycondition', 'earthcondition',
                  'poisoncondition', 'icecondition', 'freezecondition', 'deathcondition', 'cursecondition',
                  'holycondition', 'dazzlecondition', 'drowncondition', 'bleedcondition', 'physicalcondition',
                  'strength', 'effect'}
# monster-only instants in the base spells.xml (words "###N"); a monster spell may name any of them
BASE_MONSTER_SPELLS = {
    'ghastly dragon curse', 'djinn electrify', 'energy elemental electrify', 'massive energy elemental electrify',
    'massive fire elemental soulfire', 'hellfire fighter soulfire', 'hellspawn soulfire', 'spectre drown',
    'phantasm drown', 'undead dragon curse', 'draken abomination curse', 'lancer beetle curse',
    'lizard magistratus curse', 'death blob curse', 'choking fear drown', 'blightwalker curse', 'sea serpent drown',
    'young sea serpent drown', 'quara constrictor freeze', 'quara constrictor electrify', 'cliff strider electrify',
    'war golem electrify', 'souleater drown', 'mutated bat curse', 'vulcongra soulfire', 'lava golem soulfire',
    'magma crawler soulfire', 'war golem skill reducer', 'silencer skill reducer', 'warlock skill reducer',
    'cliff strider skill reducer', 'stampor skill reducer', 'diabolic imp skill reducer',
    'dark torturer skill reducer', 'forest fury skill reducer', 'demon outcast skill reducer', 'fury skill reducer',
    'barbarian brutetamer skill reducer', 'deepling spellsinger skill reducer', 'werewolf skill reducer',
    'ice golem skill reducer', 'feversleep skill reducer', 'shock head skill reducer 1', 'shock head skill reducer 2',
    'enslaved dwarf skill reducer 1', 'enslaved dwarf skill reducer 2', 'djinn cancel invisibility',
    'betrayed wraith skill reducer', 'pirate corsair skill reducer', 'monster soulfire', 'dipthrah skill reducer',
    'woodling paralyze', 'pixie skill reducer', 'physical explosion', 'glooth fairy skill reducer'}

def known_spells():
    """lower-case monster spell names the installed server knows: built-ins, base monster instants, the stock
    player spells under their Chaos names (spell_names.csv) and our own spells (spells_chaos.xml)."""
    import csv
    names = BUILTIN_SPELLS | BASE_MONSTER_SPELLS
    sp = os.path.join(HERE, '..', 'data', 'spells')
    p = os.path.join(sp, 'spell_names.csv')
    if os.path.exists(p):
        names |= {r['new_name'].lower() for r in csv.DictReader(open(p, newline='', encoding='utf-8'))}
    p = os.path.join(sp, 'chaos', 'spells_chaos.xml')
    if os.path.exists(p):
        names |= {n.lower() for n in re.findall(r'<(?:instant|rune)\b[^>]*\bname="([^"]+)"',
                                                 open(p, encoding='utf-8').read())}
    return names

# unknown spell name (lower case) -> (extra attributes, [(effect key, value)]); same damage numbers, nearest shape
SPELL_FIX = {
    "gaz'haragoth iceball": ('name="ice" range="7" target="1" radius="3"',
                             [('shootEffect', 'ice'), ('areaEffect', 'icearea')]),
    'ranged_stun_stone': ('name="speed" target="1" speedchange="-700" duration="3000"',
                          [('shootEffect', 'largerock'), ('areaEffect', 'stun')]),
    'ultra berserk': ('name="physical" radius="3" target="0"', [('areaEffect', 'blackspark')]),
    'advanced thunder shuriken': ('name="energy" range="7" target="1"',
                                  [('shootEffect', 'throwingstar'), ('areaEffect', 'energy')]),
    'arctic_plant': ('name="speed" target="1" speedchange="-400" duration="3000"',
                     [('shootEffect', 'smallice'), ('areaEffect', 'iceattack')]),
    'serpent_attack': ('name="speed" range="7" target="1" speedchange="-850" duration="12000"',
                       [('shootEffect', 'poison'), ('areaEffect', 'redshimmer')]),
}
KEEP_ATTRS = ('interval', 'speed', 'chance', 'range', 'min', 'max')

HERE = os.path.dirname(os.path.abspath(__file__))

def known_flags():
    flags = set(BASE_FLAGS)
    pdir = os.path.join(HERE, '..', 'src-patches')
    for f in sorted(os.listdir(pdir)) if os.path.isdir(pdir) else []:
        for ln in open(os.path.join(pdir, f), encoding='utf-8', errors='ignore'):
            m = re.match(r'\+.*strcasecmp\(attrName, "(\w+)"\)', ln)
            if m: flags.add(m.group(1).lower())
    return flags

LOOT_LIST = re.compile(r'^([ \t]*)<item\b([^>]*?)\bid="(\d+(?:\s*;\s*\d+)+)"([^>]*?)/>([ \t]*<!--.*?-->)?',
                       re.M)

def split_loot(m):
    indent, pre, ids, post, comment = m.group(1), m.group(2), m.group(3), m.group(4), m.group(5) or ''
    ids = [i.strip() for i in ids.split(';') if i.strip()]
    attrs = pre + post
    cm = re.search(r'\bchance="(\d+)"', attrs)
    total = int(cm.group(1)) if cm else 100000
    each = max(1, round(total / len(ids)))
    attrs = re.sub(r'\s*\bchance="\d+"', '', attrs).strip()
    attrs = re.sub(r'\s+', ' ', attrs)
    out = []
    for k, i in enumerate(ids):
        extra = (' ' + attrs) if attrs else ''
        out.append(f'{indent}<item id="{i}"{extra} chance="{each}"/>' + (comment if k == 0 else ''))
    return '\n'.join(out)

def fix_spell(m):
    indent, tag, attrs = m.group(1), m.group(2), m.group(3)
    nm = re.search(r'\bname="([^"]*)"', attrs)
    fix = SPELL_FIX.get(nm.group(1).lower()) if nm else None
    if not fix:
        return m.group(0)
    kept = [a.group(0) for a in re.finditer(r'\b(\w+)="[^"]*"', attrs) if a.group(1) in KEEP_ATTRS]
    head = f'{indent}<{tag} {fix[0]} ' + ' '.join(kept)
    body = ''.join(f'\n{indent}\t<attribute key="{k}" value="{v}"/>' for k, v in fix[1])
    return f'{head.rstrip()}>{body}\n{indent}</{tag}>'

def fix_text(t, flags):
    t = LOOT_LIST.sub(split_loot, t)
    t = re.sub(r'^([ \t]*)<(attack|defense)\b([^>]*?)\s*/>', fix_spell, t, flags=re.M)
    def flag_line(m):
        return m.group(0) if m.group(2).lower() in flags else ''
    t = re.sub(r'(\n[ \t]*<flag\s+(\w+)\s*=\s*"[^"]*"\s*/>[ \t]*)', lambda m: flag_line(m), t)
    canon = {e.lower(): e for e in ELEMENTS}
    t = re.sub(r'(<element\s+)(\w+)(\s*=)', lambda m: m.group(1) + canon.get(m.group(2).lower(), m.group(2)) + m.group(3), t)
    t = re.sub(r'(</(?:attack|defense)>)>+', r'\1', t)
    for old, new in AREA_FIX.items():
        t = re.sub(r'(key="areaEffect"\s+value=")%s"' % re.escape(old), r'\g<1>%s"' % new, t, flags=re.I)
    return t

def files(args):
    for a in args:
        if os.path.isdir(a):
            for root, _d, fs in os.walk(a):
                for f in sorted(fs):
                    if f.endswith('.xml'): yield os.path.join(root, f)
        else:
            yield a

def main():
    args = sys.argv[1:] or [os.path.join(HERE, '..', 'data', 'monster', 'monsters', 'chaos')]
    flags = known_flags()
    n = 0
    for f in files(args):
        t = open(f, encoding='utf-8').read()
        new = fix_text(t, flags)
        if new != t:
            open(f, 'w', encoding='utf-8', newline='').write(new)
            print('fixed', f); n += 1
    print(f'{n} file(s) changed')

if __name__ == '__main__':
    main()
