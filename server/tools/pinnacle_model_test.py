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
    d = PM.typical(boss['refLevel'])
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

    print('pinnacle_model_test: %d checks ok' % CHECKS)
    return 0


if __name__ == '__main__':
    sys.exit(main())
