#!/usr/bin/env python3
"""Look swaps (O619): 24 monsters leave a look that fails the stock bar for a better one that is already in the pair. install_all.py step
`monsterswaplooks`.

usage: python3 -I install_monster_swap_looks.py DATA_DIR [--dry-run] [--map CSV]

Owner 2026-11-17 (O619): "the monsters can be swapped too, I know we have many; keep everything at the same quality band". The O610 audit
measured every outfit of pair 71 against the stock bar (oblique camera lean, an east that is not a mirrored west, outline, soft alpha,
walk of 8 pictures; docs/SPRITE_STYLE.md). The donor B first set (outfits 1530-1550) failed it worst: one direction only, an upright camera
with the east a mirrored west, no outline. server/data/monster/monster_o619_looks.csv names, for each monster that leaves one of them
(and the two of the third donor set with no outline), its old look (the one its file in the repository has, or for a base server monster the
one the committed bounty pool gives it) and its new look: a look of pair 50 (outfits 2682-3360) that no monster, player or step wears
yet, that passes the same bar by the numbers (tools/ci/check_content.py holds the rows to it), that has no colour mask and that moves while
it stands (an idle group, or the walk in place list of game_bossanimate, O533 / O534). The new looks are in the pair already, so this step
needs no new picture; it rides with pair 73 like the other look steps.

The repository files keep the old look, so a server whose client is on an older pair draws what it always did. This step runs after
`monstercreaturelooks` and does, only when config.lua chaosClientPair is 73 or more (client_pair.py, README "Client pair guard"):
  * the `<look type="OLD">` of the monster's XML file, or the `lookType = OLD` of its Lua file (`monster.outfit`), anywhere under
    DATA_DIR/monster (our files and the base server's) becomes NEW. The colour fields stay: the new outfits have no colour mask and
    ignore them, and gen_bounty_pool.py gives the committed pool back from them. A monster of the recolour map (O531: six of them) wears
    the copy of its old look at pair 69 and more: the copy is a look this step knows and replaces;
  * the row of the monster in DATA_DIR/scripts/chaos/bounty_pool.lua (`look = OLD`, or its copy) becomes `look = NEW`; a boss has no row;
  * the quest and trial tables that name an old look for a monster they spawn themselves (`look = {lookType = OLD}` in
    DATA_DIR/scripts/chaos/ascension_quest_config.lua and trials_config.lua: the Warden of Ascension and the Risen Bones / Tithed Dead
    adds) get the new look of the map row that has that old look; the look of such a table row the map does not know is left alone.
A monster with no file, or whose look is none of the old one, its copy and the new one, stops the step (exit 1). Below pair 73 the step
prints a WARNING line and changes nothing; a second run changes nothing. --dry-run writes nothing.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402
import install_monster_creature_looks as C  # noqa: E402
import install_monster_donor_looks as D  # noqa: E402
import install_monster_recolour as R  # noqa: E402
import install_monster_wst_looks as P  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_o619_looks.csv')
POOL = R.POOL
MONSTERS = os.path.join('monster')
EARLIER = (R.MAP, D.MAP, P.MAP, C.MAP)   # the maps of the pairs before: a monster of one of them wears that look when this step meets it
CONFIGS = (os.path.join('scripts', 'chaos', 'ascension_quest_config.lua'), os.path.join('scripts', 'chaos', 'trials_config.lua'))


def read_map(path=MAP):
    """[(monster, old look, new look)]"""
    return R.read_map(path)


def earlier_looks(paths=EARLIER):
    """{monster: {looks an earlier pair's step gave it}}"""
    return C.earlier_looks(paths)


FACTS = os.path.join(REPO, 'server', 'data', 'monster', 'o619_look_facts.csv')
# the stock bar of the O610 look audit (docs/SPRITE_STYLE.md), the rules of its flags.py for a monster look, on the numbers of FACTS
BAR_SOFT, BAR_RIM, BAR_MIRROR, BAR_MIRROR_LEAN, BAR_LEAN, BAR_WALK = 0.05, 0.35, 0.95, 0.65, 6, 4


def read_facts(path=FACTS):
    """{look: row} of o619_look_facts.csv: the measures of the old and the new looks of the map (O610 audit numbers, pair 71)"""
    with open(path, newline='', encoding='utf-8') as f:
        return {int(r['look']): r for r in csv.DictReader(f)}


def bar_problems(row):
    """The reasons a look fails the stock bar, from its facts row (what flags.py of the audit tests for a monster): four directions of
    its own, an oblique camera (the east is not a mirrored west unless the lean is stock's), a dark outline on the rim, no soft alpha, a walk
    of pictures. A look without a colour mask is asked for as well: the monster files keep colours the new look must ignore."""
    out = []
    dirs, mirror, lean = int(row['dirs']), float(row['east_mirror']), float(row['lean'])
    if dirs != 4:
        out.append('%d directions' % dirs)
    elif mirror >= BAR_MIRROR or (mirror >= BAR_MIRROR_LEAN and abs(lean) <= BAR_LEAN):
        out.append('upright camera: east = mirrored west (%.2f), lean %.0f px' % (mirror, lean))
    if float(row['soft_alpha']) > BAR_SOFT:
        out.append('soft alpha on %d%% of the body' % round(100 * float(row['soft_alpha'])))
    if float(row['rim_dark']) < BAR_RIM:
        out.append('no dark outline (%d%% of the rim dark)' % round(100 * float(row['rim_dark'])))
    if int(row['walk_pictures']) < BAR_WALK:
        out.append('walk of %s pictures' % row['walk_pictures'])
    if int(row['layers']) != 1:
        out.append('a colour mask (%s layers)' % row['layers'])
    return out


def config_looks(rows):
    """{old look: new look} of the rows for the quest and trial tables: an old look every row that has it sends to one new look"""
    seen = {}
    for _name, old, new in rows:
        seen.setdefault(old, set()).add(new)
    return {old: next(iter(news)) for old, news in seen.items() if len(news) == 1}


def retype_config(text, looks):
    """(new text, moved, done): `look = {lookType = OLD` of a table row becomes NEW for each OLD of looks; moved counts the changes, done the
    rows that already have a new look"""
    moved = done = 0
    news = set(looks.values())
    for m in list(re.finditer(r'\blook\s*=\s*\{\s*lookType\s*=\s*(\d+)', text)):
        if int(m.group(1)) in news:
            done += 1

    def sub(m):
        nonlocal moved
        old = int(m.group(2))
        if old not in looks:
            return m.group(0)
        moved += 1
        return m.group(1) + str(looks[old])
    out = re.sub(r'(\blook\s*=\s*\{\s*lookType\s*=\s*)(\d+)', sub, text)
    return out, moved, done


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    dry = '--dry-run' in args
    path = MAP
    if '--map' in args:
        i = args.index('--map')
        path = args[i + 1]
        del args[i:i + 2]
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_SWAP, 'monsterswaplooks')
    print(why)
    if not ok:
        return 0
    rows = read_map(path)
    earlier = earlier_looks()
    files = D.definitions(os.path.join(data_dir, MONSTERS), {r[0] for r in rows})
    bad, moved, done, writes = [], 0, 0, []
    for name, old, new in rows:
        if name not in files:
            bad.append('%s: no monster file under %s' % (name, MONSTERS))
            continue
        olds = {old} | earlier.get(name, set())
        for p, kind in files[name]:   # a name defined twice (ours and the base's) moves in both
            with open(p, encoding='utf-8', errors='surrogateescape', newline='') as f:
                text = f.read()
            out, state = (P.retype_xml if kind == 'xml' else P.retype_lua)(text, olds, new)
            if state == 'other':
                m = (R.LOOK_TAG if kind == 'xml' else D.LUA_OUTFIT).search(text)
                bad.append('%s: %s has look %s, the map knows %d and %d' % (name, os.path.relpath(p, data_dir), m.group(2), old, new))
            elif state == 'moved':
                moved += 1
                writes.append((p, out))
            else:
                done += 1
    print('monster files: %d moved to their new look, %d already there' % (moved, done))
    pool = os.path.join(data_dir, POOL)
    if os.path.exists(pool):
        with open(pool, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        out, pm, pd = C.retype_pool(text, rows, earlier)
        print('bounty_pool.lua: %d rows moved to their new look, %d already there' % (pm, pd))
        if out != text:
            writes.append((pool, out))
    else:
        print('bounty_pool.lua: not installed, skipped')
    looks = config_looks(rows)
    cm = cd = 0
    for rel in CONFIGS:
        cfg = os.path.join(data_dir, rel)
        if not os.path.exists(cfg):
            continue
        with open(cfg, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        out, m, d = retype_config(text, looks)
        cm, cd = cm + m, cd + d
        if out != text:
            writes.append((cfg, out))
    print('quest and trial tables: %d look rows moved to their new look, %d already there' % (cm, cd))
    for line in bad:
        print('ERROR', line)
    if bad:
        return 1
    if dry:
        print('dry run: nothing written (%d files would change)' % len(writes))
        return 0
    for p, text in writes:
        R.write(p, text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
