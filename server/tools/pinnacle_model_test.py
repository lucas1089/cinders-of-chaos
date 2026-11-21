#!/usr/bin/env python3
"""Test of tools/pinnacle_model.py (O667): the formulas on synthetic numbers, the committed numbers pass --check, and each kind of
drift of a committed number (health, the party curve, the chance of a fragment, the damage of the boss, the level of a boss) is caught.
usage: python3 -I server/tools/pinnacle_model_test.py"""
import contextlib
import copy
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import spell_upgrade_model as _SU  # noqa: E402
_SU.set_mode(False)  # O709: the spell upgrades ship on and a model's default is the upgrades mode; this test holds the switch-off numbers (the model's --check runs both modes in CI)
import pinnacle_model as PM  # noqa: E402

os.chdir(os.path.dirname(HERE))
CHECKS = 0


def eq(a, b, msg):
    global CHECKS
    CHECKS += 1
    if a != b:
        raise SystemExit('FAIL %s: %r != %r' % (msg, a, b))


def near(a, b, tol, msg):
    global CHECKS
    CHECKS += 1
    if abs(a - b) > tol:
        raise SystemExit('FAIL %s: %r is not within %r of %r' % (msg, a, tol, b))


def check_out(nums=None, xml=None):
    """(exit code, text) of check() with the numbers replaced"""
    saved = list(PM._nums)
    saved_xml = PM.xml_text
    if nums is not None:
        PM._nums[:] = [nums]
    if xml is not None:
        PM.xml_text = xml
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            code = PM.check()
    finally:
        PM._nums[:] = saved
        PM.xml_text = saved_xml
    return code, out.getvalue()


