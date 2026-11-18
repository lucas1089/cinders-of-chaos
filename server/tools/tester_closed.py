#!/usr/bin/env python3
"""Closed test mode of the tester bots (O582; server/README.md "Closed test mode").

On the test server the bots play arena, battleground, the Marches (PvP), guild, guild war, market, bazaar, the raid, the dungeons, the
siege and the guild boss only among
themselves, switched on by `chaos-ctl.sh testers closed on` (the admin app's "Modo fechado (bots entre si)"). The switch is
the file data/chaos_testers_closed in the server folder: the word "on" is on, anything else (or no file) is off. The server
scripts read it (testers_core.lua K.closedOn) and check that every party of a closed-mode action is a tester.

This module is the part outside the game:
  parse_flag / flag_on        the same reading the Lua side does
  plan(names)                 two tester guilds ("Tester Guild Alfa" and "... Bravo") from the bots of a run: at least the guild
                              war's minimum of members each, the first bot of each one its leader; per bot its guild, rank, rival
  guild_statements(plan)      the SQL that makes those guilds before the bots log in
  clean_statements(present, ids)  the SQL that removes everything closed mode made: guilds and their wars, the tester market book
                              (offers, orders, price history), arena matches of testers only, bazaar listings of testers, the
                              raids of testers only (instances, members) and the raid rows of the testers (O588), the dungeon progress rows of the testers (O589)
Standard library only.
"""
import os
import re

REALM = 900000001            # testers_core.lua K.REALM, market_core.lua TESTER_REALM: the testers' own book
FLAG = 'chaos_testers_closed'
GUILDS = ('Tester Guild Alfa', 'Tester Guild Bravo')
MIN_MEMBERS = 3              # guildwar_config.lua minMembers: each guild of a war needs this many
MAX_MEMBERS = 5
LEADER, MEMBER = 3, 1        # guild rank levels of the base server (3 leader, 2 vice-leader, 1 member)
NAME_RE = re.compile(r'^Tester [A-Z][a-z][a-z]$')
SAFE_TABLE = re.compile(r'^[A-Za-z0-9_]+$')
DUNGEON_PROGRESS = 'chaos_dungeon_progress'   # chaos_constants.lua Chaos.tables.dungeonProgress (O589): the unlocked difficulty of a tester
RAID_TABLES = {'lockouts': 'chaos_raid_lockouts', 'instances': 'chaos_raid_instances', 'members': 'chaos_raid_members',
               'players': 'chaos_raid_players', 'purchases': 'chaos_raid_purchases'}   # raid_config.lua tables (O588)


def parse_flag(text):
    """True only for the word "on" (trimmed, any case): the reading of testers_core.lua K.parseClosed"""
    if not isinstance(text, str):
        return False
    m = re.match(r'^\s*([A-Za-z]+)\s*$', text)
    return bool(m) and m.group(1).lower() == 'on'


def flag_path(server_dir):
    return os.path.join(server_dir, 'data', FLAG)


def flag_on(server_dir):
    try:
        with open(flag_path(server_dir), encoding='utf-8') as f:
            return parse_flag(f.read(64))
    except OSError:
        return False


