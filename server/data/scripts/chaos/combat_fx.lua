-- combat_fx.lua: combat feedback visuals (ChaosCombatFx).
--
--   * elemental weapon hits: a small element sprite on the target (imbue_fire / _ice / _energy / _earth / _death /
--     _holy). The engine already shows the element part as its own coloured number (Game::combatChangeHealth sends
--     primary and secondary damage with their own text colours: fire orange, ice sky blue, energy purple, earth green,
--     death dark red, holy yellow), so no number is added here. Melee, distance and wand hits (combat origin
--     melee / ranged / wand) with a secondary element: the weapon's own element (items.xml elementFire...) and the
--     rarity "adds X% <element> damage" modifiers (customs/rarity, storages 977554..977561).
--   * critical hits: crit_burst sprite + "CRIT!" label. The engine decides crits in C++ (combat.cpp); the Chaos
--     server patch server/src-patches/0001-critical-hit-to-lua.patch passes `critical` to onHealthChange as an 8th
--     argument and leaves the burst to this script. Without the patch the argument is nil, nothing is shown here and
--     the engine keeps showing its own CONST_ME_CRITICAL_DAMAGE.
--   * dodge / reflect: ChaosCombatFx.dodge(creature) / ChaosCombatFx.reflect(creature) for whatever implements them
--     (monster_tiers.lua "Reflective" calls reflect; passive-tree keystones may call both). The engine itself has no
--     dodge and no reflect.
--
-- API (all guarded: safe to call with nil, a dead creature, or before the generated dat/spr is in use):
--   ChaosCombatFx.crit(pos[, sourceId])            ChaosCombatFx.dodge(creature)
--   ChaosCombatFx.reflect(creature)                 ChaosCombatFx.element(pos, combatType[, amount[, sourceId]])
--   ChaosCombatFx.label(pos, text, color)           ChaosCombatFx.config (on/off per visual, throttle)
-- Callers outside this file: `if ChaosCombatFx then ChaosCombatFx.dodge(player) end`.
-- Effect ids come from data/lib/chaos_fx.lua (generated, client/tools/sprites/fx_custom.csv rows 415..423).

if not ChaosFx then
	pcall(dofile, "data/lib/chaos_fx.lua")
end

ChaosCombatFx = ChaosCombatFx or {}
local M = ChaosCombatFx

M.config = M.config or {
	enabled = true,
	crit = true,          -- crit_burst sprite on critical hits
	critLabel = true,     -- "CRIT!" text
	dodge = true,         -- dodge_whoosh sprite on the creature that dodged
	dodgeLabel = true,    -- "DODGE" text
	reflect = true,       -- reflect_aegis sprite on the creature that reflected
	reflectLabel = false, -- "REFLECT" text (off: Reflective monsters reflect every hit, the sprite is enough)
	element = true,       -- element sprite on elemental weapon hits
	-- throttle: per source (attacker, or the dodging/reflecting creature) and kind, at most `perSource` visuals in
	-- `windowMs`; per target tile and kind at most one in `tileMs`; labels at most one per source in `labelMs`.
	-- An area spell that crits 20 monsters shows 3 bursts and one "CRIT!", not 20.
	windowMs = 300,
	perSource = 3,
	tileMs = 200,
	labelMs = 600,
	labels = {crit = "CRIT!", dodge = "DODGE", reflect = "REFLECT"},
	colors = {crit = 210, dodge = 129, reflect = 35}, -- TEXTCOLOR_YELLOW, _LIGHTGREY, _LIGHTBLUE
}
local cfg = M.config

local function fx(name)
	return ChaosFx and ChaosFx[name]
end

-- element combat type -> effect name (water and arcane only come from rarity modifiers)
M.elementFx = {}
local function mapElement(ctype, name)
	if ctype then
		M.elementFx[ctype] = name
	end
