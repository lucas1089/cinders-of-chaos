-- prizes_core.lua: where a prize of a base script goes, and the roulettes' winner (server/README.md "Prizes into the
-- backpack"). Pure Lua, no engine calls; the glue is prizes.lua, the base script changes are tools/patch_prizes.py;
-- tests/prizes_test.lua.
--
-- User report 2026-10-21: the Boss Roulette said "you won The Awakener" (a ship) and the ship was in no bag and not in
-- the inbox. The base roulettes give the prize with player:addItem(id, count, true), and the engine puts an item into
-- an empty inventory slot that takes it before any container: a ship went into the ship slot (14), which no client
-- draws. Engine patch 0058 refuses those slots now; the base scripts that hand out prizes give them to the backpack
-- first (a container in it when it is full), then the store inbox ("Purse"), then the ground under the player.
-- Lua 5.1 / LuaJIT and 5.3.

ChaosPrizesCore = ChaosPrizesCore or {}
local K = ChaosPrizesCore

-- where a prize may go, in order
K.PLACES = {"backpack", "store inbox", "ground"}

-- the roulette tile's winner: {id, count, charges} from the top visible thing of the tile, or nil when that is no prize
-- (the tile changed: nothing there, a creature, the ground, a decoration the roulette ignores). thing is a table with
-- the values read from the engine: {isItem, id, count, charges, showCharges}; groundId the tile's ground id or nil.
function K.winner(thing, groundId, ignored)
	if type(thing) ~= "table" or not thing.isItem then
		return nil
	end
	local id = tonumber(thing.id)
	if not id or id <= 0 or id == tonumber(groundId) then
		return nil
	end
	for _, ig in ipairs(ignored or {}) do
		if tonumber(ig) == id then
			return nil
		end
	end
	local count = math.max(1, math.floor(tonumber(thing.count) or 1))
	local out = {id = id, count = count}
	if thing.showCharges then
		out.count = 1
		out.charges = math.max(1, math.floor(tonumber(thing.charges) or count))
	end
	return out
end

-- true when the prize is rare enough to be broadcast: the lowest chance the pool gives this item is at most the
-- threshold (the base looked up chancedItems[#chancedItems - 3], the chance of another spin's item, nil after fewer
-- than four spins)
function K.isRare(pool, id, threshold)
	id = tonumber(id)
	local best
	for _, p in ipairs(pool or {}) do
		if tonumber(p.itemId) == id then
			local c = tonumber(p.chance) or 0
			best = best and math.min(best, c) or c
		end
	end
	return best ~= nil and best <= (tonumber(threshold) or 0)
end

-- the pool without the items no slot shows (badges_core.lua: decks, ships, belts, gloves). The install tool takes them
-- out of the base files; this is the guard for a pool it did not reach. Returns the new pool and the ids taken out.
function K.cleanPool(pool, isRetired)
	local out, gone = {}, {}
	for _, p in ipairs(pool or {}) do
		if isRetired and isRetired(p.itemId) then
			gone[#gone + 1] = tonumber(p.itemId)
		else
			out[#out + 1] = p
		end
	end
	return out, gone
end

-- the odds of each pool entry under the base draw (every entry rolls its chance in 1..10000; one of those that hit is
-- picked at random; nothing hit: roll again): {[index] = probability}. Exact over the hit sets for up to 20 entries
-- (the base pools have 5-21), used by the tests and the README numbers.
function K.odds(pool)
	local n = #pool
	local out = {}
	for i = 1, n do
		out[i] = 0
	end
	if n == 0 then
		return out
	end
	local p = {}
	for i = 1, n do
		p[i] = math.min(1, math.max(0, (tonumber(pool[i].chance) or 0) / 10000))
	end
	-- P(entry i picked) = sum over k of P(i hit and k-1 others hit) / k, then divided by P(any hit)
	-- the count distribution of the others is a Poisson binomial, built by dynamic programming per entry
	local none = 1
	for i = 1, n do
		none = none * (1 - p[i])
	end
	for i = 1, n do
		local dist = {[0] = 1}
		for j = 1, n do
			if j ~= i then
				local nd = {}
				for k = 0, n do
					nd[k] = (dist[k] or 0) * (1 - p[j]) + (k > 0 and (dist[k - 1] or 0) * p[j] or 0)
				end
				dist = nd
			end
		end
		local s = 0
		for k = 0, n - 1 do
			s = s + (dist[k] or 0) / (k + 1)
		end
		out[i] = p[i] * s / (1 - none)
	end
	return out
end

K.TEXT_INBOX = "Your prize %s is in your Purse (the store inbox): your backpack had no room."
K.TEXT_GROUND = "Your prize %s is on the ground under you: your backpack and your Purse had no room."
K.TEXT_LOST_SPIN = "The roulette could not find your prize. Your next spin is free."

return K
