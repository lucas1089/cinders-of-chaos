#!/usr/bin/env python3
"""Spell upgrades model (O686 phase 3): the typical rank per level, the typical power gain, the monster health curve H, and the switch
every other balance model reads (computed, not measured; docs/SPELL_UPGRADES.md sections 1.4, 5, README "Monster health curve and
the models (O686 phase 3)").

usage: python3 -I server/tools/spell_upgrade_model.py [--check] [--derive] [--table] [--no-upgrades] [--forms] [--parts rank,forms,...]
--check        exit 1 when the committed `health` curve of spell_ranks_config.lua is not the derivation, a limit of
               data/scripts/chaos/spell_upgrade_balance_config.lua fails (typical kill times within 3% of today at every level band,
               the main spell at rank 20 inside 1500 to 2000, refXpPerHour held to progression_model.lua, the no-upgrades
               character as the design states), or a class share is off
--derive       print the `health` curve as the derivation gives it, ready for spell_ranks_config.lua (use it when a part ships
               later: --parts rank,forms writes the curve of a release without combos and awakening), and the `typical` gain table of
               spell_upgrade_balance_config.lua that progression_model.lua --upgrades reads
--table        the rank, the power and the health factor per level
--no-upgrades  the character with no upgrades: experience an hour and hours to a level (design 5.6)
--forms        the Form band (design 2.1, phase 4): per kind the worst and best gain of one cast with the Form on one enemy and on five,
               from the real planner (tools/forms_numbers.lua over data/spells/forms.csv); --check fails when a row leaves the band
               (limits: spell_upgrade_balance_config.lua `formBand`)
--awakening    the Seal rates (design 3.2, phase 7): the clears an hour of the waystone, Greater Rift and pinnacle models against the rates
               the slot costs were set for (spell_awakening_config.lua `rates`), the hours of each slot, the signature of every
               awakened.csv row (about +5% of the spell) and the +3% of a class's damage each; --check fails when a model moves a rate by
               more than `tol` (20%) or a number leaves its band. The awakening part of P (`awakening.perSpell`) is not touched by it.

THE MODEL. The typical character hunts at the rate of progression_model.lua (minutes a level). A main rotation spell has `mainShare`
(16%) of the hunt damage, so it earns SP at 0.16 an hour of hunting (an SP is one hour of kill value at full share), and a rank costs
c x r^1.5 SP (42 SP for 20 ranks, spell_ranks_config.lua). The rank of the rotation's average spell is `avgRank` of that. A rank gives
+0.9% damage and a cooldown cut worth `cooldownWorth` of itself; Forms give 0.3% an average rank (6% at 20); combos give `combos.total`
(counted from the rows of spell_combos_config.lua: the share of the spell damage on a combo hit x the mean row bonus) from the average rank 3 to 10; awakening gives 3% a spell by level. P is their product. A class has `share` of its damage as spell
damage (class_dps_model.py's measured table), so its damage grows by 1 + share x (P - 1); H = 1 + classShare x (P - 1) so the median
class meets today's kill times. Checked against the design table of 5.3 (the old derivation script was never committed): rank, P and H
of every row to the digits of the table, except where the owner's 10-20% combos (design 4.2) moved P by about 1%.

THE SWITCH. active() is False in the default run and True with `--upgrades` (every balance model's main() calls from_argv()), or when
spell_ranks_config.lua `enabled` is true. gain(cls, level, targets) is the class damage factor, health(level) is H (the committed
curve, the one ChaosSpellRanks.healthFactor reads), heal_gain(level) the heal factor, both 1.0 while inactive. pvp_gain() is the half
rule (design 5.2): rank and Forms at 50%, awakening and combos off.
"""
import math
import os
import re
import statistics
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)  # python -I leaves the script's folder out of sys.path
SERVER = os.path.normpath(os.path.join(HERE, '..'))
REPO = os.path.normpath(os.path.join(SERVER, '..'))
RANKS = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'spell_ranks_config.lua')
BALANCE = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'spell_upgrade_balance_config.lua')
COMBOS = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'spell_combos_config.lua')
AWAKENING_LUA = os.path.join('tools', 'awakening_numbers.lua')
PROGRESSION = os.path.join('tools', 'progression_model.lua')
MEASURED = os.path.join(SERVER, 'data', 'spells', 'class_dps_measured.csv')
LEVELS = (100, 500, 1000)
FORMS_LUA = os.path.join('tools', 'forms_numbers.lua')
PART_NAMES = ('rank', 'forms', 'combos', 'awakening')

# ---- the switch ------------------------------------------------------------------------------------------------------------
_MODE = {'force': None}


_LISTENERS = []


def on_mode_change(fn):
    """a model that caches numbers of the mode registers a function that drops them"""
    _LISTENERS.append(fn)


def set_mode(on):
    """True: upgrades on; False: today; None: follow spell_ranks_config.lua `enabled`"""
    changed = _MODE['force'] != on
    _MODE['force'] = on
    if changed:
        for fn in _LISTENERS:
            fn()


def active():
    if _MODE['force'] is not None:
        return _MODE['force']
    if os.environ.get('CHAOS_UPGRADES') in ('1', 'on'):
        return True
    return ranks_config()['enabled']


class forced(object):
    """`with forced(False):` the numbers of today inside an upgrades run (and `forced(True)` the other way); the mode is restored"""

    def __init__(self, on):
        self.on = on

    def __enter__(self):
        self.old = _MODE['force']
        set_mode(self.on)
        return self

    def __exit__(self, *exc):
        set_mode(self.old)
        return False


_PVP = {'on': False}


class pvp(object):
    """`with pvp():` the numbers against another player (design 5.2, owner 2026-11-20: rank and Forms at 50%, awakening and combos off):
    gain() and heal_gain() answer the half rule. Only counts while the upgrades are on"""

    def __enter__(self):
        self.old = _PVP['on']
        _PVP['on'] = True
        return self

    def __exit__(self, *exc):
        _PVP['on'] = self.old
        return False


def pvp_on():
    return _PVP['on'] and active()


def mode_key():
    """what a model that caches class damage keys it by"""
    return (active(), pvp_on())


