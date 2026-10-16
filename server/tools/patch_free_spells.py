#!/usr/bin/env python3
"""Every spell and rune is free: no premium account is needed to cast, use or learn one (owner decision 2026-10-16;
server/README.md "Free spells").

usage: python3 -I patch_free_spells.py DATA_DIR [--dry-run]

The playtest of 2026-10-16 found a free level 20 Mystic unable to cast 12 of the 28 Mystic spells: the engine refuses
a spell whose premium flag is set to an account without premium time (Spell::playerSpellCheck, "You need a premium
account."). The base server marks most higher spells premium. This clears the flag of spells and runes only; the other
premium perks (areas, outfits, store time, the autoloot limit, ...) stay, and freePremium stays off.

1. spells/spells.xml: premium="1" (or true / yes) of every <instant>, <rune> and <conjure> becomes premium="0".
   The Chaos block (register_spells.py) is left alone: its own file, data/spells/chaos/spells_chaos.xml, has no
   premium spell.
2. Revscript spells (scripts/**/*.lua, spells/**/*.lua): spell:isPremium(true) becomes spell:isPremium(false).
   Player:isPremium() takes no argument, so only spell definitions match.
3. npc/lib/npcsystem/modules.lua, StdModule.learnSpell: the premium test of an NPC spell teacher goes (a teacher
   could still refuse a spell with premium = true in its parameters). The other StdModule functions (promotion,
   blessing, travel) keep theirs. A base without that function or test is reported, not refused.

Idempotent: a second run changes nothing. install_all.py step `spells`, after patch_spell_timings.py.
"""
import os
import re
import sys

CHAOS_BEGIN = '<!-- BEGIN chaos spells'
CHAOS_END = '<!-- END chaos spells -->'
TAG = re.compile(r'<(?:instant|rune|conjure)\b[^>]*>', re.S)
PREMIUM = re.compile(r'(\bpremium\s*=\s*")(?:1|true|yes)(")', re.I)
REVSCRIPT = re.compile(r'(:isPremium\(\s*)(?:true|1)(\s*\))')
LEARN_MARK = '-- Chaos: spells need no premium (patch_free_spells.py)'
LEARN_FUNC = re.compile(r'function\s+StdModule\.learnSpell\s*\(')
LEARN_TEST = re.compile(r'if\s+player:isPremium\(\)\s+or\s+not\s+parameters\.premium\s+then')


def patch_xml(text):
    """(new text, number of spells made free); the Chaos block is kept as it is"""
    head, sep, rest = text.partition(CHAOS_BEGIN)
    block, sep2, tail = rest.partition(CHAOS_END) if sep else ('', '', '')
    count = 0

    def tag(m):
        nonlocal count
        new = PREMIUM.sub(lambda p: p.group(1) + '0' + p.group(2), m.group(0))
        if new != m.group(0):
            count += 1
        return new

    head = TAG.sub(tag, head)
    tail = TAG.sub(tag, tail)
    return head + sep + block + sep2 + tail, count


def patch_revscript(text):
    """(new text, number of spell:isPremium(true) changed)"""
    return REVSCRIPT.subn(lambda m: m.group(1) + 'false' + m.group(2), text)


def patch_modules(text):
    """(new text, status): 'patched', 'already' or why it was left alone"""
    if LEARN_MARK in text:
        return text, 'already'
    f = LEARN_FUNC.search(text)
    if not f:
        return text, 'no StdModule.learnSpell'
    nxt = re.search(r'^\s*function\s', text[f.end():], re.M)
    end = f.end() + nxt.start() if nxt else len(text)
    m = LEARN_TEST.search(text, f.end(), end)
    if not m:
        return text, 'no premium test in StdModule.learnSpell'
    return text[:m.start()] + 'if true then ' + LEARN_MARK + text[m.end():], 'patched'


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def lua_files(root):
    for d, _, files in os.walk(root):
        for name in sorted(files):
            if name.endswith('.lua'):
                yield os.path.join(d, name)


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    data = os.path.abspath(args[0])
    xml_path = os.path.join(data, 'spells', 'spells.xml')
    if not os.path.isfile(xml_path):
        print('missing file: %s' % xml_path)
        return 1
    writes = []
    text, spells = patch_xml(read(xml_path))
    if spells:
        writes.append((xml_path, text))
    print('spells.xml: %d spell(s) and rune(s) made free' % spells)

    scripts = 0
    for sub in ('scripts', os.path.join('spells', 'scripts')):
        root = os.path.join(data, sub)
        if not os.path.isdir(root):
            continue
        for path in lua_files(root):
            old = read(path)
            if ':isPremium(' not in old:
                continue
            new, n = patch_revscript(old)
            if n:
                scripts += n
                writes.append((path, new))
                print('  %s: %d revscript spell(s) made free' % (os.path.relpath(path, data), n))
    print('revscripts: %d spell(s) made free' % scripts)

    mod_path = os.path.join(data, 'npc', 'lib', 'npcsystem', 'modules.lua')
    if os.path.isfile(mod_path):
        new, status = patch_modules(read(mod_path))
        if status == 'patched':
            writes.append((mod_path, new))
        print('npc/lib/npcsystem/modules.lua: %s' % status)
    else:
        print('npc/lib/npcsystem/modules.lua: missing, skipped')

    if dry:
        print('dry run: %d file(s) would change' % len(writes))
        return 0
    for path, text in writes:
        write(path, text)
    print('%d file(s) changed' % len(writes))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
