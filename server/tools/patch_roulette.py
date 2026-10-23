#!/usr/bin/env python3
"""The Boss Roulette's prize pool comes from data/scripts/chaos/boss_roulette_config.lua (idempotent).
install_all.py step `roulette`.

usage: python3 -I patch_roulette.py DATA_DIR [--dry-run] [--check]

server/README.md "Boss Roulette" (O148). Beta 2026-10-23: "I spun it twice. One reward was the golden deck, the other a boat.
The roulette also shows lots of card rewards." The base pool was nine Furious badges, four legendary cards and (before the
prizes step) two decks and a ship. This tool replaces the `prizePool = { ... }` of the base boss roulette script (found by
its "Boss Roulette requires" text) with the lines of the config: crafting orbs and sockets, gold (scaled to the winner's
level by prizes.lua), a unique chest, badges and catalysts and two cards. It also sets the broadcast threshold of the
script to the config's `rareThreshold`.

The config is read with patterns, one entry per line:
    {id = 29851, name = "Orb of Awakening", count = {1, 3}, chance = 5200, kind = "orb"},
The tool refuses a pool that holds an id of the config's `retired` list (decks, ships, belts, gloves: nothing can wear
them). The written lines carry the mark; a second run changes nothing, a changed config is written again. The other four
roulettes (exercise, premium, the two crystal token ones) are not touched. --check changes nothing and exits 1 when
something is still to do. Line endings (LF or CRLF) are kept.
"""
import os
import re
import sys

sys.dont_write_bytecode = True

MARK = 'Chaos: boss roulette pool (patch_roulette.py)'
CONFIG = os.path.join('scripts', 'chaos', 'boss_roulette_config.lua')
ENTRY = re.compile(r'^[ \t]*\{id = (\d+), name = "([^"]*)", count = \{(\d+), (\d+)\}, chance = (\d+), kind = "(\w+)"\},?'
                   r'[ \t]*$', re.M)
THRESHOLD = re.compile(r'(rareItemChance_broadcastThreshold[ \t]*=[ \t]*)(\d+)')
POOL = re.compile(r'^([ \t]*)prizePool = \{[^\n]*\n(.*?)^\1\},?[ \t]*\n', re.M | re.S)


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def parse_config(text):
    """-> (entries, rare threshold, retired ids); entries = [(id, name, lo, hi, chance, kind)]"""
    entries = [(int(m.group(1)), m.group(2), int(m.group(3)), int(m.group(4)), int(m.group(5)), m.group(6))
               for m in ENTRY.finditer(text)]
    t = re.search(r'rareThreshold = (\d+)', text)
    r = re.search(r'retired = \{([^}]*)\}', text)
    retired = [int(x) for x in re.findall(r'\d+', r.group(1))] if r else []
    return entries, int(t.group(1)) if t else None, retired


def check_entries(entries, retired):
    """problems of a pool (empty list = fine)"""
    out = []
    if not entries:
        out.append('no pool lines in the config')
    for i, name, lo, hi, chance, kind in entries:
        if i in retired:
            out.append('%s (%d) is retired' % (name, i))
        if lo < 1 or hi < lo:
            out.append('%s: bad count' % name)
        if not 0 < chance <= 10000:
            out.append('%s: chance %d out of 1..10000' % (name, chance))
    return out


def block(indent, entries):
    inner = indent + ('\t' if indent.startswith('\t') else '    ')
    lines = ['%sprizePool = { -- %s' % (indent, MARK)]
    for i, name, lo, hi, chance, kind in entries:
        lines.append('%s{itemId = %d, count = {%d, %d}, chance = %d}, -- %s' % (inner, i, lo, hi, chance, name))
    lines.append('%s},' % indent)
    return '\n'.join(lines) + '\n'


def is_boss_roulette(text):
    return 'prizePool' in text and 'local function rewardPlayer(playerId, leverPosition)' in text \
        and 'Boss Roulette requires' in text


def patch(text, entries, threshold):
    """(new text, number of changes); -1 when the script cannot be read"""
    m = POOL.search(text)
    if not m:
        return text, -1
    n = 0
    new = block(m.group(1), entries)
    if text[m.start():m.end()] != new:
        text = text[:m.start()] + new + text[m.end():]
        n += 1
    if threshold is not None:
        t = THRESHOLD.search(text)
        if t and int(t.group(2)) != threshold:
            text = text[:t.start(2)] + str(threshold) + text[t.end(2):]
            n += 1
    return text, n


def files(root):
    for d, _sub, fs in sorted(os.walk(root)):
        for f in sorted(fs):
            if f.endswith('.lua'):
                yield os.path.join(d, f)


def run(data, dry=False):
    """-> (lines of the report, how many files change, problems)"""
    report, changed = [], 0
    cfg_path = os.path.join(data, CONFIG)
    if not os.path.isfile(cfg_path):
        return ['%s not found: install the chaos scripts first' % CONFIG], 0, ['no config']
    entries, threshold, retired = parse_config(read(cfg_path))
    problems = check_entries(entries, retired)
    if problems:
        return ['config: ' + p for p in problems], 0, problems
    found = 0
    for path in files(os.path.join(data, 'scripts')):
        if os.sep + 'chaos' + os.sep in path:
            continue
        raw = read(path)
        text = raw.replace('\r\n', '\n')
        if not is_boss_roulette(text):
            continue
        found += 1
        new, n = patch(text, entries, threshold)
        rel = os.path.relpath(path, data).replace(os.sep, '/')
        if n < 0:
            report.append('%s: a boss roulette this tool cannot read (left alone)' % rel)
            continue
        if not n:
            continue
        if patch(new, entries, threshold)[1]:
            raise SystemExit('%s: not idempotent' % path)
        if '\r\n' in raw:
            new = new.replace('\n', '\r\n')
        changed += 1
        report.append('%s: %d change(s)' % (rel, n))
        if not dry:
            write(path, new)
    if not found:
        report.append('boss roulette not found (skipped)')
    return report, changed, []


def main(argv):
    dry = '--dry-run' in argv or '--check' in argv
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    report, changed, problems = run(args[0], dry)
    for line in report:
        print(line)
    if problems:
        return 1
    verb = 'would change' if dry else 'changed'
    print('roulette: %d file(s) %s' % (changed, verb) if changed else 'roulette: nothing to change')
    return 1 if ('--check' in argv and changed) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
