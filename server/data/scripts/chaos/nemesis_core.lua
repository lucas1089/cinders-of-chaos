-- Nemesis pure logic (no engine calls): who may become a nemesis, the birth chance with the server-wide soft cap,
-- names and epithets (en / pt-BR), level and growth, traits, when it appears, who it may hurt, the rewards and the
-- anti-farm rules, expiry, the SQL and the client view. Used by nemesis.lua, tested by server/tests/nemesis_test.lua.
-- Every function takes the config table (nemesis_config.lua) and, where it rolls, rand(a, b) -> integer in [a, b].
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosNemesisCore = ChaosNemesisCore or {}
local K = ChaosNemesisCore

local floor = math.floor

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end
K.clamp = clamp

local function num(v, default)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return v
end

-- ------------------------------------------------------------------ texts
function K.lang(lang)
	return (lang == "pt" or lang == "pt-BR" or lang == "pt_BR") and "pt" or "en"
end

-- text of key in lang (pt-BR or English), formatted with the arguments; English when pt-BR lacks it
function K.text(cfg, lang, key, ...)
	local texts = cfg.texts or {}
	local l = K.lang(lang)
	local t = (texts[l] or {})[key] or (texts.en or {})[key] or key
	if select("#", ...) > 0 then
		local ok, s = pcall(string.format, t, ...)
		if ok then
			return s
		end
	end
	return t
end

-- ------------------------------------------------------------------ birth
-- the birth chance in percent with `active` nemeses on the server: cfg.birth.chance up to the soft cap, then falling
-- linearly to 0 at the hard cap
function K.birthChance(cfg, active)
	local b = cfg.birth
	local chance = num(b.chance, 0)
	active = num(active, 0)
	local soft, hard = num(b.softCap, 0), num(b.serverCap, 0)
	if hard <= 0 or active >= hard then
		return 0
	end
	if soft > 0 and soft < hard and active > soft then
		chance = chance * (hard - active) / (hard - soft)
	end
	return chance
end

