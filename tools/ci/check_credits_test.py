#!/usr/bin/env python3
"""python3 -I tools/ci/check_credits_test.py: check_credits.py on small texts (packs of the sources files named or
not, the pack / source column, pt-BR headings) and on the repository (passes)."""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_credits as C  # noqa: E402

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        print('FAIL', what)
        fails += 1


CREDITS = '''intro

<!-- credits:begin -->

## Art packs {pt-BR: Pacotes de arte}

- **Alpha Pack**
  - Author: Someone
- **Beta Pack**

## Fonts {pt-BR: Fontes}

- **Cinzel**

## Same {pt-BR: Same}

- **Gamma**

<!-- credits:end -->

## Internal

- **donor Q library**, **other set**: tracing only.
'''
PT = '''ChaosLocaleStrings['pt-BR'] = {
  ["Art packs"] = "Pacotes de arte",
  ["Fonts"] = "Fontes",
}
'''

ok(C.credited_names(CREDITS) == {'alpha pack', 'beta pack', 'cinzel', 'gamma', 'donor q library', 'other set'},
   'names: %r' % C.credited_names(CREDITS))
ok(C.csv_packs('a,pack,source\n1,Alpha Pack,x\n2,Alpha Pack,y\n3,,z\n') == ['Alpha Pack'], 'pack column wins, distinct, empty skipped')
ok(C.csv_packs('a,Source\n1,donor Q library (old)\n') == ['donor Q library (old)'], 'source column')
ok(C.csv_packs('a,b\n1,2\n') == [], 'neither column')

ok(C.problems(CREDITS, {}, PT) == [], 'clean: %r' % C.problems(CREDITS, {}, PT))
good = {'x/pack27_sources.csv': 'id,pack\n1,ALPHA PACK\n2,Beta Pack v2\n',
        'y/sources.csv': 'look,source\n1,donor Q library (10.98)\n2,live look 5 (other set)\n'}
ok(C.problems(CREDITS, good, PT) == [], 'every pack named (case, longer values)')
bad = C.problems(CREDITS, {'z/pack27_sources.csv': 'id,pack\n1,Delta Pack\n2,Alpha Pack\n'}, PT)
ok(len(bad) == 1 and 'Delta Pack' in bad[0] and 'z/pack27_sources.csv' in bad[0], 'an unnamed pack: %r' % bad)

missing = C.problems(CREDITS, {}, PT.replace('  ["Fonts"] = "Fontes",\n', ''))
ok(len(missing) == 1 and 'Fonts' in missing[0], 'a heading without pt-BR: %r' % missing)
wrong = C.problems(CREDITS, {}, PT.replace('"Fontes"', '"Letras"'))
ok(len(wrong) == 1 and 'Fonts' in wrong[0], 'a different pt-BR heading: %r' % wrong)
broken = C.problems(CREDITS.replace('{pt-BR: Fontes}', ''), {}, PT)
ok(len(broken) == 1 and 'docs/CREDITS.md' in broken[0], 'a malformed CREDITS.md: %r' % broken)

# the repository passes
r = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'check_credits.py')], capture_output=True, text=True)
ok(r.returncode == 0, 'repository check: ' + r.stdout + r.stderr)

print('check_credits_test:', 'OK' if not fails else f'{fails} failure(s)')
sys.exit(1 if fails else 0)
