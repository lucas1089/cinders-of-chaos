#!/usr/bin/env python3
"""Tests of check_addhealth.py (O682): every one-argument line of the broken calls is refused, the fixed forms pass,
and the committed server Lua has none."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_addhealth as C  # noqa: E402

failures = 0


def check(cond, msg):
    global failures
    if not cond:
        failures += 1
        print("FAIL " + msg)


def bad(src):
    return len(C.check_text(src))


# the old lines of O682 (one argument): each is refused
OLD = {
    "cards leech": "if n > 0 then\n\tattacker:addHealth(n)\nend\n",
    "cards holy": "if n > 0 then\n\tM.holyAt[pid] = now\n\tattacker:addHealth(n)\nend\n",
    "newplayer fillUp": "if h > 0 then\n\tplayer:addHealth(h)\nend\n",
    "casting refund": "if health > 0 then\n\tplayer:addHealth(health)\nend\n",
    "snares drain": "owner:addHealth(drained)\n",
    "snares holy": "ally:addHealth(math.floor(ally:getMaxHealth() * holy.holy))\n",
    "testers_boss": "monster:addHealth(max - monster:getHealth())\n",
    "boss_mechanics add": "m:setMaxHealth(health)\nm:addHealth(health)\n",
    "boss_mechanics heal": "boss:addHealth(heal)\n",
    "boss_mechanics cut": "monster:addHealth(math.floor(hp * share) - monster:getHealth())\n",
    "invasion clash": "pcall(function() foe:addHealth(-dmg) end)\n",
    "tester_helper probe": "creature:addHealth(creature:getMaxHealth())\n",
    "tester_helper demon": "pcall(function() m:setMaxHealth(10000000) m:addHealth(10000000) end)\n",
    "vigils pool": "player:addHealth(back)\n",
    "pcall form": "pcall(p.addHealth, p, 5)\n",
    "multi line": "x:addHealth(\n\tmath.max(1, y)\n)\n",
    "receiver form": "Creature.addHealth(c, 5)\n",
}
for name, src in OLD.items():
    check(bad(src) == 1, "the old line is refused: " + name)

# the fixed forms and the stock fallback pairs pass
GOOD = {
    "heal": "Chaos.heal(attacker, n)\n",
    "two arguments": "creature:addHealth(\"healing\", n)\ncreature:addHealth(\"physical\", -n)\n",
    "pcall two": "pcall(player.addHealth, player, \"healing\", missing)\n",
    "fallback pair": "creature:addHealth(\"healing\", amount)\nif creature:getHealth() == before then\n\tcreature:addHealth(amount)\nend\n",
    "fallback pcall": "pcall(p.addHealth, p, \"damage\", n)\nif p:getHealth() == before then\n\tpcall(p.addHealth, p, -n)\nend\n",
    "comment": "-- creature:addHealth(5) heals nothing\n",
    "block comment": "--[[ x:addHealth(5)\n]]\n",
    "string": "local s = \"x:addHealth(5)\"\n",
    "name only": "add = \"addHealth\"\n",
    "pattern": "code:find(\":addHealth%s*%(\")\n",
    "no call": "cfg.addHealthPerExtraPlayer = 0.5\n",
    "no args": "x:addHealth()\n",
}
for name, src in GOOD.items():
    check(bad(src) == 0, "passes: " + name)

# a fallback too far below its pair, the arguments the wrong way round
far = "c:addHealth(\"healing\", n)\n" + "\n" * 6 + "c:addHealth(n)\n"
check(bad(far) == 1, "a one-argument call far from a two-argument call is refused")
check(bad("c:addHealth(5, \"healing\")\n") == 1, "number first: refused")
check(bad("c:addHealth(\"healing\", 5)\n") == 0, "type first: fine")

# the line number is reported
check(C.check_text("a = 1\nb = 2\nc:addHealth(n)\n")[0][0] == 3, "the line number")

# the committed server Lua has none
check(C.main() == 0, "the committed server Lua has no one-argument addHealth")

print("check_addhealth_test: %d failures" % failures)
sys.exit(1 if failures else 0)
