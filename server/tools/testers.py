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
--journey (O654, tester_journey.py, helper v20; setup --journey --levels 8 makes the characters in the temple of Cinderhold): the bots level
from their level onward on foot, like a person: they read the next hunt of their level (`!tester journey`), walk to the temple's teleport, the
hall's stairs and the hunt's teleport by the engine path, hunt, move on when the level has outgrown the hunt, go back to town by the Town Portal,
sell, buy potions and open the depot on a trip, die and go on from the temple. Minutes per level are in the report against progression_model.lua
--curve-json; every helper teleport in place of walking is counted with its reason. A run of its own: not with --keystones, --checks or --closed.
--closed (O582, tester_closed.py; the switch data/chaos_testers_closed must be on): closed test mode. Two tester guilds are made
before the bots log in; the bots then run the closed checks (arena, battleground, the Marches, guild war, market, the bazaar
lock, the guards the server runs) among themselves, never with a player, and play the raid like a party of people (walk, fight, loot,
leave: closed_raid, O588). The guilds, wars, tester market book, arena records and raid rows
of the run are removed when it ends, and by cleanup.
--no-gear (O658): the checks run without the gear-up (tester_checks.py gear_up: before the hard checks a bot wears its best pieces, buys potions
and basic pieces at the shops on foot, a TEST ONLY gold grant as the named fallback); the gearless run of before, for a comparison.
--video [--prep-minutes N] (O689, tools/ci/boss_video.sh; with --checks --closed --only pinnacle_party): the run of the boss fight video. The bots never hunt and never run
the free activities (a bot whose check is done waits in the temple), a member waits for its leader to the end, the leader tries the gather again (every bot alive and in
the temple first) inside N minutes (default 120), a member that dies in the prep waits for its next login and its prep goes on, the trials of the prep are the
helper's TEST ONLY grant, not a fight. A death line names the last hits the server sent. The normal closed audit is unchanged.
--retreat-at N (O662): the bots retreat under N percent health instead of 30 (a timid player): the scenario that forces a second retreat in a loop, so the
raid's Leave button and the Town Portal refusal inside a dungeon are asked live (tester_checks.py retreat_at).
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
import tester_closed as TCL  # noqa: E402  (closed test mode, O582)
import tester_journey as TJ  # noqa: E402  (the levelling journey on foot, O654)
import tester_weapons as TW  # noqa: E402  (what a weapon is worth to a class's spells, O665)

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
                  "SELECT '%s', `id`, 1, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, "
                  "UNIX_TIMESTAMP() - 86400, 128 FROM `accounts` WHERE `name` = '%s';"
                  % (b['name'], b['vocation'], b['level'], b['hp'], b['hp'], LT.exp_for_level(b['level']), b['mana'],
                     b['mana'], b['ml'], b['skill'], b['skill'], b['skill'], b['skill'], b['skill'], b['skill'],
                     b.get('cap', 3000), b['town'], b['pos'][0], b['pos'][1], b['pos'][2], b['account']))
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
        wcfg = os.path.join(data, 'scripts', 'chaos', 'waystone_tiers_config.lua')
        blocked = LT.waystone_areas(LT.read_text(wcfg)) if os.path.isfile(wcfg) else ()
        centres = LT.spawn_levels(LT.read_text(spawns[0]), LT.pool_levels(LT.read_text(pool)), blocked=blocked)
    elif spawns:
        print('no data/scripts/chaos/bounty_pool.lua: the testers are not kept off spawns above their level')
    positions = place_testers([lv for _, lv in plan], hunts, temples, index, centres)
    if a.journey:   # O654: the characters begin where a new one does, in the temple of Cinderhold; the journey takes them to the hunts
        positions = [TJ.start_position(temples) for _ in plan]
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
                     'skill': skill, 'town': a.town, 'pos': list(positions[k]),
                     # O656: the capacity of a real character of that level (17970 at level 8, the class's gaincap a level); 3000 for every level
                     # ran out (0) after enough deaths, each one takes a level and its gaincap, and a bot could carry nothing: "You do not have enough capacity"
                     'cap': 17970 + max(0, level - 8) * int(vocs[cls].get('cap', 20))})
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


# ------------------------------------------------------------------------------------------------ closed test mode (O582)
def closed_start(a, entries, st):
    """--closed: only with the switch on (data/chaos_testers_closed); leftovers of an older run go, then the two tester guilds are
    made before the bots log in (the engine loads a guild at login). The plan is kept in the state and in a.closed_plan"""
    if not TCL.flag_on(a.server_dir):
        sys.exit('closed test mode is off: chaos-ctl.sh testers closed on (data/chaos_testers_closed)')
    ids = [int(b['player_id']) for b in entries if b.get('player_id')]
    sql(closed_clean(ids))
    a.closed_plan = TCL.plan([b['name'] for b in entries])
    if a.closed_plan['guilds']:
        sql(TCL.guild_statements(a.closed_plan))
    st['closed'] = {'guilds': [g['name'] for g in a.closed_plan['guilds']], 'at': int(time.time())}
    save_state(a.state, st)
    print('closed test mode: %s' % (', '.join('%s (%d members)' % (g['name'], len(g['members'])) for g in a.closed_plan['guilds'])
                                    or 'no guilds (fewer than %d bots per guild)' % TCL.MIN_MEMBERS), flush=True)


def closed_tables():
    """the names of the tables closed mode touches that exist now"""
    out = rows(sql(["SELECT `TABLE_NAME` FROM `information_schema`.`TABLES` WHERE `TABLE_SCHEMA` = DATABASE() AND "
                    "(`TABLE_NAME` LIKE 'chaos\\_%' OR `TABLE_NAME` LIKE 'guild%');"]))
    return {r[0] for r in out if r}


def closed_clean(ids):
    return TCL.clean_statements(closed_tables(), ids)


def closed_finish(a, entries):
    """the run is over: the guilds, wars, tester market book and tester arena records it made go"""
    try:
        sql(closed_clean([int(b['player_id']) for b in entries if b.get('player_id')]))
        print('closed test mode: guilds, orders and arena records of the run removed', flush=True)
    except (SystemExit, OSError, subprocess.SubprocessError) as e:
        print('closed test mode: the clean-up failed (%s): testers cleanup --yes removes them' % e, flush=True)


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
    stmts = closed_clean(players) + cleanup_statements(tables, players, accounts, has_houses)
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
    at = 0
    while True:
        m = EXT_RE.search(plain, at)
        if m is None:
            break
        n = struct.unpack('<H', m.group(2))[0]
        body = plain[m.end():m.end() + n]
        if n and len(body) == n and body[:1] in (b'{', b'[', b'S', b'P', b'E'):
            out.append((m.group(1)[0], body.decode('latin-1')))
            at = m.end() + n
        else:
            # O661: a 0x32 byte of another message (an item id of a map update) is no header; the scan goes on one byte after it. It went on after the
            # four bytes of the false header (finditer), which swallowed the real header that followed a 0x32: the first answer of a window that
            # came right after a map update was lost for the bots (the hideout's first `place`, 3 of 3 fresh rooms)
            at = m.start() + 1
    return out


def parse_modal(plain, ids):
    """[{id, title, message, buttons: [(id, text)], choices: [(id, text)], escape, enter}] of the modal windows (0xfa: u32 id, title, message, u8 buttons
    {text, u8 id}, u8 choices {text, u8 id}, u8 escape, u8 enter, u8 priority) in a decrypted message whose id is one of `ids` (O655: the bots know the
    ids of the windows of the Oracle and of Archivist Maelis from the server's settings, the message is not framed by packets here)"""
    out = []
    for wid in ids:
        key = b'\xfa' + struct.pack('<I', wid)
        at = plain.find(key)
        while at >= 0:
            i = at + 5
            try:
                def text(i):
                    n = struct.unpack_from('<H', plain, i)[0]
                    if i + 2 + n > len(plain):
                        raise IndexError
                    return plain[i + 2:i + 2 + n].decode('latin-1'), i + 2 + n
                title, i = text(i)
                message, i = text(i)
                nb = plain[i]
                i += 1
                buttons = []
                for _ in range(nb):
                    t, i = text(i)
                    buttons.append((plain[i], t))
                    i += 1
                nc = plain[i]
                i += 1
                choices = []
                for _ in range(nc):
                    t, i = text(i)
                    choices.append((plain[i], t))
                    i += 1
                out.append({'id': wid, 'title': title, 'message': message, 'buttons': buttons, 'choices': choices, 'escape': plain[i], 'enter': plain[i + 1]})
            except (struct.error, IndexError):
                pass
            at = plain.find(key, at + 1)
    return out


MODAL_IDS = (7101, 7102) + tuple(range(7111, 7150)) + (7170, 7171)   # O655: the Oracle's trial, choice and confirm windows (ascension_quest_config.lua modal), the tales (tales_config.lua)
MODAL_IDS = MODAL_IDS + (5000,)   # O662: the waypoint window of the base script (customs/waypoints/waypoint.lua: choices by town, button 110 Select)
MODAL_IDS = MODAL_IDS + (7490,)   # O667: the Keeper of the Pinnacle's window of the four bosses (pinnacle_config.lua modal.list)

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

    # seconds an answer of the helper took: the buckets of the report's "Helper answers" line
    HELPER_BUCKETS = (1.0, 2.0, 4.0, 8.0)

    def helper_answer(self, outcome, seconds=None):
        """outcome: 'answered' (with the seconds it took), 'late' (an answer after its wait, dropped), 'lost' (no answer in time
        from a bot that was still there). Why: the first live run of 100 bots read "no helper answer" in 4 % of the commands,
        and no way to tell a busy server from a helper that never answered (O579)"""
        h = self.d.setdefault('helper', {'answered': 0, 'late': 0, 'lost': 0, 'slow': [0] * (len(self.HELPER_BUCKETS) + 1),
                                         'max_s': 0.0})
        if outcome == 'late' or outcome == 'lost':
            h[outcome] += 1
        else:
            h['answered'] += 1
        if seconds is not None:
            i = 0
            while i < len(self.HELPER_BUCKETS) and seconds >= self.HELPER_BUCKETS[i]:
                i += 1
            h['slow'][i] += 1
            h['max_s'] = round(max(h['max_s'], seconds), 1)

    def keep(self, key, n=1):
        """the bag keeping counters of the report's "Bag keeping" line (O584)"""
        k = self.d.setdefault('keep', {})
        k[key] = k.get(key, 0) + n

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
        self.go_err = None
        self.formed = None

    def alive(self):
        return bool(self.bot.alive and not self.bot.died and not self.clock['stop'])

    async def go(self, place):
        """the temple ('town') or the hunt spot ('hunt') through the helper; True when it answered without an error"""
        if not self.alive():
            return False
        self.bot.stay = place == 'town'
        r = await self.bot.helper_says(place, place)
        self.go_err = (r.get('err') if r else 'no helper answer') or None
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
        # O660: a person clicks no faster than the windows answer: the server drops a request that follows another of the same window within
        # its rate limit (Chaos.limited / ChaosRateLimit: 250 to 300 ms for the Gambler, the hideout edits, the supports ...), unanswered
        sent = bot.__dict__.setdefault('req_at', {})
        late = sent.get(op, -999.0) + REQUEST_GAP - time.monotonic()
        if late > 0:
            await asyncio.sleep(late)
        sent[op] = time.monotonic()
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


