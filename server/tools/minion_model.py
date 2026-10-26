#!/usr/bin/env python3
"""The minion balance model of the Necromancer line (O160; computed, not measured in game; server/data/spells/README.md
"Necromancer minions (O160)").

usage: python3 -I server/tools/minion_model.py [--levels 50,200,500,1000] [--class necromancer|lich|bonelord] [--check]
                                               [--legacy]

What it answers, per level: what the minions deal (damage per second of each kind, with its two spells, on 1 and on 5
enemies), how long they live in a hunt (health against the damage a pack deals to them, deaths per hour, the share of the
fight they are alive), what that is worth next to the owner's own spells and its wand, and where the class stands next to
the median class (pack_model.py: damage on 1 and on 5 targets, and experience per hour in packs).

Inputs (everything in the repo, so CI runs it without the base tree):
  necro_config.lua, necro_core.lua   the minion formulas, caps, spells, regeneration and incoming damage rule: run by
                                     tools/minion_numbers.lua (luajit or lua5.3; env LUAJIT) so the model uses the server's
                                     own functions
  necro_balance_config.lua           the model's inputs and the limits of --check
  rotation_sim.py                    the owner's spells (best set of 5, class spell factor included) and the Mystic's
                                     rotation (the wand)
  pack_model.py                      the class totals (C4 measured, kit changes), the median class, the pack, its health,
                                     the walking time and the kills per hour
  pace_config.lua                    the pace damage curve (what a monster deals to the owner: 0.85 .. 0.40)

The model:
  * Damage. total = kappa x (spells + wand + tree x minions x alive). kappa solves the C4 measurement (the class's total
    with 4 skeletons, no minion spells, no cap of 3, at full health) at every level; the tree factor is solved from the
    minions' share of that measurement at 300 and 1000 (49% / 50%). Against it the model takes the cap, the minion spells
    and the time the minions are alive. The class damage factor is today's (necro_config / class_tree.lua).
  * The hunt. A pack of P monsters (pack_model.py's lure rule), each dealing monsterDps to whoever it hits, `focus` of its
    attacks on the minions, the average monster alive `alive` of the clear time. The pack's damage to the minions is
    spread over them by `aggro`. A minion that dies is lost for the rest of the fight (its damage time stops), is raised
    again before the next pack, and the others start it with their health left plus the regeneration of the walk. Steady
    state over `packs` packs. The monsters' damage on a minion is x the pace damage curve when necro_config.lua
    minions.incoming.pace is on (--legacy: as before O160, whole).
  * Totals against the median class: pack_model.damage() (1 and 5 targets), and kills per hour in packs through
    pack_model.kills_per_hour with the class's row replaced by the model's.
"""
import json, math, os, statistics, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rotation_sim as R
import pack_model as P

SERVER = os.path.normpath(os.path.join(HERE, '..'))
CLASSES = {'necromancer': 'Necromancer', 'lich': 'Lich', 'bonelord': 'Bone Lord'}
SPELL_LEVEL = {'warrior': 8, 'mage': 16, 'skeleton': 20, 'shade': 1, 'golem': 1}
SUMMON = ('warrior', 'mage')


def lua_bin():
    return os.environ.get('LUAJIT', 'luajit')


_dump = {}


def dump(levels):
    """the numbers of the real config and core for these levels (tools/minion_numbers.lua)"""
    key = tuple(levels)
    if key not in _dump:
        args = [lua_bin(), 'tools/minion_numbers.lua'] + ['%d:%.4f' % (lv, R.stats('Necromancer', lv)['ML']) for lv in levels]
        out = subprocess.run(args, cwd=SERVER, check=True, capture_output=True, text=True).stdout
        _dump[key] = json.loads(out)
    return _dump[key]


def lin(points, x):
    return P.lin([tuple(p) for p in points], x)


