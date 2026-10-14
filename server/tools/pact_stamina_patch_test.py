#!/usr/bin/env python3
"""Guard for patch_base_events.py steps 13 and 14: the Chaos Pact regenerates stamina x1.5 faster.

Owner 2026-10-13: "Vip ganha +10% de exp e restaura stamina mais rapido". The base server regenerates stamina in two
scripts that are not in this repository: the login script regeneratestamina.lua (offline time) and the stamina trainer
tile trainer_tile_stamina.lua (one minute every 120 s). This test patches copies of the stock text (below, as the base
ships them), checks the result is idempotent and refuses an unknown text, then runs both patched scripts with luajit
(or lua5.3) on a tiny mocked engine, with and without ChaosPactPerks (data/scripts/chaos/pact_perks.lua), and checks
the numbers: 6 h offline gives 120 stamina minutes, 180 with an active Pact; the trainer tile waits 120 s, 80 s with it.

Run: python3 -I server/tools/pact_stamina_patch_test.py (standard library; luajit or lua5.3 for the run part)."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_base_events as P  # noqa: E402

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

STOCK_TRAINER = (
    "local staminaOnTrainer = MoveEvent()\n"
    "\n"
    "local function Stamina(playerId, seconds)\n"
    "    local player = Player(playerId)\n"
    "    if seconds > 0 and player then\n"
    "            player:setStamina(player:getStamina() + 1)\n"
    "            player:sendTextMessage(MESSAGE_INFO_DESCR, \"Regenerating Stamina.\")\n"
    "        addEvent(Stamina, 120000, playerId, seconds - 1)\n"
    "    end\n"
    "end\n"
    "\n"
    "local coolDownStorageID = 327144\n"
    "local coolDownSeconds = 120\n"
    "\n"
    "function staminaOnTrainer.onStepIn(player, item, position, fromPosition)\n"
    "    if player:getStorageValue(coolDownStorageID) <= os.time() then\n"
    "        player:setStorageValue(coolDownStorageID, os.time() + (coolDownSeconds - 10))\n"
    "        return Stamina(player:getId(), coolDownSeconds)\n"
    "    end\n"
    "    return not player:sendCancelMessage(\"You are exhausted.\")\n"
    "end\n"
    "\n"
    "staminaOnTrainer:aid(47777)\n"
    "staminaOnTrainer:register()\n")

# the mocked engine: prints the stamina after login and the delay of the first trainer tick
HARNESS = r"""
local pact = ...
configManager = {getBoolean = function() return true end}
configKeys = {STAMINA_SYSTEM = 1}
MESSAGE_INFO_DESCR = 22
local now = 1000000
os.time = function() return now end
local pl = {stamina = 1000, st = {}}
function pl:getLastLogout() return now - 6 * 3600 - 600 end
function pl:getStamina() return self.stamina end
function pl:setStamina(v) self.stamina = v end
function pl:getId() return 1 end
function pl:getStorageValue(k) return self.st[k] or -1 end
function pl:setStorageValue(k, v) self.st[k] = v end
function pl:sendTextMessage() end
function pl:sendCancelMessage() end
Player = function() return pl end
if pact == "1" then
	ChaosPactPerks = {staminaMult = function() return 1.5 end,
		staminaRestMs = function(_, ms) return math.floor(ms / 1.5) end}
end
dofile(LOGIN)
onLogin(pl)
print("stamina " .. math.floor(pl.stamina + 0.5))
local delays = {}
addEvent = function(fn, ms) delays[#delays + 1] = ms end
local registered
MoveEvent = function()
	local e = {}
	function e:aid() end
	function e:register() registered = self end
	return e
end
dofile(TRAINER)
registered.onStepIn(pl)
print("tick " .. tostring(delays[1]))
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

    login, status = P.patch_offline_stamina(STOCK_LOGIN)
    check(status == 'patched', 'login script patched: ' + status)
    check(P.STAMINA_MARKER in login, 'login marker')
    check('offlineTime = offlineTime * ChaosPactPerks.staminaMult(player)' in login, 'offline time multiplied')
    check(login.index(P.STAMINA_MARKER) < login.index('if offlineTime < 180 then'), 'before the 3 minute check')
    again, status = P.patch_offline_stamina(login)
    check(status == 'already' and again == login, 'login idempotent')
    _, status = P.patch_offline_stamina('function onLogin(player) return true end\n')
    check(status.startswith('unexpected'), 'an unknown login script is left alone')

    trainer, status = P.patch_trainer_stamina(STOCK_TRAINER)
    check(status == 'patched', 'trainer tile patched: ' + status)
    check('addEvent(Stamina, 120000, playerId, seconds - 1)' not in trainer, 'the fixed 120 s is gone')
    check('ChaosPactPerks.staminaRestMs(player, 120000)' in trainer, 'the Pact interval asked')
    again, status = P.patch_trainer_stamina(trainer)
    check(status == 'already' and again == trainer, 'trainer idempotent')
    _, status = P.patch_trainer_stamina('local x = 1\n')
    check(status.startswith('unexpected'), 'an unknown trainer script is left alone')

    # CRLF files keep their line ends
    crlf, status = P.patch_offline_stamina(STOCK_LOGIN.replace('\n', '\r\n'))
    check(status == 'patched' and '\r\n' + '\t' + P.STAMINA_MARKER + '\r\n' in crlf, 'CRLF login')

    exe = lua()
    if exe is None:
        print('no lua interpreter: run part skipped')
    else:
        with tempfile.TemporaryDirectory() as tmp:
            paths = {}
            for name, text in (('login', login), ('trainer', trainer), ('stock_login', STOCK_LOGIN),
                               ('stock_trainer', STOCK_TRAINER)):
                paths[name] = os.path.join(tmp, name + '.lua')
                with open(paths[name], 'w', encoding='utf-8') as f:
                    f.write(text)

            def run(login_path, trainer_path, pact):
                harness = os.path.join(tmp, 'harness.lua')
                with open(harness, 'w', encoding='utf-8') as f:
                    f.write('LOGIN = %r\nTRAINER = %r\n' % (login_path, trainer_path) + HARNESS)
                out = subprocess.run([exe, harness, pact], capture_output=True, text=True, cwd=tmp)
                check(out.returncode == 0, 'lua run: ' + out.stderr.strip())
                return out.stdout.split()

            stock = run(paths['stock_login'], paths['stock_trainer'], '0')
            check(stock == ['stamina', '1120', 'tick', '120000'], 'stock: 6 h offline +120, 120 s: %s' % stock)
            plain = run(paths['login'], paths['trainer'], '0')
            check(plain == stock, 'patched, no Pact script: as stock: %s' % plain)
            pact = run(paths['login'], paths['trainer'], '1')
            check(pact == ['stamina', '1180', 'tick', '80000'], 'Pact: +180 and 80 s: %s' % pact)

    if failures:
        print('%d failure(s)' % len(failures))
        return 1
    print('pact_stamina_patch_test: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
