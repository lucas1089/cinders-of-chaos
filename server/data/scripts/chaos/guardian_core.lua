-- Guardian teeth (O427): the pure part (no engine calls), shared by rift.lua, necro_minions.lua, boss_mechanics.lua
-- callers and tests/guardian_test.lua. Config: rift_config.lua `guardian`. server/README.md "Rifts", Guardian damage.
--   damageMult  x on a guardian's own hits to players, by rift tier (an Omen guardian its own number)
--   minionHit   what a guardian's hit does to a summon and its owner (no wall: factor 1, half of it splashes the owner)
--   kitCount    how many extra attacks a guardian gets
--   pickKit     which ones, from the run's seed and the theme (same seed, same guardian)
--   profile     a boss_mechanics profile with the kit added (the shares grow with the tier)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosGuardianCore = ChaosGuardianCore or {}
local G = ChaosGuardianCore
local floor, min, max = math.floor, math.min, math.max

-- guardian damage multiplier (tier nil or omen true: the Omen number)
function G.damageMult(cfg, tier, omen)
	local d = cfg and cfg.guardian and cfg.guardian.damage
	if not d then
		return 1
	end
	if omen then
		return d.omen or 1
	end
	return max(d.min or 0, d.base + d.perTier * (max(1, tier or 1) - 1))
end

-- a guardian hit (damage as the engine gives it, sign kept) on a summon: returns the summon's damage and the owner's splash
function G.minionHit(cfg, damage)
	local m = cfg and cfg.guardian and cfg.guardian.minion
	if not m or damage == 0 then
		return damage, 0
	end
	local sign = damage < 0 and -1 or 1
	local a = math.abs(damage)
	local own = max(1, floor(a * (m.factor or 1) + 0.5))
	local splash = (m.splash or 0) > 0 and max(1, floor(a * m.splash + 0.5)) or 0
	return sign * own, splash
end

-- how many extra attacks: a rift guardian base + floor(tier / perTiers), an Omen guardian omenCount
function G.kitCount(cfg, tier, omen)
	local k = cfg.guardian.kit
	if omen then
		return k.omenCount
	end
	return k.base + floor(max(1, tier or 1) / k.perTiers)
end

-- a small deterministic generator from a seed: rand(a, b)
local function lcg(seed)
	local s = floor(tonumber(seed) or 1) % 2147483647
	if s <= 0 then
		s = s + 2147483646
	end
	return function(a, b)
		s = (s * 48271) % 2147483647
		return a + s % (b - a + 1)
	end
end
G.lcg = lcg

-- the extra attacks of one guardian: `count` different abilities, drawn by weight (the theme's own weigh themeWeight x);
-- seed = the run's id and tier, theme = the layout theme (the monster family) name. Returns a list of ability keys in
-- draw order. skip = a set of keys the guardian already has (Omen guardians with their own telegraphs).
function G.pickKit(cfg, seed, theme, tier, omen, skip)
	local k = cfg.guardian.kit
	local rand = lcg(seed)
	local pool = {}
	for _, a in ipairs(cfg.guardian.abilities) do
		if not (skip and skip[a.key]) and not (a.minTier and (tier or 1) < a.minTier) then
			local w = 1
			for _, t in ipairs(a.themes or {}) do
				if t == theme then
					w = k.themeWeight
				end
			end
			pool[#pool + 1] = {a, w}
		end
	end
	local out = {}
	for _ = 1, min(G.kitCount(cfg, tier, omen), #pool) do
		local total = 0
		for _, r in ipairs(pool) do
			total = total + r[2]
		end
		local roll, acc = rand(1, total), 0
		for i, r in ipairs(pool) do
			acc = acc + r[2]
			if roll <= acc then
				out[#out + 1] = r[1].key
				table.remove(pool, i)
				break
			end
		end
	end
	return out
end

-- one ability spec of the kit with its share grown by the tier: a copy for boss_mechanics (telegraphs list entry)
function G.spec(cfg, key, tier, omen)
	local k = cfg.guardian.kit
	for _, a in ipairs(cfg.guardian.abilities) do
		if a.key == key then
			local s = {}
			for f, v in pairs(a) do
				s[f] = v
			end
			s.themes = nil
			local share = a.share * (1 + k.sharePerTier * (max(1, tier or 1) - 1)) * (omen and k.omenShareMult or 1)
			s.share = min(k.shareCap * (omen and k.omenShareMult or 1), share)
			return s
		end
	end
	return nil
end

-- a boss_mechanics profile: `base` (a profile table) with the kit's specs added to its telegraphs and a faster cadence.
-- Copies the telegraph list, not the other fields (they stay shared and are only read); `ownTelegraphs` makes the
-- engine give the fight its own list, so the shared one is never changed.
function G.profile(cfg, base, keys, tier, omen)
	local p = setmetatable({}, {__index = base})
	local list = {}
	for _, t in ipairs(base.telegraphs or {}) do
		list[#list + 1] = t
	end
	for _, key in ipairs(keys) do
		local s = G.spec(cfg, key, tier, omen)
		if s then
			list[#list + 1] = s
		end
	end
	p.telegraphs = list
	if base.every then -- each extra attack makes the guardian use its marks more often (never faster than the engine allows)
		p.every = floor(base.every * cfg.guardian.kit.everyMult ^ #keys)
	end
	return p
end

-- the share of a victim's max health a guardian's marked attacks take per second, on average, for the profile's own
-- cadence (one telegraph per `every` x (1 - 0.25 x difficulty) ms, all specs equally likely): for the model
function G.markShare(profile, difficulty, tier)
	local list = {}
	for _, t in ipairs(profile.telegraphs or {}) do
		if not (t.minTier and (tier or 1) < t.minTier) then
			list[#list + 1] = t
		end
	end
	if #list == 0 then
		return 0
	end
	local sum = 0
	for _, t in ipairs(list) do
		sum = sum + (t.share or 0)
	end
	local every = (profile.every or 9000) * (1 - 0.25 * (difficulty or 0))
	return sum / #list / (every / 1000)
end

return G
