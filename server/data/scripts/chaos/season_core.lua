-- Seasons: pure logic (no engine calls), shared by season.lua and server/tests/season_test.lua.
--   dates      ChaosSeason.toUnix(v, hour), times(season, ov), status(season, now, ov), active(...), upcoming(...),
--              formatDuration(seconds)
--   realms     realm = 0 for standard characters, the season id for an unmigrated character of a running season.
--              realm(row, now, seasons, ov), tagRealm(tag, now, seasons, ov)
--   joining    joinCheck(info, cfg, now, ov)
--   isolation  tradeAllowed(a, b), moveCheck(m), partyAllowed(a, b), mailReceiver(text)
--   coins      storePartAllowed(offer, rules), storeRefusal(offer, rules), storeText(realm, offer, rules, gift, name),
--              passClaimAllowed(reward, realm, rules),
--              marketCurrencyAllowed(realm, currency, rules)
--   track      mergeStat(mode, old, value), milestonesDue(track, stats, reached, has), trackView(...),
--              rewardLook(reward, female)
--   migration  migrationDue(row, now, seasons, ov), migrationPlan(rows, now, seasons, ov)
--   uniques    uniqueAllowed(uniqueSeason, ownerRealm, now, seasons, ov)
-- `ov` (overrides) = {[seasonId] = {start = unix, finish = unix}} from /season start|end (server_config rows).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosSeason = ChaosSeason or {}
local S = ChaosSeason

-- ---------------------------------------------------------------- dates
-- YYYYMMDD (8 digits, at `hour` local time), "YYYY-MM-DD", or a unix time -> unix time (nil when invalid)
function S.toUnix(v, hour)
	if type(v) == "string" then
		local y, m, d = v:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
		if y then
			v = tonumber(y) * 10000 + tonumber(m) * 100 + tonumber(d)
		else
			v = tonumber(v)
		end
	end
	if type(v) ~= "number" or v ~= v or v < 0 then
		return nil
	end
	v = math.floor(v)
	if v >= 19000101 and v <= 99991231 then
		local y, m, d = math.floor(v / 10000), math.floor(v / 100) % 100, v % 100
		if m < 1 or m > 12 or d < 1 or d > 31 then
			return nil
		end
		return os.time({year = y, month = m, day = d, hour = hour or 0, min = 0, sec = 0})
	end
	return v
end

-- start, finish (unix) of a season; the overrides of /season start|end win
function S.times(season, ov)
	local o = ov and ov[season.id] or {}
	local start = o.start or S.toUnix(season.start, season.hour or 0)
	local finish = o.finish or S.toUnix(season.finish, season.hour or 0)
	return start, finish
end

-- "upcoming" | "active" | "ended" (a season with broken dates is "ended": it never runs)
function S.status(season, now, ov)
	local start, finish = S.times(season, ov)
	if not start or not finish or finish <= start then
		return "ended"
	end
	if now < start then
		return "upcoming"
	end
	if now < finish then
		return "active"
	end
	return "ended"
end

-- the running season (the first one in the list when two overlap by mistake), or nil
function S.active(seasons, now, ov)
	for _, s in ipairs(seasons or {}) do
		if S.status(s, now, ov) == "active" then
			return s
		end
	end
	return nil
end

-- the next season to start, or nil
function S.upcoming(seasons, now, ov)
	local best, bestStart
	for _, s in ipairs(seasons or {}) do
		if S.status(s, now, ov) == "upcoming" then
			local start = S.times(s, ov)
			if not bestStart or start < bestStart then
				best, bestStart = s, start
			end
		end
	end
	return best
end

function S.byId(seasons, id)
	for _, s in ipairs(seasons or {}) do
		if s.id == id then
			return s
		end
	end
	return nil
end

