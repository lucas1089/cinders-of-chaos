-- Pure helpers of the party frames (no client calls; tested by partymath_test.lua): applying the server's state, the
-- flags, the text of the bars, the floor / distance marks, the class names and colours, the order of the frames, the
-- settings and the layout numbers.
--
-- Server state (extended opcode 235, partyframes_core.lua): {leader = id, members = [entry]}, members empty = no party.
-- entry {i id, n name, lv level, vc vocation id, h health, H max health, m mana, M max mana, p health percent,
--   dz floors (down is +), d squares (in range only), far 1 (out of range: only p, dz), f flags, o outfit {t,h,b,l,f,a},
--   b [{i icon, t 0 buff / 1 debuff, l ms left}]}

PartyMath = {}

PartyMath.FLAG = { leader = 1, fight = 2, dead = 4, offline = 8, self = 16 }
PartyMath.STALE = 4.5 -- seconds without a state: the connection to the server is in doubt (it repeats every 2 s)
PartyMath.SCALE_MIN, PartyMath.SCALE_MAX, PartyMath.SCALE_STEP = 70, 150, 10
PartyMath.FRAME_W, PartyMath.FRAME_H, PartyMath.BUFF_H = 200, 44, 16

PartyMath.DEFAULTS = { scale = 100, locked = false, shown = true, showSelf = false, showBuffs = true, showNumbers = true, follow = true }

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

local function num(v)
  v = tonumber(v)
  if v ~= v then return nil end
  return v
end

function PartyMath.sanitize(node)
  node = type(node) == 'table' and node or {}
  local d = PartyMath.DEFAULTS
  local s = {}
  local scale = num(node.scale)
  s.scale = scale and clamp(math.floor(scale / PartyMath.SCALE_STEP + 0.5) * PartyMath.SCALE_STEP, PartyMath.SCALE_MIN, PartyMath.SCALE_MAX) or d.scale
  for _, k in ipairs({ 'locked', 'shown', 'showSelf', 'showBuffs', 'showNumbers', 'follow' }) do
    if type(node[k]) == 'boolean' then s[k] = node[k] else s[k] = d[k] end
  end
  local x, y = num(node.x), num(node.y)
  if x and y then s.x, s.y = math.floor(x), math.floor(y) end
  return s
end

-- a position that keeps a panel of w x h inside a parent of pw x ph (at least `keep` pixels of it stay visible)
function PartyMath.clampPosition(x, y, w, h, pw, ph, keep)
  keep = keep or 24
  return clamp(x, keep - w, math.max(keep - w, pw - keep)), clamp(y, 0, math.max(0, ph - math.min(h, keep)))
end

-- The default spot (no position saved): the right edge of the free part of the game view (free {x, y, width, height}
-- on screen: the map panel without the side panels and the console / action bars), below the map overlay's corner box
-- (game_mapoverlay cornerRect: 36% of the free height, 140..320, 8 px from the top) and the toasts, above its control
-- strip (44 px, 8 px from the bottom). The rift / invasion HUDs and the character plate are top left, so none of them
-- is under the frames at 1280x720 and up. A party too tall for the space moves up so it stays above the strip (at
-- 1280x720 four frames with buffs then cover the lower 14 px of the corner box, which only the "corner" mode shows).
-- Returns the margins inside the parent at (px, py).
PartyMath.DEFAULT_GAP = 8
PartyMath.STRIP_H = 44
function PartyMath.defaultPosition(free, w, h, px, py)
  local gap = PartyMath.DEFAULT_GAP
  local boxH = math.floor(clamp(free.height * 0.36, 140, 320))
  local x = free.x + free.width - w - gap
  local y = free.y + gap + boxH + 6
  local stripTop = free.y + free.height - PartyMath.STRIP_H - gap
  if y + h > stripTop - 6 then
    y = math.max(free.y + gap, stripTop - 6 - h)
  end
  return math.floor(x - (px or 0)), math.floor(y - (py or 0))
end

-- the free part of the game view: the map panel's rect cut to the window, without the side panel(s) on the right /
-- left half and the bottom panels. rect {x, y, width, height}; win {width, height}; side and bottom: lists of rects
-- (a panel that starts above the window, the extended view, loses its top 40 px to the top menu, as in game_mapoverlay)
function PartyMath.freeArea(rect, win, sides, bottoms)
  local x1, y1 = math.max(0, rect.x), math.max(0, rect.y)
  if rect.y < 0 then y1 = math.max(y1, 40) end
  local x2, y2 = math.min(win.width, rect.x + rect.width), math.min(win.height, rect.y + rect.height)
  for _, r in ipairs(sides or {}) do
    if r.width > 0 then
      if r.x >= win.width / 2 then x2 = math.min(x2, r.x)
      elseif r.x + r.width <= win.width / 2 then x1 = math.max(x1, r.x + r.width) end
    end
  end
  for _, r in ipairs(bottoms or {}) do
    if r.height > 0 and r.y > win.height / 2 then y2 = math.min(y2, r.y) end
  end
  return { x = x1, y = y1, width = math.max(0, x2 - x1), height = math.max(0, y2 - y1) }
