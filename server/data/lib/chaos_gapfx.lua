-- chaos_gapfx.lua: effects for roles that had none (O606, client pair 73; the art is in the sprite pair only,
-- client/tools/sprites/gen_gap_fx.py, docs/CREDITS.md). 48 effects of a purchased effect set at the ids 5190..5237 for
-- events that sent no effect of their own (nothing, a stock puff or the shared yellow firework): progress, rewards, boss
-- marks, portals, snares, professions, world. Nothing that had its own effect is replaced, with one owner order: the boss
-- warning pulse (warning_zone, warning_fill) becomes the set's strike circle. Looks only: no damage, no timing, no area.
--
-- Gate: config.lua `chaosClientPair` (README "Client pair guard") is 73 or more, read from the file at load (C.ON). A
-- client on pair 72 has no effect 5190+, so below 73 nothing here sends and every sender does exactly what it did.
--
-- How a sender asks:
--   if not (ChaosGapFx and ChaosGapFx.at(pos, "daily")) then <the line of before> end     -- in place of a shared effect
--   if ChaosGapFx then ChaosGapFx.on(player, "talent_point") end                           -- where nothing was sent
-- at / on / to return true when the effect went out, false when the gate is off or the key is not known.
-- The keys are C.events. The ids and send offsets are the generated data/lib/chaos_gapfx_ids.lua. Plain Lua, no engine
-- call at load (server/tests/gapfx_test.lua).

local C = {}

C.PAIR = 73

-- game_telegraph draws the exact tiles of a boss area as a floor mark and its players get no sprite pulse (O549). With the
-- gate on they also get the strike circle on the 3 x 3 slots of the area, over the floor mark. false: only players
-- without the module see the strike circle, as the red pulse of before.
C.onModuleClients = true

function C.parsePair(text)
	if type(text) ~= "string" then
		return nil
	end
	local v = text:match("^%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*$") or text:match("\n%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*")
	return v and tonumber(v) or nil
end

