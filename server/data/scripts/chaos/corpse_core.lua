-- Loot bag instead of monster bodies, the pure part (ChaosCorpse; config corpse_config.lua, engine glue corpse_bag.lua,
-- tests/corpse_bag_test.lua). server/README.md "Loot bag instead of corpses". Lua 5.1 / LuaJIT compatible.
--   ChaosCorpse.validate(cfg)            list of problems (empty = fine)
--   ChaosCorpse.engineArgs(cfg, itemOk)  bagId, keepIds for Game.setMonsterLootBag: bagId 0 when off or invalid
--   ChaosCorpse.corpseFor(cfg, kind, id) the corpse item a creature of kind ("monster" | "player") leaves when its own
--                                        corpse is id; the same rule as the engine (src-patch 0089, chaoslootbag.h)
--   ChaosCorpse.isBag(cfg, id)           the id is the bag
--   ChaosCorpse.itemXml(cfg, text)       items.xml text with the bag's entry set (tools/patch_monster_corpses.py mirrors it)
-- The empty bag decay (O565; engine glue corpse_empty.lua, tests/corpse_bag_test.lua):
--   ChaosCorpse.emptyMs(cfg)             milliseconds an emptied bag has left, nil when the shortcut is off
--   ChaosCorpse.shouldShorten(cfg, size, remainingMs)   true: an empty bag that would last longer than that
--   ChaosCorpse.newWatch()               the places where a bag lies (a set of positions, nothing else)
--   ChaosCorpse.watch(w, pos, nowSec)    remember a place
--   ChaosCorpse.sweep(cfg, w, nowSec, probe, shorten)   one pass: probe(pos) answers the bags on that tile as a list of
--                                        {size, remaining} rows (remaining in ms), shorten(row, ms) is called for each
--                                        empty bag that lasts longer; a place with no bag left, or only bags that are empty
--                                        and about to go, is forgotten; so is a place older than the bag can live
--   ChaosCorpse.count(w)                 places watched

ChaosCorpse = ChaosCorpse or {}
local C = ChaosCorpse

local function isId(v)
	return type(v) == "number" and v >= 100 and v <= 65535 and v == math.floor(v)
end

function C.validate(cfg)
	local out = {}
	if type(cfg) ~= "table" then
		return {"no config"}
	end
	if not isId(cfg.bagId) then
		out[#out + 1] = "bagId must be an item id (100-65535)"
	end
	if type(cfg.seconds) ~= "number" or cfg.seconds < 30 or cfg.seconds > 300 then
		out[#out + 1] = "seconds must be 30-300 (the owner's rule: a corpse stays at most 5 minutes)"
	end
	if type(cfg.slots) ~= "number" or cfg.slots < 1 or cfg.slots > 255 then
		out[#out + 1] = "slots must be 1-255"
	end
	if type(cfg.name) ~= "string" or cfg.name == "" then
		out[#out + 1] = "name must be a text"
	end
	if not isId(cfg.look) then
		out[#out + 1] = "look must be a client item id (100-65535)"
	end
	if type(cfg.emptySeconds) ~= "number" or cfg.emptySeconds < 0 or cfg.emptySeconds > 60 then
		out[#out + 1] = "emptySeconds must be 0-60 (0 = an empty bag keeps the normal time)"
	elseif type(cfg.seconds) == "number" and cfg.emptySeconds > 0 and cfg.emptySeconds >= cfg.seconds then
		out[#out + 1] = "emptySeconds must be shorter than seconds"
	end
	for i, id in ipairs(cfg.keepIds or {}) do
		if not isId(id) then
			out[#out + 1] = "keepIds[" .. i .. "] is no item id"
		elseif id == cfg.bagId then
			out[#out + 1] = "keepIds[" .. i .. "] is the bag itself"
		end
	end
	return out
end

-- itemOk: nil (not asked) or the answer of the engine about the bag item: a container that counts as a corpse
function C.engineArgs(cfg, itemOk)
	if type(cfg) ~= "table" or not cfg.enabled or #C.validate(cfg) > 0 or itemOk == false then
		return 0, {}
	end
	local keep = {}
	for _, id in ipairs(cfg.keepIds or {}) do
		keep[#keep + 1] = id
	end
	table.sort(keep)
	return cfg.bagId, keep
end

function C.isBag(cfg, id)
	return type(cfg) == "table" and cfg.bagId == id
end

-- what the engine does (chaoslootbag.h corpseOf, called from Monster::getLookCorpse only). A player never gets the bag:
-- Player::getLookCorpse is not touched by the patch, and this function says the same.
function C.corpseFor(cfg, kind, id)
	if kind ~= "monster" then
		return id
	end
	local bag, keep = C.engineArgs(cfg)
	if bag == 0 or not id or id == 0 or id == bag then
		return id
	end
	for _, k in ipairs(keep) do
		if k == id then
			return id
		end
	end
	return bag
end

-- ---------------------------------------------------------------- the empty bag decay (O565)
C.CHECK_MS = 1000   -- how often the places are looked at; an emptied bag goes at most this much later than emptySeconds
C.GRACE_SEC = 15    -- a place is forgotten this long after the bag's own time ran out, whatever it holds

function C.emptyMs(cfg)
	if type(cfg) ~= "table" or not cfg.enabled or #C.validate(cfg) > 0 or cfg.emptySeconds <= 0 then
		return nil
	end
	return math.floor(cfg.emptySeconds * 1000)
end

function C.shouldShorten(cfg, size, remainingMs)
	local ms = C.emptyMs(cfg)
	return ms ~= nil and (size or 0) == 0 and (remainingMs or 0) > ms
end

function C.newWatch()
	return {places = {}, n = 0}
end

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

function C.watch(w, pos, nowSec)
	if type(pos) ~= "table" or not pos.x or not pos.y or not pos.z then
		return false
	end
	local k = key(pos)
	if not w.places[k] then
		w.n = w.n + 1
	end
	w.places[k] = {pos = {x = pos.x, y = pos.y, z = pos.z}, at = nowSec or 0}
	return true
end

function C.count(w)
	return w.n
end

function C.sweep(cfg, w, nowSec, probe, shorten)
	local ms = C.emptyMs(cfg)
	local done = {}
	for k, place in pairs(w.places) do
		local rows = ms and probe(place.pos) or {}
		local pending = false
		for _, row in ipairs(rows) do
			if C.shouldShorten(cfg, row.size, row.remaining) then
				shorten(row, ms)
			elseif (row.size or 0) > 0 then
				pending = true -- loot still in it: look again
			end
		end
		local expired = (nowSec or 0) - place.at > cfg.seconds + C.GRACE_SEC
		if #rows == 0 or not pending or expired then
			done[#done + 1] = k
		end
	end
	for _, k in ipairs(done) do
		w.places[k] = nil
		w.n = w.n - 1
	end
	return #done
end

return C