end

function PartyMath.stepScale(scale, dir)
  return clamp((scale or 100) + dir * PartyMath.SCALE_STEP, PartyMath.SCALE_MIN, PartyMath.SCALE_MAX)
end

-- ------------------------------------------------------------------ the state
local function memberFrom(e, now)
  if type(e) ~= 'table' then return nil end
  local id = num(e.i)
  if not id or type(e.n) ~= 'string' or e.n == '' then return nil end
  local m = {
    id = id, name = e.n, level = math.floor(num(e.lv) or 0), voc = math.floor(num(e.vc) or 0),
    pct = clamp(math.floor(num(e.p) or 0), 0, 100), dz = math.floor(num(e.dz) or 0),
    far = e.far == 1, flags = math.floor(num(e.f) or 0), outfit = nil, buffs = {},
  }
  if not m.far then
    m.hp, m.hpMax = num(e.h) or 0, num(e.H) or 0
    m.mp, m.mpMax = num(e.m) or 0, num(e.M) or 0
    m.dist = num(e.d)
  end
  if type(e.o) == 'table' then
    m.outfit = { type = num(e.o.t) or 0, head = num(e.o.h) or 0, body = num(e.o.b) or 0, legs = num(e.o.l) or 0,
      feet = num(e.o.f) or 0, addons = num(e.o.a) or 0 }
  end
  for _, b in ipairs(type(e.b) == 'table' and e.b or {}) do
    if type(b) == 'table' and type(b.i) == 'string' then
      local left = num(b.l)
      m.buffs[#m.buffs + 1] = { icon = b.i, debuff = b.t == 1, endAt = left and (now + left / 1000) or nil,
        name = type(b.n) == 'string' and b.n:sub(1, 40) or nil }
    end
  end
  return m
end

