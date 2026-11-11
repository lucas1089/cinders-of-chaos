-- The Rune Bag in the purse: the count of a magic rune the client adds to its own (O509, owner 2026-11-11: "The rune
-- bag stays in the purse."; server data/scripts/chaos/pouches.lua `runebag`, engine src-patch 0092; the pure part, tested by
-- runebagcount_test.lua; the client calls are in pouches.lua).
--
-- Why: LocalPlayer:getInventoryCount counts the equipped items and the OPEN containers only. A rune in a closed bag, and
-- every rune in the Rune Bag of the purse (the client never opens the purse's bags by itself), counted 0, so the action
-- bar showed no number for it and the helper could only probe. With engine src-patch 0092 the server finds that rune for a
-- hotkey, the action bar and the helper, so the server says how many of each magic rune the purse's Rune Bag holds
-- (`runebag {engine, counts = {[client id] = n}, bag, poll}`, polled) and the client adds them to its own count.
--   * engine = false (an engine built before the patch): nothing is added. The client never counts a rune the server could
--     not use, so the helper keeps its probe and the action bar its old number (no use that fails every tick).
--   * the bag is open in the client (a page of the inventory panel, a window): its runes are already in the client's count,
--     so only what the open bag does not show is added (never counted twice).
-- Lua 5.1 / LuaJIT and 5.3.

RuneBagCount = {}
local R = RuneBagCount

R.MIN_POLL = 1 -- seconds
R.MAX_POLL = 60
R.DEFAULT_POLL = 15

function R.newState()
  return { engine = false, counts = {}, bag = false, poll = R.DEFAULT_POLL }
end

-- back to the start (game end, a new game): in place, so a count function that holds the table sees it
function R.reset(state)
  state.engine, state.counts, state.bag, state.poll = false, {}, false, R.DEFAULT_POLL
end

-- the server's answer into the state. Returns true when what the count shows changed (the action bar needs a refresh).
-- A malformed answer changes nothing.
function R.apply(state, data)
  if type(data) ~= 'table' then return false end
  local before = R.signature(state)
  state.engine = data.engine == true
  local counts = {}
  if state.engine and type(data.counts) == 'table' then
    for k, v in pairs(data.counts) do
      local id, n = tonumber(k), tonumber(v)
      if id and id > 0 and n and n > 0 then counts[tostring(math.floor(id))] = math.floor(n) end
    end
  end
  state.counts = counts
  state.bag = data.bag == true
  local poll = tonumber(data.poll) or R.DEFAULT_POLL
  state.poll = math.max(R.MIN_POLL, math.min(R.MAX_POLL, poll))
  return R.signature(state) ~= before
end

-- the counts as one text, in id order (what changed between two answers)
function R.signature(state)
  if not state.engine then return 'off' end
  local keys = {}
  for k in pairs(state.counts) do keys[#keys + 1] = tonumber(k) end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. '=' .. state.counts[tostring(k)] end
  return table.concat(parts, ',')
end

-- how many of rune `id` (a client item id) the client already sees inside an open Rune Bag of the purse. containers =
-- { { inPurseBag = bool, items = { { id = , count = } } } } (the adapter in pouches.lua builds it from the open containers)
function R.openSeen(containers, id)
  local n = 0
  for _, c in ipairs(containers or {}) do
    if c.inPurseBag then
      for _, it in ipairs(c.items or {}) do
        if it.id == id then n = n + (tonumber(it.count) or 1) end
      end
    end
  end
  return n
end

-- the count to add to the client's own count of rune `id`: the server's count of the purse bag, less what an open copy of
-- that bag already shows. seen(id) gives that (nil: nothing open). 0 without the engine patch.
function R.extra(state, id, seen)
  if not state.engine then return 0 end
  local n = state.counts[tostring(id)]
  if not n then return 0 end
  local shown = seen and seen(id) or 0
  return math.max(0, n - shown)
end

-- the delay to the next question, in milliseconds
function R.pollMs(state)
  return math.floor(math.max(R.MIN_POLL, math.min(R.MAX_POLL, state.poll or R.DEFAULT_POLL)) * 1000)
end

-- the count function that replaces LocalPlayer:getInventoryCount: the old count plus the extra. A failure in the extra
-- gives back the old count (never an error in the action bar or the helper).
function R.wrap(original, state, seen)
  return function(self, id, ...)
    local n = original(self, id, ...)
    if not state.engine or not id then return n end
    local ok, extra = pcall(R.extra, state, id, seen)
    if ok and extra and extra > 0 then return (n or 0) + extra end
    return n
  end
end

return RuneBagCount
