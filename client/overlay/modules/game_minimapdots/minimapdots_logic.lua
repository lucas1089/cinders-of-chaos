-- game_minimapdots, the rules without client API (tested by minimapdots_logic_test.lua).
-- The server (radar.lua, action `radar` of extended opcode 153) sends the creatures within the radius as [[x, y, f], ...] with the
-- floor z and the radius r; f bits: 1 boss, 2 NPC, 4 party member, 0 monster. The module draws one dot per entry on the minimap.
MinimapDotsLogic = {}
local L = MinimapDotsLogic

L.OPCODE = 153
L.OPTION = 'minimapRadar'
L.MAX_DOTS = 400
L.BOSS, L.NPC, L.PARTY = 1, 2, 4
L.STALE_MS = 15000   -- a list older than this is hidden (the server sends again whenever something changed; a quiet place keeps its list)
L.CHECK_MS = 2000    -- how often the module looks whether the radar should be on (window shown, option, online)
L.WALK_MS = 40       -- the dots follow the smooth scroll of the map every this many ms while the player walks

-- the option as a switch: a missing value (no settings module, no saved choice) counts as on
function L.isOn(value)
  return value ~= false
end

-- should the client ask the server for the radar now?
function L.wantRadar(optionOn, windowVisible, online)
  return optionOn == true and windowVisible == true and online == true
end

local function int(v)
  if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then return nil end
  return math.floor(v)
end

-- the server message data -> {z, r, dots = [{x, y, kind}]}; bad entries are dropped, the list is cut at MAX_DOTS
function L.decode(data)
  if type(data) ~= 'table' then return nil end
  local z = int(data.z)
  if not z or z < 0 or z > 15 then return nil end
  local out = { z = z, r = int(data.r) or 0, dots = {} }
  local m = type(data.m) == 'table' and data.m or {}
  for i = 1, math.min(#m, L.MAX_DOTS) do
    local e = m[i]
    if type(e) == 'table' then
      local x, y, f = int(e[1]), int(e[2]), int(e[3]) or 0
      if x and y and x >= 0 and y >= 0 and x < 65536 and y < 65536 then
        out.dots[#out.dots + 1] = { x = x, y = y, kind = L.kindOf(f) }
      end
    end
  end
  return out
end

-- the kind of a flag value: boss wins over party over NPC over monster
function L.kindOf(f)
  f = int(f) or 0
  if math.floor(f / L.BOSS) % 2 == 1 then return 'boss' end
  if math.floor(f / L.PARTY) % 2 == 1 then return 'party' end
  if math.floor(f / L.NPC) % 2 == 1 then return 'npc' end
  return 'monster'
end

-- the colours: red monster, red with a gold ring for a boss, green party, blue NPC, white you (with a dark edge so a dot
-- reads on any ground)
L.COLORS = {
  monster = { fill = '#ff1e1e', edge = '#000000', shine = '#ffbeb4' },
  boss = { fill = '#be0f0f', edge = '#ffd646' },
  party = { fill = '#46e15a', edge = '#002800' },
  npc = { fill = '#5096ff', edge = '#000000', shine = '#d2e6ff' },
  self = { fill = '#ffffff', edge = '#000000' },
}

-- size in px and ring width for a kind at a zoom (scale = px per tile). Owner 2026-11-13 (option C of the preview): a monster
-- or NPC dot is a bright square with a 1 px black edge and a light pixel in its top left corner, so it reads on any ground
-- (the edge is drawn inside the widget, so the dot is the fill plus 2 px). At 1 px per tile or less the fill is 2 x 2 (4 px
-- with the edge), the boss 6 x 6 with a 1 px gold ring, you and the party 4 x 4 with a dark ring; from 2 px per tile up the
-- fill grows with the zoom (3 px at 2, 4 at 4, 6 at 8, at most 9); a boss is 3 px bigger with a 2 px gold ring, you and the
-- party one px bigger with a 1 px ring. `shine` is the colour of the corner pixel (nil: none).
function L.style(kind, scale)
  scale = tonumber(scale) or 1
  local c = L.COLORS[kind] or L.COLORS.monster
  local size, ring
  if scale < 1.5 then
    if kind == 'monster' or kind == 'npc' then
      size, ring = 2, 0
    elseif kind == 'boss' then
      size, ring = 6, 1
    else
      size, ring = 4, 1
    end
  else
    size = math.max(3, math.min(9, math.floor(0.5 * scale + 2)))
    ring = size >= 5 and 1 or 0
    if kind == 'boss' then
      size, ring = size + 3, 2
    elseif kind == 'self' or kind == 'party' then
      size, ring = size + 1, 1
    end
  end
  local shine
  if L.COLORS[kind] == nil or kind == 'monster' or kind == 'npc' then
    size, ring, shine = size + 2, 1, c.shine
  end
  return { size = size, ring = ring, fill = c.fill, edge = c.edge, shine = shine }
end

-- the order the dots are drawn in (later over earlier): NPCs, monsters, party, bosses, you
L.DRAW_ORDER = { 'npc', 'monster', 'party', 'boss', 'self' }

-- which kinds the options show: monsters and bosses are the option itself, NPCs and party follow
function L.shows(kind, settings)
  settings = settings or {}
  if kind == 'npc' then return settings.npcs ~= false end
  if kind == 'party' then return settings.party ~= false end
  return true
end

-- the top left corner of a dot of `size` px whose centre is at (cx, cy)
function L.corner(cx, cy, size)
  return math.floor(cx - size / 2 + 0.5), math.floor(cy - size / 2 + 0.5)
end

-- is the point inside the minimap's drawing rectangle {x, y, width, height}, with `pad` px of room for the dot?
function L.inside(px, py, rect, pad)
  pad = pad or 0
  return px >= rect.x - pad and py >= rect.y - pad and px < rect.x + rect.width + pad and py < rect.y + rect.height + pad
end

-- a list the client holds: still good at now? (floor of the camera, age)
function L.fresh(state, camZ, now)
  if not state or state.z ~= camZ then return false end
  return (now - (state.at or 0)) <= L.STALE_MS
end

-- one line for the log / the module's status
function L.summary(state)
  if not state then return 'no radar list' end
  local n = { monster = 0, boss = 0, party = 0, npc = 0 }
  for _, d in ipairs(state.dots) do n[d.kind] = (n[d.kind] or 0) + 1 end
  return 'radar: ' .. n.monster .. ' monsters, ' .. n.boss .. ' bosses, ' .. n.party .. ' party, ' .. n.npc .. ' NPCs on floor ' .. state.z
end
