-- Pure rules of the boss passive points (bosspoints.lua; settings bosspoints_config.lua; tests:
-- server/tests/bosspoints_test.lua). No engine calls here.
--
--   K.build(cfg)                         -> index {list (by id), byName (lower case type name -> boss), total, problems}
--   K.isBoss(index, typeName)            -> the boss entry or nil
--   K.count(index, has)                  -> points owned; has(id) -> true when the flag of that boss is set
--   K.killers(damageIds, resolve, extra, idOf) -> players of the damage map (resolve(id) -> player or nil) plus
--                                           `extra` (the last hit, the most damage), each once, in a stable order
--   K.credit(killers, membersOf, posOf, range, idOf) -> the bounty board's party credit (bounty_core.lua): the
--                                           killers and their party members within range, each once
--   K.retroIds(index, sources)           -> ids of the bosses an older kill shows (sources: bestiary = {name = kills},
--                                           stats = {stat = value}, storage = function(key) -> value)
--   K.state(index, has)                  -> {got, total, label, bosses = [{id, name, label, done}]} for the window
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

if not ChaosBounty or not ChaosBounty.credit then
	dofile("data/scripts/chaos/bounty_core.lua")
end

ChaosBossPointsCore = ChaosBossPointsCore or {}
local K = ChaosBossPointsCore
K.credit = ChaosBounty.credit

function K.build(cfg)
	local index = {list = {}, byName = {}, byId = {}, total = 0, problems = {}}
	local maxId = cfg and cfg.maxId or 19
	for _, boss in ipairs(cfg and cfg.bosses or {}) do
		local id, name = tonumber(boss.id), type(boss.name) == "string" and boss.name:lower() or nil
		if not id or id < 1 or id > maxId or id ~= math.floor(id) then
			index.problems[#index.problems + 1] = "boss " .. tostring(boss.name) .. ": id must be 1.." .. maxId
		elseif index.byId[id] then
			index.problems[#index.problems + 1] = "boss id " .. id .. " is used twice"
		elseif not name or name == "" then
			index.problems[#index.problems + 1] = "boss id " .. id .. " has no name"
		elseif index.byName[name] then
			index.problems[#index.problems + 1] = "boss " .. boss.name .. " is listed twice"
		else
			local entry = {id = id, name = boss.name, key = name, label = boss.label or boss.name, retro = boss.retro or {}}
			index.byId[id] = entry
			index.byName[name] = entry
			index.list[#index.list + 1] = entry
		end
	end
	table.sort(index.list, function(a, b) return a.id < b.id end)
	index.total = #index.list
	return index
end

function K.isBoss(index, typeName)
	if type(typeName) ~= "string" then
		return nil
	end
	return index.byName[typeName:lower()]
end

function K.count(index, has)
	local n = 0
	for _, boss in ipairs(index.list) do
		if has(boss.id) then
			n = n + 1
		end
	end
	return n
end

-- damageIds: the keys of creature:getDamageMap() (any order); resolve(id) -> the player (a summon resolved to its
-- master) or nil; extra: more players (last hit, most damage). Sorted by id so the result does not depend on pairs().
function K.killers(damageIds, resolve, extra, idOf)
	local out, seen = {}, {}
	local ids = {}
	for _, id in ipairs(damageIds or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	local function add(p)
		if p then
			local id = idOf(p)
			if not seen[id] then
				seen[id] = true
				out[#out + 1] = p
			end
		end
	end
	for _, id in ipairs(ids) do
		add(resolve(id))
	end
	for _, p in ipairs(extra or {}) do
		add(p)
	end
	return out
end

function K.retroIds(index, sources)
	sources = sources or {}
	local out = {}
	for _, boss in ipairs(index.list) do
		local r, found = boss.retro, false
		if r.bestiary and sources.bestiary and (tonumber(sources.bestiary[boss.key]) or 0) > 0 then
			found = true
		end
		if not found and r.stat and sources.stats and (tonumber(sources.stats[r.stat]) or 0) > 0 then
			found = true
		end
		if not found and type(r.storage) == "table" and sources.storage then
			local v = tonumber(sources.storage(r.storage.key)) or -1
			if v >= (r.storage.atLeast or 1) then
				found = true
			end
		end
		if found then
			out[#out + 1] = boss.id
		end
	end
	return out
end

function K.label(got, total)
	return string.format("Boss points %d/%d", got, total)
end

function K.state(index, has)
	local bosses, got = {}, 0
	for _, boss in ipairs(index.list) do
		local done = has(boss.id) and true or false
		if done then
			got = got + 1
		end
		bosses[#bosses + 1] = {id = boss.id, name = boss.name, label = boss.label, done = done}
	end
	return {got = got, total = index.total, label = K.label(got, index.total), bosses = bosses}
end

return K
