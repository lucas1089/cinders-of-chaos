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
check(M.health(t, 500) > 250000 and M.health(t, 500) < 320000, 'about 282,000 health at 500')
check(M.health(t, 400) == M.health(t, 500), 'the level is clamped to the window')
check(M.health(t, 900) == M.health(t, 700), 'and its top')
if fails:
    sys.exit(1)
print('mainquest_boss_model_test: ok')
