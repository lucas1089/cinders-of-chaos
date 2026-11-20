-- Spell showcase pack, the engine side (O692, TEST ONLY: server/README.md "Spell showcase video (O692)").
-- tools/ci/unity_live_check.sh with UL_SPELL_SHOWCASE=1 copies this file to data/scripts/zz_spell_showcase.lua and spell_showcase_core.lua to
-- data/scripts/zz_spell_showcase_core.lua of the run's own server, before tfs starts. It is never part of install_all.py and never in the
-- repository's server data.
--
-- Every ShowcaseCore.INTERVAL_MS a global event looks at the online characters named "Showcase Xxx" (staff characters made for the film,
-- ShowcaseCore.isShowcase) and, when fewer than ShowcaseCore.WANT monsters stand within ShowcaseCore.RADIUS tiles, makes the missing ones on
-- free tiles round the character (nearest first), so the spells of the film always have a target and the area spells hit something. The
-- monsters are stock ones (a Troll, else a Rotworm, else a Rat), made with Game.createMonster and left as they are: no monster or player
-- gets health, damage, a target or a status from this file. No other character is read.
-- Assumed engine API (TFS 1.4.2): GlobalEvent, Game.getPlayers, Game.getSpectators, Game.createMonster, Player:getName / getPosition,
-- Creature:isMonster. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ShowcaseCore or not ShowcaseCore.isShowcase then
	dofile("data/scripts/zz_spell_showcase_core.lua")
end
local C = ShowcaseCore

local monsterName -- the first stock monster the server knows, found at the first success

local function makeOne(pos)
	local names = monsterName and {monsterName} or C.MONSTERS
	for _, name in ipairs(names) do
		local ok, m = pcall(Game.createMonster, name, pos, false, true)
		if ok and m then
			monsterName = name
			return true
		end
	end
	return false
end

local function keepPack(player)
	local pos = player:getPosition()
	local near = Game.getSpectators(pos, false, false, C.RADIUS, C.RADIUS, C.RADIUS, C.RADIUS)
	local alive, occupied = 0, {}
	for _, c in ipairs(near or {}) do
		if c:isMonster() then
			alive = alive + 1
			local cp = c:getPosition()
			occupied[(cp.x - pos.x) .. "," .. (cp.y - pos.y)] = true
		end
	end
	local need = C.needed(alive)
	if need == 0 then
		return
	end
	for _, o in ipairs(C.freeOffsets(occupied)) do
		if need == 0 then
			break
		end
		if makeOne(Position(pos.x + o[1], pos.y + o[2], pos.z)) then
			need = need - 1
		end
	end
end

local think = GlobalEvent("ZzSpellShowcasePack")
function think.onThink(interval)
	for _, player in ipairs(Game.getPlayers()) do
		if C.isShowcase(player:getName()) then
			local ok, err = pcall(keepPack, player)
			if not ok then
				print("[spell showcase] " .. tostring(err))
			end
		end
	end
	return true
end
think:interval(C.INTERVAL_MS)
think:register()

print("[spell showcase] TEST ONLY: a pack of monsters is kept round the characters named \"" .. C.PREFIX .. "Xxx\"")
