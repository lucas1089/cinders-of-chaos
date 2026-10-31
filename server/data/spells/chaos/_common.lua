-- Shared helpers for the Chaos spells.
-- Loaded by every chaos spell with: dofile('data/spells/scripts/chaos/_common.lua')
-- (path is relative to the server working dir, same convention as the rest of data/).
if not ChaosSupportsSpell then -- spell supports: wraps every spell script loaded from here on (_supports.lua)
	local ok, err = pcall(dofile, 'data/spells/scripts/chaos/_supports.lua')
	if not ok then
		print('[Chaos supports] ' .. tostring(err))
	end
end
if not Fx or not FxMissile then
	pcall(dofile, 'data/lib/chaos_fx.lua') -- real ids, once the merged dat/spr is in use
	if not Fx or not FxMissile then
		dofile('data/spells/scripts/chaos/_fx_fallback.lua')
	end
end
-- the spells ask ChaosFx only for names it has (tests/spell_fx_names_test.lua); one missile name is spelled differently
if ChaosFxMissile then
	ChaosFxMissile.holy_arrow = ChaosFxMissile.holy_arrow or ChaosFxMissile.holy_bolt
end
if ChaosSpell then
	return
end

ChaosSpell = {}

local DIR_STEP = {
	[NORTH] = {0, -1}, [EAST] = {1, 0}, [SOUTH] = {0, 1}, [WEST] = {-1, 0},
	[NORTHEAST] = {1, -1}, [SOUTHEAST] = {1, 1}, [SOUTHWEST] = {-1, 1}, [NORTHWEST] = {-1, -1},
}

function ChaosSpell.cancel(creature, message)
	if message then
		if type(message) == "string" and Chaos and Chaos.tx and creature.isPlayer and creature:isPlayer() then
			message = Chaos.tx(creature, message) -- an English refusal of a core, in the player's language
		end
		creature:sendCancelMessage(message)
	else
		creature:sendCancelMessage(RETURNVALUE_NOTPOSSIBLE)
	end
	creature:getPosition():sendMagicEffect(CONST_ME_POFF)
	return false
end

