-- Chest auras and the Templar foot aura: the rules without client API (tested by chestaura_test.lua with luajit and lua5.3).
-- Pictures: client/tools/gen_aura_art.py (the counts, sizes and the piece order here are the ones it draws; the test reads the files).
--   chest auras    a looping picture on the floor under a chest, found by its client item id
--   foot aura      the Templar line's sigil under the feet of every Templar-line player the server names
--   range frame    a faint square on the floor over the aura's range (one widget of (2r + 1) x (2r + 1) tiles), only while the
--                  Templar is in a party

ChestAuraLogic = {}
local L = ChestAuraLogic

L.OPCODE = 118            -- server templar_combat.lua, ChaosOpcodes.templarAura (server -> client `sync`)
L.DEFAULTS = { chestAuras = true }

-- an option value from the settings: a boolean is kept, anything else (nil, junk, an older settings file) is the default
function L.optionOn(value)
  if type(value) == 'boolean' then return value end
  return L.DEFAULTS.chestAuras == true
end

-- ---------------------------------------------------------------- the pictures
L.SPRITE = 32             -- px of one tile in the pictures (1x: the chest and foot pictures cover two tiles, the coffer four)
L.CHEST_FRAMES = 12       -- frames of one loop of a chest aura
L.CHEST_FRAME_MS = 200    -- 2.4 s a loop
L.FOOT_FRAMES = 24        -- frames of one slow turn of the foot aura
L.FOOT_FRAME_MS = 250     -- 6 s a turn
L.FOOT_PX = 64            -- one foot frame is 64 x 64 px: two tiles, the ring centred in it
L.FRAME_PX = 96           -- the range frame picture: 3 x 3 tiles, drawn as a nine-slice with a border of FRAME_BORDER px
L.FRAME_BORDER = 32
L.FOOT_DY = 12            -- px (of a 32 px tile) from the creature's tile centre down to its feet: the ring's centre goes there

-- client item id -> the aura. px: the picture's side (its tiles = px / SPRITE). big: a 2 x 2 item, which the engine draws up and to
-- the left of its tile, so its picture is centred on the corner of the tile (shift -0.5 tile each way).
L.CHESTS = {
  [38758] = { art = 'reward_sigil', px = 64 },                 -- the reward chest, one tile (server 32311)
  [38642] = { art = 'cursed_smoke', px = 64 },                 -- the cursed chest (server 32281)
  [38657] = { art = 'coffer_smoke', px = 128, big = true },    -- the Sealed Coffer on the big gold chest (server 32312, the retired 2 x 2 look of pair 45)
}

function L.chestOf(clientId)
  return L.CHESTS[clientId]
end

function L.chestPath(art)
  return '/modules/game_chestaura/images/chest/' .. art .. '.png'
end

