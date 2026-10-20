-- ChaosPotionGate: may the helper use a potion it cannot count? (base patch 0070; potiongate_test.lua;
-- client/MANIFEST.md "Helper potions in closed backpacks").
-- On this server (10.98, no packed inventory) LocalPlayer:getInventoryCount counts only the equipped items and the
-- OPEN containers, and the helper used a potion only when that count was above 0. A potion in a closed backpack, as
-- the Everfull potions usually are (one per character, look of the Health / Mana Potion), was never used, although
-- the server's use by id finds the item in any carried container. Now a count of 0 still allows a use every PROBE_MS
-- (a probe). A potion the client sees (count > 0) is used as before. Runes go the same way (canUse / noteUse below).
--
-- The server's answer decides what a probe found:
--   * "Using ..." (the hotkey message of every use by id: "Using an everfull mana potion (never runs out).", "Using
--     one of 12 ...", "Using the last ...") within REPLY_MS: the item is there. It is then used like a counted one
--     (no PROBE_MS wait) until a probe fails;
--   * "Sorry, not possible." / "You cannot use this object." within REPLY_MS and no "Using ..." within SETTLE_MS
--     after it: nothing to use, the item waits BACKOFF_MS.
-- Owner beta 2026-10-20 ("the helper stopped using the potion", Ranger at 21 mana): the old gate backed every probe of
-- the last REPLY_MS off on the first failure-like text, and its texts included "you do not have", which is the start
-- of the server's "You do not have enough mana." The helper's heal spell went out in the same tick as the potion
-- probe; with no mana the server refused the spell, and that refusal put the Everfull mana and health potions on a
-- 30 s wait, again at every retry of the spell, so no potion was used while the character ran dry. A spell's refusal
-- no longer counts, and a failure is only the probe's when the probe did not answer "Using ..." itself.
ChaosPotionGate = ChaosPotionGate or {}
local G = ChaosPotionGate

G.PROBE_MS = 3000
G.REPLY_MS = 1500
G.SETTLE_MS = 500
G.BACKOFF_MS = 30000
-- the server's answer to a use by id that found nothing (Game::playerUseItemEx / playerUseWithCreature: the thing
-- is not found -> RETURNVALUE_NOTPOSSIBLE). Not "You do not have enough mana." (a spell's refusal).
G.FAIL_TEXTS = { 'sorry, not possible', 'you cannot use this object' }
-- the hotkey message of a use by id (actions.cpp showUseHotkeyMessage, server patch 0043 for the Everfull)
G.USED_PATTERN = '^using '

local seq = 0 -- the order of the probes: the server answers them in the order they were sent

local function state(st, id)
  st[id] = st[id] or { nextProbe = 0, lastProbe = nil, order = 0, answered = true, failAt = nil, found = false }
  return st[id]
end

-- a failure that no "Using ..." took back within SETTLE_MS: the probe found nothing
local function settle(s, now)
  if s.failAt and now - s.failAt >= G.SETTLE_MS then
    s.nextProbe = s.failAt + G.BACKOFF_MS
    s.failAt = nil
    s.found = false
  end
end

function G.newState() return {} end

-- may potion `id` be used now? count: what the client counts
function G.allowed(st, id, now, count)
  if (tonumber(count) or 0) > 0 then return true end
  now = tonumber(now) or 0
  local s = state(st, id)
  settle(s, now)
  if s.failAt then return false end -- the answer is not settled yet
  if s.found then return true end
  return now >= s.nextProbe
end

-- the use was sent: a use the client could not count is a probe
function G.used(st, id, now, count)
  local s = state(st, id)
  if (tonumber(count) or 0) > 0 then
    s.nextProbe = 0
    return
  end
  seq = seq + 1
  s.lastProbe, s.order, s.answered = now, seq, false
  if not s.found then s.nextProbe = now + G.PROBE_MS end
end

-- the probe within REPLY_MS that a text answers: the oldest one not answered yet (pending), else, for a
-- "Using ...", the latest one whose failure is not settled (another use's refusal came before the probe's answer)
local function answering(st, now, takeBack)
  local best = nil
  for _, s in pairs(st) do
    if s.lastProbe and now - s.lastProbe <= G.REPLY_MS and not s.answered then
      if not best or s.order < best.order then best = s end
    end
  end
  if best or not takeBack then return best end
  for _, s in pairs(st) do
    if s.lastProbe and now - s.lastProbe <= G.REPLY_MS and s.failAt then
      if not best or s.order > best.order then best = s end
    end
  end
  return best
end

-- a server text: "Using ..." marks the answered probe found; a failure holds it (failAt), and it backs off unless its
-- own "Using ..." follows within SETTLE_MS. Returns true when the text answered a probe.
function G.onText(st, text, now)
  local t = tostring(text or ''):lower()
  if t:find(G.USED_PATTERN) then
    local s = answering(st, now, true)
    if not s then return false end
    s.answered, s.failAt, s.found, s.nextProbe = true, nil, true, 0
    return true
  end
  local failure = false
  for _, f in ipairs(G.FAIL_TEXTS) do
    if t:find(f, 1, true) then failure = true end
  end
  if not failure then return false end
  local s = answering(st, now, false)
  if not s then return false end
  s.answered, s.failAt = true, now
  return true
end

G.session = G.session or G.newState()

-- The same gate for runes (base patch 0082; owner 2026-10-20: "o helper nao esta usando runas"). The magic shooter and
-- the healing rune (Auto UH) used a rune only when getInventoryCount saw one, and that count misses a rune in a closed
-- backpack, where every rune sits, so the helper never used a rune. The call sites use the shared session:
-- canUse(id, count, now) before the use, noteUse(id, count, now) after it; onText (autorotation_ui) reads the answer.
function G.canUse(id, count, now)
  return G.allowed(G.session, id, now, count)
end

function G.noteUse(id, count, now)
  G.used(G.session, id, now, count)
end

function G.reset()
  G.session = G.newState()
end

return ChaosPotionGate
