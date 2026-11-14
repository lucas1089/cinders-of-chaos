"""mainquest_boss_model.py on the committed configs and on bent ones (python3 -I server/tools/mainquest_boss_model_test.py)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mainquest_boss_model as M  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


check(M.problems() == [], 'the committed numbers pass: %s' % M.problems())
real = M.tier


def bent(**kw):
    def f():
        t = real()
        t.update(kw)
        return t
    return f


M.tier = bent(share=real()['share'] * 1.5)
check(any('median class needs' in p for p in M.problems()), 'a boss with 50% more health is caught')
M.tier = bent(share=real()['share'] * 0.5)
check(any('median class needs' in p for p in M.problems()), 'a boss with half the health is caught')
M.tier = bent(hit=0.2)
check(any('Cruel Trial' in p for p in M.problems()), 'a hit above the Cruel Trial share is caught')
M.tier = bent(lives=1)
check(any('3 lives' in p for p in M.problems()), 'one life is caught')
M.tier = bent(time=200)
check(any('3 lives and 300-420' in p or 'of the 200 s limit' in p for p in M.problems()), 'a short clock is caught')
M.tier = real
t = real()
# O554: Vael's attacks
import copy  # noqa: E402
real_attacks = M.attacks
c0 = real_attacks()
check(len(c0['attacks']) in range(4, 7), 'four to six attacks')


def bent_attacks(fn):
    def f():
        c = copy.deepcopy(c0)
        fn(c)
        return c
    return f


def has(word):
    return any(word in p for p in M.problems())


M.attacks = bent_attacks(lambda c: c['attacks'][0].update(windMs=1200))
check(has('winds up 1200'), 'a windup under 1.8 s is caught')
M.attacks = bent_attacks(lambda c: c.update(minWindMs=1000))
check(has('minWindMs'), 'a lowered minimum windup is caught')
M.attacks = bent_attacks(lambda c: c['attacks'][1].update(windMs=5000))
check(has('over 3.5 s'), 'a windup so long it is no threat is caught')
M.attacks = bent_attacks(lambda c: c['attacks'][3]['parts'][0].update(share=0.4))
check(has('the tier allows'), 'a hit over the tier\'s zone share is caught')
M.attacks = bent_attacks(lambda c: c['attacks'].append(copy.deepcopy(c['attacks'][0])))
check(has('(4 to 6)'), 'seven attacks are caught')
M.attacks = bent_attacks(lambda c: c.update(attacks=c['attacks'][:3]))
check(has('(4 to 6)') and has('has none'), 'three attacks, and a phase without one, are caught')
M.attacks = bent_attacks(lambda c: c.update(every=[3000, 3000, 3000, 3000]))
check(has('adds') and has('typical dodge'), 'attacks that come too often are caught by the load')
M.attacks = bent_attacks(lambda c: c['dodge'].update(typical=0.2, poor=0.1))
check(has('typical dodge'), 'a low dodge assumption fails the load check')
M.attacks = bent_attacks(lambda c: c['dodge'].update(typical=0.4, poor=0.6))
check(has('0 < poor < typical < 1'), 'poor above typical is caught')
M.attacks = bent_attacks(lambda c: [a.update(parts=a['parts'][:1]) for a in c['attacks']])
check(has('two different shapes'), 'no mixed shape in the last phase is caught')
M.attacks = bent_attacks(lambda c: c.update(enabled=False))
check(has('switch is off'), 'the switch off is caught')
M.attacks = real_attacks
check(M.problems() == [], 'back to the committed attacks: %s' % M.problems())
c = real_attacks()
check(abs(M.period_s(c, 1, c['attacks'][0], False) - 9.0) < 1e-9, 'the cadence of phase 1 is 9 s')
check(M.period_s(c, 4, c['attacks'][-1], True) >= (c['attacks'][-1]['windMs'] + c['gapMs']) / 1000.0, 'enraged never shorter than windup + gap')
check(abs(M.hit_share(c['attacks'][-1]) - 0.19) < 1e-9, 'the Final Oath is two shares: 0.10 + 0.09')
check(M.phase_load(c, 1, 1.0, False) == 0.0, 'a full dodge takes nothing')
check(M.phase_load(c, 1, 0.5, False) > M.phase_load(c, 1, 0.75, False), 'a poor dodge takes more')
check(M.health(t, 500) > 250000 and M.health(t, 500) < 320000, 'about 282,000 health at 500')
check(M.health(t, 400) == M.health(t, 500), 'the level is clamped to the window')
check(M.health(t, 900) == M.health(t, 700), 'and its top')
if fails:
    sys.exit(1)
print('mainquest_boss_model_test: ok')
