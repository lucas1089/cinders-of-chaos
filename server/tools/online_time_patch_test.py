#!/usr/bin/env python3
"""Guard for engine src-patch 0095: players.onlinetime counts each online second once (O253, O258).

Seen in a client 2026-11-26: a new character read onlinetime 1795718727 after a 258 s session. The stock
IOLoginData::savePlayer added time(nullptr) - lastLoginSaved at every save of an online player; lastLoginSaved is the
last login from the database (0 for a new character) until ProtocolGame::login sets it, so the save of the level the
first-login kit gives inside onLogin (stock advance_save) added the whole clock, and every save inside a session counted
the session start again. The patch adds Player::onlineCountedAt, set at the login, and counts from it. This test reads
the patch text and checks that
  * it is the only patch numbered 0095 and touches src/iologindata.cpp, src/player.h and src/protocolgame.cpp only,
  * the only removed lines are the stock onlinetime condition and its query line,
  * the new count needs onlineCountedAt != 0 and moves the mark only after the transaction commits,
  * the mark is set in the fresh login branch only (a takeover of a lingering character keeps it),
  * no later patch removes it,
  * it applies with patch -p1 --fuzz=0 to a tree rebuilt from its own context (SRC_TREE=DIR: a dry run on a real
    source tree with 0001-0094 applied).
It also runs the save arithmetic, stock and patched, on the sessions of the client run.
Run: python3 -I server/tools/online_time_patch_test.py (standard library; the apply step needs the patch tool)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')
NAME = '0095-online-time-once.patch'
FILES = ['src/iologindata.cpp', 'src/player.h', 'src/protocolgame.cpp']
STOCK = ['if (!player->isOffline()) {',
         'query << "`onlinetime` = `onlinetime` + " << (time(nullptr) - player->lastLoginSaved) << \',\';']


def hunks(text):
    """{file: [(old lines, new lines)]} from a unified diff"""
    out, cur, old, new = {}, None, None, None
    for line in text.splitlines():
        if line.startswith('+++ b/'):
            cur = line[6:].split()[0]
            out[cur] = []
            old = new = None
        elif line.startswith('@@'):
            old, new = [], []
            out[cur].append((old, new))
        elif old is not None and cur and not line.startswith('--- ') and not line.startswith('diff '):
            if line.startswith('-'):
                old.append(line[1:])
            elif line.startswith('+'):
                new.append(line[1:])
            elif line.startswith(' ') or line == '':
                old.append(line[1:])
                new.append(line[1:])
    return out


def stock_save(online, last_login_saved, now):
    """the stock line: a save of an online player adds now - lastLoginSaved"""
    return online + (now - last_login_saved)


def patched_save(online, counted_at, now):
    """the patched line: counts from the mark when it is set, then moves it; returns (onlinetime, mark)"""
    if counted_at != 0 and now > counted_at:
        return online + (now - counted_at), now
    return online, counted_at


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    names = sorted(os.listdir(PATCHES))
    mine = [n for n in names if n.startswith('0095-')]
    check(mine == [NAME], 'one patch 0095: %s' % mine)
    if mine != [NAME]:
        return 1
    text = open(os.path.join(PATCHES, NAME), encoding='utf-8').read()
    files = [l[6:].split()[0] for l in text.splitlines() if l.startswith('+++ b/')]
    check(files == FILES, 'files: %s' % files)
    removed = [l[1:].strip() for l in text.splitlines() if l.startswith('-') and not l.startswith('---')]
    added = [l[1:] for l in text.splitlines() if l.startswith('+') and not l.startswith('+++')]
    code = [l.strip() for l in added if l.strip() and not l.strip().startswith('//')]
    check(removed == STOCK, 'removes only the stock onlinetime lines: %r' % removed)
    check('time_t onlineCountedAt = 0;' in code, 'new Player field onlineCountedAt, 0 by default')
    check(any('player->onlineCountedAt != 0' in l and '!player->isOffline()' in l for l in code),
          'counts only an online player whose login is done')
    check(any('(onlineNow - player->onlineCountedAt)' in l for l in code), 'counts from the mark')
    check(not any('lastLoginSaved' in l and '`onlinetime`' in l for l in code), 'no onlinetime query line reads lastLoginSaved')
    h = hunks(text)
    login = [l for _, new in h.get('src/protocolgame.cpp', []) for l in new if 'onlineCountedAt' in l]
    check(len(login) == 1 and 'player->onlineCountedAt = player->lastLoginSaved;' in login[0],
          'the mark is set once at the login, to the new lastLoginSaved: %r' % login)
    pg = h.get('src/protocolgame.cpp', [])
    check(len(pg) == 1 and any('endPreAuth(); // Chaos (patch 0067): logged in, no longer' in l for l in pg[0][1]),
          'the protocolgame hunk is the fresh login branch, not the takeover')
    io = h.get('src/iologindata.cpp', [])
    check(len(io) == 2, 'two hunks in iologindata.cpp')
    if len(io) == 2:
        tail = io[1][1]
        commit = next((i for i, l in enumerate(tail) if 'transaction.commit()' in l), None)
        moved = next((i for i, l in enumerate(tail) if 'player->onlineCountedAt = onlineNow;' in l), None)
        check(commit is not None and moved is not None and moved > commit, 'the mark moves after the commit')
        check(any('if (countOnline)' in l for l in tail), 'the mark moves only when the save counted')
    check(text.count('Chaos (patch 0095)') >= 4, 'every change carries a patch 0095 comment')
    for n in names:
        if n > NAME:
            body = open(os.path.join(PATCHES, n), encoding='utf-8').read()
            gone = [l for l in body.splitlines() if l.startswith('-') and not l.startswith('---')]
            check(not any('onlineCountedAt' in l for l in gone), 'no later patch removes the mark: ' + n)

    # apply on a tree rebuilt from the patch's own context (the base tree is not in the repository)
    if shutil.which('patch'):
        tmp = tempfile.mkdtemp(prefix='p0095_')
        try:
            for f, hs in h.items():
                path = os.path.join(tmp, f)
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, 'w', encoding='utf-8') as out:
                    for old, _ in hs:
                        # filler keeps the hunks apart; patch takes the offset (no fuzz)
                        out.write('// filler\n' * 40)
                        out.write('\n'.join(old) + '\n')
            r = subprocess.run(['patch', '-p1', '--fuzz=0', '-s', '-i', os.path.join(PATCHES, NAME)], cwd=tmp,
                               capture_output=True, text=True)
            check(r.returncode == 0, 'applies with --fuzz=0 to a tree rebuilt from its context: ' + r.stdout + r.stderr)
            if r.returncode == 0:
                body = open(os.path.join(tmp, 'src/iologindata.cpp'), encoding='utf-8').read()
                check('lastLoginSaved) <<' not in body, 'the stock count is gone after the apply')
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        tree = os.environ.get('SRC_TREE')
        if tree:
            r = subprocess.run(['patch', '-p1', '--fuzz=0', '--dry-run', '-i', os.path.join(PATCHES, NAME)], cwd=tree,
                               capture_output=True, text=True)
            check(r.returncode == 0, 'dry run on SRC_TREE: ' + r.stdout + r.stderr)

    # the sessions of the client run (2026-11-26). A new character: lastlogin 0 in the database; the kit's level in
    # onLogin saves at T, the login sets lastLoginSaved = T, later levels save at T+60 and T+120, the logout at T+258.
    T = 1795718469
    online = stock_save(0, 0, T)  # the save inside onLogin
    for now in (T + 60, T + 120, T + 258):
        online = stock_save(online, T, now)
    check(online == T + 438, 'stock: the clock plus 60 + 120 + 258 s (%d)' % online)
    check(online >= 946684800, 'stock: a clock value, past the metrics limit')
    online, mark = patched_save(0, 0, T)  # the mark is 0 inside onLogin: nothing counted
    check((online, mark) == (0, 0), 'patched: a save before the login is done counts nothing')
    mark = T  # ProtocolGame::login
    for now in (T + 60, T + 120, T + 258):
        online, mark = patched_save(online, mark, now)
    check(online == 258, 'patched: the 258 s of the session, once (%d)' % online)
    # a returning character: a save in onLogin counted the offline time (lastLoginSaved = the last login)
    check(stock_save(3600, T - 86400, T) - 3600 == 86400, 'stock: a day offline counted as played')
    check(patched_save(3600, 0, T) == (3600, 0), 'patched: nothing before the login is done')
    # a failed save does not move the mark: the next one counts the whole time since the last counted save
    online, mark = patched_save(100, T, T + 30)
    check((online, mark) == (130, T + 30), 'patched: a save moves the mark')
    check(patched_save(online, mark, mark) == (130, T + 30), 'patched: two saves in the same second add nothing')
    if failures:
        return 1
    print('online time patch test OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
