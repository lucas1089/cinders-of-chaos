#!/usr/bin/env python3
"""Tester bots: characters that play on the live server to find bugs (server/README.md "Tester bots").

Standard library only. The owner runs it through chaos-ctl.sh (testers start | stop | status | report | cleanup);
by hand, as root:

  setup    create N tester accounts and characters (state folder: a root-only state.json with their random passwords)
             python3 -I testers.py setup --count 100 --server-dir SERVER [--state /var/lib/chaos/testers]
                 [--levels 30,100,250,500,750,1000,1250,1500,1750,2000] [--classes auto | NAME:WEIGHT,...] [--hash-iterations 120000]
  run      log them in and play until --minutes are over (default 60), then log out
             python3 -I testers.py run --key-file /etc/chaos/tester-client-key --server-dir SERVER
                 [--state DIR] [--minutes 60] [--count N] [--host 127.0.0.1] [--port 7171] [--log SERVER_LOG]
                 [--scenarios FILE] [--ramp 1.0] [--keystones] [--checks]
  report   the bug harvest of the last run (the bots' results and the server log since the run started)
             python3 -I testers.py report [--state DIR] [--log SERVER_LOG] [--scenarios FILE]
  cleanup  delete the tester accounts, their characters and every database row of them; nothing else
             python3 -I testers.py cleanup [--state DIR] [--dry-run]
  status   bots=, minutes=, online= (in game now), online_peak=, logins=, deaths= of the state folder (chaos-ctl.sh testers status)

Safety (live server with real players):
  * at most 150 bots (MAX_BOTS), default 100; the database rows of a tester carry the player storage 7102900 = 1
    (Chaos.storage.tester; the engine never counts it online, src-patch 0059); names "Tester Xxx", accounts
    "tstbot" + 10 random hex digits, group 1, account type 1, never staff
  * every account gets its own random password; it lives only in state.json (mode 0600, root)
  * the client guard key comes from --key-file: a file owned by root (or the user running this), not readable by group
    or others, made by the owner with `read -rs` (server/README.md "Tester bots"); never from argv or the environment.
    The public development key is refused, and so is a server with clientGuardAllowDevKey = true
  * cleanup deletes only rows of characters that have the tester storage AND a "Tester Xxx" name AND an account named
    "tstbot..." (the ids in state.json, plus such characters the state lost); no LIKE on names
What a bot does, by the weighted behaviours of tester_core.BEHAVIOURS: hunts (the helper server/tools/tester_helper.lua,
TEST ONLY, gives it a target), casts its class rotation, heals itself with its best healing spell and with potions (the
hotkey packet: use with creature at position 0xFFFF on its own creature id), really dies and logs in again, goes to town,
a depot locker (the retired depot: it opens the stash), an NPC (hi, trade, buy potions, sell, bye), parties, private messages, client module
requests (--scenarios tester_scenarios.json: tester_scenarios.py, also places and NPC dialogs through the helper's
`!tester enter`), loot filter takes, opens its backpack, logs out and in. A dropped connection (server restart) is
retried with a growing pause, so the bots come back after a restart.
--keystones (needs --scenarios): each bot first runs the keystone and mastery scenario of its class once (tester_keystones.py,
O249): allocates every node of its class the points allow, as the tree window does, checks that the effect shows (the
totals of the tree window, the keystone's own row of the combat log) or says it cannot be seen, and resets the tree.
--checks: each bot then runs the system checks of its class once (tester_checks.py, O110): pets, the Necromancer's minions,
the Beastmaster's wolf (O86: no summon takes its owner or a party member for a target), party play and its shared experience, a rift and its layout, waystone runs by tier and modifiers, the content rewards, the waystone
atlas, the reward chest, the cursed chest and the Auto setup spell list. A failed check is a "BUG ..." line in the report.
"""
import asyncio
import base64
import hashlib
import json
import os
import random
import re
import secrets
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import loadtest as LT  # noqa: E402
import tester_core as TC  # noqa: E402
import tester_keystones as TK  # noqa: E402  (the keystone and mastery scenario, O249)
import tester_checks as TX  # noqa: E402  (the system checks, O110)

DEFAULT_STATE = '/var/lib/chaos/testers'
LETTERS = 'abcdefghijklmnopqrstuvwxyz'


# ------------------------------------------------------------------------------------------------ names, state
def tester_name(index):
    i, suffix = index, ''
    for _ in range(3):
        suffix = LETTERS[i % 26] + suffix
        i //= 26
    return 'Tester ' + suffix.capitalize()


def new_account_name():
    return 'tstbot' + secrets.token_hex(5)


def safe_name(name):
    return bool(TC.NAME_RE.match(name or ''))


def safe_account(name):
    return bool(TC.ACCOUNT_RE.match(name or ''))


def state_path(folder):
    return os.path.join(folder, 'state.json')