-- Whether a death may make a nemesis, before the dice. info = {
--   victimLevel, killer = {monster (bool), master (bool), boss (bool), name (type name), shown (shown name),
--   maxHealth, goblin (bool), nemesis (bool: already somebody's nemesis)}, pvp (a player took part), instance (key or
--   nil), active (this character's active nemeses), serverActive, endedAt (os.time its last one ended)}
-- Returns ok, reason.
function K.eligible(cfg, info, now)
	local b = cfg.birth
	if not cfg.enabled then
		return false, "disabled"
	end
	local k = info.killer
	if not k or not k.monster then
		return false, "not a monster"
	end
	if info.pvp then
		return false, "pvp"
	end
	if k.master then
		return false, "summon"
	end
	if k.boss then
		return false, "boss"
	end
	if k.goblin then
		return false, "goblin"
	end
	if k.nemesis then
		return false, "nemesis"
	end
	if info.instance then
		return false, "instance"
	end
	local name = tostring(k.name or ""):lower()
	if name == "" then
		return false, "no type"
	end
	-- a renamed monster is an event or instance monster (rift, invader, ambush copy of a rift monster)
	if k.shown and tostring(k.shown):lower() ~= name then
		return false, "event monster"
	end
	if (b.skipNames or {})[name] then
		return false, "skipped"
	end
	if num(k.maxHealth, 0) < num(b.minMonsterHealth, 0) then
		return false, "weak"
	end
	if num(info.victimLevel, 0) < num(b.minLevel, 0) then
		return false, "level"
	end
	if num(info.active, 0) >= num(b.maxPerPlayer, 1) then
		return false, "has one"
	end
	if num(info.endedAt, 0) > 0 and num(now, 0) - num(info.endedAt, 0) < num(b.cooldownSeconds, 0) then
		return false, "cooldown"
	end
	if K.birthChance(cfg, info.serverActive) <= 0 then
		return false, "server cap"
	end
	return true
end

-- the dice: chance in 1/100 percent steps
function K.rollBirth(cfg, info, now, rand)
	local ok, why = K.eligible(cfg, info, now)
	if not ok then
		return false, why
	end
	local chance = K.birthChance(cfg, info.serverActive)
	if rand(1, 10000) > floor(chance * 100 + 0.5) then
		return false, "roll"
	end
	return true
end

-- ------------------------------------------------------------------ names
function K.genName(cfg, rand)
	local n = cfg.names
	local p = n.prefixes[rand(1, #n.prefixes)]
	local m = n.middles[rand(1, #n.middles)]
	local s = n.suffixes[rand(1, #n.suffixes)]
	-- no doubled letter at a seam ("Ulla"), no vowel pile-up ("Zulaa")
	if m ~= "" and p:sub(-1):lower() == m then
		m = ""
	end
	if m == "" and p:sub(-1):lower() == s:sub(1, 1) then
		s = s:sub(2)
	end
	return p .. m .. s
end

-- epithet for the kills (1.. #list, the last one for more); victim = the victim's name
function K.epithet(cfg, lang, victim, kills)
	local list = (cfg.epithets or {})[K.lang(lang)] or cfg.epithets.en
	local i = clamp(floor(num(kills, 1)), 1, #list)
	return string.format(list[i], tostring(victim or "?"))
end

-- the shown name: "Varkh, Bane of Varek"; over names.maxShown characters only the base name
function K.fullName(cfg, lang, rec, victim)
	local full = tostring(rec.name) .. ", " .. K.epithet(cfg, lang, victim, rec.kills)
	if #full > (cfg.names.maxShown or 40) then
		return tostring(rec.name)
	end
	return full
end

-- ------------------------------------------------------------------ level and growth
function K.baseLevel(cfg, monsterLevel, maxHealth)
	local l = cfg.level
	local level = num(monsterLevel, 0)
	if level <= 0 then
		level = num(maxHealth, 0) / (l.healthPerLevel or 20)
	end
	return clamp(floor(level), l.min or 1, l.max or 1500)
end

-- level for a base level, the birth bump (percent) and the kills
function K.levelFor(cfg, base, bump, kills)
	local l = cfg.level
	local extra = (clamp(num(kills, 1), 1, l.maxKills or 4) - 1) * (l.growthPct or 0)
	return clamp(floor(base * (100 + num(bump, 0) + extra) / 100 + 0.5), l.min or 1, l.max or 1500)
end

-- weighted trait pick among those not held yet; nil when every trait is held
function K.pickTrait(cfg, have, rand)
	local held = {}
	for _, k in ipairs(have or {}) do
		held[k] = true
	end
	local pool, total = {}, 0
	for _, t in ipairs(cfg.traits) do
		if not held[t.key] and (t.weight or 0) > 0 then
			pool[#pool + 1] = t
			total = total + t.weight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll, acc = rand(1, total), 0
	for _, t in ipairs(pool) do
		acc = acc + t.weight
		if roll <= acc then
			return t.key
		end
	end
	return pool[#pool].key
end

function K.trait(cfg, key)
	for _, t in ipairs(cfg.traits) do
		if t.key == key then
			return t
		end
	end
	return nil
end

-- a new record. info = {victim (guid), monster (type name), monsterLevel, maxHealth, hc}
function K.newRecord(cfg, info, now, rand)
	local base = K.baseLevel(cfg, info.monsterLevel, info.maxHealth)
	local bump = rand(cfg.level.bumpMin, cfg.level.bumpMax)
	local rec = {
		victim = info.victim, monster = info.monster, name = K.genName(cfg, rand), baseLevel = base, bump = bump,
		kills = 1, traits = {}, created = now, lastSeen = now, appearances = 0, hc = info.hc and true or false
	}
	rec.level = K.levelFor(cfg, base, bump, 1)
	rec.traits[1] = K.pickTrait(cfg, {}, rand)
	return rec
end

-- the nemesis killed its victim again: one more kill (up to maxKills), level up, the second trait. Returns true when
-- it grew (at the cap only lastSeen changes).
function K.grow(cfg, rec, now, rand)
	rec.lastSeen = now
	local maxKills = cfg.level.maxKills or 4
	if (rec.kills or 1) >= maxKills then
		return false
	end
	rec.kills = (rec.kills or 1) + 1
	rec.level = K.levelFor(cfg, rec.baseLevel, rec.bump, rec.kills)
	if #rec.traits < (cfg.maxTraits or 2) then
		local t = K.pickTrait(cfg, rec.traits, rand)
		if t then
			rec.traits[#rec.traits + 1] = t
		end
	end
	return true
end

-- the monster's numbers: maxHealth (from the type's), speed delta, damage and experience multipliers
function K.stats(cfg, rec, typeMaxHealth)
	local s = cfg.stats
	local ratio = rec.level / math.max(1, rec.baseLevel)
	local speed = s.speed or 0
	for _, key in ipairs(rec.traits or {}) do
		local t = K.trait(cfg, key)
		speed = speed + (t and t.speed or 0)
	end
	return {
		maxHealth = math.max(1, floor(num(typeMaxHealth, 1) * (s.healthMult or 1) * ratio)),
		speed = speed, damage = s.damageMult or 1, xp = s.xpMult or 1
	}
end

-- the monster_tiers.lua modifier keys of the traits (stalker has none)
function K.modKeys(cfg, rec)
	local out = {}
	for _, key in ipairs(rec.traits or {}) do
		local t = K.trait(cfg, key)
		if t and t.mod then
			out[#out + 1] = t.mod
		end
	end
	return out
end

function K.hasTrait(rec, key)
	for _, k in ipairs(rec.traits or {}) do
		if k == key then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------------ expiry
function K.expired(cfg, rec, now)
	return num(now, 0) - num(rec.lastSeen, 0) >= (cfg.expireDays or 14) * 86400
end

-- ------------------------------------------------------------------ appearing
-- a kill of the victim calls the nemesis: same type, or a monster within bandPct of its base level
function K.matchesHunt(cfg, rec, killedName, killedLevel)
	if tostring(killedName or ""):lower() == tostring(rec.monster or ""):lower() then
		return true
	end
	local lvl = num(killedLevel, 0)
	if lvl <= 0 then
		return false
	end
	local band = (cfg.appear.bandPct or 0) / 100
	local base = rec.baseLevel or 1
	return lvl >= base * (1 - band) and lvl <= base * (1 + band)
end

-- kill = {name, level, instance, pz}; st = {alive (bool), pending (bool), lastAppear}. Returns ok, reason.
function K.appearRoll(cfg, rec, kill, st, now, rand)
	local a = cfg.appear
	if not cfg.enabled then
		return false, "disabled"
	end
	if not rec then
		return false, "none"
	end
	if st.alive or st.pending then
		return false, "already here"
	end
	if kill.instance or kill.pz then
		return false, "area"
	end
	if num(st.lastAppear, 0) > 0 and now - st.lastAppear < (a.cooldownSeconds or 0) then
		return false, "cooldown"
	end
	if not K.matchesHunt(cfg, rec, kill.name, kill.level) then
		return false, "elsewhere"
	end
	if rand(1, 10000) > floor((a.chance or 0) * 100 + 0.5) then
		return false, "roll"
	end
	return true
end

-- positions on the ring minDistance..maxDistance around center (same floor), nearest ring first, in a rand order
function K.ringPositions(cfg, center, rand)
	local a = cfg.appear
	local out = {}
	for r = a.minDistance or 3, a.maxDistance or 6 do
		local ring = {}
		for dx = -r, r do
			for dy = -r, r do
				if math.max(math.abs(dx), math.abs(dy)) == r then
					ring[#ring + 1] = {x = center.x + dx, y = center.y + dy, z = center.z}
				end
			end
		end
		for i = #ring, 2, -1 do
			local j = rand(1, i)
			ring[i], ring[j] = ring[j], ring[i]
		end
		for _, p in ipairs(ring) do
			out[#out + 1] = p
		end
	end
	return out
end

-- who the nemesis may hurt: its victim and the victim's party (no griefing of strangers)
function K.canHurt(victimGuid, targetGuid, partyGuids)
	if targetGuid == victimGuid then
		return true
	end
	for _, g in ipairs(partyGuids or {}) do
		if g == targetGuid then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------------ rewards
-- k = {guid, account, ip, isVictim, inParty, hc, lastBounty, lastAvenge}; v = {guid, account, ip} of the victim.
-- Returns {kind = "avenge" | "hunt" | "none", trophy, gold, goldTo = "corpse" | "bank", title, reason}
function K.reward(cfg, rec, k, v, now)
	local r = cfg.rewards
	if rec.rewarded then
		return {kind = "none", reason = "rewarded"}
	end
	if k.isVictim then
		local out = {kind = "avenge", trophy = true, gold = 0, title = r.titles.avenger}
		if k.hc and r.hardcoreTrophyOnly then
			out.reason = "hardcore"
			return out
		end
		if num(k.lastAvenge, 0) > 0 and now - k.lastAvenge < r.avenge.cooldownSeconds then
			out.reason = "cooldown"
			return out
		end
		out.gold = floor(r.avenge.goldBase + r.avenge.goldPerLevel * rec.level)
		out.goldTo = "corpse"
		return out
	end
	if not k.inParty then
		return {kind = "none", reason = "stranger"}
	end
	local out = {kind = "hunt", trophy = false, gold = 0}
	if k.hc and r.hardcoreTrophyOnly then
		out.reason = "hardcore"
		return out
	end
	-- the victim's other characters or connection never earn the bounty (a planned death to feed a second character)
	if (k.account and k.account == v.account) or (num(k.ip, 0) ~= 0 and k.ip == v.ip) then
		out.reason = "same owner"
		return out
	end
	if now - num(rec.created, now) < r.bounty.minAgeSeconds then
		out.reason = "too young"
		return out
	end
	if num(k.lastBounty, 0) > 0 and now - k.lastBounty < r.bounty.cooldownSeconds then
		out.reason = "cooldown"
		return out
	end
	out.gold = floor(r.bounty.goldBase + r.bounty.goldPerLevel * rec.level)
	out.goldTo = "bank"
	return out
end

-- gold value -> {{id, count}, ...} in crystal (2160), platinum (2152) and gold (2148) coins, stacks of at most 100
function K.coins(value)
	local out = {}
	local function add(id, n)
		while n > 0 do
			local c = math.min(100, n)
			out[#out + 1] = {id = id, count = c}
			n = n - c
		end
	end
	value = math.max(0, floor(num(value, 0)))
	add(2160, floor(value / 10000))
	value = value % 10000
	add(2152, floor(value / 100))
	add(2148, value % 100)
	return out
end

-- the titles a character holds: avenged / hunted = its counters
function K.titles(cfg, avenged, hunted)
	local t = cfg.rewards.titles
	local out = {}
	if num(avenged, 0) >= 1 then
		out[#out + 1] = {key = "nemesis:avenger", text = t.avenger, color = t.color}
	end
	if num(hunted, 0) >= (t.hunterMin or 1) then
		out[#out + 1] = {key = "nemesis:hunter", text = t.hunter, color = t.color}
	end
	return out
end

-- ------------------------------------------------------------------ persistence
function K.encodeTraits(list)
	return table.concat(list or {}, ",")
end

function K.decodeTraits(cfg, s)
	local out, seen = {}, {}
	for key in tostring(s or ""):gmatch("[%w_]+") do
		if K.trait(cfg, key) and not seen[key] and #out < (cfg.maxTraits or 2) then
			seen[key] = true
			out[#out + 1] = key
		end
	end
	return out
end

-- a DB row (strings or numbers) -> record, or nil when it is broken
function K.fromRow(cfg, row)
	local id, victim = tonumber(row.id), tonumber(row.player_id)
	if not id or not victim or type(row.monster) ~= "string" or row.monster == "" then
		return nil
	end
	local rec = {
		id = id, victim = victim, monster = row.monster, name = tostring(row.name or "?"),
		baseLevel = math.max(1, tonumber(row.base_level) or 1), level = math.max(1, tonumber(row.level) or 1),
		bump = tonumber(row.bump) or 0, kills = clamp(tonumber(row.kills) or 1, 1, cfg.level.maxKills or 4),
		traits = K.decodeTraits(cfg, row.traits), created = tonumber(row.created) or 0,
		lastSeen = tonumber(row.last_seen) or 0, appearances = tonumber(row.appearances) or 0,
		hc = (tonumber(row.hc) or 0) > 0
	}
	return rec
end

local COLUMNS = "`player_id`, `monster`, `name`, `base_level`, `level`, `bump`, `kills`, `traits`, `created`, " ..
	"`last_seen`, `appearances`, `hc`"
K.SELECT_COLUMNS = {"id", "player_id", "monster", "name", "base_level", "level", "bump", "kills", "traits", "created",
	"last_seen", "appearances", "hc"}

function K.sqlCreate(T)
	return "CREATE TABLE IF NOT EXISTS `" .. T .. "` (`id` int(10) unsigned NOT NULL AUTO_INCREMENT, " ..
		"`player_id` int(11) NOT NULL, `monster` varchar(64) NOT NULL, `name` varchar(32) NOT NULL, " ..
		"`base_level` smallint(5) unsigned NOT NULL DEFAULT 1, `level` smallint(5) unsigned NOT NULL DEFAULT 1, " ..
		"`bump` tinyint(3) unsigned NOT NULL DEFAULT 0, `kills` tinyint(3) unsigned NOT NULL DEFAULT 1, " ..
		"`traits` varchar(64) NOT NULL DEFAULT '', `created` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`last_seen` int(10) unsigned NOT NULL DEFAULT 0, `appearances` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`hc` tinyint(1) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `chaos_nemesis_player` (`player_id`), " ..
		"KEY `chaos_nemesis_seen` (`last_seen`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
end

function K.sqlInsert(T, rec, esc)
	return string.format("INSERT INTO `%s` (%s) VALUES (%d, %s, %s, %d, %d, %d, %d, %s, %d, %d, %d, %d)", T, COLUMNS,
		rec.victim, esc(rec.monster), esc(rec.name), rec.baseLevel, rec.level, rec.bump or 0, rec.kills,
		esc(K.encodeTraits(rec.traits)), rec.created, rec.lastSeen, rec.appearances or 0, rec.hc and 1 or 0)
end

function K.sqlUpdate(T, rec, esc)
	return string.format("UPDATE `%s` SET `level` = %d, `kills` = %d, `traits` = %s, `last_seen` = %d, " ..
		"`appearances` = %d WHERE `id` = %d AND `player_id` = %d", T, rec.level, rec.kills,
		esc(K.encodeTraits(rec.traits)), rec.lastSeen, rec.appearances or 0, rec.id, rec.victim)
end

function K.sqlDelete(T, rec)
	return string.format("DELETE FROM `%s` WHERE `id` = %d AND `player_id` = %d", T, rec.id, rec.victim)
end

function K.sqlSelectVictim(T, guid)
	return string.format("SELECT `id`, %s FROM `%s` WHERE `player_id` = %d ORDER BY `id` DESC LIMIT 5", COLUMNS, T,
		guid)
end

function K.sqlExpire(cfg, T, now)
	return string.format("DELETE FROM `%s` WHERE `last_seen` < %d", T, now - (cfg.expireDays or 14) * 86400)
end

function K.sqlCount(T)
	return "SELECT COUNT(*) AS `n` FROM `" .. T .. "`"
end

-- ------------------------------------------------------------------ client view
-- rec (or nil) -> the "state" payload: {has, name, shown, monster, level, kills, traits = {{key, name, desc}},
-- lastSeen, created, expiresIn, avenged, hunted}
function K.view(cfg, rec, victimName, now, lang, counters)
	counters = counters or {}
	local out = {has = rec ~= nil, avenged = num(counters.avenged, 0), hunted = num(counters.hunted, 0)}
	if not rec then
		return out
	end
	local pt = K.lang(lang) == "pt"
	out.name = rec.name
	out.shown = K.fullName(cfg, lang, rec, victimName)
	out.monster = rec.monster
	out.level = rec.level
	out.kills = rec.kills
	out.lastSeen = rec.lastSeen
	out.created = rec.created
	out.expiresIn = math.max(0, rec.lastSeen + (cfg.expireDays or 14) * 86400 - now)
	out.traits = {}
	for _, key in ipairs(rec.traits or {}) do
		local t = K.trait(cfg, key)
		if t then
			out.traits[#out.traits + 1] = {key = key, name = pt and t.pt or t.name, desc = pt and t.descPt or t.desc}
		end
	end
	return out
end

return K