def power(points, x):
    """a power law between the points (below the first by the exponent of the first two, above the last by the last)"""
    pts = [tuple(p) for p in points]
    if x <= pts[0][0]:
        (x0, y0), (x1, y1) = pts[0], pts[1]
    elif x >= pts[-1][0]:
        (x0, y0), (x1, y1) = pts[-2], pts[-1]
    else:
        (x0, y0), (x1, y1) = next((a, b) for a, b in zip(pts, pts[1:]) if x <= b[0])
    e = math.log(y1 / y0) / math.log(x1 / x0)
    return y0 * (x / x0) ** e


def at_level(points, level):
    """the value of a list of {level, value} steps ({level, count}): the last step reached"""
    v = 0
    for lv, n in points:
        if level >= lv:
            v = n
    return v


# ------------------------------------------------------------------------------------------------ the minions
def rows_of(data, cls, level):
    return {r['kind']: r for r in data['rows'] if r['class'] == cls and r['level'] == level}


def compose(bal, cls, level, build, total):
    """the kinds a class has out at `level` for a build name: the build's kinds in order, a kind not yet learned replaced
    by the warrior (Raise Bone Warrior, level 8), at most the total cap (the golem is on top of it)"""
    if cls == 'necromancer':
        names = bal['builds'][build]
    else:
        names = bal['classBuilds'][cls]
    kinds = []
    for k in names:
        if k == 'golem':
            continue
        kinds.append(k if level >= SPELL_LEVEL[k] else 'warrior')
    kinds = kinds[:total] if total else []
    if 'golem' in names and level >= 1 and cls == 'bonelord':
        kinds.append('golem')
    return kinds


def c4_dps(data, cls, level):
    """the damage per second of the minions of the C4 measurement: skeletons (the shade, the golem) hitting every 2 s,
    no spell, the caps of that day"""
    bal = data['balance']
    rows = rows_of(data, cls, level)
    kind = {'necromancer': 'skeleton', 'lich': 'shade', 'bonelord': 'skeleton'}[cls]
    n = at_level(bal['c4']['caps'][cls], level)
    r = rows[kind]
    one = (r['hitMin'] + r['hitMax']) / 2 / (data['config']['minions'][kind]['intervalMs'] / 1000.0)
    total = n * one
    if bal['c4']['golem'].get(cls) and level >= 1:
        g = rows['golem']
        total += (g['hitMin'] + g['hitMax']) / 2 / (data['config']['minions']['golem']['intervalMs'] / 1000.0)
    return total


# ------------------------------------------------------------------------------------------------ the hunt
def monster_dps(bal, level):
    return power(bal['monsterDps'], max(level, 1))


def pace_mult(data, level, legacy):
    inc = data['config']['minions'].get('incoming')
    if legacy or not inc:
        return 1.0
    f = inc.get('factor', 1.0)
    if inc.get('pace'):
        f *= lin(data['paceDamage'], level)
    return f


def regen_rates(data, legacy):
    """(per second in the fight, per second idle, ms until idle) as shares of the maximum health"""
    r = data['config']['minions'].get('regen')
    if legacy or not r:
        return 0.0, 0.0, 0.0
    return r.get('combat', 0.0), r.get('idle', 0.0), r.get('idleAfterMs', 0) / 1000.0


def pack_of(level, damage1, damage5, cfg, mons):
    """(pack size, clear time, walking time, health per monster) for a class with these damages: pack_model.py's rule"""
    scaled = level >= 1000
    health = lin(P.SCALED_HEALTH, level) if scaled else P.median_health(mons, level)
    m = lin(cfg['scaled'] if scaled else cfg['base'], level)
    p0, walk = next((p, w) for lo, hi, p, w in P.PACK if lo <= level < hi)
    share = max(0.0, (damage5 - damage1) / damage5) if damage5 else 0.0
    n = min(P.PCAP, p0 - 2 + 4 * min(1.0, share / 0.6))
    s = max(0.0, (damage5 - damage1) / 4)
    clear = n * health * m / (damage1 + (n - 1) * s)
    return n, clear, walk, health * m


