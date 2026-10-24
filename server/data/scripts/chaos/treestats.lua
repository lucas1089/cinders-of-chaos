-- treestats.lua: passive tree pick statistics for the beta (server/README.md "Passive tree pick statistics").
-- Staff only. On demand, one query over the saved trees (the active preset of every character, no per-allocation hook):
--   /treestats                         characters with a saved tree per class line and level band
--   /treestats <class> [band] [n]      the n most taken nodes (default 10) and the never-taken ones of that line and band
--                                      (class: a line or any class of it, "ninja" = the Thief line; band: "300-499",
--                                      "1000+", a level such as "350", or "all", the default)
--   /treestats export                  every line, band and node as counts to data/chaos_tree_picks_<date>.csv
-- Counts only: no character name, id or account in any output. Staff test characters (group >= staffGroup) are left
-- out; a line and band with fewer than minCharacters characters is not written to the CSV.
-- Rules: treestats_core.lua, numbers: treestats_config.lua, tests: server/tests/treestats_test.lua.

if not (Chaos and Chaos.t) then
	if not Chaos then
		dofile("data/scripts/chaos/chaos_constants.lua")
	end
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosTreeStatsCore then
	dofile("data/scripts/chaos/treestats_core.lua")
end
ChaosTreeStatsConfig = ChaosTreeStatsConfig or dofile("data/scripts/chaos/treestats_config.lua")

ChaosTreeStats = ChaosTreeStats or {}
local TS = ChaosTreeStats
local S = ChaosTreeStatsCore
local function cfg()
	return ChaosTreeStatsConfig
end

-- the class lines in a fixed order and the classes of each ({[line key] = {class keys}}), from Chaos.classes
function TS.lines()
	local c = Chaos.classes
	local keyOf = {}
	for key, id in pairs(c.ids) do
		keyOf[id] = key
	end
	local lines, classes = {}, {}
	local bases = {}
	for id, base in pairs(c.baseOf) do
		local line = keyOf[base]
		if line and keyOf[id] then
			if not classes[line] then
				classes[line] = {}
				bases[#bases + 1] = {id = base, key = line}
			end
			table.insert(classes[line], keyOf[id])
		end
	end
	table.sort(bases, function(a, b) return a.id < b.id end)
	for _, b in ipairs(bases) do
		lines[#lines + 1] = b.key
		table.sort(classes[b.key])
	end
	local lineOfVoc = {}
	for id, base in pairs(c.baseOf) do
		lineOfVoc[id] = keyOf[base]
	end
	return lines, classes, lineOfVoc
end

local function tree()
	local T = ChaosPassiveTree and ChaosPassiveTree.internal
	if T and T.getTree then
		return T.getTree()
	end
	return Chaos.load and Chaos.load("passivetree_data.lua") or dofile("data/scripts/chaos/passivetree_data.lua")
end

-- the saved trees (one row per preset; the core keeps each character's active one)
function TS.rows()
	return Chaos.select("SELECT `t`.`player_id` AS `player`, `t`.`preset` AS `preset`, `p`.`vocation` AS `vocation`, " ..
		"`p`.`level` AS `level`, `p`.`group_id` AS `grp`, `t`.`nodes` AS `nodes` FROM `" .. Chaos.tables.passiveTree ..
		"` AS `t` INNER JOIN `players` AS `p` ON `p`.`id` = `t`.`player_id` WHERE `p`.`deletion` = 0",
		{{"player", "n"}, {"preset", "n"}, {"vocation", "n"}, {"level", "n"}, {"grp", "n"}, {"nodes", "s"}})
end

-- stats, tree, ctx for the reports (rows: TS.rows() unless given, for the tests)
function TS.collect(rows)
	local lines, classes, lineOfVoc = TS.lines()
	local t = tree()
	for _, r in ipairs(rows) do
		r.group = r.group or r.grp
	end
	local ctx = {tree = t, bands = cfg().bands, staffGroup = cfg().staffGroup, minCharacters = cfg().minCharacters,
		lines = lines, lineClasses = classes, lineOf = function(voc) return lineOfVoc[voc] end}
	return S.aggregate(rows, ctx), t, ctx
end

-- a line key from a word: the line itself or one of its classes
local function lineFor(word, classes)
	for line, list in pairs(classes) do
		if word == line then
			return line
		end
		for _, k in ipairs(list) do
			if word == k then
				return line
			end
		end
	end
	return nil
end

-- the answer of /treestats <param> as text lines (rows: for the tests)
function TS.command(param, rows)
	local words = {}
	for w in tostring(param or ""):lower():gmatch("[^%s,]+") do
		words[#words + 1] = w
	end
	local stats, t, ctx = TS.collect(rows or TS.rows())
	if words[1] == "export" then
		local text, written, skipped = S.csv(stats, t, ctx)
		local path = string.format(cfg().csvPath, os.date("%Y%m%d-%H%M"))
		local f = io.open(path, "w")
		if not f then
			return {"Could not write " .. path .. "."}
		end
		f:write(text)
		f:close()
		local out = {string.format("Written %s: %d rows (counts only).", path, written)}
		if #skipped > 0 then
			out[#out + 1] = string.format("Left out (fewer than %d characters): %s.", cfg().minCharacters, table.concat(skipped, ", "))
		end
		return out, path, text
	end
	if #words == 0 then
		local out = {"Characters with a saved tree (staff left out), per level band:"}
		local labels = S.bandLabels(ctx.bands)
		for _, line in ipairs(ctx.lines) do
			local parts = {}
			for _, band in ipairs(labels) do
				local e = stats[line] and stats[line][band]
				parts[#parts + 1] = band .. " " .. (e and e.characters or 0)
			end
			out[#out + 1] = line .. ": " .. table.concat(parts, ", ")
		end
		out[#out + 1] = "Usage: /treestats <class> [band] [n] | /treestats export"
		return out
	end
	local line = lineFor(words[1], ctx.lineClasses)
	if not line then
		return {"Unknown class '" .. words[1] .. "'. Lines: " .. table.concat(ctx.lines, ", ") .. "."}
	end
	local band, n = S.ALL, cfg().top
	for i = 2, #words do
		local w = words[i]
		if w == S.ALL or w:find("[%-%+]") then
			band = w
		elseif tonumber(w) and i == 2 and tonumber(w) > cfg().maxTop then
			band = S.bandOf(tonumber(w), ctx.bands) or band
		elseif tonumber(w) then
			n = math.max(1, math.min(cfg().maxTop, math.floor(tonumber(w))))
		end
	end
	local known = false
	for _, label in ipairs(S.bandLabels(ctx.bands)) do
		known = known or label == band
	end
	if not known then
		return {"Unknown band '" .. band .. "'. Bands: " .. table.concat(S.bandLabels(ctx.bands), ", ") .. "."}
	end
	return S.report(stats, t, ctx, line, band, n, cfg().neverListed)
end

local talk = TalkAction("/treestats")
function talk.onSay(player, words, param)
	local allowed, staff = Chaos.staffCommand(player, words, param, false)
	if not allowed then
		return not staff
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "treestats", cfg().rateMs) then
		player:sendCancelMessage(Chaos.t(player, "Wait a moment: /treestats reads every saved tree."))
		return false
	end
	local ok, out = pcall(TS.command, param)
	if not ok then
		print("[ChaosTreeStats] " .. tostring(out))
		player:sendTextMessage(MESSAGE_INFO_DESCR, "/treestats failed (see the server console).")
		return false
	end
	local text = table.concat(out, "\n")
	if player.popupFYI and #out > 3 then
		player:popupFYI(text)
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	end
	return false
end
talk:separator(" ")
talk:register()
