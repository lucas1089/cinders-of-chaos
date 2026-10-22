#!/usr/bin/env python3
"""Tests of patch_tester_filters.py (tester bots out of the base highscores, top 3 statues and !online).

  python3 -I server/tools/patch_tester_filters_test.py
Synthetic copies of the base lines (the base server is not in the repository).
"""
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_tester_filters as P  # noqa: E402

FAILS = []


def check(cond, what):
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


HIGHSCORES = ('  local countQ = db.storeQuery(\n'
              '    ("SELECT COUNT(*) AS total FROM `players` WHERE `vocation` IN (%s)")\n'
              '    :format(vocFilter)\n'
              '  )\n'
              '  local sql = ([[\n'
              '    SELECT p.`name`\n'
              '    FROM `players` p\n'
              '    WHERE p.`vocation` IN (%s)\n'
              '    ORDER BY %s DESC\n'
              '    LIMIT %d,%d\n'
              '  ]]):format(col, vocFilter, col, offset, perPage)\n')
TOP = ('        local query = string.format("SELECT `name`, `level` FROM `players` ORDER BY `level` DESC, '
       '`experience` DESC LIMIT %d", amount)\n')
ONLINE = ('\tfor _, targetPlayer in ipairs(players) do\n'
          '\t\tif player:canSeeCreature(targetPlayer) then\n'
          '\t\t\ttable.insert(onlineList, targetPlayer:getName())\n'
          '\t\tend\n'
          '\tend\n')


def main():
    const = open(os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'chaos_constants.lua'), encoding='utf-8').read()
    m = re.search(r'Chaos\.storage\.tester = (\d+)', const)
    check(m and int(m.group(1)) == P.KEY, 'the key is Chaos.storage.tester')

    new, st = P.patch(HIGHSCORES, P.EDITS[0][1])
    check(st == 'patched', 'highscores patched')
    check(new.count('`ts`.`key` = 7102900 AND `ts`.`value` = 1') == 2, 'highscores: the count and the page')
    check('`ts`.`player_id` = `players`.`id`' in new and '`ts`.`player_id` = p.`id`' in new, 'aliases')
    check('-- Chaos' not in new.split('[[')[1], 'no Lua comment inside the SQL string')
    again, st2 = P.patch(new, P.EDITS[0][1])
    check(st2 == 'already' and again == new, 'highscores: idempotent')

    new, st = P.patch(TOP, P.EDITS[1][1])
    check(st == 'patched' and 'FROM `players` WHERE NOT EXISTS' in new, 'top 3 statues')
    check(new.rstrip('\n').endswith(P.MARK), 'the marker ends the line')

    new, st = P.patch(ONLINE.replace('\n', '\r\n'), P.EDITS[3][1])
    check(st == 'patched' and '\r\n' in new and '\n' not in new.replace('\r\n', ''), '!online, CRLF kept')
    check('Chaos.isTester(targetPlayer)' in new, '!online leaves testers out')

    _, st = P.patch('nothing to see', P.EDITS[1][1])
    check(st.startswith('expected text found 0 times'), 'a changed base is reported')

    tmp = tempfile.mkdtemp()
    try:
        for rel, text in ((P.EDITS[0][0], HIGHSCORES), (P.EDITS[1][0], TOP), (P.EDITS[3][0], ONLINE)):
            os.makedirs(os.path.dirname(os.path.join(tmp, rel)), exist_ok=True)
            with open(os.path.join(tmp, rel), 'w', newline='') as f:
                f.write(text)
        check(P.main([tmp, '--dry-run']) == 0, 'dry run')
        check(P.MARK not in open(os.path.join(tmp, P.EDITS[0][0])).read(), 'dry run writes nothing')
        check(P.main([tmp]) == 0, 'run (one statue file missing is skipped)')
        check(P.MARK in open(os.path.join(tmp, P.EDITS[3][0])).read(), 'written')
        check(P.main([tmp]) == 0, 'second run')
        with open(os.path.join(tmp, P.EDITS[2][0]), 'w') as f:
            f.write('changed base\n')
        check(P.main([tmp]) == 1, 'a known file that cannot be patched fails the step')
    finally:
        shutil.rmtree(tmp)

    print('patch_tester_filters_test: %d failure(s)' % len(FAILS))
    return 1 if FAILS else 0


if __name__ == '__main__':
    sys.exit(main())
