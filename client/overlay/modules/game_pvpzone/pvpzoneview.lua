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

return V
