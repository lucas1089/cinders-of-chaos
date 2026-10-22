#!/usr/bin/env python3
"""Tester bots stay out of the base server's player lists (server/README.md "Tester bots").

usage: python3 -I patch_tester_filters.py DATA_DIR [--dry-run]

A tester is a character with the player storage 7102900 = 1 (Chaos.storage.tester; server/tools/testers.py). The base
scripts that list or count players from the players table or the online players leave testers out:
  scripts/customs/highscores/highscores.lua       the in-game highscores (opcode 73): its count and its page query
  scripts/customs/actions/top_3_players_2.lua     the top 3 statues of the main town
  scripts/customs/actions/top_3_players_rook.lua  the top 3 statues of the starting island
  talkactions/scripts/online.lua                  !online: the count and the list
Each change carries the marker below and is not made twice. A file that is missing or whose text differs is reported
and skipped (exit 1 when a known file exists but cannot be patched, so a base update is noticed).
install_all.py runs it in the events step.
"""
import os
import sys

MARK = 'Chaos: tester bots left out (patch_tester_filters.py)'
KEY = 7102900
NOT_TESTER = ('NOT EXISTS (SELECT 1 FROM `player_storage` `ts` WHERE `ts`.`player_id` = %s.`id` '
              'AND `ts`.`key` = ' + str(KEY) + ' AND `ts`.`value` = 1)')

HS_COUNT_OLD = '("SELECT COUNT(*) AS total FROM `players` WHERE `vocation` IN (%s)")'
HS_COUNT_NEW = ('("SELECT COUNT(*) AS total FROM `players` WHERE `vocation` IN (%s) AND '
                + (NOT_TESTER % '`players`') + '") -- ' + MARK)
HS_PAGE_OLD = '    WHERE p.`vocation` IN (%s)\n'
HS_PAGE_NEW = ('    WHERE p.`vocation` IN (%s) AND ' + (NOT_TESTER % 'p') + ' /* ' + MARK + ' */\n')  # inside the SQL

TOP_OLD = 'FROM `players` ORDER BY `level` DESC, `experience` DESC LIMIT %d", amount)'
TOP_NEW = ('FROM `players` WHERE ' + (NOT_TESTER % '`players`')
           + ' ORDER BY `level` DESC, `experience` DESC LIMIT %d", amount) -- ' + MARK)

ONLINE_OLD = '\t\tif player:canSeeCreature(targetPlayer) then\n'
ONLINE_NEW = ('\t\t-- ' + MARK + '\n'
              '\t\tif player:canSeeCreature(targetPlayer) and not (Chaos and Chaos.isTester and Chaos.isTester(targetPlayer)) then\n')

# (path below data, [(old, new)])
EDITS = [
    ('scripts/customs/highscores/highscores.lua', [(HS_COUNT_OLD, HS_COUNT_NEW), (HS_PAGE_OLD, HS_PAGE_NEW)]),
    ('scripts/customs/actions/top_3_players_2.lua', [(TOP_OLD, TOP_NEW)]),
    ('scripts/customs/actions/top_3_players_rook.lua', [(TOP_OLD, TOP_NEW)]),
    ('talkactions/scripts/online.lua', [(ONLINE_OLD, ONLINE_NEW)]),
]


def patch(text, edits):
    """returns (new text, status): 'patched', 'already' or an error message"""
    if MARK in text:
        return text, 'already'
    crlf = '\r\n' in text
    for old, new in edits:
        if crlf:
            old, new = old.replace('\n', '\r\n'), new.replace('\n', '\r\n')
        n = text.count(old)
        if n != 1:
            return text, 'expected text found %d times, not patched: %s' % (n, old.strip()[:60])
        text = text.replace(old, new)
    return text, 'patched'


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    data = args[0]
    rc = 0
    for rel, edits in EDITS:
        path = os.path.join(data, rel)
        if not os.path.isfile(path):
            print('%s: not found, skipped' % rel)
            continue
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, st = patch(text, edits)
        if st not in ('patched', 'already'):
            rc = 1
        if st == 'patched' and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        print('%s: %s%s' % (rel, st, ' (dry run, not written)' if dry and st == 'patched' else ''))
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
