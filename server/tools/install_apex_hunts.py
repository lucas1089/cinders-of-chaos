#!/usr/bin/env python3
"""The ten hunt monsters of levels 2100-2500 (O763) join the six O759 hall hunts once the client has pair 84.
install_all.py step `apexhunts`.

usage: python3 -I install_apex_hunts.py DATA_DIR [--dry-run] [--swaps CSV] [--map CSV] [--spawn PATH]

Client pair 84 holds their outfits 3734-3743 (client/tools/sprites/gen_apex_monsters.py, README "Hunt monsters above level 2000 (O763)").
Their monster files are ours (data/monster/monsters/chaos, registered by the `monsters` step) and keep a stand-in look of pair 83 in the
repository (server/data/monster/monster_apex_looks.csv: monster, stand-in look, new look); they spawn nowhere until this step runs. server/data/monster/apex_hunt_swaps.csv names, per hunt plan, an old monster of that hunt (levels 1500-2000), the new
monster that takes its packs and the share of its packs that move (0 to 1). The choice is by level: the lowest monsters of each hunt give
their packs first, so the hunt keeps its density and its tiles (the spawn points do not move, only the names).

This step runs after `contentareas` (which writes each plan's spawn blocks, marked chaoscontent="PLAN") and does, only when config.lua
chaosClientPair is 84 or more (client_pair.py, README "Client pair guard"):
  * in the spawn file of the loaded map (DATA_DIR/world/<mapName>-spawn.xml, or --spawn), among the blocks of the plan whose creatures are
    all the old monster (or that this step moved before: attribute chaosapex="OLD"), the i-th block (0-based, file order) moves when
    floor((i + 1) * share) > floor(i * share): its monsters get the new name and the block the attribute chaosapex="OLD". A block of
    another monster or of a mixed pack is never touched. Rerun after `contentareas` wrote the blocks again, it moves the same blocks;
  * the `<look type="STAND-IN">` of each new monster's file under DATA_DIR/monster becomes its new look (outfits 3734-3743);
  * in DATA_DIR/scripts/chaos/bounty_pool.lua, every monster the swaps name gets its spawn count from the spawn file (the rule of
    gen_bounty_pool.py: its monster entries), and a new monster without a row gets one (level the middle of its <level>, experience,
    health of its file, its new look), a row of a new monster gets its new look, in the order of the pool (level, then name).
A swap whose plan has no block in the spawn file, or a new monster without a file or with a look that is neither of its map row, stops the step (exit 1). Below pair 84 the step
prints a WARNING line and changes nothing; a second run changes nothing. --dry-run writes nothing.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import client_pair  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
SWAPS = os.path.join(REPO, 'server', 'data', 'monster', 'apex_hunt_swaps.csv')
MAP = os.path.join(REPO, 'server', 'data', 'monster', 'monster_apex_looks.csv')
POOL = os.path.join('scripts', 'chaos', 'bounty_pool.lua')
MONSTER_DIR = os.path.join('monster', 'monsters', 'chaos')
BLOCK = re.compile(r'\t<spawn\b[^>]*>.*?</spawn>\n', re.S)
MON = re.compile(r'(<monster\s+name=")([^"]+)(")')
POOL_ROW = re.compile(r'^\t\t\{name = "([^"]+)", level = (\d+), exp = (\d+), health = (\d+), spawns = (\d+), look = (\d+)(.*)\},\r?$', re.M)


def read_swaps(path=SWAPS):
    """[(plan, old, new, share)]"""
    with open(path, newline='', encoding='utf-8') as f:
        out = [(r['plan'], r['old'], r['new'], float(r['share'])) for r in csv.DictReader(f)]
    for plan, old, new, share in out:
        if not 0 < share <= 1 or old == new:
            raise SystemExit('%s: %s -> %s share %s: a share above 0 and up to 1, two monsters' % (plan, old, new, share))
    return out


def chosen(i, share):
    """the i-th block of a swap moves"""
    return int((i + 1) * share + 1e-9) > int(i * share + 1e-9)


def swap_text(text, swaps):
    """(the spawn file with the swaps applied, {(plan, old, new): (blocks moved now, blocks of the new monster in all)}, [problems])"""
    counts, bad = {}, []
    for plan, old, new, share in swaps:
        tag = 'chaoscontent="%s"' % plan
        blocks = [m for m in BLOCK.finditer(text) if tag in m.group(0).split('>', 1)[0]]
        if not blocks:
            bad.append('%s: no spawn block of the plan in the spawn file (run the contentareas step first)' % plan)
            continue
        mine = []
        for m in blocks:
            b = m.group(0)
            head = b.split('>', 1)[0]
            names = set(n for _a, n, _c in MON.findall(b))
            src = re.search(r'\schaosapex="([^"]*)"', head)
            if (src and src.group(1) == old and names == {new}) or (not src and names == {old}):
                mine.append(m)
        moved, total, pieces, last = 0, 0, [], 0
        for i, m in enumerate(mine):
            b = m.group(0)
            if not chosen(i, share):
                continue
            total += 1
            if 'chaosapex=' in b.split('>', 1)[0]:
                continue
            nb = re.sub(r'^(\t<spawn\b[^>]*?)>', r'\1 chaosapex="%s">' % old, b, count=1)
            nb = MON.sub(lambda x: x.group(1) + new + x.group(3), nb)
            pieces.append(text[last:m.start()] + nb)
            last = m.end()
            moved += 1
        text = ''.join(pieces) + text[last:]
        counts[(plan, old, new)] = (moved, total)
    return text, counts, bad


def read_map(path=MAP):
    """{monster: (stand-in look, new look)}"""
    with open(path, newline='', encoding='utf-8') as f:
        return {r['monster']: (int(r['look']), int(r['new_look'])) for r in csv.DictReader(f)}


def monster_path(data_dir, name):
    """the monster file of ours named `name`, None when there is none"""
    folder = os.path.join(data_dir, MONSTER_DIR)
    for root, dirs, files in os.walk(folder):
        dirs.sort()
        for f in sorted(files):
            if f.endswith('.xml'):
                p = os.path.join(root, f)
                n = re.search(r'<monster\s+name="([^"]+)"', open(p, encoding='utf-8', errors='replace').read())
                if n and n.group(1) == name:
                    return p
    return None


def retype(text, olds, new):
    """(text, 'moved' | 'done' | 'other') of the first <look type> (install_monster_wst_looks.retype_xml)"""
    m = re.search(r'(<look\s+type=")(\d+)(")', text)
    if not m:
        return text, 'other'
    cur = int(m.group(2))
    if cur == new:
        return text, 'done'
    if cur not in olds:
        return text, 'other'
    return text[:m.start(2)] + str(new) + text[m.end(2):], 'moved'


def monster_file(data_dir, name):
    """(level, exp, health, look) of the monster file of ours named `name`, None when there is none"""
    folder = os.path.join(data_dir, MONSTER_DIR)
    for root, dirs, files in os.walk(folder):
        dirs.sort()
        for f in sorted(files):
            if not f.endswith('.xml'):
                continue
            t = open(os.path.join(root, f), encoding='utf-8', errors='replace').read()
            n = re.search(r'<monster\s+name="([^"]+)"', t)
            if not n or n.group(1) != name:
                continue
            lv = re.search(r'<level\s+min="(\d+)"\s+max="(\d+)"', t)
            ex = re.search(r'<monster\s[^>]*\sexperience="(\d+)"', t)
            hp = re.search(r'<health\s[^>]*max="(\d+)"', t)
            lk = re.search(r'<look\s+type="(\d+)"', t)
            if not (lv and ex and hp and lk):
                return None
            return ((int(lv.group(1)) + int(lv.group(2))) // 2, int(ex.group(1)), int(hp.group(1)), int(lk.group(1)))
    return None


def spawn_counts(text):
    out = {}
    for _a, n, _c in MON.findall(text):
        out[n] = out.get(n, 0) + 1
    return out


def pool_text(text, names, counts, stats, looks=None):
    """the pool with the spawns of `names` from `counts`, the look of each name of `looks` ({name: new look}) and a row for each name of
    `stats` it lacks; (text, rows set, rows added)"""
    set_, added = 0, 0
    looks = looks or {}

    def fix(m):
        nonlocal set_
        if m.group(1) not in names:
            return m.group(0)
        want = counts.get(m.group(1), 0)
        lk = looks.get(m.group(1), int(m.group(6)))
        if int(m.group(5)) == want and int(m.group(6)) == lk:
            return m.group(0)
        set_ += 1
        row = m.group(0).replace('spawns = %s,' % m.group(5), 'spawns = %d,' % want, 1)
        return row.replace('look = %s' % m.group(6), 'look = %d' % lk, 1)
    text = POOL_ROW.sub(fix, text)
    hunt = text.find('\thunt = {')
    end = text.find('\n\t},', hunt)
    have = {m.group(1) for m in POOL_ROW.finditer(text)}
    for name, (lv, ex, hp, lk) in sorted(stats.items(), key=lambda kv: (kv[1][0], kv[0])):
        if name in have:
            continue
        row = '\t\t{name = "%s", level = %d, exp = %d, health = %d, spawns = %d, look = %d},\n' % (
            name, lv, ex, hp, counts.get(name, 0), looks.get(name, lk))
        at = end + 1
        for m in POOL_ROW.finditer(text, hunt, end):
            if (int(m.group(2)), m.group(1)) > (lv, name):
                at = m.start()
                break
        text = text[:at] + row + text[at:]
        end = text.find('\n\t},', hunt)
        added += 1
    return text, set_, added


def spawn_file(data_dir):
    """the spawn file of the loaded map (patch_base_towns.map_path: config.lua mapName, else the one map of world/), None without one"""
    import patch_base_towns
    mp = patch_base_towns.map_path(data_dir)
    return mp[:-5] + '-spawn.xml' if mp else None


def write(path, text):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='latin-1' if path.endswith('.xml') else 'utf-8', newline='') as f:
        f.write(text)
    os.replace(tmp, path)


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    dry = '--dry-run' in args
    opts = {}
    for k in ('--swaps', '--spawn', '--map'):
        if k in args:
            i = args.index(k)
            opts[k] = args[i + 1]
            del args[i:i + 2]
    args = [a for a in args if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    data_dir = args[0]
    ok, why = client_pair.allows(data_dir, client_pair.PAIR_APEX_MONSTERS, 'apexhunts')
    print(why)
    if not ok:
        return 0
    swaps = read_swaps(opts.get('--swaps', SWAPS))
    sp = opts.get('--spawn') or spawn_file(data_dir)
    if not sp or not os.path.exists(sp):
        print('ERROR spawn file %s is missing' % sp)
        return 1
    with open(sp, encoding='latin-1', newline='') as f:
        text = f.read()
    new_text, counts, bad = swap_text(text, swaps)
    looks = read_map(opts.get('--map', MAP))
    stats, writes, moved = {}, [], 0
    for new in sorted({n for _p, _o, n, _s in swaps}):
        p = monster_path(data_dir, new)
        if p is None or new not in looks:
            bad.append('%s: no monster file of ours under %s%s' % (new, MONSTER_DIR, '' if new in looks else ' or no row of the look map'))
            continue
        with open(p, encoding='utf-8', newline='') as f:
            mt = f.read()
        out, state = retype(mt, {looks[new][0]}, looks[new][1])
        if state == 'other':
            bad.append('%s: %s has a look that is neither %d nor %d' % (new, os.path.relpath(p, data_dir), looks[new][0], looks[new][1]))
        elif state == 'moved':
            moved += 1
            writes.append((p, out))
        st = monster_file(data_dir, new)
        stats[new] = st and st[:3] + (looks[new][1],)
    for line in bad:
        print('ERROR', line)
    if bad:
        return 1
    print('monster files: %d moved to their new look, %d already there' % (moved, len(stats) - moved))
    for (plan, old, new), (mv, total) in sorted(counts.items()):
        print('%s: %s -> %s: %d pack(s) moved now, %d in all' % (plan, old, new, mv, total))
    if new_text != text:
        writes.append((sp, new_text))
    pool = os.path.join(data_dir, POOL)
    if os.path.exists(pool):
        with open(pool, encoding='utf-8', newline='') as f:
            ptext = f.read()
        names = {o for _p, o, _n, _s in swaps} | {n for _p, _o, n, _s in swaps}
        out, set_, added = pool_text(ptext, names, spawn_counts(new_text), stats, {n: looks[n][1] for n in stats})
        print('bounty_pool.lua: %d spawn counts set, %d rows added' % (set_, added))
        if out != ptext:
            writes.append((pool, out))
    else:
        print('bounty_pool.lua: not installed, skipped')
    if dry:
        print('dry run: nothing written (%d files would change)' % len(writes))
        return 0
    for p, t in writes:
        if p.endswith('-spawn.xml'):
            write(p, t)
        else:
            with open(p + '.tmp', 'w', encoding='utf-8', newline='') as f:
                f.write(t)
            os.replace(p + '.tmp', p)
    return 0


if __name__ == '__main__':
    sys.exit(main())
