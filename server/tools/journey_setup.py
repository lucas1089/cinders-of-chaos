#!/usr/bin/env python3
"""Tester characters of the journey bots (O542, server/README.md "Journey bots (O542)").

A journey bot plays a FRESH character from its first login on, like a new player: level 1 as the website makes it (150 health, 0 mana,
400 capacity, position 0,0,0, last login 0: the first login gives the start level, the kit and the temple of Cinderhold). The character is
a tester by every rule of server/tools/testers.py: named "Tester Xxx", the marker storage 7102900 = 1, group 1, an account of type 1
named tstbot... So the server keeps it apart from the players (src-patch 0059, testers.lua: never counted online, no combat, trade,
party, market or mail with a player, not in rankings, Discord or broadcasts) and `testers.py cleanup --state DIR` deletes it (every row).
No helper file is installed and the bot gets no teleport: it is the tester marker without the TEST ONLY helper.

  journey_setup.py setup --count N --server-dir SERVER --state DIR [--classes Warrior,Ranger,Mystic] [--hash-iterations N]
  journey_setup.py env   --state DIR --index I     export lines for bot I (account, password, character): read inside a subshell, never logged
  journey_setup.py list  --state DIR               key=value lines: bots, then one line per bot (name, class), no password

The state file is private (mode 600) and holds the passwords. Cleanup: python3 -I server/tools/testers.py cleanup --state DIR --server-dir SERVER [--yes].
Database settings come from the environment like testers.py (CHAOS_MYSQL, CHAOS_DB_SOCKET, ...).
"""
import os
import secrets
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import testers as T  # noqa: E402
import tester_core as TC  # noqa: E402
import loadtest as LT  # noqa: E402

MAX_BOTS = 10
DEFAULT_CLASSES = 'Warrior,Ranger,Mystic'


def plan(count, classes):
    """[(class name, weight)] -> the class of each of `count` bots, in turn."""
    wheel = [name for name, w in classes for _ in range(w)]
    return [wheel[i % len(wheel)] for i in range(count)]


def new_bot_statements(bots, pw_hash_of):
    """the INSERTs of fresh level 1 tester accounts and characters (names checked) and the marker storage only (no hunt spot, no kit)."""
    st = []
    for b in bots:
        assert T.safe_account(b['account']) and T.safe_name(b['name'])
        st.append("INSERT INTO `accounts` (`name`, `password`, `email`, `type`) VALUES ('%s', '%s', '', 1);" % (b['account'], pw_hash_of(b)))
        st.append("INSERT INTO `players` (`name`, `account_id`, `group_id`, `vocation`, `level`, `experience`, `health`, `healthmax`, `mana`, `manamax`, `cap`, `soul`, "
                  "`sex`, `looktype`, `lookhead`, `lookbody`, `looklegs`, `lookfeet`, `lookaddons`, `town_id`, `posx`, `posy`, `posz`, `lastlogin`) "
                  "SELECT '%s', `id`, 1, %d, 1, 0, 150, 150, 0, 0, 400, 100, 1, 128, 78, 68, 58, 76, 3, %d, 0, 0, 0, 0 FROM `accounts` WHERE `name` = '%s';"
                  % (b['name'], b['vocation'], b.get('town', 2), b['account']))
        st.append("INSERT INTO `player_storage` (`player_id`, `key`, `value`) SELECT `id`, %d, 1 FROM `players` WHERE `name` = '%s';" % (TC.TESTER_STORAGE, b['name']))
    return st