-- applies a state message; `state` = {members = {}, leader = id, at = seconds}. Returns true when it changed
function PartyMath.apply(state, data, now)
  data = type(data) == 'table' and data or {}
  local list = {}
  for _, e in ipairs(type(data.members) == 'table' and data.members or {}) do
    local m = memberFrom(e, now)
    if m then list[#list + 1] = m end
  end
  state.members = list
  state.leader = num(data.leader)
  state.at = now
  return true
end

function PartyMath.clear(state)
  state.members, state.leader, state.at = {}, nil, nil
end

function PartyMath.inParty(state)
  return #(state.members or {}) > 0
end

-- the members to draw: the viewer's own frame only when asked for
function PartyMath.visible(state, showSelf)
  local out = {}
  for _, m in ipairs(state.members or {}) do
    if showSelf or not PartyMath.flag(m, 'self') then out[#out + 1] = m end
  end
  return out
end

function PartyMath.flag(m, name)
  local bit = PartyMath.FLAG[name]
  return bit ~= nil and math.floor((m.flags or 0) / bit) % 2 == 1
end

function PartyMath.stale(state, now)
  return state.at ~= nil and now - state.at > PartyMath.STALE
end

-- true when the viewer is the leader of the party
function PartyMath.viewerIsLeader(state)
  for _, m in ipairs(state.members or {}) do
    if PartyMath.flag(m, 'self') then return PartyMath.flag(m, 'leader') end
  end
  return false
end

-- ------------------------------------------------------------------ texts and marks
local function short(n)
  n = math.floor(n or 0)
  if n >= 10000000 then return string.format('%.1fm', n / 1000000) end
  if n >= 100000 then return string.format('%dk', math.floor(n / 1000)) end
  return tostring(n)
end
PartyMath.short = short

-- "1234 / 2000" in range; "~50%" far
function PartyMath.hpText(m)
  if m.far then return '~' .. m.pct .. '%' end
  return short(m.hp) .. ' / ' .. short(m.hpMax)
end

function PartyMath.mpText(m)
  if m.far then return '' end
  return short(m.mp) .. ' / ' .. short(m.mpMax)
end

function PartyMath.mpPct(m)
  if m.far or (m.mpMax or 0) <= 0 then return 0 end
  return clamp(math.floor(m.mp * 100 / m.mpMax + 0.5), 0, 100)
end

-- health bar colour by percent
function PartyMath.hpColor(pct)
  if pct > 60 then return '#3a9a48' end
  if pct > 30 then return '#c2a024' end
  return '#c0281e'
end

-- 'up' / 'down' with the number of floors, or nil on the same floor
function PartyMath.floorMark(dz)
  if not dz or dz == 0 then return nil end
  if dz < 0 then return 'up', -dz end
  return 'down', dz
end

-- the text beside the marks: squares in range, "far" out of range, nothing for yourself
function PartyMath.distanceText(m)
  if PartyMath.flag(m, 'self') then return '' end
  if m.far then return 'far' end
  if m.dist == nil then return '' end
  return math.floor(m.dist) .. ' sq'
end

-- the one state word to show on a frame (the most important first), or nil
function PartyMath.stateWord(m, stale)
  if stale or PartyMath.flag(m, 'offline') then return 'offline' end
  if PartyMath.flag(m, 'dead') then return 'dead' end
  if PartyMath.flag(m, 'fight') then return 'fight' end
  return nil
end

-- vocation id -> {name, colour}; the lines share a colour
local LINES = {
  { '#d9743a', { [4] = 'Warrior', [8] = 'Juggernaut', [14] = 'Berserker' } },
  { '#6fbf5a', { [3] = 'Ranger', [7] = 'Deadeye', [15] = 'Beastmaster' } },
  { '#5a9be0', { [1] = 'Mystic', [5] = 'Elementalist', [10] = 'Illusionist' } },
  { '#a77be0', { [11] = 'Thief', [12] = 'Ninja', [13] = 'Samurai' } },
  { '#e0b84a', { [17] = 'Monk', [18] = 'Shadowfist', [19] = 'Iron Sage' } },
  { '#4fc2b0', { [20] = 'Necromancer', [21] = 'Lich', [22] = 'Bone Lord' } },
  { '#f0e0a0', { [23] = 'Templar', [24] = 'Inquisitor', [25] = 'Sentinel' } },
}
function PartyMath.vocation(id)
  for _, line in ipairs(LINES) do
    local name = line[2][id]
    if name then return name, line[1] end
  end
  return 'Adventurer', '#9a9088'
end

-- ------------------------------------------------------------------ layout
function PartyMath.scaled(px, scale)
  return math.floor(px * clamp(scale or 100, PartyMath.SCALE_MIN, PartyMath.SCALE_MAX) / 100 + 0.5)
end

-- the height of one frame
function PartyMath.frameHeight(m, settings)
  local h = PartyMath.FRAME_H
  if settings.showBuffs and not m.far and #m.buffs > 0 then h = h + PartyMath.BUFF_H end
  return PartyMath.scaled(h, settings.scale)
end

-- the y of each frame in a column and the total height: {ys, total}
function PartyMath.column(members, settings, headerH, gap)
  local ys, y = {}, headerH + gap
  for i, m in ipairs(members) do
    ys[i] = y
    y = y + PartyMath.frameHeight(m, settings) + gap
  end
  return ys, y
end

function PartyMath.tooltip(m, now)
  local voc = PartyMath.vocation(m.voc)
  local lines = { m.name .. '  Lv ' .. m.level .. '  ' .. voc }
  if m.far then
    lines[#lines + 1] = 'Far away: about ' .. m.pct .. '% health'
  else
    lines[#lines + 1] = 'Health ' .. math.floor(m.hp) .. ' / ' .. math.floor(m.hpMax)
    lines[#lines + 1] = 'Mana ' .. math.floor(m.mp) .. ' / ' .. math.floor(m.mpMax)
  end
  local dir, n = PartyMath.floorMark(m.dz)
  if dir then lines[#lines + 1] = n .. (n == 1 and ' floor ' or ' floors ') .. (dir == 'up' and 'above you' or 'below you') end
  if PartyMath.flag(m, 'leader') then lines[#lines + 1] = 'Party leader' end
  if PartyMath.flag(m, 'fight') then lines[#lines + 1] = 'In a fight' end
  if PartyMath.flag(m, 'dead') then lines[#lines + 1] = 'Dead' end
  if PartyMath.flag(m, 'offline') then lines[#lines + 1] = 'Connection lost' end
  -- the names of the buffs under the frame (the icons themselves take no mouse): a Templar's aura, a stun ...
  local names = {}
  for _, b in ipairs(m.buffs or {}) do
    if b.name and b.name ~= '' then names[#names + 1] = b.name end
  end
  if #names > 0 then lines[#lines + 1] = table.concat(names, ', ') end
  return table.concat(lines, '\n')
end
