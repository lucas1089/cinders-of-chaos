-- Pure logic of the pinnacle bosses (pinnacle.lua; numbers pinnacle_config.lua; tests/pinnacle_test.lua). No engine calls.
-- Overview: server/README.md "Pinnacle bosses (O667)". Lua 5.1 / LuaJIT and Lua 5.3.
--
--   K.index(cfg)                          -> {list, byKey} of the four bosses (index = place in cfg.bosses, 1-4)
--   K.fragKey(cfg, bossIdx, kind)         -> the storage key of a fragment count (kind 1-4)
--   K.have(cfg, read, bossIdx)            -> {n1, n2, n3, n4} of a boss (read(key) -> number)
--   K.setReady(have)                      -> true when every kind is held
--   K.missing(have)                       -> list of the kinds (1-4) not held
--   K.sourceOf(cfg, source, info)         -> the source's row when `info` (tier, omen) qualifies, else nil
--   K.openBosses(cfg, level)              -> the bosses a level opens
--   K.dropBoss(cfg, level, focus, rand)   -> the boss a fragment of a clear is of (focus when it is open, else at random)
--   K.rollClear(cfg, source, info, level, focus, have, rand) -> {{boss, kind}} the fragments one character earns from one clear
--   K.addFragment(cfg, have, kind)        -> newCount, added (the cap)
--   K.scale(curve, players)               -> factor of a {solo, perExtra, max} curve
--   K.bossHealth(boss, players)           -> the health of the fight
--   K.enterError(info)                    -> nil or why (the opener's checks, in order)
--   K.memberError(info)                   -> nil or why (a party member's checks: they stay behind)
--   K.seasonBit(season)                   -> the bit (0-29) of a season; K.hasBit / K.setBit(mask, bit)
--   K.uniqueRoll(cfg, pityKills, find, rand) -> true when the unique drops (a roll, or the bad-luck count reached)
--   K.reward(cfg, boss)                   -> {tokens, chaos, divine, exalted}
--   K.titleList(cfg, boss, firstMask, deathless, seasonTag) -> the titles a boss's rows give (titles.lua form)
--   K.clockText(seconds)                  -> "m:ss"
-- Reasons (why) are {key, args...}: key an English string.format pattern the engine translates (Chaos.t).

ChaosPinnacleCore = ChaosPinnacleCore or {}
local K = ChaosPinnacleCore

local floor, max, min = math.floor, math.max, math.min

local function T(key, ...)
	return {key, ...}
end
K.T = T

-- ======================================================================== the bosses
function K.index(cfg)
	local out = {list = {}, byKey = {}}
	for i, b in ipairs(cfg.bosses or {}) do
		local row = {}
		for k, v in pairs(b) do
			row[k] = v
		end
		row.index = i
		out.list[i] = row
		out.byKey[b.key] = row
	end
	return out
end

function K.openBosses(cfg, level)
	local out = {}
	for i, b in ipairs(cfg.bosses or {}) do
		if (level or 0) >= b.minLevel then
			out[#out + 1] = i
		end
	end
	return out
end

-- ======================================================================== fragments
function K.fragKey(cfg, bossIdx, kind)
	local s = cfg.storage
	return s.base + s.frag + (bossIdx - 1) * 4 + (kind - 1)
end

function K.have(cfg, read, bossIdx)
	local out = {}
	for kind = 1, 4 do
		out[kind] = max(0, floor(tonumber(read(K.fragKey(cfg, bossIdx, kind))) or 0))
	end
	return out
end

function K.setReady(have)
	for kind = 1, 4 do
		if (have[kind] or 0) < 1 then
			return false
		end
	end
	return true
end

function K.missing(have)
	local out = {}
	for kind = 1, 4 do
		if (have[kind] or 0) < 1 then
			out[#out + 1] = kind
		end
	end
	return out
end

-- a clear of a source: `info` = {tier = number (waystone / rift tier), omen = true for an Omen guardian}. The source's row, or nil
function K.sourceOf(cfg, source, info)
	local row = (cfg.fragments.sources or {})[source]
	if not row then
		return nil
	end
	info = info or {}
	if source == "waystone" and (tonumber(info.tier) or 0) < (row.minTier or 1) then
		return nil
	end
	if source == "rift" then
		if info.omen then
			return nil
		end
		if (tonumber(info.tier) or 0) < (row.minTier or 1) then
			return nil
		end
	end
	if source == "omen" and not info.omen then
		return nil
	end
	return row
end

-- the boss a fragment is of: the focus when the level opens it, else one of the open bosses at random; nil when none is open
function K.dropBoss(cfg, level, focus, rand)
	local open = K.openBosses(cfg, level)
	if #open == 0 then
		return nil
	end
	focus = tonumber(focus) or 0
	for _, i in ipairs(open) do
		if i == focus then
			return i
		end
	end
	return open[rand(1, #open)]
end

local function roll(percent, rand)
	return percent > 0 and rand(1, 10000) <= floor(percent * 100 + 0.5)
end

-- the fragments one character earns from one clear: its own kind and the keystone, each a roll. `have` is not read here (the cap
-- is applied by K.addFragment); `rand(a, b)` -> integer
function K.rollClear(cfg, source, info, level, focus, rand)
	local row = K.sourceOf(cfg, source, info)
	local out = {}
	if not row then
		return out
	end
	local boss = K.dropBoss(cfg, level, focus, rand)
	if not boss then
		return out
	end
	if roll(row.chance or 0, rand) then
		out[#out + 1] = {boss = boss, kind = row.kind}
	end
	if roll(row.anyChance or 0, rand) then
		out[#out + 1] = {boss = boss, kind = 4}
	end
	return out
end

-- one fragment added to a held count: the new count and whether it was added (a full kind keeps its cap)
function K.addFragment(cfg, count, kind)
	local cap = cfg.fragments.cap or 6
	count = count or 0
	if count >= cap then
		return count, false
	end
	return count + 1, true
end

-- ======================================================================== scaling
function K.scale(curve, players)
	players = max(1, players or 1)
	local f = (curve.solo or 1) + (curve.perExtra or 0) * (players - 1)
	if curve.max then
		f = min(f, curve.max)
	end
	return f
end

-- the health of the fight: the boss's own solo health x (1 + perExtra x (players - 1)), whole
function K.bossHealth(boss, players)
	players = max(1, players or 1)
	return floor(boss.health * (1 + (boss.perExtra or 0) * (players - 1)) + 0.5)
end

-- ======================================================================== entering
-- info: {enabled, boss, level, needPz, pz, inFight, instance (label or nil), cooldown (seconds), have = {n1..n4}, noRoom}
function K.enterError(info)
	if not info.enabled then
		return T("The pinnacle bosses are closed for now.")
	end
	local boss = info.boss
	if not boss then
		return T("There is no such pinnacle boss.")
	end
	if (info.level or 0) < boss.minLevel then
		return T("%s opens from level %d.", boss.name, boss.minLevel)
	end
	if info.instance then
		return T("You are in %s already.", info.instance)
	end
	if info.needPz and not info.pz then
		return T("Open it from a protection zone.")
	end
	if info.inFight then
		return T("You cannot open it in a fight.")
	end
	if (info.cooldown or 0) > 0 then
		return T("Wait %d seconds before you open another.", info.cooldown)
	end
	if not K.setReady(info.have or {}) then
		local names = {}
		for _, kind in ipairs(K.missing(info.have or {})) do
			names[#names + 1] = boss.fragments[kind]
		end
		return T("The set is not whole. Missing: %s.", table.concat(names, ", "))
	end
	return nil
end

-- a party member of the opener: stays behind with the reason (they pay no set)
function K.memberError(info)
	local boss = info.boss
	if (info.level or 0) < boss.minLevel then
		return T("level %d is needed", boss.minLevel)
	end
	if info.instance then
		return T("in %s", info.instance)
	end
	if info.inFight then
		return T("in a fight")
	end
	if info.far then
		return T("too far")
	end
	return nil
end

-- ======================================================================== seasons and titles
function K.seasonBit(season)
	return (tonumber(season) or 0) % 30
end

function K.hasBit(mask, bit)
	mask = max(0, floor(tonumber(mask) or 0))
	return floor(mask / 2 ^ bit) % 2 == 1
end

function K.setBit(mask, bit)
	mask = max(0, floor(tonumber(mask) or 0))
	if K.hasBit(mask, bit) then
		return mask
	end
	return floor(mask + 2 ^ bit)
end

-- the titles of one boss: a first-kill title per season bit set (the tag of the season by `tags[bit]`, else "[S<bit>]") and the
-- deathless one. A title: {key, text, color, frame, at}; the text is cut to 24 characters
function K.titleList(cfg, boss, firstMask, deathless, tags, at)
	local t = cfg.titles
	local out = {}
	for bit = 0, 29 do
		if K.hasBit(firstMask, bit) then
			local tag = (tags and tags[bit]) or ("[S" .. bit .. "]")
			out[#out + 1] = {key = "pinnacle:" .. boss.key .. ":s" .. bit, text = (string.format(t.first, boss.short, tag)):sub(1, 24),
				color = t.color, frame = t.frame, at = at or 0}
		end
	end
	if deathless and deathless > 0 then
		out[#out + 1] = {key = "pinnacle:" .. boss.key .. ":deathless", text = (string.format(t.deathless, boss.short)):sub(1, 24),
			color = t.color, frame = t.frame, at = at or 0}
	end
	return out
end

-- ======================================================================== rewards
-- the exclusive unique of one player at one kill: a roll of `chance` percent x find (capped), or the bad-luck count reached.
-- pityKills = kills of that boss since the last unique, this kill not counted. Returns drops, newCount.
function K.uniqueRoll(cfg, pityKills, find, rand)
	local u = cfg.unique
	local mult = min(max(tonumber(find) or 1, 0), u.itemFindCap or 1.5)
	pityKills = max(0, floor(tonumber(pityKills) or 0))
	if pityKills + 1 >= (u.pity or 8) or roll(u.chance * mult, rand) then
		return true, 0
	end
	return false, pityKills + 1
end

function K.reward(cfg, boss)
	local o = boss.orbs or {}
	return {tokens = boss.tokens or 0, chaos = o.chaos or 0, divine = o.divine or 0, exalted = o.exalted or 0}
end

function K.clockText(secs)
	secs = max(0, floor((secs or 0) + 0.5))
	return string.format("%d:%02d", floor(secs / 60), secs % 60)
end

-- the marker of a run in progress (the boss index + 1, 0 none)
function K.marker(bossIdx)
	return (bossIdx or 0) > 0 and bossIdx or 0
end

return K
