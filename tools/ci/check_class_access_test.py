#!/usr/bin/env python3
"""check_class_access.py on the real data (clean) and on spoiled copies (each one is reported). python3 -I tools/ci/check_class_access_test.py"""
import copy
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_class_access as C  # noqa: E402
from patch_spell_cap import CAP  # noqa: E402


def load():
    chaos, stock = C.load_chaos(), C.load_stock()
    client, capped = C.load_client()
    return chaos, stock, client, capped, C.load_rotation()


def run(chaos, stock, client, capped, rotation):
    return C.problems(chaos, stock, client, capped, CAP, rotation)


def has(bad, text):
    return any(text in b for b in bad)


def main():
    chaos, stock, client, capped, rotation = load()
    assert len(rotation) == 21, len(rotation)
    assert len(chaos) > 100 and len(client) == len(chaos), (len(chaos), len(client))
    bad = run(chaos, stock, client, capped, rotation)
    assert bad == [], bad

    by_name = {s['name']: sid for sid, s in chaos.items()}
    hail = by_name['Hail of Dawn']

    # the server gives the Beastmaster a spell the client copy lacks
    c2 = copy.deepcopy(chaos)
    c2[hail]['vocations'].append('Beastmaster')
    bad = run(c2, stock, client, capped, rotation)
    assert has(bad, 'Hail of Dawn') and has(bad, 'client lists classes'), bad

    # the client copy gives the Beastmaster a spell the server refuses
    cl2 = copy.deepcopy(client)
    cl2[hail]['vocations'].add(15)
    bad = run(chaos, stock, cl2, capped, rotation)
    assert has(bad, 'Hail of Dawn') and has(bad, 'client lists classes'), bad

    # a level that differs, a spell only one side has
    cl3 = copy.deepcopy(client)
    cl3[hail]['level'] = 250
    assert has(run(chaos, stock, cl3, capped, rotation), 'level'), 'level'
    cl4 = copy.deepcopy(client)
    del cl4[hail]
    assert has(run(chaos, stock, cl4, capped, rotation), 'not in spelldata.lua'), 'missing in client'

    # an unknown class name and a spell with no class
    c3 = copy.deepcopy(chaos)
    c3[hail]['vocations'].append('Beastmasters')
    assert has(run(c3, stock, client, capped, rotation), 'unknown class'), 'unknown class'
    c4 = copy.deepcopy(chaos)
    c4[hail]['vocations'] = []
    assert has(run(c4, stock, client, capped, rotation), 'has no class'), 'no class'

    # Auto setup holds a spell its class cannot cast (a Beastmaster with Final Verdict)
    fv = by_name['Final Verdict']
    r2 = copy.deepcopy(rotation)
    r2['Beastmaster'].add(fv)
    bad = run(chaos, stock, client, capped, r2)
    assert has(bad, 'Beastmaster: Auto setup holds Final Verdict'), bad

    # the installed snapshot lists a capped spell for a class the cap dropped
    s2 = copy.deepcopy(stock)
    sid = next(i for i, (_, name, keep) in ((v[0], v) for v in CAP.values()) if i in s2 and keep)
    s2[sid]['vocations'] = s2[sid]['vocations'] + ['Samurai']
    assert has(run(chaos, s2, client, capped, rotation), 'cap:'), 'cap parity'

    # a class with no healing spell
    c5 = copy.deepcopy(chaos)
    s3 = copy.deepcopy(stock)
    for table in (c5, s3):
        for s in table.values():
            if s['group'] == 'healing' and 'Sentinel' in s['vocations']:
                s['vocations'] = [v for v in s['vocations'] if v != 'Sentinel']
    assert has(run(c5, s3, client, capped, rotation), 'Sentinel has no healing spell'), 'healing'
    print('check_class_access_test: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
