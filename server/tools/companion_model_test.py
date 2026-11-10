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

# the pack model: in the C4 frame (O444: companion_model.py rebuilds the Beastmaster in it; the boss, pack and tower models read
# class_dps_model.py, whose Beastmaster number holds the wolves) the Beastmaster's total is the model's tree build; other classes
# untouched; tune off untouched
raw = P._damage('Beastmaster', 400, True, False)
ok(P.damage('Beastmaster', 400, True, False) == raw, 'tune off: the measured numbers')
ok(P.damage('Warrior', 400, frame='c4') == P._damage('Warrior', 400), 'other classes: untouched')
ok(P.damage('Beastmaster', 400) != P.damage('Beastmaster', 400, frame='c4'), 'O444: the live frame is class_dps_model.py, the C4 frame is the one rebuilt here')
d1, d5 = P.damage('Beastmaster', 400, frame='c4')
t = M.totals(400, 'tree')
ok(abs(d1 - t['total1']) < 1e-6 and abs(d5 - t['total5']) < 1e-6, 'pack model: Beastmaster = the model\'s tree build')
ok(abs(t['total5c'] / t['head5c'] - 1) < 0.70, 'level 400: a pack of 5 moved by the O430 balance only (cut by class_dps_model.py, within 70%)')
# O444: the leader rules (the Elementalist 8% ahead on a pack, the Deadeye ahead on one target) were retired by O430 and are gone from
# pack_model.py and boss_model.py; class_dps_model.py holds every class to the level median. The Beastmaster rebuilt here still
# stays under the top of the C4 frame's pack classes and the Deadeye, as a sanity bound on the rebuild
cfg = P.pace()
for lv in (800, 1000, 1200):
    area = P.damage(M.CLASS, lv, frame='c4')[1] * M.cleave(lv)
    e = P.damage('Elementalist', lv, frame='c4')[1]
    e = e * M.growth(lv)   # O472: the other classes grow by W as well (the model of them is not re-fitted yet)
    ok(area <= e * 1.5, 'level %d: the rebuilt Beastmaster is not far above the Elementalist on a pack (%.0f against %.0f)' % (lv, area, e))
    ok(P.damage(M.CLASS, lv, frame='c4')[0] < P.damage('Deadeye', lv, frame='c4')[0] * M.growth(lv), 'level %d: the Deadeye is above the rebuilt Beastmaster on one target' % lv)

# O468: the bite is the owner's ORIGIN_SPELL (classDamage and the armour of the median normal monster apply), and autoByLevel was
# re-fitted so the PLAIN build's bite dps is the one before O468 (autoByLevel 1 / 0.88 / 0.56 / 0.5, no event factors): within 2%
OLD_AUTO = [(60, 1.0), (100, 0.88), (500, 0.56), (1000, 0.5)]
for lv in (100, 400, 750, 1000):
    sk = R.stats(M.CLASS, lv)['SK']
    old_bite = (lv * c['autoLevel'] + sk * c['autoSkill']) * R.interp(OLD_AUTO, lv)
    new_dps = M.companion_dps(lv)
    ref = M.cap(c, lv) * old_bite / (c['biteMs'] / 1000.0) * M.conf()[1]['contact'] * M.uptime(lv)
    # O475 (2026-11-10): was 2%. The armour of the median normal monster follows the regenerated hit curve (monster_defence_config.lua:
    # 464 at 100, 9,993 at 1000; was 576 and 7,169), so the same bite meets more armour at 100 and less at 1000: -16% to +8% here (the model's number)
    ok(abs(new_dps / ref - 1) < 0.20, 'level %d: the plain bite dps is the one before O468 within the armour move of the round (%.1f against %.1f)' % (lv, new_dps, ref))
    ok(M.event_factor(lv, 1000) < 1.0, 'level %d: the events cut a bite (classDamage x armour)' % lv)
    ok(M.companion_dps(lv, factor=1.5) / new_dps > 1.5, 'level %d: a wolf factor raises the bite more than its own size (armour keeps more of a big hit)' % lv)

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
