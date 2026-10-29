"""Test of rift_looks.py (O309): python3 -I tools/ci/rift_looks_test.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rift_looks as R

SAMPLE = '''return { looks = {
  enabled = true,
  families = {
    ["A"] = {minion = 2100, brute = 2101, elite = 2102, guardian = 2103},
    ["B"] = {minion = 2104, brute = 2105, elite = 2106, guardian = 2107}
  },
  UNDRAWN
  variants = { ["A"] = { minion = {{look = 2202, name = "Bloodeel"}}, elite = {{look = 2203, name = "Rune"}} } },
  bigGuardiansOn = BIG,
  bigGuardians = {[2103] = 2208, [2107] = 2209}
} }'''
BLANK = {2101, 2102, 2105, 2106, 2208, 2209}
fails = 0
def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)

def run(undrawn='', big='false'):
    return R.problems(SAMPLE.replace('UNDRAWN', undrawn).replace('BIG', big), BLANK, 2300)

p = run()
check(len(p) == 4 and all('invisible' in m for m in p), f'blank family looks fail: {p}')
p = run('undrawn = {[2101] = 2200, [2102] = 2203, [2105] = 2104, [2106] = 2204},')
check(p == [], f'replacements fix it: {p}')
p = run('undrawn = {[2101] = 2200, [2102] = 2203, [2105] = 2104, [2106] = 2102},')
check(any('replacement' in m for m in p) and any('blank' in m for m in p), f'a blank replacement fails: {p}')
ok = 'undrawn = {[2101] = 2200, [2102] = 2203, [2105] = 2104, [2106] = 2204},'
check(run(ok, 'true') != [] and len(run(ok, 'true')) == 2, 'big guardians count when on')
check(R.problems('return {}', BLANK, 2300) != [], 'no looks block is reported')
check(R.problems(SAMPLE.replace('UNDRAWN', ok).replace('BIG', 'false').replace('2203, name', '9999, name'), BLANK, 2300)[0]
      .endswith('outfits of the pair'), 'a look above the pair fails')
# the real file passes
here = os.path.dirname(os.path.abspath(__file__))
real = open(os.path.join(here, '..', '..', 'server', 'data', 'scripts', 'chaos', 'rift_config.lua'), encoding='utf-8').read()
out, undrawn, on = R.looks(real)
check(len(out) >= 16 + 8 and len(undrawn) == 8 and on is False, f'real config parsed: {len(out)} looks, {len(undrawn)} undrawn, big {on}')
print('rift_looks_test:', 'OK' if not fails else f'{fails} failed')
sys.exit(1 if fails else 0)
