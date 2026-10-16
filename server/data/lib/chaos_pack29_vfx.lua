-- Pair 29, second part: condition auras, element blasts, missiles, fireworks and hit splashes of the five effect
-- packs (animated, one studio) the owner bought on 2026-10-16, used as the owner and the coordinator agreed. Effects
-- only: no damage, chance, timing, target or reward changes.
-- The art: client/tools/sprites/gen_pack29_vfx.py (art_import/pack29_vfx.csv), appended to pair 29 after the Mystic
-- effects and the Archmage (effects 780-829, missiles 170-185) by import_fx_art.py, which wrote the ids to
-- data/lib/chaos_pack29_vfx_ids.lua.
--
-- Switch: the pair 29 one, ChaosPack29Fx.PAIR29 (data/lib/chaos_pack29_fx.lua), OFF until pair 29 is live on the
-- clients. Off, nothing changes: the ids file is not loaded, no engine override is set and every call site sends what
-- it sent before. On:
--   * the engine (src-patch 0045, Game.setHitEffect / Game.setMissileEffect, set once by C.applyEngine at startup):
--     the tick of a damage condition shows its aura on the creature (C.conditionTicks), a physical hit on a blood or
--     fire creature the pack's splash (C.raceHits), a direct element hit a blast (C.elementHits), and the stock and
--     procedural element missiles the pack's bolts (C.missiles). An engine without the patch: nothing set.
--   * Lua (C.names): the spells' small element hits and procedural bursts (ChaosSpell.fx / vfx during a cast) send a
--     blast; the Mystic swaps of chaos_pack29_fx.lua come first.
--   * the other auras (C.auras): sent again while the state lasts (C.hold, one addEvent chain per creature and
--     state, at most C.maxHeld), from the call sites that know the state (slows, stuns, chill and shock, status words,
--     boss phases) and from a light scan of the online players (scripts/chaos/pack29_vfx.lua).
--   * celebrations (C.celebrate): the level-up, achievement and boss kill fireworks; boss deaths a big blast.
-- Lua 5.1 / LuaJIT / 5.3; the pure parts (pick, auraFor, celebration, throttle) run without the engine
-- (server/tests/pack29_vfx_test.lua).

ChaosPack29Vfx = ChaosPack29Vfx or {}
local C = ChaosPack29Vfx

-- a state -> its aura (the status pack: all sixteen). Silenced and petrified have no game mechanic yet: imported, unused.
C.auras = {
	burning = "cond_burning", poison = "cond_poison", frozen = "cond_frozen", slowed = "cond_slowed",
	shocked = "cond_shocked", bleeding = "cond_bleeding", cursed = "cond_cursed", stunned = "cond_stunned",
	fear = "cond_fear", silenced = "cond_silenced", confused = "cond_confused", regeneration = "cond_regeneration",
	blessed = "cond_blessed", enraged = "cond_enraged", invulnerable = "cond_invulnerable",
	petrified = "cond_petrified",
}

-- engine, kind 2: the tick of a damage condition of this combat type shows the aura instead of the stock hit sparks
C.conditionTicks = {
	COMBAT_FIREDAMAGE = "burning", COMBAT_EARTHDAMAGE = "poison", COMBAT_ENERGYDAMAGE = "shocked",
	COMBAT_PHYSICALDAMAGE = "bleeding", COMBAT_ICEDAMAGE = "frozen", COMBAT_DEATHDAMAGE = "cursed",
}

-- engine, kind 0: a physical hit on a creature of this race (RaceType_t: 1 venom, 2 blood, 3 undead, 4 fire,
-- 5 energy). The blood pack is red only: venom, undead and energy keep the stock hit. The splash item stays.
C.raceHits = {
	[2] = "hit_blood",       -- blood (players too)
	[4] = "hit_blood_spray", -- fire (the stock sends the same red splash there)
}