def from_argv(argv):
    """--upgrades sets the mode on, --today off; both are removed from the list that is returned (a model's main() reads the rest)"""
    out = []
    for a in argv:
        if a == '--upgrades':
            set_mode(True)
        elif a == '--today':
            set_mode(False)
        else:
            out.append(a)
    return out


def banner():
    return 'spell upgrades: %s' % ('ON (class damage x the typical gain, monster health x H)' if active() else 'off (today)')


# ---- the config files -------------------------------------------------------------------------------------------------------
_CACHE = {}


def _read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def _pairs(body):
    return [(float(a), float(b)) for a, b in re.findall(r'\{\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+)\s*\}', body)]


def _block(text, key, open_='{', close='}'):
    """the text between the braces of `key = {...}` (balanced)"""
    m = re.search(r'\b' + key + r' = \{', text)
    if not m:
        raise KeyError(key)
    i, depth = m.end(), 1
    while depth:
        c = text[i]
        depth += c == '{'
        depth -= c == '}'
        i += 1
    return text[m.end():i - 1]


def ranks_config(path=RANKS):
    key = ('ranks', path)
    if key not in _CACHE:
        t = _read(path)
        cost = _block(t, 'cost')
        dmg, heal = _block(_block(t, 'effects'), 'damage'), _block(_block(t, 'effects'), 'heal')

        def num(body, name):
            return float(re.search(r'\b' + name + r' = (-?[0-9.]+)', body).group(1))
        pvp = _block(t, 'pvp')
        _CACHE[key] = {
            'enabled': re.search(r'\benabled = (true|false)', t).group(1) == 'true',
            'maxRank': int(num(t, 'maxRank')),
            'minLevel': int(num(t, 'minLevel')),
            'costExp': num(cost, 'exp'), 'totalSp': num(cost, 'totalSp'),
            'refXp': _pairs(_block(t, 'refXpPerHour')),
            'health': _pairs(_block(t, 'health')),
            'damage': {'power': num(dmg, 'power'), 'step': num(dmg, 'cooldownPerStep')},
            'heal': {'power': num(heal, 'power'), 'step': num(heal, 'cooldownPerStep')},
            'cdRanks': [int(float(x)) for x in _block(_block(t, 'effects'), 'cdRanks').split(',') if x.strip()],
            'pvp': {'rank': num(pvp, 'rank'), 'forms': num(pvp, 'forms')},
        }
    return _CACHE[key]


def combos_config(path=COMBOS):
    """the combo rows of spell_combos_config.lua (O686 phase 6): [(id, bonus, weight)], the band, and the model block. The typical gain of
    the combos is counted from them: triggerShare x the mean bonus weighted by `weight`"""
    key = ('combos', path)
    if key not in _CACHE:
        t = _read(path)
        rows = []
        for chunk in t.split('{id = "')[1:]:  # one chunk a row: the id, then (past the nested spell lists) the bonus and the weight
            m = re.search(r'bonus = ([0-9.]+), weight = ([0-9.]+)', chunk)
            rows.append((chunk.split('"', 1)[0], float(m.group(1)), float(m.group(2))))
        model = _block(t, 'model')
        band = _block(t, 'band')

        def num(body, name):
            return float(re.search(r'\b' + name + r' = (-?[0-9.]+)', body).group(1))
        _CACHE[key] = {
            'rows': rows,
            'band': (num(band, 'min'), num(band, 'max')),
            'model': {k: num(model, k) for k in ('triggerShare', 'typicalMax', 'bestMax')},
        }
    return _CACHE[key]


def combos_total(path=COMBOS):
    """the typical rotation's gain from the combos: the share of its spell damage on a combo hit x the mean bonus of the rows"""
    c = combos_config(path)
    w = sum(r[2] for r in c['rows'])
    mean = sum(r[1] * r[2] for r in c['rows']) / w
    return c['model']['triggerShare'] * mean


def combos_best(path=COMBOS):
    c = combos_config(path)
    return c['model']['triggerShare'] * max(r[1] for r in c['rows'])


def combos_problems(path=COMBOS):
    bad = []
    c = combos_config(path)
    lo, hi = c['band']
    if len(c['rows']) != 13:
        bad.append('combos: %d rows in spell_combos_config.lua, the design has 13' % len(c['rows']))
    for rid, bonus, weight in c['rows']:
        if not lo - 1e-9 <= bonus <= hi + 1e-9:
            bad.append('combo %s: bonus %.0f%% is outside %.0f%% to %.0f%% (owner 2026-11-20)' % (rid, bonus * 100, lo * 100, hi * 100))
    typical, best = combos_total(path), combos_best(path)
    if typical > c['model']['typicalMax'] + 1e-9:
        bad.append('combos: the typical rotation gains %.1f%%, the limit is %.1f%%' % (typical * 100, c['model']['typicalMax'] * 100))
    if best > c['model']['bestMax'] + 1e-9:
        bad.append('combos: the best legal rotation gains %.1f%%, the limit is %.1f%%' % (best * 100, c['model']['bestMax'] * 100))
    expected = balance_config()['combos']['expected']
    if abs(typical - expected) > 0.003:
        bad.append('combos: the rows count %.2f%% for the typical rotation, spell_upgrade_balance_config.lua `combos.total` says %.2f%% (within 0.3 points); '
                   'the health curve was derived from the second: change one and run --derive' % (typical * 100, expected * 100))
    return bad


# ---- awakening (design 3.1 to 3.3, phase 7) ----------------------------------------------------------------------------------
def awakening_numbers():
    """({config name: value}, {spell id: (value, output, utility, kind)}): spell_awakening_config.lua and the value of every row of
    data/spells/awakened.csv, from the one implementation (tools/awakening_numbers.lua)"""
    if 'awakening' not in _CACHE:
        out, last = None, None
        for exe in ('luajit', 'lua5.3'):
            try:
                r = subprocess.run([exe, AWAKENING_LUA], cwd=SERVER, capture_output=True, text=True, timeout=120)
            except FileNotFoundError:
                continue
            if r.returncode == 0:
                out = r.stdout
                break
            last = r.stderr
        if out is None:
            raise RuntimeError('awakening_numbers.lua needs luajit or lua5.3: %s' % last)
        cfg, rows = {}, {}
        for line in out.strip().split('\n'):
            f = line.split('\t')
            if f[0] == 'cfg':
                cfg[f[1]] = f[2]
            elif f[0] == 'row':
                rows[int(f[1])] = (float(f[2]), float(f[3]), float(f[4]), f[5])
        _CACHE['awakening'] = (cfg, rows)
    return _CACHE['awakening']