REQUEST_GAP = 0.35   # O660: seconds between two requests of the same opcode (one window): above the 250 and 300 ms rate limits of the windows


STEP_BYTES = {(0, -1): 0x65, (1, 0): 0x66, (0, 1): 0x67, (-1, 0): 0x68,   # the walk packets: north, east, south, west
              (1, -1): 0x6A, (1, 1): 0x6B, (-1, 1): 0x6C, (-1, -1): 0x6D}   # O683: northeast, southeast, southwest, northwest (a dodge runs off a mark in a line)


class CheckIO(KeyIO):
    """what tester_checks.CheckRun needs of a bot in game (KeyIO's requests and pauses, plus the helper, speech and parties)"""

    async def helper(self, command, kind, wait=4.0):
        if not self.alive():
            return None
        return await self.bot.helper_says(command, kind, wait)

    async def open_bag(self, client_id):
        """the own backpack as container 0 (a position inside it is (0xFFFF, 0x40, slot)); nothing without the client id"""
        if self.alive() and client_id:
            self.bot.conn.send(TC.use_packet((0xFFFF, 3, 0), int(client_id)))
            await self.bot.conn.w.drain()

    async def use_item(self, client_id):
        """uses an item the character carries by its client id, as a hotkey does (0x82 with the position 0xFFFF: a rift key, O592)"""
        if self.alive() and client_id:
            self.bot.conn.send(TC.use_packet((0xFFFF, 0, 0), int(client_id)))
            await self.bot.conn.w.drain()
            return True
        return False

    async def use_at(self, pos, client_id, stack=1):
        """uses an item that lies on a map tile (a ladder of a rift, O651) by its position, client id and place in the tile's stack: the
        packet a click on it sends, from the tile next to it"""
        if self.alive() and client_id and isinstance(pos, (tuple, list)) and len(pos) == 3:
            self.bot.conn.send(TC.use_packet((int(pos[0]), int(pos[1]), int(pos[2])), int(client_id), int(stack or 0)))
            await self.bot.conn.w.drain()
            return True
        return False

    async def use_with(self, from_slot, from_sprite, to_slot, to_sprite):
        """use the backpack item in from_slot on the one in to_slot (a gem on a piece of gear)"""
        if self.alive():
            self.bot.conn.send(TC.use_with_packet((0xFFFF, 0x40, from_slot), int(from_sprite), from_slot,
                                                  (0xFFFF, 0x40, to_slot), int(to_sprite), to_slot))
            await self.bot.conn.w.drain()

    async def wear(self, index, client_id, slot):
        """moves the backpack item in slot `index` to the equipment slot `slot` (a person drags a piece onto the paper doll, O653)"""
        if self.alive():
            self.bot.conn.send(TC.move_packet((0xFFFF, 0x40, int(index)), int(client_id), int(index), (0xFFFF, int(slot), 0), 1))
            await self.bot.conn.w.drain()

    async def say(self, text):
        if self.alive():
            self.bot.say(text)
            await self.bot.conn.w.drain()

    # ---- O655: what a person sees and answers in a talk: the server's text lines, a modal window, a purchase
    async def said_and_heard(self, text, wait=1.5, kind=1):
        """says `text` (a spell's words, a word to an NPC) and returns the server's text lines of the next `wait` seconds"""
        if not self.alive():
            return []
        n0 = self.bot.recent_n
        self.bot.say(text, kind)
        await self.bot.conn.w.drain()
        await asyncio.sleep(wait)
        new = min(self.bot.recent_n - n0, len(self.bot.recent))
        return list(self.bot.recent[-new:]) if new > 0 else []

    async def say_modal(self, text, ids, wait=5.0, kind=1):
        """says `text` to an NPC and waits for a modal window with one of `ids`: (the window dict of parse_modal or None, the server's text lines meanwhile)"""
        if not self.alive():
            return None, []
        self.bot.modals.clear()
        n0 = self.bot.recent_n
        self.bot.say(text, kind)
        await self.bot.conn.w.drain()
        found, end = None, time.monotonic() + wait
        while found is None and time.monotonic() < end and self.alive():
            for w in reversed(self.bot.modals):
                if w['id'] in ids:
                    found = w
                    break
            if found is None:
                await asyncio.sleep(0.2)
        new = min(self.bot.recent_n - n0, len(self.bot.recent))
        return found, (list(self.bot.recent[-new:]) if new > 0 else [])

    async def modal_answer(self, window_id, button, choice, wait=1.5, ids=()):
        """presses a button of a modal window (with the choice picked: 0 for none); waits `wait` seconds and returns (the next window with one of `ids`
        or None, the server's text lines meanwhile)"""
        if not self.alive():
            return None, []
        self.bot.modals.clear()
        n0 = self.bot.recent_n
        self.bot.conn.send(TC.modal_answer_packet(window_id, button, choice))
        await self.bot.conn.w.drain()
        found, end = None, time.monotonic() + wait
        while time.monotonic() < end and self.alive():
            for w in reversed(self.bot.modals):
                if w['id'] in ids:
                    found = w
                    break
            if found is not None:
                break
            await asyncio.sleep(0.2)
        new = min(self.bot.recent_n - n0, len(self.bot.recent))
        return found, (list(self.bot.recent[-new:]) if new > 0 else [])

    def note(self, text):
        """O689: a line of the activity log (kind RETRY) from a check: what the video run tries again and why"""
        self.bot.results.log(self.bot, 'RETRY', text)

    def class_spells(self):
        """the spells of this bot's class as parsed from the spell file (words, name, group, level, needlearn, params, needtarget): what the class lists"""
        return list(getattr(self.bot, 'all_spells', None) or [])

    async def shop_window(self, npc, wait=5.0):
        """says hi and trade to the NPC and waits for its trade window: the items [{id (client id), name, buy, sell}] or None"""
        bot = self.bot
        bot.shop_npc, bot.shop = npc, None
        await self.say('hi')
        await asyncio.sleep(1.5)
        if self.alive():   # O656: the words to a greeted NPC go in the NPC channel (a plain "trade" after "hi" is ignored by the NPC library)
            self.bot.say('trade', NPC_CHANNEL)
            await self.bot.conn.w.drain()
        end = time.monotonic() + wait
        while bot.shop is None and time.monotonic() < end and self.alive():
            await asyncio.sleep(0.2)
        return bot.shop

    def shop_close(self):
        self.bot.shop_npc = None

    # ---- O658: what the retreat of the play loops reads and does (tester_checks.py retreat_check)
    @property
    def health(self):
        """the bot's own health in percent (its creature's health updates), None while none was seen"""
        return self.bot.health if self.bot.health_at is not None else None

    async def heal_now(self):
        """a person under a third of his health drinks or casts a heal: the bot's own heal spell when it is ready, else the stock health potion
        (the packet of the heal rule, keep_alive), whatever the health threshold of the rule; 'spell', 'potion' or None when both are on cooldown"""
        bot, now = self.bot, time.monotonic()
        if not (self.alive() and bot.cid):
            return None
        if bot.heal and bot.ready.get('heal', 0) <= now and bot.ready.get(bot.heal['group'], 0) <= now:
            bot.say(bot.heal['words'])
            bot.ready['heal'] = now + max(1.0, bot.heal['cooldown'] / 1000.0)
            bot.ready[bot.heal['group']] = now + bot.heal['groupcooldown'] / 1000.0 + 0.1
            bot.results.behaviour('heal_spell', 'tried')
            bot.pending.setdefault('heal_spell', now + HEAL_SEEN)
            await bot.conn.w.drain()
            return 'spell'
        pot = (bot.helper.get('info') or {}).get('potions', {}).get('health')
        if pot and bot.ready.get('potion', 0) <= now:
            bot.conn.send(b'\x84' + struct.pack('<HHB', 0xFFFF, 0, 0) + struct.pack('<HB', pot, 0) + struct.pack('<I', bot.cid))
            bot.ready['potion'] = now + 1.1
            bot.results.behaviour('potion', 'tried')
            bot.pending.setdefault('potion', now + HEAL_SEEN)
            await bot.conn.w.drain()
            return 'potion'
        return None

    async def buy(self, item_id, amount=1):
        """buys from the NPC whose trade window is open (a person presses Buy)"""
        if self.alive():
            n0 = self.bot.recent_n
            self.bot.conn.send(TC.buy_packet(int(item_id), 0, int(amount)))
            await self.bot.conn.w.drain()
            await asyncio.sleep(1.0)   # O656: the server's lines of the purchase ("You do not have enough money", "Thanks for buying") come back to the check
            new = min(self.bot.recent_n - n0, len(self.bot.recent))
            return list(self.bot.recent[-new:]) if new > 0 else []
        return []

    async def use_at(self, pos, client_id, stackpos=0, wait=1.5):
        """uses an item that lies on the map (a node, a lever: 0x82 with a map position); returns the server's text lines of the next `wait` seconds"""
        if not self.alive():
            return []
        n0 = self.bot.recent_n
        self.bot.conn.send(TC.use_packet((int(pos['x']), int(pos['y']), int(pos['z'])), int(client_id), int(stackpos)))
        await self.bot.conn.w.drain()
        await asyncio.sleep(wait)
        new = min(self.bot.recent_n - n0, len(self.bot.recent))
        return list(self.bot.recent[-new:]) if new > 0 else []

    async def collect(self, opname, action, datas, wait=3.0):
        """sends each of `datas` as `action` of the window and returns every message the window sent back in `wait` seconds (a window that answers
        one request with several: the stash)"""
        bot = self.bot
        op = bot.args.ops.get(opname)
        if op is None or not self.alive():
            return []

        class Keep:
            def __init__(self):
                self.items = []

            def done(self):
                return False

            def set_result(self, msg):
                self.items.append(msg)

        keep = Keep()
        waiter = (op, {'*'}, keep)
        bot.waiters.append(waiter)
        try:
            for data in datas:
                bot.conn.send(b'\x32' + bytes([op]) + LT.string(json.dumps({'action': action, 'data': data}, separators=(',', ':'))))
                await bot.conn.w.drain()
                await asyncio.sleep(0.7)
            await asyncio.sleep(wait)
        finally:
            if waiter in bot.waiters:
                bot.waiters.remove(waiter)
        return keep.items

    # ---- O657: a tool used on a thing of the map and the mount button, as the client sends them
    async def use_item_with(self, client_id, pos, target_client_id, target_stackpos=0, wait=1.5):
        """uses a tool the character carries (by its client id, the hotkey place 0xFFFF 0 0: the server finds it in the backpack) on a thing that lies on
        the map (a corpse, a water tile; 0x83): the server's text lines of the next `wait` seconds"""
        if not self.alive() or not client_id or not isinstance(pos, dict):
            return []
        n0 = self.bot.recent_n
        self.bot.conn.send(TC.use_with_packet((0xFFFF, 0, 0), int(client_id), 0, (int(pos['x']), int(pos['y']), int(pos['z'])),
                                              int(target_client_id or 0), int(target_stackpos or 0)))
        await self.bot.conn.w.drain()
        await asyncio.sleep(wait)
        new = min(self.bot.recent_n - n0, len(self.bot.recent))
        return list(self.bot.recent[-new:]) if new > 0 else []

    def release_partner(self, name, other):
        """O671: the two names a partner() call took are free again (a check that ends with no party leave)"""
        release_party(name, other)

    def io_of(self, name):
        """O681: the io of ANOTHER bot in game (the gear-up of a party member runs on its own bot), None when it is not in game"""
        b = next((b for b in ONLINE.values() if b.name == name and b.alive and not b.died), None)
        return CheckIO(b, self.clock) if b is not None else None

    def class_of(self, name):
        """O681: the class of a bot in game (a party of mixed classes), '' when it is not in game"""
        b = next((b for b in ONLINE.values() if b.name == name), None)
        return str(getattr(b, 'cls', '') or '') if b is not None else ''

    def level_of(self, name):
        b = next((b for b in ONLINE.values() if b.name == name), None)
        return int(getattr(b, 'level', 0) or 0) if b is not None else 0

    def heal_earlier(self, names, on, spell_at=75, potion_at=55, first_at=0):
        """O681: a person heals earlier against a boss whose hit is a third of his health: the bots' heal spell and potion thresholds
        (60 / 40 percent) are raised while a pinnacle fight is played, and put back after. O684: under `first_at` percent the bot casts no attack
        while its heal spell or its potion is ready (a person at 40% stops hitting and heals)"""
        for b in [b for b in ONLINE.values() if b.name in names]:
            b.heal_at = (spell_at, potion_at) if on else (60, 40)
            b.heal_first = first_at if on else 0

    def health_of(self, name):
        """O684: the health in percent of a bot in game as its own creature updates show it (the party's healer picks the lowest), None when unknown"""
        b = self._bot(name)
        return b.health if b is not None and b.health_at is not None else None

    async def heal_spell_of(self, name):
        """O684: the bot's heal spell cast now when it is ready (the Mystic's Purifying Wellspring heals the party within 3 tiles), never the potion.
        -> True when it was cast"""
        b, now = self._bot(name), time.monotonic()
        if b is None or not b.heal or b.ready.get('heal', 0) > now or b.ready.get(b.heal['group'], 0) > now:
            return False
        b.say(b.heal['words'])
        b.ready['heal'] = now + max(1.0, b.heal['cooldown'] / 1000.0)
        b.ready[b.heal['group']] = now + b.heal['groupcooldown'] / 1000.0 + 0.1
        b.results.behaviour('heal_spell', 'tried')
        b.pending.setdefault('heal_spell', now + HEAL_SEEN)
        await b.conn.w.drain()
        return True

    def rotation_words(self, n=3):
        """O685: the words of the first `n` attack spells of the bot's rotation (the spells a support rune goes into)"""
        return [s['words'] for s in (getattr(self.bot, 'rotation', None) or []) if s.get('group') == 'attack'][:n]

    async def cast_words_of(self, name, words, gap=2.0):
        """O685: the bot casts the spell of `words` of its own class now when it is ready (a healer's Mirror Mend, Lucid Reverie, Kindled Breath: no
        target word, the spell picks the most hurt party member). The cooldown is the spell's own, the group cooldown the spell's group. -> True when it was cast"""
        b, now = self._bot(name), time.monotonic()
        spell = next((s for s in (getattr(b, 'all_spells', None) or []) if s.get('words') == words and not s.get('needlearn')), None) if b is not None else None
        if b is None or spell is None or b.ready.get(words, 0) > now or b.ready.get(spell['group'], 0) > now:
            return False
        b.say(words)
        b.ready[words] = now + max(gap, spell['cooldown'] / 1000.0)
        b.ready[spell['group']] = now + spell['groupcooldown'] / 1000.0 + 0.1
        b.results.behaviour('support_cast', 'tried')
        await b.conn.w.drain()
        return True

    def set_potions(self, health, mana):
        """O681: the potions the heal rule drinks (client ids; `!tester info` answers the same once the bot carries the flasks)"""
        info = self.bot.helper.setdefault('info', {})
        pots = info.setdefault('potions', {})
        if health:
            pots['health'] = health
        if mana:
            pots['mana'] = mana

    def hold_party(self, names):
        """O681: the bots of a long party fight stay named busy (PARTY_HOLD_S is 120 s, a pinnacle fight lasts up to 20 minutes): no random party step
        of theirs, no other check takes them as a partner"""
        PARTY_BUSY.update([n for n in names if n])

    async def party_group(self, others):
        """O681: one party of this bot (the leader) and all of `others`: everybody leaves the old party, the leader invites each (0xA3), each joins
        (0xA4). False when a bot is gone"""
        bots = [next((b for b in ONLINE.values() if b.name == n and b.alive and not b.died), None) for n in others]
        bot = self.bot
        if not self.alive() or not bot.cid or any(b is None or not b.cid for b in bots):
            return False
        for b in [bot] + bots:
            await b.helper_says('party leave', 'party')
        for b in bots:
            bot.conn.send(b'\xA3' + struct.pack('<I', b.cid))      # invite
            await bot.conn.w.drain()
            await asyncio.sleep(0.8)
            b.conn.send(b'\xA4' + struct.pack('<I', bot.cid))       # join the leader
            await b.conn.w.drain()
            await asyncio.sleep(0.4)
        return True

    async def party_group_leave(self, others):
        """O681: the party of party_group ends: every bot leaves (the helper takes a bot out that is in a fight, as party('leave') does)"""
        names = [self.bot.name] + list(others)
        asyncio.get_running_loop().call_later(PARTY_RELEASE_S, release_party, *names)
        for b in [b for b in ONLINE.values() if b.name in names and b.alive and not b.died]:
            b.conn.send(b'\xA7')
            await b.conn.w.drain()
        await asyncio.sleep(0.5)
        for b in [b for b in ONLINE.values() if b.name in names and b.alive and not b.died]:
            await b.helper_says('party leave', 'party')

    async def helper_of(self, name, command, kind, wait=4.0):
        """O671: the helper's answer for ANOTHER bot in game (the stranger of the loot test is a bot of its own): None when it is not in game"""
        b = self._bot(name)
        if b is None:
            return None
        return await b.helper_says(command, kind, wait)

    async def open_bag_of(self, name, client_id):
        """O671: the backpack of another bot opened as container 0 (the target of its drag)"""
        b = self._bot(name)
        if b is not None and client_id:
            b.conn.send(TC.use_packet((0xFFFF, 3, 0), int(client_id)))
            await b.conn.w.drain()

    async def drag_of(self, name, src, client_id, stackpos, dst=(0xFFFF, 0x40, 0), count=1, wait=1.5, until_text=None):
        """O671: the move item packet of the bot `name` (this one or another in game): a thing on the map tile `src` (x, y, z) with its client id and place
        in the tile's stack onto `dst` (the first slot of its open backpack when none is given). -> the server's text lines of the next `wait` seconds
        (a refusal arrives as one; a bot that is not next to the item first walks there, so `until_text` ends the wait at the first line with that text),
        None when the bot is not in game"""
        b = self._bot(name)
        if b is None:
            return None
        n0 = b.recent_n

        def lines():
            new = min(b.recent_n - n0, len(b.recent))
            return list(b.recent[-new:]) if new > 0 else []

        b.conn.send(TC.move_packet((int(src[0]), int(src[1]), int(src[2])), int(client_id), int(stackpos), tuple(int(v) for v in dst), int(count)))
        await b.conn.w.drain()
        end = time.monotonic() + wait
        while time.monotonic() < end and b.alive:
            await asyncio.sleep(0.25)
            if until_text and any(until_text in str(l) for l in lines()):
                break
        return lines()

    def tap_of(self, name, box=None):
        """O678: starts (box given) or stops (box None) reading the map's effects and items for the bot `name` (this one or another in game); stopping
        returns the events [(seconds, kind, a, b)] of the tap, None when the bot is not in game or no tap ran"""
        b = self._bot(name)
        if b is None:
            return None
        if box is not None:
            b.tap = TC.WorldTap(box)
            return []
        tap, b.tap = b.tap, None
        return list(tap.events) if tap is not None else None

    def msgs_of(self, name, op_name, action, since):
        """O678: the extended messages of window `op_name` with `action` that the bot `name` read after the monotonic time `since`: [(seconds, data)]"""
        b = self._bot(name)
        if b is None:
            return []
        return [(t, d) for t, n, a, d in b.msgs if n == op_name and a == action and t >= since]

    async def toggle_mount(self, on, wait=2.5):
        """the mount button (0xD4, u8 1 = mount, 0 = dismount): the server's text lines of the next `wait` seconds"""
        if not self.alive():
            return []
        n0 = self.bot.recent_n
        self.bot.conn.send(b'\xD4' + (b'\x01' if on else b'\x00'))
        await self.bot.conn.w.drain()
        await asyncio.sleep(wait)
        new = min(self.bot.recent_n - n0, len(self.bot.recent))
        return list(self.bot.recent[-new:]) if new > 0 else []

    async def partner(self, min_level=0):
        # a bot that is in no other party check: the checks of all bots start together, and when every bot picked the
        # same partner (the lowest id) only one party formed and the others read 0 members (local run 2026-10-31)
        # Every bot also starts its party checks at about the same time: wait up to PARTNER_WAIT_S for a free one
        # (live run 2026-11-01: 13 of 14 party_xp checks found none free and skipped)
        end = time.monotonic() + PARTNER_WAIT_S
        while True:
            if self.bot.name not in PARTY_BUSY:
                for cid, other in sorted(ONLINE.items()):
                    if cid != self.bot.cid and other is not self.bot and other.alive and not other.died \
                            and other.name not in PARTY_BUSY and (getattr(other, 'level', 0) or 0) >= min_level:
                        PARTY_BUSY.update((self.bot.name, other.name))
                        return other.name
            if time.monotonic() >= end or not self.alive():
                return None
            await asyncio.sleep(min(2.0, max(0.05, end - time.monotonic())))

    async def partners(self, n, min_level=0):
        """O681: up to `n` other bots in no party check, taken at once (partner() called again would wait: the first call named this bot busy). Waits up to
        PARTNER_WAIT_S for all n; takes what is free then. Different classes first (a party of mixed classes). -> [names] (empty when none)"""
        end = time.monotonic() + PARTNER_WAIT_S
        while True:
            if self.bot.name not in PARTY_BUSY:
                free = [o for cid, o in sorted(ONLINE.items()) if cid != self.bot.cid and o is not self.bot and o.alive and not o.died
                        and o.name not in PARTY_BUSY and (getattr(o, 'level', 0) or 0) >= min_level]
                if len(free) >= n or (free and time.monotonic() >= end):
                    seen, picked, rest = {str(getattr(self.bot, 'cls', ''))}, [], []
                    for o in free:
                        c = str(getattr(o, 'cls', ''))
                        if c not in seen and len(picked) < n:
                            seen.add(c)
                            picked.append(o)
                        else:
                            rest.append(o)
                    picked += rest[:max(0, n - len(picked))]
                    names = [o.name for o in picked]
                    PARTY_BUSY.update([self.bot.name] + names)
                    return names
            if time.monotonic() >= end or not self.alive():
                return []
            await asyncio.sleep(min(2.0, max(0.05, end - time.monotonic())))

    async def party(self, action, other_name):
        other = next((b for b in ONLINE.values() if b.name == other_name), None)
        bot = self.bot
        if other is None or not self.alive() or not other.alive or not bot.cid or not other.cid:
            if action in ('form', 'leave'):
                PARTY_BUSY.discard(bot.name)
                PARTY_BUSY.discard(other_name)
            return False
        if action == 'form':
            self.formed = (other_name, other.cid, bot.cid)
            # out of any party the random party behaviour made before this check
            await bot.helper_says('party leave', 'party')
            await other.helper_says('party leave', 'party')
            bot.conn.send(b'\xA3' + struct.pack('<I', other.cid))      # invite
            await bot.conn.w.drain()
            await asyncio.sleep(1.0)
            other.conn.send(b'\xA4' + struct.pack('<I', bot.cid))       # join the leader
            await other.conn.w.drain()
        elif action == 'join':
            # the leader's invite came from the Party Finder (the server made it): the other bot only joins (0xA4)
            other.conn.send(b'\xA4' + struct.pack('<I', bot.cid))
            await other.conn.w.drain()
        elif action in ('share', 'unshare'):
            bot.conn.send(b'\xA8' + (b'\x01' if action == 'share' else b'\x00'))   # the leader's shared experience switch
            await bot.conn.w.drain()
        else:
            # both stay busy a while: the check reads the party again after the leave, and a random party step of a
            # freed bot could join another party first (local run 2026-10-31)
            asyncio.get_running_loop().call_later(PARTY_RELEASE_S, release_party, bot.name, other_name)
            other.conn.send(b'\xA7')                                    # leave
            bot.conn.send(b'\xA7')
            await other.conn.w.drain()
            await bot.conn.w.drain()
            # the engine refuses the leave packet in a fight (Game::playerLeaveParty), and hunting bots are in one:
            # the helper takes both out (Party:removeMember), else the partner stays in the party for the next check
            await asyncio.sleep(0.5)
            await other.helper_says('party leave', 'party')
            await bot.helper_says('party leave', 'party')
        return True

    def partner_kept(self, other_name):
        """False when this bot or the partner died, left the game or logged in again (a new creature id) since the
        party was formed: a party of 0 or 1 is then no bug (live run 2026-11-01 at level 1600: bots died every few s)"""
        formed = getattr(self, 'formed', None)
        other = next((b for b in ONLINE.values() if b.name == other_name), None)
        if not formed or formed[0] != other_name or other is None or not self.alive():
            return False
        return other.alive and not other.died and other.cid == formed[1] and self.bot.cid == formed[2]

    def autosetup(self):
        return getattr(self.bot.args, 'checks_rotation', None)

    # closed test mode (O582): the same calls for another bot, the plan of the tester guilds, the bazaar rows
    def _bot(self, name):
        return next((b for b in ONLINE.values() if b.name == name and b.alive and not b.died), None)

    def online(self, name):
        return name if name and self._bot(name) is not None else None

    def closed_plan(self):
        return (getattr(self.bot.args, 'closed_plan', None) or {}).get('of', {}).get(self.bot.name)

    async def helper_of(self, other, command, kind, wait=4.0):
        b = self._bot(other)
        return await b.helper_says(command, kind, wait) if b is not None and self.alive() else None

    async def go_of(self, other, place):
        b = self._bot(other)
        if b is None or not self.alive():
            return False
        b.stay = place == 'town'
        r = await b.helper_says(place, place)
        return bool(r and not r.get('err'))

    async def request_of(self, other, opname, action, data, expect, timeout):
        b = self._bot(other)
        return await KeyIO(b, self.clock).request(opname, action, data, expect, timeout) if b is not None else None

    # the raid in closed test mode (O588): the walk steps of a person, the loot, and no flight to the temple inside
    STEP_BYTES = STEP_BYTES

    async def step_of(self, other, dx, dy):
        b = self._bot(other)
        if b is None or not b.alive or b.died or (dx, dy) not in self.STEP_BYTES:
            return False
        b.walk_until = time.monotonic() + 3.0  # a "not possible" in this time is a blocked step, not a bug
        b.conn.send(bytes([self.STEP_BYTES[(dx, dy)]]))
        await b.conn.w.drain()
        return True

    async def step(self, dx, dy):
        return await self.step_of(self.bot.name, dx, dy)

    async def chase_of(self, other, on):
        """O683: the fight mode's chase switch of a bot (a person who steps off a mark does not want the game to walk him back to the monster)"""
        b = self._bot(other)
        if b is None or not b.alive or b.died:
            return False
        b.conn.send(b'\xA0\x01' + (b'\x01' if on else b'\x00') + b'\x01\x00')
        await b.conn.w.drain()
        return True

    async def chase(self, on):
        return await self.chase_of(self.bot.name, on)

    async def loot(self):
        if self.alive():
            await self.bot.do_loot(self.clock)

    def raid_mode(self, names, on, keep_flee=False):
        """inside a run of closed mode: no walk back to the hunt; `keep_flee`: the bot may still flee to the temple at low health
        (a dungeon does not catch a lethal hit as the raid does, so there the bot flees like a person, and leaves the run)"""
        for name in names or []:
            b = self._bot(name)
            if b is not None:
                b.in_raid = bool(on) and not keep_flee
                b.stay = bool(on)

    def sql(self, statements):
        try:
            sql(statements)
            return True
        except (SystemExit, OSError, subprocess.SubprocessError):
            return False

    def spells(self):
        return getattr(self.bot.args, 'checks_spells', None) or {}

    def equip_rules(self):
        """O663: the parsed data/lib/chaos_equip_rules.lua of the server (tester_checks.parse_equip_rules), or None"""
        return getattr(self.bot.args, 'checks_equip', None)

    def timers(self):
        return getattr(self.bot.args, 'checks_timers', None)

    def weapon_stats(self):
        """O665: {item id: attack / wand damage} of the server's items.xml and weapons.xml (tester_weapons.load_weapon_stats), or None"""
        return getattr(self.bot.args, 'checks_weapons', None)


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
    if not os.path.exists(stock):
        # no install step copies the table: the repo's copy (server/data/spells, made from the installed spells.xml).
        # Without it every stock spell of a preset read "not on the server" (local run 2026-10-31)
        stock = os.path.join(HERE, '..', 'data', 'spells', 'stock_spells.csv')
    if os.path.exists(stock):
        for line in LT.read_text(stock).splitlines()[1:]:
            c = line.split(',')
            if len(c) > 11 and c[0].isdigit() and int(c[0]) not in out:
                names = [n for n in c[11].split(';') if n]
                out[int(c[0])] = {'name': c[1], 'level': int(c[4] or 0), 'vocations': [vocs[n]['id'] for n in names if n in vocs]}
    return out