-- engine, kind 1: a direct hit of this combat type (spells, runes, wands, monster attacks)
C.elementHits = {
	COMBAT_FIREDAMAGE = "blast_fire1", COMBAT_ICEDAMAGE = "blast_ice", COMBAT_ENERGYDAMAGE = "blast_energy",
	COMBAT_EARTHDAMAGE = "blast_poison", COMBAT_DEATHDAMAGE = "blast_dark", COMBAT_ARCANEDAMAGE = "blast_arcane",
}

-- engine missiles: a stock (CONST_ANI_*) or procedural (ChaosFxMissile, gen_effects.py) missile -> the pack's bolt.
-- Weapon arrows, bolts, spears and stones keep theirs.
C.missiles = {
	CONST_ANI_FIRE = "bolt_fire", CONST_ANI_ENERGY = "bolt_lightning", CONST_ANI_ENERGYBALL = "bolt_plasma",
	CONST_ANI_DEATH = "bolt_dark", CONST_ANI_SUDDENDEATH = "bolt_soul", CONST_ANI_ICE = "bolt_ice",
	CONST_ANI_SMALLICE = "bolt_crystal", CONST_ANI_EARTH = "bolt_thorn", CONST_ANI_SMALLEARTH = "bolt_thorn",
	CONST_ANI_POISON = "bolt_poison", CONST_ANI_HOLY = "bolt_holy", CONST_ANI_SMALLHOLY = "bolt_holy",
	CONST_ANI_EXPLOSION = "bolt_meteor",
	["fx:fire_bolt"] = "bolt_fire", ["fx:fire_streak"] = "bolt_meteor", ["fx:ice_shard"] = "bolt_ice",
	["fx:arcane_orb"] = "bolt_arcane", ["fx:shadow_bolt"] = "bolt_shadow", ["fx:holy_bolt"] = "bolt_holy",
	["fx:lightning_orb"] = "bolt_lightning", ["fx:poison_dart"] = "bolt_poison", ["fx:skull_orb"] = "bolt_soul",
}

-- Lua: a name a spell sends during its cast (ChaosSpell.fx / vfx) -> a blast. Only the small hits and the procedural
-- bursts; names that are also large pack effects (fire_explosion, frost_nova) keep theirs.
C.names = {
	fireball_hit = "blast_fire1", ice_shatter = "blast_ice", lightning_hit = "blast_lightning",
	shadow_hit = "blast_dark", arcane_hit = "blast_arcane", venom_splash = "blast_poison", holy_hit = "blast_magical",
	frost_burst = "blast_ice", poison_burst = "blast_poison", ground_slam = "blast_ground",
	arcane_burst = "blast_arcane", lightning_zap = "blast_lightning", fire_burst = "blast_fire4",
	inferno_burst = "blast_fire2", fire_nova = "blast_fire6", fire_ring = "blast_fire3",
}

-- celebrations: a kind -> a firework, or a list (one is picked)
C.celebrations = {
	levelup = "fw_grand",
	achievement = "fw_star",
	boss = "fw_rainbow",
	reward = {"fw_gold_ring", "fw_blue_star", "fw_orange", "fw_green", "fw_violet", "fw_heart", "fw_white_ring",
		"fw_spiral", "fw_twin", "fw_rocket", "fw_sparks", "fw_ice", "fw_willow"},
}
-- a boss death: the blast on the corpse; a boss of massiveHealth max health or more (world, raid and guild bosses)
-- the massive one
C.bossBlast = {boss = "blast_boss", massive = "blast_massive"}
C.massiveHealth = 1000000

-- a status word of chaos_status_fx.lua sent on a creature -> the aura held for wordHoldMs
C.words = {
	word_frozen = "frozen", word_stunned = "stunned", word_feared = "fear", word_cursed = "cursed",
	word_blessed = "blessed", word_shocked = "shocked", word_rooted_vines = "slowed",
}
C.wordHoldMs = 3000