def awakening_rates():
    """what the three models say about the sources of the Seals: {'waystoneMinutes': a cleared deep map and the walk to the next one, as
    the pinnacle model plays it; 'waystoneIdeal': the waystone endgame model's clear time of tiers 16-25 plus the overhead, in minutes;
    'riftSeconds': a Greater run at the tier the median class reaches (greater_rift_model.py, levels 2000 and 2500, solo); 'pinnacleHours':
    the hours of top content of a whole set of fragments}. The models are imported here, not at the top: they import this module"""
    if 'awakeningRates' not in _CACHE:
        sys.modules.setdefault('spell_upgrade_model', sys.modules[__name__])
        import pinnacle_model as PM
        import greater_rift_model as GM
        import waystone_endgame_model as WM
        n = PM.numbers()
        cfg, bal = n['cfg'], n['bal']
        hours = PM.set_hours(cfg, bal)[0]
        num = WM.numbers()
        a = num['bal']['assume']
        deep = [WM.deep_target(num, tier, 'deepClearSeconds') + a['overheadSeconds'] for tier in range(16, 26)]
        res = GM.compute([2000, 2500])
        secs = [r['secsReach'] for r in res['rows']]
        _CACHE['awakeningRates'] = {'waystoneMinutes': bal['minutes']['waystone'], 'waystoneIdeal': sum(deep) / len(deep) / 60.0,
                                    'riftSeconds': sum(secs) / len(secs), 'pinnacleHours': hours}
    return _CACHE['awakeningRates']


def awakening_check(nums, rates):
    """the problems of the awakening against the models (empty when sound). nums: awakening_numbers(), rates: awakening_rates().
    Design 3.2: the slot costs were set for 4 Waystone Seals an hour (a 15 minute clear), 3 Rift Seals an hour (a 1200 s run) and 0.72
    Pinnacle Seals an hour (2 a kill, a set of fragments in 2.77 hours); a model that moves one of them by more than `tol` (20%) fails the
    check and the costs are retuned. The signature of every row is about +5% of the spell; with the +10% a spell is +3% of a class's damage"""
    cfg, rows = nums
    bad = []

    def f(name):
        return float(cfg[name])
    tol = f('tol')

    def within(label, got, want, unit):
        if abs(got / want - 1) > tol:
            bad.append('awakening: %s is %.2f %s in the models, the Seal costs were set for %.2f (%+.0f%%, limit +-%.0f%%): retune '
                       'spell_awakening_config.lua `slots` / `rates`' % (label, got, unit, want, (got / want - 1) * 100, tol * 100))
    # the rates the config states are the ones its own table is made of
    near_rates = (('rates.waystonePerHour', 60.0 / f('rates.waystoneMinutes'), 'waystonePerHour and waystoneMinutes'),
                  ('rates.riftPerHour', 3600.0 / f('rates.riftSeconds'), 'riftPerHour and riftSeconds'))
    for key, want, what in near_rates:
        if abs(f(key) - want) > 0.05 * want:
            bad.append('awakening: %s are not one rate: %.2f against %.2f' % (what, f(key), want))
    # the models
    within('a waystone clear and the walk to the next map (pinnacle_model.py minutes.waystone)', rates['waystoneMinutes'],
           f('rates.waystoneMinutes'), 'minutes')
    within('a deep waystone clear of tiers XVI-XXV and its overhead (waystone_endgame_model.py) x %.1f real efficiency' % f('rates.efficiency'),
           rates['waystoneIdeal'] * f('rates.efficiency'), f('rates.waystoneMinutes'), 'minutes')
    within('a Greater Rift run at the tier the median class reaches (greater_rift_model.py)', rates['riftSeconds'], f('rates.riftSeconds'),
           'seconds')
    within('the Pinnacle Seals an hour (2 a kill, a set of fragments in %.2f hours: pinnacle_model.py)' % rates['pinnacleHours'],
           f('perKillPinnacle') / rates['pinnacleHours'], f('rates.pinnacleSealsPerHour'), 'Seals an hour')
    # the three Seals of a slot come at the same time: the pinnacle hours of a slot against the waystone + rift hours
    slots = [tuple(int(x) for x in cfg['slot%d' % i].split(',')) for i in (1, 2, 3)]
    for i, (w, r, p) in enumerate(slots, 1):
        hours = w / f('rates.waystonePerHour') + r / f('rates.riftPerHour')
        pin = p / f('rates.pinnacleSealsPerHour')
        if abs(pin / hours - 1) > tol:
            bad.append('awakening: slot %d: the Pinnacle Seals take %.1f hours, the Waystone and Rift Seals %.1f (limit +-%.0f%%): the three '
                       'kinds must come together' % (i, pin, hours, tol * 100))
        if i > 1 and not (w > slots[i - 2][0] and r > slots[i - 2][1] and p > slots[i - 2][2]):
            bad.append('awakening: slot %d does not cost more of every Seal than slot %d' % (i, i - 1))
    # the signature of every awakened spell and the +3% of a class's damage each
    lo, hi, target = f('bandMin'), f('bandMax'), f('target')
    for sid, (v, out, util, kind) in sorted(rows.items()):
        if not lo - 1e-9 <= v <= hi + 1e-9:
            bad.append('awakening: spell %d (%s) signature is worth %.1f%% of the spell, the band is %.0f%% to %.0f%%' % (
                sid, kind, v * 100, lo * 100, hi * 100))
    if rows:
        mean = sum(v[0] for v in rows.values()) / len(rows)
        if abs(mean - target) > 0.005:
            bad.append('awakening: the mean signature is %.2f%% of the spell, the target is %.0f%%' % (mean * 100, target * 100))
        perspell = (f('bonus') + mean) * f('classShare')
        if abs(perspell - f('perSpell')) > 0.005:
            bad.append('awakening: (+%.0f%% and a %.1f%% signature) x a %.0f%% share is +%.2f%% of the class damage, the design says +%.0f%%' % (
                f('bonus') * 100, mean * 100, f('classShare') * 100, perspell * 100, f('perSpell') * 100))
    else:
        bad.append('awakening: data/spells/awakened.csv has no rows')
    # the awakening part of P is the one of the balance config, unchanged: 3% a spell
    if abs(balance_config()['awakening']['perSpell'] - f('perSpell')) > 1e-9:
        bad.append('awakening: spell_upgrade_balance_config.lua awakening.perSpell is %.3f, spell_awakening_config.lua perSpell %.3f' % (
            balance_config()['awakening']['perSpell'], f('perSpell')))
    return bad