class JourneyIO(CheckIO):
    """what tester_journey.Journey needs of a bot in game (O654): the clock, the depot locker, the trade window of a shop NPC and the bag
    keeping; the walk steps, the speech, the helper and the loot are CheckIO's"""

    def alive(self):
        return bool(self.bot.alive and not self.bot.died and not self.clock['stop'] and time.monotonic() < self.clock['until'])

    def now(self):
        return time.monotonic()

    async def open_locker(self, lk):
        """the depot locker next to the temple, opened as `do_depot` does (use the item on its tile), closed after a moment"""
        if not self.alive() or not all(isinstance(lk.get(k), int) for k in ('x', 'y', 'z', 'cid')):
            return False
        bot = self.bot
        bot.conn.send(b'\x82' + struct.pack('<HHB', lk['x'], lk['y'], lk['z']) + struct.pack('<HBB', lk['cid'], int(lk.get('sp') or 1), 0))
        await bot.conn.w.drain()
        await self.sleep(3)
        bot.conn.send(b'\x87\x00')
        bot.results.keep('journey_depot')
        return True

    async def shop_here(self, name):
        """the trade window of the NPC the bot stands at: hi, trade, sell what the window lists as bought (the Loot Buyer), buy potions
        (the Apothecary), bye. -> {'sold': kinds sold, 'bought': potions bought, 'window': the window opened}"""
        bot = self.bot
        if not self.alive():
            return None
        bot.shop_npc, bot.shop, bot.npc_spoke, bot.nothing_to_sell = name, None, False, False
        bot.say('hi')
        await self.sleep(1.5)
        bot.say('trade', NPC_CHANNEL)
        await self.sleep(1.5)
        sold = bought = 0
        window = bot.shop is not None
        if bot.shop:
            for item in [i for i in bot.shop if i['sell'] > 0][:TC.SELL_ITEMS]:
                bot.conn.send(TC.sale_packet(item['id'], item['sub'], TC.SELL_AMOUNT))
                await bot.conn.w.drain()
                sold += 1
                await self.sleep(0.7)
            potions = sorted((i for i in bot.shop if i['buy'] > 0 and 'potion' in i['name'].lower()), key=lambda i: i['buy'])[:2]
            for item in potions:
                bot.conn.send(b'\x7a' + struct.pack('<HBBBB', item['id'], item['sub'], TJ.POTION_BUY, 0, 0))
                await bot.conn.w.drain()
                bought += TJ.POTION_BUY
                await self.sleep(0.7)
            bot.conn.send(b'\x7c')
        elif not bot.nothing_to_sell:
            bot.results.count('failures', 'journey: no trade window from %s (%s)' % (name, 'it answered' if bot.npc_spoke else 'no answer to hi'), bot)
        bot.say('bye', NPC_CHANNEL)
        bot.shop_npc = None
        bot.results.keep('journey_shops')
        return {'sold': sold, 'bought': bought, 'window': window}

    async def keep(self):
        """the bag the way a person keeps it on the road (`!tester bag`: the helper tops the potions up and reports): wear a better piece, drop
        junk; the sale is the trip's. -> {'sell': the bag is full enough to make a trip worth it}"""
        bot = self.bot
        r = await bot.keep_report()
        if r is None:
            return None
        plan = TC.keep_plan(r, bot.equip_refused, bot.room_fails)
        bot.room_fails = 0
        await bot.open_bag(r)
        if plan['equip']:
            await bot.equip(plan['equip'], r)
            r = await bot.keep_report() or r
        for row in TC.drop_rows(r):
            await bot.drop(row, r)
        return {'sell': bool(plan['sell'] or TC.bag_fill(r) >= TC.BAG_JAM)}


