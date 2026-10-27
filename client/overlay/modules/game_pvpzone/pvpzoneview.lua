-- The Scorched Marches: pure helpers of the window, the entry confirmation and the HUD (no widgets; pvpzoneview_test.lua).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
PvpZoneView = {}
local V = PvpZoneView

local floor = math.floor

function V.clock(s)
  s = math.max(0, floor(tonumber(s) or 0))
  if s >= 3600 then
    return string.format('%d:%02d:%02d', floor(s / 3600), floor(s % 3600 / 60), s % 60)
  end
  return string.format('%d:%02d', floor(s / 60), s % 60)
end

function V.number(n)
  local s = tostring(floor(tonumber(n) or 0))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''):gsub('^%-,', '-'))
end

function V.span(s)
  s = math.max(0, floor(tonumber(s) or 0))
  if s < 60 then return s .. 's' end
  if s < 3600 then return floor(s / 60) .. 'm' end
  local h, m = floor(s / 3600), floor(s % 3600 / 60)
  return m > 0 and string.format('%dh %dm', h, m) or (h .. 'h')
end

-- the embers line: "Embers 1,250 / 2,500"
function V.embersLine(d)
  return string.format('Embers %s / %s', V.number(d.embers), V.number(d.cap))
end

-- 0..100: how full the carry is, and the bar colour (gold, then hot when nearly full)
function V.carryPercent(d)
  local cap = tonumber(d.cap) or 0
  if cap <= 0 then return 0, '#e8a040' end
  local p = math.min(100, floor((tonumber(d.embers) or 0) * 100 / cap))
  return p, p >= 90 and '#ff5a2a' or '#e8a040'
end

-- the shrine line of the HUD and the window, and its colour
function V.contestLine(c)
  c = c or {}
  local phase = c.phase
  if phase == 'warden' then
    return tr('Shrine Warden %s- %s left', c.warden and string.format('%d%% ', c.warden) or '',
      V.clock(c.left)), '#ff7040'
  elseif phase == 'capture' then
    if c.contested then
      return tr('Shrine: CONTESTED - %s left', V.clock(c.left)), '#ff4030'
    end
    local lead = c.progress and c.progress[1]
    if lead then
      return string.format('Shrine: %s %d%% - %s left', lead.short or lead.name, lead.pct or 0, V.clock(c.left)), lead.color or '#f6cf72'
    end
    return tr('Shrine: open, take it! - %s left', V.clock(c.left)), '#f6cf72'
  end
  return tr('Shrine contest in %s', V.clock(c.left)), '#b8ab92'
end

-- who holds the shrine: text, colour
function V.holderLine(c)
  local h = c and c.holder
  if not h then
    return tr('Nobody holds the Cinder Shrine'), '#8c8070'
  end
  return tr('%s hold the shrine (%s)', h.short or h.name, V.span(h.left)), h.color or '#f6cf72'
end

function V.pledgeLine(p)
  if not p then
    return tr('Not pledged: no reputation, no shrine'), '#8c8070'
  end
  return tr('Fighting for %s', (p.name or p.key)), p.color or '#d6c9ae'
end

-- the status line under the bars: protection, the exit channel, piles around
function V.statusLine(d)
  if tonumber(d.exit) then
    return tr('Leaving... %d%% (do not fight)', d.exit), '#9fd89f'
  end
  if (tonumber(d.protect) or 0) > 0 then
    return tr('Protected for %ds', d.protect), '#8fb8ff'
  end
  if (tonumber(d.piles) or 0) > 0 then
    return tr('%s embers lie on the ground', V.number(d.piles)), '#e8a040'
  end
  return tr('Bank your embers at a safe exit'), '#8c8070'
end

-- the entry button of the window: text, enabled, tooltip
function V.enterButton(s)
  if s.inside then
    return 'Inside', false, tr('Leave through a safe exit to bank your embers.')
  end
  if not s.canEnter then
    return 'Enter', false, s.why or ''
  end
  return tr('Enter the Marches'), true, tr('Opens the rules and the confirmation first.')
