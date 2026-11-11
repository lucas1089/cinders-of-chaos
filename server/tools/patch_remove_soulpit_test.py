#!/usr/bin/env python3
"""Tests of patch_remove_soulpit.py and of the files that carry the removal (O488, server/README.md "Soul pit removed"):
python3 -I server/tools/patch_remove_soulpit_test.py

Part 1, the tool on synthetic copies of the base files (written here in the stock shape, LF and CRLF, made-up monsters):
dry run writes nothing; each change is made once; a second run says "already done" and changes no byte; the three pit
scripts become one-line stubs; Player:onGainExperience loses the table and its use (and the `sourceName` line when nothing
else reads it); the soul core and exalted core lines leave Lua and XML loot (a last entry without a comma too, an entry by
name too) and nothing else does; Iletrya's step gives the kit with no exalted cores; the recipe and the dust / sliver drop
go with nothing else; every description is "No longer used."; an id the stock pit names that IDS lacks is reported and
cleaned; a file of another shape is listed and left alone.
Part 2, with luajit when it is there: the patched player.lua gives a player who had the +3% bonus the plain experience; the
patched Iletrya gives the Waystone Portal Kit and sets the quest storage on "help" with no cores in the bag; the stubs
register nothing.
Part 3, the repository: the SQL file (server/sql/chaos_zz_soulpit_removal.sql) names the same ids as IDS, every statement
runs only when its table exists, it deletes no table; the price tables, the survey, the recipe table and the loot bands
have none of the ids (dust and sliver stay sellable); the install step comes after eventrooms; instance_limits_config has
no soul pit time; the pit's boss room wiring is gone from patch_base_eventrooms.py."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import patch_remove_soulpit as P

fails = 0


def check(cond, label):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + label)


def read(path):
    with open(path, 'rb') as f:
        return f.read().decode('utf-8')


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(text.encode('utf-8'))


def run(data, *flags):
    proc = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'patch_remove_soulpit.py'), data] + list(flags),
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return proc.returncode, proc.stdout


def tree(data):
    out = {}
    for base, _dirs, files in os.walk(data):
        for n in files:
            p = os.path.join(base, n)
            out[os.path.relpath(p, data)] = read(p)
    return out


# ------------------------------------------------------------------------------------------------ the synthetic base
SOULPIT = '''print(">> Soulpit System Loaded")
local event = {
    waves = {
        [28326] = {
            monsters = {{"angry mudling"}, {"wrathful mudling"}},
            storage = 876547,
            waves = 2,
            name = "Mudling"
        },
        [28999] = {
            monsters = {{"angry sprite"}},
            storage = 876999,
            waves = 1,
            name = "Sprite"
        },
    },
    spawnArea = {Position(1, 1, 8), Position(2, 2, 8)},
}
local config = {
    actionId = 57392,
}
local soulPit = Action()
function soulPit.onUse(player, item, fromPos, target, toPos, isHotkey)
    if ChaosBossRooms and target then return true end -- Chaos (patch_base_eventrooms.py)
    return true
end
soulPit:id(28326)
soulPit:register()
'''
TRANSFORM = '''local itemsRandom = {
    28327,
    28328
}

local exaltedCore = Action()
function exaltedCore.onUse(player, item, fromPos, target, toPos, isHotkey)
    return true
end
exaltedCore:id(28345)
exaltedCore:register()
'''
TELEPORT = '''local soulpitEntrance = MoveEvent()
function soulpitEntrance.onStepIn(player, item, position, fromPosition)
    return true
end
soulpitEntrance:type("stepin")
soulpitEntrance:aid(5896)
soulpitEntrance:register()
'''
PLAYER = '''local pet_id = 633453

local monsterExpBoosts = {
    ["mudling"] = 876547,
	["sprite"] = 876548
}

function Player:onGainExperience(source, exp, rawExp)
	if not source or source:isPlayer() then
		return exp
	end
	local sourceName = source:getName():lower()
    local storageValue = monsterExpBoosts[sourceName]
    if storageValue then
        if self:getStorageValue(storageValue) >= 1 then
            exp = exp * 1.03 -- Gives 3% EXP Boost Permanent to the monster - 1.00 = Normal, 1.03 = 3%, 2.00 = 100% Plus
        end
    end
	if source:isMonster() then
        exp = exp * 2
    end
	return exp
end
'''
PLAYER_SOURCE_USED = PLAYER.replace('	if source:isMonster() then', '	if sourceName == "x" then exp = 0 end\n	if source:isMonster() then')
ILETRYA = '''local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
local REWARD_ITEM = 29628 -- Waystone Portal Kit
local STORAGE_FINISHED = Expeditions.WaystoneDeviceFinished

local function creatureSayCallback(cid, type, msg)
    local player = Player(cid)
    msg = msg:lower()

    if msgcontains(msg, "help") then
        if player:getStorageValue(STORAGE_FINISHED) >= 1 then
            npcHandler:say("You already helped me.", cid)
            return true
        end
        if player:removeItem(28345, 10) then
            npcHandler:say("Thanks! Here is the Waystone Portal Kit.", cid)
            player:addItem(REWARD_ITEM, 1)
            player:setStorageValue(STORAGE_FINISHED, 1)
        else
            local have = player:getItemCount(28345)
            npcHandler:say(
                string.format("Collect or craft %d Exalted Core. You currently have %d/%d.", 10, have, 10),
                cid
            )
        end
        return true
    end

    return true
end

npcHandler:setMessage(MESSAGE_GREET,
'Look at this device. To repair it you need to {help} me with a small task. Are you interested?')
npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
'''
CRAFTING = '''local recipes = {
    {
        id = 28260,
        name = "Root Sickle",
        level = 20,
        materials = {
            {id = 28142, count = 1},
        }
    },
    {
        id = 28345,
        name = "Exalted Core",
        level = 20,
        cost = 1500,
        count = 1,
        storage = 0,
        storageText = "",
        materials = {
            {id = 28343, count = 40},
            {id = 28344, count = 15},
        }
    },
    {
        id = 29473,
        name = "mount scroll",
        level = 10,
        materials = {
            {id = 29474, count = 120},
        }
    },
}
'''
DROP = '''function drops(corpse, self)
    if math.random(1, 100) <= 3 then
        local quantity28343 = math.random(1, 5)
        local specialItem1 = corpse:addItem(28343, quantity28343)
        if not specialItem1 then
            print(string.format("could not add 28343 to %s", self:getName()))
        end

        local quantity28344 = math.random(1, 3)
        local specialItem2 = corpse:addItem(28344, quantity28344)
        if not specialItem2 then
            print(string.format("could not add 28344 to %s", self:getName()))
        end
    end

    if math.random(1, 100) <= 3 then
    local waystones = {
        {id=29845, chance=50},
    }
    end
end
'''
MONSTER_LUA = '''monster.loot = {
	{id = "gold coin", chance = 80000, maxCount = 100},
	{id = 28326, chance = 500},
	{id = "mudling soul core", chance = 500},
	{id = 2160, chance = 70}, -- crystal coin
	{id = 28345, chance = 90, maxCount = 2},
	{id = 28333, chance = 500}
}
'''
MONSTER_LUA_PLAIN = '''monster.loot = {
	{id = 2160, chance = 28333},
	{id = "gold coin", chance = 80000}
}
'''
MONSTER_XML = '''<monster name="Mudling" nameDescription="a mudling" race="blood" experience="10" speed="100">
	<loot>
		<item id="2148" countmax="100" chance="80000"/>
		<item id="28327" chance="500"/>
		<item id="7590" name="great mana potion" chance="28333" countmax="5"/>
		<item name="sprite soul core" chance="500"/>
	</loot>
</monster>
'''
ITEMS = '''<items>
	<item id="2148" article="a" name="gold coin" plural="gold coins"/>
	<item id="28326" article="a" name="mudling soul core">
	<attribute key="description" value="Offers a soul to the Soulpit. Combine with an exalted core to turn it into another soul core."/>
		<attribute key="weight" value="320" />
	</item>
	<item id="28327" article="a" name="sprite soul core">
		<attribute key="description" value="Offers a soul to the Soulpit."/>
		<attribute key="weight" value="320" />
	</item>
	<item id="28343" article="an" name="dust" plural="dust's">
	<attribute key="description" value="This item is used to create exalted cores on crafting table."/>
		<attribute key="weight" value="80"/>
	</item>
	<item id="28344" article="a" name="sliver" plural="slivers">
		<attribute key="weight" value="10"/>
	</item>
	<item id="28345" article="an" name="exalted core" plural="exalted cores">
		<attribute key="description" value="This item is used to transfrom Soul Cores to a random soul core."/>
		<attribute key="weight" value="260"/>
	</item>
	<item id="28999" article="a" name="made-up core">
		<attribute key="description" value="Offers a soul."/>
	</item>
	<item id="29000" article="a" name="other" />
</items>
'''


def crlf(s):
    return s.replace('\n', '\r\n')


def build(root, newline=lambda s: s):
    d = os.path.join(root, 'data')
    write(os.path.join(d, 'scripts/customs/soulpit_system/soulpit.lua'), newline(SOULPIT))
    write(os.path.join(d, 'scripts/customs/soulpit_system/transform_soulcores.lua'), newline(TRANSFORM))
    write(os.path.join(d, 'scripts/customs/soulpit_system/teleport.lua'), newline(TELEPORT))
    write(os.path.join(d, 'events/scripts/player.lua'), newline(PLAYER))
    write(os.path.join(d, 'npc/scripts/Iletrya.lua'), newline(ILETRYA))
    write(os.path.join(d, 'scripts/customs/crafting/generalcrafting.lua'), newline(CRAFTING))
    write(os.path.join(d, 'scripts/eventcallbacks/monster/default_onDropLoot.lua'), newline(DROP))
    write(os.path.join(d, 'monster/lua/soul_war/mudling.lua'), newline(MONSTER_LUA))
    write(os.path.join(d, 'monster/lua/other/plain.lua'), newline(MONSTER_LUA_PLAIN))
    write(os.path.join(d, 'monster/monsters/mudling.xml'), newline(MONSTER_XML))
    write(os.path.join(d, 'items/items.xml'), newline(ITEMS))
    return d


def part1():
    root = tempfile.mkdtemp(prefix='soulpit_test_')
    try:
        data = build(root)
        before = tree(data)
        rc, out = run(data, '--dry-run')
        check(rc == 0, 'dry run exits 0: %s' % out)
        check(tree(data) == before, 'dry run writes nothing')
        check(out.count('dry run, not written') >= 9, 'dry run reports what it would do: %s' % out)
        check('28999' in out and 'IDS lacks' in out, 'an id the stock pit names that IDS lacks is reported: %s' % out)

        rc, out = run(data)
        check(rc == 0, 'run exits 0')
        after = tree(data)
        for name in P.PIT_SCRIPTS:
            text = after['scripts/customs/soulpit_system/' + name]
            check(text.strip() == P.STUB_TEXT and text.startswith('--'), 'stub %s: one comment line, nothing registered' % name)
            check('Action(' not in text and 'MoveEvent(' not in text, 'stub %s registers nothing' % name)
        player = after['events/scripts/player.lua']
        check('monsterExpBoosts' not in player and '1.03' not in player and 'sourceName' not in player and 'storageValue' not in player,
              'player.lua: table, use and the unused sourceName line gone')
        check('exp = exp * 2' in player and 'function Player:onGainExperience' in player and 'local pet_id = 633453' in player,
              'player.lua: the rest stays')
        check('+3%' in player, 'player.lua: a comment says what went')
        lua = after['monster/lua/soul_war/mudling.lua']
        check(lua == 'monster.loot = {\n\t{id = "gold coin", chance = 80000, maxCount = 100},\n\t{id = 2160, chance = 70}, -- crystal coin\n}\n',
              'Lua loot: only the core lines go: %r' % lua)
        xml = after['monster/monsters/mudling.xml']
        check('28327' not in xml and 'soul core' not in xml and 'great mana potion' in xml and 'id="2148"' in xml, 'XML loot: core lines go, others stay')
        npc = after['npc/scripts/Iletrya.lua']
        check('28345' not in npc and 'removeItem' not in npc and 'Exalted' not in npc and 'player:addItem(REWARD_ITEM, 1)' in npc
              and 'player:setStorageValue(STORAGE_FINISHED, 1)' in npc and 'You already helped me.' in npc, 'Iletrya: the kit and the storage, no cores')
        check('{help} me with a small task' not in npc and 'you only need to {help} me' in npc, 'Iletrya: the greeting says no task')
        craft = after['scripts/customs/crafting/generalcrafting.lua']
        check('28345' not in craft and 'Exalted' not in craft and 'Root Sickle' in craft and 'mount scroll' in craft
              and craft.count('{') == craft.count('}'), 'recipe gone, the others stay, braces balanced')
        drop = after['scripts/eventcallbacks/monster/default_onDropLoot.lua']
        check('28343' not in drop and '28344' not in drop and 'waystones' in drop and drop.count('if math.random(1, 100) <= 3 then') == 1,
              'dust and sliver drop gone, the waystone drop stays')
        items = after['items/items.xml']
        for iid in (28326, 28327, 28343, 28344, 28345, 28999):
            m = re.search(r'<item id="%d"[^>]*>(.*?)</item>' % iid, items, re.S)
            check(m and m.group(1).count('description') == 1 and 'value="No longer used."' in m.group(1), 'description of %d' % iid)
        check('<item id="29000" article="a" name="other" />' in items and 'value="320"' in items, 'items.xml: other entries and attributes stay')
        check('Combine with' not in items and 'Soulpit' not in items, 'no old description text left')

        # the plain Lua line with a core id as a chance is left alone
        check('{id = 2160, chance = 28333}' in after['monster/lua/other/plain.lua'], 'a chance number that looks like an id is not touched')

        again = tree(data)
        rc, out2 = run(data)
        check(tree(data) == again, 'a second run changes no byte')
        check(out2.count('already done') >= 9 and 'patched' not in out2.replace('already done', '') and 'stubbed' not in out2,
              'a second run: already done: %s' % out2)

        # CRLF is kept
        data = build(os.path.join(root, 'crlf'), crlf)
        rc, out = run(data)
        after = tree(data)
        for rel in ('events/scripts/player.lua', 'npc/scripts/Iletrya.lua', 'scripts/customs/crafting/generalcrafting.lua',
                    'scripts/eventcallbacks/monster/default_onDropLoot.lua', 'monster/lua/soul_war/mudling.lua',
                    'monster/monsters/mudling.xml', 'items/items.xml', 'scripts/customs/soulpit_system/soulpit.lua'):
            text = after[rel]
            check(re.search(r'[^\r]\n', text) is None, 'CRLF kept: ' + rel)
        check('monsterExpBoosts' not in after['events/scripts/player.lua'] and '28345' not in after['npc/scripts/Iletrya.lua'], 'CRLF files patched too: %s' % out)

        # the sourceName line stays when something else reads it
        data = os.path.join(root, 'src', 'data')
        write(os.path.join(data, 'events/scripts/player.lua'), PLAYER_SOURCE_USED)
        rc, out = run(data)
        text = read(os.path.join(data, 'events/scripts/player.lua'))
        check('monsterExpBoosts' not in text and 'local sourceName' in text and 'sourceName == "x"' in text, 'sourceName stays when read elsewhere')

        # another shape: listed, left alone
        data = os.path.join(root, 'odd', 'data')
        odd_player = PLAYER.replace('if self:getStorageValue(storageValue) >= 1 then', 'if self:getStorageValue(storageValue) >= 2 then')
        odd_npc = ILETRYA.replace('player:removeItem(28345, 10)', 'player:removeItem(28345, 10) and true')
        write(os.path.join(data, 'events/scripts/player.lua'), odd_player)
        write(os.path.join(data, 'npc/scripts/Iletrya.lua'), odd_npc)
        write(os.path.join(data, 'scripts/customs/crafting/generalcrafting.lua'), CRAFTING + CRAFTING)
        rc, out = run(data)
        check(rc == 0 and out.count('unrecognised') == 3, 'other shapes: three listed: %s' % out)
        check(read(os.path.join(data, 'events/scripts/player.lua')) == odd_player
              and read(os.path.join(data, 'npc/scripts/Iletrya.lua')) == odd_npc
              and read(os.path.join(data, 'scripts/customs/crafting/generalcrafting.lua')) == CRAFTING + CRAFTING, 'and left alone')

        # an empty server folder: nothing to do, exit 0; a missing folder: exit 2
        empty = os.path.join(root, 'empty')
        os.makedirs(empty)
        rc, out = run(empty)
        check(rc == 0 and 'nothing to do' in out, 'nothing there: exit 0')
        rc, out = run(os.path.join(root, 'nope'))
        check(rc == 2, 'no folder: exit 2')
    finally:
        shutil.rmtree(root, ignore_errors=True)


# ------------------------------------------------------------------------------------------------ part 2, luajit
HARNESS_PLAYER = r'''
local text = io.open(arg[1], "rb"):read("*a")
Player = {}
local function monster(name)
	return {isPlayer = function() return false end, isMonster = function() return true end, getName = function() return name end}
end
local env = setmetatable({Player = Player}, {__index = _G})
assert(load(text, "=player.lua", "t", env))()
local p = {getStorageValue = function(_, k) return k == 876547 and 1 or -1 end}
print(Player.onGainExperience(p, monster("Mudling"), 100, 100))
'''
HARNESS_NPC = r'''
local text = io.open(arg[1], "rb"):read("*a")
local said, added, stored = {}, {}, {}
local cb
local handler = {say = function(_, t) said[#said + 1] = t end, setMessage = function() end,
	setCallback = function(_, _, f) cb = f end}
local env = setmetatable({
	KeywordHandler = {new = function() return {} end}, NpcHandler = {new = function() return handler end},
	Expeditions = {WaystoneDeviceFinished = 5000}, MESSAGE_GREET = 1, CALLBACK_MESSAGE_DEFAULT = 2,
	msgcontains = function(m, w) return m:find(w, 1, true) ~= nil end,
	Player = function() return {
		getStorageValue = function(_, k) return stored[k] or -1 end,
		setStorageValue = function(_, k, v) stored[k] = v end,
		removeItem = function() return false end,
		getItemCount = function() return 0 end,
		addItem = function(_, id, n) added[#added + 1] = id .. "x" .. n end}
	end}, {__index = _G})
assert(load(text, "=iletrya.lua", "t", env))()
cb(1, 0, "help")
print(table.concat(added, ","), stored[5000], #said)
'''
HARNESS_STUB = r'''
local reg = 0
local env = setmetatable({Action = function() return {id = function() end, register = function() reg = reg + 1 end} end,
	MoveEvent = function() return {type = function() end, aid = function() end, register = function() reg = reg + 1 end} end,
	Position = function() return {}  end}, {__index = _G})
for i = 1, #arg do assert(loadfile(arg[i], "t", env))() end
print(reg)
'''


def luajit_run(harness, *files):
    exe = shutil.which('luajit')
    if not exe:
        return None
    fd, path = tempfile.mkstemp(suffix='.lua')
    os.close(fd)
    try:
        with open(path, 'w') as f:
            f.write(harness)
        proc = subprocess.run([exe, path] + list(files), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
        return proc.stdout.strip()
    finally:
        os.unlink(path)


def part2():
    if not shutil.which('luajit'):
        print('patch_remove_soulpit_test: luajit not found, part 2 skipped')
        return
    root = tempfile.mkdtemp(prefix='soulpit_test_lua_')
    try:
        data = build(root)
        pl = os.path.join(data, 'events/scripts/player.lua')
        npc = os.path.join(data, 'npc/scripts/Iletrya.lua')
        got = luajit_run(HARNESS_PLAYER, pl)
        check(abs(float(got) - 206) < 1e-6, 'before: the player with the bonus gets 103 x2: %s' % got)
        got = luajit_run(HARNESS_NPC, npc)
        check(got == 'nil\t1', 'before: Iletrya asks for the cores, no kit: %r' % got)
        run(data)
        got = luajit_run(HARNESS_PLAYER, pl)
        check(abs(float(got) - 200) < 1e-6, 'after: the same player gets plain experience (x2 of the monster rule only): %s' % got)
        got = luajit_run(HARNESS_NPC, npc)
        check(got == '29628x1\t1\t1', 'after: "help" with no cores gives the kit, sets the storage, says one thing: %r' % got)
        stubs = [os.path.join(data, 'scripts/customs/soulpit_system', n) for n in P.PIT_SCRIPTS]
        check(luajit_run(HARNESS_STUB, *stubs) == '0', 'the stubs register nothing: %s' % luajit_run(HARNESS_STUB, *stubs))
        before = tempfile.mkdtemp(prefix='soulpit_test_lua2_')
        try:
            d2 = build(before)
            stock = [os.path.join(d2, 'scripts/customs/soulpit_system', n) for n in P.PIT_SCRIPTS]
            check(luajit_run(HARNESS_STUB, *stock).splitlines()[-1] == '3', 'before: the stock scripts register 3 things: %s' % luajit_run(HARNESS_STUB, *stock))
        finally:
            shutil.rmtree(before, ignore_errors=True)
        for base, _dirs, files in os.walk(data):
            for n in files:
                if n.endswith('.lua'):
                    p = os.path.join(base, n)
                    proc = subprocess.run(['luajit', '-bl', p], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                    check(proc.returncode == 0, 'parses after the patch: ' + n)
    finally:
        shutil.rmtree(root, ignore_errors=True)


# ------------------------------------------------------------------------------------------------ part 3, the repository
def repo(*parts):
    return os.path.join(SERVER, *parts)


def part3():
    check(len(P.SOUL_CORES) == 36 and P.EXALTED == 28345 and len(P.IDS) == 37, 'ids: 36 soul cores and the exalted core')
    check(28343 not in P.IDS and 28344 not in P.IDS and P.DEAD_MATERIALS == (28343, 28344), 'dust and sliver are not in IDS')
    sql = read(repo('sql', 'chaos_zz_soulpit_removal.sql'))
    m = re.search(r"SET @ids = '([0-9,]+)';", sql)
    check(m and [int(x) for x in m.group(1).split(',')] == list(P.IDS), 'the SQL file names the ids of IDS, in order')
    stmts = re.findall(r"^SET @q = IF\((.*?)\n  CONCAT\((.*?)\),\n  'DO 0'\);\nPREPARE s FROM @q; EXECUTE s; DEALLOCATE PREPARE s;$", sql, re.S | re.M)
    check(len(stmts) == 14, 'the SQL file has 14 guarded statements: %d' % len(stmts))
    tables = set()
    for cond, body in stmts:
        names = re.findall(r"'([a-z_]+)'", cond.split('TABLE_NAME IN')[1])
        check(all(re.search(r'`%s`' % n, body) for n in names[:1]), 'the guard names the table of its statement: ' + body[:60])
        check('@ids' in body, 'every statement uses the id list: ' + body[:60])
        check(not re.search(r'\b(DROP|TRUNCATE|ALTER)\b', body), 'no DROP / TRUNCATE / ALTER')
        tables.update(names)
        check(re.search(r'DELETE|UPDATE', body), 'a delete or an update')
    want = {'player_items', 'player_depotitems', 'player_inboxitems', 'player_storeinboxitems', 'market_offers', 'chaos_stash',
            'chaos_stash_items', 'chaos_stash_block', 'chaos_guild_depot', 'chaos_market_deliveries', 'chaos_market_offers',
            'chaos_market_offer_mods', 'chaos_market_orders'}
    check(tables == want, 'the tables of the SQL file: %s' % sorted(tables ^ want))
    check(not re.search(r'CREATE TABLE', sql), 'the SQL file creates no table (launch_wipe_tables.json stays right)')
    check(sql.count('DELETE d FROM') == 1 and "d.`kind` = ''item''" in sql and 'd.`delivered` = 0' in sql,
          'only owed item deliveries are deleted (a gold delivery is a player\'s gold)')
    check("`state` IN (0, 9)" in sql, 'only active and pending offers are deleted')
    check('SET `expires` = 1' in sql and 'SET `created` = 0' in sql, 'buy orders and base buy offers close through the server')

    ids = set(P.IDS)

    def numbers(path):
        return {int(x) for x in re.findall(r'\[(\d+)\] =', read(path))}

    for rel in (('data', 'scripts', 'chaos', 'sell_prices.lua'), ('data', 'lib', 'chaos_item_prices_data.lua')):
        have = numbers(repo(*rel))
        check(not (have & ids), 'no sell price of a removed item in %s' % rel[-1])
        check({28343, 28344} <= have, 'dust and sliver stay sellable in %s' % rel[-1])
    values = {int(l.split(',')[0]) for l in read(repo('data', 'items', 'base_item_values.csv')).split('\n')[1:] if l[:1].isdigit()}
    check(not (values & (ids | {28343, 28344})), 'the survey has no row of the removed items')
    recipes = {int(l.split(',')[0]) for l in read(repo('data', 'items', 'base_recipes.csv')).split('\n')[1:] if l[:1].isdigit()}
    check(28345 not in recipes, 'the recipe table has no exalted core')
    bands = read(repo('tools', 'loot_bands_data.lua'))
    check(not re.search(r'\{(?:%s), \d+, \d+, "[a-z]+", \d+\}' % '|'.join(str(i) for i in sorted(ids)), bands), 'the loot bands have no core')
    rules = read(repo('data', 'items', 'item_price_rules.csv'))
    check(re.search(r'^28343,material,120,', rules, re.M) and re.search(r'^28344,material,120,', rules, re.M), 'dust and sliver keep their price by rule')

    import install_all as I
    check('soulpit' in I.STEPS and I.STEPS.index('soulpit') > I.STEPS.index('eventrooms') and I.STEPS.index('soulpit') < I.STEPS.index('sql'),
          'the step soulpit runs after eventrooms and before sql')
    check(' soulpit ' in (I.__doc__ or '') and 'patch_remove_soulpit.py' in (I.__doc__ or ''), 'install_all docstring lists the step')

    cfg = read(repo('data', 'scripts', 'chaos', 'instance_limits_config.lua'))
    check(re.search(r'ownSeconds = \{towerdefense = 1200\}', cfg) and not re.search(r'soulpit\s*=', cfg), 'no soul pit time in instance_limits_config.lua')
    ev = read(os.path.join(HERE, 'patch_base_eventrooms.py'))
    check('SOULPIT' not in ev and 'soulpit_system' not in ev and 'getSpectators' not in ev, 'patch_base_eventrooms.py no longer wires the pit')


part1()
part2()
part3()
if fails:
    print('patch_remove_soulpit_test: %d FAILED' % fails)
    sys.exit(1)
print('patch_remove_soulpit_test: all checks passed')