-- >>> Cosmetics: spell effect skins (data/scripts/chaos/cosmetics.lua). During a cast (the supports wrapper knows the
-- caster and the spell, also in the cast's addEvent callbacks) an effect name may be swapped for its recoloured variant
-- the caster chose; every viewer sees the variant. A variant the pair does not have falls back to the default effect.
local function skinned(kind, name)
	local C, W = ChaosCosmetics, ChaosSupportsSpell
	if type(name) ~= "string" or not C or not C.swapFor or not W or not W.cast then
		return nil
	end
	local pid, spellId = W.cast()
	if not pid then
		return nil
	end
	local ok, alt = pcall(C.swapFor, pid, spellId, kind, name)
	return ok and alt or nil
end
ChaosSpell.skinned = skinned

-- >>> Class signature effects (data/lib/chaos_class_fx.lua, switch ChaosClassFx.PAIR22_FX): the caster's class may send
-- an effect of its own for this spell; nil when the switch is off or no swap fits. A cosmetic skin wins over it.
if not ChaosClassFx then
	pcall(dofile, 'data/lib/chaos_class_fx.lua')
end
local function classFx(name)
	local C, W = ChaosClassFx, ChaosSupportsSpell
	if type(name) ~= "string" or not C or not C.swapFor or not W or not W.cast then
		return nil
	end
	local pid, spellId = W.cast()
	if not pid then
		return nil
	end
	local ok, alt = pcall(C.swapFor, pid, spellId, name)
	return ok and alt or nil
end
ChaosSpell.classFx = classFx
-- <<< Class signature effects

-- >>> Large spell effects (data/lib/chaos_big_fx.lua, switch ChaosBigFx.BIG_FX): the strongest area spells may send a
-- big effect for the effect they send at the centre of their area; nil when the switch is off or no swap fits.
if not ChaosBigFx then
	pcall(dofile, 'data/lib/chaos_big_fx.lua')
end
local function bigFx(name)
	local B, W = ChaosBigFx, ChaosSupportsSpell
	if type(name) ~= "string" or not B or not B.swapFor or not W or not W.cast then
		return nil
	end
	local pid, spellId = W.cast()
	if not pid then
		return nil
	end
	local ok, alt = pcall(B.swapFor, spellId, name)
	return ok and alt or nil
end
ChaosSpell.bigFx = bigFx
-- <<< Large spell effects

-- >>> Pair 27 effects (data/lib/chaos_pack27_fx.lua, switch ChaosPack27Fx.PAIR27_FX, off): a spell may send an effect
-- or missile of its own; nil when the switch is off or no swap fits. Skins win over it; large and class effects too,
-- unless the second result is true (the swap is listed as `first` for that spell).
if not ChaosPack27Fx then
	pcall(dofile, 'data/lib/chaos_pack27_fx.lua')
end
-- Pair 29 effects (data/lib/chaos_pack29_fx.lua, switch ChaosPack29Fx.PAIR29, off): the Mystic line's new effects come
-- first (as a `first` pair 27 swap: over the large and class effects); nil when off or no swap fits
if not ChaosPack29Fx then
	pcall(dofile, 'data/lib/chaos_pack29_fx.lua')
end
-- The element blasts of the pair 29 VFX packs (data/lib/chaos_pack29_vfx.lua, same switch) stand in for the small hits
-- and procedural bursts of any spell when the Mystic table has no swap.
if not ChaosPack29Vfx then
	pcall(dofile, 'data/lib/chaos_pack29_vfx.lua')
end
local function pack29(kind, name)
	local Q, W = ChaosPack29Fx, ChaosSupportsSpell
	if type(name) ~= "string" or not Q or not Q.swapFor or not Q.PAIR29 or not W or not W.cast then
		return nil
	end
	local pid, spellId = W.cast()
	local ok, alt = pcall(Q.swapFor, spellId, kind, name)
	if pid and ok and alt then
		return alt
	end
	local V = ChaosPack29Vfx
	if pid and V and V.swapFor then
		local ok2, blast = pcall(V.swapFor, kind, name)
		return ok2 and blast or nil
	end
	return nil
end
ChaosSpell.pack29 = pack29
-- the name a script sends itself (VfxShoot): the pair 29 one during the cast, else the same name
function ChaosSpell.pack29Name(kind, name)
	return pack29(kind, name) or name
end
-- Pair 36 effects (data/lib/chaos_pack36_fx.lua, switch ChaosPack36Fx.PAIR36_FX): the spells pair 27 has no swap for
-- may send an appended pack effect; it takes the place of a pair 27 swap (not first: skins, large and class effects win)
if not ChaosPack36Fx then
	pcall(dofile, 'data/lib/chaos_pack36_fx.lua')
end
local function pack36(kind, name)
	local Q, W = ChaosPack36Fx, ChaosSupportsSpell
	if type(name) ~= "string" or not Q or not Q.swapFor or not Q.PAIR36_FX or not W or not W.cast then
		return nil
	end
	local pid, spellId = W.cast()
	if not pid then
		return nil
	end
	local ok, alt = pcall(Q.swapFor, spellId, kind, name)
	return ok and alt or nil
end
ChaosSpell.pack36 = pack36
local function pack27(kind, name)
	local p29 = pack29(kind, name)
	if p29 then
		return p29, true
	end
	local p36 = pack36(kind, name)
	if p36 then
		return p36, false
	end
	local P, W = ChaosPack27Fx, ChaosSupportsSpell
	if type(name) ~= "string" or not P or not P.swapFor or not P.PAIR27_FX or not W or not W.cast then
		return nil
	end
	local pid, spellId = W.cast()
	if not pid then
		return nil
	end
	local ok, alt, first = pcall(P.swapFor, spellId, kind, name)
	if not ok or not alt then
		return nil, false
	end
	return alt, first == true
end
ChaosSpell.pack27 = pack27
-- <<< Pack farming spell effects

-- Fx / FxMissile (chaos_fx.lua) are also called inside the casts (heal and area effects): wrapped once
local function wrapFx()
	if Fx and Fx ~= ChaosSpellSkinFx then
		local raw = Fx
		ChaosSpellSkinFx = function(name, fallback)
			local alt = skinned("fx", name)
			if alt and ChaosFx and ChaosFx[alt] then
				return raw(alt, fallback)
			end
			local cls = classFx(name) -- a class effect sent on the tile itself (offset 0,0) can stand in for the id
			local e = cls and ChaosVfx and ChaosVfx[cls]
			if e and e.dx == 0 and e.dy == 0 then
				return e.id
			end
			return raw(name, fallback)
		end
		Fx = ChaosSpellSkinFx
	end
	if FxMissile and FxMissile ~= ChaosSpellSkinFxMissile then
		local raw = FxMissile
		ChaosSpellSkinFxMissile = function(name, fallback)
			local alt = skinned("missile", name)
			if alt and ChaosFxMissile and ChaosFxMissile[alt] then
				return raw(alt, fallback)
			end
			return raw(name, fallback)
		end
		FxMissile = ChaosSpellSkinFxMissile
	end
end
wrapFx()
-- <<< Cosmetics

function ChaosSpell.fx(pos, name, fallback)
	local skin = skinned("fx", name)
	local p27, p27first = nil, false
	if not skin then
		p27, p27first = pack27("fx", name) -- the pair 27 effect, before the class effect when it comes first
	end
	if p27 and p27first and Vfx and Vfx(Position(pos), p27) then
		return
	end
	local cls = not skin and classFx(name) -- the class effect at its offset tile, unless a skin was chosen
	if cls and Vfx and Vfx(Position(pos), cls) then
		return
	end
	if p27 and not cls and Vfx and Vfx(Position(pos), p27) then -- the pair 27 effect, unless a class effect fits
		return
	end
	Position(pos):sendMagicEffect(Fx(name, fallback))
end

function ChaosSpell.shoot(fromPos, toPos, name, fallback)
	local p27 = pack27("missile", name) -- the pack farming missile (pair 27)
	if p27 and VfxShoot and VfxShoot(Position(fromPos), Position(toPos), p27) then
		return
	end
	Position(fromPos):sendDistanceEffect(Position(toPos), FxMissile(name, fallback))
end

-- Animated pack effects and missiles (data/lib/chaos_vfx.lua, client/tools/sprites/import_vfx.py). They are bigger
-- than a tile and are sent at an offset tile by Vfx/VfxShoot. Without chaos_vfx.lua these send nothing (vfx/vfxDir)
-- or fall back to the named chaos effect (vfxOr/vshoot).
if not ChaosVfx then
	pcall(dofile, 'data/lib/chaos_vfx.lua')
end
-- effects of our own art appended after them (bone_spear, bone_burst, bone_aura; client/tools/sprites/import_fx_art.py)
if ChaosVfx and not ChaosVfx.bone_burst then
	pcall(dofile, 'data/lib/chaos_vfx_art.lua')
end

-- direction (NORTH .. NORTHWEST) from one position to another, for the directional effects (VfxDir)
function ChaosSpell.dirTo(fromPos, toPos)
	local dx, dy = toPos.x - fromPos.x, toPos.y - fromPos.y
	if dx == 0 and dy == 0 then
		return SOUTH
	end
	local sx = dx > 0 and 1 or (dx < 0 and -1 or 0)
	local sy = dy > 0 and 1 or (dy < 0 and -1 or 0)
	if math.abs(dx) >= 2 * math.abs(dy) then
		sy = 0
	elseif math.abs(dy) >= 2 * math.abs(dx) then
		sx = 0
	end
	for dir, step in pairs(DIR_STEP) do
		if step[1] == sx and step[2] == sy then
			return dir
		end
	end
	return SOUTH
end

function ChaosSpell.vfx(pos, name)
	if Vfx == nil or pos == nil then
		return false
	end
	local alt = skinned("vfx", name) -- Cosmetics: the skin's variant first, the default when the pair lacks it
	if alt and Vfx(Position(pos), alt) then
		return true
	end
	local p27, p27first = nil, false
	if not alt then
		p27, p27first = pack27("fx", name) -- the pair 27 effect, before the large and class effect when it comes first
	end
	if p27 and p27first and Vfx(Position(pos), p27) then
		return true
	end
	local big = not alt and bigFx(name) -- the large effect, unless a skin was chosen; it wins over the class effect
	if big and Vfx(Position(pos), big) then
		return true
	end
	local cls = not alt and classFx(name) -- the class effect, unless a skin was chosen
	if cls and Vfx(Position(pos), cls) then
		return true
	end
	if p27 and not big and not cls and Vfx(Position(pos), p27) then -- the pair 27 effect
		return true
	end
	local p27d = not alt and not big and not cls and VfxDir and pack27("fxdir", name) -- turned from the caster
	if p27d then
		local W = ChaosSupportsSpell
		local pid = W and W.cast and W.cast()
		local caster = pid and Player and Player(pid)
		if caster and VfxDir(Position(pos), p27d, ChaosSpell.dirTo(caster:getPosition(), Position(pos))) then
			return true
		end
	end
	return Vfx(Position(pos), name)
end

function ChaosSpell.vfxDir(pos, base, direction)
	local p27 = VfxDir ~= nil and pos ~= nil and pack27("dir", base) -- the pack farming directional effect (pair 27)
	if p27 and VfxDir(Position(pos), p27, direction) then
		return true
	end
	return VfxDir ~= nil and pos ~= nil and VfxDir(Position(pos), base, direction)
end

-- pack effect, or the chaos effect `name` / stock `fallback` when the pack effect is not there
function ChaosSpell.vfxOr(pos, vname, name, fallback)
	if not ChaosSpell.vfx(pos, vname) then
		ChaosSpell.fx(pos, name, fallback)
	end
end

function ChaosSpell.vshoot(fromPos, toPos, vname, name, fallback)
	local alt = VfxShoot ~= nil and skinned("vmissile", vname) -- Cosmetics: the skin's variant first
	if alt and VfxShoot(Position(fromPos), Position(toPos), alt) then
		return
	end
	local p27 = VfxShoot ~= nil and pack27("missile", vname) -- the pack farming missile (pair 27)
	if p27 and VfxShoot(Position(fromPos), Position(toPos), p27) then
		return
	end
	if not (VfxShoot ~= nil and VfxShoot(Position(fromPos), Position(toPos), vname)) then
		ChaosSpell.shoot(fromPos, toPos, name, fallback)
	end
end

-- A pair 41 / 42 missile (data/lib/chaos_pack41_fx_ids.lua, O239): `pname` (a ChaosVfxMissile name of the
-- pair 41 or 42) when the ids are known (ChaosPack36Fx.PAIR36_FX on, which loads them), the spell has no
-- skin and no pair 27 / 29 swap for the missile it sent before; else exactly what it sent before: vshoot(vname, name,
-- fallback) when `vname` is given, else shoot(name, fallback) when `name` is. Neither given: nothing is sent then.
function ChaosSpell.pshoot(fromPos, toPos, pname, vname, name, fallback)
	if ChaosPack36Fx and ChaosPack36Fx.live then
		pcall(ChaosPack36Fx.live)
	end
	local m = pname and ChaosVfxMissile and ChaosVfxMissile[pname]
	local old = vname or name
	local taken = old and (skinned("vmissile", old) or skinned("missile", old) or pack27("missile", old))
	if m and VfxShoot ~= nil and not taken and VfxShoot(Position(fromPos), Position(toPos), pname) then
		return
	end
	if vname then
		ChaosSpell.vshoot(fromPos, toPos, vname, name, fallback)
	elseif name then
		ChaosSpell.shoot(fromPos, toPos, name, fallback)
	end
end

-- Damage helper: returns positive min, max from the usual TFS level/magic-level formula, times `scale` (default 1,
-- the per-spell balance factor: the whole value scales, the level part included).
function ChaosSpell.mlValues(player, mlMin, mlMax, baseMin, baseMax, scale)
	local l = player:getLevel() / 5
	local m = player:getMagicLevel()
	scale = scale or 1
	return (l + m * mlMin + baseMin) * scale, (l + m * mlMax + baseMax) * scale
end

-- Damage helper for skill based spells (melee / distance).
function ChaosSpell.skillValues(player, skillId, mult, baseMin, baseMax)
	local s = player:getEffectiveSkillLevel(skillId)
	local l = player:getLevel() / 5
	return l + s * mult * 0.6 + baseMin, l + s * mult + baseMax
end

-- Attack of the wielded distance weapon, the way the engine adds it up: the bow's or crossbow's own attack (they fire
-- without ammunition and carry its attack themselves: data/lib/chaos_archery_core.lua), or the attack of a throwing
-- weapon. Item attack attributes (rarity rolls) win over the item type value.
-- Never below 20 (an empty hand), so the spells still do something without a weapon.
local function itemAttack(item)
	local a = item:getAttribute(ITEM_ATTRIBUTE_ATTACK)
	if not a or a == 0 then
		a = ItemType(item:getId()):getAttack()
	end
	return a or 0
end

function ChaosSpell.distanceAttack(player)
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		local it = item and ItemType(item:getId())
		if it and it:getWeaponType() == WEAPON_DISTANCE then
			return math.max(20, itemAttack(item))
		end
	end
	return 20
end

function ChaosSpell.bestMeleeSkill(player)
	local best = SKILL_SWORD
	local bestValue = -1
	for _, id in ipairs({SKILL_SWORD, SKILL_CLUB, SKILL_AXE}) do
		local v = player:getEffectiveSkillLevel(id)
		if v > bestValue then
			best, bestValue = id, v
		end
	end
	return best
end

-- ONE melee skill (data/scripts/chaos/melee_skill_core.lua): the level a melee spell or strike uses is the best of the
-- sword, club and axe skills, whichever weapon is in the hand
function ChaosSpell.meleeSkillLevel(player)
	return player:getEffectiveSkillLevel(ChaosSpell.bestMeleeSkill(player))
end

function ChaosSpell.spectators(pos, radius, onlyPlayers)
	return Game.getSpectators(Position(pos), false, onlyPlayers or false, radius, radius, radius, radius) or {}
end

-- A monster the caster may hit with manually looped spells (never the caster's own summons).
-- PvP rules for damage the scripts deal themselves (doTargetCombat skips the engine's checks): the same rules as
-- Combat::canDoCombat plus this server's Creature:onTargetCombat (a player in secure mode cannot be attacked,
-- party members cannot hit each other). Monsters and their summons are always fair game here.
function ChaosSpell.canAttack(caster, target)
	if not target or target == caster or target:getHealth() <= 0 then
		return false
	end
	local targetPlayer = target:getPlayer()
	if not targetPlayer then
		-- never the caster's own summons or its party's (summons_core.lua; the comment above always said so)
		local targetMaster = target:getMaster()
		local masterPlayer = targetMaster and targetMaster:getPlayer()
		if masterPlayer then
			local casterMaster = caster:getMaster()
			local owner = caster:getPlayer() or (casterMaster and casterMaster:getPlayer())
			if owner and (owner == masterPlayer or (owner:getParty() and owner:getParty() == masterPlayer:getParty())) then
				return false
			end
		end
		return true
	end
	local master = caster:getMaster()
	local casterPlayer = caster:getPlayer() or (master and master:getPlayer())
	if not casterPlayer then
		return true
	end
	if casterPlayer == targetPlayer or Game.getWorldType() == WORLD_TYPE_NO_PVP then
		return false
	end
	-- guild siege arena: its own rules (data/scripts/chaos/siege.lua; nil = not the siege's business)
	local siege = ChaosSiege and ChaosSiege.canAttack and ChaosSiege.canAttack(casterPlayer, targetPlayer)
	if siege ~= nil then
		return siege
	end
	-- the Scorched Marches (data/scripts/chaos/pvpzone.lua): open PvP inside, its own refusals (nil = not its business)
	local marches = ChaosPvpZone and ChaosPvpZone.canAttack and ChaosPvpZone.canAttack(casterPlayer, targetPlayer)
	if marches ~= nil then
		return marches
	end
	for _, pos in ipairs({targetPlayer:getPosition(), casterPlayer:getPosition()}) do
		local tile = Tile(pos)
		if tile and (tile:hasFlag(TILESTATE_PROTECTIONZONE) or tile:hasFlag(TILESTATE_NOPVPZONE)) then
			return false
		end
	end
	local protection = configManager.getNumber(configKeys.PROTECTION_LEVEL)
	if targetPlayer:getLevel() < protection or casterPlayer:getLevel() < protection then
		return false
	end
	local party = casterPlayer:getParty()
	if party and party == targetPlayer:getParty() then
		return false
	end
	if targetPlayer:hasSecureMode() then
		return false
	end
	-- multi-client: a character with another character online from its IP cannot attack players
	-- (data/scripts/chaos/multiclient.lua; same rule, the settings live in chaos_constants.lua)
	local ip = casterPlayer:getIp()
	if ip ~= 0 and casterPlayer:getGroup():getId() < 4 and Game.getStorageValue(7100990) ~= 1 then
		for _, other in ipairs(Game.getPlayers()) do
			if other ~= casterPlayer and other:getIp() == ip then
				return false
			end
		end
	end
	return true
end

function ChaosSpell.isEnemy(caster, target)
	if not target or target == caster or not target:isMonster() then
		return false
	end
	local master = target:getMaster()
	if master and (master == caster or master:isPlayer()) then
		return false
	end
	local tile = target:getTile()
	if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		return false
	end
	return true
end

function ChaosSpell.enemiesAround(caster, pos, radius)
	local list = {}
	for _, c in ipairs(ChaosSpell.spectators(pos, radius)) do
		if ChaosSpell.isEnemy(caster, c) then
			list[#list + 1] = c
		end
	end
	return list
end

-- Caster + party members (+ caster's summons when includeSummons) around pos.
function ChaosSpell.alliesAround(caster, pos, radius, includeSummons)
	local list = {}
	local party = caster:isPlayer() and caster:getParty() or nil
	for _, c in ipairs(ChaosSpell.spectators(pos, radius)) do
		if c == caster then
			list[#list + 1] = c
		elseif c:isPlayer() then
			if party and c:getParty() == party then
				list[#list + 1] = c
			end
		elseif includeSummons then
			local master = c:getMaster()
			if master and master == caster then
				list[#list + 1] = c
			end
		end
	end
	return list
end

-- Target of a "needtarget" spell. Variants are tables ({number=...}) or userdata depending on build.
function ChaosSpell.targetOf(variant)
	local id
	if type(variant) == 'table' or type(variant) == 'userdata' then
		id = variant.number
		if not id and variant.getNumber then
			id = variant:getNumber()
		end
	elseif type(variant) == 'number' then
		id = variant
	end
	if id and id ~= 0 then
		return Creature(id)
	end
	return nil
end

function ChaosSpell.stepPos(pos, direction, steps)
	local d = DIR_STEP[direction] or {0, 0}
	steps = steps or 1
	return Position(pos.x + d[1] * steps, pos.y + d[2] * steps, pos.z)
end

-- Free to stand on: ground, nothing solid, no creature, no floor change, not protection zone.
function ChaosSpell.isFreeTile(pos)
	local tile = Tile(pos)
	if not tile or not tile:getGround() then
		return false
	end
	if tile:hasFlag(TILESTATE_BLOCKSOLID) or tile:hasFlag(TILESTATE_PROTECTIONZONE)
		or tile:hasFlag(TILESTATE_FLOORCHANGE) or tile:hasFlag(TILESTATE_TELEPORT)
		or tile:hasFlag(TILESTATE_MAGICFIELD) then
		return false
	end
	if tile:getTopCreature() then
		return false
	end
	return true
end

-- Free tiles around center, ordered by distance to ref (ascending). Set far=true for descending.
function ChaosSpell.freeAround(center, ref, far)
	local list = {}
	for dx = -1, 1 do
		for dy = -1, 1 do
			if dx ~= 0 or dy ~= 0 then
				local p = Position(center.x + dx, center.y + dy, center.z)
				if ChaosSpell.isFreeTile(p) then
					local dist = (p.x - ref.x) ^ 2 + (p.y - ref.y) ^ 2
					list[#list + 1] = {pos = p, dist = dist}
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if far then return a.dist > b.dist end
		return a.dist < b.dist
	end)
	return list
end

-- The refusal when no tile around was free: freeAround never picks a protection zone tile, so a cast in a temple said
-- "not enough room" (live check of O85, Wild Bond); there it names the protection zone.
function ChaosSpell.noRoom(creature)
	local tile = Tile(creature:getPosition())
	if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		return ChaosSpell.cancel(creature, RETURNVALUE_ACTIONNOTPERMITTEDINPROTECTIONZONE)
	end
	return ChaosSpell.cancel(creature, RETURNVALUE_NOTENOUGHROOM)
end

-- Run fn(caster, step) now and then every `interval` ms until `count` runs were made.
-- Stops when the caster is gone/dead or fn returns false.
function ChaosSpell.pulse(casterId, count, interval, fn, step)
	step = step or 1
	local caster = Creature(casterId)
	if not caster or caster:getHealth() <= 0 then
		return
	end
	if fn(caster, step) == false then
		return
	end
	if step < count then
		addEvent(ChaosSpell.pulse, interval, casterId, count, interval, fn, step + 1)
	end
end

-- Remove a creature later (summons / clones).
function ChaosSpell.removeLater(creatureId)
	local c = Creature(creatureId)
	if c then
		c:getPosition():sendMagicEffect(CONST_ME_POFF)
		c:remove()
	end
end

-- Slow a creature: ticks ms, percent 0..1 of speed removed.
function ChaosSpell.slow(target, ticks, percent)
	local c = Condition(CONDITION_PARALYZE)
	c:setParameter(CONDITION_PARAM_TICKS, ticks)
	c:setFormula(-percent, 0, -percent, 0)
	target:addCondition(c)
	if ChaosPack29Vfx then -- the slowed aura while it lasts (pair 29 switch; off: nothing)
		pcall(ChaosPack29Vfx.hold, target, "slowed", ticks)
	end
end

function ChaosSpell.damageTarget(caster, target, ctype, min, max, effect)
	if not ChaosSpell.canAttack(caster, target) then
		return false
	end
	return doTargetCombat(caster, target, ctype, -math.floor(min), -math.floor(max), effect)
end

function ChaosSpell.healTarget(caster, target, min, max, effect)
	doTargetCombat(caster, target, COMBAT_HEALING, math.floor(min), math.floor(max), effect)
end

-- Distinct condition sub ids so several chaos buffs can run together. Retired with their scripts (O254), never reused:
-- 71001 (Blood Pact) and 71074 (Wildstride).
ChaosSpell.SUBID = {
	crimson_fury = 71002, rally = 71003, barkskin = 71004,
	divine_ward = 71005, soul_aegis = 71006, phantom_veil = 71007, dash = 71008, iron_will = 71009,
	tautstring = 71072, -- Tautstring (the Ranger line, in place of the stock Hawkeye)
	ironhold = 71073, -- Ironhold (the Warrior line, in place of the stock Bulwark / Protector)
	-- the level 800 buffs of the line spell quests (scripts/chaos/quest_buffs_config.lua subId; Veil of Whispers' regeneration
	-- condition is veil + 1000)
	ironbound_oath = 71075, unblinking_gaze = 71076, veil_of_whispers = 71077, shroud_of_knives = 71078,
	dirge_of_the_legion = 71079, lotus_stance = 71080, mantle_of_dawn = 71081,
	-- timer-only conditions (no attributes) that stand for a summon / decoy spell on the buff bar (chaos_buffs.lua)
	moonfang_pack = 71070, mirror_image = 71071,
}

-- A timer condition on the caster for a support spell that has a duration but no stat of its own (summons, decoys): the
-- buff bar finds it by its sub id (data/lib/chaos_buffs.lua) and shows the time left.
function ChaosSpell.buffTimer(player, subId, ticks)
	local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
	c:setParameter(CONDITION_PARAM_SUBID, subId)
	c:setParameter(CONDITION_PARAM_TICKS, ticks)
	player:addCondition(c)
end

-- ------------------------------------------------------------------------------------------------ Thief line
-- (thief/ ninja/ samurai/; the class rules are data/scripts/chaos/classes.lua, loaded here once)
function ChaosSpell.loadClasses()
	if not ChaosClasses then
		dofile('data/scripts/chaos/classes.lua')
	end
	return ChaosClasses
end

-- whose side a creature is on (data/scripts/chaos/summons_core.lua): a summon is made with ChaosSummonsCore.bind(owner, m)
function ChaosSpell.loadSummons()
	if not ChaosSummonsCore then
		dofile('data/scripts/chaos/summons_core.lua')
	end
	return ChaosSummonsCore
end

-- make `monster` the summon of `player` (setMaster plus clearing the target its creation gave it)
function ChaosSpell.bindSummon(player, monster)
	local K = ChaosSpell.loadSummons()
	if K then
		return K.bind(player, monster)
	end
	monster:setMaster(player)
	return monster
end

-- attack of the main-hand melee weapon (left hand first, as the engine picks it), never below 20 (an empty hand). An
-- empty hand with the Open Hand Creed keystone or the Knuckles of the Unbound (data/scripts/chaos/archetypes_core.lua)
-- strikes with the fist attack of that archetype instead.
function ChaosSpell.meleeAttack(player)
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		local it = item and ItemType(item:getId())
		if it then
			local wt = it:getWeaponType()
			if wt == WEAPON_SWORD or wt == WEAPON_CLUB or wt == WEAPON_AXE then
				return math.max(20, itemAttack(item))
			end
		end
	end
	if not ChaosArchetypesCore then
		pcall(dofile, 'data/scripts/chaos/archetypes_core.lua')
	end
	local open = ChaosArchetypesCore and ChaosArchetypesCore.spellOpenHandAttack(player)
	if open then
		return math.max(20, math.floor(open))
	end
	return 20
end

-- skill x attack of a Thief-line weapon strike: the melee skill and the main-hand blade
function ChaosSpell.bladePower(player)
	return ChaosSpell.meleeSkillLevel(player) * ChaosSpell.meleeAttack(player)
end

-- skill x attack of a shuriken: the better of the melee and distance skill, the throwing star in hand (any throwing
-- weapon) or Chaos.classes.shuriken.defaultAttack
function ChaosSpell.shurikenPower(player)
	local skill = math.max(ChaosSpell.meleeSkillLevel(player), player:getEffectiveSkillLevel(SKILL_DISTANCE))
	local attack = (Chaos and Chaos.classes and Chaos.classes.shuriken.defaultAttack) or 50
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		local it = item and ItemType(item:getId())
		-- a throwing weapon: one-handed (a bow or crossbow is two-handed and has no ammunition type any more either)
		if it and it:getWeaponType() == WEAPON_DISTANCE and it:getAmmoType() == 0
				and bit.band(it:getSlotPosition(), SLOTP_TWO_HAND) == 0 then
			attack = math.max(attack, itemAttack(item))
		end
	end
	return skill * attack
end

-- A weapon strike dealt by a spell: physical damage with a weapon origin (ORIGIN_MELEE or ORIGIN_RANGED), so the
-- weapon-hit rules of data/scripts/chaos/thief_combat.lua apply to it (stealth ambush crit, Poison Blades, Bushido
-- crit, the Ninja's off-hand strike after a melee strike). PvP rules as ChaosSpell.damageTarget.
-- Level factor of the Thief line's spell strikes (Chaos.classes.spellLevelScale, when set): 1 up to level `from`, then +1
-- per `per` levels, at most `max`. It stood in for the passive tree and was dropped with the class trees (docs/CLASSES.md
-- "Phase 2b"): unset, so 1; the line's damage is scaled by class_tree.lua classDamage instead.
function ChaosSpell.thiefLevelScale(player)
	local s = Chaos and Chaos.classes and Chaos.classes.spellLevelScale
	if not s or not player.getLevel then
		return 1
	end
	return math.min(s.max, 1 + math.max(0, player:getLevel() - s.from) / s.per)
end

function ChaosSpell.weaponStrike(caster, target, min, max, effect, origin)
	if not ChaosSpell.canAttack(caster, target) then
		return false
	end
	local k = ChaosSpell.thiefLevelScale(caster)
	-- the class spell factor (spell_factor_config.lua, C2): a spell's strike is not ORIGIN_SPELL, so the damage event
	-- never sees it; the same curve as the rest of the class's spells is applied here, not on the auto attack
	local SF = ChaosSpellFactor
	if SF and SF.forVocation and (SF.depth or 0) == 0 and caster.getVocation and caster.getLevel then
		local voc = caster:getVocation()
		k = k * SF.forVocation(voc and voc:getId() or 0, nil, caster:getLevel())
	end
	min, max = min * k, max * k
	-- the strike's numbers come from ChaosSpell.meleeSkillLevel already: weapon_styles.lua must not apply the melee skill
	-- rule (the ratio of the best skill to the weapon's own) to it a second time; it reads this storage during the call
	local key = (Chaos and Chaos.storage and Chaos.storage.weaponStrike) or 7100028
	caster:setStorageValue(key, 1)
	local ok, result = pcall(doTargetCombat, caster, target, COMBAT_PHYSICALDAMAGE, -math.floor(min), -math.floor(max),
		effect, origin or ORIGIN_MELEE)
	caster:setStorageValue(key, 0)
	if not ok then
		error(result, 0)
	end
	return result
end

-- Make monsters around `pos` let go of `player` (or of every player, when player is nil): drop it as attack and
-- follow target and take it off their target lists. Used by Shadow Veil (stealth) and Smoke Bomb (blind).
function ChaosSpell.dropTarget(monster, player)
	if not monster or not monster:isMonster() then
		return
	end
	local current = monster:getTarget()
	if current and (not player or current == player) then
		monster:setTarget(nil)
		monster:setFollowCreature(nil)
	end
	for _, t in ipairs(monster:getTargetList() or {}) do
		if t:isPlayer() and (not player or t == player) then
			monster:removeTarget(t)
		end
	end
end
