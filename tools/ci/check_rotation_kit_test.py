#!/usr/bin/env python3
"""Tests of check_rotation_kit.py: the real data passes, and a kit spell the rotation data lacks is caught (O157).
usage: python3 -I tools/ci/check_rotation_kit_test.py"""
import copy
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_rotation_kit as C  # noqa: E402


def main():
    kit = C.load_kit()
    spells, classes = C.load_data()
    model_spells, model = C.R.load_all()
    assert len(kit) == 58, len(kit)
    assert C.problems(kit, spells, classes, model_spells, model) == []
    names = {k['name']: k['id'] for k in kit}
    # the Thief case: the five spells are known, with the area rule of their shape
    for n, area in (('Gutting Slash', False), ('Razor Rain', True), ('Venom Spiral', False), ('Crescent Cut', True),
                    ('Last Breath', False)):
        assert spells[names[n]]['area'] is area, n
        assert names[n] in classes['Thief']['spells'] | classes['Ninja']['spells'], n

    def bad(sp, cl):
        return C.problems(kit, sp, cl, model_spells, model)

    # a kit spell missing from the table
    s2 = copy.deepcopy(spells)
    del s2[names['Gutting Slash']]
    assert any('Gutting Slash' in b for b in bad(s2, classes))
    # a wrong area rule
    s3 = copy.deepcopy(spells)
    s3[names['Razor Rain']]['area'] = False
    assert any('Razor Rain' in b and 'hits a pack' in b for b in bad(s3, classes))
    s3[names['Razor Rain']]['area'] = True
    s3[names['Last Breath']]['area'] = True
    assert any('Last Breath' in b and 'one target' in b for b in bad(s3, classes))
    # a spell no preset of the class holds
    c2 = copy.deepcopy(classes)
    c2['Thief']['spells'].discard(names['Last Breath'])
    assert any('Last Breath' in b and 'Thief' in b for b in bad(spells, c2))
    # O307: client vocations against the server's
    server, client = C.load_server_vocations(), C.load_client_vocations()
    assert len(client) > 100 and C.client_problems(server, client, classes) == []
    fv = [i for i, v in client.items() if v == server[i] and 7 in v and 15 not in v][0]
    c3 = copy.deepcopy(client)
    c3[fv].add(15)
    assert any('spell %d' % fv in b for b in C.client_problems(server, c3, classes))
    c4 = copy.deepcopy(classes)
    c4['Beastmaster']['spells'].add(fv)
    assert any('Beastmaster' in b and 'does not let' in b for b in C.client_problems(server, client, c4))
    print('check_rotation_kit_test: OK')


if __name__ == '__main__':
    main()
