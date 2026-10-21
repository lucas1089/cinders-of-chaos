#!/usr/bin/env python3
"""Tests of tools/loot_bands.py on a synthetic base data folder (no base server needed):
python3 -I server/tools/loot_bands_test.py"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import loot_bands as B  # noqa: E402

ITEMS = """<?xml version="1.0"?>
<items>
	<item id="2148" name="gold coin" />
	<item id="2160" name="crystal coin" />
	<item id="2392" name="fire sword">
		<attribute key="weaponType" value="sword" />
	</item>
	<item id="2476" name="knight armor">
		<attribute key="slotType" value="body" />
	</item>
	<item id="2544" name="arrow">
		<attribute key="weaponType" value="ammunition" />
		<attribute key="ammoType" value="arrow" />
	</item>
	<item fromid="3000" toid="3002" name="ring band">
		<attribute key="slotType" value="ring" />
	</item>
	<item id="7590" name="great mana potion" />
	<item id="29851" name="orb" />
	<item id="5021" name="pearl" />
</items>
"""

MONSTERS_XML = """<monsters>
	<monster name="Test Spider" file="test_spider.xml" />
	<monster name="Missing File" file="nope.xml" />
</monsters>
"""

SPIDER = """<monster name="Test Spider">
	<health now="40000" max="40000" />
	<loot>
		<item id="2160" countmax="7" chance="60000" />
		<item name="great mana potion" countmax="2" chance="19000" />
		<item id="2392" chance="900" />
		<item id="2476" chance="5000" />
		<item id="29851" countmax="4" chance="20000" />
		<item id="5021" chance="3000" />
		<item id="2544" countmax="10" chance="0" />
	</loot>
</monster>
"""

WIDOW_LUA = """local mType = Game.createMonsterType("Nightfang Widow")
local monster = {}
monster.health = 40000
monster.loot = {
	{id = "crystal coin", chance = 60000, maxCount = 7},
	{id = 3001, chance = 2000},
}
mType:register(monster)
"""

POOL = """return {
	hunt = {
		{name = "Test Spider", level = 509, exp = 45000, health = 40000, spawns = 47, look = 1},
		{name = "Nightfang Widow", level = 509, exp = 45000, health = 40000, spawns = 47, look = 1404},
		{name = "Low Rat", level = 3, exp = 5, health = 20, spawns = 90, look = 21},
		{name = "Scaled Thing", level = 300, exp = 100, health = 100, spawns = 10, look = 2},
	},
	bosses = {
		{name = "Big Boss", level = 500, exp = 1, health = 1, spawns = 1, look = 3},
	}
}
"""

PRICES = """return {
	prices = {
		[2392] = 4000, [2476] = 5000, [7590] = 120, [5021] = 0, [3001] = 700,
	},
	unsellable = {
		[29851] = "currency",
	},
}
"""

checks = failures = 0


def check(v, m):
    global checks, failures
    checks += 1
    if not v:
        failures += 1
        print("FAIL", m)


def write(root, rel, text):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text)


with tempfile.TemporaryDirectory() as tmp:
    data = os.path.join(tmp, "data")
    write(data, "items/items.xml", ITEMS)
    write(data, "monster/monsters.xml", MONSTERS_XML)
    write(data, "monster/test_spider.xml", SPIDER)
    write(data, "monster/lua/w/nightfang_widow.lua", WIDOW_LUA)

    gear = B.gear_ids(ITEMS)
    check(2392 in gear and 2476 in gear, "a weapon type and an equipment slot are gear")
    check(2544 not in gear, "ammunition is not gear")
    check({3000, 3001, 3002} <= gear, "a fromid / toid range")
    check(7590 not in gear, "a potion is not gear")

    prices, unsellable = B.price_tables(PRICES)
    check(prices[2392] == 4000 and 29851 in unsellable, "price tables read")

    check(B.estimate_level(45000, 40000) == 509, "the pool's level estimate: %d" % B.estimate_level(45000, 40000))
    check(B.hunt_level(509, 45000, 40000, 0, 0) == (1018, False), "a base monster: twice the pool level")
    check(B.hunt_level(300, 100, 100, 0, 0) == (300, True), "a pool level that is not the estimate: level-scaled")
    check(B.hunt_level(0, 0, 0, 640, 660) == (650, True), "min / max level: the middle")

    check(B.classify(2160, 7, prices, unsellable, gear) == ("coin", 10000), "crystal coins")
    check(B.classify(2392, 1, prices, unsellable, gear) == ("gear", 4000), "gear with its price")
    check(B.classify(7590, 2, prices, unsellable, gear) == ("junk", 120), "a potion is junk")
    check(B.classify(29851, 4, prices, unsellable, gear) == ("other", 0), "an orb is other")
    check(B.classify(5021, 1, prices, unsellable, gear) == ("other", 0), "no price: other")

    check(B.in_band(1018) and B.in_band(100) and B.in_band(1300), "band ranges (1500: the top of the pool)")
    check(not B.in_band(200) and not B.in_band(6), "outside every band")

    rows = B.build(data, POOL, PRICES)
    names = [r[0] for r in rows]
    check(names == ["Nightfang Widow", "Test Spider"], "the band monsters with a loot file, sorted: %s" % names)
    spider = dict((r[0], r) for r in rows)["Test Spider"]
    check(spider[1] == 1018 and spider[2] is False and spider[3] == 47, "level, kind, spawns")
    ids = [e[0] for e in spider[4]]
    check(2544 not in ids, "a chance of 0 is left out")
    check((7590, 19000, 2, "junk", 120) in spider[4], "a name resolved to its id")
    widow = dict((r[0], r) for r in rows)["Nightfang Widow"]
    check((2160, 60000, 7, "coin", 10000) in widow[4] and (3001, 2000, 1, "gear", 700) in widow[4], "a Lua monster file")

    text = B.render(rows)
    check(text.startswith("-- Loot of the hunting bands") and text.endswith("}\n"), "the Lua file's frame")
    check('{name = "Test Spider", level = 1018, scaled = false, spawns = 47, loot = {' in text, "a row")
    check(B.render(B.build(data, POOL, PRICES)) == text, "a rerun gives the same text")

    out = os.path.join(tmp, "bands.lua")
    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        B.SERVER = tmp  # read the pool and prices from the synthetic tree
        write(tmp, "data/scripts/chaos/bounty_pool.lua", POOL)
        write(tmp, "data/lib/chaos_item_prices_data.lua", PRICES)
        rc1 = B.main([data, "--out", out, "--check"])
        rc2 = B.main([data, "--out", out])
        rc3 = B.main([data, "--out", out, "--check"])
    check(rc1 == 1 and rc2 == 0 and rc3 == 0, "--check: out of date, written, up to date (%s %s %s)" % (rc1, rc2, rc3))

print("loot_bands_test: %d checks, %d failures" % (checks, failures))
sys.exit(1 if failures else 0)
