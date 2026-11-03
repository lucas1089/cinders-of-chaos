-- The Weekly Challenge (O390): one queue dungeon whose layout comes from the ISO week, the same for everyone; the
-- fastest clears per class on two weekly leaderboard boards; class rewards and a Discord post at the week's end.
-- Numbers: weekly_challenge_config.lua. Pure logic: weekly_challenge_core.lua (tests/weekly_challenge_test.lua).
-- Overview: server/README.md "The Weekly Challenge (O390)".
--
-- How it plugs in (no opcode, no storage of its own):
--   areagen.lua   at startup asks ChaosWeeklyChallenge.areaFor(cfg, A, opts) for the week's area (a copy of the Hollow
--                 Vault's with the week's seed and theme) and builds it like its other areas; registerDungeon gives
--                 the dungeon system the hooks below (fixed difficulty, the entry check, the clear, the window line)
--   dungeons.lua  queue: the difficulty is the challenge's own; entry: refused when the layout is not this week's;
--                 a won run calls onClear per finisher with the run time and party size
--   leaderboard   challenge_solo / challenge_party (leaderboard_config.lua): mode "min", time, class tabs, the title of
--                 the overall top 3; ChaosLeaderboard.onReset -> onWeekEnd: Conquest Tokens for the top 3 of every
--                 class (conquest.lua grantGuid) and the Discord row "weekly_challenge" (discord.lua)
-- The client: game_dungeons shows the challenge with its week and theme (dungeon payload `weekly`), the boards are in
-- game_leaderboard and on the website's Leaderboards page (both read leaderboard_config.lua).
-- Staff: /challenge (status: the built week, seed and theme; the current week).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/weekly_challenge_core.lua")
ChaosWeeklyChallengeConfig = dofile("data/scripts/chaos/weekly_challenge_config.lua")

ChaosWeeklyChallenge = ChaosWeeklyChallenge or {}
local WC = ChaosWeeklyChallenge
local W = ChaosWeeklyChallengeCore

local function C()
	return ChaosWeeklyChallengeConfig
end

local function log(text)
	print("[Chaos weekly challenge] " .. text)
end

-- the leaderboard week key now (YYYYMMDD of its Monday; the boards' reset hour)
function WC.weekNow()
	local LB = ChaosLeaderboard
	local hour = Chaos.leaderboardConfig and Chaos.leaderboardConfig.resetHour or 6
	if LB and LB.week then
		return LB.week(LB.now and LB.now() or os.time(), hour)
	end
	if ChaosBounty and ChaosBounty.week then
		return ChaosBounty.week(os.time(), {rollHour = hour})
	end
	return nil
end

-- ---------------------------------------------------------------- the area (areagen.lua at startup)
-- -> the week's area definition, or nil (off, no base, no valid seed). A = ChaosAreaGenCore.
function WC.areaFor(agCfg, A, opts)
	local cfg = C()
	if not cfg.enabled then
		return nil
	end
	local base
	for _, def in ipairs(agCfg.areas or {}) do
		if def.id == cfg.base then
			base = def
		end
	end
	local week = WC.weekNow()
	if not base or not week then
		log("not built: no base area " .. tostring(cfg.base) .. " or no week")
		return nil
	end
	local y, w = W.weekOf(week)
	for try = 0, math.max(1, cfg.seedTries or 1) - 1 do
		local def = W.areaDef(cfg, base, {isoYear = y, isoWeek = w, try = try})
		local okGen, model = pcall(A.generate, agCfg, def, opts)
		local problems = okGen and A.validate(agCfg, model, opts) or {tostring(model)}
		if #problems == 0 then
			problems = W.layoutProblems(cfg, model)
		end
		if #problems == 0 then
			def.weekly.week = week
			return def
		end
		log(string.format("%s seed %d: %s (next seed)", def.weekly.label, def.seed, tostring(problems[1])))
	end
	log("not built: no seed of this week gave a valid layout")
	return nil
end

-- areagen.lua: the area stands (entry = {def, model, ...})
function WC.onBuilt(entry)
	local wk = entry.def.weekly
	WC.built = {week = wk.week, label = wk.label, theme = wk.theme, seed = wk.seed, try = wk.try}
	log(string.format("%s built for %s: theme %s, seed %d", entry.def.name, wk.label, wk.theme, wk.seed))
end

-- ---------------------------------------------------------------- the dungeon system's hooks
-- the reason the queue refuses, or nil
function WC.entryProblem(player)
	local why = W.entryProblem(WC.built and WC.built.week, WC.weekNow())
	return why and Chaos.t(player, why) or nil
end

-- the window's line (dungeons.lua dungeonPayload `weekly`)
function WC.info(player)
	local b = WC.built
	if not b then
		return nil
	end
	local LB = ChaosLeaderboard
	local now = LB and LB.now and LB.now() or os.time()
	local resetIn = LB and LB.nextReset and Chaos.leaderboardConfig
		and math.max(0, LB.nextReset(now, Chaos.leaderboardConfig.resetHour) - now) or nil
	return {label = b.label, theme = b.theme, current = b.week == WC.weekNow(), resetIn = resetIn,
		boards = {C().boards.solo, C().boards.party}}
end

-- a won run, per finisher (dungeons.lua endRun -> the area's onClear): info = {ms, size, difficulty, deaths}
function WC.onClear(player, info)
	local b = WC.built
	if not (b and b.week == WC.weekNow() and ChaosLeaderboard and ChaosLeaderboard.record) then
		return -- a run that crossed the week's end: the layout belongs to the week that ended
	end
	local secs = W.seconds(info and info.ms)
	local board = W.boardOf(C(), info and info.size)
	local e = ChaosLeaderboard.record(board, player, secs)
	local best = e and e.value or secs
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
		"Weekly Challenge %s cleared in %s (%s). Your best this week: %s. See Leaderboards.", b.label, W.clock(secs),
		Chaos.t(player, (info and info.size or 1) > 1 and "party" or "solo"), W.clock(best)))
