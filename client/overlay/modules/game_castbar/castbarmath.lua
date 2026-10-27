-- Pure parts of game_castbar (castbarmath_test.lua): progress, texts, colours and where a bar goes over a creature.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
CastbarMath = {}
local M = CastbarMath

M.RESULT_TEXT = {
  moved = 'Interrupted: moved', paralysed = 'Interrupted: paralysed', died = 'Interrupted', logout = 'Interrupted',
  spell = 'Interrupted: new spell', portal = 'Interrupted: portal', cancel = 'Cancelled',
  failed = 'Failed', hit = 'Interrupted: hit', refused = 'Refused',
}
M.COLOR = { casting = '#c08a2a', done = '#d8b04a', interrupted = '#8a1a1a', portal = '#4a6ad0' }

-- 0..1 of a cast that started at startMs and lasts ms
function M.progress(startMs, ms, nowMs)
  ms = tonumber(ms) or 0
  if ms <= 0 then return 1 end
  local p = ((tonumber(nowMs) or 0) - (tonumber(startMs) or 0)) / ms
  if p < 0 then return 0 end
  if p > 1 then return 1 end
  return p
end

-- "Doomtide  0.8s" (time left, one decimal)
function M.label(name, ms, elapsed)
  local left = math.max(0, (tonumber(ms) or 0) - (tonumber(elapsed) or 0)) / 1000
  return string.format('%s  %.1fs', tostring(name or ''), left)
end

function M.resultText(result)
  if result == 'done' then return nil end
  return tr(M.RESULT_TEXT[result] or 'Interrupted') -- run-time keys of pt_br.lua
end

-- size of one map tile on screen: rect {x, y, width, height} of the map widget, visible dimension {width, height}
function M.tileSize(rect, vd, keepAspect)
  if not rect or not vd or (vd.width or 0) <= 0 or (vd.height or 0) <= 0 then return 32, 32 end
  local w, h = rect.width / vd.width, rect.height / vd.height
  if keepAspect then
    local s = math.min(w, h)
    return s, s
  end
  return w, h
end

-- top left of a bar (barW x barH) over the creature dx, dy tiles away from the local player (who is drawn in the middle
-- of the map widget); `lift` tiles above the creature's tile centre. nil when that is outside the map widget.
function M.place(rect, vd, keepAspect, dx, dy, barW, barH, lift)
  local tw, th = M.tileSize(rect, vd, keepAspect)
  local cx = rect.x + rect.width / 2 + (dx or 0) * tw
  local cy = rect.y + rect.height / 2 + (dy or 0) * th
  local x = math.floor(cx - barW / 2)
  local y = math.floor(cy - (lift or 1) * th - barH)
  if x + barW < rect.x or x > rect.x + rect.width or y + barH < rect.y or y > rect.y + rect.height then
    return nil
  end
  return x, y
end

-- a server message, checked: {action, data} with the fields each action needs, or nil
function M.parse(msg)
  if type(msg) ~= 'table' or type(msg.action) ~= 'string' then return nil end
  local d = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'start' then
    local ms = tonumber(d.ms)
    if not ms or ms <= 0 then return nil end
    return { action = 'start', serial = tonumber(d.s) or 0, name = tostring(d.n or ''), ms = math.min(ms, 60000) }
  elseif msg.action == 'end' then
    return { action = 'end', serial = tonumber(d.s) or 0, result = tostring(d.r or 'done'), text = d.t }
  elseif msg.action == 'other' then
    local cid, ms = tonumber(d.c), tonumber(d.ms)
    if not cid or not ms or ms <= 0 then return nil end
    return { action = 'other', cid = cid, name = tostring(d.n or ''), ms = math.min(ms, 60000) }
  elseif msg.action == 'otherEnd' then
    local cid = tonumber(d.c)
    if not cid then return nil end
    return { action = 'otherEnd', cid = cid, result = tostring(d.r or 'done') }
  end
  return nil
end
