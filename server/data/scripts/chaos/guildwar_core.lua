-- In-game guild wars: the pure part (no engine calls), shared by guildwar.lua and tests/guildwar_test.lua.
-- Numbers: guildwar_config.lua. Overview: server/README.md "Guild wars in game". Lua 5.1 / LuaJIT and Lua 5.3.
--
-- A war row (chaos_guildwar) as a table: {id, warId (guild_wars.id, 0 until accepted), guild1 (declarer), guild2,
--   name1, name2, realm, fragLimit, hours, stake (per side), status, declaredAt, expiresAt, startedAt, endsAt, endedAt,
--   kills1, kills2, winner (guild id, 0 = draw), reason, escrow1, escrow2, payout, fee}
-- Statuses: pending (offered, the declarer's stake held) -> active (accepted, both stakes held) -> ended;
--   pending -> declined | cancelled | expired (the stake goes back).
--
--   C.terms(input, cfg)                 normalised {fragLimit, hours, stake} or nil, reason
--   C.declareError(info, cfg)           nil or why a declaration is refused
--   C.answerError(info, cfg)            nil or why an accept / decline / cancel / surrender is refused
--   C.side(war, gid)                    1 (declarer), 2 (the other guild) or nil
--   C.killVerdict(k, war, cfg)          counted (bool), reason: does a player kill count for the war
--   C.addKill(war, side)                one counted kill; returns true when the frag limit is reached
--   C.timeUp(war, now) / C.offerExpired(war, now)
--   C.outcome(war, reason, loserSide)   winner side (0 = draw) and the end reason
--   C.settle(war, side, cfg)            the gold of the end: {pay1, pay2, fee} (pay = to that guild's bank)
--   C.refund(war)                       the gold of a declined / cancelled / expired offer
--   C.gxpOf(war, side, reason, cfg)     guild XP of the winner
--   C.row(war, gid, now)                one war for the window (own side first)
--   C.termsText(war), C.scoreText(war, gid), C.money(n), C.durationText(s)

ChaosGuildWarCore = ChaosGuildWarCore or {}
local C = ChaosGuildWarCore

local floor = math.floor

-- the text in `lang` (ChaosI18n when it is loaded, English otherwise); guildwar.lua passes the language of the reader
local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

function C.money(n)
	n = floor(tonumber(n) or 0)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (n < 0 and "-" or "") .. out
end

function C.durationText(s)
	s = math.max(0, floor(tonumber(s) or 0))
	local d, h, m = floor(s / 86400), floor(s % 86400 / 3600), floor(s % 3600 / 60)
	if d > 0 then
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm", m)
end

local function inList(list, v)
	for _, x in ipairs(list or {}) do
		if x == v then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------- terms
-- input = {fragLimit, hours, stake} (from the client: numbers or strings). Only the listed frag limits and durations.
function C.terms(input, cfg)
	input = type(input) == "table" and input or {}
	local frag = floor(tonumber(input.fragLimit) or 0)
	local hours = floor(tonumber(input.hours) or 0)
	local stake = tonumber(input.stake) or 0
	if stake ~= stake or stake == math.huge then
		stake = -1
	end
	stake = floor(stake)
	if not inList(cfg.fragLimits, frag) then
		return nil, "Pick one of the frag limits."
	end
	if not inList(cfg.durations, hours) then
		return nil, "Pick one of the durations."
	end
	local s = cfg.stake
	if stake < 0 then
		return nil, "The stake cannot be negative."
	end
	if stake > 0 and stake < s.min then
		return nil, string.format("A stake is at least %s gold (or none).", C.money(s.min))
	end
	if stake > s.max then
		return nil, string.format("A stake is at most %s gold.", C.money(s.max))
	end
	return {fragLimit = frag, hours = hours, stake = stake}
end

-- ---------------------------------------------------------------- declaring
-- info = {enabled, guildId, rank, targetId, targetExists, realm, targetRealm, members, targetMembers, wars, targetWars,
--   pairBusy (a pending or active war between the two), pairCooldown (seconds until a new war of the pair is allowed),
--   sameOwner, stake, bank, sinceLastDeclare (seconds; nil = never), seasonBank (a season character: no bank)}
function C.declareError(info, cfg)
	if not cfg.enabled or info.enabled == false then
		return "Guild wars are closed."
	end
	if not info.guildId or info.guildId == 0 then
		return "You are not in a guild."
	end
	if (info.rank or 0) < (cfg.rank or 2) then
		return "Only the guild leader or a vice-leader can declare war."
	end
	if not info.targetExists or not info.targetId then
		return "There is no guild of that name."
	end
	if info.targetId == info.guildId then
		return "Your guild cannot declare war on itself."
	end
	if (info.realm or 0) ~= (info.targetRealm or 0) then
		return "Wars are fought only within a realm: that guild belongs to another realm."
	end
	if cfg.sameOwnerBlocked and info.sameOwner then
		return "These two guilds are led from the same account or connection; they cannot fight each other."
	end
	if (info.members or 0) < (cfg.minMembers or 1) then
		return string.format("Your guild needs at least %d members to declare war.", cfg.minMembers)
	end
	if (info.targetMembers or 0) < (cfg.minMembers or 1) then
		return string.format("That guild has fewer than %d members.", cfg.minMembers)
	end
	if info.pairBusy then
		return "There is already an offer or a war between these guilds."
	end
	if (info.pairCooldown or 0) > 0 then
		return string.format("These guilds fought recently: a new war in %s.", C.durationText(info.pairCooldown))
	end
	if (info.wars or 0) >= (cfg.maxWars or 3) then
		return string.format("Your guild already has %d wars and offers.", cfg.maxWars)
	end
	if (info.targetWars or 0) >= (cfg.maxWars or 3) then
		return "That guild has as many wars and offers as it may."
	end
	if info.sinceLastDeclare and info.sinceLastDeclare < (cfg.declareCooldown or 0) then
		return "Your guild just declared a war. Wait a moment."
	end
	if (info.stake or 0) > 0 then
		if (info.rank or 0) < (cfg.stakeRank or 3) then
			return "Only the guild leader can put gold at stake."
		end
		if info.seasonBank then
			return "Season characters cannot use the guild bank while the season runs."
		end
		if (info.bank or 0) < info.stake then
			return string.format("The guild bank holds %s gold; the stake is %s.", C.money(info.bank or 0), C.money(info.stake))
		end
	end
	return nil
end

-- info = {action ("accept" | "decline" | "cancel" | "surrender"), guildId, rank, war, bank, wars, seasonBank, now}
function C.answerError(info, cfg)
	local w = info.war
	if not w then
		return "That war is not there any more."
	end
	if not info.guildId or info.guildId == 0 then
		return "You are not in a guild."
	end
	local side = C.side(w, info.guildId)
	if not side then
		return "Your guild is not part of that war."
	end
	if (info.rank or 0) < (cfg.rank or 2) then
		return "Only the guild leader or a vice-leader can do that."
	end
	local a = info.action
	if a == "accept" or a == "decline" then
		if w.status ~= "pending" then
			return "That offer is no longer open."
		end
		if side ~= 2 then
			return "Your guild made that offer; the other guild answers it."
		end
		if C.offerExpired(w, info.now or 0) then
			return "That offer expired."
		end
		if a == "accept" then
			if (info.wars or 0) > (cfg.maxWars or 3) then
				return string.format("Your guild already has %d wars.", cfg.maxWars)
			end
			if (w.stake or 0) > 0 then
				if (info.rank or 0) < (cfg.stakeRank or 3) then
					return "Only the guild leader can accept a war with gold at stake."
				end
				if info.seasonBank then
					return "Season characters cannot use the guild bank while the season runs."
				end
				if (info.bank or 0) < w.stake then
					return string.format("Your guild bank holds %s gold; the stake is %s.", C.money(info.bank or 0), C.money(w.stake))
				end
			end
		end
		return nil
	elseif a == "cancel" then
		if w.status ~= "pending" then
			return "That offer is no longer open."
		end
		if side ~= 1 then
			return "Only the guild that made the offer can take it back."
		end
		return nil
	elseif a == "surrender" then
		if w.status ~= "active" then
			return "That war is not running."
		end
		return nil
	end
	return "Unknown action."
end

function C.side(war, gid)
	if not war or not gid then
		return nil
	end
	if war.guild1 == gid then
		return 1
	elseif war.guild2 == gid then
		return 2
	end
	return nil
end

-- ---------------------------------------------------------------- kills
-- k = {killerGuild, victimGuild, killerAccount, victimAccount, killerIp, victimIp, killerLevel, victimLevel,
--   killerRealm, victimRealm, at, lastCounted (the time of the victim's last counted death in this war, or nil)}
-- Returns counted, reason. reason "ok" when it counts; else a short text for the war log.
function C.killVerdict(k, war, cfg)
	if not war or war.status ~= "active" then
		return false, "no war"
	end
	local ks, vs = C.side(war, k.killerGuild), C.side(war, k.victimGuild)
	if not ks or not vs or ks == vs then
		return false, "no war"
	end
	if C.timeUp(war, k.at or 0) then
		return false, "war over"
	end
	local r = cfg.kills or {}
	if r.sameAccount and k.killerAccount and k.killerAccount ~= 0 and k.killerAccount == k.victimAccount then
		return false, "same account"
	end
	if r.sameIp and k.killerIp and k.killerIp ~= 0 and k.killerIp == k.victimIp then
		return false, "same IP"
	end
	if r.realm and ((k.killerRealm or 0) ~= (war.realm or 0) or (k.victimRealm or 0) ~= (war.realm or 0)) then
		return false, "realm"
	end
	local vl, kl = tonumber(k.victimLevel) or 0, tonumber(k.killerLevel) or 0
	if vl < (r.minVictimLevel or 0) then
		return false, "low level"
	end
	if r.minLevelRatio and vl < kl * r.minLevelRatio then
		return false, "low level"
	end
	if k.lastCounted and r.sameVictimMinutes and (k.at or 0) - k.lastCounted < r.sameVictimMinutes * 60 then
		return false, "repeat"
	end
	return true, "ok"
end

function C.addKill(war, side)
	if side == 1 then
		war.kills1 = (war.kills1 or 0) + 1
	elseif side == 2 then
		war.kills2 = (war.kills2 or 0) + 1
	else
		return false
	end
	return (war.kills1 or 0) >= war.fragLimit or (war.kills2 or 0) >= war.fragLimit
end

function C.timeUp(war, now)
	return war.status == "active" and (war.endsAt or 0) > 0 and now >= war.endsAt
end

function C.offerExpired(war, now)
	return war.status == "pending" and (war.expiresAt or 0) > 0 and now >= war.expiresAt
end

-- ---------------------------------------------------------------- the end
-- reason: "limit" | "time" | "surrender" | "disband" | "staff" | "external"; loserSide: the side that surrendered or
-- disbanded. Returns the winner side (0 = draw) and the reason.
function C.outcome(war, reason, loserSide)
	if (reason == "surrender" or reason == "disband") and (loserSide == 1 or loserSide == 2) then
		return 3 - loserSide, reason
	end
	local k1, k2 = war.kills1 or 0, war.kills2 or 0
	if k1 > k2 then
		return 1, reason
	elseif k2 > k1 then
		return 2, reason
	end
	return 0, reason
end

-- the escrow of an ended war: the winner takes both stakes minus the fee (the sink); a draw gives each stake back.
-- pay1 + pay2 + fee == escrow1 + escrow2 always.
function C.settle(war, side, cfg)
	local e1, e2 = math.max(0, floor(war.escrow1 or 0)), math.max(0, floor(war.escrow2 or 0))
	if side ~= 1 and side ~= 2 then
		return {pay1 = e1, pay2 = e2, fee = 0}
	end
	local pot = e1 + e2
	local fee = floor(pot * ((cfg.stake and cfg.stake.feePercent) or 0) / 100)
	local out = {pay1 = 0, pay2 = 0, fee = fee}
	out["pay" .. side] = pot - fee
	return out
end

-- a declined / cancelled / expired offer: each side gets what it put in
function C.refund(war)
	return {pay1 = math.max(0, floor(war.escrow1 or 0)), pay2 = math.max(0, floor(war.escrow2 or 0)), fee = 0}
end

function C.gxpOf(war, side, reason, cfg)
	local g = cfg.gxp or {}
	if (side ~= 1 and side ~= 2) or (reason ~= "limit" and reason ~= "time") then
		return 0
	end
	if (war.kills1 or 0) + (war.kills2 or 0) < (g.minKills or 0) then
		return 0
	end
	return g.win or 0
end

-- ---------------------------------------------------------------- texts and rows
function C.termsText(war, lang)
	local parts = {T(lang, "first to %d kills", war.fragLimit or 0),
		T(lang, "%d hours", war.hours or 0)}
	if (war.stake or 0) > 0 then
		parts[#parts + 1] = T(lang, "%s gold at stake per side", C.money(war.stake))
	else
		parts[#parts + 1] = T(lang, "no stake")
	end
	return table.concat(parts, ", ")
end

-- "12 : 7" from the point of view of gid (own kills first); without gid the declarer first
function C.scoreText(war, gid)
	local k1, k2 = war.kills1 or 0, war.kills2 or 0
	if gid and war.guild2 == gid then
		return string.format("%d : %d", k2, k1)
	end
	return string.format("%d : %d", k1, k2)
end

local REASONS = {limit = "frag limit reached", time = "time is up", surrender = "surrender", disband = "a guild disbanded",
	staff = "ended by the staff", external = "ended outside the game"}

function C.reasonText(reason, lang)
	local text = REASONS[reason]
	return text and T(lang, text) or tostring(reason or "")
end

-- one war for the window, from gid's point of view (gid nil: the declarer's)
function C.row(war, gid, now, lang)
	local side = C.side(war, gid) or 1
	local own, other = side == 1 and war.name1 or war.name2, side == 1 and war.name2 or war.name1
	local r = {id = war.id, status = war.status, own = own, enemy = other, side = side, mine = C.side(war, gid) ~= nil,
		fragLimit = war.fragLimit, hours = war.hours, stake = war.stake or 0, terms = C.termsText(war, lang),
		ownKills = side == 1 and (war.kills1 or 0) or (war.kills2 or 0),
		enemyKills = side == 1 and (war.kills2 or 0) or (war.kills1 or 0),
		score = C.scoreText(war, side == 1 and war.guild1 or war.guild2)}
	if war.status == "pending" then
		r.left = math.max(0, (war.expiresAt or 0) - now)
		r.incoming = side == 2
	elseif war.status == "active" then
		r.left = math.max(0, (war.endsAt or 0) - now)
	else
		r.endedAt = war.endedAt or 0
		r.reason = C.reasonText(war.reason, lang)
		if war.status == "ended" then
			if (war.winner or 0) == 0 then
				r.result = "draw"
			elseif war.winner == (side == 1 and war.guild1 or war.guild2) then
				r.result = "won"
			else
				r.result = "lost"
			end
			r.payout = war.payout or 0
		else
			r.result = war.status
		end
	end
	return r
end

return C
