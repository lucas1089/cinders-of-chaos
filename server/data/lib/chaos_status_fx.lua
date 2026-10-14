-- Status words: animated word effects ("FROZEN!", "STUNNED!", "REVIVED!" ...) over a creature when a spell or an
-- event puts a state on it. Effects only: no damage, chance, timing or target changes.
-- Art: client/tools/sprites/gen_status_fx.py (the owner's text effect set, art_import/status_fx.csv), appended after
-- the large spell effects by import_fx_art.py, which writes the ids to data/lib/chaos_status_fx_ids.lua (656-673).
--
-- Switch (C.STATUS_FX): off until a pair with effects 656-673 is on windows-assets (client/MANIFEST.md "Status
-- words"). Off, nothing changes: every call site sends exactly what it sent before (or nothing). On, a word is sent at
-- its offset tile (Vfx), at most one per creature in `targetMs` and at most `perCast` creatures per cast.
-- Two ways in:
--   * spell hits: ChaosStatusFx.onSpellHit(creature, attacker, origin) from combat_fx.lua's damage event reads the
--     attacker's cast context (data/spells/chaos/_supports.lua writes it into a storage while a spell's hits run) and
--     sends the word of that spell (C.spells) on the creature hit;
--   * uses: ChaosStatusFx.send(pos, use[, fallback[, key]]) at a call site (C.uses), e.g. Iron Palm's stun.
-- Lua 5.1 / LuaJIT / 5.3; the pure parts (pick, wordOfSpell, allow) run without the engine (server/tests/status_fx_test.lua).

ChaosStatusFx = ChaosStatusFx or {}
local C = ChaosStatusFx

C.STATUS_FX = false

-- spell id (spells_chaos.xml) -> word, sent on the creatures the spell's own hits land on (not its damage over time)
C.spells = {
	[205] = "word_frozen",       -- Frozen Crypt
	[210] = "word_rooted_vines", -- Briar Prison
	[213] = "word_drenched",     -- Primordial Squall
	[215] = "word_impaled",      -- Skewering Line
	[181] = "word_impaled",      -- Bone Spear
	[220] = "word_reaped",       -- Reaping Gyre
	[189] = "word_smite",        -- Radiant Smite
	[198] = "word_smite",        -- Judgement
	[182] = "word_cursed",       -- Withering Curse
	[228] = "word_feared",       -- Shattered Psyche
	[202] = "word_shocked",      -- Forked Storm
}

-- use key -> word, for call sites that know the state themselves
C.uses = {
	stun = "word_stunned",              -- Iron Palm: a monster really stunned (not the bosses' slow)
	lay_on_hands = "word_blessed",      -- Lay on Hands: the healed party member
	rift_revive = "word_revived_rise",  -- rift.lua: back at the rift's entrance after a death with lives left
	-- boss_mechanics.lua: a channel nobody stopped goes off, the word over the boss ("channel_" .. mechanic key)
	channel_oblivion = "word_oblivion", -- Nyxareth's Oblivion (the Void Anchor was not killed in time)
}

-- every word of the pair (art_import/status_fx.csv order); the ones no spell or use sends yet are there for later
C.words = {"word_blessed", "word_oblivion", "word_charmed", "word_cursed", "word_drenched", "word_feared",
	"word_frozen", "word_impaled", "word_reaped", "word_revived", "word_revived_rise", "word_revived_small",
	"word_rooted", "word_rooted_vines", "word_shackled", "word_shocked", "word_smite", "word_stunned"}

C.targetMs = 2000  -- one word per creature in this time
C.perCast = 3      -- creatures that get the word of one cast (an area spell on a pack shows three, not twenty)
C.storageContext = (ChaosSupports and ChaosSupports.config and ChaosSupports.config.storageContext) or 7109990
-- (chaos_supports_config.lua storageContext: serial * 1000 + spell id while a spell's own hits run)

-- the word of a use or a spell id, or nil (pure: no switch, no ids)
function C.pick(use)
	return type(use) == "string" and C.uses[use] or nil
end

function C.wordOfSpell(spellId)
	return spellId and C.spells[spellId] or nil
end

-- ---------------------------------------------------------------- throttle (pure, the clock passed in)
local lastByKey, casts = {}, {}
local lastSweep = 0

local function sweep(t)
	if t - lastSweep < 10000 then
		return
	end
	lastSweep = t
	for k, v in pairs(lastByKey) do
		if t - v >= C.targetMs then lastByKey[k] = nil end
	end
	for k, v in pairs(casts) do
		if t - v.t >= 10000 then casts[k] = nil end
	end
end

-- true when a word may go on `key` (a creature id or a position key) now, and books it; `cast` (caster id and serial)
-- also counts against perCast
function C.allow(key, t, cast)
	sweep(t)
	if key ~= nil and lastByKey[key] and t - lastByKey[key] < C.targetMs then
		return false
	end
	if cast then
		local c = casts[cast]
		if not c then
			c = {t = t, n = 0}
			casts[cast] = c
		end
		if c.n >= C.perCast then
			return false
		end
		c.n = c.n + 1
	end
	if key ~= nil then
		lastByKey[key] = t
	end
	return true
end

function C.resetThrottle()
	lastByKey, casts, lastSweep = {}, {}, 0
end

local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end
C.now = now

-- ---------------------------------------------------------------- engine side
-- the switch on and the word ids known (chaos_vfx.lua and chaos_status_fx_ids.lua; loaded once)
function C.live()
	if not C.STATUS_FX then
		return false
	end
	if C.loaded == nil then
		if not ChaosVfx then
			pcall(dofile, "data/lib/chaos_vfx.lua")
		end
		if ChaosVfx and not ChaosVfx.word_stunned then
			pcall(dofile, "data/lib/chaos_status_fx_ids.lua")
		end
		C.loaded = ChaosVfx ~= nil and Vfx ~= nil and ChaosVfx.word_stunned ~= nil
	end
	return C.loaded
end

local function sendWord(pos, name)
	return name ~= nil and ChaosVfx[name] ~= nil and Vfx(pos, name) and true or false
end

local function stock(pos, fallback)
	if fallback and pos then
		if pos.sendMagicEffect then
			pos:sendMagicEffect(fallback)
		else
			Position(pos.x, pos.y, pos.z):sendMagicEffect(fallback)
		end
	end
end

-- send the word of `use` at pos (throttled on `key`, default the position); else the stock `fallback` (switch off,
-- unknown use, throttled: the call site's old effect, or nothing)
function C.send(pos, use, fallback, key)
	if pos and C.live() then
		local name = C.pick(use)
		if name and C.allow(key or (pos.x .. ":" .. pos.y .. ":" .. pos.z), now()) and sendWord(pos, name) then
			return true
		end
	end
	stock(pos, fallback)
	return false
end

-- combat_fx.lua's damage event: the word of the spell whose hit this is (direct hits of a player's cast only)
function C.onSpellHit(creature, attacker, origin)
	if not C.STATUS_FX or not creature or not attacker or not attacker:isPlayer() then
		return false
	end
	if ORIGIN_CONDITION and origin == ORIGIN_CONDITION then
		return false
	end
	local v = tonumber(attacker:getStorageValue(C.storageContext))
	if not v or v <= 0 then
		return false
	end
	local serial, spellId = math.floor(v / 1000), v % 1000
	local name = C.wordOfSpell(spellId)
	if not name or not C.live() then
		return false
	end
	if not C.allow(creature:getId(), now(), attacker:getId() .. ":" .. serial) then
		return false
	end
	return sendWord(creature:getPosition(), name)
end
