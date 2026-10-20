-- Tools: the pair 30 gallery for the owner (PLAN_PAIR30 6.3). Admin only: the panel's Tools > Pair 30 gallery and the
-- staff talkaction /pack30gallery run the same function, ChaosPack30Gallery.run(player, what, arg).
--   items <block|from-to> | groups | grounds | anim | looks <from-to> | schemes <look> | fx <from-to> | missiles
--   | wear <look> [scheme] | clear
-- Items, groups and anim stand in rows east of the admin; grounds replace the ground under a strip of tiles (never a
-- protection zone or house tile) and `clear` puts the old ground ids back; looks are "Look Model" monsters
-- (pack30_gallery.xml) with setOutfit. Everything placed is remembered per admin, `clear` removes it, and it clears
-- itself after 30 minutes. At most 150 objects per call. No opcode and no storage key: it rides on the admin opcode.
-- Pure layout: ../pack30_gallery_core.lua (tests/pack30_gallery_test.lua). Data: data/lib/chaos_pack30_items.lua
-- (generated, may be missing) and data/lib/chaos_pack30_fx_ids.lua (ChaosVfx / ChaosVfxMissile entries, may be missing).
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "tools"; def.id = "tools." .. def.id; ChaosAdminPending[def.id] = def end

if not (ChaosPack30GalleryCore and ChaosPack30GalleryCore.parse) then
	dofile("data/scripts/chaos/pack30_gallery_core.lua")
end
local G = ChaosPack30GalleryCore

ChaosPack30Gallery = ChaosPack30Gallery or {}
local M = ChaosPack30Gallery
M.store = M.store or G.newStore()
M.events = M.events or {} -- admin key -> list of addEvent ids (fx / missiles)
M.names = M.names or {}   -- admin key -> character name (Player() takes a name, not a guid)

local MODEL = "Look Model"
local MAX_LINES = 160

local function loadLib()
	local ok, lib = pcall(dofile, "data/lib/chaos_pack30_items.lua")
	if ok and type(lib) == "table" then return lib end
	return nil
end

-- the fx id file defines ChaosVfx / ChaosVfxMissile entries; absent until the integrator generates it
local function loadFx()
	pcall(dofile, "data/lib/chaos_pack30_fx_ids.lua")
	return rawget(_G, "ChaosVfx") or {}, rawget(_G, "ChaosVfxMissile") or {}
end

local function adminKey(player) return player:getGuid() end
local function posOf(t) return Position(t.x, t.y, t.z) end
local function nowMs() return os.mtime and os.mtime() or (os.time() * 1000) end

-- ------------------------------------------------------------------ clear
function M.clear(player)
	local key = adminKey(player)
	local records = G.take(M.store, key)
	local items, monsters, grounds = 0, 0, 0
	for _, r in ipairs(records) do
		if r.kind == "item" then
			local tile = Tile(posOf(r.pos))
			local it = tile and tile:getItemById(r.id)
			if it then it:remove(); items = items + 1 end
		elseif r.kind == "monster" then
			local m = Monster(r.cid)
			if m then m:remove(); monsters = monsters + 1 end
		elseif r.kind == "ground" then
			local tile = Tile(posOf(r.pos))
			if tile then
				local g = tile:getGround()
				if g and g:getId() == r.new then g:remove() end
				if r.old and r.old > 0 then Game.createItem(r.old, 1, posOf(r.pos)) end
				grounds = grounds + 1
			end
		end
	end
	local ev = M.events[key]
	M.events[key] = nil
	local stopped = 0
	for _, id in ipairs(ev or {}) do
		if stopEvent then stopEvent(id); stopped = stopped + 1 end
	end
	return string.format("Cleared %d item(s), %d look(s), %d ground tile(s)%s.", items, monsters, grounds,
		stopped > 0 and (", stopped " .. stopped .. " scheduled effect(s)") or "")
end

local function scheduleExpiry(player)
	local key = adminKey(player)
	M.names[key] = player:getName()
	addEvent(function()
		for _, k in ipairs(G.expired(M.store, nowMs())) do
			if k == key then
				local p = Player(M.names[key] or "")
				if p then
					M.clear(p)
					p:sendTextMessage(MESSAGE_INFO_DESCR, "Pair 30 gallery: cleared after 30 minutes.")
				else
					-- the admin left: drop the records the same way, the engine objects still exist
					local fake = {getGuid = function() return key end}
					M.clear(fake)
				end
			end
		end
	end, G.TTL_MS + 1000)
end