def plan(names):
    """two tester guilds from bot names: {'guilds': [{'name', 'members', 'leader'}], 'of': {bot: {'guild', 'leader', 'rival',
    'rival_leader'}}}. Fewer bots than two guilds of MIN_MEMBERS: no guilds (the guild checks say so, nothing is faked)"""
    names = [n for n in names if NAME_RE.match(n or '')]
    k = min(MAX_MEMBERS, len(names) // 2)
    if k < MIN_MEMBERS:
        return {'guilds': [], 'of': {}}
    guilds = []
    for i, gname in enumerate(GUILDS):
        members = names[i * k:(i + 1) * k]
        guilds.append({'name': gname, 'members': members, 'leader': members[0]})
    of = {}
    for i, g in enumerate(guilds):
        rival = guilds[1 - i]
        for m in g['members']:
            of[m] = {'guild': g['name'], 'leader': m == g['leader'], 'rival': rival['name'], 'rival_leader': rival['leader']}
    return {'guilds': guilds, 'of': of}


def _q(name):
    assert NAME_RE.match(name) or name in GUILDS, name
    return "'%s'" % name


def guild_statements(pl):
    """the guilds of a plan, their three ranks and their members (TFS tables guilds, guild_ranks, guild_membership)"""
    st = []
    for g in pl.get('guilds', []):
        gq = _q(g['name'])
        st.append("INSERT INTO `guilds` (`name`, `ownerid`, `creationdata`, `motd`) SELECT %s, `id`, UNIX_TIMESTAMP(), '' "
                  "FROM `players` WHERE `name` = %s;" % (gq, _q(g['leader'])))
        for level, rank in ((3, 'Leader'), (2, 'Vice-Leader'), (1, 'Member')):
            # O656: the base schema's trigger oncreate_guilds already made the three ranks of a new guild; a second set made
            # two rows of each level and the member insert (a join on the level) two rows of one player: duplicate key
            st.append("INSERT INTO `guild_ranks` (`guild_id`, `name`, `level`) SELECT `id`, '%s', %d FROM `guilds` "
                      "WHERE `name` = %s AND NOT EXISTS (SELECT 1 FROM `guild_ranks` `x` WHERE `x`.`guild_id` = `guilds`.`id` "
                      "AND `x`.`level` = %d);" % (rank, level, gq, level))
        for m in g['members']:
            level = LEADER if m == g['leader'] else MEMBER
            st.append("INSERT INTO `guild_membership` (`player_id`, `guild_id`, `rank_id`, `nick`) "
                      "SELECT `p`.`id`, `g`.`id`, `r`.`id`, '' FROM `players` `p` JOIN `guilds` `g` ON `g`.`name` = %s "
                      "JOIN `guild_ranks` `r` ON `r`.`guild_id` = `g`.`id` AND `r`.`level` = %d WHERE `p`.`name` = %s;"
                      % (gq, level, _q(m)))
    return st


GUILD_TABLES = ('chaos_guild', 'chaos_guild_contrib', 'chaos_guild_log', 'chaos_guild_stats', 'chaos_guild_hall',
                'chaos_guild_upgrades', 'chaos_guild_depot', 'chaos_guildboss_week', 'chaos_guildboss_contrib',
                'chaos_guildboss_runs')


def clean_statements(present, tester_ids):
    """DELETEs of what closed mode made, by exact keys only: the guilds named GUILDS owned by a tester, the market book of
    realm REALM, arena matches whose every player is a tester, bazaar listings of testers. present: the table names that
    exist; tester_ids: player ids of the testers (empty: only the realm-keyed rows)"""
    present = set(present)
    ids = ','.join(str(int(i)) for i in sorted(set(tester_ids))) or '0'
    names = ', '.join("'%s'" % n for n in GUILDS)
    gsub = "(SELECT `id` FROM `guilds` WHERE `name` IN (%s) AND `ownerid` IN (%s))" % (names, ids)
    st = []

    def has(*tables):
        return all(t in present for t in tables)

    if has('guilds'):
        if has('chaos_guildwar_kills', 'chaos_guildwar'):
            st.append("DELETE FROM `chaos_guildwar_kills` WHERE `war_id` IN (SELECT `id` FROM `chaos_guildwar` WHERE "
                      "`guild1` IN %s OR `guild2` IN %s);" % (gsub, gsub))
        if has('chaos_guildwar'):
            st.append("DELETE FROM `chaos_guildwar` WHERE `guild1` IN %s OR `guild2` IN %s;" % (gsub, gsub))
        if has('guild_wars'):
            st.append("DELETE FROM `guild_wars` WHERE `guild1` IN %s OR `guild2` IN %s;" % (gsub, gsub))
        for t in GUILD_TABLES:
            if has(t) and SAFE_TABLE.match(t):
                st.append("DELETE FROM `%s` WHERE `guild_id` IN %s;" % (t, gsub))
        if has('guild_membership'):
            st.append("DELETE FROM `guild_membership` WHERE `guild_id` IN %s;" % gsub)
        if has('guild_ranks'):
            st.append("DELETE FROM `guild_ranks` WHERE `guild_id` IN %s;" % gsub)
        st.append("DELETE FROM `guilds` WHERE `name` IN (%s) AND `ownerid` IN (%s);" % (names, ids))
    if has('chaos_market_offers'):
        if has('chaos_market_offer_mods'):
            st.append("DELETE FROM `chaos_market_offer_mods` WHERE `offer_id` IN (SELECT `id` FROM `chaos_market_offers` "
                      "WHERE `realm` = %d);" % REALM)
        st.append("DELETE FROM `chaos_market_offers` WHERE `realm` = %d;" % REALM)
    if has('chaos_market_orders'):
        st.append("DELETE FROM `chaos_market_orders` WHERE `realm` = %d;" % REALM)
    for t in ('chaos_market_history', 'chaos_market_history_daily'):
        if has(t):
            st.append("DELETE FROM `%s` WHERE `realm` = %d;" % (t, REALM))
    if has('chaos_arena_matches', 'chaos_arena_match_players'):
        st.append("DELETE FROM `chaos_arena_matches` WHERE `id` IN (SELECT `match_id` FROM `chaos_arena_match_players` "
                  "WHERE `player_id` IN (%s)) AND `id` NOT IN (SELECT `match_id` FROM `chaos_arena_match_players` "
                  "WHERE `player_id` NOT IN (%s));" % (ids, ids))
    # the testers' own raids (O588): the member rows of testers in raids a tester led, then those raids when no member row is
    # left (a raid with a player in it is kept), and the lockouts, marks and vendor purchases of the testers. No statement reads the
    # table it deletes from (MySQL error 1093)
    if has(RAID_TABLES['instances'], RAID_TABLES['members']):
        st.append("DELETE FROM `%s` WHERE `player_id` IN (%s) AND `instance_id` IN (SELECT `id` FROM `%s` WHERE `leader_id` IN (%s));"
                  % (RAID_TABLES['members'], ids, RAID_TABLES['instances'], ids))
        st.append("DELETE FROM `%s` WHERE `leader_id` IN (%s) AND `id` NOT IN (SELECT `instance_id` FROM `%s`);"
                  % (RAID_TABLES['instances'], ids, RAID_TABLES['members']))
    for key in ('lockouts', 'players', 'purchases'):
        if has(RAID_TABLES[key]):
            st.append("DELETE FROM `%s` WHERE `player_id` IN (%s);" % (RAID_TABLES[key], ids))
    # the testers' dungeon rows (O589): their unlocked difficulties; a tester run is never stored on the boards (dungeons.lua), so no run row
    if has(DUNGEON_PROGRESS):
        st.append("DELETE FROM `%s` WHERE `player_id` IN (%s);" % (DUNGEON_PROGRESS, ids))
    if has('chaos_bazaar_listings'):
        if has('chaos_bazaar_bids'):
            st.append("DELETE FROM `chaos_bazaar_bids` WHERE `listing_id` IN (SELECT `id` FROM `chaos_bazaar_listings` "
                      "WHERE `player_id` IN (%s));" % ids)
        st.append("DELETE FROM `chaos_bazaar_listings` WHERE `player_id` IN (%s);" % ids)
    return st


def bazaar_statements(player_name, ends_in=600):
    """a closed-mode bazaar listing of one tester (the lock check): the character is listed for sale to nobody. The website
    never shows it and never takes a bid on it (bazaar_lib.php isTesterName); min_price 1, no bids, no Chaos Coins move"""
    assert NAME_RE.match(player_name)
    return ["INSERT INTO `chaos_bazaar_listings` (`player_id`, `seller_account_id`, `min_price`, `status`, `created_at`, "
            "`ends_at`, `player_name`, `level`, `vocation`) SELECT `id`, `account_id`, 1, 'active', UNIX_TIMESTAMP(), "
            "UNIX_TIMESTAMP() + %d, `name`, `level`, `vocation` FROM `players` WHERE `name` = '%s';" % (int(ends_in), player_name)]


def bazaar_release_statements(player_name):
    assert NAME_RE.match(player_name)
    return ["UPDATE `chaos_bazaar_listings` SET `status` = 'cancelled', `reason` = 'closed test mode', "
            "`settled_at` = UNIX_TIMESTAMP() WHERE `status` IN ('active', 'settling') AND `player_id` = "
            "(SELECT `id` FROM `players` WHERE `name` = '%s');" % player_name]
