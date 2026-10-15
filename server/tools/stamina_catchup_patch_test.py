#!/usr/bin/env python3
"""Guard for patch_base_events.py steps 16 and 17: low stamina cuts the loot (never zero) and stamina comes back
faster offline (data/scripts/chaos/catchup.lua, catchup_config.lua; server/README.md "Time-friendly progression").

The base server's loot callback (default_onDropLoot.lua) and login script (regeneratestamina.lua) are not in this
repository. This test patches copies of their stock lines (the parts the steps touch, below), after step 2 as the
installer runs them, checks the result is idempotent and refuses an unknown text, then runs both with luajit (or
lua5.3) on a tiny mocked engine:
  * loot: an entry of chance 1000 rolled at 600 drops at full stamina; at low stamina with ChaosCatchup (x0.5) it
    does not (600 > 500) and at 400 it does; without ChaosCatchup low stamina keeps the stock "nothing" line.
  * offline: 6 h offline give 120 stamina minutes stock, 240 with ChaosCatchup (x2), 360 with the Pact (x1.5) too.

Run: python3 -I server/tools/stamina_catchup_patch_test.py (standard library; luajit or lua5.3 for the run part)."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_base_events as P  # noqa: E402

# the stock loot callback, cut to the lines steps 2, 10 and 16 read (the gate, the rarity roll and the loot loop)
STOCK_LOOT = (
    "local ec = EventCallback\n"
    "\n"
    "local rarities = {{id = 1, chance = 15.0}}\n"
    "\n"
    "local function rollRarity()\n"
    "    if math.random(100) > 70 then\n"
    "        return 0\n"
    "    end\n"
    "\n"
    "    for _, r in ipairs(rarities) do\n"
    "        local roll = math.random(100)\n"
    "        if roll <= r.chance then\n"
    "            return r.id\n"
    "        end\n"
    "    end\n"
    "    return 0\n"
    "end\n"
    "\n"
    "ec.onDropLoot = function(self, corpse)\n"
    "    local mType  = self:getType()\n"
    "    local player = Player(corpse:getCorpseOwner())\n"
    "\n"
    "    if not player then\n"
    "        return\n"
    "    end\n"
    "\n"
    "    if player:getStamina() <= 840 then\n"
    "        local text = (\"Loot of %s: nothing (due to low stamina)\")\n"
    "            :format(mType:getNameDescription())\n"
    "        player:sendTextMessage(MESSAGE_LOOT, text)\n"
    "        return\n"
    "    end\n"
    "\n"
    "    for _, lootData in ipairs(mType:getLoot()) do\n"
    "        local roll = getLootRandom()\n"
    "            if roll <= lootData.chance then\n"
    "                local newItem = corpse:addItem(lootData.itemId, 1)\n"
    "                if newItem then\n"
    "                    local rarityId = rollRarity(player)\n"
    "                end\n"
    "            end\n"
    "    end\n"
    "\n"
    "    local text = (\"Loot of %s: %s\"):format(mType:getNameDescription(), \"items\")\n"
    "    player:sendTextMessage(MESSAGE_LOOT, text)\n"
    "end\n"
    "\n"
    "ec:register()\n")

STOCK_LOGIN = (
    "function onLogin(player)\n"
    "\tif not configManager.getBoolean(configKeys.STAMINA_SYSTEM) then\n"
    "\t\treturn true\n"
    "\tend\n"
    "\n"
    "\tlocal lastLogout = player:getLastLogout()\n"
    "\tlocal offlineTime = lastLogout ~= 0 and math.min(os.time() - lastLogout, 86400 * 21) or 0\n"
    "\tofflineTime = offlineTime - 600\n"
    "\n"
    "\tif offlineTime < 180 then\n"
    "\t\treturn true\n"
    "\tend\n"
    "\n"
    "\tlocal staminaMinutes = player:getStamina()\n"
    "\tlocal maxNormalStaminaRegen = 2400 - math.min(2400, staminaMinutes)\n"
    "\n"
    "\tlocal regainStaminaMinutes = offlineTime / 180\n"
    "\tif regainStaminaMinutes > maxNormalStaminaRegen then\n"
    "\t\tlocal happyHourStaminaRegen = (offlineTime - (maxNormalStaminaRegen * 180)) / 600\n"
    "\t\tstaminaMinutes = math.min(2520, math.max(2400, staminaMinutes) + happyHourStaminaRegen)\n"
    "\telse\n"
    "\t\tstaminaMinutes = staminaMinutes + regainStaminaMinutes\n"
    "\tend\n"
    "\n"
    "\tplayer:setStamina(staminaMinutes)\n"
    "\treturn true\n"
    "end\n")

# args: stamina, roll, catchup ("1" / "0"), pact ("1" / "0"); prints "drops N lines L stamina S"
HARNESS = r"""
local stamina, roll, catchup, pact = tonumber(arg[1]), tonumber(arg[2]), arg[3] == "1", arg[4] == "1"
configManager = {getBoolean = function() return true end}
configKeys = {STAMINA_SYSTEM = 1}
MESSAGE_LOOT = 1
local now = 1000000
os.time = function() return now end
local lines = {}
local pl = {stamina = stamina, st = {}}
function pl:getStamina() return self.stamina end
function pl:setStamina(v) self.stamina = v end
function pl:getLastLogout() return now - 6 * 3600 - 600 end
function pl:getStorageValue(k) return self.st[k] or -1 end
function pl:sendTextMessage(_, text) lines[#lines + 1] = text end
Player = function() return pl end
getLootRandom = function() return roll end
if catchup then
	ChaosCatchup = {staminaLootMult = function(p) return p:getStamina() <= 840 and 0.5 or 1 end,
		offlineStaminaMult = function() return 2 end}
end
if pact then
	ChaosPactPerks = {staminaMult = function() return 1.5 end}
end
local registered
EventCallback = {register = function(self) registered = self end}
dofile(LOOT)
local drops = 0
local corpse = {getCorpseOwner = function() return 1 end, addItem = function() drops = drops + 1 return {} end}
local monster = {getType = function() return {getNameDescription = function() return "a rat" end,
	getLoot = function() return {{itemId = 1, chance = 1000}} end} end}
registered.onDropLoot(monster, corpse)
local nothing = 0
for _, l in ipairs(lines) do
	if l:find("nothing", 1, true) then nothing = nothing + 1 end
end
dofile(LOGIN)
pl.stamina = 1000
onLogin(pl)
print("drops " .. drops .. " nothing " .. nothing .. " stamina " .. math.floor(pl.stamina + 0.5))
"""


def lua():
    for name in ('luajit', 'lua5.3', 'lua'):
        path = shutil.which(name)
        if path:
            return path
    return None


def main():
    failures = []

    def check(cond, label):
        if not cond:
            failures.append(label)
            print('FAIL ' + label)

    # the installer's order: step 2 (waystone loot) before step 16
    loot, status = P.patch_loot(STOCK_LOOT)
    check(status == 'patched', 'step 2 on the stock copy: ' + status)
    loot, status = P.patch_low_stamina_loot(loot)
    check(status == 'patched', 'step 16 patched: ' + status)
    check(P.LOWLOOT_MARKER in loot, 'loot marker')
    check('* chaosStaminaLootMult(player) then' in loot, 'the loot chance is x the factor')
    check('if player:getStamina() <= 840 and chaosStaminaLootMult(player) <= 0 then' in loot, 'the gate asks the factor')
    check(loot.index(P.LOWLOOT_MARKER) < loot.index('ec.onDropLoot = function'), 'the helper comes first')
    again, status = P.patch_low_stamina_loot(loot)
    check(status == 'already' and again == loot, 'loot idempotent')
    alone, status = P.patch_low_stamina_loot(STOCK_LOOT)
    check(status == 'patched', 'step 16 also works without step 2')
    _, status = P.patch_low_stamina_loot('ec.onDropLoot = function(self, corpse) end\n')
    check(status.startswith('unexpected'), 'an unknown loot script is left alone')

    login, status = P.patch_offline_stamina(STOCK_LOGIN)
    check(status == 'patched', 'step 13 on the stock copy: ' + status)
    login, status = P.patch_offline_catchup(login)
    check(status == 'patched', 'step 17 patched: ' + status)
    check('offlineTime = offlineTime * ChaosCatchup.offlineStaminaMult(player)' in login, 'offline time multiplied')
    check(login.index(P.OFFLINE_MARKER) < login.index('if offlineTime < 180 then'), 'before the 3 minute check')
    again, status = P.patch_offline_catchup(login)
    check(status == 'already' and again == login, 'login idempotent')
    _, status = P.patch_offline_catchup('function onLogin(player) return true end\n')
    check(status.startswith('unexpected'), 'an unknown login script is left alone')
    crlf, status = P.patch_offline_catchup(STOCK_LOGIN.replace('\n', '\r\n'))
    check(status == 'patched' and '\r\n' + '\t' + P.OFFLINE_MARKER + '\r\n' in crlf, 'CRLF login')

    exe = lua()
    if exe is None:
        print('no lua interpreter: run part skipped')
    else:
        with tempfile.TemporaryDirectory() as tmp:
            paths = {}
            for name, text in (('loot', loot), ('login', login), ('stock_loot', STOCK_LOOT),
                               ('stock_login', STOCK_LOGIN)):
                paths[name] = os.path.join(tmp, name + '.lua')
                with open(paths[name], 'w', encoding='utf-8') as f:
                    f.write(text)
            harness = os.path.join(tmp, 'harness.lua')

            def run(lootf, loginf, stamina, roll, catchup, pact):
                with open(harness, 'w', encoding='utf-8') as f:
                    f.write('LOOT = %r\nLOGIN = %r\n' % (lootf, loginf) + HARNESS)
                out = subprocess.run([exe, harness, str(stamina), str(roll), catchup, pact], capture_output=True,
                                     text=True, cwd=tmp)
                check(out.returncode == 0, 'lua run: ' + out.stderr.strip())
                return out.stdout.split()

            stock = run(paths['stock_loot'], paths['stock_login'], 600, 400, '0', '0')
            check(stock == ['drops', '0', 'nothing', '1', 'stamina', '1120'], 'stock: nothing at low stamina: %s' % stock)
            full = run(paths['loot'], paths['login'], 2000, 600, '1', '0')
            check(full[:4] == ['drops', '1', 'nothing', '0'], 'full stamina: the chance as before: %s' % full)
            low = run(paths['loot'], paths['login'], 600, 600, '1', '0')
            check(low == ['drops', '0', 'nothing', '0', 'stamina', '1240'],
                  'low stamina: half chance (600 > 500), no "nothing" line; 6 h offline +240: %s' % low)
            low2 = run(paths['loot'], paths['login'], 600, 400, '1', '0')
            check(low2[:2] == ['drops', '1'], 'low stamina: a roll under half the chance drops: %s' % low2)
            plain = run(paths['loot'], paths['login'], 600, 400, '0', '0')
            check(plain == stock, 'patched, no catchup script: as stock: %s' % plain)
            both = run(paths['loot'], paths['login'], 2000, 400, '1', '1')
            check(both[-2:] == ['stamina', '1360'], 'catchup x2 and Pact x1.5: +360: %s' % both)

    if failures:
        print('%d failure(s)' % len(failures))
        return 1
    print('stamina_catchup_patch_test: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