-- 1 Templar, 2 Inquisitor, 3 Sentinel (the server's lineOf)
L.LINES = { 'templar', 'inquisitor', 'sentinel' }

function L.footPath(line)
  local name = L.LINES[line]
  return name and ('/modules/game_chestaura/images/foot/' .. name .. '_sigil.png') or nil
end

function L.framePath(line)
  local name = L.LINES[line]
  return name and ('/modules/game_chestaura/images/frame/' .. name .. '.png') or nil
end

-- ---------------------------------------------------------------- frames
-- the loop frame (0-based) at a time: the same frame for every widget of a kind at a moment, so the auras of two chests are in step
function L.frameIndex(nowMs, frameMs, frames)
  nowMs = tonumber(nowMs) or 0
  if frameMs <= 0 or frames <= 0 then return 0 end
  return math.floor(nowMs / frameMs) % frames
end

-- the image-clip string of frame `i` (0-based) in a strip of square frames `px` wide
function L.clip(i, px)
  return string.format('%d 0 %d %d', i * px, px, px)
end

-- ---------------------------------------------------------------- sizes
-- Floor widgets (base patch 0078 draws them with the ground effects) and creature bottom widgets are drawn inside the map's own
-- picture, so their sizes and margins are in sprite pixels: the map scales them with everything else, and nothing here needs to
-- follow the zoom or the window size. (game_combatdecals sizes its floor widgets from the map panel's tile size in screen pixels;
-- which of the two is right for floor widgets is open until a client shows it, client/MANIFEST.md "Chest and Templar auras".
-- If it is screen pixels, floorBox is the one place to change.)

-- size and margins of a floor widget `tiles` wide (the picture's px / 32) that sits on a tile, centred on it; shift moves it by that
-- many tiles each way (-0.5: the corner of the tile, the middle of a 2 x 2 item whose position is its bottom right tile).
-- The engine puts a tile widget's centre at the tile's top left + margin + one sprite size (drawWidgetOverTile, base patch 0041,
-- which 0078 reuses), so the margin that centres it is (shift - 0.5) tiles.
function L.floorBox(spriteSize, tiles, shift)
  local u = spriteSize or L.SPRITE
  local size = math.floor(u * tiles + 0.5)
  local m = math.floor(u * ((shift or 0) - 0.5) + 0.5)
  return size, m, m
end

function L.chestBox(def, spriteSize)
  return L.floorBox(spriteSize, def.px / L.SPRITE, def.big and -0.5 or 0)
end

-- the range frame: ONE widget of (2r + 1) x (2r + 1) tiles for a Templar of aura radius r, centred on the Templar's tile. A floor widget
-- lies on one tile; the margins move its centre, so it may be hosted on a free tile near the Templar (dx, dy = the Templar's tile minus
-- the host tile, in tiles) when the Templar's own tile already carries another module's floor widget (a footprint, a stain).
function L.frameBox(spriteSize, radius, dx, dy)
  local spr = spriteSize or L.SPRITE
  local size = (2 * radius + 1) * spr
  return size, math.floor(((dx or 0) - 0.5) * spr + 0.5), math.floor(((dy or 0) - 0.5) * spr + 0.5)
end

-- the foot picture: two tiles wide, in map pixels (the engine draws a creature's widgets in the map's own coordinates); the margin
-- moves the ring's centre from the creature's tile centre down to its feet
function L.footBox(spriteSize)
  local spr = spriteSize or L.SPRITE
  return spr * (L.FOOT_PX / L.SPRITE), math.floor(L.FOOT_DY * spr / L.SPRITE + 0.5)
end

-- ---------------------------------------------------------------- which tiles
function L.tileKey(pos)
  return pos.x .. ',' .. pos.y .. ',' .. pos.z
end

-- the position of a tile key, nil for anything else
function L.keyPos(key)
  local x, y, z = tostring(key):match('^(-?%d+),(-?%d+),(-?%d+)$')
  if not x then return nil end
  return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

-- ---------------------------------------------------------------- the range square
-- The aura covers the party members within `radius` sqm of the Templar by Chebyshev distance (the larger of the two axes), on its
-- floor: the (2r + 1) x (2r + 1) tiles round the Templar's tile. squareBounds gives its corners, inSquare tests a tile.
function L.squareBounds(center, r)
  return { x0 = center.x - r, y0 = center.y - r, x1 = center.x + r, y1 = center.y + r, z = center.z }
end

function L.inSquare(pos, center, r)
  if type(pos) ~= 'table' or type(center) ~= 'table' or pos.z ~= center.z then return false end
  return math.max(math.abs(pos.x - center.x), math.abs(pos.y - center.y)) <= r
end

function L.squareSize(r)
  return (2 * r + 1) * (2 * r + 1)
end

-- The frame widget is hosted on the Templar's tile when its floor widget slot is free, else on the nearest free tile within HOST_REACH
-- (rings of growing Chebyshev distance, row by row inside a ring). free(pos) says whether a tile can host (it exists, is in view and
-- carries no floor widget). Returns a position table or nil.
L.HOST_REACH = 2

function L.pickHost(center, free, reach)
  reach = reach or L.HOST_REACH
  for d = 0, reach do
    for dy = -d, d do
      for dx = -d, d do
        if math.max(math.abs(dx), math.abs(dy)) == d then
          local p = { x = center.x + dx, y = center.y + dy, z = center.z }
          if free(p) then return p end
        end
      end
    end
  end
  return nil
end

-- a host that still serves a Templar standing at `center`: within HOST_REACH of it
function L.hostNear(host, center, reach)
  return L.inSquare(host, center, reach or L.HOST_REACH)
end

-- ---------------------------------------------------------------- what is visible
L.VIEW_MARGIN = 1         -- tiles past the visible area where a chest still gets its widget (the map scrolls a step ahead)

-- a position the player can see: same floor, inside the visible tiles (vw x vh) round the player, plus the margin (default 1; a host of
-- the range frame takes 0: it must really be drawn)
function L.onScreen(pos, center, vw, vh, margin)
  if type(pos) ~= 'table' or type(center) ~= 'table' or pos.z ~= center.z then return false end
  vw, vh = tonumber(vw) or 0, tonumber(vh) or 0
  if vw <= 0 or vh <= 0 then return false end
  margin = margin or L.VIEW_MARGIN
  return math.abs(pos.x - center.x) <= math.floor(vw / 2) + margin and math.abs(pos.y - center.y) <= math.floor(vh / 2) + margin
end

-- the foot aura shows under a Templar-line player the server named (entry) when auras are on and the viewer sees the creature
function L.showSigil(enabled, entry, creatureVisible)
  return enabled == true and entry ~= nil and creatureVisible == true and L.footPath(entry.line) ~= nil
end

-- the range frame shows for an entry the server flagged `party` (the Templar is in a party and the viewer is it or shares it): not
-- for a Templar without a party, not for a viewer outside it, not when the Templar is on another floor than the viewer
function L.showFrame(enabled, entry, templarPos, viewerPos)
  if enabled ~= true or not entry or not entry.party or entry.radius < 1 then return false end
  if type(templarPos) ~= 'table' or type(viewerPos) ~= 'table' then return false end
  return templarPos.z == viewerPos.z
end

-- ---------------------------------------------------------------- the server's list
-- msg = the JSON of opcode 118: {action = 'sync', data = {t = [{i, l, r, p}]}}. Returns {[creature id] = {id, line, radius, party}}
-- for the valid rows (line 1..3, radius 1..15, a creature id), or nil for a message that is not a sync.
L.MAX_RADIUS = 15
L.MAX_ROWS = 64
L.MAX_FRAMES = 6         -- range frames drawn at once (8 r tiles each); more Templars in one party in view get their sigil only

function L.parseSync(msg)
  if type(msg) ~= 'table' or msg.action ~= 'sync' then return nil end
  local data = type(msg.data) == 'table' and msg.data or {}
  local rows = type(data.t) == 'table' and data.t or {}
  local out, n = {}, 0
  for _, row in ipairs(rows) do
    if type(row) == 'table' and n < L.MAX_ROWS then
      local id, line, r = tonumber(row.i), tonumber(row.l), tonumber(row.r)
      if id and id > 0 and line and L.LINES[line] and r and r >= 1 then
        r = math.min(math.floor(r), L.MAX_RADIUS)
        out[id] = { id = id, line = line, radius = r, party = tonumber(row.p) == 1 or row.p == true }
        n = n + 1
      end
    end
  end
  return out
end

-- what changed between two lists (the ones parseSync gives): {added = {id}, removed = {id}, changed = {id}} sorted by id
function L.syncDiff(old, new)
  local added, removed, changed = {}, {}, {}
  for id, e in pairs(new or {}) do
    local o = old and old[id]
    if not o then
      added[#added + 1] = id
    elseif o.line ~= e.line or o.radius ~= e.radius or o.party ~= e.party then
      changed[#changed + 1] = id
    end
  end
  for id in pairs(old or {}) do
    if not (new and new[id]) then removed[#removed + 1] = id end
  end
  table.sort(added)
  table.sort(removed)
  table.sort(changed)
  return { added = added, removed = removed, changed = changed }
end