function C.recordedPair(path)
	local f = io.open(path or "config.lua", "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return C.parsePair(text)
end

-- the gate, read once at load; tests set it by hand
C.ON = (C.recordedPair() or 0) >= C.PAIR

-- key = the effect; the sender is named for the docs and the test (server/README.md "Effects for roles that had none")
C.events = {
	-- progress
	talent_point = "gx_talent_point", -- passivetree.lua: new nodes saved or a plan applied
	class_unlock = "gx_class_unlock", -- class_unlocks.lua: a class unlocked
	spell_mastery = "gx_spell_mastery", -- spell_masteries.lua: a mastery chosen
	paragon = "gx_paragon", -- paragon.lua: Paragon points spent
	title = "gx_title", -- descent.lua: a title earned
	rank_up = "gx_rank_up", -- professions.lua: a profession level
	class_change = "gx_class_change", -- ascension.lua: the ascension
	milestone_bronze = "gx_milestone_bronze", -- milestones.lua: a level milestone, by quarter of the list
	milestone_silver = "gx_milestone_silver",
	milestone_gold = "gx_milestone_gold",
	milestone_diamond = "gx_milestone_diamond",
	respec = "gx_respec", -- passivetree.lua, respec.lua: a reset
	-- rewards
	quest_complete = "gx_quest_complete", -- mainquest.lua: a chapter done
	daily = "gx_daily", -- daily.lua: the daily reward
	bounty = "gx_bounty", -- bounty.lua: a bounty paid
	chest_royal = "gx_chest_royal", -- weeklychest.lua, cursedchest.lua: the chest opens
	season_tier = "gx_season_tier", -- seasonpass.lua: a tier claimed
	set_complete = "gx_set_complete", -- itemsets.lua: a set piece found
	card_common = "gx_card_common", -- cards.lua: a new card
	card_rare = "gx_card_rare", -- cards.lua: a new card above Common
	relic = "gx_relic", -- uber.lua: a relic
	jackpot = "gx_jackpot", -- prizes.lua: a unique from a roulette
	masterwork = "gx_masterwork", -- crafting.lua: the best outcome
	-- boss marks
	tele_zone = "gx_tele_zone", -- the danger pulse of a boss area (the four senders of warnEffect)
	tele_fill = "gx_tele_fill", -- the last pulse before the hit
	spread = "gx_spread", -- boss_mechanics.lua: puddles on players
	chase = "gx_chase", -- boss_mechanics.lua: the follow circle's target
	safe_zone = "gx_safe_zone", -- boss_mechanics.lua: cover from a line of sight attack
	countdown = "gx_countdown", -- boss_mechanics.lua: the end of a channel
	meteor_shadow = "gx_meteor_shadow", -- boss_mechanics.lua: the puddles of a meteor attack, before the hit
	-- portals
	gate = "gx_gate", -- townportal.lua: a style without a loop
	rift_open = "gx_rift_open", -- rift.lua: the way in
	rift = "gx_rift", -- rift.lua: a breach
	rift_close = "gx_rift_close", -- rift.lua: the way out
	waystone = "gx_waystone", -- waystone_mods.lua: a waystone used
	dungeon_beacon = "gx_dungeon_beacon", -- dungeons.lua: the entrance
	spawn_in = "gx_spawn_in", -- raid.lua: a raid boss appears
	-- snares
	mine_armed = "gx_mine_armed", -- spells/chaos/_snares.lua
	trap_spikes = "gx_trap_spikes",
	-- professions
	mining = "gx_mining", -- professions.lua
	herb = "gx_herb",
	fishing = "gx_fishing",
	craft_success = "gx_craft_success", -- crafting.lua
	craft_fail = "gx_craft_fail",
	enchant = "gx_enchant", -- gems.lua
	-- world
	boss_beacon = "gx_boss_beacon", -- worldboss.lua: where the boss will appear, while the players gather
	summon_gate = "gx_summon_gate", -- uber.lua, guildboss.lua: adds
	rift_seal = "gx_rift_seal", -- rift.lua: the arrival point
}

-- the boss warning pulse: the name a config asks -> the key (owner order of O606)
C.telegraphKeys = {warning_zone = "tele_zone", warning_fill = "tele_fill"}

-- the gate on and the ids known: the generated table is merged once into ChaosVfx
function C.live()
	if not C.ON then
		return false
	end
	if C.loaded == nil then
		C.loaded = false
		if not ChaosVfx and dofile then
			pcall(dofile, "data/lib/chaos_vfx.lua")
		end
		if not ChaosGapFxIds and dofile then
			pcall(dofile, "data/lib/chaos_gapfx_ids.lua")
		end
		local I = ChaosGapFxIds
		if I and ChaosVfx then
			for name, e in pairs(I.effects) do
				ChaosVfx[name] = {id = e.id, dx = e.dx, dy = e.dy, ms = e.ms}
			end
			C.loaded = true
		end
	end
	return C.loaded
end

-- the effect entry of a key ({id, dx, dy, ms}) and its name, or nil (gate off, no such key, the id not known)
function C.entry(key)
	local name = type(key) == "string" and C.events[key] or nil
	if not name or not C.live() then
		return nil
	end
	local e = ChaosVfx[name]
	if not e then
		return nil
	end
	return e, name
end

-- the ChaosVfx name of a key, or nil
function C.name(key)
	local _, name = C.entry(key)
	return name
end

-- how long the effect of a key plays, in ms (0 when it would not be sent)
function C.ms(key)
	local e = C.entry(key)
	return e and e.ms or 0
end

local function xyz(pos)
	if type(pos) ~= "table" and type(pos) ~= "userdata" then
		return nil
	end
	local ok, x, y, z = pcall(function()
		return pos.x, pos.y, pos.z
	end)
	if not ok or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return nil
	end
	return x, y, z
end

-- the effect of `key` at a position; who = one player (only that client gets it) or nil (everybody near)
function C.to(who, pos, key)
	local e = C.entry(key)
	if not e or not Position then
		return false
	end
	local x, y, z = xyz(pos)
	if not x then
		return false
	end
	local p = Position(x + e.dx, y + e.dy, z)
	if who then
		p:sendMagicEffect(e.id, who)
	else
		p:sendMagicEffect(e.id)
	end
	return true
end

function C.at(pos, key)
	return C.to(nil, pos, key)
end

-- the effect of `key` over a creature (it is not sent for one that is gone)
function C.on(creature, key)
	if not creature or not C.entry(key) then
		return false
	end
	local ok, pos = pcall(function()
		return creature:getPosition()
	end)
	if not ok or not pos then
		return false
	end
	return C.to(nil, pos, key)
end

-- the name a boss warning pulse sends: the strike circle with the gate on, else the name asked
function C.telegraph(name)
	local key = type(name) == "string" and C.telegraphKeys[name] or nil
	return key and C.name(key) or name
end

-- do the players with game_telegraph get the strike circle over their floor mark?
function C.onModule()
	return C.onModuleClients == true and C.name("tele_zone") ~= nil
end

-- the milestone effect by where the level stands in the ascending list of milestone levels (quarters)
function C.milestoneKey(index, count)
	index, count = tonumber(index), tonumber(count)
	if not index or not count or count < 1 then
		return "milestone_bronze"
	end
	local q = math.ceil(index * 4 / count)
	if q <= 1 then
		return "milestone_bronze"
	elseif q == 2 then
		return "milestone_silver"
	elseif q == 3 then
		return "milestone_gold"
	end
	return "milestone_diamond"
end

ChaosGapFx = C
return C