end

-- ---------------------------------------------------------------- the week's end (leaderboard reset)
function WC.onWeekEnd(prev, ranked)
	local cfg = C()
	local LB = ChaosLeaderboard
	if not cfg.enabled or not (LB and LB.classGroups and LB.filterClass) then
		return
	end
	local groups = LB.classGroups()
	local n = math.max(cfg.rewardTop or 3, cfg.discordTop or 3)
	local tops = {}
	for _, key in ipairs({cfg.boards.solo, cfg.boards.party}) do
		tops[#tops + 1] = {board = key, groups = W.classTop(ranked[key] or {}, groups, n, LB.filterClass)}
	end
	local y, w = W.weekOf(prev)
	local label = W.label(y, w)
	local given = 0
	for _, a in ipairs(W.awards(cfg, tops)) do
		if ChaosConquest and ChaosConquest.grantGuid then
			given = given + ChaosConquest.grantGuid(a.guid, a.tokens, "weekly_challenge",
				string.format("Weekly Challenge %s", label))
		end
	end
	local theme = WC.built and WC.built.label == label and WC.built.theme
		or (W.theme(cfg, W.seed(cfg, y, w, 0)) or {}).name or "?"
	if ChaosDiscord and ChaosDiscord.queue and ChaosDiscordCore and ChaosDiscordConfig then
		local sections = W.discordSections(cfg, tops, {[cfg.boards.solo] = "Solo", [cfg.boards.party] = "Party"})
		ChaosDiscord.queue(ChaosDiscordCore.weeklyChallenge(ChaosDiscordConfig, label, theme, sections))
	end
	log(string.format("week %s ended: %d Conquest Tokens to the class top %d", label, given, cfg.rewardTop or 3))
end

local function hook()
	if ChaosLeaderboard and ChaosLeaderboard.onReset then
		ChaosLeaderboard.onReset(function(prev, ranked)
			WC.onWeekEnd(prev, ranked)
		end, "weekly_challenge")
		return true
	end
	return false
end

if not hook() then
	local startup = GlobalEvent("ChaosWeeklyChallengeStartup")
	function startup.onStartup()
		if not hook() then
			log("the leaderboard is not loaded: no rewards and no Discord post at the week's end")
		end
		return true
	end
	startup:register()
end

-- ---------------------------------------------------------------- staff
local talk = TalkAction("/challenge")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false
	end
	if not Chaos.staffCommand(player, words, param, false) then
		return false
	end
	local b = WC.built
	local y, w = W.weekOf(WC.weekNow() or 0)
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Weekly Challenge: built %s (theme %s, seed %s, try %s); " ..
		"this week %s.", b and b.label or "nothing", b and b.theme or "-", b and tostring(b.seed) or "-",
		b and tostring(b.try) or "-", W.label(y, w)))
	return false
end
talk:separator(" ")
talk:register()
