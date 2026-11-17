#!/usr/bin/env python3
"""python3 -I server/tools/tester_closed_test.py: closed test mode outside the game (tester_closed.py, O582): the switch file,
the tester guild plan, the SQL that makes and removes what the mode made (every DELETE keyed, never a player's row), the numbers
shared with the Lua rules."""
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tester_closed as C  # noqa: E402

CHAOS = os.path.join(HERE, '..', 'data', 'scripts', 'chaos')
count, failed = 0, 0


def ok(cond, label):
    global count, failed
    count += 1
    if not cond:
        failed += 1
        print('FAIL ' + label)


def eq(a, b, label):
    ok(a == b, '%s (%r != %r)' % (label, a, b))


def lua(name):
    with open(os.path.join(CHAOS, name), encoding='utf-8') as f:
        return f.read()


# the switch
ok(C.parse_flag('on') and C.parse_flag(' ON\n') and C.parse_flag('On'), 'on, any case, trimmed')
ok(not any(C.parse_flag(t) for t in ('off', '', 'onn', '1', 'on off', None, 5, 'yes')), 'anything else is off')
with tempfile.TemporaryDirectory() as d:
    os.makedirs(os.path.join(d, 'data'))
    ok(not C.flag_on(d), 'no file: off')
    with open(C.flag_path(d), 'w') as f:
        f.write('on\n')
    ok(C.flag_on(d), 'the file says on')
    with open(C.flag_path(d), 'w') as f:
        f.write('off\n')
    ok(not C.flag_on(d), 'the file says off')
    ok(not C.flag_on(os.path.join(d, 'nowhere')), 'no folder: off')
eq(os.path.basename(C.flag_path('/x')), 'chaos_testers_closed', 'the file name')

# the same numbers as the Lua rules
core = lua('testers_core.lua')
eq(int(re.search(r'K\.REALM = (\d+)', core).group(1)), C.REALM, 'the realm of testers_core.lua')
eq(re.search(r'K\.CLOSED_FILE = "data/([a-z_]+)"', core).group(1), C.FLAG, 'the switch file of testers_core.lua')
eq(re.search(r'K\.GUILD_MARK = "([^"]+)"', core).group(1), 'Tester Guild ', 'the guild mark')
ok(all(g.startswith(re.search(r'K\.GUILD_MARK = "([^"]+)"', core).group(1)) for g in C.GUILDS), 'guild names carry the mark')
ok(all(g.startswith(re.search(r'K\.GUILD_PREFIX = "([^"]+)"', core).group(1)) for g in C.GUILDS), 'and the tester prefix')
eq(int(re.search(r'TESTER_REALM = (\d+)', lua('market_core.lua')).group(1)), C.REALM, 'market_core.lua')
eq(int(re.search(r'testerRealm = (\d+)', lua('pvpzone_config.lua')).group(1)), C.REALM, 'pvpzone_config.lua')
eq(int(re.search(r'minMembers = (\d+)', lua('guildwar_config.lua')).group(1)), C.MIN_MEMBERS, 'guild war minimum members')

# the plan
names = ['Tester %sa%s' % (a, b) for a in 'ABCD' for b in 'bcde'][:14]
ok(C.plan(names[:5]) == {'guilds': [], 'of': {}}, 'five bots: no guilds (3 per guild needed)')
p = C.plan(names[:6])
eq([len(g['members']) for g in p['guilds']], [3, 3], 'six bots: two guilds of three')
p = C.plan(names)
eq([len(g['members']) for g in p['guilds']], [5, 5], 'at most five a guild')
ok(set(p['guilds'][0]['members']).isdisjoint(p['guilds'][1]['members']), 'no bot in both')
g0, g1 = p['guilds']
eq(p['of'][g0['leader']], {'guild': C.GUILDS[0], 'leader': True, 'rival': C.GUILDS[1], 'rival_leader': g1['leader']}, 'leader of Alfa')
eq(p['of'][g1['members'][1]]['leader'], False, 'a member')
eq(p['of'][g1['members'][1]]['rival'], C.GUILDS[0], 'its rival')
ok(len(p['of']) == 10, 'a bot beyond the guilds has no entry')
eq(C.plan(['Ana', 'Bob', 'Cid', 'Dan', 'Eve', 'Fay'])['guilds'], [], 'only tester names count')

# making guilds
st = C.guild_statements(C.plan(names[:6]))
joined = '\n'.join(st)
eq(sum(1 for s in st if s.startswith('INSERT INTO `guilds`')), 2, 'two guilds')
eq(sum(1 for s in st if s.startswith('INSERT INTO `guild_ranks`')), 6, 'three ranks each')
eq(sum(1 for s in st if s.startswith('INSERT INTO `guild_membership`')), 6, 'six members')
ok("'Tester Guild Alfa'" in joined and "'Tester Guild Bravo'" in joined, 'the names')
ok(all('`level` = 3' in s for s in st if "WHERE `p`.`name` = '%s'" % names[0] in s), 'the leader has the leader rank')
try:
    C.guild_statements({'guilds': [{'name': "x'; DROP TABLE players; --", 'members': [], 'leader': names[0]}]})
    ok(False, 'an unsafe guild name is refused')
except AssertionError:
    ok(True, 'an unsafe guild name is refused')