def awakening_problems():
    return awakening_check(awakening_numbers(), awakening_rates())


def awakening_table():
    cfg, rows = awakening_numbers()
    rates = awakening_rates()
    f = lambda k: float(cfg[k])  # noqa: E731
    lines = ['| Source | in the models | the costs were set for |', '|---|---|---|',
             '| Waystone clear and walk (pinnacle_model.py) | %.1f min | %.1f min = %.1f an hour |' % (
                 rates['waystoneMinutes'], f('rates.waystoneMinutes'), f('rates.waystonePerHour')),
             '| Deep waystone clear, tiers XVI-XXV (waystone_endgame_model.py) x %.1f | %.1f min | %.1f min |' % (
                 f('rates.efficiency'), rates['waystoneIdeal'] * f('rates.efficiency'), f('rates.waystoneMinutes')),
             '| Greater Rift run (greater_rift_model.py, 2000 / 2500) | %.0f s | %.0f s = %.1f an hour |' % (
                 rates['riftSeconds'], f('rates.riftSeconds'), f('rates.riftPerHour')),
             '| Pinnacle Seals an hour (a set of fragments in %.2f h) | %.2f | %.2f |' % (
                 rates['pinnacleHours'], 2.0 / rates['pinnacleHours'], f('rates.pinnacleSealsPerHour')), '',
             '| Slot | Waystone | Rift | Pinnacle | hours (Waystone / 4 + Rift / 3) | hours of the Pinnacle Seals |', '|---:|---:|---:|---:|---:|---:|']
    for i in (1, 2, 3):
        w, r, p = (int(x) for x in cfg['slot%d' % i].split(','))
        lines.append('| %d | %d | %d | %d | %.1f | %.1f |' % (i, w, r, p, w / f('rates.waystonePerHour') + r / f('rates.riftPerHour'),
                                                             p / f('rates.pinnacleSealsPerHour')))
    vs = [v[0] for v in rows.values()]
    lines += ['', 'The signature of %d awakened spells: %.1f%% to %.1f%% of the spell, mean %.2f%% (target %.0f%%); with the +%.0f%% a spell is '
              '+%.2f%% of a class\'s damage (the design: +%.0f%% each, +%.0f%% with three).' % (
                  len(vs), min(vs) * 100, max(vs) * 100, sum(vs) / len(vs) * 100, f('target') * 100, f('bonus') * 100,
                  (f('bonus') + sum(vs) / len(vs)) * f('classShare') * 100, f('perSpell') * 100, f('perSpell') * 300)]
    return '\n'.join(lines)


def balance_config(path=BALANCE):
    key = ('balance', path)
    if key not in _CACHE:
        t = _read(path)

        def num(body, name):
            return float(re.search(r'\b' + name + r' = (-?[0-9.]+)', body).group(1))
        avg = _block(t, 'avgRank')
        comb = _block(t, 'combos')
        awake = _block(t, 'awakening')
        lim = _block(t, 'limits')
        parts = _block(t, 'parts')
        _CACHE[key] = {
            'parts': {n: re.search(r'\b' + n + r' = (true|false)', parts).group(1) == 'true' for n in PART_NAMES},
            'mainShare': num(t, 'mainShare'),
            'avg': {k: num(avg, k) for k in ('from', 'to', 'fromLevel', 'toLevel')},
            'cooldownWorth': num(t, 'cooldownWorth'),
            'formsTotal': num(_block(t, 'forms'), 'total'),
            # `total` is counted from the combo rows (spell_combos_config.lua, phase 6); the balance config's own number is what the
            # committed health curve was derived with (`expected`) and --check holds the two together
            'combos': dict({k: num(comb, k) for k in ('fromRank', 'toRank')}, expected=num(comb, 'total'),
                           total=combos_total() if os.path.exists(COMBOS) else num(comb, 'total')),
            'awakening': {'perSpell': num(awake, 'perSpell'), 'steps': _pairs(awake)},
            'classShare': num(t, 'classShare'), 'shareTol': num(t, 'shareTol'), 'healthStep': num(t, 'healthStep'),
            'limits': {k: num(lim, k) for k in ('killTime', 'killTimeOneTarget', 'killTimeFiveTargets', 'healthTol', 'refXpTol',
                                                  'noUpgradesXpTol', 'noUpgradesHoursTol')},
            'rank20': tuple(int(float(x)) for x in re.search(r'rank20 = \{([0-9., ]+)\}', lim).group(1).split(',')),
            'noUpgradesXp': _pairs(_block(lim, 'noUpgradesXp')),
            'noUpgradesHours': _pairs(_block(lim, 'noUpgradesHours')),
            'typical': _pairs(_block(t, 'typical')),
            'widen': {name: {k: float(v) for k, v in re.findall(r'(\w+) = ([0-9.]+)', body)}
                      for name, body in re.findall(r'\b(\w+) = \{([^{}]*)\}', _block(t, 'widen'))},
        }
    return _CACHE[key]


# ---- the Form band (design 2.1, phase 4) -----------------------------------------------------------------------------------
def form_band_config(path=BALANCE):
    key = ('formBand', path)
    if key not in _CACHE:
        body = _block(_read(path), 'formBand')

        def pair(name):
            m = re.search(r'\b' + name + r' = \{\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+)\s*\}', body)
            return float(m.group(1)), float(m.group(2))

        def num(name):
            return float(re.search(r'\b' + name + r' = (-?[0-9.]+)', body).group(1))
        _CACHE[key] = {'one': pair('one'), 'five': pair('five'), 'best': num('best'), 'utilityBelow': num('utilityBelow'),
                       'twinGap': num('twinGap'), 'counted': num('counted'), 'countedTol': num('countedTol')}
    return _CACHE[key]


