-- ChaosHelperSell: when the helper asks the Auto Seller to sell the Loot Bag (pure Lua: no engine calls; tests:
-- helper_sell_test.lua).
-- The old helper's "Auto Sell Loot" sold the loot through a summoned sell NPC (a Summon Quill), which this server does not
-- have. What it has is the store's Auto Seller (server/README.md "Store services", data/scripts/chaos/autosell.lua): the
-- player's Loot Bag is sold at the NPC prices, the gold goes to the bank, at most once in 30 seconds. The helper only
-- asks (extended opcode 226 action `sell`, through game_pouches' sellAll) and never touches an item: the server decides
-- what is sold and keeps what must stay (locked items, uniques, equipped items, containers' locked contents, orbs, gems and
-- keys, store items, rarities the player did not tick, named items), and it refuses when the player has no Auto Seller.
-- Ask when
--   * the timer is out: every `minutes` (5, 10, 15, 30 or 60) after the last ask, or
--   * the free capacity is below `capacity` oz (the old option "sell when capacity is low"), at most every CAP_GAP_MS;
-- and only when the server told the client the Auto Seller is unlocked and its cooldown is over, outside the pauses the
-- helper has anyway (helper off, a frozen connection).
ChaosHelperSell = ChaosHelperSell or {}
local S = ChaosHelperSell

S.MINUTES = { 5, 10, 15, 30, 60 }
S.DEFAULT_MINUTES = 30
S.CAP_GAP_MS = 60000          -- the capacity trigger asks at most this often
S.MIN_GAP_MS = 31000          -- no two asks closer than the server's 30 s cooldown
S.STATE_STALE_MS = 300000     -- ask the server for its state again after this long

function S.minutesOf(v)
  local n = tonumber(v)
  for _, m in ipairs(S.MINUTES) do
    if n == m then return m end
  end
  return nil
end

function S.newState() return { lastAsk = nil, lastSync = nil } end

-- cfg = { enabled, minutes, belowCap, capacity }; seller = what the server said { known, unlocked, cooldown (s) };
-- in = { now (ms), freeCap (oz), helperOn }. Returns 'sell', 'sync' or nil, and a reason.
function S.decide(cfg, st, seller, input)
  if type(cfg) ~= 'table' or cfg.enabled ~= true then return nil, 'off' end
  if not input.helperOn then return nil, 'helperoff' end
  local now = input.now
  if not seller or not seller.known then
    -- the state is not here yet: ask for it (the server answers with the window state, no window opens)
    if not st.lastSync or now - st.lastSync >= 10000 then
      st.lastSync = now
      return 'sync', 'unknown'
    end
    return nil, 'unknown'
  end
  if not seller.unlocked then
    -- maybe bought a moment ago: look again now and then
    if not st.lastSync or now - st.lastSync >= S.STATE_STALE_MS then
      st.lastSync = now
      return 'sync', 'locked'
    end
    return nil, 'locked'
  end
  if (tonumber(seller.cooldown) or 0) > 0 then return nil, 'cooldown' end
  if st.lastAsk and now - st.lastAsk < S.MIN_GAP_MS then return nil, 'gap' end
  local minutes = S.minutesOf(cfg.minutes) or S.DEFAULT_MINUTES
  -- the count runs from the last ask; before the first one from the first look at the state (no sale at the very login)
  local since = st.lastAsk
  if not since then
    st.start = st.start or now
    since = st.start
  end
  local due = now - since >= minutes * 60000
  local why = 'timer'
  if not due and cfg.belowCap == true and tonumber(input.freeCap) and input.freeCap <= (tonumber(cfg.capacity) or 0) then
    if not st.lastAsk or now - st.lastAsk >= S.CAP_GAP_MS then
      due, why = true, 'capacity'
    end
  end
  if not due then return nil, 'wait' end
  st.lastAsk = now
  return 'sell', why
end

return ChaosHelperSell
