-- Shared helpers of the Necromancer line's spells (necromancer/ lich/ bonelord/; docs/CLASSES.md "Necromancer").
-- Loaded by every Necromancer spell with: dofile('data/spells/scripts/chaos/_necro.lua')
-- Engine helpers (minions, corpses, damage as the caster): data/scripts/chaos/necro_lib.lua (ChaosNecro), loaded
-- here into the spell Lua state; rules: necro_core.lua (ChaosNecroCore); numbers: necro_config.lua.
-- Damage over time is scripted (addEvent pulses in this state) and dealt as the caster, so every tick counts for it
-- and curses amplify it.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosNecro then
	dofile('data/scripts/chaos/necro_lib.lua')
end
if NecroSpell then
	return
end

NecroSpell = {}
local S = NecroSpell
local L = ChaosNecro
local N = ChaosNecroCore
S.cfg = ChaosNecroConfig

-- The line's effect at pos: the first of the pack / own-art effects `vnames` the server knows (chaos_vfx.lua,
-- chaos_vfx_art.lua; e.g. {"bonelord_ward", "bone_aura"}: the new art, then the older one), else the chaos effect
-- `name` / stock `fallback` (nothing when both are nil). Returns the effect name sent, or nil for the fallback.
function S.fx(pos, vnames, name, fallback)
	for _, v in ipairs(vnames) do
		if ChaosSpell.vfx(pos, v) then
			return v
		end
	end
	if name or fallback then
		ChaosSpell.fx(pos, name, fallback)
	end
	return nil
end

-- A summon spell (Raise Bone Warrior / Archer / Mage): ONE minion of `kind` next to the caster. The class's total cap is
-- enforced by ChaosNecro.raise (the oldest minion is dismissed first). Returns true, or cancels with a message.
function S.summon(player, kind)
	local classKey = S.class(player)
	if not classKey then
		return false
	end
	if player:getSkull() == SKULL_BLACK then
		return ChaosSpell.cancel(player)
	end
	local minion = L.raise(player, kind, player:getPosition())
	if not minion then
		return ChaosSpell.noRoom(player)
	end
	-- the seal where the minion rises (it may be placed next to the caster)
	ChaosSpell.vfxOr(minion:getPosition(), "necro_seal", "summon_portal", CONST_ME_MORTAREA)
	return true
end

-- running damage-over-time effects: slot -> token (a recast replaces the running one)
S.dots = {}

-- the caster's class, or cancel with a message
function S.class(player)
	local classKey = L.classOf(player)
	if not classKey then
		ChaosSpell.cancel(player, "Only the Necromancer line can cast this.")
	end
	return classKey
end

-- The target of a needtarget spell that the caster may hit, or nil (the cancel is sent).
function S.target(player, variant)
	local target = ChaosSpell.targetOf(variant)
	if not target or target == player or target:getHealth() <= 0 then
		ChaosSpell.cancel(player, RETURNVALUE_YOUCANONLYUSEITONCREATURES)
		return nil
	end
	local master = target:getMaster()
	if master and master == player then
		ChaosSpell.cancel(player, "You cannot attack your own minions.")
		return nil
	end
	if not ChaosSpell.canAttack(player, target) then
		ChaosSpell.cancel(player, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER)
		return nil
	end
	return target
end

-- Damage over time: `ticks` hits of min..max every tickMs on the creature `targetId`, dealt as the caster, the first at once
-- (firstMs, default 0; O474, was one tickMs after the cast). `key` names the effect (one per caster and target: a recast restarts
-- it). It runs on ChaosSpell.dotChain: when the host dies before the last tick the rest jumps to the nearest living monster
-- within jumpRadius of where it died (default ChaosDotConfig.jump.radius; Soul Rot did this alone before O474; 0 = never).
function S.dot(casterId, targetId, key, ticks, tickMs, min, max, ctype, effect, jumpRadius, firstMs)
	local D = ChaosDot
	if jumpRadius == nil then
		jumpRadius = D and D.cfg().jump and D.cfg().jump.radius or 0
	end
	ChaosSpell.dotChain({
		casterId = casterId, targetId = targetId, key = key, registry = S.dots, ticks = ticks, tickMs = tickMs,
		firstMs = firstMs or 0, jumpRadius = jumpRadius, ctype = ctype,
		onJump = function(from, to)
			ChaosSpell.shoot(from, to:getPosition(), "skull_orb", CONST_ANI_DEATH)
		end,
		deal = function(caster, host)
			local hitFx = effect -- a stock id, or {vfx = <pack effect name>, fx = <stock id without it>}
			if type(effect) == "table" then
				hitFx = ChaosSpell.vfx(host:getPosition(), effect.vfx) and CONST_ME_NONE or effect.fx
			end
			L.damage(caster, host, ctype, min, max, hitFx, ORIGIN_SPELL)
		end,
	})
end

-- Withering Curse on one creature: the amplify timer (monsters) and the rot
function S.curse(player, classKey, target)
	local w = S.cfg.witheringCurse
	if target:isMonster() then
		local sub = classKey == "lich" and S.cfg.subId.curseLich or S.cfg.subId.curse
		L.addTimer(target, sub, w.durationMs)
		target:registerEvent("ChaosNecroCurse")
	end
	local min, max = N.curseTick(S.cfg, classKey, player:getLevel(), player:getMagicLevel(), L.spellFactor(player))
	local tickMs, firstMs, radius = w.tickMs, 0, nil
	local D = ChaosDot
	if D and target:isPlayer() then -- against a player the old gap and first tick (ChaosDotConfig.pvp.necro), never a jump
		local old = D.pvpNecro("curse")
		tickMs, firstMs, radius = old.tickMs or tickMs, old.firstMs or 0, 0
	end
	S.dot(player:getId(), target:getId(), "curse", w.ticks, tickMs, min, max, COMBAT_DEATHDAMAGE,
		CONST_ME_SMALLCLOUDS, radius, firstMs)
	ChaosSpell.fx(target:getPosition(), "necro_skull", CONST_ME_MORTAREA)
end

return S
