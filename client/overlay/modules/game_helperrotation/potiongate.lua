-- ChaosPotionGate: may the helper use a potion it cannot count? (base patch 0070; potiongate_test.lua;
-- client/MANIFEST.md "Helper potions in closed backpacks").
-- On this server (10.98, no packed inventory) LocalPlayer:getInventoryCount counts only the equipped items and the
-- OPEN containers, and the helper used a potion only when that count was above 0. A potion in a closed backpack, as
-- the Everfull potions usually are (one per character, look of the Health / Mana Potion), was never used, although
-- the server's use by id finds the item in any carried container. Now a count of 0 still allows a use every PROBE_MS
-- (a probe); when the server answers it with "Sorry, not possible." (nothing to use) within REPLY_MS, the potion waits
-- BACKOFF_MS. A potion the client sees (count > 0) is used as before.
ChaosPotionGate = ChaosPotionGate or {}
local G = ChaosPotionGate

G.PROBE_MS = 3000
G.REPLY_MS = 1500
G.BACKOFF_MS = 30000
G.FAIL_TEXTS = { 'sorry, not possible', 'you do not have', 'you cannot use this object' }

local function state(st, id)
  st[id] = st[id] or { nextProbe = 0, lastProbe = nil }
  return st[id]
end

function G.newState() return {} end

-- may potion `id` be used now? count: what the client counts
function G.allowed(st, id, now, count)
  if (tonumber(count) or 0) > 0 then return true end
  return (tonumber(now) or 0) >= state(st, id).nextProbe
end

-- the use was sent: a use the client could not count is a probe
function G.used(st, id, now, count)
  if (tonumber(count) or 0) > 0 then
    state(st, id).nextProbe = 0
    return
  end
  local s = state(st, id)
  s.lastProbe = now
  s.nextProbe = now + G.PROBE_MS
end

-- a server text: the answer to a probe sent within REPLY_MS means there was nothing to use
function G.onText(st, text, now)
  local t = tostring(text or ''):lower()
  local failure = false
  for _, f in ipairs(G.FAIL_TEXTS) do
    if t:find(f, 1, true) then failure = true end
  end
  if not failure then return false end
  local hit = false
  for _, s in pairs(st) do
    if s.lastProbe and now - s.lastProbe <= G.REPLY_MS then
      s.nextProbe = now + G.BACKOFF_MS
      s.lastProbe = nil
      hit = true
    end
  end
  return hit
end

G.session = G.session or G.newState()

return ChaosPotionGate
