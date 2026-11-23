-- Run from the server/ folder: luajit tests/cosmetics_removal_test.lua (and lua5.3; CI runs both)
-- The Victory Emotes removal (O564, server/README.md "Victory emotes removed"): the retired list of
-- cosmetics_config.lua against the refund file server/sql/chaos_zz_emote_removal.sql, and nothing of the emotes left
-- in the live config, the store, the Pact shelf or the client.
local n = 0
local function eq(a, b, msg)
	n = n + 1
	if a ~= b then
		error(string.format("FAIL %s: got %s, want %s", msg, tostring(a), tostring(b)), 2)
	end
end
local function read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local cfg = dofile("data/scripts/chaos/cosmetics_config.lua")
local pact = dofile("data/scripts/chaos/pact_config.lua")
local sql = read("sql/chaos_zz_emote_removal.sql")
eq(sql ~= nil, true, "the refund file exists")

-- the retired list: five emotes, ids 801-805, never reused, list prices 150-250
eq(#cfg.retired, 10, "five retired emotes (O564) and five retired kill effects (O715)")
local live = {}
for _, c in ipairs(cfg.cosmetics) do
	live[c.key], live["id" .. c.id] = true, true
	eq(c.kind ~= "emote", true, c.key .. " is not an emote")
end
for _, k in ipairs(cfg.kinds) do
	eq(k.key ~= "emote", true, "no emote kind")
end
eq(cfg.storage.emote, nil, "the emote storage is not read any more (7102004 stays reserved)")
local emotes, kills = {}, {}
for _, r in ipairs(cfg.retired) do
	if r.kind == "killfx" then
		kills[#kills + 1] = r
	else
		emotes[#emotes + 1] = r
	end
end
eq(#emotes, 5, "five emotes") eq(#kills, 5, "five kill effects")
for _, r in ipairs(emotes) do
	eq(r.kind, "emote", r.key .. " kind")
	eq(live[r.key], nil, r.key .. " key not live") eq(live["id" .. r.id], nil, r.key .. " id not live")
	eq(r.price >= 150 and r.price <= 250, true, r.key .. " list price")
	-- the file names the key and its price in the list of the refund join
	local price = sql:match("SELECT ''" .. r.key .. "'' AS `k`, (%d+) AS `price`") or sql:match("UNION ALL SELECT ''" .. r.key .. "'', (%d+),")
	eq(tonumber(price), r.price, r.key .. " price in the SQL")
	eq(select(2, sql:gsub("''" .. r.key .. "''", "")) >= 2, true, r.key .. " is refunded and deleted")
end
eq(select(2, sql:gsub("''emote_[a-z]+''", "")), 10, "the SQL names no other emote (5 in the join, 5 in the delete)")
eq(sql:find("7102004", 1, true) ~= nil, true, "the chosen emote storage is cleared")
eq(sql:find("100000", 1, true) ~= nil and pact.marks.maxBalance, 100000, "the Marks cap of the Pact")
eq(sql:find("START TRANSACTION", 1, true) ~= nil and sql:find("COMMIT;", 1, true) ~= nil, true, "one transaction")

-- the kill effects of the first generation (O715): the retired list against the refund file, nothing of them live
local ksql = read("sql/chaos_zz_killfx_removal.sql")
eq(ksql ~= nil, true, "the kill effect refund file exists")
for _, r in ipairs(kills) do
	eq(live[r.key], nil, r.key .. " key not live") eq(live["id" .. r.id], nil, r.key .. " id not live")
	eq(r.price, 200, r.key .. " list price")
	eq(tonumber(ksql:match("SELECT ''" .. r.key .. "'' AS `k`, (%d+) AS `price`") or ksql:match("UNION ALL SELECT ''" .. r.key .. "'', (%d+),")), r.price,
		r.key .. " price in the SQL")
	eq(select(2, ksql:gsub("''" .. r.key .. "''", "")) >= 2, true, r.key .. " is refunded and deleted")
	eq(ksql:find("AND `value` IN (101, 102, 103, 104, 105)", 1, true) ~= nil and ksql:find(r.id .. ",", 1, true) ~= nil or r.id == 105, true, r.key .. " chosen id cleared")
end
eq(select(2, ksql:gsub("''kill_[a-z]+''", "")), 11, "the SQL names no other kill effect (5 + 5 + the Windswept stand-in)")
eq(ksql:find("7100940", 1, true) ~= nil and cfg.storage.killfx, 7100940, "the chosen kill effect storage is cleared")
eq(ksql:find("START TRANSACTION", 1, true) ~= nil and ksql:find("COMMIT;", 1, true) ~= nil, true, "one transaction")
eq(live.kill_windswept, true, "the stand-in for Mentor Marks buyers is a live kill effect")
local mentor = read("data/scripts/chaos/mentor_config.lua")
eq(mentor:find("kill_soulspark", 1, true), nil, "the mentor shop sells no retired kill effect")
for _, it in ipairs(pact.marks.monthly) do
	eq(it.key:find("^kill_") == nil or live[it.key] == true, true, "monthly " .. it.key .. " is live")
end
for _, it in ipairs(pact.marks.shelf) do
	eq(live[it.key] == true, true, "shelf " .. it.key .. " is live")
end
local harvest = dofile("data/scripts/chaos/harvest_event_config.lua")
for _, e in ipairs(harvest.charmPool) do
	if e.kind == "cosmetic" then
		eq(live[e.key] == true, true, "charm pool " .. e.key .. " is live")
	end
end

-- the Pact shelf and its monthly slot name no emote
for _, it in ipairs(pact.marks.monthly) do
	eq(it.key:find("^emote_"), nil, "monthly " .. it.key)
end
for _, it in ipairs(pact.marks.shelf) do
	eq(it.key:find("^emote_"), nil, "shelf " .. it.key)
end

-- the store sells no emote
local store = dofile("data/scripts/chaos/cosmetics_store.lua")
eq(pcall(store, "emote"), false, "no emote store category")
local shop = read("data/scripts/chaos/shop_config.lua")
eq(shop:find("Victory Emotes", 1, true), nil, "the store config has no Victory Emotes")

-- the client lists no emote tab
local logic = read("../client/overlay/modules/game_cosmetics/cosmeticslogic.lua")
eq(logic ~= nil and logic:find("key = 'emote'", 1, true) == nil, true, "the client has no emote tab")

print(string.format("cosmetics_removal_test: %d checks OK", n))