def form_rows():
    """[{id, name, tier, pick, kind, g1, g5, situation, utility}] of every Form of data/spells/forms.csv: the gain of one cast with the
    Form, on one enemy and on a pack of five (the real planner, tools/forms_numbers.lua; the spell hits t5 of the five)"""
    if 'forms' not in _CACHE:
        import rotation_sim as R
        model = R.load_model()
        names, t5 = {}, []
        for s in R.load_chaos() + R.load_stock():
            if s['group'] in ('attack', 'healing') and s['vocations'] and s['id'] not in names:
                names[s['id']] = s['name']
                m = model.get(s['words'])
                t5.append('%d\t%s' % (s['id'], m['t5'] if m and s['group'] == 'attack' else 1))
        out, last = None, None
        for exe in ('luajit', 'lua5.3'):
            try:
                r = subprocess.run([exe, FORMS_LUA], cwd=SERVER, input='\n'.join(t5) + '\n', capture_output=True, text=True, timeout=300)
            except FileNotFoundError:
                continue
            if r.returncode == 0:
                out = r.stdout
                break
            last = r.stderr
        if out is None:
            raise RuntimeError('forms_numbers.lua needs luajit or lua5.3: %s' % last)
        rows = []
        for line in out.strip().split('\n'):
            i, tier, pick, kind, g1, g5, sit, util = line.split('\t')
            rows.append({'id': int(i), 'name': names.get(int(i), '?'), 'tier': int(tier), 'pick': int(pick), 'kind': kind,
                         'g1': float(g1), 'g5': float(g5), 'situation': sit, 'utility': util == '1'})
        _CACHE['forms'] = rows
    return _CACHE['forms']


def form_in_situation(r):
    """the gain of a Form in the situation it is for: pack Forms on five, solo Forms on one, the rest the better of the two"""
    return r['g5'] if r['situation'] == 'pack' else (r['g1'] if r['situation'] == 'one' else max(r['g1'], r['g5']))


def form_problems(rows=None, band=None):
    bad = []
    rows = form_rows() if rows is None else rows
    b = band or form_band_config()
    for r in rows:
        where = '%s (%d) Form %s%d %s' % (r['name'], r['id'], 'I' if r['tier'] == 1 else 'II', r['pick'], r['kind'])
        g1, g5 = r['g1'] - 1, r['g5'] - 1
        if not b['one'][0] - 1e-9 <= g1 <= b['one'][1] + 1e-9:
            bad.append('%s: %+.1f%% on one enemy, the band is %+.0f%% to %+.0f%%' % (where, g1 * 100, b['one'][0] * 100, b['one'][1] * 100))
        if not b['five'][0] - 1e-9 <= g5 <= b['five'][1] + 1e-9:
            bad.append('%s: %+.1f%% on five, the band is %+.0f%% to %+.0f%%' % (where, g5 * 100, b['five'][0] * 100, b['five'][1] * 100))
        sit = form_in_situation(r) - 1
        if sit > b['best'] + 1e-9:
            bad.append('%s: %+.1f%% in the situation it is for (%s), at most %+.0f%%' % (where, sit * 100, r['situation'], b['best'] * 100))
        if g1 < b['utilityBelow'] and g5 < b['utilityBelow'] and not r['utility']:
            bad.append('%s: %+.1f%% on one and %+.1f%% on five and no utility named (spell_forms_core.lua `utility`)' % (where, g1 * 100, g5 * 100))
    # a Form is not better than its twin on both counts (unless the twin names a utility)
    by = {}
    for r in rows:
        by.setdefault((r['id'], r['tier']), []).append(r)
    for (sid, tier), pair in sorted(by.items()):
        if len(pair) != 2:
            continue
        for a, c in ((pair[0], pair[1]), (pair[1], pair[0])):
            if a['g1'] - c['g1'] > b['twinGap'] and a['g5'] - c['g5'] > b['twinGap'] and not c['utility']:
                bad.append('%s (%d) Form %s: %s (%+.1f%% / %+.1f%%) beats its twin %s (%+.1f%% / %+.1f%%) on both counts' % (
                    a['name'], sid, 'I' if tier == 1 else 'II', a['kind'], (a['g1'] - 1) * 100, (a['g5'] - 1) * 100, c['kind'],
                    (c['g1'] - 1) * 100, (c['g5'] - 1) * 100))
    # counted power: +3% a tier
    for tier in (1, 2):
        sel = [r for r in rows if r['tier'] == tier]
        if sel:
            mean = sum((r['g1'] + r['g5']) / 2 for r in sel) / len(sel) - 1
            if abs(mean - b['counted']) > b['countedTol']:
                bad.append('Form %s counted power: the mean gain is %+.2f%%, the design counts %+.0f%% (tolerance %.1f points)' % (
                    'I' if tier == 1 else 'II', mean * 100, b['counted'] * 100, b['countedTol'] * 100))
    return bad


def form_table(rows=None):
    """markdown: per kind, the worst and the best gain on one enemy and on five over every row that has it"""
    rows = form_rows() if rows is None else rows
    kinds = {}
    for r in rows:
        kinds.setdefault((r['tier'], r['kind']), []).append(r)
    lines = ['| Form | Kind | Rows | One enemy worst / best | Five enemies worst / best | In its situation, best | Utility |',
             '|---|---|---:|---|---|---:|---|']
    for (tier, kind), rs in sorted(kinds.items(), key=lambda kv: (kv[0][0], kv[0][1])):
        lines.append('| %s | %s | %d | %+.1f%% / %+.1f%% | %+.1f%% / %+.1f%% | %+.1f%% | %s |' % (
            'I' if tier == 1 else 'II', kind, len(rs), (min(r['g1'] for r in rs) - 1) * 100, (max(r['g1'] for r in rs) - 1) * 100,
            (min(r['g5'] for r in rs) - 1) * 100, (max(r['g5'] for r in rs) - 1) * 100,
            (max(form_in_situation(r) for r in rs) - 1) * 100, 'yes' if rs[0]['utility'] else ''))
    return '\n'.join(lines)


