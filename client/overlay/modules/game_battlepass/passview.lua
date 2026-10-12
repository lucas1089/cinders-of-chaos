-- Pure helpers of the Season Pass window (no client API), tested by passview_test.lua.
PassView = {}

local FREE, PREMIUM = 0, 1
PassView.FREE, PassView.PREMIUM = FREE, PREMIUM

-- "0110" (the server's claimed string, tier 1 first) -> {[2] = true, [3] = true}
function PassView.claimedSet(str)
  local set = {}
  if type(str) ~= 'string' then return set end
  for i = 1, #str do
    if str:sub(i, i) == '1' then set[i] = true end
  end
  return set
end

-- state of one reward cell: 'claimed', 'claimable', 'premium' (reached, the account has no premium), 'locked'
-- (tier not reached), 'closed' (reached but the claim window is over)
function PassView.cellState(state, tier, track)
  state = type(state) == 'table' and state or {}
  local claimed = type(state.claimed) == 'table' and state.claimed[track + 1] or ''
  if type(claimed) == 'string' and claimed:sub(tier, tier) == '1' then return 'claimed' end
  if tier > (tonumber(state.tier) or 0) then return 'locked' end
  if track == PREMIUM and not state.premium then return 'premium' end
  local s = type(state.season) == 'table' and state.season.status or nil
  if s ~= 'active' and s ~= 'grace' then return 'closed' end
  return 'claimable'
end

-- rewards the account can claim now
function PassView.claimableCount(state)
  local n = 0
  local top = math.min(tonumber(state and state.tier) or 0, tonumber(state and state.maxTier) or 0)
  for t = 1, top do
    for _, track in ipairs({ FREE, PREMIUM }) do
      if PassView.cellState(state, t, track) == 'claimable' then n = n + 1 end
    end
  end
  return n
end

-- 93784 -> "1d 02h 03m", 3725 -> "1h 02m 05s", nil / negative -> "0h 00m 00s"
function PassView.formatTime(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local d = math.floor(seconds / 86400)
  local h = math.floor((seconds % 86400) / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if d > 0 then return string.format('%dd %02dh %02dm', d, h, m) end
  return string.format('%dh %02dm %02ds', h, m, s)
end

-- seconds left now, from the value the server sent and the time since it arrived
function PassView.left(sent, receivedAt, now)
  return math.max(0, (tonumber(sent) or 0) - math.max(0, (now or 0) - (receivedAt or 0)))
end

-- progress bar: percent and text
function PassView.progress(state)
  local tier, max = tonumber(state.tier) or 0, tonumber(state.maxTier) or 0
  if max > 0 and tier >= max then return 100, 'Max tier reached' end
  local into, need = tonumber(state.into) or 0, tonumber(state.need) or 0
  if need <= 0 then return 0, '' end
  return math.floor(into * 100 / need), string.format('%d / %d XP to tier %d', into, need, tier + 1)
end

-- the button of an offer of the Packs page: text, enabled
function PassView.offerButton(offer)
  if type(offer) ~= 'table' then return '', false end
  if offer.owned then return 'Owned', false end
  local price = tonumber(offer.price)
  if not price then return 'Unavailable', false end
  local full = tonumber(offer.full) or price
  if price < full then return string.format('Upgrade %d', price), true end
  return string.format('Buy %d', price), true
end

-- "Experience 120 / 300" (a source line of the Challenges page)
function PassView.sourceLine(s)
  if type(s) ~= 'table' then return '' end
  return string.format('%s %d / %d', tostring(s.name or s.key or '?'), math.floor(tonumber(s.today) or 0),
    math.floor(tonumber(s.cap) or 0))
end

-- a challenge row: text, progress text, percent
function PassView.challenge(c)
  if type(c) ~= 'table' then return '', '', 0 end
  local target = math.max(1, tonumber(c.target) or 1)
  local progress = math.min(target, tonumber(c.progress) or 0)
  if c.done then return tostring(c.text or ''), 'Done', 100 end
  return tostring(c.text or ''), string.format('%d / %d', progress, target), math.floor(progress * 100 / target)
end

-- the tier rows of a season arrive in parts: cache = {season, total, rows = {[tier] = row}}; returns the cache and
-- true once every tier is there
function PassView.mergeTiers(cache, msg)
  if type(msg) ~= 'table' then return cache, false end
  if not cache or cache.season ~= msg.season then
    cache = { season = msg.season, total = tonumber(msg.total) or 0, rows = {} }
  end
  for _, r in ipairs(type(msg.rows) == 'table' and msg.rows or {}) do
    if tonumber(r.tier) then cache.rows[tonumber(r.tier)] = r end
  end
  local complete = cache.total > 0
  for t = 1, cache.total do
    if not cache.rows[t] then complete = false end
  end
  return cache, complete
end

return PassView
