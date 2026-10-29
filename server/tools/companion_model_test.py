"""Tests for companion_model.py (O306, O332): the Python formulas against the server's Lua functions, the shipped config inside
its limits, the before / after of the two fixes, and the wolves as the main damage of an invested Beastmaster.

Run: python3 -I server/tools/companion_model_test.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import companion_model as M
import pack_model as P
import rotation_sim as R

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


levels = (1, 50, 100, 399, 400, 1000)
data = M.dump(levels)
c, bal = M.conf()
ok(len(data['rows']) == len(levels), 'dumper: one row per level')
for r in data['rows']:
    lv, sk = r['level'], r['skill']
    ok(r['health'] == M.health(c, lv), 'health formula = classes.lua at %d' % lv)
    ok(r['cap'] == M.cap(c, lv), 'cap = classes.lua at %d' % lv)
    avg = M.bite(c, lv, sk)
    ok(abs((r['autoMin'] + r['autoMax']) / 2 - avg) <= 1.0, 'auto bite = classes.lua at %d' % lv)
    ok(r['shown'] == lv, 'shown level is the owner level at %d' % lv)
    spell = lv * c['biteLevel'] + sk * c['biteSkill']
    ok(abs((r['mulMin'] + r['mulMax']) / 2 - spell) <= 1.0, 'spell bite = classes.lua at %d' % lv)
    ok(abs((r['wolfMin'] + r['wolfMax']) / 2 - 1.5 * spell) <= 1.5, 'the wolf factor multiplies the bite at %d' % lv)
    ok(r['autoMax'] > r['mulMax'] or lv < 5, 'the own bite is above the spells bite at %d' % lv)
    ok(r['taken'] == round(1000 * c['taken']), 'taken share at %d' % lv)
    ok(r['takenAlpha'] < r['taken'], 'Pack Alpha cuts more at %d' % lv)
ok(M.cap(c, 399) == 1 and M.cap(c, 400) == 2, 'two companions from level 400')
ok(R.WOLF_LEVEL == c['caps'][-1]['level'], 'the rotation model counts the second companion from the same level (WOLF_LEVEL)')
ok(R.wolf_bite() == (c['biteLevel'], c['biteSkill']), 'the rotation model has the spells\' bite')
sim = R.stats(M.CLASS, 750)
ok(abs(sim['BITE'] - (750 * c['biteLevel'] + sim['SK'] * c['biteSkill'])) < 1e-9, 'BITE of the rotation model')
ok(R.stats(M.CLASS, 399)['PETS'] == 1 and R.stats(M.CLASS, 400)['PETS'] == 2 and R.stats(M.CLASS, 400)['WOLF'] == 1.0, 'PETS and WOLF')
_spells, _model = R.load_all()
ok(400 in R.breakpoints(_spells, _model, M.CLASS), 'the best set is searched again at the second companion')

# the shipped config passes its own limits, at the report levels too
ok(M.check() == [], 'check: the shipped config is inside its limits')

# O306: the fix matters (tester report: dead in under 5 s at level 400, 4% of the damage)
for lv in (100, 400, 1000):
    old, new = M.alive_seconds(lv, True), M.alive_seconds(lv)
    ok(old < 8, 'legacy: the companion lived %.1f s at %d' % (old, lv))
    ok(new >= bal['limits']['aliveSecondsMin'] and new > 2 * old, 'fix: lives %.1f s at %d' % (new, lv))
    ok(M.companion_dps(lv, True) / P.damage(M.CLASS, lv, tune=False)[0] < 0.09, 'legacy: the bites were under 9%% at %d' % lv)
ok(M.hits_survived(400, True) < 8 <= M.hits_survived(400), 'hits survived at 400')

# more attackers, less time; a damage cut of Pack Alpha is outside the model (it only helps)
ok(M.alive_seconds(400, attackers=4) < M.alive_seconds(400) / 1.9, 'four attackers halve the time')

# ---- O332: the wolves are the main damage of an invested Beastmaster ---------------------------------------------------
ok(M.trials_minion() == 65, "the Trials' minion damage of the Beastmaster: Alpha Bond 25 + Apex Predator 40 (trials_nodes.lua)")
pa = 1 + data['packAlpha']['bonus']
ok(abs(M.wolf_factor('tree') - pa) < 1e-9 and M.wolf_factor('plain') == 1.0, 'the wolf factor of the plain and the tree build')
ok(abs(M.wolf_factor('full') - pa * 1.65) < 1e-9, 'the wolf factor of the full build = Pack Alpha x the Trials')
for lv in (400, 750, 1000):
    ts = {b: M.totals(lv, b) for b in M.BUILDS}
    lo, hi = bal['limits']['shareFull']
    ok(lo <= ts['full']['share'] <= hi, 'full build: the wolves are %.0f%% at %d (%.0f-%.0f%%)' % (100 * ts['full']['share'], lv, 100 * lo, 100 * hi))
    ok(ts['plain']['share'] < ts['tree']['share'] < ts['full']['share'], 'more investment, more wolves at %d' % lv)
    ok(ts['plain']['share'] <= bal['limits']['sharePlain'][1], 'a plain Beastmaster stays a bow class at %d: wolves %.0f%%' % (lv, 100 * ts['plain']['share']))
    ok(ts['plain']['total1'] >= 0.75 * ts['tree']['total1'], 'a plain Beastmaster is not far behind at %d' % lv)
    ok(ts['tree']['total1'] < ts['full']['total1'] <= bal['limits']['fullOverTree'][1] * ts['tree']['total1'], 'a full build is ahead, not by far, at %d' % lv)
    ok(ts['full']['wolf1'] + ts['full']['bites'] > ts['full']['spell1'] - ts['full']['wolf1'], 'the wolves out-damage the rest at %d' % lv)
    ok('Pack Howl' in ts['full']['set'], 'Auto setup casts Pack Howl at %d: %s' % (lv, ts['full']['set']))
ok(len(M.totals(750, 'full')['set']) == 5, 'the preset at 750 has 5 spells')
# the Trials' minion damage reaches every wolf hit: without it the full build is the tree build (the bug of O332)
ok(M.totals(750, 'full')['bites'] > 1.6 * M.totals(750, 'tree')['bites'], 'the Trials raise the bites')
ok(M.totals(750, 'full')['wolf1'] > 1.6 * M.totals(750, 'tree')['wolf1'], 'the Trials raise the wolf spells')

# before O332: the main wolf skill of a tester build was a small share (Pack Frenzy at the old numbers: 17% of the model's
# damage, 10-12% in the tester's report); the share of the wolves is what the model gives now
ok(M.totals(750, 'full')['topshare'] < 0.30, 'the main wolf spell is a share of the damage, the wolves together the main part')

# the pack model: the Beastmaster's total is the model's tree build; other classes untouched; tune off untouched
raw = P._damage('Beastmaster', 400, True, False)
ok(P.damage('Beastmaster', 400, True, False) == raw, 'tune off: the measured numbers')
ok(P.damage('Warrior', 400) == P._damage('Warrior', 400), 'other classes: untouched')
d1, d5 = P.damage('Beastmaster', 400)
t = M.totals(400, 'tree')
ok(abs(d1 - t['total1']) < 1e-6 and abs(d5 - t['total5']) < 1e-6, 'pack model: Beastmaster = the model\'s tree build')
ok(abs(t['total5c'] / t['head5c'] - 1) < 0.08, 'level 400: a pack of 5 is where it was')
# a pure area class: the lead of the Elementalist on a pack holds (pack_model.py --check has the same rule at 300 800 1000 1200)
cfg = P.pace()
for lv in (800, 1000, 1200):
    area = P.damage(M.CLASS, lv)[1] * M.cleave(lv)
    e = P.damage('Elementalist', lv)[1]
    ok(area * 1.08 <= e * 1.0001, 'level %d: the Beastmaster is not the top pack class (%.0f x 1.08 against the Elementalist\'s %.0f)' % (lv, area, e))
    ok(P.damage(M.CLASS, lv)[0] < P.damage('Deadeye', lv)[0], 'level %d: the Deadeye leads on one target' % lv)

# a retuned config fails the check: bites back to the old ones, or wolves with no investment
saved = dict(c)
c['autoLevel'], c['autoSkill'] = 5.0, 9.0
M._best.clear()
try:
    ok(M.check() != [], 'check: huge bites fail the share limits')
finally:
    c.update(saved)
    M._best.clear()
ok(M.check() == [], 'check: back to the shipped numbers')

if fails:
    print('companion_model_test: %d failed' % fails)
    sys.exit(1)
print('companion_model_test: ok')