# ---- the progression curve ---------------------------------------------------------------------------------------------------
def minutes_per_level():
    """{level: minutes a level} of progression_model.lua --curve-json (luajit, else lua5.3), levels 1 to 2250"""
    if 'minutes' not in _CACHE:
        import json
        last = None
        for exe in ('luajit', 'lua5.3'):
            try:
                r = subprocess.run([exe, PROGRESSION, '--curve-json', '2250'], cwd=SERVER, capture_output=True, text=True, timeout=300)
            except FileNotFoundError:
                continue
            if r.returncode == 0:
                last = json.loads(r.stdout)
                break
        if last is None:
            raise RuntimeError('progression_model.lua --curve-json needs luajit or lua5.3')
        _CACHE['minutes'] = {int(k): float(v) for k, v in last['levels'].items()}
    return _CACHE['minutes']


def minutes(level):
    m = minutes_per_level()
    top = max(m)
    return m[min(max(int(level), 1), top)]


def hours_in(level):
    """hunting hours from the first level a character earns SP (minLevel) up to `level` (progression_model.lua, the levels past 2250
    take the last level's pace)"""
    if ('hours', 0) not in _CACHE:
        m = minutes_per_level()
        lo = ranks_config()['minLevel']
        acc, out = 0.0, {}
        for L in range(lo, 2601):
            out[L] = acc
            acc += minutes(L) / 60.0
        _CACHE[('hours', 0)] = out
    t = _CACHE[('hours', 0)]
    return t[min(max(int(level), min(t)), max(t))]


def exp_to_next(L):
    return 50 * L * L - 150 * L + 200


def ref_xp_per_hour(L):
    """experience an hour with stage and no boosts at level L, from progression_model.lua (what refXpPerHour holds)"""
    return exp_to_next(L) * 60.0 / minutes(L)


# ---- ranks -------------------------------------------------------------------------------------------------------------------
def rank_costs():
    c = ranks_config()
    raw = [r ** c['costExp'] for r in range(1, c['maxRank'] + 1)]
    k = c['totalSp'] / sum(raw)
    return [k * v for v in raw]


def rank_of_sp(sp):
    """the fractional rank for sp SP on a spell of weight 1: whole ranks of the cost table, the rest a share of the next rank"""
    acc = 0.0
    for r, cost in enumerate(rank_costs(), 1):
        if sp < acc + cost:
            return (r - 1) + (sp - acc) / cost
        acc += cost
    return float(ranks_config()['maxRank'])


def main_rank(level):
    """the rank of a main rotation spell at a level: mainShare x the hunting hours so far"""
    b = balance_config()
    return rank_of_sp(b['mainShare'] * hours_in(level))


def _lin(points, x):
    if x <= points[0][0]:
        return points[0][1]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return points[-1][1]


def avg_rank(level):
    """the rank of the rotation's average spell"""
    a = balance_config()['avg']
    t = min(1.0, max(0.0, (level - a['fromLevel']) / float(a['toLevel'] - a['fromLevel'])))
    return main_rank(level) * (a['from'] + (a['to'] - a['from']) * t)


# ---- power -------------------------------------------------------------------------------------------------------------------
def _cd_worth(a, kind):
    """damage worth of the cooldown cut at the average rank a (a continuous cut: step per cdRanks gap, averaged over spells)"""
    c = ranks_config()
    gap = c['cdRanks'][0]
    cut = math.floor(min(a, c["maxRank"]) / gap) * c[kind]["step"] / 100.0
    return balance_config()['cooldownWorth'] * (1.0 / (1.0 - cut) - 1.0)


def rank_power(a, kind='damage', pvp=False):
    c = ranks_config()
    f = c['pvp']['rank'] if pvp else 1.0
    return (1 + f * min(a, c['maxRank']) * c[kind]['power'] / 100.0) * (1 + f * _cd_worth(a, kind))


def forms_power(a, pvp=False):
    b = balance_config()
    f = ranks_config()['pvp']['forms'] if pvp else 1.0
    return 1 + f * b['formsTotal'] * min(a, ranks_config()['maxRank']) / ranks_config()['maxRank']


def combos_power(a):
    cb = balance_config()['combos']
    t = min(1.0, max(0.0, (a - cb['fromRank']) / float(cb['toRank'] - cb['fromRank'])))
    return 1 + cb['total'] * t


def awakening_power(level):
    """a straight line between the points (spells awakened on the typical character), 0 below the first: a step would put a jump into
    every curve that reads P (the tower's clear time must climb floor by floor)"""
    aw = balance_config()['awakening']
    return 1 + aw['perSpell'] * _lin([(lv, c) for lv, c in aw['steps']], level)


def parts_at(level, parts=None):
    """{part: factor} of the typical character's spell power at a level (a part that is switched off is 1)"""
    on = parts if parts is not None else balance_config()['parts']
    a = avg_rank(level)
    return {'rank': rank_power(a) if on.get('rank') else 1.0, 'forms': forms_power(a) if on.get('forms') else 1.0,
            'combos': combos_power(a) if on.get('combos') else 1.0, 'awakening': awakening_power(level) if on.get('awakening') else 1.0}


def power(level, parts=None):
    """P, the spell power of the typical character's rotation: the product of the parts"""
    p = 1.0
    for v in parts_at(level, parts).values():
        p *= v
    return p


def h_raw(level, parts=None):
    return 1 + balance_config()['classShare'] * (power(level, parts) - 1)


def derived_health(level, parts=None):
    step = balance_config()['healthStep']
    return round(h_raw(level, parts) / step) * step


def committed_health():
    return ranks_config()['health']


def typical_gain(level):
    """the typical character's damage gain at a level: the blend of 1 and 5 targets of the median class's spell share (a hunt is both)"""
    return 1 + spell_share(None, level, 0) * (power(level) - 1)


def committed_typical():
    """spell_upgrade_balance_config.lua `typical`: {level, typical gain}, what progression_model.lua --upgrades reads (Lua cannot run this model)"""
    return balance_config()['typical']


def health(level):
    """H the games reads (ChaosSpellRanks.healthFactor): the committed curve, 1 below its first point; 1.0 while the switch is off"""
    if not active():
        return 1.0
    return health_committed(level)


def health_committed(level):
    pts = committed_health()
    if level < pts[0][0]:
        return 1.0
    return _lin(pts, level)