def write_private(path, text):
    """write a file only its owner can read (0600), atomically"""
    folder = os.path.dirname(path) or '.'
    os.makedirs(folder, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.tmp', dir=folder)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'w') as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def load_state(folder):
    try:
        with open(state_path(folder)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {'bots': []}


def save_state(folder, st):
    write_private(state_path(folder), json.dumps(st, indent=1, sort_keys=True))


# ------------------------------------------------------------------------------------------------ the client key
def read_key_file(path):
    """the client guard key (64 hex digits) of a root-only file; exits with the reason otherwise"""
    try:
        info = os.lstat(path)
    except OSError as e:
        sys.exit('--key-file %s: %s (create it: see server/README.md "Tester bots")' % (path, e.strerror))
    if not stat.S_ISREG(info.st_mode):
        sys.exit('--key-file %s: not a plain file' % path)
    if info.st_uid not in (0, os.getuid()):
        sys.exit('--key-file %s: not owned by root' % path)
    if info.st_mode & 0o077:
        sys.exit('--key-file %s: readable by group or others (chmod 600)' % path)
    with open(path) as f:
        key = f.read().strip()
    if not re.match(r'^[0-9a-fA-F]{64}$', key):
        sys.exit('--key-file %s: not 64 hex digits' % path)
    raw = bytes.fromhex(key)
    if raw == LT.GUARD_DEV_KEY:
        sys.exit('--key-file %s: that is the public development key; the live server needs the real client key' % path)
    return raw


def dev_key_allowed(config_text):
    """config.lua lets the development key in (clientGuardAllowDevKey = true): never on this server"""
    text = re.sub(r'--[^\n]*', '', config_text or '')
    m = re.search(r'^\s*clientGuardAllowDevKey\s*=\s*(\w+)', text, re.M)
    return bool(m and m.group(1).lower() == 'true')


def lua_setting_string(config_text, name):
    """the plain string value of NAME = "..." in config.lua, or '' (an expression such as os.getenv counts as '')"""
    text = re.sub(r'--[^\n]*', '', config_text or '')
    m = re.search(r'^\s*%s\s*=\s*"([^"\n]*)"' % re.escape(name), text, re.M)
    return m.group(1) if m else ''


def login_key_file(config_text, server_dir, env=None):
    """the first file of rsaKeyFile as the engine reads it (src-patches/0046): a plain string, or
    os.getenv("CHAOS_RSA_KEY_FILE") or "x" (prod_config.py) read from ENV (chaos-ctl.sh loads chaos.env); empty means
    key.pem. A relative path is under SERVER_DIR, as the engine starts there. Returns (path, configured)"""
    env = os.environ if env is None else env
    text = re.sub(r'--[^\n]*', '', config_text or '')
    value, configured = '', False
    m = re.search(r'^\s*rsaKeyFile\s*=\s*([^\n]*)', text, re.M)
    if m:
        expr = m.group(1)
        g = re.match(r'\s*os\.getenv\(\s*"(\w+)"\s*\)(?:\s*or\s*"([^"\n]*)")?', expr)
        if g:
            value = (env.get(g.group(1)) or '').strip() or (g.group(2) or '')
        else:
            value = lua_setting_string(config_text, 'rsaKeyFile')
        configured = True
    first = value.split(',')[0].strip() or 'key.pem'
    configured = configured and first != 'key.pem'
    return (first if os.path.isabs(first) else os.path.join(server_dir, first)), configured


def manifest_floor(text):
    """min_package of an updater manifest (an envelope with JSON inside a JSON string), the same reading as the
    engine's ClientGuard::manifestFloor (src-patches/0021); None when absent"""
    m = re.search(r'min_package[\\":\s]{0,16}?(\d{1,5})', text or '')
    return int(m.group(1)) if m else None


def guard_build(config_text, read=None):
    """the client build the bots announce: the engine refuses a build missing from clientGuardBuilds or below the
    min_package of clientGuardManifest (ClientGuard::gateReason), so take the newest build both accept"""
    read = read or LT.read_text
    builds = sorted({int(t) for t in re.split(r'[\s,;]+', lua_setting_string(config_text, 'clientGuardBuilds'))
                     if t.isdigit() and int(t) <= 0xFFFF})
    floor = 0
    manifest = lua_setting_string(config_text, 'clientGuardManifest')
    if manifest:
        try:
            floor = manifest_floor(read(manifest)) or 0
        except OSError:
            floor = 0
    ok = [b for b in builds if b >= floor]
    if ok:
        return ok[-1]
    if builds:
        return builds[-1]
    return max(1, min(floor, 0xFFFF))


def binds_only_global(config_text):
    text = re.sub(r'--[^\n]*', '', config_text or '')
    m = re.search(r'^\s*bindOnlyGlobalAddress\s*=\s*(\w+)', text, re.M)
    return bool(m and m.group(1).lower() == 'true')


# ------------------------------------------------------------------------------------------------ database
def mysql_cmd(db):
    """the mysql command line and its temporary option file (the password never on a command line)"""
    fd, opt = tempfile.mkstemp(prefix='chaos_testers_', suffix='.cnf')
    os.chmod(opt, 0o600)
    with os.fdopen(fd, 'w') as f:
        f.write('[client]\n')
        if os.environ.get('CHAOS_DB_SOCKET'):
            f.write('socket="%s"\n' % os.environ['CHAOS_DB_SOCKET'].replace('"', ''))
        else:
            f.write('host="%s"\nport="%s"\n' % (os.environ.get('CHAOS_DB_HOST', '127.0.0.1').replace('"', ''),
                                              os.environ.get('CHAOS_DB_PORT', '3306').replace('"', '')))
        f.write('user="%s"\n' % os.environ.get('CHAOS_DB_USER', 'chaos').replace('"', ''))
        f.write('password="%s"\n' % os.environ.get('CHAOS_DB_PASS', '').replace('\\', '\\\\').replace('"', '\\"'))
    client = os.environ.get('CHAOS_MYSQL') or shutil.which('mysql') or shutil.which('mariadb') or 'mysql'
    return [client, '--defaults-extra-file=' + opt, '--batch', '-N', db], opt


def sql(statements, db=None):
    db = db or os.environ.get('CHAOS_DB_NAME', 'chaos')
    cmd, opt = mysql_cmd(db)
    try:
        proc = subprocess.run(cmd, input='\n'.join(statements).encode(), stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT)
        out = proc.stdout.decode(errors='replace')
        if proc.returncode != 0:
            sys.exit('database: ' + out.strip())
        return out
    finally:
        os.unlink(opt)


def rows(out):
    return [line.split('\t') for line in out.splitlines() if line.strip()]


def ids_sql(ids):
    clean = sorted({int(i) for i in ids})
    return ','.join(str(i) for i in clean) if clean else 'NULL'


# ------------------------------------------------------------------------------------------------ setup
def pbkdf2_hash(password, iterations):
    """accounts.password as the website writes it (engine src-patch 0014); always salted PBKDF2: the testers
    never write the old unsalted SHA-1 that loadtest.py's --hash-iterations 0 allows"""
    salt = os.urandom(16)
    key = hashlib.pbkdf2_hmac('sha256', password.encode(), salt, iterations, 32)
    return 'pbkdf2-sha256$%d$%s$%s' % (iterations, base64.b64encode(salt).decode(), base64.b64encode(key).decode())


# the level bands of the testers (beta 2026-10-22: up to the endgame, 2000)
LEVELS = (30, 100, 250, 500, 750, 1000, 1250, 1500, 1750, 2000)


def plan_bots(count, classes, levels):
    """[(class, level)] of the testers: the levels in turn, so every band gets count / len(levels) of them whatever
    the number of classes, and the classes shifted by one each round, so a band does not get the same classes (the
    load test's assign() fills the bands class by class: 100 testers over 15 classes never reached the last bands)"""
    wheel = [name for name, w in classes for _ in range(w)]
    return [(wheel[(i + i // len(levels)) % len(wheel)], levels[i % len(levels)]) for i in range(count)]


def plan_classes(spec, vocations):
    """[(name, weight)]: 'auto' = every class of vocations.xml except None (id 0)"""
    if spec == 'auto':
        return [(name, 1) for name, v in sorted(vocations.items(), key=lambda kv: kv[1]['id']) if v['id'] > 0]
    weights = LT.parse_weights(spec)
    missing = [n for n, _ in weights if n not in vocations]
    if missing:
        sys.exit('--classes: no such vocation in vocations.xml: %s' % ', '.join(missing))
    return weights


def setup_statements(bots, pw_hash_of):
    """the INSERTs of the tester accounts, characters and their marker storages (names checked before)"""
    st = []
    for b in bots:
        assert safe_account(b['account']) and safe_name(b['name'])
        st.append("INSERT INTO `accounts` (`name`, `password`, `email`, `type`) VALUES ('%s', '%s', '', 1);"
                  % (b['account'], pw_hash_of(b)))
        st.append("INSERT INTO `players` (`name`, `account_id`, `group_id`, `vocation`, `level`, `health`, `healthmax`, "
                  "`experience`, `mana`, `manamax`, `maglevel`, `skill_fist`, `skill_club`, `skill_sword`, `skill_axe`, "
                  "`skill_dist`, `skill_shielding`, `cap`, `town_id`, `posx`, `posy`, `posz`, `lastlogin`, `looktype`) "
                  "SELECT '%s', `id`, 1, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, 3000, %d, %d, %d, %d, "
                  "UNIX_TIMESTAMP() - 86400, 128 FROM `accounts` WHERE `name` = '%s';"
                  % (b['name'], b['vocation'], b['level'], b['hp'], b['hp'], LT.exp_for_level(b['level']), b['mana'],
                     b['mana'], b['ml'], b['skill'], b['skill'], b['skill'], b['skill'], b['skill'], b['skill'],
                     b['town'], b['pos'][0], b['pos'][1], b['pos'][2], b['account']))
        for off, val in ((0, 1), (2, b['pos'][0]), (3, b['pos'][1]), (4, b['pos'][2])):
            st.append("INSERT INTO `player_storage` (`player_id`, `key`, `value`) SELECT `id`, %d, %d FROM `players` "
                      "WHERE `name` = '%s';" % (TC.TESTER_STORAGE + off, val, b['name']))
    return st


SNAP_REACH = 30  # sqm round a hunt mark in which a spawn centre safe for the level is looked for
SNAP_CLEAR = 14  # sqm round the chosen centre in which every other spawn centre must be safe too (their monsters aggro)


def place_testers(levels, hunts, temples, index=None, centres=None):
    """one position per tester: in a hunt its level may hold (TC.safe_hunts: the whole band, in hunting levels, at or under
    the level), on the nearest spawn centre whose monsters all hunt at or under the level (spawn_levels; none within SNAP_REACH:
    the temple)"""
    pos = LT.level_positions(hunts, temples, levels, 0.0, pick=TC.safe_hunts if hunts else None)
    if index is None:
        return pos
    out = []
    for i, (p, lv) in enumerate(zip(pos, levels)):
        q = LT.snap_to_spawn(p, index, reach=SNAP_REACH if centres is not None else 12, centre_levels=centres, max_level=lv,
                             clear=SNAP_CLEAR)
        if centres is not None and centres.get(q, 10 ** 9) > lv and q not in temples:
            q = tuple(temples[i % len(temples)])  # no safe spawn within reach: the temple, a player's start
        out.append(q)
    return out


def setup(a):
    if not 1 <= a.count <= TC.MAX_BOTS:
        sys.exit('--count 1..%d' % TC.MAX_BOTS)
    st = load_state(a.state)
    if st.get('bots'):
        sys.exit('%s already lists %d testers: run cleanup first' % (state_path(a.state), len(st['bots'])))
    data = os.path.join(a.server_dir, 'data')
    vocs = LT.parse_vocations(LT.read_text(os.path.join(data, 'XML', 'vocations.xml')))
    classes = plan_classes(a.classes, vocs)
    levels = [int(v) for v in a.levels.split(',') if v.strip()]
    poi = LT.read_text(os.path.join(data, 'chaos_poi.lua'))
    temples = [m[1:] for m in LT.poi_marks(poi) if m[0] == 'temple']
    hunts = LT.hunt_marks(poi)
    if not temples:
        sys.exit('no temple marks in data/chaos_poi.lua (install step poi)')
    plan = plan_bots(a.count, classes, levels)
    spawns = sorted(__import__('glob').glob(os.path.join(data, 'world', '*-spawn.xml')))[:1]
    index = LT.spawn_index(LT.read_text(spawns[0])) if spawns else None
    centres = None
    pool = os.path.join(data, 'scripts', 'chaos', 'bounty_pool.lua')
    if spawns and os.path.isfile(pool):
        centres = LT.spawn_levels(LT.read_text(spawns[0]), LT.pool_levels(LT.read_text(pool)))
    elif spawns:
        print('no data/scripts/chaos/bounty_pool.lua: the testers are not kept off spawns above their level')
    positions = place_testers([lv for _, lv in plan], hunts, temples, index, centres)
    # names: the first free "Tester Xxx" (a name a player already has is skipped, never touched)
    taken = {r[0] for r in rows(sql(["SELECT `name` FROM `players` WHERE `name` LIKE 'Tester %';"]))}
    bots, i = [], 0
    for k, (cls, level) in enumerate(plan):
        while tester_name(i) in taken:
            i += 1
        name = tester_name(i)
        i += 1
        hp, mana, ml, skill = LT.class_stats(cls, level, vocs[cls])
        bots.append({'account': new_account_name(), 'password': secrets.token_urlsafe(18), 'name': name,
                     'class': cls, 'vocation': vocs[cls]['id'], 'level': level, 'hp': hp, 'mana': mana, 'ml': ml,
                     'skill': skill, 'town': a.town, 'pos': list(positions[k])})
    exist = rows(sql(["SELECT `name` FROM `accounts` WHERE `name` IN (%s);"
                      % ','.join("'%s'" % b['account'] for b in bots)]))
    if exist:
        sys.exit('account names already exist (random clash, run setup again): %s' % exist)
    hashes = {b['account']: pbkdf2_hash(b['password'], a.hash_iterations) for b in bots}
    # the state first: a cleanup after a crash half way still finds every account by name
    st = {'bots': bots, 'created': int(time.time()), 'server_dir': a.server_dir}
    save_state(a.state, st)
    sql(setup_statements(bots, lambda b: hashes[b['account']]))
    got = rows(sql(["SELECT p.`id`, p.`name`, a.`id`, a.`name` FROM `players` p JOIN `accounts` a ON a.`id` = "
                    "p.`account_id` WHERE a.`name` IN (%s);" % ','.join("'%s'" % b['account'] for b in bots)]))
    by_acc = {r[3]: r for r in got}
    for b in bots:
        r = by_acc.get(b['account'])
        if r and r[1] == b['name']:
            b['player_id'], b['account_id'] = int(r[0]), int(r[2])
    save_state(a.state, st)
    print('%d tester characters created (%d classes, levels %s); state: %s' % (
        sum(1 for b in bots if 'player_id' in b), len(classes), a.levels, state_path(a.state)))


# ------------------------------------------------------------------------------------------------ cleanup
def cleanup_targets(state_bots, db_rows):
    """the (player ids, account ids) cleanup may delete. db_rows: [(player id, player name, account id, account name,
    tester storage value)] of the candidates (the state's ids and every character with the tester storage).
    A row qualifies only with the storage 1 AND a "Tester Xxx" name AND a "tstbot..." account."""
    players, accounts = set(), set()
    for pid, pname, aid, aname, mark in db_rows:
        if str(mark) == '1' and safe_name(pname) and safe_account(aname):
            players.add(int(pid))
            accounts.add(int(aid))
    # accounts of the state with no character left (setup crashed between the two INSERTs)
    return players, accounts


KICK_WAIT = 8  # seconds: remote_cmd.lua takes remote.cmd every 2.5 s, a kicked character is saved on its way out


def kick_lines(names):
    """remote.cmd lines that kick the given characters: only exact "Tester Xxx" names (server/README.md "Tester bots")"""
    return ['kick %s' % n for n in sorted(set(names)) if safe_name(n)]


def kick_online(server_dir, names, wait):
    """Delete a character that is still in game and the engine cannot save it any more: its `players` row is gone
    (Game::saveIncremental logs "Could not save player", at shutdown "Error while saving player"). So the testers are
    kicked first, through the server's remote commands, and cleanup waits for their save. No server folder or no
    server running: remote.cmd is not read, and the server removes a leftover file at its start."""
    lines = kick_lines(names)
    if not lines or not server_dir or not os.path.isdir(server_dir):
        return 0
    with open(os.path.join(server_dir, 'remote.cmd'), 'a') as f:
        f.write('\n'.join(lines) + '\n')
    if wait > 0:
        time.sleep(wait)
    return len(lines)


def cleanup(a):
    st = load_state(a.state)
    pids = [int(b['player_id']) for b in st.get('bots', []) if b.get('player_id')]
    accs = [b['account'] for b in st.get('bots', []) if safe_account(b.get('account'))]
    cand = rows(sql([
        "SELECT p.`id`, p.`name`, a.`id`, a.`name`, IFNULL(s.`value`, 0) FROM `players` p JOIN `accounts` a ON a.`id` = "
        "p.`account_id` LEFT JOIN `player_storage` s ON s.`player_id` = p.`id` AND s.`key` = %d WHERE p.`id` IN (%s) "
        "OR s.`value` = 1;" % (TC.TESTER_STORAGE, ids_sql(pids))]))
    players, accounts = cleanup_targets(st.get('bots', []), [tuple(r) for r in cand if len(r) == 5])
    # empty accounts of the state (no character): by exact name, and only when no character is on them
    if accs:
        for r in rows(sql(["SELECT a.`id`, a.`name` FROM `accounts` a LEFT JOIN `players` p ON p.`account_id` = a.`id` "
                           "WHERE a.`name` IN (%s) AND p.`id` IS NULL;" % ','.join("'%s'" % n for n in accs)])):
            if safe_account(r[1]):
                accounts.add(int(r[0]))
    skipped = [r for r in cand if len(r) == 5 and int(r[0]) not in players]
    for r in skipped:
        print('NOT deleted (not a tester by every rule): player %s %r account %r' % (r[0], r[1], r[3]))
    if not players and not accounts:
        print('no tester characters or accounts in the database')
        if not a.dry:
            st['bots'] = []
            save_state(a.state, st)
        return
    tables = rows(sql(["SELECT `TABLE_NAME`, `COLUMN_NAME` FROM `information_schema`.`COLUMNS` WHERE "
                       "`TABLE_SCHEMA` = DATABASE() AND (`COLUMN_NAME` IN ('player_id', 'account_id') OR `COLUMN_NAME` "
                       "LIKE '%\\_player\\_id' OR `COLUMN_NAME` LIKE '%\\_account\\_id') AND `TABLE_NAME` NOT IN "
                       "('players', 'accounts') ORDER BY 1, 2;"]))
    has_houses = bool(rows(sql(["SELECT 1 FROM `information_schema`.`TABLES` WHERE `TABLE_SCHEMA` = DATABASE() AND "
                                "`TABLE_NAME` = 'houses';"])))
    stmts = cleanup_statements(tables, players, accounts, has_houses)
    print('cleanup: %d characters, %d accounts; rows in %d tables' % (len(players), len(accounts), len(tables)))
    if a.dry:
        print('\n'.join(stmts))
        return
    names = [r[1] for r in cand if len(r) == 5 and int(r[0]) in players]
    kicked = kick_online(a.server_dir, names, a.kick_wait)
    if kicked:
        print('kicked %d tester characters still in game, waited %d s for their save' % (kicked, a.kick_wait))
    sql(stmts)
    st['bots'] = []
    st['cleaned'] = int(time.time())
    save_state(a.state, st)
    print('tester accounts, characters and their rows deleted')


def cleanup_statements(tables, players, accounts, has_houses=False):
    """DELETEs by exact ids only: every row whose player column (player_id, *_player_id) or account column (account_id,
    *_account_id) holds a tester's id, a house a tester owns given back, then players, then accounts"""
    p, acc = ids_sql(players), ids_sql(accounts)
    out = []
    for table, column in tables:
        if not re.match(r'^[A-Za-z0-9_]+$', table) or not re.match(r'^([a-z0-9_]+_)?(player|account)_id$', column):
            continue
        out.append('DELETE FROM `%s` WHERE `%s` IN (%s);' % (table, column, acc if column.endswith('account_id') else p))
    if has_houses:
        out.append('UPDATE `houses` SET `owner` = 0 WHERE `owner` IN (%s);' % p)
        out.append('UPDATE `houses` SET `bid` = 0, `bid_end` = 0, `last_bid` = 0, `highest_bidder` = 0 '
                   'WHERE `highest_bidder` IN (%s);' % p)
    out.append('DELETE FROM `players` WHERE `id` IN (%s);' % p)
    out.append('DELETE FROM `accounts` WHERE `id` IN (%s) AND NOT EXISTS (SELECT 1 FROM `players` WHERE '
               '`account_id` IN (%s));' % (acc, acc))
    return out


# ------------------------------------------------------------------------------------------------ the bot
SHOP_RE_CACHE = {}
WALKED_INTO = 'not possible (a blind step into an obstacle)'  # expected (tester_core.EXPECTED)
ROOM_AFTER_BAG = 'not enough room right after the bag was emptied'  # a bug if it happens
NPC_CHANNEL = 12  # TALKTYPE_PRIVATE_PN: words to the NPC a player is talking to (the client's NPC channel)
SHOP_NOTHING = 'shop: Loot Buyer buys nothing the tester carries'  # expected (tester_core.EXPECTED)


NO_PRICE = 0xFFFFFFFF
SHOP_UNSET = 'shop: the trade window prices an item the NPC does not trade as 4294967295 (-1 as u32; install_all step shopprices)'


def parse_shop(plain, npc):
    """the NPC trade window (0x7A, the NPC's name, u16 count, items: u16 client id, u8 sub, string name, u32 weight,
    u32 buy, u32 sell) in a decrypted message, or None"""
    key = b'\x7a' + struct.pack('<H', len(npc)) + npc.encode('latin-1', 'replace')
    i = plain.find(key)
    if i < 0:
        return None
    i += len(key)
    try:
        count = struct.unpack_from('<H', plain, i)[0]
        i += 2
        items = []
        for _ in range(min(count, 500)):
            cid, sub = struct.unpack_from('<HB', plain, i)
            name, i = LT.read_string(plain, i + 3)
            weight, buy, sell = struct.unpack_from('<III', plain, i)
            i += 12
            # the stock ShopModule prices "not sold / not bought" as -1 and the engine sends it as a u32: 4294967295
            # (patch_shop_prices.py makes it 0). Such a price is no offer: a trade on it raises a Lua error in the NPC
            unset = NO_PRICE in (buy, sell)
            items.append({'id': cid, 'sub': sub, 'name': name, 'buy': 0 if buy == NO_PRICE else buy,
                          'sell': 0 if sell == NO_PRICE else sell, 'unset': unset})
        return items
    except (struct.error, IndexError):
        return None


EXT_RE = re.compile(rb'\x32([\x00-\xff])([\x00-\xff]{2})')


def extended_messages(plain):
    """[(opcode, text)] of the extended opcode messages (0x32, u8 opcode, string) in a decrypted message"""
    out = []
    for m in EXT_RE.finditer(plain):
        n = struct.unpack('<H', m.group(2))[0]
        body = plain[m.end():m.end() + n]
        if n and len(body) == n and body[:1] in (b'{', b'[', b'S', b'P', b'E'):
            out.append((m.group(1)[0], body.decode('latin-1')))
    return out


ACTIVITY_MAX = 300000  # lines of one run's activity log (100 testers, 60 minutes: about 40,000)


class Results:
    """what every bot saw, for the report (written to the state folder as run.json); with `activity` (a path) every
    action, its outcome and every error, one line each, as it happens (runs/<run>.log, the owner reads it with
    chaos-ctl.sh testers log)"""

    def __init__(self, n, activity=None):
        self.lines = 0
        self.activity = None
        if activity:
            os.makedirs(os.path.dirname(activity), mode=0o700, exist_ok=True)
            fd = os.open(activity, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            self.activity = os.fdopen(fd, 'a', buffering=1, encoding='utf-8', errors='replace')
        self.d = {'bots': n, 'started': time.strftime('%Y-%m-%d %H:%M:%S'), 'logins': 0, 'deaths': 0, 'relogs': 0,
                  'reconnects': 0, 'behaviours': {}, 'failures': {}, 'lua_errors': {}, 'kicks': {}, 'anomalies': [],
                  'first': {}, 'coverage': {}}

    def log(self, bot, kind, text):
        """one line of the activity log: time, tester (level, class), what, outcome or error"""
        if not self.activity or self.lines >= ACTIVITY_MAX:
            return
        self.lines += 1
        who = '%s (L%s %s)' % (bot.name, bot.level, bot.cls) if bot is not None else '-'
        line = '%s %s %-8s %s' % (time.strftime('%H:%M:%S'), who, kind, ' '.join(str(text).split()))
        if self.lines == ACTIVITY_MAX:
            line += ' [the log stops here: %d lines]' % ACTIVITY_MAX
        try:
            self.activity.write(line + '\n')
        except OSError:
            self.activity = None

    def close(self):
        if self.activity:
            self.activity.close()
            self.activity = None

    def first(self, key, bot):
        self.d['first'].setdefault(key, {'bot': bot.name, 'did': bot.last, 'at': time.strftime('%H:%M:%S')})

    def count(self, table, key, bot):
        t = self.d[table]
        t[key] = t.get(key, 0) + 1
        self.log(bot, {'failures': 'FAIL', 'lua_errors': 'LUAERROR', 'kicks': 'KICK'}.get(table, table.upper()), key)
        self.first({'failures': 'fail:', 'lua_errors': 'lua:', 'kicks': 'kick:'}.get(table, table + ':') + key, bot)

    def behaviour(self, name, outcome, bot=None):
        b = self.d['behaviours'].setdefault(name, {'tried': 0, 'ok': 0, 'failed': 0, 'expected': 0})
        b[outcome] = b.get(outcome, 0) + 1
        if bot is not None and outcome != 'tried':
            self.log(bot, 'do', '%s %s' % (name, outcome))

    def anomaly(self, rule, bot, **data):
        if len(self.d['anomalies']) < 500:
            data.update(rule=rule, who=bot.name, did=bot.last, t=int(time.time()))
            self.d['anomalies'].append(data)
        self.log(bot, 'ANOMALY', '%s while %s %s' % (rule, bot.last, json.dumps({k: v for k, v in data.items()
                 if k not in ('rule', 'who', 'did', 't')}, sort_keys=True)))


class KeyIO:
    """what tester_keystones.KeyTest needs of a bot in game: requests with their answers, pauses, whether it is still there"""

    def __init__(self, bot, clock):
        self.bot, self.clock = bot, clock

    def alive(self):
        return bool(self.bot.alive and not self.bot.died and not self.clock['stop'])

    async def go(self, place):
        """the temple ('town') or the hunt spot ('hunt') through the helper; True when it answered without an error"""
        if not self.alive():
            return False
        self.bot.stay = place == 'town'
        r = await self.bot.helper_says(place, place)
        return bool(r and not r.get('err'))

    async def sleep(self, seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end and self.alive():
            await asyncio.sleep(min(0.5, max(0.0, end - time.monotonic())))

    async def request(self, opname, action, data, expect, timeout):
        bot = self.bot
        op = bot.args.ops.get(opname)
        if op is None or not self.alive():
            return None
        fut = asyncio.get_event_loop().create_future()
        waiter = (op, set(expect), fut)
        if expect:
            bot.waiters.append(waiter)
        try:
            payload = json.dumps({'action': action, 'data': data}, separators=(',', ':'))
            bot.conn.send(b'\x32' + bytes([op]) + LT.string(payload))
            await bot.conn.w.drain()
            if not expect:
                return None
            return await asyncio.wait_for(fut, timeout)
        except (asyncio.TimeoutError, ConnectionError, OSError):
            return None
        finally:
            if waiter in bot.waiters:
                bot.waiters.remove(waiter)


class CheckIO(KeyIO):
    """what tester_checks.CheckRun needs of a bot in game (KeyIO's requests and pauses, plus the helper, speech and parties)"""

    async def helper(self, command, kind, wait=4.0):
        if not self.alive():
            return None
        return await self.bot.helper_says(command, kind, wait)

    async def say(self, text):
        if self.alive():
            self.bot.say(text)
            await self.bot.conn.w.drain()

    async def partner(self):
        for cid, other in sorted(ONLINE.items()):
            if cid != self.bot.cid and other is not self.bot and other.alive and not other.died:
                return other.name
        return None

    async def party(self, action, other_name):
        other = next((b for b in ONLINE.values() if b.name == other_name), None)
        bot = self.bot
        if other is None or not self.alive() or not other.alive or not bot.cid or not other.cid:
            return False
        if action == 'form':
            bot.conn.send(b'\xA3' + struct.pack('<I', other.cid))      # invite
            await bot.conn.w.drain()
            await asyncio.sleep(1.0)
            other.conn.send(b'\xA4' + struct.pack('<I', bot.cid))       # join the leader
            await other.conn.w.drain()
        elif action in ('share', 'unshare'):
            bot.conn.send(b'\xA8' + (b'\x01' if action == 'share' else b'\x00'))   # the leader's shared experience switch
            await bot.conn.w.drain()
        else:
            other.conn.send(b'\xA7')                                    # leave
            bot.conn.send(b'\xA7')
            await other.conn.w.drain()
            await bot.conn.w.drain()
        return True

    def autosetup(self):
        return getattr(self.bot.args, 'checks_rotation', None)

    def spells(self):
        return getattr(self.bot.args, 'checks_spells', None) or {}


def load_check_spells(server_dir, vocs):
    """{spell id: {name, level, vocations: [vocation ids]}} of the Chaos spells (spells_chaos.xml) and the stock ones
    (stock_spells.csv): what Auto setup's presets are held against"""
    out = {}
    data = os.path.join(server_dir, 'data', 'spells')
    chaos = os.path.join(data, 'chaos', 'spells_chaos.xml')
    if os.path.exists(chaos):
        text = re.sub(r'<!--.*?-->', '', LT.read_text(chaos), flags=re.S)
        for m in re.finditer(r'<instant\b([^>]*?)(/>|>(.*?)</instant>)', text, flags=re.S):
            a = LT._attrs(m.group(1))
            if 'spellid' in a:
                names = re.findall(r'<vocation\s+name="([^"]+)"', m.group(3) or '')
                out[int(a['spellid'])] = {'name': a.get('name', ''), 'level': int(a.get('level', 0) or 0),
                                          'vocations': [vocs[n]['id'] for n in names if n in vocs]}
    stock = os.path.join(data, 'stock_spells.csv')
    if os.path.exists(stock):
        for line in LT.read_text(stock).splitlines()[1:]:
            c = line.split(',')
            if len(c) > 11 and c[0].isdigit() and int(c[0]) not in out:
                names = [n for n in c[11].split(';') if n]
                out[int(c[0])] = {'name': c[1], 'level': int(c[4] or 0), 'vocations': [vocs[n]['id'] for n in names if n in vocs]}
    return out


ONLINE = LT.ONLINE  # creature id -> bot in game (loadtest's party_step reads the same table)
BAG_EVERY = 240  # seconds between the bag clean-ups (and potion top-ups) of a bot
ROOM_FAILS_BAG = 3  # "not enough room" messages that call a clean-up at once
PING_EVERY = 2.0  # seconds between the pings of a session (the engine kicks 60 s after the last one)
HEAL_SEEN = 3.0  # seconds: a heal or a potion counts ok when the health rises within them
FLEE_AT = 20  # percent of health: under it, with the heal and the potion on cooldown, the bot leaves for the temple
FLEE_REST = 15  # seconds in the temple after a flee, then back to the hunt
SPEAK_RE = re.compile(rb'\xaa[\x00-\xff]{4}[\x00-\xff]{2}')  # a creature speaks: statement id, then its name


class TesterBot(LT.Bot):
    def __init__(self, index, entry, args, n_rsa, results, spells):
        self.index = index
        self.account, self.password, self.name = entry['account'], entry['password'], entry['name']
        self.level = entry.get('level', 1)
        self.cls = entry.get('class', '?')
        self.args, self.n, self.results = args, n_rsa, results
        self.stats = {'no_challenge': 0}
        self.source = '127.1.%d.%d' % (1 + index // 250, 1 + index % 250) if args.host.startswith('127.') else None
        self.conn = None
        self.alive = False
        self.stage = 'start'
        self.cid = 0
        self.guard_wait = 0
        self.abort_at = None
        self.invited_by = []
        self.rotation = spells['rotation']
        self.heal = spells['heal']
        self.ready = {}
        self.sched = TC.Scheduler(index)
        self.last = 'login'
        self.health = 100
        self.health_at = None  # monotonic time of the last health update of its own creature (None: none seen yet)
        self.deaths_at = []  # monotonic times of its deaths (TC.death_rest)
        self.helper = {}
        self.shop = None
        self.kills = []
        self.chunks = {}
        self.died = False
        self.after_death = False
        self.fails = 0
        self.pending = {}  # 'heal_spell' / 'potion' -> until when a health rise counts it as ok
        self.back_at = None  # after a flee: when to go back to the hunt
        self.npc_spoke = False
        self.nothing_to_sell = False
        self.walk_until = 0.0  # until when a blind walk is the likely cause of a "not possible"
        self.room_fails = 0  # "not enough room" since the bag was last emptied (helper "bag")
        self.bag_at = -999.0  # when the bag was last emptied
        self.waiters = []  # (opcode, {actions}, future): requests of the keystone scenario waiting for their answer
        self.class_index = 0  # this bot's place among the bots of its class (the keystone scenario starts there)
        self.keytest_done = False
        self.keytest_flushed = False
        self.stay = False  # the keystone scenario keeps the bot in the temple: no walk back to the hunt
        self.keytest = None  # the KeyTest of this bot: it goes on after a death and a new login (O249)
        self.checks = None  # the CheckRun of this bot (O110): it goes on after a death and a new login
        self.checks_done = False
        self.checks_flushed = False

    # ---------------------------------------------------------------- sessions until the end
    async def run(self, clock):
        pause = 3
        while time.monotonic() < clock['until'] and not clock['stop']:
            entered = await self.session(clock)
            if clock['stop'] or time.monotonic() >= clock['until']:
                break
            if entered:
                pause = 3
            else:
                pause = min(120, pause * 2)  # the server is down or restarting: try again, slower each time
            await asyncio.sleep(pause * (0.5 + random.random()))

    async def session(self, clock):
        try:
            session, world = await self.login_server()
            self.conn = await self.enter_game(session, world)
        except Exception as e:  # noqa: BLE001 - every failure is a result of the test
            self.fails += 1
            if self.fails > 1:
                self.results.d['reconnects'] += 1
            reason = LT.failure_reason(self.stage, e)
            self.results.log(self, 'login', 'failed: %s' % reason)
            if not reason.startswith('timeout') and 'Connection' not in reason:
                self.results.count('kicks', 'login: ' + reason, self)
            return False
        self.results.d['logins'] += 1
        self.results.log(self, 'login', 'in game')
        self.alive, self.died, self.health, self.health_at = True, False, 100, None
        ONLINE[self.cid] = self
        reader = asyncio.ensure_future(self.drain())
        guard = asyncio.ensure_future(self.guard())
        self.conn.send(b'\xA0\x01\x01\x01\x00')  # offensive, chase on, secure mode on (never a player)
        self.say('!tester info')
        if self.after_death:  # a dead tester wakes in the temple and rests there before it goes back to its hunt
            self.after_death = False
            rest = TC.death_rest(self.deaths_at, time.monotonic())
            self.back_at = time.monotonic() + rest
            self.results.log(self, 'do', 'rests %d s in the temple after %d deaths' % (
                rest, len([t for t in self.deaths_at if time.monotonic() - t <= TC.DEATH_WINDOW])))
        if self.args.after_login:
            self.say(self.args.after_login)
        try:
            await self.act(clock)
        finally:
            ONLINE.pop(self.cid, None)
            reader.cancel()
            guard.cancel()
            if self.alive:
                try:
                    self.conn.send(b'\x14')
                    await self.conn.w.drain()
                except Exception:  # noqa: BLE001
                    pass
            self.conn.w.close()
            self.alive = False
        return True

    def say(self, text, kind=1):
        self.conn.send(b'\x96' + bytes([kind]) + LT.string(text))

    # ---------------------------------------------------------------- what the server sends
    async def drain(self):
        last = None
        try:
            while True:
                last = await self.conn.read_message()
                plain = self.conn.decrypt(last)
                if self.guard_wait:
                    nonce = LT.find_challenge(plain)
                    if nonce is not None:
                        self.send_guard_answer(self.conn, nonce)
                    elif time.monotonic() > self.guard_wait:
                        self.guard_wait = 0
                self.read(plain)
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - the server closed the connection
            if self.alive:
                self.alive = False
                text = None
                try:
                    text = LT.disconnect_text(self.conn.decrypt(last)) if last else None
                except Exception:  # noqa: BLE001
                    pass
                if not self.died:
                    self.results.count('kicks', text or 'connection closed without a message', self)

    def read(self, plain):
        if plain[:1] == b'\x28':  # the death window
            self.on_death()
            return
        if self.cid:
            for m in re.finditer(re.escape(b'\x8c' + struct.pack('<I', self.cid)) + rb'([\x00-\x64])', plain):
                before, self.health = self.health, m.group(1)[0]
                seen_at, self.health_at = self.health_at, time.monotonic()
                rule = TC.health_anomaly(before, self.health, False,
                                         None if seen_at is None else self.health_at - seen_at, seen_at is not None)
                if rule:
                    self.results.anomaly(rule, self, health_before=before)
                if self.health > before:
                    for kind in self.pending:  # the heal or the potion worked
                        self.results.behaviour(kind, 'ok', self)
                    self.pending.clear()
        if self.shop_npc and SPEAK_RE.search(plain) and self.shop_npc.encode('latin-1', 'replace') in plain:
            self.npc_spoke = True
        if self.shop_npc and b'carry nothing I buy' in plain:
            self.nothing_to_sell = True
        if self.shop_npc and b'\x7a' in plain:
            items = parse_shop(plain, self.shop_npc)
            if items is not None:
                self.shop = items
        for op, text in extended_messages(plain):
            self.on_extended(op, text)
        for text in TC.strings_of(plain):
            self.on_text(text)

    shop_npc = None

    def on_death(self):
        if self.died:
            return
        self.died = self.after_death = True
        for kind in list(self.pending):  # dead before the heal or the potion could work: the deaths have their section
            self.results.behaviour(kind, 'expected', self)
        self.pending.clear()
        self.deaths_at.append(time.monotonic())
        del self.deaths_at[:-20]
        self.results.d['deaths'] += 1
        self.results.log(self, 'DEATH', 'died while %s' % self.last)
        age = None if self.health_at is None else time.monotonic() - self.health_at
        rule = TC.health_anomaly(self.health, 0, True, age, self.health_at is not None)
        if rule:
            self.results.anomaly(rule, self, health_before=self.health)

    def on_text(self, text):
        kind, detail = TC.classify(text)
        if kind == 'helper':
            hk, data = detail
            self.helper[hk] = data
            if hk == 'info':
                self.level = data.get('level', self.level)
                cid = data.get('cid')
                if isinstance(cid, int) and cid > 0 and cid != self.cid:
                    # the login answer may come after other messages (the client guard's challenge first): without
                    # its own creature id a bot tracks no health, uses no potion and is no party or pm partner
                    ONLINE.pop(self.cid, None)
                    self.cid = cid
                    ONLINE[cid] = self
            if hk == 'error':
                self.results.count('failures', 'helper: ' + str(data.get('err'))[:80], self)
        elif kind == 'lua_error':
            self.results.count('lua_errors', text[:200], self)
        elif kind == 'failure':
            now = time.monotonic()
            if detail == 'not possible' and now < self.walk_until:
                detail = WALKED_INTO  # a blind step into a wall, a counter or a creature: the engine says so
            elif detail == 'not enough room':
                self.room_fails += 1
                if now - self.bag_at < 30:
                    detail = ROOM_AFTER_BAG  # not expected: the bag was emptied a moment ago
            elif detail in ('no mana', 'no soul', 'exhausted') and self.pending:
                # the heal spell (no mana / exhausted) or the potion (exhausted) was not cast: expected, not a heal
                # that did not heal. Exhausted: the newest of the two
                kind_ = 'heal_spell' if detail != 'exhausted' and 'heal_spell' in self.pending else \
                    max(self.pending, key=self.pending.get)
                if detail == 'exhausted' or kind_ == 'heal_spell':
                    del self.pending[kind_]
                    self.results.behaviour(kind_, 'expected', self)
            self.results.count('failures', detail, self)
        elif kind == 'xp':
            rule = TC.xp_anomaly(self.level, detail)
            if rule:
                self.results.anomaly(rule, self, gained=detail)
        elif kind == 'loot':
            rule = TC.gold_anomaly(self.level, detail[1])
            if rule:
                self.results.anomaly(rule, self, monster=detail[0], gold=detail[1])
        elif kind == 'advance':
            self.level = detail[1]
            self.results.log(self, 'advance', text)
        elif kind == 'death':
            self.on_death()

    def on_extended(self, op, text):
        if text[:1] in ('S', 'P', 'E') and not text.startswith('{'):
            if text[0] == 'S':
                self.chunks[op] = text[1:]
                return
            if op not in self.chunks:
                return
            self.chunks[op] += text[1:]
            if text[0] == 'P':
                return
            text = self.chunks.pop(op)
        try:
            msg = json.loads(text)
        except ValueError:
            return
        if not isinstance(msg, dict):
            return
        if op == self.args.ops.get('lootfilter') and msg.get('action') == 'kill':
            data = msg.get('data') or {}
            if data.get('items'):
                self.kills.append(data)
                del self.kills[:-5]
        for w_op, w_actions, fut in list(self.waiters):
            if w_op == op and ('*' in w_actions or msg.get('action') in w_actions) and not fut.done():
                fut.set_result(msg)
        hook = getattr(self.args, 'on_answer', None)
        if hook:
            hook(self, op, msg)

    # ---------------------------------------------------------------- what the bot does
    async def tidy_bag(self):
        """the helper empties the backpack of loot and tops up the potions (`!tester bag`): the bots loot and never sell,
        so the bag fills and every pickup says "There is not enough room." (1225 times in the first live run); the
        supplies were given once, a potion count of 100 does not last 29 deaths"""
        self.results.behaviour('bag', 'tried')
        r = await self.helper_says('bag', 'bag')
        self.bag_at, self.room_fails = time.monotonic(), 0
        if not r or r.get('err'):
            if self.died or not self.alive:
                self.results.behaviour('bag', 'expected', self)
                return False
            return self.failed('bag', r)
        self.results.behaviour('bag', 'ok', self)
        return True

    async def act(self, clock):
        next_ping = next_pick = next_bag = time.monotonic()
        next_bag += BAG_EVERY
        while self.alive and not self.died and time.monotonic() < clock['until'] and not clock['stop']:
            now = time.monotonic()
            if now >= next_ping:
                self.conn.send(b'\x1E')
                next_ping = now + 2
            if (self.room_fails >= ROOM_FAILS_BAG or now >= next_bag) and self.cid:
                next_bag = now + BAG_EVERY
                try:
                    await self.tidy_bag()
                except (ConnectionError, OSError, asyncio.IncompleteReadError):
                    break
            if now >= next_pick:
                name = self.sched.next(now) or 'hunt'
                if getattr(self.args, 'keystones', False) and not self.keytest_done:
                    name = 'keytest'  # before anything else, until it is through (it goes on after a death and a new login)
                elif getattr(self.args, 'checks', False) and not self.checks_done:
                    name = 'checks'  # then the system checks (tester_checks.py)
                self.last = name
                self.results.behaviour(name, 'tried')
                try:
                    ok = await getattr(self, 'do_' + name)(clock)
                except (ConnectionError, OSError, asyncio.IncompleteReadError):
                    break
                # a behaviour cut short by the bot's own death or a dropped connection is not a failure of the system
                # it tried: the deaths and kicks have their sections
                cut = not ok and (self.died or not self.alive)
                self.results.behaviour(name, 'expected' if cut else 'ok' if ok else 'failed', self)
                next_pick = time.monotonic() + 5 + random.random() * 10
            try:
                await self.conn.w.drain()
            except Exception:  # noqa: BLE001
                break
            await asyncio.sleep(0.25)
        if self.died:
            await asyncio.sleep(3)
            self.results.d['relogs'] += 1

    async def guard(self):
        """keep_alive four times a second for the whole session, also while a behaviour waits (a shop visit, a coverage
        scenario at the hunt): the bot heals in every fight, not only between behaviours. Also the ping: the engine logs a
        player out without a message 60 s after its last answer to a ping (Player::sendPing, "no-pong kick"), and
        the ping of act() stops while one behaviour runs long (the keystone scenario waits for minutes): the 65
        "connection closed without a message" of the first live run, the first after keytest"""
        next_ping = 0.0
        while self.alive and not self.died:
            try:
                now = time.monotonic()
                if now >= next_ping:
                    self.conn.send(b'\x1E')
                    next_ping = now + PING_EVERY
                self.keep_alive(now)
            except (ConnectionError, OSError):
                return
            await asyncio.sleep(0.25)

    def keep_alive(self, now):
        """heal by spell under 60 %, by potion (hotkey: use with creature at 0xFFFF on its own id) under 40 %; under
        FLEE_AT % with both on cooldown, back to the temple (as a player's town portal) and to the hunt FLEE_REST
        seconds later; cast the rotation otherwise (not under 50 % with a heal: the mana is for the heal). A heal or a
        potion counts ok when the health rises within HEAL_SEEN seconds, else failed"""
        for kind, until in list(self.pending.items()):
            if now > until:
                del self.pending[kind]
                self.results.behaviour(kind, 'failed', self)
        if self.back_at and now >= self.back_at and not self.stay:
            self.back_at = None
            self.say('!tester hunt')
        if self.health < 60 and self.heal and self.ready.get('heal', 0) <= now \
                and self.ready.get(self.heal['group'], 0) <= now:
            self.say(self.heal['words'])
            self.ready['heal'] = now + max(1.0, self.heal['cooldown'] / 1000.0)
            self.ready[self.heal['group']] = now + self.heal['groupcooldown'] / 1000.0 + 0.1
            self.results.behaviour('heal_spell', 'tried')
            self.pending.setdefault('heal_spell', now + HEAL_SEEN)
        if self.health < 40 and self.ready.get('potion', 0) <= now and self.cid:
            pot = (self.helper.get('info') or {}).get('potions', {}).get('health')
            if pot:
                self.conn.send(b'\x84' + struct.pack('<HHB', 0xFFFF, 0, 0) + struct.pack('<HB', pot, 0)
                               + struct.pack('<I', self.cid))
                self.ready['potion'] = now + 1.1
                self.results.behaviour('potion', 'tried')
                self.pending.setdefault('potion', now + HEAL_SEEN)
        if self.health <= FLEE_AT and not self.back_at and self.ready.get('flee', 0) <= now \
                and self.ready.get('heal', 0) > now and self.ready.get('potion', 0) > now:
            self.say('!tester town')
            self.ready['flee'] = now + 60
            self.back_at = now + FLEE_REST
            self.results.behaviour('flee', 'tried')
            self.results.log(self, 'do', 'flee at %d %% health' % self.health)
            return
        if self.rotation and not (self.health < 50 and self.heal):
            spell = LT.next_spell(self.rotation, self.ready, now)
            if spell:
                self.say(spell['words'])
                self.ready[spell['words']] = now + spell['cooldown'] / 1000.0 + 0.1
                self.ready[spell['group']] = now + spell['groupcooldown'] / 1000.0 + 0.1

    async def helper_says(self, command, kind, wait=4.0):
        self.helper.pop(kind, None)
        self.say('!tester ' + command)
        end = time.monotonic() + wait
        while time.monotonic() < end and self.alive:
            if kind in self.helper:
                return self.helper[kind]
            await asyncio.sleep(0.2)
        return None

    def walk(self, steps):
        self.walk_until = time.monotonic() + 3.0  # a "Sorry, not possible." in this time is a blind step into an obstacle
        for _ in range(steps):
            self.conn.send(bytes([random.choice((0x65, 0x66, 0x67, 0x68))]))

    async def do_hunt(self, clock):
        return True

    async def do_wander(self, clock):
        self.walk(random.randint(2, 5))
        return True

    def failed(self, behaviour, r):
        """False, and why in the failure list: no helper answer, or the helper's own err"""
        if self.died or not self.alive:
            return False  # the bot died (or lost its connection) while it waited: no answer to wait for
        why = r.get('err') if r else 'no helper answer'
        self.results.count('failures', '%s: %s' % (behaviour, why or 'incomplete answer'), self)
        return False

    async def do_town(self, clock):
        r = await self.helper_says('town', 'town')
        if not r or r.get('err'):
            return self.failed('town', r)
        self.walk(4)
        await asyncio.sleep(8)
        r = await self.helper_says('hunt', 'hunt')
        return True if r and not r.get('err') else self.failed('town back to the hunt', r)

    async def do_depot(self, clock):
        r = await self.helper_says('depot', 'depot')
        if not r or r.get('err') or 'locker' not in r:
            return self.failed('depot', r)
        p = r['locker']
        self.conn.send(b'\x82' + struct.pack('<HHB', p['x'], p['y'], p['z']) + struct.pack('<HBB', r['clientId'], r.get('stackpos', 1), 0))
        await asyncio.sleep(3)
        self.conn.send(b'\x87\x00')  # close the container
        await self.helper_says('hunt', 'hunt')
        return True

    async def do_shop(self, clock):
        r = await self.helper_says('shop', 'shop')
        if not r or r.get('err') or not r.get('npc'):
            return self.failed('shop', r)
        self.shop_npc, self.shop, self.npc_spoke, self.nothing_to_sell = r['npc'], None, False, False
        self.say('hi')  # the greeting is a plain say; the NPC then focuses the player
        await asyncio.sleep(1.5)
        # what a player says to a focused NPC goes in the NPC channel (TALKTYPE_PRIVATE_PN): the NPC library
        # (npchandler.lua onCreatureSay) takes a keyword from a focused player only from there, so a plain "trade"
        # after "hi" was ignored and the window never opened (first live run: 0 of 164)
        self.say('trade', NPC_CHANNEL)
        await asyncio.sleep(1.5)
        ok = self.shop is not None  # the trade window opened: what the shop system must do
        if self.shop:
            if any(i.get('unset') for i in self.shop):
                self.results.count('failures', SHOP_UNSET, self)
            buy = [i for i in self.shop if i['buy'] > 0]
            buy = [i for i in buy if 'potion' in i['name'].lower()] or buy
            if buy:
                item = min(buy, key=lambda i: i['buy']) if random.random() < 0.5 else random.choice(buy)
                # purchase: u16 id, u8 sub type, u8 amount, u8 ignore capacity, u8 in backpacks
                self.conn.send(b'\x7a' + struct.pack('<HBBBB', item['id'], item['sub'], 1, 0, 0))
            sell = [i for i in self.shop if i['sell'] > 0]
            if sell and random.random() < 0.5:
                item = random.choice(sell)
                # sale: u16 id, u8 sub type, u8 amount, u8 ignore equipped
                self.conn.send(b'\x7b' + struct.pack('<HBBB', item['id'], item['sub'], 1, 1))
            await asyncio.sleep(1)
            self.conn.send(b'\x7c')
        elif self.nothing_to_sell:
            # the Loot Buyer lists what the player carries and buys: a tester with potions and gold only gets his
            # "You carry nothing I buy" (loot_buyer.lua onTradeRequest). Right answer, counted as expected
            self.results.count('failures', SHOP_NOTHING, self)
            ok = True
        else:
            self.results.count('failures', 'shop: no trade window from %s (%s)' % (
                r['npc'], 'it answered' if self.npc_spoke else 'no answer to hi'), self)
        self.say('bye', NPC_CHANNEL)
        self.shop_npc = None
        await self.helper_says('hunt', 'hunt')
        return ok

    async def do_party(self, clock):
        self.party_step()
        return True

    def other(self):
        ids = [cid for cid in ONLINE if cid != self.cid]
        return ONLINE[random.choice(ids)] if ids else None

    def count(self, key):
        self.results.behaviour('party_' + key, 'tried')

    async def do_pm(self, clock):
        other = self.other()
        if not other:
            return False
        self.conn.send(b'\x96\x05' + LT.string(other.name) + LT.string(random.choice(LT.WORDS)))
        return True

    async def do_opcodes(self, clock):
        """a scenario of the coverage layer (tester_scenarios.py): its steps with a pause between them"""
        runner = getattr(self.args, 'scenarios_runner', None)
        steps = self.args.next_request(self) if self.args.next_request else None
        if not steps or not runner:
            return False

        def send_ext(op, payload):
            self.conn.send(b'\x32' + bytes([op]) + LT.string(payload))

        def use_hotkey(client_id):
            self.conn.send(b'\x82' + struct.pack('<HHB', 0xFFFF, 0, 0) + struct.pack('<HBB', client_id, 0, 0))

        for step in steps:
            if not self.alive or self.died or clock['stop']:
                break
            self.last = 'opcodes:' + ' '.join(str(x) for x in step)[:60]
            runner.run_step(self, step, ONLINE, send_ext, self.say, use_hotkey)
            await self.conn.w.drain()
            await asyncio.sleep(getattr(runner, 'pause', 1.5))
        return True

    async def do_keytest(self, clock):
        """the keystone and mastery scenario (tester_keystones.py): True when no node failed. The same KeyTest goes on
        after a death and a new login (a node cut off by it is done again); the bot waits in the temple, and walks to
        its hunt only for a keystone that needs hits. Done (keytest_done) when every node of its class has its result."""
        table = (getattr(self.args, 'keytest_table', None) or {})
        if not table.get('classes'):
            self.keytest_done = True
            return self.failed('keytest', {'err': 'no keytest section in the scenarios file (gen_tester_scenarios.py)'})
        first = self.keytest is None
        if first:
            self.keytest = TK.KeyTest(table, self.name, self.class_index)
        test = self.keytest
        io = KeyIO(self, clock)
        await asyncio.sleep(15 if first else 3)  # the helper's supplies; after a login the temple
        await io.go('town')
        mark, rmark = len(test.results), len(test.resets)
        try:
            await test.run(io)
        finally:
            self.stay = False
            for r in test.results[mark:]:
                self.results.log(self, 'KEYTEST', '%s %s: %s' % (r['status'].upper(), r['what'], r['detail']))
        if test.finished:
            self.flush_keytest()
            return not any(r['status'] == TK.FAIL for r in test.results)
        return True  # cut off (died, left): the next pick continues; its results are kept in the KeyTest

    def flush_keytest(self, why=None):
        """the results of the KeyTest into the run's results, once; with why: the nodes it did not get to are not tested"""
        test = self.keytest
        if test is None or self.keytest_flushed:
            return
        if why and not test.finished:
            test.finish(why)
        if test.finished:
            self.keytest_flushed = self.keytest_done = True
            d = self.results.d
            d.setdefault('keytest', []).extend(test.results)
            d.setdefault('keytest_resets', []).extend(test.resets)

    async def do_checks(self, clock):
        """the system checks of the bot's class (tester_checks.py): True when none failed. Goes on after a death and a new
        login; a failed check is logged as a BUG line at once"""
        first = self.checks is None
        if first:
            self.checks = TX.CheckRun(self.name, self.cls, self.level)
        run = self.checks
        io = CheckIO(self, clock)
        await asyncio.sleep(10 if first else 3)
        mark = len(run.results)
        try:
            await run.run(io)
        finally:
            self.stay = False
            for r in run.results[mark:]:
                self.results.log(self, 'CHECK', '%s %s%s' % (r.status.upper(), r.check, ': ' + r.detail if r.detail else ''))
                line = r.bug_line()
                if line:
                    self.results.log(self, 'BUG', line)
        if run.finished:
            self.flush_checks()
            return not any(r.status == TX.FAIL for r in run.results)
        return True

    def flush_checks(self):
        run = self.checks
        if run is None or self.checks_flushed:
            return
        if run.finished:
            self.checks_flushed = self.checks_done = True
            self.results.d.setdefault('checks', []).extend(r.as_dict() for r in run.results)

    async def do_loot(self, clock):
        lf = self.args.ops.get('lootfilter')
        if self.kills and lf:
            k = self.kills.pop()
            for n, item in enumerate(k.get('items') or [], 1):
                msg = {'action': 'take', 'data': {'k': k.get('k'), 'n': item.get('n', n), 'id': item.get('id'), 'one': False}}
                self.conn.send(b'\x32' + bytes([lf]) + LT.string(json.dumps(msg, separators=(',', ':'))))
        # open the own backpack (use the item in the backpack slot)
        bp = self.args.backpack_client_id
        if bp:
            self.conn.send(b'\x82' + struct.pack('<HHB', 0xFFFF, 3, 0) + struct.pack('<HBB', bp, 0, 0))
        return True

    async def do_relog(self, clock):
        self.conn.send(b'\x14')  # logout; act() ends, session() closes, run() logs in again
        await self.conn.w.drain()
        self.alive = False
        self.results.d['relogs'] += 1
        return True


# ------------------------------------------------------------------------------------------------ run
def class_spells(spells, model, vocation, level):
    """{'rotation': attack and support spells (loadtest.rotation_for), 'heal': the best healing spell (or None)}"""
    rot = LT.rotation_for(spells, model, vocation, level)
    heals = [s for s in spells if s['group'] == 'healing' and s['level'] <= level and not s['needlearn']
             and not s['params'] and (not s['vocations'] or vocation in s['vocations'])]
    heals.sort(key=lambda s: (-s['level'], s['words']))
    return {'rotation': rot, 'heal': heals[0] if heals else None}


def load_ops(server_dir):
    path = os.path.join(server_dir, 'data', 'scripts', 'chaos', 'chaos_constants.lua')
    out = {}
    try:
        text = LT.read_text(path)
    except OSError:
        return out
    m = re.search(r'ChaosOpcodes = \{(.*?)\n\}', text, re.S)
    for k, v in re.findall(r'^\s*(\w+) = (\d+)', m.group(1) if m else '', re.M):
        out[k] = int(v)
    for k, v in re.findall(r'^ChaosOpcodes\.(\w+) = (\d+)', text, re.M):
        out[k] = int(v)
    return out


async def run_bots(a, entries):
    n = LT.modulus_from_pem(a.rsa_key) if a.rsa_key else LT.OT_RSA_N
    data = os.path.join(a.server_dir, 'data')
    spells = LT.parse_spells(LT.read_text(os.path.join(data, 'spells', 'spells.xml')))
    vocs = LT.parse_vocations(LT.read_text(os.path.join(data, 'XML', 'vocations.xml')))
    by_id = {v['id']: name for name, v in vocs.items()}
    model_path = os.path.join(HERE, '..', 'data', 'spells', 'rotation_model.csv')
    model = LT.parse_rotation_model(LT.read_text(model_path)) if os.path.exists(model_path) else {}
    results = Results(len(entries), a.activity)
    clock = {'until': time.monotonic() + a.minutes * 60, 'stop': False}
    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, lambda: clock.update(stop=True))
        except (NotImplementedError, RuntimeError):
            pass
    bots = []
    seen_class = {}
    for i, e in enumerate(entries):
        bots.append(TesterBot(i, e, a, n, results, class_spells(spells, model, by_id.get(e['vocation'], ''), e['level'])))
        bots[-1].class_index = seen_class.get(e.get('class'), 0)
        seen_class[e.get('class')] = bots[-1].class_index + 1
    saver = asyncio.ensure_future(save_results_loop(a, results))
    tasks = []
    for bot in bots:
        if clock['stop']:
            break
        tasks.append(asyncio.ensure_future(bot.run(clock)))
        await asyncio.sleep(a.ramp)
    await asyncio.gather(*tasks)
    for bot in bots:
        bot.flush_keytest('the run ended before the bot was through: it was out of the game or dead')
        if bot.checks is not None and not bot.checks_flushed:
            bot.checks_flushed = True   # what it got through is kept; the rest was not run
            results.d.setdefault('checks', []).extend(r.as_dict() for r in bot.checks.results)
    saver.cancel()
    results.d['ended'] = time.strftime('%Y-%m-%d %H:%M:%S')
    save_results(a, results)
    results.close()
    # the report of the run, written next to its activity log (the server log is read up to now)
    try:
        write_private(a.activity[:-len('.log')] + '-report.txt', report_text(a))
    except Exception as e:  # noqa: BLE001 - the run itself is over and saved; the owner can still run report
        print('report file not written: %s' % e, flush=True)
    print('run over: %d logins, %d deaths, %d kicks kinds; report: testers.py report' % (
        results.d['logins'], results.d['deaths'], len(results.d['kicks'])), flush=True)


ONLINE_FRESH = 90  # seconds: an older online count in run.json is from a run that is no longer saving (status says 0)


def save_results(a, results):
    n = len(ONLINE)
    results.d['online'] = n
    results.d['online_at'] = int(time.time())
    results.d['online_peak'] = max(n, results.d.get('online_peak', 0))
    write_private(os.path.join(a.state, 'run.json'), json.dumps(results.d, indent=1, sort_keys=True))


async def save_results_loop(a, results):
    tick = 0
    while True:
        await asyncio.sleep(15)
        save_results(a, results)
        tick += 1
        if tick % 4 == 0:  # once a minute the activity log gets the count too
            results.log(None, 'online', '%d testers in game (peak %d)' % (results.d['online'], results.d['online_peak']))


def run(a):
    if a.count is not None and not 1 <= a.count <= TC.MAX_BOTS:
        sys.exit('--count 1..%d' % TC.MAX_BOTS)
    if not 1 <= a.minutes <= 24 * 60:
        sys.exit('--minutes 1..1440')
    cfg_path = os.path.join(a.server_dir, 'config.lua')
    cfg = LT.read_text(cfg_path) if os.path.exists(cfg_path) else ''
    if dev_key_allowed(cfg):
        sys.exit('config.lua has clientGuardAllowDevKey = true: never on the live server; the testers refuse to run')
    if a.host.startswith('127.') and binds_only_global(cfg):
        sys.exit('config.lua has bindOnlyGlobalAddress = true: the bots cannot connect over 127.x (give --host)')
    a.guard_key = read_key_file(a.key_file)
    a.client_build = guard_build(cfg, lambda path: LT.read_text(os.path.join(a.server_dir, path)))
    print('client build %d (clientGuardBuilds / min_package of clientGuardManifest)' % a.client_build, flush=True)
    a.client_id = LT.GUARD_TAG << 16 | a.client_build
    a.no_source_ips = False
    a.game_port = 0
    a.login_timeout = 30.0
    a.ops = load_ops(a.server_dir)
    a.next_request = None
    a.on_answer = None
    a.scenarios_runner = None
    a.keytest_table = {}
    a.checks_rotation = None
    a.checks_spells = {}
    if a.checks:
        rot = os.path.join(HERE, '..', '..', 'client', 'overlay', 'modules', 'game_helperrotation', 'autorotation_data.lua')
        if os.path.exists(rot):
            a.checks_rotation = TX.load_table(rot)
        vocs = LT.parse_vocations(LT.read_text(os.path.join(a.server_dir, 'data', 'XML', 'vocations.xml')))
        a.checks_spells = load_check_spells(a.server_dir, vocs)
    a.backpack_client_id = 0
    a.after_login = ''
    if a.scenarios:
        import tester_scenarios as TS  # the coverage layer (server/tools/tester_scenarios.py)
        TS.attach(a, a.scenarios)
        a.keytest_table = TS.load(a.scenarios).get('keytest') or {}
    if a.keystones and not a.scenarios:
        sys.exit('--keystones needs --scenarios tester_scenarios.json (the table of keystones and masteries)')
    st = load_state(a.state)
    entries = [b for b in st.get('bots', []) if b.get('player_id') and safe_name(b['name']) and safe_account(b['account'])]
    if not entries:
        sys.exit('no testers in %s: run setup first' % state_path(a.state))
    entries = entries[:min(a.count or len(entries), TC.MAX_BOTS)]
    if a.rsa_key == '':
        # the login key the server really uses (rsaKeyFile, patch 0046), not key.pem: with another key every login block
        # is unreadable and the server closes the connection without a word
        path, configured = login_key_file(cfg, a.server_dir)
        if os.path.exists(path):
            a.rsa_key = path
        elif configured:
            sys.exit('the login key of rsaKeyFile is missing: %s' % path)
    print('login key %s' % (a.rsa_key or 'the standard open-server key'), flush=True)
    stamp = time.strftime('%Y%m%d-%H%M%S')
    a.activity = os.path.join(a.state, 'runs', 'run-%s.log' % stamp)
    prune_runs(os.path.join(a.state, 'runs'), KEEP_RUNS - 1)
    st['run'] = {'started': int(time.time()), 'minutes': a.minutes, 'count': len(entries), 'log': a.log,
                 'activity': a.activity,
                 'log_offset': os.path.getsize(a.log) if a.log and os.path.exists(a.log) else 0,
                 'scenarios': os.path.abspath(a.scenarios) if a.scenarios else ''}
    save_state(a.state, st)
    print('%d testers for %d minutes (Ctrl+C or SIGTERM ends early)' % (len(entries), a.minutes), flush=True)
    asyncio.run(run_bots(a, entries))


# ------------------------------------------------------------------------------------------------ report
def read_log_since(path, offset):
    if not path or not os.path.exists(path):
        return []
    size = os.path.getsize(path)
    with open(path, 'rb') as f:
        if offset <= size:
            f.seek(offset)
        return f.read().decode('utf-8', 'replace').splitlines()


KEEP_RUNS = 20  # runs kept in runs/ (activity log and report each)


def prune_runs(folder, keep):
    """keep the newest `keep` runs of runs/ (run-<stamp>.log and run-<stamp>-report.txt)"""
    try:
        names = os.listdir(folder)
    except OSError:
        return
    stamps = sorted({n[4:19] for n in names if re.match(r'^run-\d{8}-\d{6}(\.log|-report\.txt)$', n)})
    for old in stamps[:max(0, len(stamps) - keep)]:
        for n in ('run-%s.log' % old, 'run-%s-report.txt' % old):
            try:
                os.remove(os.path.join(folder, n))
            except OSError:
                pass


def report(a):
    sys.stdout.write(report_text(a))


def report_text(a):
    st = load_state(a.state)
    r = st.get('run') or {}
    try:
        with open(os.path.join(a.state, 'run.json')) as f:
            res = json.load(f)
    except (OSError, ValueError):
        res = {}
    log = a.log or r.get('log') or ''
    lines = read_log_since(log, int(r.get('log_offset', 0)))
    parsed = TC.parse_log(lines)
    table = a.scenarios or r.get('scenarios') or ''
    if table and os.path.exists(table):
        import tester_scenarios as TS  # the per-system coverage: tried, ok, refused, log errors, never reached and why
        res['coverage'] = TS.merge(TS.load(table), res.get('coverage') or {}, parsed)
    text = TC.build_report(res, parsed)
    if not log:
        text += '(no server log given: --log)\n'
    if r.get('activity'):
        text += 'every action and error of the run: %s (chaos-ctl.sh testers log)\n' % r['activity']
    return text


def status(a):
    """key=value lines for chaos-ctl.sh testers status: testers in the state, the last run's numbers"""
    st = load_state(a.state)
    r = st.get('run') or {}
    try:
        with open(os.path.join(a.state, 'run.json')) as f:
            res = json.load(f)
    except (OSError, ValueError):
        res = {}
    print('bots=%d' % len([b for b in st.get('bots', []) if b.get('player_id')]))
    print('minutes=%s' % r.get('minutes', ''))
    fresh = time.time() - int(res.get('online_at', 0) or 0) <= ONLINE_FRESH
    print('online=%d' % (int(res.get('online', 0) or 0) if fresh else 0))
    print('online_peak=%s' % res.get('online_peak', 0))
    print('logins=%s' % res.get('logins', 0))
    print('deaths=%s' % res.get('deaths', 0))


# ------------------------------------------------------------------------------------------------ main
class Args:
    pass


def parse(argv):
    if not argv or argv[0] not in ('setup', 'run', 'report', 'cleanup', 'status'):
        print(__doc__)
        sys.exit(2)
    a = Args()
    a.cmd = argv[0]
    defaults = {'--count': TC.DEFAULT_BOTS if a.cmd == 'setup' else None, '--state': DEFAULT_STATE, '--server-dir': '',
                '--levels': ','.join(str(v) for v in LEVELS), '--classes': 'auto', '--hash-iterations': 120000, '--town': 1,
                '--minutes': TC.DEFAULT_MINUTES, '--host': '127.0.0.1', '--port': 7171, '--log': '',
                '--key-file': '', '--rsa-key': '', '--scenarios': '', '--ramp': 1.0, '--kick-wait': KICK_WAIT}
    types = {'--count': int, '--hash-iterations': int, '--town': int, '--minutes': int, '--port': int, '--ramp': float, '--kick-wait': int}
    vals = dict(defaults)
    flags = {'--yes': False, '--dry-run': False, '--keystones': False, '--checks': False}
    i = 1
    while i < len(argv):
        k = argv[i]
        if k in flags:
            flags[k] = True
        elif k in vals and i + 1 < len(argv):
            try:
                vals[k] = types.get(k, str)(argv[i + 1])
            except ValueError:
                sys.exit('%s: not a number' % k)
            i += 1
        elif k in ('--client-key', '--dev-key'):
            sys.exit('%s: the testers read the key only from --key-file (a root-only file), never the command line' % k)
        else:
            sys.exit('unknown option %s' % k)
        i += 1
    for k, v in vals.items():
        setattr(a, k.lstrip('-').replace('-', '_'), v)
    a.yes, a.dry, a.keystones, a.checks = flags['--yes'], flags['--dry-run'], flags['--keystones'], flags['--checks']
    if a.hash_iterations < 1:
        sys.exit('--hash-iterations: at least 1 (as the server passwordHashIterations); testers never use SHA-1')
    if a.cmd in ('setup', 'run') and not a.server_dir:
        sys.exit('--server-dir SERVER (the installed server folder) is required')
    if a.cmd == 'run' and not a.key_file:
        sys.exit('--key-file FILE is required (server/README.md "Tester bots")')
    return a


def main(argv):
    a = parse(argv)
    {'setup': setup, 'run': run, 'report': report, 'cleanup': cleanup, 'status': status}[a.cmd](a)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
