-- Text helpers of the arena module (no client API, tested by arenatext_test.lua with plain Lua).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
ArenaText = {}

-- 75 -> "1:15", negative -> "0:00"
function ArenaText.clock(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

-- +12 / -8 / +0
function ArenaText.delta(d)
  d = math.floor(tonumber(d) or 0)
  return (d >= 0 and '+' or '') .. tostring(d)
end

ArenaText.RESULT_TEXT = { win = 'VICTORY', loss = 'DEFEAT', draw = 'DRAW' }
ArenaText.RESULT_COLOR = { win = '#f6cf72', loss = '#e03a1e', draw = '#d6c9ae' }

function ArenaText.result(r)
  return ArenaText.RESULT_TEXT[r] or tostring(r or '?'):upper(), ArenaText.RESULT_COLOR[r] or '#d6c9ae'
end

ArenaText.MODE_TITLE = { ['1v1'] = 'Duel 1v1', ['2v2'] = 'Team 2v2', ['3v3'] = 'Warband 3v3' }

-- the PvP season line of a mode card: tier and season rating, or the placement progress
function ArenaText.seasonLine(v, seasonId)
  if type(v) ~= 'table' then
    return '', '#8c8070', ''
  end
  local tip = tr('PvP Season %d rating %d (%d matches).', tonumber(seasonId) or 1, tonumber(v.rating) or 1500,
    tonumber(v.matches) or 0)
  if not v.placed then
    local total = (tonumber(v.matches) or 0) + (tonumber(v.placementLeft) or 0)
    return tr('Season: placement %d/%d', tonumber(v.matches) or 0, total), '#8c8070', tip
  end
  return tr('Season: %s %d', v.tierName or '?', tonumber(v.rating) or 1500), v.color or '#d6c9ae', tip
end

-- the season part of the result toast
function ArenaText.seasonDelta(s)
  if type(s) ~= 'table' then return '' end
  local text = tr('Season %d -> %d (%s)', tonumber(s.before) or 0, tonumber(s.after) or 0, ArenaText.delta(s.delta))
  if s.placed and s.tierName then
    text = text .. ' ' .. s.tierName
  elseif not s.placed then
    text = text .. tr(', placement: %d left', tonumber(s.placementLeft) or 0)
  end
  return text
end


-- "Rating 1000 -> 1020 (+20)"
function ArenaText.ratingLine(before, after, delta)
  return tr('Rating %d -> %d (%s)', tonumber(before) or 0, tonumber(after) or 0, ArenaText.delta(delta))
end

-- record "12-4-1" (wins-losses-draws)
function ArenaText.record(r)
  r = type(r) == 'table' and r or {}
  return string.format('%d-%d-%d', tonumber(r.wins) or 0, tonumber(r.losses) or 0, tonumber(r.draws) or 0)
end

-- how long ago (seconds) -> "just now", "5m ago", "3h ago", "2d ago"
function ArenaText.ago(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  if seconds < 60 then return tr('just now') end
  if seconds < 3600 then return math.floor(seconds / 60) .. 'm ago' end
  if seconds < 86400 then return math.floor(seconds / 3600) .. 'h ago' end
  return math.floor(seconds / 86400) .. 'd ago'
end

ArenaText.REASON_TEXT = {
  defeat = 'knock-out', timeout = 'time ran out', defeated = 'knocked out', left = 'left the match',
  secure = 'secure mode on', mc = 'multi-client', stop = 'stopped'
}

function ArenaText.reason(r)
  return ArenaText.REASON_TEXT[r] or tostring(r or '')
end

-- HUD centre text: countdown seconds, fight clock or the end
function ArenaText.hudCenter(phase, left)
  if phase == 'countdown' then
    return tostring(math.max(0, math.floor(tonumber(left) or 0))), tr('starts in')
  elseif phase == 'fight' then
    return ArenaText.clock(left), 'fight'
  end
  return '-', 'over'
end

-- health bar colour by percent
function ArenaText.hpColor(pct)
  pct = tonumber(pct) or 0
  if pct > 60 then return '#2f7a2a' end
  if pct > 30 then return '#b07a10' end
  return '#8a1010'
end

return ArenaText
