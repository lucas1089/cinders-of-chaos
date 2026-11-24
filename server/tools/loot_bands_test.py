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
    check(B.hunt_level(509, 45000, 40000, 0, 0) == (509, False), "a base monster: the pool level (baseLevelMult 1, O285)")
    check(B.hunt_level(300, 100, 100, 0, 0) == (300, True), "a pool level that is not the estimate: level-scaled")
    check(B.hunt_level(0, 0, 0, 640, 660) == (650, True), "min / max level: the middle")

    check(B.classify(2160, 7, prices, unsellable, gear) == ("coin", 10000), "crystal coins")
    check(B.classify(2392, 1, prices, unsellable, gear) == ("gear", 4000), "gear with its price")
    check(B.classify(7590, 2, prices, unsellable, gear) == ("junk", 120), "a potion is junk")
    check(B.classify(29851, 4, prices, unsellable, gear) == ("other", 0), "an orb is other")
    check(B.classify(5021, 1, prices, unsellable, gear) == ("other", 0), "no price: other")

    check(B.in_band(509) and B.in_band(100) and B.in_band(657), "band ranges (every base monster from 40)")
    check(not B.in_band(39) and not B.in_band(6), "outside every band")

    rows = B.build(data, POOL, PRICES)
    names = [r[0] for r in rows]
    check(names == ["Nightfang Widow", "Test Spider"], "the band monsters with a loot file, sorted: %s" % names)
    spider = dict((r[0], r) for r in rows)["Test Spider"]
    check(spider[1] == 509 and spider[2] is False and spider[3] == 47, "level, kind, spawns")
    ids = [e[0] for e in spider[4]]
    check(2544 not in ids, "a chance of 0 is left out")
    check((7590, 19000, 2, "junk", 120) in spider[4], "a name resolved to its id")
    widow = dict((r[0], r) for r in rows)["Nightfang Widow"]
    check((2160, 60000, 7, "coin", 10000) in widow[4] and (3001, 2000, 1, "gear", 700) in widow[4], "a Lua monster file")

    text = B.render(rows)
    check(text.startswith("-- Loot of the hunting bands") and text.endswith("}\n"), "the Lua file's frame")
    check('{name = "Test Spider", level = 509, scaled = false, spawns = 47, loot = {' in text, "a row")
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

    # O751: --late, the repository's own level-scaled monsters of hunting level LATE_FROM and up
    LATE_POOL = POOL.replace("\tbosses = {", "\t\t{name = \"Ash Drake\", level = 1, exp = 1, health = 1, spawns = 12, "
                             "minLevel = 880, maxLevel = 920, look = 5},\n\t\t{name = \"Gone Drake\", level = 1, exp = 1, "
                             "health = 1, spawns = 3, minLevel = 980, maxLevel = 1020, look = 6},\n\tbosses = {")
    LATE_PRICES = PRICES.replace("unsellable = {", "gear = {[3001] = 700},\n\tunsellable = {")
    write(tmp, "late/data/monster/ash_drake.xml", "<monster name=\"Ash Drake\">\n\t<health now=\"9000\" max=\"9000\" />\n\t<loot>\n"
          "\t\t<item id=\"2160\" countmax=\"3\" chance=\"50000\" />\n\t\t<item id=\"3001\" chance=\"1500\" />\n"
          "\t\t<item name=\"pearl\" chance=\"900\" />\n\t</loot>\n</monster>\n")
    check(B.gear_table(LATE_PRICES) == {3001}, "the gear ids of the price data")
    files = B.repo_monster_files(os.path.join(tmp, "late", "data"))
    check(list(files) == ["ash drake"], "the repository monster files by lower name: %s" % list(files))
    lrows, missing, by_name = B.build_late(os.path.join(tmp, "late", "data"), LATE_POOL, LATE_PRICES)
    check([r[0] for r in lrows] == ["Ash Drake"], "only the pool monsters of LATE_FROM and up with a file: %s" % lrows)
    check(missing == ["Gone Drake"] and by_name == 1, "a missing file and a loot entry by name are reported")
    drake = lrows[0] if lrows else ("", 0, False, 0, [])
    check(drake[1] == 900 and drake[2] is True and drake[3] == 12, "the middle of min / max, level-scaled, spawns")
    check((3001, 1500, 1, "gear", 700) in drake[4] and (2160, 50000, 3, "coin", 10000) in drake[4],
          "loot classified: %s" % (drake[4],))
    ltext = B.render(lrows, late=True)
    check("GENERATED by server/tools/loot_bands.py --late" in ltext and "level = 900, scaled = true" in ltext,
          "the late file's frame and row")
    lout = os.path.join(tmp, "late.lua")
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
        B.SERVER = os.path.join(tmp, "late")
        write(tmp, "late/data/scripts/chaos/bounty_pool.lua", LATE_POOL)
        write(tmp, "late/data/lib/chaos_item_prices_data.lua", LATE_PRICES)
        r1 = B.main(["--late", "--out", lout, "--check"])
        r2 = B.main(["--late", "--out", lout])
        r3 = B.main(["--late", "--out", lout, "--check"])
    check(r1 == 1 and r2 == 0 and r3 == 0, "--late --check: out of date, written, up to date (%s %s %s)" % (r1, r2, r3))

print("loot_bands_test: %d checks, %d failures" % (checks, failures))
sys.exit(1 if failures else 0)