class BusyNames:
    """the bot names in a party check now (partner() picks among the others; leave frees both). A name frees itself
    PARTY_HOLD_S after it was taken: a check cut off by the bot's death never sends the leave, and the two names stayed
    busy for the rest of the run (live run 2026-11-01: 14 of 14 party_xp checks "no free bot")"""

    def __init__(self):
        self.until = {}

    def __contains__(self, name):
        t = self.until.get(name)
        return t is not None and t > time.monotonic()

    def __iter__(self):
        return iter([n for n in self.until if n in self])

    def update(self, names):
        for n in names:
            self.until[n] = time.monotonic() + PARTY_HOLD_S

    def discard(self, name):
        self.until.pop(name, None)

    def clear(self):
        self.until.clear()


PARTNER_WAIT_S = 60.0  # seconds partner() waits for a bot in no other party check
PARTY_HOLD_S = 120.0  # a party check (form, look, leave and PARTY_RELEASE_S) is over well within it
PARTY_BUSY = BusyNames()
PARTY_RELEASE_S = 10.0  # seconds after a leave before both bots are free again


def release_party(*names):
    for n in names:
        PARTY_BUSY.discard(n)
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
        self.all_spells = spells.get('all') or []   # O655: every spell of the class at its level (the support and learned-spell checks)
        self.heal = spells['heal']
        self.vocation = entry.get('vocation')   # O665: the rotation is rebuilt for the level the character really has (refresh_rotation)
        self.rotation_level = self.level
        self.ready = {}
        self.sched = TC.Scheduler(index)
        self.last = 'login'
        self.health = 100
        self.mana, self.mana_max = None, None   # O663: from the player stats packet (0xA0), None until one is seen
        self.health_at = None  # monotonic time of the last health update of its own creature (None: none seen yet)
        self.deaths_at = []  # monotonic times of its deaths (TC.death_rest)
        self.helper = {}
        self.helper_seq = 0   # the number of the newest numbered helper command: "!tester <cmd> #N" (O579)
        self.shop = None
        self.kills = []
        self.chunks = {}
        self.tap = None        # O678: a TC.WorldTap while a check reads the effects and items of the map around a loot burst
        self.msgs = []         # O678: the last extended messages of the loot windows: (seconds, opcode name, action, data)
        self.died = False
        self.after_death = False
        self.fails = 0
        self.pending = {}  # 'heal_spell' / 'potion' -> until when a health rise counts it as ok
        self.back_at = None  # after a flee: when to go back to the hunt
        self.equip_refused = set()  # item ids the server refused to wear (a class or level rule): not tried again (O584)
        self.jams = 0  # keep rounds in a row that ended with a jammed bag
        self.hunt_since = None  # when the bot came to its hunt spot (login, `!tester hunt`); None: away from it (O584)
        self.last_progress = None  # the last experience or loot message (TC.hunt_outcome)
        self.last_move = None  # O689: (helper move 'hunt' / 'town', monotonic time) of the last answer, for the death line
        self.flee_check = None  # (when to judge it, health at the flee) of the flee under way (TC.flee_outcome)
        self.npc_spoke = False
        self.nothing_to_sell = False
        self.walk_until = 0.0  # until when a blind walk is the likely cause of a "not possible"
        self.room_fails = 0  # "not enough room" since the bag was last emptied (helper "bag")
        self.bag_at = -999.0  # when the bag was last looked at
        self.bag_report = {}  # the newest `!tester bag` answer
        self.waiters = []  # (opcode, {actions}, future): requests of the keystone scenario waiting for their answer
        self.modals = []   # O655: the modal windows the server opened (parse_modal), the newest last
        self.recent_n = 0
        self.recent = []   # O655: the last server text lines (a check reads what a cast or a word was answered with)
        self.class_index = 0  # this bot's place among the bots of its class (the keystone scenario starts there)
        self.keytest_done = False
        self.keytest_flushed = False
        self.stay = False  # the keystone scenario keeps the bot in the temple: no walk back to the hunt
        self.keytest = None  # the KeyTest of this bot: it goes on after a death and a new login (O249)
        self.checks = None  # the CheckRun of this bot (O110): it goes on after a death and a new login
        self.checks_done = False
        self.checks_flushed = False
        self.in_raid = False  # inside the testers' raid (O588): the engine catches a lethal hit there, no flight to the temple
        self.heal_at = (60, 40)  # O681: health percent under which the bot casts its heal spell / drinks a potion (a boss fight sets it higher)
        self.heal_first = 0  # O684: health percent under which the bot casts no attack while its heal spell or its potion is ready (a pinnacle fight: 40)

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
        self.mana, self.mana_max = None, None
        self.hunt_since, self.flee_check = time.monotonic(), None  # the login spot is the hunt spot
        ONLINE[self.cid] = self
        reader = asyncio.ensure_future(self.drain())
        guard = asyncio.ensure_future(self.guard())
        self.conn.send(b'\xA0\x01\x01\x01\x00')  # offensive, chase on, secure mode on (never a player)
        self.say('!tester info')
        if self.checks_stay() or self.video():   # O660: the checks run from the temple, not from a hunt spot of a bot with no gear; O689: the video run never hunts
            self.stay = True
            self.say('!tester town')
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
        if self.tap is not None:
            self.tap.feed(time.monotonic(), plain)
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
        if b'\xa0' in plain:   # O663: the mana of the stats packet, for the mana potion and the spells the bot can pay
            stats = TC.parse_stats(plain)
            if stats is not None:
                self.mana, self.mana_max = stats
        if self.shop_npc and SPEAK_RE.search(plain) and self.shop_npc.encode('latin-1', 'replace') in plain:
            self.npc_spoke = True
        if self.shop_npc and b'carry nothing I buy' in plain:
            self.nothing_to_sell = True
        if self.shop_npc and b'\x7a' in plain:
            items = parse_shop(plain, self.shop_npc)
            if items is not None:
                self.shop = items
        if b'\xfa' in plain:
            self.modals.extend(parse_modal(plain, MODAL_IDS))
            del self.modals[:-8]
        for op, text in extended_messages(plain):
            self.on_extended(op, text)
        for text in TC.strings_of(plain):
            self.on_text(text)

    shop_npc = None

    def on_death(self):
        if self.died:
            return
        self.died = self.after_death = True
        if self.flee_check:  # the flee did not save it
            self.flee_check = None
            self.results.behaviour('flee', 'failed', self)
            self.results.count('failures', 'flee: died within %d s of the flee' % TC.FLEE_LOOK, self)
        self.hunt_since = None
        for kind in list(self.pending):  # dead before the heal or the potion could work: the deaths have their section
            self.results.behaviour(kind, 'expected', self)
        self.pending.clear()
        self.deaths_at.append(time.monotonic())
        del self.deaths_at[:-20]
        self.results.d['deaths'] += 1
        self.results.log(self, 'DEATH', 'died while %s%s' % (self.last, self.death_facts()))
        age = None if self.health_at is None else time.monotonic() - self.health_at
        rule = TC.health_anomaly(self.health, 0, True, age, self.health_at is not None)
        if rule:
            self.results.anomaly(rule, self, health_before=self.health)

    def death_facts(self):
        """O689: what the server said before the death, for the activity log: the attackers named in the last damage lines ("You lose 812 hitpoints due to an
        attack by a Dragon."), the last other lines about damage or death, the last helper move (hunt / town) and how long ago. The second video run lost a
        level 1900 bot about a hundred times with only "died while town" to show for it: that name is the last behaviour started, not the place"""
        facts = TC.death_facts(self.recent, self.last_move, time.monotonic())
        return '; ' + facts if facts else ''

    def on_text(self, text):
        bar = TC.cast_bar(text)   # O665: the cast bar of the bot's own cast-time spell
        if bar:
            self.cast_until = time.monotonic() + bar[1] / 1000.0 + TC.CAST_SLOP if bar[0] == 'start' else 0.0
        self.recent.append(text)
        self.recent_n += 1
        del self.recent[:-60]
        kind, detail = TC.classify(text)
        if kind == 'helper':
            hk, data = detail
            seq = data.get('seq') if isinstance(data, dict) else None
            if isinstance(seq, int) and hk != 'info' and seq < self.helper_seq:
                # the answer to a command the bot stopped waiting for (a busy server): it is not the answer to the newer
                # command of the same kind (live run 2026-11-15: a late "chest none" read as the new chest's state)
                self.results.helper_answer('late')
                return
            self.helper[hk] = data
            if hk in ('hunt', 'town') and not data.get('err'):
                self.last_move = (hk, time.monotonic())   # O689: for the death line
            if hk == 'hunt' and not data.get('err'):
                self.hunt_since = time.monotonic()
            elif hk == 'town':
                self.hunt_since = None
            if hk == 'info':
                self.level = data.get('level', self.level)
                self.follow_vocation(data.get('voc'))   # O685: an ascension in the run changes the class
                self.refresh_rotation()   # O665: state.json holds the level of the setup; deaths and levelling moved the real one
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
        elif kind == 'sold':
            self.results.keep('sold_units', detail[0])
            self.results.keep('sold_gold', detail[1])
            self.results.log(self, 'keep', 'sold %d for %d gold' % detail)
        elif kind == 'xp':
            self.last_progress = time.monotonic()
            rule = TC.xp_anomaly(self.level, detail)
            if rule:
                self.results.anomaly(rule, self, gained=detail)
        elif kind == 'loot':
            self.last_progress = time.monotonic()
            rule = TC.gold_anomaly(self.level, detail[1])
            if rule:
                self.results.anomaly(rule, self, monster=detail[0], gold=detail[1])
        elif kind == 'advance':
            self.level = detail[1]
            self.refresh_rotation()   # O665: a new level may open a spell (and the preset of the level)
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
        for name in ('groundLoot', 'lootfilter'):   # O678: the explode, tiles and beam messages the loot burst check reads
            if op == self.args.ops.get(name):
                self.msgs.append((time.monotonic(), name, msg.get('action'), msg.get('data')))
                del self.msgs[:-300]
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
        """the potion top-up and a look at the backpack (`!tester bag`, O584): the helper tops the potions up (a count of 100 does
        not last 29 deaths) and reports the slots; it removes nothing any more. What to do with the drops is `do_keep`: sell,
        wear a better piece, drop junk. The report also tells the bot how full the bag is"""
        self.results.behaviour('bag', 'tried')
        r = await self.helper_says('bag', 'bag', 6.0)
        self.bag_at = time.monotonic()
        if not r or r.get('err'):
            if self.died or not self.alive:
                self.results.behaviour('bag', 'expected', self)
                return False
            return self.failed('bag', r)
        self.bag_report = r
        self.results.behaviour('bag', 'ok', self)
        return True

    async def keep_report(self):
        """a fresh `!tester bag` report, None when the helper did not answer"""
        r = await self.helper_says('bag', 'bag', 6.0)
        if not r or r.get('err'):
            return None
        self.bag_report = r
        return r

    async def open_bag(self, report):
        """the own backpack as container 0, so a slot has a position the move packet can name"""
        cid = report.get('bagClientId')
        if cid:
            self.conn.send(TC.use_packet((0xFFFF, 3, 0), int(cid)))
            await asyncio.sleep(1.0)

    async def sell_trip(self):
        """to the Loot Buyer by the helper, the NPC trade window, every kind it lists sold, back (O584: the trade path a player
        takes). True when it sold at least once"""
        self.results.keep('sell_visits')
        self.hunt_since = None
        r = await self.helper_says('shop Loot Buyer', 'shop')
        if not r or r.get('err') or not r.get('npc'):
            self.failed('keep: sell trip', r)
            await self.helper_says('hunt', 'hunt')
            return False
        before = self.results.d.get('keep', {}).get('sold_units', 0)
        self.shop_npc, self.shop, self.npc_spoke, self.nothing_to_sell = r['npc'], None, False, False
        self.say('hi')
        await asyncio.sleep(1.5)
        self.say('trade', NPC_CHANNEL)
        await asyncio.sleep(1.5)
        if self.shop:
            sell = [i for i in self.shop if i['sell'] > 0][:TC.SELL_ITEMS]
            for item in sell:
                self.conn.send(TC.sale_packet(item['id'], item['sub'], TC.SELL_AMOUNT))
                await self.conn.w.drain()
                await asyncio.sleep(0.7)
            await asyncio.sleep(1)
            self.conn.send(b'\x7c')
        elif self.nothing_to_sell:
            self.results.keep('nothing')
        else:
            self.results.count('failures', 'keep: no trade window from %s (%s)' % (
                r['npc'], 'it answered' if self.npc_spoke else 'no answer to hi'), self)
        self.say('bye', NPC_CHANNEL)
        self.shop_npc = None
        await self.helper_says('hunt', 'hunt')
        return self.results.d.get('keep', {}).get('sold_units', 0) > before

    async def do_keep(self, clock):
        """keep the bag like a player (O584): look at it (`!tester bag`), wear a piece that beats the worn one (the move packet
        to the equipment slot), sell at the Loot Buyer when it is full, drop junk when it is still jammed (the move packet to the
        floor). The helper only reports. A bag that stays jammed with what can be neither sold nor dropped is wiped by the helper
        after MAX_JAMS rounds, as a counted failure"""
        r = await self.keep_report()
        if r is None:
            return self.failed('keep', self.helper.get('bag'))
        plan = TC.keep_plan(r, self.equip_refused, self.room_fails)
        self.room_fails = 0
        await self.open_bag(r)
        if plan['equip']:
            await self.equip(plan['equip'], r)
            r = await self.keep_report() or r
        if plan['sell']:
            await self.sell_trip()
            r = await self.keep_report() or r
        dropped = 0
        for row in TC.drop_rows(r):
            await self.drop(row, r)
            dropped += 1
        if dropped:
            r = await self.keep_report() or r
        if TC.bag_fill(r) >= TC.BAG_JAM and not dropped:
            self.jams += 1
            if self.jams >= TC.MAX_JAMS:
                self.jams = 0
                self.results.keep('wiped')
                self.results.count('failures', 'keep: the bag stayed jammed with items that are neither sold nor dropped: wiped by the helper', self)
                await self.helper_says('bag wipe', 'bag', 6.0)
        else:
            self.jams = 0
        return True

    async def equip(self, row, report):
        """wear the piece: move it from its backpack slot to its equipment slot; ok when the slot of the backpack holds another
        thing afterwards. The server's refusal (a class or level rule) is remembered, not retried"""
        slot = row.get('s')
        if not slot:
            return False
        self.conn.send(TC.move_packet((0xFFFF, 0x40, row['i']), int(row['cid']), row['i'], (0xFFFF, slot, 0), 1))
        await self.conn.w.drain()
        await asyncio.sleep(1.5)
        after = await self.keep_report()
        left = TC.row_at(after, row['i']) if after else None
        if after is not None and not (left and left.get('id') == row['id']):
            self.results.keep('equipped')
            self.results.log(self, 'keep', 'wore item %s (score %s)' % (row['id'], row.get('sc')))
            return True
        self.equip_refused.add(row['id'])
        self.results.keep('equip_refused')
        return False

    async def drop(self, row, report):
        """throw a junk item on the floor of the bot's own tile, as a player clears a bag"""
        pos = report.get('pos') or {}
        if not all(isinstance(pos.get(k), int) for k in 'xyz'):
            return False
        self.conn.send(TC.move_packet((0xFFFF, 0x40, row['i']), int(row['cid']), row['i'], (pos['x'], pos['y'], pos['z']),
                                      int(row.get('n') or 1)))
        await self.conn.w.drain()
        await asyncio.sleep(1.0)
        self.results.keep('dropped')
        self.results.log(self, 'keep', 'dropped item %s' % row['id'])
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
                    if self.room_fails >= ROOM_FAILS_BAG:
                        self.last = 'keep'
                        self.results.behaviour('keep', 'tried')  # no room for a pickup: keep the bag now
                        ok = await self.do_keep(clock)
                        self.results.behaviour('keep', 'ok' if ok else 'failed', self)
                    else:
                        await self.tidy_bag()
                except (ConnectionError, OSError, asyncio.IncompleteReadError):
                    break
            if now >= next_pick:
                name = self.sched.next(now) or 'hunt'
                if getattr(self.args, 'keystones', False) and not self.keytest_done:
                    name = 'keytest'  # before anything else, until it is through (it goes on after a death and a new login)
                elif (getattr(self.args, 'checks', False) or getattr(self.args, 'closed', False)) and not self.checks_done:
                    name = 'checks'  # then the system checks (tester_checks.py)
                elif getattr(self.args, 'journey', False):
                    name = 'journey'  # O654: the levelling journey on foot, the only thing this run does
                elif self.video():
                    name = 'hold'  # O689: the checks are done (a verdict or a member's wait is over): the bot waits in the temple, no hunt, no errand that ends at a hunt
                self.last = name
                self.results.behaviour(name, 'tried')
                try:
                    ok = await getattr(self, 'do_' + name)(clock)
                except (ConnectionError, OSError, asyncio.IncompleteReadError):
                    break
                # a behaviour cut short by the bot's own death or a dropped connection is not a failure of the system
                # it tried: the deaths and kicks have their sections
                cut = not ok and (self.died or not self.alive)
                if ok is None:  # not judged (TC.hunt_outcome: the bot has not been at its hunt long enough)
                    outcome = 'expected'
                else:
                    outcome = 'expected' if cut else 'ok' if ok else 'failed'
                self.results.behaviour(name, outcome, self)
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
            await asyncio.sleep(TC.beat_delay(time.monotonic(), self.ready))   # O665: awake when the attack group is ready, not on a 0.25 s grid

    def keep_alive(self, now):
        """heal by spell under 60 %, by potion (hotkey: use with creature at 0xFFFF on its own id) under 40 %; under
        FLEE_AT % with both on cooldown, back to the temple (as a player's town portal) and to the hunt FLEE_REST
        seconds later; cast the rotation otherwise (not under 50 % with a heal: the mana is for the heal). A heal or a
        potion counts ok when the health rises within HEAL_SEEN seconds, else failed"""
        if self.flee_check and now >= self.flee_check[0]:
            at_flee = self.flee_check[1]
            self.flee_check = None
            outcome, why = TC.flee_outcome(at_flee, self.health, self.died, self.helper.get('town'))
            self.results.behaviour('flee', outcome, self)
            if outcome != 'ok':
                self.results.count('failures', 'flee: ' + why, self)
        for kind, until in list(self.pending.items()):
            if now > until:
                del self.pending[kind]
                self.results.behaviour(kind, 'failed', self)
        if self.back_at and now >= self.back_at and not self.stay and not self.video():
            self.back_at = None
            self.say('!tester hunt')
        healed = False   # O663: the heal went this beat
        pot_ready = bool(self.heal_first and self.cid and self.ready.get('potion', 0) <= now
                         and (self.helper.get('info') or {}).get('potions', {}).get('health'))   # O684: a potion could go this beat
        if self.health < self.heal_at[0] and self.heal and self.ready.get('heal', 0) <= now \
                and self.ready.get(self.heal['group'], 0) <= now:
            healed = True
            self.say(self.heal['words'])
            self.ready['heal'] = now + max(1.0, self.heal['cooldown'] / 1000.0)
            self.ready[self.heal['group']] = now + self.heal['groupcooldown'] / 1000.0 + 0.1
            self.results.behaviour('heal_spell', 'tried')
            self.pending.setdefault('heal_spell', now + HEAL_SEEN)
        if self.health < self.heal_at[1] and self.ready.get('potion', 0) <= now and self.cid:
            pot = (self.helper.get('info') or {}).get('potions', {}).get('health')
            if pot:
                self.conn.send(b'\x84' + struct.pack('<HHB', 0xFFFF, 0, 0) + struct.pack('<HB', pot, 0)
                               + struct.pack('<I', self.cid))
                self.ready['potion'] = now + 1.1
                self.results.behaviour('potion', 'tried')
                self.pending.setdefault('potion', now + HEAL_SEEN)
        pot = (self.helper.get('info') or {}).get('potions', {}).get('mana')
        if pot and self.cid and self.ready.get('potion', 0) <= now and TC.mana_potion_due(self.health, self.mana, self.mana_max):
            self.conn.send(b'\x84' + struct.pack('<HHB', 0xFFFF, 0, 0) + struct.pack('<HB', pot, 0) + struct.pack('<I', self.cid))   # O663: a person drinks a mana potion
            self.ready['potion'] = now + 1.1
            self.results.log(self, 'do', 'mana potion at %d %% mana' % (100 * self.mana // max(1, self.mana_max)))
        if self.health <= FLEE_AT and not self.in_raid and not self.back_at and self.ready.get('flee', 0) <= now \
                and self.ready.get('heal', 0) > now and self.ready.get('potion', 0) > now:
            self.helper.pop('town', None)
            self.say('!tester town')
            self.ready['flee'] = now + 60
            self.back_at = now + FLEE_REST
            self.flee_check = (now + TC.FLEE_LOOK, self.health)
            self.results.behaviour('flee', 'tried')
            self.results.log(self, 'do', 'flee at %d %% health' % self.health)
            return
        if self.rotation and not TC.hold_attack(self.health, self.heal, healed or (
                self.heal and self.ready.get('heal', 0) <= now and self.ready.get(self.heal['group'], 0) <= now)) \
                and not TC.heal_first_hold(self.health, self.heal_first, self.heal, healed, pot_ready):   # O663: the heal on cooldown, the attack goes
            spell = LT.next_spell(self.rotation, self.ready, now, mana=self.mana)
            if spell:
                self.say(spell['words'])
                self.ready[spell['words']] = now + spell['cooldown'] / 1000.0 + TC.CAST_SLOP   # O665: 0.03 s, not 0.1 s
                self.ready[spell['group']] = now + spell['groupcooldown'] / 1000.0 + TC.CAST_SLOP

    async def helper_says(self, command, kind, wait=4.0):
        """say `!tester <command> #N` and wait for the answer of that kind that carries N (the helper echoes it). The helper's own
        error answer for this command comes back as {err, cmd}: a command that failed is a failure with its reason, not "no
        answer". None when nothing came within `wait` (the helper is not there, the bot died, the server was busy; counted
        in the report's "Helper answers" line)"""
        self.helper_seq += 1
        seq = self.helper_seq
        self.helper.pop(kind, None)
        self.helper.pop('error', None)
        self.say('!tester %s #%d' % (command, seq))
        t0 = time.monotonic()
        end = t0 + wait
        while time.monotonic() < end and self.alive:
            if kind in self.helper:
                self.results.helper_answer('answered', time.monotonic() - t0)
                return self.helper[kind]
            err = self.helper.get('error')
            if isinstance(err, dict) and err.get('seq') == seq:
                self.helper.pop('error', None)
                self.results.helper_answer('answered', time.monotonic() - t0)
                return err
            await asyncio.sleep(0.2)
        if self.alive and not self.died:
            self.results.helper_answer('lost', time.monotonic() - t0)
        return None

    def walk(self, steps):
        self.walk_until = time.monotonic() + 3.0  # a "Sorry, not possible." in this time is a blind step into an obstacle
        for _ in range(steps):
            self.conn.send(bytes([random.choice((0x65, 0x66, 0x67, 0x68))]))

    async def do_hunt(self, clock):
        """O584: ok only when the bot gained experience or loot within TC.HUNT_WINDOW seconds; failed when it stood at its
        hunt that long and gained none; not judged (None) before it has been there a window. It said ok always before."""
        outcome = TC.hunt_outcome(time.monotonic(), self.hunt_since, self.last_progress)
        if outcome == 'failed':
            self.results.count('failures', 'hunt: no experience in %d s at the hunt spot' % TC.HUNT_WINDOW, self)
            self.hunt_since = time.monotonic()  # judged again after the next window, not at every pick
            return False
        return True if outcome == 'ok' else None

    def video(self):
        """O689: the run of the boss video (--video): no hunt, no free activity"""
        return bool(getattr(self.args, 'video', False))

    async def do_hold(self, clock):
        """O689 (video run): the free activity loop of a bot whose check is done. The second run's bots fell into it, walked errands that end with `!tester hunt`
        (town, depot, shop) and died at their hunts at level 1900. Now: the temple, nothing else"""
        self.stay = True
        self.back_at = None
        if self.helper.get('town') is None:
            await self.helper_says('town', 'town')
        await asyncio.sleep(5)
        return True

    async def do_wander(self, clock):
        # O665: a person does not step off while his own cast-time spell runs (a move cancels it and the mana comes back: the bar says "You moved:
        # the spell is interrupted."); the strongest spells of the Deadeye, the Elementalist and the Juggernaut are such casts
        waited = 0.0
        while self.casting(time.monotonic()) and waited < TC.CAST_WAIT_MAX and self.alive and not self.died:
            await asyncio.sleep(0.1)
            waited += 0.1
        self.walk(random.randint(2, 5))
        return True

    def follow_vocation(self, voc):
        """O685: the class the character is now (the helper's `info` carries its vocation id): an ascension in a run (the Oracle's Choice) makes a Mystic an
        Illusionist, and its rotation, heal and spell list are the new class's. -> True when the class changed"""
        ctx = getattr(self.args, 'rotation_ctx', None)
        if not ctx or isinstance(voc, bool) or not isinstance(voc, int) or voc <= 0 or voc == self.vocation:
            return False
        name = ctx[2].get(voc)
        if not name:
            return False
        self.vocation, self.cls, self.rotation_level = voc, name, None
        return True

    def refresh_rotation(self):
        """O665: the rotation, the heal and the spell list of the level the character really has. `entry['level']` is the level of the setup (800 to 2000 for
        the ten testers) and the bots lose and win levels: a Deadeye of 574 cast the preset of level 1000 and a Mystic of 447 the preset of level 800. -> True when
        the lists changed"""
        ctx = getattr(self.args, 'rotation_ctx', None)
        level = self.level
        if not ctx or not isinstance(level, int) or level <= 0 or level == self.rotation_level:
            return False
        spells, model, by_id, auto = ctx
        cs = class_spells(spells, model, by_id.get(self.vocation, ''), level, auto)
        self.rotation, self.heal, self.all_spells = cs['rotation'], cs['heal'], cs.get('all') or []
        self.rotation_level = level
        return True

    def casting(self, now):
        """True while a cast-time spell of the bot is on the cast bar (the bar's own start message, ChaosCasting; `cast_until` is set in on_text)"""
        return now < getattr(self, 'cast_until', 0.0)

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
        # not while a party check holds this bot: a random invite, join or leave broke the check's party (local run
        # 2026-10-31: "left the party, the helper still sees 2 members", "joined, the party has 0 members")
        if self.name in PARTY_BUSY:
            return False
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
            if step[0] == 'walk':
                await self.walk_to_place(step[1], clock)   # O589: on foot first, the helper's teleport only as the named fallback
                await asyncio.sleep(getattr(runner, 'pause', 1.5))
                continue
            runner.run_step(self, step, ONLINE, send_ext, self.say, use_hotkey)
            await self.conn.w.drain()
            await asyncio.sleep(getattr(runner, 'pause', 1.5))
        return True

    WALK_ROUNDS = 8      # asks for a path at most this many times (each answer holds up to 80 steps)
    WALK_BUDGET = 150.0  # seconds a walk to a place may take: then the helper's teleport is the fallback

    async def walk_to(self, args, clock):
        """walks the engine path of `!tester path <args>`: 'foot' when the bot stands next to it, else the reason it did not
        arrive (the helper's own words: no path, another floor, no such place; or 'no answer', 'far', 'blocked')"""
        t0, last, stalled = time.monotonic(), None, 0
        for _ in range(self.WALK_ROUNDS):
            if not self.alive or self.died or clock['stop']:
                return 'gone'
            r = await self.helper_says('path ' + args, 'path', 6.0)
            if not isinstance(r, dict):
                return 'no answer'
            if r.get('err'):
                return str(r['err'])[:40]
            dist = r.get('dist')
            if r.get('here') or (dist is not None and dist <= 1):
                return 'foot'
            steps = TX.raid_path_steps(r.get('path'))
            if not steps:
                return 'an empty path'
            if last is not None and dist is not None and dist >= last:
                stalled += 1
                if stalled >= 2:
                    return 'blocked'
            else:
                stalled = 0
            last = dist
            self.walk_until = time.monotonic() + 3.0
            for dx, dy in steps:
                if not self.alive or self.died or clock['stop']:
                    return 'gone'
                self.conn.send(bytes([STEP_BYTES[(dx, dy)]]))
                await self.conn.w.drain()
                await asyncio.sleep(0.3)
            if time.monotonic() - t0 > self.WALK_BUDGET:
                return 'far'
        return 'far'

    async def walk_to_place(self, args, clock):
        """a scenario's way to a place or an NPC: on foot; when that fails the helper's `enter` puts the bot there and its answer
        carries `fallback` (the reason), which the coverage counts and names. The answer is left in self.helper['enter'] for the
        `check` step, as the plain `enter` was"""
        why = await self.walk_to(args, clock)
        if why == 'gone':
            return False
        if why == 'foot':
            self.helper['enter'] = {'walked': True, 'kind': args.split(' ', 1)[0]}
            self.helper['walk'] = {'foot': True}
            return True
        r = await self.helper_says('enter ' + args, 'enter', 8.0)
        if isinstance(r, dict) and not r.get('err'):
            r['fallback'] = 'enter %s: %s' % (args, why)
        # a later step (the rift key, O592) replaces the answer in helper['enter']: the walk's own outcome is kept for it
        self.helper['walk'] = {'fallback': 'enter %s: %s' % (args, why)}
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
            closed = bool(getattr(self.args, 'closed', False))
            self.checks = TX.CheckRun(self.name, self.cls, self.level, closed=closed, gear=not getattr(self.args, 'no_gear', False),
                                      only=(([k for k in str(getattr(self.args, 'only', '') or '').split(',') if k] or None)   # O656: --only a,b runs just those checks
                                            if getattr(self.args, 'checks', False) else TX.CLOSED_KEYS))
        run = self.checks
        io = CheckIO(self, clock)
        await asyncio.sleep(10 if first else 3)
        await self.check_rest()   # O660: after a death the bot rests in the temple as long as the death rule says
        if self.checks_stay():   # O660: a person does his errands in town; a check that needs the hunt asks for it (io.go('hunt'))
            self.stay = True
            await io.go('town')
        mark = len(run.results)
        try:
            await run.run(io)
        finally:
            self.stay = (self.checks_stay() and not run.finished) or self.video()   # O689: the video run stays in the temple for good; O660: stays in town between the passes of an unfinished check run
            for r in run.results[mark:]:
                self.results.log(self, 'CHECK', '%s %s%s' % (r.status.upper(), r.check, ': ' + r.detail if r.detail else ''))
                line = r.bug_line()
                if line:
                    self.results.log(self, 'BUG', line)
        if run.finished:
            self.flush_checks()
            return not any(r.status == TX.FAIL for r in run.results)
        return True

    async def check_rest(self):
        """O660: a bot that died waits in the temple for the rest of the death rule (TC.death_rest: 20 s, doubling to 300) before the checks go
        on: a person does not walk back into the pack that just killed him. Only while the checks hold the bot in town (checks_stay)"""
        while self.checks_stay() and self.back_at and time.monotonic() < self.back_at and self.alive and not self.died:
            await asyncio.sleep(1.0)

    def checks_stay(self):
        """O660: true while this run still has system checks to do (not a journey, not a keystone round): the bot waits in the temple, as a
        person does between errands, instead of standing at its hunt spot until a monster pack kills a bot that has no gear"""
        a = self.args
        return bool((getattr(a, 'checks', False) or getattr(a, 'closed', False)) and not getattr(a, 'journey', False)
                    and not self.checks_done and not (getattr(a, 'keystones', False) and not self.keytest_done))

    def flush_checks(self):
        run = self.checks
        if run is None or self.checks_flushed:
            return
        if run.finished:
            self.checks_flushed = self.checks_done = True
            self.results.d.setdefault('checks', []).extend(r.as_dict() for r in run.results)

    async def do_journey(self, clock):
        """the levelling journey of tester_journey.py (O654): the bot walks from the temple to the hunts of its level, hunts, moves on, goes
        back to town for the shops and the depot, dies and goes on. It goes on after a death and a new login (the Journey is kept); False
        only when the helper never answers `!tester journey` (an older helper file)"""
        first = getattr(self, 'journey', None) is None
        self.stay = True   # no helper walk back to a hunt spot: the bot walks, whatever the flee and the death do
        self.back_at = None
        if first:
            self.journey = TJ.Journey(self.name, self.cls, self.level, seed=self.index)
            self.journey.sink = lambda text: self.results.log(self, 'JOURNEY', text)
            await asyncio.sleep(10)  # the helper's supplies, once
        else:
            await asyncio.sleep(3)
        j = self.journey
        io = JourneyIO(self, clock)
        fresh = [t for t in self.deaths_at if t > j.died_seen]
        if fresh:
            j.died_seen = max(fresh)
            j.deaths_seen(len(fresh), io.now())
        journeys = self.results.d.setdefault('journey', {})

        def emit(jj):
            journeys[self.name] = jj.as_dict(io.now())
        try:
            why = await j.play(io, emit=emit)
        finally:
            emit(j)
        if why == 'no helper':
            return self.failed('journey', {'err': 'no answer to !tester journey (the helper file is older than v20)'})
        return True

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
def class_spells(spells, model, vocation, level, auto=None):
    """{'rotation': attack and support spells (loadtest.rotation_for), 'heal': the best healing spell (or None)}. `auto` (O663): (the Auto setup table of
    autorotation_data.lua, {spell id: name}): the attack spells are then the preset of the class and level, as a player with Auto setup casts them"""
    rot = LT.rotation_for(spells, model, vocation, level)
    if auto and auto[0]:
        if len(auto) > 2 and auto[2] is not None:   # O665: the rotation the button writes (top-up to five, area first), not the bare preset
            rot = TC.helper_rotation(auto[0].get(vocation), level, auto[1], {s['name']: s for s in spells}, rot, auto[2])
        else:
            rot = TC.preset_rotation(auto[0].get(vocation), level, auto[1], {s['name']: s for s in spells}, rot)
    heals = [s for s in spells if s['group'] == 'healing' and s['level'] <= level and not s['needlearn']
             and not s['params'] and (not s['vocations'] or vocation in s['vocations'])]
    heals.sort(key=lambda s: (-s['level'], s['words']))
    return {'rotation': rot, 'heal': heals[0] if heals else None,
            'all': [s for s in spells if s['level'] <= level and (not s['vocations'] or vocation in s['vocations'])]}


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
    a.rotation_ctx = (spells, model, by_id, (getattr(a, 'auto_table', None), getattr(a, 'auto_names', None) or {}, getattr(a, 'auto_area', None)))   # O665
    for i, e in enumerate(entries):
        bots.append(TesterBot(i, e, a, n, results, class_spells(spells, model, by_id.get(e['vocation'], ''), e['level'],
                                                               (getattr(a, 'auto_table', None), getattr(a, 'auto_names', None) or {},
                                                                getattr(a, 'auto_area', None)))))
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
    a.checks_equip = None
    a.checks_weapons = None   # O665
    a.auto_table, a.auto_names = None, {}   # O663: the Auto setup rotation the bots cast (autorotation_data.lua), set below
    a.checks_timers = None
    if a.checks:
        rot = os.path.join(HERE, '..', '..', 'client', 'overlay', 'modules', 'game_helperrotation', 'autorotation_data.lua')
        if os.path.exists(rot):
            a.checks_rotation = TX.load_table(rot)
        sup = os.path.join(HERE, '..', '..', 'client', 'overlay', 'modules', 'game_helpersupport', 'supportspells.lua')
        if os.path.exists(sup):
            a.checks_timers = TX.load_timer_ids(sup)
        vocs = LT.parse_vocations(LT.read_text(os.path.join(a.server_dir, 'data', 'XML', 'vocations.xml')))
        a.checks_spells = load_check_spells(a.server_dir, vocs)
        a.checks_equip = TX.load_equip_rules(a.server_dir)   # O663: the weapons a class may wear
        a.checks_weapons = TW.load_weapon_stats(a.server_dir) or None   # O665: what a weapon is worth to the class's spells
    rot663 = os.path.join(HERE, '..', '..', 'client', 'overlay', 'modules', 'game_helperrotation', 'autorotation_data.lua')
    if os.path.exists(rot663) and a.server_dir:   # O663: the bots cast the preset of Auto setup, like the player the balance models measured
        try:
            a.auto_table = TX.load_table(rot663)
            a.auto_area = TC.load_area(rot663)   # O665: which spells the button puts first
            a.auto_names = {sid: s['name'] for sid, s in load_check_spells(
                a.server_dir, LT.parse_vocations(LT.read_text(os.path.join(a.server_dir, 'data', 'XML', 'vocations.xml')))).items()}
        except (OSError, ValueError):
            a.auto_table, a.auto_names = None, {}
    a.backpack_client_id = 0
    a.after_login = ''
    a.closed_plan = {'guilds': [], 'of': {}}
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
    if a.closed:
        closed_start(a, entries, st)
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
    try:
        asyncio.run(run_bots(a, entries))
    finally:
        if a.closed:
            closed_finish(a, entries)


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


def previous_report(state, activity):
    """(text, ' of <stamp>') of the newest report file in runs/ that is older than the run of `activity` (O584: the diff); ('', '')
    when there is none"""
    folder = os.path.join(state, 'runs')
    mine = re.search(r'run-(\d{8}-\d{6})', activity or '')
    try:
        names = os.listdir(folder)
    except OSError:
        return '', ''
    stamps = sorted(n[4:19] for n in names if re.match(r'^run-\d{8}-\d{6}-report\.txt$', n)
                    and (not mine or n[4:19] < mine.group(1)))
    if not stamps:
        return '', ''
    try:
        with open(os.path.join(folder, 'run-%s-report.txt' % stamps[-1]), encoding='utf-8', errors='replace') as f:
            return f.read(), ' of ' + stamps[-1]
    except OSError:
        return '', ''


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
        res['coverage'] = TS.merge(TS.load(table), res.get('coverage') or {}, parsed, res.get('checks'))
    prev, prev_title = previous_report(a.state, r.get('activity'))
    text = TC.build_report(res, parsed, prev, prev_title)
    if res.get('journey'):   # O654: minutes per level against tools/progression_model.lua --curve-json
        try:
            top = max(int(j.get('level') or 1) for j in res['journey'].values()) + 1
            text += '\n'.join(TJ.report_lines(res['journey'], TJ.curve_for(top))) + '\n'
        except (ValueError, TypeError, OSError, AttributeError) as e:
            text += '(journey section not written: %s)\n' % e
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
                '--key-file': '', '--rsa-key': '', '--scenarios': '', '--ramp': 1.0, '--kick-wait': KICK_WAIT, '--only': '', '--retreat-at': 0, '--prep-minutes': 0}
    types = {'--count': int, '--hash-iterations': int, '--town': int, '--minutes': int, '--port': int, '--ramp': float, '--kick-wait': int, '--retreat-at': int, '--prep-minutes': int}
    vals = dict(defaults)
    flags = {'--yes': False, '--dry-run': False, '--keystones': False, '--checks': False, '--closed': False, '--journey': False, '--no-gear': False, '--video': False}
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
    a.closed = flags['--closed']
    a.journey = flags['--journey']
    a.video = flags['--video']
    if a.video and not (a.checks and a.closed and a.only == 'pinnacle_party'):
        sys.exit('--video is the run of the boss video: with --checks --closed --only pinnacle_party (server/README.md "Malgrath fight video (O689)")')
    if not 0 <= a.prep_minutes <= 1440:
        sys.exit('--prep-minutes 1..1440 (0 or no option is 120)')
    TX.set_video(a.video, a.prep_minutes)   # O689: the retry, the wait for members, no hunt
    if not 0 <= a.retreat_at <= 99:
        sys.exit('--retreat-at 1..99 (percent health; 0 or no option is the usual 30)')
    TX.set_retreat_at(a.retreat_at)   # O662: the scenario of a second retreat (0 = the usual 30 percent)
    a.no_gear = flags['--no-gear']   # O658: no gear-up before the hard checks (the old gearless run, for a comparison)
    if a.journey and (a.keystones or a.checks or a.closed):
        sys.exit('--journey is a run of its own: not with --keystones, --checks or --closed (server/README.md "The levelling journey on foot (O654)")')
    if a.journey and a.cmd == 'setup':
        a.town = TJ.TOWN   # the teleport room and its hunts are Cinderhold's
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