end
mapElement(COMBAT_FIREDAMAGE, "imbue_fire")
mapElement(COMBAT_ICEDAMAGE, "imbue_ice")
mapElement(COMBAT_ENERGYDAMAGE, "imbue_energy")
mapElement(COMBAT_EARTHDAMAGE, "imbue_earth")
mapElement(COMBAT_DEATHDAMAGE, "imbue_death")
mapElement(COMBAT_HOLYDAMAGE, "imbue_holy")
mapElement(COMBAT_WATERDAMAGE, "imbue_ice")
mapElement(COMBAT_ARCANEDAMAGE, "imbue_energy")

-- rarity element storages (data/scripts/customs/rarity): combat type of the first one the player has
M.rarityElementStorages = {
	{977554, COMBAT_FIREDAMAGE}, {977555, COMBAT_ICEDAMAGE}, {977556, COMBAT_ENERGYDAMAGE}, {977557, COMBAT_EARTHDAMAGE},
	{977558, COMBAT_DEATHDAMAGE}, {977559, COMBAT_WATERDAMAGE}, {977560, COMBAT_HOLYDAMAGE}, {977561, COMBAT_ARCANEDAMAGE},
}

-- ------------------------------------------------------------------------------------------------ throttle
local now = os.mtime or function() return os.time() * 1000 end
M.now = now
local srcLog, tileLog, labelLog = {}, {}, {}
local lastSweep = 0

local function sweep(t)
	if t - lastSweep < 10000 then
		return
	end
	lastSweep = t
	for k, v in pairs(srcLog) do
		if t - v.start > cfg.windowMs then srcLog[k] = nil end
	end
	for k, v in pairs(tileLog) do
		if t - v > cfg.tileMs then tileLog[k] = nil end
	end
	for k, v in pairs(labelLog) do
		if t - v > cfg.labelMs then labelLog[k] = nil end
	end
end

local function tileKey(kind, pos)
	return kind .. ":" .. pos.x .. ":" .. pos.y .. ":" .. pos.z
end

-- true when a visual of `kind` from `source` on `pos` may be shown now (and books it)
function M.allow(kind, source, pos)
	local t = now()
	sweep(t)
	local tk = tileKey(kind, pos)
	if tileLog[tk] and t - tileLog[tk] < cfg.tileMs then
		return false
	end
	local sk = kind .. ":" .. tostring(source or 0)
	local s = srcLog[sk]
	if not s or t - s.start >= cfg.windowMs then
		s = {start = t, n = 0}
		srcLog[sk] = s
	end
	if s.n >= cfg.perSource then
		return false
	end
	s.n = s.n + 1
	tileLog[tk] = t
	return true
end

function M.allowLabel(kind, source)
	local t = now()
	local k = kind .. ":" .. tostring(source or 0)
	if labelLog[k] and t - labelLog[k] < cfg.labelMs then
		return false
	end
	labelLog[k] = t
	return true
end

function M.resetThrottle()
	srcLog, tileLog, labelLog = {}, {}, {}
end

-- ------------------------------------------------------------------------------------------------ senders
local function toPos(p)
	if not p then
		return nil
	end
	if p.x and p.y and p.z then
		return p
	end
	return nil
end

local function sendEffect(pos, id)
	if id and pos.sendMagicEffect then
		pos:sendMagicEffect(id)
		return true
	end
	if id and Position then
		Position(pos.x, pos.y, pos.z):sendMagicEffect(id)
		return true
	end
	return false
end

-- floating text above a tile for every player who sees it (opcode 0x84, the animated text the client parses in
-- ProtocolGame::parseAnimatedText; 10.98 servers do not send it themselves)
function M.label(pos, text, color)
	pos = toPos(pos)
	if not pos or not text or not NetworkMessage or not Game.getSpectators then
		return false
	end
	for _, spectator in ipairs(Game.getSpectators(pos, false, true) or {}) do
		local msg = NetworkMessage()
		msg:addByte(0x84)
		msg:addPosition(pos)
		msg:addByte(color or 215)
		msg:addString(text)
		msg:sendToPlayer(spectator)
		if msg.delete then
			msg:delete()
		end
	end
	return true