-- ------------------------------------------------------------------ items, groups, anim
local function placeUnits(player, units, label)
	local origin = player:getPosition()
	local lay = G.layoutUnits(units, origin)
	local lines, records, skippedTile = {}, {}, 0
	for _, p in ipairs(lay.placements) do
		local pos = posOf(p)
		local tile = Tile(pos)
		if not tile or tile:getHouse() then
			skippedTile = skippedTile + 1
		else
			local it = Game.createItem(p.id, 1, pos)
			if it then
				records[#records + 1] = {kind = "item", pos = {x = p.x, y = p.y, z = p.z}, id = p.id}
				lines[#lines + 1] = G.line(p) .. string.format(" @%d,%d", p.x, p.y)
			else
				skippedTile = skippedTile + 1
			end
		end
	end
	if #records > 0 then G.add(M.store, adminKey(player), records, nowMs()); scheduleExpiry(player) end
	local msg = string.format("%s: %d object(s) in %d unit(s), %d row(s) east of you", label, #records, lay.units, lay.rows)
	if lay.skippedUnits > 0 then msg = msg .. string.format("; %d more unit(s) cut by the %d object cap, use a smaller range", lay.skippedUnits, G.MAX_OBJECTS) end
	if skippedTile > 0 then msg = msg .. string.format("; %d skipped (no tile, house tile or the server refused the id)", skippedTile) end
	return #records > 0, msg .. ".", lines
end

-- ------------------------------------------------------------------ grounds
local function placeGrounds(player, entries)
	local lay = G.layoutGrounds(entries, player:getPosition())
	local lines, records, refused = {}, {}, 0
	for _, p in ipairs(lay.placements) do
		local pos = posOf(p)
		local tile = Tile(pos)
		if not tile or tile:hasFlag(TILESTATE_PROTECTIONZONE) or tile:getHouse() then
			refused = refused + 1
		else
			local old = tile:getGround()
			local oldId = old and old:getId() or 0
			local it = Game.createItem(p.id, 1, pos)
			if it then
				records[#records + 1] = {kind = "ground", pos = {x = p.x, y = p.y, z = p.z}, old = oldId, new = p.id}
				lines[#lines + 1] = G.line(p) .. string.format(" @%d,%d (was %d)", p.x, p.y, oldId)
			else
				refused = refused + 1
			end
		end
	end
	if #records > 0 then G.add(M.store, adminKey(player), records, nowMs()); scheduleExpiry(player) end
	local msg = string.format("Grounds: %d tile(s) replaced (clear puts the old ground back)", #records)
	if refused > 0 then msg = msg .. string.format("; %d refused (protection zone, house tile, no tile)", refused) end
	if lay.skipped > 0 then msg = msg .. string.format("; %d more ground(s) beyond the %d cap", lay.skipped, G.MAX_OBJECTS) end
	return #records > 0, msg .. ".", lines
end

-- ------------------------------------------------------------------ looks
local function placeLooks(player, list, label)
	local lines, records, failed = {}, {}, 0
	for _, p in ipairs(list.placements) do
		local m = Game.createMonster(MODEL, posOf(p), false, true)
		if m then
			m:setOutfit({lookType = p.look, lookHead = p.head, lookBody = p.body, lookLegs = p.legs, lookFeet = p.feet})
			records[#records + 1] = {kind = "monster", cid = m:getId()}
			lines[#lines + 1] = string.format("look %d%s @%d,%d", p.look, p.label and (" " .. p.label) or "", p.x, p.y)
		else
			failed = failed + 1
		end
	end
	if #records > 0 then G.add(M.store, adminKey(player), records, nowMs()); scheduleExpiry(player) end
	local msg = string.format("%s: %d look(s) in rows of %d", label, #records, G.LOOKS_PER_ROW)
	if failed > 0 then msg = msg .. string.format("; %d failed (blocked tile, or the monster '%s' is not installed)", failed, MODEL) end
	if list.skipped > 0 then msg = msg .. string.format("; %d more beyond the %d cap", list.skipped, G.MAX_OBJECTS) end
	return #records > 0, msg .. ".", lines
end

-- ------------------------------------------------------------------ fx and missiles
local function schedule(player, list, fn)
	local key = adminKey(player)
	M.events[key] = M.events[key] or {}
	for _, e in ipairs(list) do
		M.events[key][#M.events[key] + 1] = addEvent(fn, math.max(e.delay, 1), e)
	end
end

local function showFx(player, cmd)
	local vfx = loadFx()
	local list = G.layoutFx(cmd.from, cmd.to, player:getPosition(), G.knownFx(vfx))
	local lines = {}
	for _, e in ipairs(list) do lines[#lines + 1] = string.format("fx %d%s @%d,%d after %d ms", e.id, e.name and ("/" .. e.name) or "", e.x, e.y, e.delay) end
	schedule(player, list, function(e) posOf(e):sendMagicEffect(e.id) end)
	return true, string.format("Effects %d-%d: %d effect(s), one every %.1f s east of you.", cmd.from, cmd.to, #list, G.FX_STEP_MS / 1000), lines
end

local function showMissiles(player)
	local _, missiles = loadFx()
	local list = G.layoutMissiles(G.missileIds(missiles), player:getPosition())
	local lines = {}
	for _, e in ipairs(list) do lines[#lines + 1] = string.format("missile %d after %d ms", e.id, e.delay) end
	schedule(player, list, function(e) posOf(e.from):sendDistanceEffect(posOf(e.to), e.id) end)
	return true, string.format("Missiles: %d shot(s), one every %.1f s.", #list, G.FX_STEP_MS / 1000), lines
end

-- ------------------------------------------------------------------ wear
local function wear(player, cmd, lib)
	local outfit, why = G.wearOutfit(lib, cmd.look, cmd.scheme)
	if not outfit then return false, why end
	local c = Condition(CONDITION_OUTFIT)
	c:setOutfit(outfit)
	c:setTicks(G.WEAR_MS)
	player:addCondition(c)
	return true, string.format("You wear look %d (scheme %d) for 10 minutes; walk to see the cycle. Relog or 'wear' another look to change.", cmd.look, cmd.scheme or 1)
end

-- ------------------------------------------------------------------ entry point
function M.run(player, what, arg)
	if not (ChaosAdmin and ChaosAdmin.isAdmin(player)) then return false, "Admins only." end
	local cmd, why = G.parse(what, arg)
	if not cmd then return false, why end
	if cmd.cmd == "clear" then return true, M.clear(player) end
	local lib = loadLib()
	local needsLib = cmd.cmd == "items" or cmd.cmd == "groups" or cmd.cmd == "grounds" or cmd.cmd == "anim"
	if needsLib and not lib then
		return false, "data/lib/chaos_pack30_items.lua is missing: run server/tools/install_pack30_items.py --lua first."
	end
	if cmd.cmd == "items" then
		return placeUnits(player, G.units(lib, G.selectRange(G.entries(lib), cmd.from, cmd.to)), "Items " .. (cmd.block or (cmd.from .. "-" .. cmd.to)))
	elseif cmd.cmd == "groups" then
		return placeUnits(player, G.units(lib, nil), "Groups")
	elseif cmd.cmd == "anim" then
		return placeUnits(player, G.units(lib, G.selectAnim(G.entries(lib))), "Animated objects")
	elseif cmd.cmd == "grounds" then
		return placeGrounds(player, G.selectGrounds(G.entries(lib)))
	elseif cmd.cmd == "looks" then
		return placeLooks(player, G.layoutLooks(G.range(cmd.from, cmd.to), player:getPosition()), "Looks " .. cmd.from .. "-" .. cmd.to)
	elseif cmd.cmd == "schemes" then
		lib = lib or loadLib()
		return placeLooks(player, G.layoutSchemes(lib, cmd.look, player:getPosition()), "Schemes of look " .. cmd.look)
	elseif cmd.cmd == "fx" then
		return showFx(player, cmd)
	elseif cmd.cmd == "missiles" then
		return showMissiles(player)
	elseif cmd.cmd == "wear" then
		return wear(player, cmd, loadLib())
	end
	return false, "Unknown command."
end

reg{id = "pack30_gallery", name = "Pair 30 gallery",
	description = "Show the pair 30 art in game: items <block|from-to> (blocks items-a..d, corpses-1/2, grounds, decor-1/2, bldg, anim, reserve; or client ids), groups, grounds (replaces the floor under a strip, clear restores it), anim, looks <from-to>, schemes <look>, fx <from-to>, missiles, wear <look> [scheme], clear. Max 150 objects per call, auto clear after 30 minutes. Needs a client on pair 30.",
	params = {{name = "what", label = "What", type = "select", default = "clear", options = {
			{value = "items", label = "items <block|from-to>"}, {value = "groups", label = "groups (whole buildings)"},
			{value = "grounds", label = "grounds (replaces floor, clear restores)"}, {value = "anim", label = "anim (animated objects)"},
			{value = "looks", label = "looks <from-to>"}, {value = "schemes", label = "schemes <look>"}, {value = "fx", label = "fx <from-to>"},
			{value = "missiles", label = "missiles"}, {value = "wear", label = "wear <look> [scheme]"}, {value = "clear", label = "clear"}}},
		{name = "arg", label = "Argument (block name, from-to, look id, 'look scheme')", type = "string", max = 40, required = false}},
	handler = function(actor, p)
		if not ChaosAdmin.isAdmin(actor) then return false, "Admins only." end
		local ok, msg, lines = M.run(actor, p.what, p.arg)
		if lines and #lines > MAX_LINES then
			local cut = {}
			for i = 1, MAX_LINES do cut[i] = lines[i] end
			lines = cut
		end
		return ok, msg, lines
	end}

-- /pack30gallery <what> [arg]: staff only, same function (owner rule: no player talkactions)
local talk = TalkAction("/pack30gallery")
function talk.onSay(player, words, param)
	if not (ChaosAdmin and ChaosAdmin.isAdmin(player)) then
		return true
	end
	local ok, msg, lines = M.run(player, param, "")
	player:sendTextMessage(MESSAGE_INFO_DESCR, msg or "")
	for i, l in ipairs(lines or {}) do
		if i > 40 then player:sendTextMessage(MESSAGE_INFO_DESCR, "... " .. (#lines - 40) .. " more (use the panel for the full list)"); break end
		player:sendTextMessage(MESSAGE_INFO_DESCR, l)
	end
	return false
end
talk:separator(" ")
talk:register()
