#!/usr/bin/env python3
"""Guard for engine src-patches 0034 and 0035: taking over a lingering character neither throws the new client out at
once (0034) nor, when the takeover is cancelled, leaves the character in the game for good (0035).

A character whose connection was lost stays in the game until Player::sendPing() removes it, 60 s after the last answer
to a ping. ProtocolGame::connect (a new login of that character) did not renew that time, so the next check logged the
new client out before its first ping (server/README.md "Stress test"). This test reads the patch chain in order and
checks that the last patch that writes ProtocolGame::connect in src/protocolgame.cpp renews the pong
(player->receivePing()) when it gives the player the new client, before the player is sent to it, and that connect()
clears foundPlayer->isConnecting when it gives up on an expired connection (0035: Player::sendPing() never removes a
character that is connecting, so it stayed in the world without a client).

Run: python3 -I server/tools/reattach_ping_patch_test.py (standard library only)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')


def connect_hunks(text):
    """the new text ('+' and ' ' lines) of the hunks of src/protocolgame.cpp that set player->client in connect()"""
    out, inside, hunk = [], False, []
    for line in text.splitlines() + ['@@ end']:
        if line.startswith('+++ '):
            inside = line[4:].split()[0].endswith('src/protocolgame.cpp')
            continue
        if line.startswith('--- '):
            continue
        if line.startswith('@@'):
            body = '\n'.join(hunk)
            if 'player->client = getThis();' in body and 'sendAddCreature(player, player->getPosition(), 0, false);' in body:
                out.append(body)
            hunk = []
            continue
        if inside and (line.startswith('+') or line.startswith(' ')):
            hunk.append(line[1:])
    return out


def expired_branch(text):
    """the new text of the isConnectionExpired() branch of ProtocolGame::connect in a patch, or None"""
    body = '\n'.join(l[1:] for l in text.splitlines() if (l.startswith('+') or l.startswith(' '))
                     and not l.startswith('+++'))
    m = re.search(r'if \(isConnectionExpired\(\)\) \{([\s\S]*?)\n\t\}', body)
    return m.group(1) if m else None


def clears(branch):
    return bool(branch and re.search(r'foundPlayer->isConnecting = false;[\s\S]*return;', branch))


def renews(body):
    """True when the pong is renewed after the client is set and before the player is sent to it"""
    m = re.search(r'player->client = getThis\(\);([\s\S]*?)sendAddCreature\(player, player->getPosition\(\), 0, false\);',
                  body)
    return bool(m and re.search(r'player->receivePing\(\);', m.group(1)))


def main():
    fails, last, expired = [], None, None
    for name in sorted(os.listdir(PATCHES)):
        if not re.match(r'^\d{4}-.*\.patch$', name):
            continue
        with open(os.path.join(PATCHES, name), errors='replace') as f:
            text = f.read()
        for body in connect_hunks(text):
            last = (name, body)
        if expired_branch(text) is not None:
            expired = (name, expired_branch(text))
    if expired is None or not clears(expired[1]):
        fails.append('ProtocolGame::connect gives up on an expired connection without clearing isConnecting (0035 '
                     'missing or undone, last: %s): the character stays in the game for good' % (expired[0] if expired else '-'))
    if clears('\n\t\treturn;') or not clears('\n\t\tfoundPlayer->isConnecting = false;\n\t\treturn;'):
        fails.append('clears() does not tell the stock branch from the fixed one')
    if last is None or not renews(last[1]):
        fails.append('ProtocolGame::connect does not renew the pong (0034 missing or undone, last: %s): a reconnect '
                     'to a lingering character is logged out at the next ping check' % (last[0] if last else '-'))
    # the check itself
    if renews('player->client = getThis();\nsendAddCreature(player, player->getPosition(), 0, false);'):
        fails.append('renews() accepts the stock code')
    if not renews('player->client = getThis();\nplayer->receivePing();\nsendAddCreature(player, player->getPosition(), 0, false);'):
        fails.append('renews() refuses the fixed code')
    for f in fails:
        print('FAIL ' + f)
    print('reattach_ping_patch_test: ProtocolGame::connect last written by %s, %d failure(s)'
          % (last[0] if last else '-', len(fails)))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