def fight(data, cls, level, kinds, clear, n, legacy):
    """the pack cycles of a minion set: returns {'alive': the share of the damage time the minions are alive (damage
    weighted), 'deaths': minions lost per pack, 'packs': packs a full set survives, 'pool': the minions' health,
    'incoming': the damage a pack deals to them} at steady state"""
    bal = data['balance']
    rows = rows_of(data, cls, level)
    if not kinds:
        return {'alive': 0.0, 'deaths': 0.0, 'packs': float('inf'), 'pool': 0, 'incoming': 0.0}
    hp = [rows[k]['health'] for k in kinds]
    dps = [rows[k]['dps1'] for k in kinds]
    w = [bal['aggro'][k] for k in kinds]
    share = [x / sum(w) for x in w]
    walk = next(wk for lo, hi, p, wk in P.PACK if lo <= level < hi)
    incoming = bal['focus'] * monster_dps(bal, level) * pace_mult(data, level, legacy) * n * bal['alive'] * clear
    c_rate, i_rate, idle_after = regen_rates(data, legacy)
    ratio = [1.0] * len(kinds)
    alive_sum, weight_sum, deaths_sum, counted = 0.0, 0.0, 0.0, 0
    for pack in range(bal['packs']):
        deaths = 0
        up = []
        for i in range(len(kinds)):
            if ratio[i] <= 0:  # raised again before the pack
                ratio[i] = 1.0
            take = share[i] * incoming
            alive = min(1.0, ratio[i] * hp[i] / take) if take > 0 else 1.0
            up.append(alive)
            left = ratio[i] - take / hp[i]
            # the regeneration while it stands: in the fight (the share of the clear time it lives), idle on the walk
            ratio[i] = max(0.0, left)
            if ratio[i] <= 0:
                deaths += 1
            else:
                ratio[i] = min(1.0, ratio[i] + c_rate * clear * alive + i_rate * max(0.0, walk - idle_after))
        if pack >= bal['packs'] // 2:
            alive_sum += sum(u * d for u, d in zip(up, dps))
            weight_sum += sum(dps)
            deaths_sum += deaths
            counted += 1
    pool = sum(hp)
    return {'alive': alive_sum / weight_sum, 'deaths': deaths_sum / counted, 'pool': pool, 'incoming': incoming,
            'packs': pool / incoming if incoming else float('inf')}


# ------------------------------------------------------------------------------------------------ the class
_ctx = {}


def context():
    if not _ctx:
        spells, model = R.load_all()
        _ctx.update(spells=spells, model=model, cfg=P.pace(), mons=P.monsters())
    return _ctx


def spells_of(cls, level):
    c = context()
    b = R.analyse(c['spells'], c['model'], cls, level)['best']
    return (b['dps1'], b['dps5']) if b else (0.0, 0.0)


ANCHORS = (300, 1000)  # the levels of the C4 measurement


def anchor_kappa(key, tree, mdl):
    """kappa at the two C4 levels: the class's total then (today's class damage factor) over the model's raw sum with the
    minions of that day (skeletons, no spell, the caps of that day). Returns {level: (kappa on 1 target, on 5 targets)}"""
    out = {}
    for lv in ANCHORS:
        data = dump(mdl)
        cls = CLASSES[key]
        s1, s5 = spells_of(cls, lv)
        wand = wand_of(data, lv)
        c4 = c4_dps(data, key, lv)
        t1, t5 = c4_totals(data, key, lv)
        out[lv] = (t1 / (s1 + wand + tree * c4), t5 / (s5 + wand + tree * c4))
    return out


def kappa_at(anchors, level):
    """the tree and gear multiplier at a level: linear from 1 at level 1 to the level 300 value, then to the level 1000
    value (more tree points and better gear with the level), flat above"""
    pts1 = [(1, 1.0), (300, anchors[300][0]), (1000, anchors[1000][0])]
    pts5 = [(1, 1.0), (300, anchors[300][1]), (1000, anchors[1000][1])]
    return lin(pts1, level), lin(pts5, level)


def wand_of(data, level):
    mystic = R.analyse(context()['spells'], context()['model'], 'Mystic', level)['best']
    return data['balance']['wandShare'] * (mystic['dps1'] if mystic else 0.0)