-- 93784 -> "1d 2h", 7500 -> "2h 5m", 300 -> "5m", 20 -> "under a minute"
function S.formatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local d = math.floor(seconds / 86400)
	local h = math.floor((seconds % 86400) / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if d > 0 then
		return string.format("%dd %dh", d, h)
	end
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	if m > 0 then
		return string.format("%dm", m)
	end
	return "under a minute"
end

-- ---------------------------------------------------------------- realms
-- row = {season = id, migrated = unix or 0} (chaos_season_players) or nil. A character is in its season's realm
-- until it is migrated or its season ends, whichever comes first.
function S.realm(row, now, seasons, ov)
	if not row or (tonumber(row.migrated) or 0) > 0 then
		return 0
	end
	local s = S.byId(seasons, row.season)
	if not s or S.status(s, now, ov) ~= "active" then
		return 0
	end
	return s.id
end

-- realm tag of an item (custom attribute) -> the realm it counts for now. nil tag = untagged (free).
function S.tagRealm(tag, now, seasons, ov)
	tag = tonumber(tag)
	if not tag then
		return nil
	end
	if tag == 0 then
		return 0
	end
	return S.realm({season = tag, migrated = 0}, now, seasons, ov)
end

-- ---------------------------------------------------------------- joining
-- info = {level, row (existing chaos_season_players row or nil), items (depot + inbox items), party (bool),
--         house (bool)}; jc = cfg.join. Returns season, nil or nil, reason
function S.joinCheck(info, cfg, now, ov)
	local season = S.active(cfg.seasons, now, ov)
	if not season then
		local nxt = S.upcoming(cfg.seasons, now, ov)
		if nxt then
			return nil, string.format("%s has not started yet: it starts in %s.", nxt.name,
				S.formatDuration(S.times(nxt, ov) - now))
		end
		return nil, "No season is running."
	end
	if info.row then
		if info.row.season == season.id and (tonumber(info.row.migrated) or 0) == 0 then
			return nil, "This character is already a " .. season.name .. " character."
		end
		return nil, "This character already played a season. Make a new character to join."
	end
	local jc = cfg.join
	if (info.level or 0) > jc.maxLevel then
		return nil, string.format("Only a fresh character can join: level %d or lower (this character is level %d). " ..
			"Make a new character to join.", jc.maxLevel, info.level or 0)
	end
	if jc.requireEmptyDepot and (info.items or 0) > 0 then
		return nil, "Empty your depot, inbox and store inbox first: season characters start with nothing."
	end
	if info.party then
		return nil, "Leave your party first."
	end
	if info.house then
		return nil, "Characters that own a house cannot join a season."
	end
	return season, nil
end

-- ---------------------------------------------------------------- isolation
-- realms a and b (0 = standard). Exempt = staff (never blocked).
function S.tradeAllowed(a, b, exemptA, exemptB)
	if exemptA or exemptB then
		return true
	end
	return (a or 0) == (b or 0)
end

S.partyAllowed = S.tradeAllowed

-- m = {mover = realm, exempt = bool,
--      mail = realm of the mail receiver (nil = not a mail or unknown receiver),
--      houseFrom / houseTo = realm of the owner of the house the item comes from / goes to (nil = no house or no owner),
--      tags = {realms of the tagged item and of every container around it, source and destination; nil = untagged}}
-- -> true or false, reason key (cfg.isolation.messages)
function S.moveCheck(m)
	if m.exempt then
		return true
	end
	local me = m.mover or 0
	if m.mail ~= nil and m.mail ~= me then
		return false, "mail"
	end
	if m.houseFrom ~= nil and m.houseFrom ~= me then
		return false, "house"
	end
	if m.houseTo ~= nil and m.houseTo ~= me then
		return false, "house"
	end
	for _, t in ipairs(m.tags or {}) do
		if t ~= me then
			return false, "move"
		end
	end
	return true
end

-- the receiver of a letter / parcel label (the engine's rule: the first line of the text, trimmed), or nil
function S.mailReceiver(text)
	if type(text) ~= "string" then
		return nil
	end
	local line = text:match("^([^\r\n]*)") or ""
	line = line:gsub("^%s+", ""):gsub("%s+$", "")
	if line == "" then
		return nil
	end
	return line
end

-- ---------------------------------------------------------------- store coins (account-wide)
-- may a season character get this store offer part (not a bundle)? rules = cfg.store. Not listed = refused.
function S.storePartAllowed(offer, rules)
	if type(offer) ~= "table" or type(rules) ~= "table" or offer.seasonBlocked then
		return false
	end
	local kind = offer.kind
	if kind == "service" then
		return (rules.services or {})[offer.service] == true
	end
	if kind == "unlock" then
		local key = tostring(offer.unlock or "")
		if (rules.unlocks or {})[key] then
			return true
		end
		for _, prefix in ipairs(rules.unlockPrefixes or {}) do
			if key ~= "" and key:sub(1, #prefix) == prefix then
				return true
			end
		end
		return false
	end
	return (rules.kinds or {})[kind] == true
end

-- nil when a season character may get the offer; else the offer (or the bundle part) that is refused.
-- A bundle needs every part allowed (offer.resolved: the parts as shop.lua resolved them; else offer.parts tables)
function S.storeRefusal(offer, rules)
	if type(offer) ~= "table" then
		return {}
	end
	if offer.kind == "bundle" then
		local parts = offer.resolved or offer.parts or {}
		if #parts == 0 then
			return offer
		end
		for _, part in ipairs(parts) do
			if type(part) ~= "table" then
				return offer -- an unresolved part: cannot tell
			end
			if not S.storePartAllowed(part, rules) then
				return part
			end
		end
		return nil
	end
	if S.storePartAllowed(offer, rules) then
		return nil
	end
	return offer
end

-- the store's refusal text for a character of this realm (0 = standard: nil), or nil when the offer is allowed.
-- gift: bought by someone else for that character (name = the receiver)
function S.storeText(realm, offer, rules, gift, name)
	if (tonumber(realm) or 0) == 0 or type(rules) ~= "table" or not S.storeRefusal(offer, rules) then
		return nil
	end
	if gift then
		return string.format(rules.giftMessage or "%s is a season character.", tostring(name or "That character"))
	end
	return string.format(rules.message or "%s is not for season characters.", tostring(offer.name or "This offer"))
end

-- a season pass reward claimed by a character of this realm (0 = standard): true or false.
-- rules = cfg.passItems: item rewards (gold, potions) only by standard characters while the season runs
function S.passClaimAllowed(reward, realm, rules)
	if (tonumber(realm) or 0) == 0 or type(reward) ~= "table" then
		return true
	end
	if reward.kind == "item" then
		return type(rules) == "table" and rules.seasonCharacters == true
	end
	return true
end

-- a market action of a character of this realm in this currency ("gold" | "coins"): true or false.
-- rules = cfg.market: the season markets trade for gold only unless rules.coins
function S.marketCurrencyAllowed(realm, currency, rules)
	if (tonumber(realm) or 0) == 0 or currency ~= "coins" then
		return true
	end
	return type(rules) == "table" and rules.coins == true
end

-- ---------------------------------------------------------------- reward track
-- one leaderboard record into a season stat. mode "add" | "max" | "count"
function S.mergeStat(mode, old, value)
	old = tonumber(old) or 0
	value = math.floor(tonumber(value) or 0)
	if mode == "max" then
		return math.max(old, value)
	elseif mode == "count" then
		return old + 1
	end
	return old + math.max(0, value)
end

-- whether a milestone is offered (its `requires` global exists). has(name) -> bool
local function offered(m, has)
	return not m.requires or (has and has(m.requires)) and true or false
end

-- milestones of `track` reached by stats ({[stat] = value}) and not in `reached` ({[key] = true}) -> list
function S.milestonesDue(track, stats, reached, has)
	local out = {}
	for _, m in ipairs(track or {}) do
		if offered(m, has) and not (reached and reached[m.key]) and (tonumber(stats[m.stat]) or 0) >= m.value then
			out[#out + 1] = m
		end
	end
	return out
end

local function rewardText(r)
	if r.kind == "title" then
		return "Title: " .. r.title
	end
	return r.name or r.kind
end
S.rewardText = rewardText

-- the window's track: {key, name, stat, value, progress, reward, kind, unlocked, by, at}
-- reached = {[key] = {by = name, at = unix}} (account-wide)
function S.trackView(track, stats, reached, has)
	local out = {}
	for _, m in ipairs(track or {}) do
		if offered(m, has) then
			local r = reached and reached[m.key]
			out[#out + 1] = {key = m.key, name = m.name, stat = m.stat, value = m.value,
				progress = math.min(m.value, tonumber(stats and stats[m.stat]) or 0), reward = rewardText(m.reward),
				kind = m.reward.kind, unlocked = r and true or false, by = r and r.by or nil, at = r and r.at or nil}
		end
	end
	return out
end

-- look type and addons for a character of this sex (outfit / addon rewards), or nil
function S.rewardLook(reward, female)
	if reward.kind ~= "outfit" and reward.kind ~= "addon" then
		return nil
	end
	local look = female and reward.female or reward.male
	return look, reward.kind == "addon" and (reward.addons or 3) or 0
end

-- ---------------------------------------------------------------- migration
-- a season character is migrated (becomes standard) once its season has ended; idempotent: never twice
function S.migrationDue(row, now, seasons, ov)
	if not row or (tonumber(row.migrated) or 0) > 0 then
		return false
	end
	local s = S.byId(seasons, row.season)
	if not s then
		return true -- a season removed from the config: its characters are standard again
	end
	return S.status(s, now, ov) == "ended"
end

function S.migrationPlan(rows, now, seasons, ov)
	local out = {}
	for _, r in ipairs(rows or {}) do
		if S.migrationDue(r, now, seasons, ov) then
			out[#out + 1] = r
		end
	end
	return out
end

-- ---------------------------------------------------------------- uniques
-- uniqueSeason: the `season` field of a ChaosUniqueItems entry (nil = a normal unique). ownerRealm: the realm of
-- the player the drop is for (nil = unknown: rifts, goblins, ... without an owner).
-- Before its season: drops for nobody. During: only for that season's characters. After: for everyone.
function S.uniqueAllowed(uniqueSeason, ownerRealm, now, seasons, ov)
	if not uniqueSeason then
		return true
	end
	local id = uniqueSeason == true and 1 or tonumber(uniqueSeason)
	local s = S.byId(seasons, id)
	if not s then
		return true
	end
	local st = S.status(s, now, ov)
	if st == "ended" then
		return true
	end
	if st == "upcoming" then
		return false
	end
	return ownerRealm == s.id
end

-- ---------------------------------------------------------------- look text
-- realm row of the looked-at character -> line, or nil
function S.lookLine(row, now, seasons, ov, pronoun)
	if not row then
		return nil
	end
	local s = S.byId(seasons, row.season)
	if not s then
		return nil
	end
	pronoun = pronoun or "He"
	local verb = pronoun == "You" and "are" or "is"
	if S.realm(row, now, seasons, ov) == s.id then
		return string.format("%s %s a %s character %s.", pronoun, verb, s.name, s.tag or "")
	end
	return string.format("%s %s a veteran of %s.", pronoun, verb, s.name)
end

return S