end

-- the confirmation: may the player confirm? (the box ticked, and for a Hardcore character the second box)
function V.canConfirm(s, accepted, hcAccepted)
  if not accepted then return false end
  if s and s.hc and s.hc.isHc then
    return s.hc.allow == true and hcAccepted == true
  end
  return true
end

-- the risk text of the confirmation (one block)
function V.riskText(s)
  local lines = {}
  for _, r in ipairs(s.rules or {}) do lines[#lines + 1] = '- ' .. r end
  lines[#lines + 1] = tr('You carry %s embers now. A defeat drops them all; your killer may take up to %s of them.',
    V.number(s.carried), V.number(s.pickup and s.pickup.perKill or 0))
  if s.hc and s.hc.isHc then
    lines[#lines + 1] = s.hc.allow and tr('HARDCORE: a defeat here may end your Hardcore run.') or
      tr('HARDCORE: Hardcore characters cannot enter the Marches.')
  end
  return table.concat(lines, '\n')
end

-- a faction pledge row: text, button text, enabled, tooltip
function V.factionRow(f, s)
  local rival = (f.rivalName or f.rival) and (tr('sworn rival: %s', (f.rivalName or f.rival))) or ''
  if f.pledged then
    local wait = tonumber(s.pledgeChangeIn) or 0
    return f.name, 'Pledged', false, wait > 0 and (tr('You can change in %s', V.span(wait))) or rival
  end
  return f.name, 'Pledge', f.can == true, f.why or rival
end

-- a vendor row: sub text, button text, enabled
function V.vendorRow(o, banked)
  local sub
  if o.weekly then
    sub = tr('%d of %d this week', o.bought or 0, o.weekly)
  elseif o.kind == 'cosmetic' then
    sub = 'Cosmetic, account-wide'
  else
    sub = 'Consumable'
  end
  if o.owned then
    return sub, 'Owned', false
  end
  return sub, V.number(o.cost) .. ' embers', o.can == true and (tonumber(banked) or 0) >= (tonumber(o.cost) or 0)
end

function V.recordLine(s)
  return tr('Banked %s (this week %s, all time %s)   Defeats dealt %s, taken %s   Shrines %s',
    V.number(s.banked), V.number(s.weekBanked), V.number(s.total), V.number(s.kills), V.number(s.defeats), V.number(s.captures))
end

-- ---------------------------------------------------------------- how it works, the goal and the map marks
-- the four numbered steps at the top of the window
function V.steps(s)
  s = s or {}
  local list = {
    tr('Pledge to a faction in this window, outside the zone. Pledged players earn reputation and can take the shrine.'),
    tr('Enter from a protection zone. Kill monsters and rival players: every kill gives embers, which you carry (at most %s).',
      V.number(s.carryMax or 2500)),
    tr('Carried embers are at risk. If you are defeated you drop them all and your killer may take up to %s. Equipment and experience are never lost.',
      V.number(s.pickup and s.pickup.perKill or 800)),
    tr('Bank them: stand %ds in a white safe-exit circle without fighting (the circles are marked on your map). Banked embers are safe and buy orbs, potions and cosmetics from the vendor below.',
      s.exitSeconds or 5),
  }
  for i, text in ipairs(list) do
    list[i] = string.format('%d. %s', i, text)
  end
  return list
end

local KINDS = { exit = true, shrine = true }
local ICON = { exit = 0, shrine = 0 }
V.ICON = ICON

-- the marks the server sends on entering: only exits and the shrine, with numbers and a name, at most 8
function V.cleanMarks(list)
  local out = {}
  if type(list) ~= 'table' then return out end
  for _, m in ipairs(list) do
    if type(m) == 'table' and KINDS[m.kind] and tonumber(m.x) and tonumber(m.y) and tonumber(m.z) and #out < 8 then
      out[#out + 1] = { kind = m.kind, x = floor(m.x), y = floor(m.y), z = floor(m.z), name = tostring(m.name or '') }
    end
  end
  return out
end

-- distance (the larger of the two axes) and the compass sector from one position to another: 'n', 'ne', ... or nil
-- when standing on it. Plain integer comparisons, no trigonometry.
function V.compass(from, to)
  local dx, dy = to.x - from.x, to.y - from.y
  local ax, ay = math.abs(dx), math.abs(dy)
  local dist = math.max(ax, ay)
  if dist == 0 then return 0, nil end
  local ns = dy < 0 and 'n' or 's'
  local ew = dx > 0 and 'e' or 'w'
  if ay * 2 <= ax then return dist, ew end
  if ax * 2 <= ay then return dist, ns end
  return dist, ns .. ew
end

-- "23 tiles north-east"
function V.whereText(dist, dir)
  dist = floor(tonumber(dist) or 0)
  if not dir then return tr('you are here') end
  if dir == 'n' then return tr('%d tiles north', dist) end
  if dir == 'ne' then return tr('%d tiles north-east', dist) end
  if dir == 'e' then return tr('%d tiles east', dist) end
  if dir == 'se' then return tr('%d tiles south-east', dist) end
  if dir == 's' then return tr('%d tiles south', dist) end
  if dir == 'sw' then return tr('%d tiles south-west', dist) end
  if dir == 'w' then return tr('%d tiles west', dist) end
  return tr('%d tiles north-west', dist)
end

-- the nearest mark of a kind on the player's floor: mark, text; nil when there is none
function V.nearest(marks, kind, pos)
  local best, bd, bdir
  for _, m in ipairs(marks or {}) do
    if m.kind == kind and pos and m.z == pos.z then
      local d, dir = V.compass(pos, m)
      if not bd or d < bd then best, bd, bdir = m, d, dir end
    end
  end
  if not best then return nil end
  return best, V.whereText(bd, bdir)
end

-- the objective lines of the HUD (what to do now): a list of { text, color }. exitWhere / shrineWhere: "23 tiles north"
-- or nil. d is the server's HUD data.
function V.goalLines(d, exitWhere, shrineWhere)
  d = d or {}
  local lines = {}
  local carried = tonumber(d.embers) or 0
  if tonumber(d.exit) then
    lines[1] = { tr('Leaving... hold still, do not fight. Your %s embers are banked when the bar is full.', V.number(carried)), '#9fd89f' }
    return lines
  end
  if carried > 0 then
    if exitWhere then
      lines[1] = { tr('Embers carried: %s. Bank them at the nearest safe exit (%s, marked on your map) before you are defeated.',
        V.number(carried), exitWhere), '#f6cf72' }
    else
      lines[1] = { tr('Embers carried: %s. Bank them at a safe exit (marked on your map) before you are defeated.',
        V.number(carried)), '#f6cf72' }
    end
  else
    lines[1] = { tr('Goal: kill monsters and rival players for embers, then bank them at a safe exit (marked on your map).'),
      '#b8ab92' }
  end
  local c = d.contest or {}
  local pledged = d.pledge ~= nil
  if c.phase == 'warden' then
    lines[2] = { shrineWhere and tr('Shrine event: slay the Shrine Warden at the shrine (%s, marked on your map).', shrineWhere)
      or tr('Shrine event: slay the Shrine Warden at the shrine (marked on your map).'), '#ff7040' }
  elseif c.phase == 'capture' then
    if pledged then
      lines[2] = { shrineWhere and tr('Shrine event: stand in the shrine circle with your faction to take it (%s, marked on your map).', shrineWhere)
        or tr('Shrine event: stand in the shrine circle with your faction to take it (marked on your map).'), '#ff7040' }
    else
      lines[2] = { tr('Shrine event: only players pledged to a faction can take the shrine.'), '#8c8070' }
    end
  end
  return lines
end

return V