# removing what the mode made
ALL = {'guilds', 'guild_ranks', 'guild_membership', 'guild_wars', 'chaos_guildwar', 'chaos_guildwar_kills'} | set(C.GUILD_TABLES) | {
    'chaos_market_offers', 'chaos_market_offer_mods', 'chaos_market_orders', 'chaos_market_history', 'chaos_market_history_daily',
    'chaos_arena_matches', 'chaos_arena_match_players', 'chaos_bazaar_listings', 'chaos_bazaar_bids'} | set(C.RAID_TABLES.values()) | {C.DUNGEON_PROGRESS}
cs = C.clean_statements(ALL, [10, 11, 12])
eq(len(cs), 30, 'every table is cleaned')
for s in cs:
    ok(s.startswith('DELETE FROM'), 'only DELETEs: ' + s[:40])
    keyed = (str(C.REALM) in s or "'Tester Guild Alfa'" in s or '(10,11,12)' in s)
    ok(keyed, 'keyed by the realm, the guild names or the tester ids: ' + s[:60])
    ok(' WHERE ' in s, 'no unkeyed DELETE: ' + s[:60])
last_guild = [s for s in cs if s.startswith('DELETE FROM `guilds`')]
eq(len(last_guild), 1, 'the guilds are deleted once')
ok("`ownerid` IN (10,11,12)" in last_guild[0], 'only guilds a tester owns')
ok(cs.index(last_guild[0]) > max(i for i, s in enumerate(cs) if 'guild_membership' in s or 'guild_ranks' in s), 'children first')
ok(any('realm` = %d' % C.REALM in s and 'chaos_market_orders' in s for s in cs), 'the tester order book')
ok(any('chaos_arena_matches' in s and 'NOT IN (10,11,12)' in s for s in cs), 'arena matches with no player outside the testers')
ok(any('chaos_bazaar_listings' in s and 'player_id` IN (10,11,12)' in s for s in cs), 'bazaar listings of testers')
# the testers' own raids (O588)
rt = C.RAID_TABLES
raid_st = [s for s in cs if 'chaos_raid_' in s]
eq(len(raid_st), 5, 'five raid statements: members, instances, lockouts, players, purchases')
ok(all('(10,11,12)' in s for s in raid_st), 'every raid statement is keyed by the tester ids')
for s in raid_st:
    target = re.match(r'DELETE FROM `(\w+)`', s).group(1)
    ok(target not in re.sub(r'^DELETE FROM `\w+`', '', s), 'no statement reads the table it deletes from (error 1093): ' + s[:60])
ok(cs.index([s for s in raid_st if s.startswith('DELETE FROM `chaos_raid_members`')][0]) <
   cs.index([s for s in raid_st if s.startswith('DELETE FROM `chaos_raid_instances`')][0]), 'members before their raids')
ok(any('chaos_raid_instances' in s and 'NOT IN (SELECT `instance_id` FROM `chaos_raid_members`)' in s for s in raid_st),
   'a raid with a member row left (a player) is kept')
eq(C.clean_statements({rt['players']}, [7]), ['DELETE FROM `chaos_raid_players` WHERE `player_id` IN (7);'], 'one raid table alone')
eq(C.clean_statements({rt['instances']}, [7]), [], 'the raids need their member table too')
raid_cfg = lua('raid_config.lua')
for key, table in rt.items():
    ok(('%s = "%s"' % (key, table)) in raid_cfg, 'raid_config.lua names the table ' + table)
ok(any('chaos_dungeon_progress' in s and 'player_id` IN (10,11,12)' in s for s in cs), 'dungeon progress of testers (O589)')
ok('dungeonProgress = "%s"' % C.DUNGEON_PROGRESS in lua('chaos_constants.lua'), 'chaos_constants.lua names the dungeon progress table')
eq(C.clean_statements({C.DUNGEON_PROGRESS}, [7]), ['DELETE FROM `chaos_dungeon_progress` WHERE `player_id` IN (7);'], 'the progress table alone')
eq(C.clean_statements(set(), [1]), [], 'no table, nothing to do')
only = C.clean_statements({'chaos_market_orders'}, [])
eq(only, ['DELETE FROM `chaos_market_orders` WHERE `realm` = %d;' % C.REALM], 'only the book, without tester ids')
ok(all('IN (0)' in s or str(C.REALM) in s for s in C.clean_statements(ALL, [])), 'no ids: an impossible id, never everything')
ok(all(re.match(r'^[A-Za-z0-9_]+$', t) for t in C.GUILD_TABLES), 'table names are plain')

# the bazaar lock probe
b = C.bazaar_statements('Tester Abc')
ok(len(b) == 1 and "'Tester Abc'" in b[0] and "'active'" in b[0], 'a listing of one tester')
ok('chaos_bazaar_bids' not in b[0], 'no bid, no Chaos Coins')
r = C.bazaar_release_statements('Tester Abc')
ok("'cancelled'" in r[0] and "'Tester Abc'" in r[0], 'released by name')
for bad in ("Tester Abc'; --", 'Ana', 'Tester abc'):
    try:
        C.bazaar_statements(bad)
        ok(False, 'refused: ' + bad)
    except AssertionError:
        ok(True, 'refused: ' + bad)

print('tester_closed_test: %d checks, %d failures' % (count, failed))
sys.exit(1 if failed else 0)