def setup(count, server_dir, state, classes=DEFAULT_CLASSES, iterations=120000, town=2):
    if not 1 <= count <= MAX_BOTS:
        sys.exit('--count 1..%d' % MAX_BOTS)
    st = T.load_state(state)
    if st.get('bots'):
        sys.exit('%s already lists %d bots: run testers.py cleanup --state first' % (T.state_path(state), len(st['bots'])))
    vocs = LT.parse_vocations(LT.read_text(os.path.join(server_dir, 'data', 'XML', 'vocations.xml')))
    wanted = [c.strip() for c in classes.split(',') if c.strip()]
    missing = [c for c in wanted if c not in vocs]
    if missing:
        sys.exit('no such vocation in vocations.xml: %s' % ', '.join(missing))
    taken = {r[0] for r in T.rows(T.sql(["SELECT `name` FROM `players` WHERE `name` LIKE 'Tester %';"]))}
    bots, i = [], 0
    for cls in plan(count, [(c, 1) for c in wanted]):
        while T.tester_name(i) in taken:
            i += 1
        bots.append({'account': T.new_account_name(), 'password': secrets.token_urlsafe(18), 'name': T.tester_name(i), 'class': cls, 'vocation': vocs[cls]['id'], 'town': town})
        i += 1
    hashes = {b['account']: T.pbkdf2_hash(b['password'], iterations) for b in bots}
    state_doc = {'bots': bots, 'created': 0, 'server_dir': server_dir, 'journey': True}
    T.save_state(state, state_doc)   # first, so a cleanup after a crash finds every account by name
    T.sql(new_bot_statements(bots, lambda b: hashes[b['account']]))
    got = T.rows(T.sql(["SELECT p.`id`, p.`name`, a.`id`, a.`name` FROM `players` p JOIN `accounts` a ON a.`id` = p.`account_id` WHERE a.`name` IN (%s);"
                        % ','.join("'%s'" % b['account'] for b in bots)]))
    by_acc = {r[3]: r for r in got}
    for b in bots:
        r = by_acc.get(b['account'])
        if r and r[1] == b['name']:
            b['player_id'], b['account_id'] = int(r[0]), int(r[2])
    T.save_state(state, state_doc)
    print('%d journey tester characters created (%s); state: %s' % (sum(1 for b in bots if 'player_id' in b), ', '.join(sorted(set(b['class'] for b in bots))), T.state_path(state)))


def env_lines(bot):
    """export lines for one bot: the values are checked (letters, digits, spaces only), so a subshell can eval them safely."""
    assert T.safe_account(bot['account']) and T.safe_name(bot['name'])
    assert all(c.isalnum() or c in '-_' for c in bot['password'])
    return ['export CHAOS_LIVE_ACCOUNT=%s' % bot['account'], 'export CHAOS_LIVE_PASSWORD=%s' % bot['password'], "export JOURNEY_CHARACTER='%s'" % bot['name'],
            "export JOURNEY_CLASS='%s'" % bot['class']]


def list_lines(state_doc):
    bots = state_doc.get('bots', [])
    out = ['bots=%d' % len(bots)]
    for i, b in enumerate(bots):
        out.append('bot%d=%s;%s' % (i, b['name'], b['class']))
    return out


def main(argv):
    if not argv or argv[0] not in ('setup', 'env', 'list'):
        print(__doc__)
        return 2
    cmd, opts, i = argv[0], {}, 1
    while i < len(argv):
        if argv[i].startswith('--') and i + 1 < len(argv):
            opts[argv[i][2:]] = argv[i + 1]
            i += 2
        else:
            sys.exit('unknown or incomplete option %s' % argv[i])
    state = opts.get('state')
    if not state:
        sys.exit('--state DIR is required')
    if cmd == 'setup':
        if 'count' not in opts or 'server-dir' not in opts:
            sys.exit('--count N and --server-dir SERVER are required')
        try:
            count, iterations = int(opts['count']), int(opts.get('hash-iterations', 120000))
        except ValueError:
            sys.exit('--count and --hash-iterations are numbers')
        if iterations < 1:
            sys.exit('--hash-iterations: at least 1')
        setup(count, opts['server-dir'], state, opts.get('classes', DEFAULT_CLASSES), iterations)
        return 0
    doc = T.load_state(state)
    if cmd == 'list':
        print('\n'.join(list_lines(doc)))
        return 0
    try:
        bot = doc['bots'][int(opts.get('index', '0'))]
    except (ValueError, IndexError, KeyError):
        sys.exit('no such bot in %s' % T.state_path(state))
    print('\n'.join(env_lines(bot)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
