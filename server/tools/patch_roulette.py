#!/usr/bin/env python3
"""The roulettes' prize pools come from data/scripts/chaos/boss_roulette_config.lua and roulette_{exercise,premium,
crystal}_config.lua (idempotent). install_all.py step `roulette`.

usage: python3 -I patch_roulette.py DATA_DIR [--dry-run] [--check]

server/README.md "Boss Roulette" (O148) and "Roulette prizes against token drops" (O151). Beta 2026-10-23: "I spun it twice. One reward was the golden deck, the other a boat.
The roulette also shows lots of card rewards." The base pool was nine Furious badges, four legendary cards and (before the
prizes step) two decks and a ship. This tool replaces the `prizePool = { ... }` of the base boss roulette script (found by
its "Boss Roulette requires" text) with the lines of the config: crafting orbs and sockets, gold (scaled to the winner's
level by prizes.lua), a unique chest, badges and catalysts and two cards. It also sets the broadcast threshold of the
script to the config's `rareThreshold`.

The config is read with patterns, one entry per line:
    {id = 29851, name = "Orb of Awakening", count = {1, 3}, chance = 5200, kind = "orb"},
The tool refuses a pool that holds an id of the config's `retired` list (decks, ships, belts, gloves: nothing can wear
them), and one of the fixed base gear 28373-28393 (O151). The written lines carry the mark; a second run changes
nothing, a changed config is written again.

O151: the other four roulettes get their pools the same way: the exercise roulette (actionId 18563), the premium roulette
(18564) and the two crystal token roulettes (18565, 18566; one pool for both). A script is matched to its config by the
`actionId` of its `config` table (`actionIds` in the config); the boss script also by its "Boss Roulette requires" text.
A script whose playItem is not the config's token is left alone. The two crystal scripts are copies of the premium and
the exercise ones and still said "Premium Roulette" / "Exercise Roulette" (messages, broadcast, the label ChaosPrizes
gets): they are named the Crystal Roulette. --check changes nothing and exits 1 when something is still to do. Line
endings (LF or CRLF) are kept.
"""
import os
import re
import sys

sys.dont_write_bytecode = True

MARK = 'Chaos: boss roulette pool (patch_roulette.py)'  # the boss one; the others say their title instead of "boss"
CONFIGS = ('boss_roulette_config.lua', 'roulette_exercise_config.lua', 'roulette_premium_config.lua',
           'roulette_crystal_config.lua')
CONFIG = os.path.join('scripts', 'chaos', CONFIGS[0])  # the one that has to be there
ACTION_ID = re.compile(r'^[ \t]*actionId[ \t]*=[ \t]*(\d+)', re.M)
PLAY_ITEM = re.compile(r'playItem[ \t]*=[ \t]*\{[^}]*?itemId[ \t]*=[ \t]*(\d+)', re.S)
# the crystal scripts are copies of the premium / exercise ones
WRONG_NAME = re.compile(r'\b(?:Premium|Exercise) Roulette\b')
WRONG_BROADCAST = re.compile(r'from the (?:premium|exercise) roulette!')
WRONG_LABEL = re.compile(r'(rouletteReward\([^\n]*, )"(?:premium|exercise)"\)')
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


def parse_meta(text):
    """-> (actionIds, title, token); empty / None when the config has none"""
    a = re.search(r'actionIds = \{([^}]*)\}', text)
    t = re.search(r'^[ \t]*title = "(\w+)"', text, re.M)
    k = re.search(r'^[ \t]*token = (\d+)', text, re.M)
    return ([int(x) for x in re.findall(r'\d+', a.group(1))] if a else [], t.group(1) if t else 'boss',
            int(k.group(1)) if k else None)


# the fixed base gear of the old crystal pool: no roulette gives it again (its ids are transmog set looks, so the range is
# here and not in a config)
FIXED_GEAR = range(28373, 28394)


def check_entries(entries, retired):
    """problems of a pool (empty list = fine)"""
    out = []
    if not entries:
        out.append('no pool lines in the config')
    for i, name, lo, hi, chance, kind in entries:
        if i in retired:
            out.append('%s (%d) is retired' % (name, i))
        if i in FIXED_GEAR:
            out.append('%s (%d) is fixed base gear that does not scale with the level' % (name, i))
        if lo < 1 or hi < lo:
            out.append('%s: bad count' % name)
        if not 0 < chance <= 10000:
            out.append('%s: chance %d out of 1..10000' % (name, chance))
    return out


def mark(title='boss'):
    return MARK.replace('boss roulette', '%s roulette' % title)