# ---- the class gain ----------------------------------------------------------------------------------------------------------
def _shares():
    """{class: {level: (spell share on 1 target, spell share on 5 targets)}} from class_dps_measured.csv (1 - the auto attack's share)"""
    if 'shares' not in _CACHE:
        import csv
        out = {}
        with open(MEASURED, encoding='utf-8') as f:
            for r in csv.DictReader(f):
                out.setdefault(r['class'], {})[int(r['level'])] = (1 - float(r['auto_share_1t']), 1 - float(r['auto_share_5t']))
        _CACHE['shares'] = out
    return _CACHE['shares']


def spell_share(cls, level, targets=1):
    """the class's spell share of its damage at a level: the measured levels, a straight line in between, flat outside. cls None: the median
    class. targets: 1, 5, or 0 for the blend of the two (a hunt is both)"""
    sh = _shares()
    pts = []
    for lv in LEVELS:
        if cls is None:
            a = statistics.median(sh[c][lv][0] for c in sh)
            b = statistics.median(sh[c][lv][1] for c in sh)
        else:
            a, b = sh[cls][lv]
        pts.append((lv, a if targets == 1 else b if targets == 5 else (a + b) / 2.0))
    return _lin(pts, level)


def gain(cls, level, targets=1, parts=None):
    """the factor on a class's damage at a level (the typical character): 1 + its spell share x (P - 1). 1.0 while the switch is off.
    targets 1 / 5 pick the class's share on that many targets"""
    if not active():
        return 1.0
    if _PVP['on']:
        a = avg_rank(level)
        return 1 + spell_share(cls, level, 1 if targets <= 1 else 5) * (rank_power(a, pvp=True) * forms_power(a, pvp=True) - 1)
    return 1 + spell_share(cls, level, 1 if targets <= 1 else 5) * (power(level, parts) - 1)


def median_gain(level, targets=1):
    """what the typical (median) damage of the classes grew by at a level: class_dps_model.median_dps with the upgrades over without
    (the median of the classes' own gains, which is not the gain of the median class); targets 1 or 5. 1.0 while the switch is off"""
    if not active():
        return 1.0
    import class_dps_model as CD  # a lazy import: class_dps_model reads this module
    i = 0 if targets <= 1 else 1
    with forced(False):
        today = CD.median_dps(level)[i]
    return CD.median_dps(level)[i] / today


def slack(level, targets=1):
    """how far the typical kill time is from today's at a level, as a share (H against the typical damage's gain): the room a model that
    holds a derived number to a tolerance needs in the upgrades mode, where the health curve is one number and the gain is not. 0 while off"""
    if not active():
        return 0.0
    return abs(health_committed(level) / median_gain(level, targets) - 1)


def widen(name, limit):
    """how much looser a limit of a model is in the upgrades mode (spell_upgrade_balance_config.lua `widen`, a named row with its reason);
    0.0 while the switch is off or when there is no row"""
    if not active():
        return 0.0
    return balance_config()['widen'].get(name, {}).get(limit, 0.0)


def pvp_gain(level, parts=None):
    """the factor on a player's damage against another player (design 5.2: rank and Forms at 50%, awakening and combos off), the same for
    every class (the share is the median class's blend). 1.0 while the switch is off"""
    if not active():
        return 1.0
    a = avg_rank(level)
    p = rank_power(a, pvp=True) * forms_power(a, pvp=True)
    return 1 + spell_share(None, level, 0) * (p - 1)


def heal_gain(level):
    """the factor on a heal at a level: the heal spell's rank and Forms (design 1.5: +12% power, cooldown -15%; Forms like a damage
    spell; no combos, no awakening). 1.0 while the switch is off"""
    if not active():
        return 1.0
    a = avg_rank(level)
    if _PVP['on']:
        return rank_power(a, 'heal', pvp=True) * forms_power(a, pvp=True)
    return rank_power(a, 'heal') * forms_power(a)


def kill_time_ratio(level, targets=0):
    """the typical character's time to kill against today: H over the median class's gain (targets 0: the blend)"""
    sh = spell_share(None, level, targets)
    return health_committed(level) / (1 + sh * (power(level) - 1))


# ---- the character with no upgrades (design 5.6) ----------------------------------------------------------------------------
def no_upgrades_xp(level):
    """percent less experience an hour than the typical character (monsters take H times as long)"""
    return (1 - 1 / health_committed(level)) * 100


def no_upgrades_hours(level):
    """percent more hours to reach `level` from minLevel than the typical character"""
    lo = ranks_config()['minLevel']
    base = sum(minutes(L) for L in range(lo, level))
    slow = sum(minutes(L) * health_committed(L) for L in range(lo, level))
    return (slow / base - 1) * 100


# ---- check -------------------------------------------------------------------------------------------------------------------
CHECK_LEVELS = (100, 200, 300, 400, 500, 600, 700, 800, 1000, 1300, 1600, 2000, 2200, 2500)