-- imported, sent by nothing yet (no game mechanic, or no fitting element): kept for later
C.unused = {"cond_silenced", "cond_petrified", "blast_fire5", "bolt_ultimate", "bolt_water", "bolt_wind"}

C.maxHeld = 300        -- at most this many creature + state pairs held at once (the rest show once)
C.scanMs = 1000        -- the online players' scan (scripts/chaos/pack29_vfx.lua)

-- ------------------------------------------------------------------------------------------------ pure parts
function C.auraFor(state)
	return type(state) == "string" and C.auras[state] or nil
end

-- the blast for a name sent during a cast, or nil
function C.pick(kind, name)
	if kind ~= "fx" or type(name) ~= "string" then
		return nil
	end
	return C.names[name]
end

-- the firework of a celebration kind; `roll(n)` picks from a list (default math.random)
function C.celebration(kind, roll)
	local v = C.celebrations[kind]
	if type(v) == "table" then
		return v[(roll or math.random)(#v)]
	end
	return v
end

-- throttle: a creature's aura of one state is sent again only when the previous one has played
local nextAt, heldCount, lastSweep = {}, 0, 0
function C.allow(key, t, ms)
	if t - lastSweep >= 10000 then
		lastSweep = t
		for k, v in pairs(nextAt) do
			if v <= t then nextAt[k] = nil end
		end
	end
	local n = nextAt[key]
	if n and n > t then
		return false
	end
	nextAt[key] = t + (ms or 1000)
	return true
end

function C.resetThrottle()
	nextAt, heldCount, lastSweep = {}, 0, 0
	C.held = {}
end
C.held = C.held or {}

local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end
C.now = now

-- ------------------------------------------------------------------------------------------------ engine side
-- the pair 29 switch on and the ids known (chaos_pack29_vfx_ids.lua loaded once)
function C.live()
	if not ChaosPack29Fx and dofile then
		pcall(dofile, "data/lib/chaos_pack29_fx.lua")
	end
	if not (ChaosPack29Fx and ChaosPack29Fx.PAIR29) then
		return false
	end
	if C.loaded == nil then
		C.loaded = false
		if not ChaosVfx and dofile then
			pcall(dofile, "data/lib/chaos_vfx.lua")
		end
		if not (ChaosVfx and ChaosVfx.cond_burning) and dofile then
			pcall(dofile, "data/lib/chaos_pack29_vfx_ids.lua")
		end
		C.loaded = ChaosVfx ~= nil and Vfx ~= nil and ChaosVfx.cond_burning ~= nil
	end
	return C.loaded
end

local function effect(name)
	return name and ChaosVfx and ChaosVfx[name] or nil
end

-- the blast for a name a spell sends, when live and the id is known
function C.swapFor(kind, name)
	local alt = C.pick(kind, name)
	return alt and C.live() and effect(alt) and alt or nil
end

-- the aura of `state` on `creature` once (throttled to its own length); true when sent
function C.show(creature, state)
	local name = C.auraFor(state)
	if not name or not creature or not C.live() then
		return false
	end
	local e = effect(name)
	local ok, id = pcall(creature.getId, creature)
	if not e or not ok or not id then
		return false
	end
	if not C.allow(id .. ":" .. state, now(), e.ms) then
		return false
	end
	return Vfx(creature:getPosition(), name) and true or false
end

-- the aura of `state` on `creature`, sent again every time it ends, for `ms`; one chain per creature and state
function C.hold(creature, state, ms)
	if not C.show(creature, state) and not C.live() then
		return false
	end
	local e = effect(C.auraFor(state))
	if not e or not addEvent or not ms or ms <= e.ms then
		return true
	end
	local id = creature:getId()
	local key = id .. ":" .. state
	local untilMs = now() + ms
	local h = C.held[key]
	if h then
		h.untilMs = math.max(h.untilMs, untilMs) -- a running chain: only the end moves
		return true
	end
	if heldCount >= C.maxHeld then
		return true
	end
	heldCount = heldCount + 1
	C.held[key] = {untilMs = untilMs}
	local function step()
		local cur = C.held[key]
		local c = Creature and Creature(id)
		if not cur or not c or now() >= cur.untilMs or not C.live() then
			if cur then
				C.held[key] = nil
				heldCount = math.max(0, heldCount - 1)
			end
			return
		end
		C.show(c, state)
		addEvent(step, e.ms)
	end
	addEvent(step, e.ms)
	return true
end

-- chaos_status_fx.lua sent a word on `creature`: its state's aura for wordHoldMs
function C.onWord(creature, word)
	local state = C.words[word]
	return state ~= nil and C.hold(creature, state, C.wordHoldMs) or false
end

-- a celebration at `pos` (level-up, achievement, boss kill, reward); else the stock `fallback` effect
function C.celebrate(pos, kind, fallback)
	local name = C.celebration(kind)
	if pos and name and C.live() and effect(name) and Vfx(pos, name) then
		return true
	end
	if pos and fallback then
		Position(pos.x, pos.y, pos.z):sendMagicEffect(fallback)
	end
	return false
end

-- the blast of a boss death by the boss's max health (pure)
function C.bossBlastFor(maxHealth)
	return C.bossBlast[(maxHealth or 0) >= C.massiveHealth and "massive" or "boss"]
end

-- a boss of `maxHealth` died at `pos`: its blast; nothing when off
function C.bossDeath(pos, maxHealth)
	local name = C.bossBlastFor(maxHealth)
	return pos ~= nil and C.live() and effect(name) ~= nil and Vfx(pos, name) and true or false
end

-- the engine overrides as {kind, key, effect id, dx, dy} / {stock id, missile id, dx, dy} rows (pure on the tables
-- and the ids; a name without an id or an unknown constant is skipped)
function C.engineRows(G, vfx, missiles, fxMissiles)
	local hits, shots = {}, {}
	local function add(kind, key, name)
		local e = vfx[name]
		if key and e then
			hits[#hits + 1] = {kind, key, e.id, e.dx, e.dy}
		end
	end
	for ctype, state in pairs(C.conditionTicks) do
		add(2, G[ctype], C.auras[state])
	end
	for race, name in pairs(C.raceHits) do
		add(0, race, name)
	end
	for ctype, name in pairs(C.elementHits) do
		add(1, G[ctype], name)
	end
	for key, name in pairs(C.missiles) do
		local stock = key:sub(1, 3) == "fx:" and fxMissiles[key:sub(4)] or G[key]
		local m = missiles[name]
		if stock and m then
			shots[#shots + 1] = {stock, m.id, m.dx, m.dy}
		end
	end
	local byKey = function(a, b)
		for i = 1, #a do
			if a[i] ~= b[i] then return a[i] < b[i] end
		end
		return false
	end
	table.sort(hits, byKey)
	table.sort(shots, byKey)
	return hits, shots
end

-- startup: set the engine overrides (src-patch 0045) when live; clear them when off. Returns the rows set.
function C.applyEngine()
	if not (Game and Game.setHitEffect and Game.setMissileEffect) then
		return 0
	end
	if Game.clearEffectOverrides then
		Game.clearEffectOverrides()
	end
	if not C.live() then
		return 0
	end
	if not ChaosFxMissile and dofile then
		pcall(dofile, "data/lib/chaos_fx.lua")
	end
	local hits, shots = C.engineRows(_G, ChaosVfx, ChaosVfxMissile or {}, ChaosFxMissile or {})
	for _, h in ipairs(hits) do
		Game.setHitEffect(h[1], h[2], h[3], h[4], h[5])
	end
	for _, s in ipairs(shots) do
		Game.setMissileEffect(s[1], s[2], s[3], s[4])
	end
	return #hits + #shots
end