def main():
    base = PM.numbers()
    cfg, bal = base['cfg'], base['bal']

    # the committed numbers pass
    code, text = check_out()
    eq(code, 0, 'the committed numbers pass --check: ' + text)
    ok_line = [ln for ln in text.splitlines() if ln.startswith('pinnacle check')][0]
    eq('ok' in ok_line, True, 'the summary says ok')

    # fragments: a set is three kinds in turn and the keystone along the way
    fake = {'fragments': {'sources': {s: {'chance': 25, 'anyChance': 10} for s in ('waystone', 'rift', 'omen')}}}
    fake_bal = {'minutes': {'waystone': 15, 'rift': 15, 'omen': 15}}
    hours, specific, keys = PM.set_hours(fake, fake_bal)
    near(specific, 3 * 15 / 60.0 / 0.25, 1e-9, 'three kinds, a clear every 15 minutes at 25%: 3 hours')
    near(keys, 3 * 0.1 / 0.25, 1e-9, 'the keystone rolls on every clear of the three segments')
    near(hours, specific, 1e-9, 'enough keystones along the way: no extra hours')
    fake['fragments']['sources']['rift']['anyChance'] = 0
    fake['fragments']['sources']['waystone']['anyChance'] = 1
    fake['fragments']['sources']['omen']['anyChance'] = 1
    hours2, specific2, keys2 = PM.set_hours(fake, fake_bal)
    eq(keys2 < 1, True, 'too few keystones')
    eq(hours2 > specific2, True, 'the fastest source is worked on until the keystone comes')
    near(PM.expected_kills({'unique': {'chance': 100, 'pity': 8}}), 1.0, 1e-9, 'a sure roll: one kill')
    near(PM.expected_kills({'unique': {'chance': 0.0001, 'pity': 8}}), 8.0, 0.01, 'no luck: the bad-luck count')
    near(PM.expected_kills({'unique': {'chance': 50, 'pity': 2}}), 1.5, 1e-9, 'half: 1.5')
    near(PM.keystone_per_hour(fake, fake_bal), (0 + 4 * 0.01 + 4 * 0.01) / 3, 1e-9, 'keystone an hour')

    # the fight's length
    boss = cfg['bosses'][0]
    heal = 250
    health, extra = PM.derive_health(boss, bal, heal)
    d = PM.typical(boss['refLevel'], boss)   # O699: the boss file's own resistance
    near(health, bal['seconds']['solo'] * (d * bal['uptime'] - heal), 1e-6, 'solo health')
    solo = PM.kill_seconds(dict(boss, health=health, perExtra=extra), bal, 1, heal)
    near(solo, bal['seconds']['solo'], 1e-6, 'the median class kills it in the planned time')
    party = PM.kill_seconds(dict(boss, health=health, perExtra=extra), bal, bal['players'], heal)
    near(party, bal['seconds']['party'], 1e-6, 'five of them in the planned party time')
    weak = PM.kill_seconds(dict(boss, health=health, perExtra=extra), bal, 1, heal, 0.75)
    eq(weak > solo, True, 'the weakest class needs longer')
    eq(weak < bal['limitSeconds'], True, 'and finishes in the limit')

    # marks: a group-only soak is no part of a solo fight
    profile = base['profiles']['ascended malgrath']
    solo_marks = PM.marks_share(profile, 1)
    party_marks = PM.marks_share(profile, 5)
    eq(party_marks > solo_marks, True, 'the soak adds to the marks of a party only')
    eq(PM.warn_seconds(0), 3.0, 'warning at difficulty 0')
    eq(PM.warn_seconds(1), 1.5, 'warning at difficulty 1')

    # each drift is caught
    def bumped(path, value):
        n = copy.deepcopy(base)
        t = n
        for key in path[:-1]:
            t = t[key]
        t[path[-1]] = value
        return n

    code, text = check_out(bumped(['cfg', 'bosses', 0, 'health'], int(cfg['bosses'][0]['health'] * 1.05)))
    eq(code, 1, 'a health 5% off is caught')
    eq('health' in text, True, 'and named')
    code, text = check_out(bumped(['cfg', 'bosses', 1, 'perExtra'], 0.9))
    eq(code, 1, 'a party curve off is caught')
    code, text = check_out(bumped(['cfg', 'fragments', 'sources', 'rift', 'chance'], 2))
    eq(code, 1, 'a rift fragment that almost never drops makes a set take too long')
    eq('hours' in text, True, 'in hours of top content')
    code, text = check_out(bumped(['cfg', 'fragments', 'sources', 'waystone', 'anyChance'], 100))
    eq(code, 1, 'a keystone on nearly every clear is caught')
    code, text = check_out(bumped(['cfg', 'unique', 'chance'], 100))
    eq(code, 1, 'a unique that drops on every kill is caught: a few hours of top content')
    slow = bumped(['cfg', 'unique', 'chance'], 2)
    slow['cfg']['unique']['pity'] = 60
    code, text = check_out(slow)
    eq(code, 1, 'a unique at 2% with a bad-luck count of sixty kills takes far too many hours')
    code, text = check_out(bumped(['cfg', 'bosses', 3, 'level'], 3400))
    eq(code, 1, 'the ladder 1900 / 2100 / 2300 / 2500 is asked')
    code, text = check_out(bumped(['bal', 'uptime'], 0.7))
    eq(code, 1, 'a changed uptime without the health following is caught')
    code, text = check_out(bumped(['cfg', 'bosses', 2, 'fragments'], ['a', 'b', 'c']))
    eq(code, 1, 'four fragment kinds are asked')
    code, text = check_out(bumped(['cfg', 'titles', 'deathless'], 'Deathless and Unbroken %s'))
    eq(code, 1, 'a title over 24 characters is caught')
    code, text = check_out(bumped(['cfg', 'bosses', 0, 'unique', 'name'], 'Not A Unique'))
    eq(code, 1, 'a unique that is not in the drop table is caught')

    # the boss that hits too hard or too little: the XML's attacks scaled
    def scaled_xml(factor):
        def read(boss):
            text = PM.S.read(PM.xml_path(boss))
            import re

            def swap(m):
                lo, hi = int(m.group(2)), int(m.group(3))
                return '%smin="-%d" max="-%d"' % (m.group(1), int(lo * factor), int(hi * factor))
            return re.sub(r'(<attack [^>]*?)min="-(\d+)" max="-(\d+)"', swap, text)
        return read
    code, text = check_out(xml=scaled_xml(4.0))
    eq(code, 1, 'a boss that hits four times as hard is caught')
    eq('healing' in text or 'no healing' in text, True, 'against the healing')
    code, text = check_out(xml=scaled_xml(0.05))
    eq(code, 1, 'a boss that hardly hits is caught')

    # O690: the hit cap
    on, share, tel = PM.cap_settings()
    eq((on, share, tel), (True, cfg['hitCap']['share'], cfg['hitCap']['telegraph']), 'the cap settings are the committed ones')
    near(PM.GM.uniform_retention(0, 100, 100), 1.0, 1e-9, 'a roll under the cap is left whole')
    near(PM.GM.uniform_retention(50, 100, 50), 50 / 75.0, 1e-9, 'a cap at the lowest roll: the cap over the mean')
    ret = PM.GM.uniform_retention(0, 100, 50)
    near(ret, (50 * 50 / 2.0 + 50 * 50) / 100 / 50, 1e-9, 'a cap in the middle of an even spread')
    rs = PM.rows()
    capped = {r['boss']['key']: r for r in rs}
    PM.numbers()['_nocap'] = True
    try:
        eq(PM.cap_settings(), (False, 0.0, 0.0), '--nocap switches the model off')
        before = {r['boss']['key']: r for r in PM.rows()}
    finally:
        del PM.numbers()['_nocap']
    for key, r in capped.items():
        b = before[key]
        eq(r['m1']['pressure'] < b['m1']['pressure'], True, key + ': the cap lowers the pressure alone')
        eq(r['press5'] < b['press5'], True, key + ': and with five')
        eq(r['m1']['pressure'] >= bal['limits']['pressure']['min'], True, key + ': the pressure stays inside the band with the cap')
        eq(r['press5'] <= bal['limits']['partyPressure'], True, key + ': and the party pressure under its limit')
        eq(all('ret' in x for x in r['m1']['rows']), True, key + ': every class has its retention')
        eq(all(0 < min(x['ret'].values()) <= 1.0 for x in r['m5']['rows']), True, key + ': a retention is a share')
    table = PM.hit_table()
    eq(len(table), 4, 'the hit table has the four bosses')
    for row in table:
        for players, c in row['cells'].items():
            eq(c['retMean'] >= bal['hitCap']['retention']['mean'], True, row['boss']['key'] + ': the mean damage kept')
            eq(c['retWorst'] <= c['retMean'], True, row['boss']['key'] + ': the worst class keeps no more than the mean')
        eq(row['cells'][5]['cut'] >= row['cells'][1]['cut'], True, row['boss']['key'] + ': with five more classes are cut than alone')
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        PM.print_hits(table)
    eq('hit cap (O690): on' in out.getvalue() and 'Ascended Varkhul' in out.getvalue(), True, '--hits prints the table')

    # each drift of the cap is caught
    code, text = check_out(bumped(['cfg', 'hitCap', 'enabled'], False))
    eq(code, 1, 'a cap switched off is caught')
    eq('enabled' in text, True, 'and named')
    code, text = check_out(bumped(['cfg', 'hitCap', 'share'], 0.55))
    eq(code, 1, 'a plain share under which two hits kill is caught')
    code, text = check_out(bumped(['cfg', 'hitCap', 'share'], 0.12))
    eq(code, 1, 'a plain share so low the boss is a wall is caught')
    code, text = check_out(bumped(['cfg', 'hitCap', 'telegraph'], 0.30))
    eq(code, 1, 'a marked cap under the biggest designed marked hit is caught')
    code, text = check_out(bumped(['cfg', 'hitCap', 'telegraph'], 0.95))
    eq(code, 1, 'a marked cap near the whole pool is caught')
    code, text = check_out(bumped(['cfg', 'hitCap', 'share'], 0.70))
    eq(code, 1, 'a plain share over the marked one is caught')
    code, text = check_out(bumped(['cfg', 'hitCap', 'share'], 0.38))
    eq(code, 1, 'a share that is not the reasoned one is caught')
    eq('pinnacle_balance_config.lua' in text, True, 'against the balance file')
    code, text = check_out(bumped(['cfg', 'hitCap', 'extra'], 1))
    eq(code, 1, 'a key the model does not read is caught')
    gone = copy.deepcopy(base)
    del gone['cfg']['hitCap']
    code, text = check_out(gone)
    eq(code, 1, 'no hitCap block is caught')
    code, text = check_out(bumped(['cfg', 'hitCap', 'share'], 'x'))
    eq(code, 1, 'a share that is no number is caught')
    wide = copy.deepcopy(base)
    wide['bal']['hitCap']['cuts']['atLeast'] = 22
    code, text = check_out(wide)
    eq(code, 1, 'a cap that touches nobody is caught')
    wall = copy.deepcopy(base)
    wall['bal']['hitCap']['retention']['mean'] = 0.995
    code, text = check_out(wall)
    eq(code, 1, 'a cap that takes too much of the damage is caught')
    # the boss that hits so little the cap would take the pressure under the band is caught by the band (the damage is raised, not the cap)
    code, text = check_out(xml=scaled_xml(0.7))
    eq(code, 1, 'a weaker boss is still caught under the band, with the cap')

    # O698: the mechanics' health factor of each size, from the real core, is held to the plan
    facs = base['factors']
    for key, sizes in facs.items():
        eq(sorted(sizes, key=int), ['1', '2', '3', '4', '5'], key + ': a factor row for every size')
        near(sizes['1']['final'], base['bal']['seconds']['solo'], 5, key + ': alone the factor keeps the plan')
        near(sizes['5']['final'], base['bal']['seconds']['party'], 3, key + ': with five the factor keeps the plan')
        eq(sizes['5']['hpMult'] != sizes['5']['soloMult'], True, key + ': the party factor is its own')
    near(facs['ascended vhoss']['5']['soloFinal'], 275, 2, 'the solo factor at five would kill the Vhoss in 275 s (the bug)')
    # a factor that misses the plan is caught (the solo one handed to a party)
    bad = copy.deepcopy(base)
    for key in bad['factors']:
        bad['factors'][key]['5']['final'] = bad['factors'][key]['5']['soloFinal'] * 0.9
    code, text = check_out(bad)
    eq(code, 1, 'a factor that misses the planned party time is caught')
    eq('with the factor' in text, True, 'and named')
    floor = copy.deepcopy(base)
    floor['factors']['ascended vhoss']['3']['hpMult'] = 0.6
    code, text = check_out(floor)
    eq(code, 1, 'a factor on the floor of the profile is caught')
    # the real resistance of a boss file against BOSS_RES (the option a of --options)
    kept, res = PM.real_kept(PM.S.read(PM.xml_path(base['cfg']['bosses'][0])))
    near(res, 0.0833, 0.001, 'Malgrath resists 8.3% on the six elements (fire -10, energy -15, earth 20, ice 35, holy -20, death 40)')
    near(kept, 0.7083, 0.001, 'the kept share of the boss files (BOSS_RES 0.30 keeps 0.600)')
    # the options: the bots kill faster than the median five today, option b brings them to the plan, option a keeps the median at the plan
    opts = PM.bot_scale(base['bal'], PM.rows())
    for o in opts:
        today, a, b, c = [t for _, t in o['options']]
        near(today['median5'], 300, 3, o['boss']['name'] + ': today the median five kill in 300 s')
        near(a['median5'], 300, 3, o['boss']['name'] + ': option a keeps the median five at the plan')
        near(b['bots5'], 300, 1, o['boss']['name'] + ': option b brings the bot five to the plan')
        near(c['bots5'], 150, 1, o['boss']['name'] + ': option c brings the bot five to half of it')
        eq(abs(today['bots5'] - a['bots5']) < 1e-6 and a['bots5'] < c['bots5'] < b['bots5'], True, o['boss']['name'] + ': option a is the committed state (O699), the others rise in health')
    near(opts[0]['options'][0][1]['bots5'], 77, 1, 'Malgrath today: the measured 79 s x the better factor')

    print('pinnacle_model_test: %d checks ok' % CHECKS)
    return 0


if __name__ == '__main__':
    sys.exit(main())