def block(indent, entries, title='boss'):
    inner = indent + ('\t' if indent.startswith('\t') else '    ')
    lines = ['%sprizePool = { -- %s' % (indent, mark(title))]
    for i, name, lo, hi, chance, kind in entries:
        lines.append('%s{itemId = %d, count = {%d, %d}, chance = %d}, -- %s' % (inner, i, lo, hi, chance, name))
    lines.append('%s},' % indent)
    return '\n'.join(lines) + '\n'


def is_roulette(text):
    return 'prizePool' in text and 'local function rewardPlayer(playerId, leverPosition)' in text


def rename(text):
    """the crystal scripts' copied names -> Crystal Roulette; (new text, number of changes)"""
    n = 0
    text, k = WRONG_NAME.subn('Crystal Roulette', text)
    n += k
    text, k = WRONG_BROADCAST.subn('from the crystal roulette!', text)
    n += k
    text, k = WRONG_LABEL.subn(r'\1"crystal")', text)
    return text, n + k


def patch(text, entries, threshold, title='boss'):
    """(new text, number of changes); -1 when the script cannot be read"""
    m = POOL.search(text)
    if not m:
        return text, -1
    n = 0
    new = block(m.group(1), entries, title)
    if text[m.start():m.end()] != new:
        text = text[:m.start()] + new + text[m.end():]
        n += 1
    if threshold is not None:
        t = THRESHOLD.search(text)
        if t and int(t.group(2)) != threshold:
            text = text[:t.start(2)] + str(threshold) + text[t.end(2):]
            n += 1
    if title == 'crystal':
        text, k = rename(text)
        n += k
    return text, n


def files(root):
    for d, _sub, fs in sorted(os.walk(root)):
        for f in sorted(fs):
            if f.endswith('.lua'):
                yield os.path.join(d, f)


def load_configs(data):
    """-> (list of {name, entries, threshold, retired, ids, title, token}, problems)"""
    out, problems = [], []
    for name in CONFIGS:
        path = os.path.join(data, 'scripts', 'chaos', name)
        if not os.path.isfile(path):
            if name == CONFIGS[0]:
                return [], ['no config']
            continue
        entries, threshold, retired = parse_config(read(path))
        ids, title, token = parse_meta(read(path))
        bad = check_entries(entries, retired)
        problems += ['%s: %s' % (name, p) for p in bad]
        out.append({'name': name, 'entries': entries, 'threshold': threshold, 'ids': ids, 'title': title,
                    'token': token})
    return out, problems


def pick(configs, text):
    """the config of a roulette script: by the actionId of its config table, else the boss one by its text"""
    a = ACTION_ID.search(text)
    if a:
        for c in configs:
            if int(a.group(1)) in c['ids']:
                return c
    if 'Boss Roulette requires' in text:
        return configs[0]
    return None


def run(data, dry=False):
    """-> (lines of the report, how many files change, problems)"""
    report, changed = [], 0
    if not os.path.isfile(os.path.join(data, CONFIG)):
        return ['%s not found: install the chaos scripts first' % CONFIG.replace(os.sep, '/')], 0, ['no config']
    configs, problems = load_configs(data)
    if problems:
        return ['config: ' + p for p in problems], 0, problems
    found = 0
    for path in files(os.path.join(data, 'scripts')):
        if os.sep + 'chaos' + os.sep in path:
            continue
        raw = read(path)
        text = raw.replace('\r\n', '\n')
        if not is_roulette(text):
            continue
        cfg = pick(configs, text)
        if not cfg:
            continue
        found += 1
        rel = os.path.relpath(path, data).replace(os.sep, '/')
        play = PLAY_ITEM.search(text)
        if cfg['token'] and play and int(play.group(1)) != cfg['token']:
            report.append('%s: its token is %s, the config says %d (left alone)' % (rel, play.group(1), cfg['token']))
            continue
        new, n = patch(text, cfg['entries'], cfg['threshold'], cfg['title'])
        if n < 0:
            report.append('%s: a %s roulette this tool cannot read (left alone)' % (rel, cfg['title']))
            continue
        if not n:
            continue
        if patch(new, cfg['entries'], cfg['threshold'], cfg['title'])[1]:
            raise SystemExit('%s: not idempotent' % path)
        if '\r\n' in raw:
            new = new.replace('\n', '\r\n')
        changed += 1
        report.append('%s: %s roulette, %d change(s)' % (rel, cfg['title'], n))
        if not dry:
            write(path, new)
    if not found:
        report.append('no roulette script found (skipped)')
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