def c4_totals(data, key, level):
    """the class's C4 totals (pack_model.py: measured, kit changes) at a level x today's class damage factor over the
    C4 day's"""
    bal = data['balance']
    t1, t5 = P.damage(CLASSES[key], level, kit=True)
    fix = lin(data['classDamage'][key], level) / lin(bal['c4']['classDamage'][key], level)
    return t1 * fix, t5 * fix


def model_class(key, level, build=None, legacy=False, tree=None, levels=None):
    """the numbers of one class at one level: see the module docstring. Returns a dict."""
    mdl = tuple(sorted(set(levels or (level,)) | set(ANCHORS)))
    data = dump(mdl)
    bal = data['balance']
    cls = CLASSES[key]
    c = context()
    tree = bal['minionTree'] if tree is None else tree
    rows = rows_of(data, key, level)
    total = rows['skeleton']['total']
    kinds = compose(bal, key, level, build or bal['defaultBuild'], total)
    s1, s5 = spells_of(cls, level)
    wand = wand_of(data, level)
    nominal1 = sum(rows[k]['dps1'] for k in kinds)
    nominal5 = sum(rows[k]['dps5'] for k in kinds)
    kappa1, kappa5 = kappa_at(anchor_kappa(key, tree, mdl), level)
    c4 = c4_dps(data, key, level)
    t1, t5 = c4_totals(data, key, level)
    # the clear time depends on the damage, which depends on the time alive: a few passes
    alive = 1.0
    for _ in range(6):
        d1 = kappa1 * (s1 + wand + tree * nominal1 * alive)
        d5 = kappa5 * (s5 + wand + tree * nominal5 * alive)
        n, clear, walk, hp = pack_of(level, d1, d5, c['cfg'], c['mons'])
        fl = fight(data, key, level, kinds, clear, n, legacy)
        alive = fl['alive']
    d1 = kappa1 * (s1 + wand + tree * nominal1 * alive)
    d5 = kappa5 * (s5 + wand + tree * nominal5 * alive)
    full1 = kappa1 * (s1 + wand + tree * nominal1)
    full5 = kappa5 * (s5 + wand + tree * nominal5)
    med1 = statistics.median(P.damage(n_, level)[0] for n_ in P.C4)
    med5 = statistics.median(P.damage(n_, level)[1] for n_ in P.C4)
    return {
        'class': key, 'level': level, 'build': build or bal['defaultBuild'], 'kinds': kinds, 'rows': rows,
        'ml': R.stats(cls, level)['ML'], 'spells1': s1, 'spells5': s5, 'wand': wand, 'c4minions': c4,
        'nominal1': nominal1, 'nominal5': nominal5, 'kappa1': kappa1, 'kappa5': kappa5, 'fight': fl,
        'pack': (n, clear, walk, hp), 'total1': d1, 'total5': d5, 'full1': full1, 'full5': full5,
        'c4total1': t1, 'c4total5': t5, 'median1': med1, 'median5': med5, 'tree': tree,
        'share1': tree * nominal1 * alive / (s1 + wand + tree * nominal1 * alive),
        'share1_full': tree * nominal1 / (s1 + wand + tree * nominal1),
        'ratio1': d1 / med1, 'ratio5': d5 / med5, 'ratio1_full': full1 / med1, 'ratio5_full': full5 / med5,
        'kph': kills_per_hour(cls, level, d1, d5),
    }

def kills_per_hour(cls, level, d1, d5):
    """(kills per hour of the class with these damages, the median class's, ratio): pack_model.kills_per_hour with the
    class's damage row replaced"""
    c = context()
    scaled = level >= 1000
    health = lin(P.SCALED_HEALTH, level) if scaled else P.median_health(c['mons'], level)
    real = P.damage

    def patched(name, L, kit=True):
        if name == cls and L == level:
            return d1, d5
        return real(name, L, kit)
    P.damage = patched
    try:
        mine = P.kills_per_hour(cls, level, scaled, c['cfg'], health)[0]
        med = statistics.median(P.kills_per_hour(n, level, scaled, c['cfg'], health)[0] for n in P.C4)
    finally:
        P.damage = real
    return mine, med, mine / med