end

local function creatureOf(c)
	if type(c) == "number" then
		return Creature and Creature(c)
	end
	return c
end

local function show(kind, pos, source, labelOn)
	if not cfg.enabled or not cfg[kind] or not pos then
		return false
	end
	if not M.allow(kind, source, pos) then
		return false
	end
	local shown = sendEffect(pos, fx(M.effectNames[kind]))
	if labelOn and cfg.labels[kind] and M.allowLabel(kind, source) then
		M.label(pos, cfg.labels[kind], cfg.colors[kind])
	end
	return shown
end
M.effectNames = {crit = "crit_burst", dodge = "dodge_whoosh", reflect = "reflect_aegis"}

function M.crit(pos, sourceId)
	return show("crit", toPos(pos), sourceId, cfg.critLabel)
end

function M.dodge(creature)
	creature = creatureOf(creature)
	if not creature or (creature.isRemoved and creature:isRemoved()) then
		return false
	end
	return show("dodge", creature:getPosition(), creature:getId(), cfg.dodgeLabel)
end

function M.reflect(creature)
	creature = creatureOf(creature)
	if not creature or (creature.isRemoved and creature:isRemoved()) then
		return false
	end
	return show("reflect", creature:getPosition(), creature:getId(), cfg.reflectLabel)
end

function M.element(pos, combatType, amount, sourceId)
	pos = toPos(pos)
	if not cfg.enabled or not cfg.element or not pos or (amount and amount == 0) then
		return false
	end
	local name = M.elementFx[combatType]
	if not name or not fx(name) then
		return false
	end
	if not M.allow("element", sourceId, pos) then
		return false
	end
	return sendEffect(pos, fx(name))
end

-- element a rarity modifier adds to this player's weapon hits (when our event ran before the rarity script did)
function M.rarityElement(player)
	for _, e in ipairs(M.rarityElementStorages) do
		if e[2] and (player:getStorageValue(e[1]) or 0) > 0 then
			return e[2]
		end
	end
	return nil
end

-- ------------------------------------------------------------------------------------------------ engine hooks
M.weaponOrigin = {}
if ORIGIN_MELEE then
	M.weaponOrigin[ORIGIN_MELEE], M.weaponOrigin[ORIGIN_RANGED] = true, true
	if ORIGIN_WAND then M.weaponOrigin[ORIGIN_WAND] = true end
end

-- `critical` is the 8th argument added by server/src-patches/0001-critical-hit-to-lua.patch (nil without it)
function M.onHit(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin, critical)
	if not attacker or not attacker:isPlayer() or primaryType == COMBAT_HEALING then
		return
	end
	if (primaryDamage or 0) == 0 and (secondaryDamage or 0) == 0 then
		return
	end
	local pos = creature:getPosition()
	local src = attacker:getId()
	if critical == true then
		M.crit(pos, src)
	end
	if M.weaponOrigin[origin] then
		if secondaryDamage ~= 0 and secondaryType and secondaryType ~= COMBAT_NONE and secondaryType ~= COMBAT_PHYSICALDAMAGE then
			M.element(pos, secondaryType, secondaryDamage, src)
		elseif primaryType == COMBAT_PHYSICALDAMAGE and origin ~= ORIGIN_WAND then
			local etype = M.rarityElement(attacker) -- the rarity script adds its element after this event ran
			if etype then
				M.element(pos, etype, nil, src)
			end
		end
	end
end

local hit = CreatureEvent("ChaosCombatFx")
function hit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin, critical)
	local ok, err = pcall(M.onHit, creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin, critical)
	if not ok then
		print("[ChaosCombatFx] " .. tostring(err))
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
hit:register()

-- register on whatever a player attacks; a late index so the event is added after the rarity and passive-tree
-- damage events (it only reads the damage)
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and creature:isPlayer() then
		target:registerEvent("ChaosCombatFx")
	end
	return RETURNVALUE_NOERROR
end
targetCb:register(50)