def problems():
    bad = []
    b = balance_config()
    lim = b['limits']
    c = ranks_config()
    # the committed curve is the derivation
    for lv, v in committed_health():
        d = h_raw(int(lv))
        if abs(v - d) > lim['healthTol']:
            bad.append('health at level %d: spell_ranks_config.lua has %.2f, the derivation %.4f (tolerance %.4f); run --derive' % (
                lv, v, d, lim['healthTol']))
        if abs(v - derived_health(int(lv))) > 1e-9:
            bad.append('health at level %d: %.2f is not the derivation rounded to %.2f (%.2f); run --derive' % (
                lv, v, b['healthStep'], derived_health(int(lv))))
    # the typical gain table progression_model.lua reads is the derivation
    pts_t = committed_typical()
    if [int(lv) for lv, _ in pts_t] != list(CHECK_LEVELS):
        bad.append('typical: the levels are %s, not %s' % ([int(lv) for lv, _ in pts_t], list(CHECK_LEVELS)))
    else:
        for lv, v in pts_t:
            d = typical_gain(int(lv))
            if abs(v - d) > 0.0015:
                bad.append('typical gain at level %d: spell_upgrade_balance_config.lua has %.3f, the derivation %.4f; run --derive' % (lv, v, d))
    # nothing is written below the first point and the curve never falls
    pts = committed_health()
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if y1 < y0:
            bad.append('health falls from level %d to %d' % (x0, x1))
    # kill times of the typical character against today
    for lv in CHECK_LEVELS:
        for targets, key, name in ((0, 'killTime', 'blend of 1 and 5 targets'), (1, 'killTimeOneTarget', 'one target'),
                                   (5, 'killTimeFiveTargets', 'five targets')):
            r = kill_time_ratio(lv, targets)
            if abs(r - 1) > lim[key] + 1e-9:
                bad.append('kill time of the typical character at level %d, %s: %+.1f%% against today (limit +-%.0f%%)' % (
                    lv, name, (r - 1) * 100, lim[key] * 100))
    # the class share H assumes against the measured one
    for lv in LEVELS:
        s = spell_share(None, lv, 0)
        if abs(s - b['classShare']) > b['shareTol']:
            bad.append('class share at level %d: median class %.2f against the constant %.2f (tolerance %.2f)' % (
                lv, s, b['classShare'], b['shareTol']))
    # rank 20 of the main spell inside the window
    first = next((L for L in range(c['minLevel'], 2600) if main_rank(L) >= c['maxRank'] - 1e-9), None)
    lo, hi = b['rank20']
    if first is None or not lo <= first <= hi:
        bad.append('the main spell reaches rank %d at level %s, the window is %d to %d' % (c['maxRank'], first, lo, hi))
    # refXpPerHour is progression_model.lua
    for lv, v in c['refXp']:
        if lv > 2200 or lv < 8:
            continue
        d = ref_xp_per_hour(int(lv))
        if abs(v / d - 1) > lim['refXpTol']:
            bad.append('refXpPerHour at level %d: %d in spell_ranks_config.lua, progression_model.lua says %d' % (lv, v, d))
    # the Form band of the design (2.1), from the real planner and forms.csv
    bad.extend(form_problems())
    # the combos (design 4.1 and 4.2, phase 6): every row 10-20%, the typical and the best rotation inside their limits
    bad.extend(combos_problems())
    # the awakening (design 3.2 and 3.3, phase 7): the Seal rates against the waystone, Greater Rift and pinnacle models, the signatures
    bad.extend(awakening_problems())
    # the no-upgrades character as the design states
    for lv, pct in b['noUpgradesXp']:
        d = no_upgrades_xp(int(lv))
        if abs(d - pct) > lim['noUpgradesXpTol']:
            bad.append('no upgrades, experience an hour at level %d: -%.1f%%, the design says -%d%%' % (lv, d, pct))
    for lv, pct in b['noUpgradesHours']:
        d = no_upgrades_hours(int(lv))
        if abs(d - pct) > lim['noUpgradesHoursTol']:
            bad.append('no upgrades, hours to level %d: +%.1f%%, the design says +%d%%' % (lv, d, pct))
    return bad


def table():
    lines = ['| Level | Hunting hours | Main rank | Avg rank | Rank | Forms | Combos | Awakening | P | H raw | H | kill time 1t / blend / 5t | class gain 1t / 5t | heal gain | PvP gain |',
             '|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---:|---:|']
    for lv in CHECK_LEVELS:
        p = parts_at(lv)
        a = avg_rank(lv)
        sh = lambda t: spell_share(None, lv, t)  # noqa: E731
        lines.append('| %d | %.1f | %.1f | %.1f | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f | %.2f | %+.1f%% / %+.1f%% / %+.1f%% | %.3f / %.3f | %.3f | %.3f |' % (
            lv, hours_in(lv), main_rank(lv), a, p['rank'], p['forms'], p['combos'], p['awakening'], power(lv), h_raw(lv),
            health_committed(lv), (kill_time_ratio(lv, 1) - 1) * 100, (kill_time_ratio(lv, 0) - 1) * 100,
            (kill_time_ratio(lv, 5) - 1) * 100, 1 + sh(1) * (power(lv) - 1), 1 + sh(5) * (power(lv) - 1),
            rank_power(a, 'heal') * forms_power(a), 1 + sh(0) * (rank_power(a, pvp=True) * forms_power(a, pvp=True) - 1)))
    return '\n'.join(lines)


def derive(parts=None):
    pts = [int(lv) for lv, _ in committed_health()]
    return ', '.join('{%d, %.2f}' % (lv, derived_health(lv, parts)) for lv in pts)


def derive_typical():
    return ', '.join('{%d, %.3f}' % (lv, typical_gain(lv)) for lv in CHECK_LEVELS)


def no_upgrades_table():
    lines = ['| Level | experience an hour | hours to the level, typical | no upgrades | more |', '|---:|---:|---:|---:|---:|']
    lo = ranks_config()['minLevel']
    for lv in (100, 500, 1000, 1500, 2000, 2200):
        base = sum(minutes(L) for L in range(lo, lv)) / 60.0
        slow = sum(minutes(L) * health_committed(L) for L in range(lo, lv)) / 60.0
        lines.append('| %d | -%.0f%% | %.0f | %.0f | +%.0f%% |' % (lv, no_upgrades_xp(lv), base, slow, (slow / base - 1) * 100))
    return '\n'.join(lines)


def main(argv):
    argv = from_argv(argv)
    parts = None
    if '--parts' in argv:
        names = argv[argv.index('--parts') + 1].split(',')
        parts = {n: n in names for n in PART_NAMES}
    if '--derive' in argv:
        print('health = {%s}' % derive(parts))
        print('typical = {%s}' % derive_typical())
        return 0
    if '--table' in argv:
        print(table())
        return 0
    if '--no-upgrades' in argv:
        print(no_upgrades_table())
        return 0
    if '--awakening' in argv:
        print(awakening_table())
        for x in awakening_problems():
            print('FAIL ' + x)
        return 1 if awakening_problems() else 0
    if '--forms' in argv:
        print(form_table())
        for x in form_problems():
            print('FAIL ' + x)
        return 1 if form_problems() else 0
    bad = problems()
    if '--check' in argv:
        for b in bad:
            print('FAIL ' + b)
        if not bad:
            print('spell upgrade check: ok (health curve = derivation, typical kill times within %.0f%% of today at %d levels, the main spell at rank 20 at level %d)' % (
                balance_config()['limits']['killTime'] * 100, len(CHECK_LEVELS),
                next(L for L in range(8, 2600) if main_rank(L) >= 20 - 1e-9)))
        return 1 if bad else 0
    print(table())
    for b in bad:
        print('FAIL ' + b)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