# ------------------------------------------------------------------------------------------------ reports
def fmt_kind_rows(data, level):
    rows = rows_of(data, 'necromancer', level)
    out = []
    for k in ('skeleton', 'warrior', 'mage'):
        r = rows[k]
        out.append('| %d | %s | %d | %d | %.1f | %.1f | %.1f |' % (
            level, k, (r['hitMin'] + r['hitMax']) / 2, r['health'], (r['hitMin'] + r['hitMax']) / 2 / 2, r['dps1'], r['dps5']))
    return out


def report(levels, key, legacy, sens=False):
    data = dump(levels)
    bal = data['balance']
    print('| Level | Kind | Hit | Health | Plain dps | dps with spells (1 target) | dps with spells (5 targets) |')
    print('|---|---|---|---|---|---|---|')
    for lv in levels:
        for line in fmt_kind_rows(data, lv):
            print(line)
    print()
    print('| Level | Build | Minions | Pool health | Pack damage on them | Packs per set | Alive | Deaths per pack | Spells | Wand | Minions (nominal / alive) | Minion share | Total 1t | vs median | Total 5t | vs median | Exp/h vs median |')
    print('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|')
    out = {}
    for lv in levels:
        m = model_class(key, lv, legacy=legacy, levels=levels)
        out[lv] = m
        f = m['fight']
        print('| %d | %s | %s | %d | %d | %.1f | %.0f%% | %.2f | %.0f | %.0f | %.0f / %.0f | %.0f%% | %.0f | %.2f | %.0f | %.2f | %.2f |' % (
            lv, m['build'], '+'.join(m['kinds']), f['pool'], f['incoming'], f['packs'], 100 * f['alive'], f['deaths'],
            m['spells1'], m['wand'], m['tree'] * m['nominal1'], m['tree'] * m['nominal1'] * f['alive'], 100 * m['share1'],
            m['total1'], m['ratio1'], m['total5'], m['ratio5'], m['kph'][2]))
    return out


def check(levels):
    bal = dump(levels)['balance']
    lim = bal['limits']
    bad = []
    for lv in bal['checkLevels']:
        m = model_class('necromancer', lv, levels=tuple(bal['checkLevels']))
        f = m['fight']
        if f['alive'] < lim['uptimeMin']:
            bad.append('level %d: the trio is alive %.0f%% of the fight (at least %.0f%%)' % (lv, 100 * f['alive'], 100 * lim['uptimeMin']))
        if f['packs'] < lim['packsPerSet']:
            bad.append('level %d: a full set survives %.1f packs (at least %.1f)' % (lv, f['packs'], lim['packsPerSet']))
        if not lim['shareMin'] <= m['share1_full'] <= lim['shareMax']:
            bad.append('level %d: the minions are %.0f%% of the damage (%.0f-%.0f%%)' % (lv, 100 * m['share1_full'], 100 * lim['shareMin'], 100 * lim['shareMax']))
        for what, key, v in (('damage on 1 target', 'ratio1', m['ratio1']), ('damage on 5 targets', 'ratio5', m['ratio5']),
                             ('experience per hour', 'ratioExp', m['kph'][2])):
            lo, hi = lim[key]
            if not lo <= v <= hi:
                bad.append('level %d: %s %.2f of the median class (%.2f-%.2f)' % (lv, what, v, lo, hi))
    return bad


def main(argv):
    levels = tuple(int(x) for x in argv[argv.index('--levels') + 1].split(',')) if '--levels' in argv else tuple(dump((1,))['balance']['levels'])
    key = argv[argv.index('--class') + 1] if '--class' in argv else 'necromancer'
    legacy = '--legacy' in argv
    if '--check' in argv:
        bad = check(levels)
        for b in bad:
            print('FAIL ' + b)
        print('minion model: %s' % ('FAIL' if bad else 'ok'))
        return 1 if bad else 0
    report(levels, key, legacy)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
