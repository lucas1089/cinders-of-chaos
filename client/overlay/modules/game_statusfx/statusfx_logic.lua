-- Pure rules of game_statusfx (client/MANIFEST.md "Status layer (O597)"): the server's messages, which statuses a
-- creature shows (2 at most, by priority), the screen cap, the start / loop / stop timing of one status and the box of
-- its canvas on a creature. No engine call here (statusfx_test.lua runs it with plain Lua; server/tests/
-- status_vfx_test.lua reads the opcode).
StatusFxLogic = {}
local L = StatusFxLogic

L.OPCODE = 165                 -- server ChaosOpcodes.statusVfx
L.OPTION = 'statusEffects'     -- Options > Graphics "Status effects on creatures" (base patch 0205), default on
-- bit order of a mask (server chaos_status_vfx_ids.lua M.order)
L.ORDER = { 'burn', 'freeze', 'shock', 'poison', 'curse', 'root', 'soak', 'stun', 'confuse', 'haste', 'bless', 'regen',
  'shield', 'rage' }
-- which statuses win when a creature has more than CAP_CREATURE: what stops it first, then what hurts it, then the rest
L.PRIORITY = { 'stun', 'freeze', 'root', 'confuse', 'burn', 'shock', 'poison', 'curse', 'soak', 'shield', 'rage',
  'bless', 'regen', 'haste' }
L.CAP_CREATURE = 2
L.CAP_SCREEN = 24              -- statuses drawn at once; the creatures nearest the player win
L.CAP_SCREEN_MOBILE = 12
L.MAX_PAIRS = 256              -- pairs read from one message
L.FRAME_MS = 66                -- one phase of a status effect (the pair's own length)
L.SPRITE = 32
L.CANVAS = 64                  -- a status canvas: 2 x 2 tiles
L.TILES = 2
L.FEET_Y = 56                  -- the creature's feet on the canvas (x: the middle)
L.FOOT_DY = 12                 -- px from the creature's tile centre down to its feet
L.MAX_TILES = 3                -- widest creature the canvas grows with

local function num(v, d)
  v = tonumber(v)
  if v == nil or v ~= v or v == math.huge or v == -math.huge then return d end
  return v
end

function L.optionOn(value)
  return value ~= false
end

function L.hello(on)
  return { action = 'hello', data = { on = on and 1 or 0 } }
end

local function hasBit(mask, bit)
  return mask % (bit * 2) >= bit
end

L.BITS, L.RANK = {}, {}
do
  local b = 1
  for _, name in ipairs(L.ORDER) do
    L.BITS[name] = b
    b = b * 2
  end
  for i, name in ipairs(L.PRIORITY) do L.RANK[name] = i end
end

-- the statuses of a mask, the strongest first, at most `cap`
function L.pick(mask, cap)
  mask = math.floor(num(mask, 0))
  local out = {}
  if mask <= 0 then return out end
  for _, name in ipairs(L.PRIORITY) do
    if #out >= (cap or L.CAP_CREATURE) then break end
    if hasBit(mask, L.BITS[name]) then out[#out + 1] = name end
  end
  return out
end

-- the server's cfg message -> {on = bool, fx = {[status] = {start = {id, n}, loop = {id, n}, stop = {id, n}}}} (n = phases),
-- nil for any other message
function L.parseCfg(msg)
  if type(msg) ~= 'table' or msg.action ~= 'cfg' or type(msg.data) ~= 'table' then return nil end
  local d = msg.data
  local cfg = { on = d.on == 1, fx = {} }
  if not cfg.on then return cfg end
  local e, ms = d.e, d.ms
  if type(e) ~= 'table' or type(ms) ~= 'table' or #e ~= #L.ORDER * 3 or #ms ~= #e then
    cfg.on = false
    return cfg
  end
  for i, name in ipairs(L.ORDER) do
    local row = {}
    for j, part in ipairs({ 'start', 'loop', 'stop' }) do
      local k = (i - 1) * 3 + j
      local id = math.floor(num(e[k], 0))
      local n = math.floor(num(ms[k], 0) / L.FRAME_MS + 0.5)
      if id <= 0 or id > 65535 or n < 1 or n > 64 then
        cfg.on = false
        return cfg
      end
      row[part] = { id = id, n = n }
    end
    cfg.fx[name] = row
  end
  return cfg
end

-- the server's s message -> {{id, mask}, ...}, nil for any other message
function L.parseList(msg)
  if type(msg) ~= 'table' or msg.action ~= 's' or type(msg.data) ~= 'table' or type(msg.data.l) ~= 'table' then return nil end
  local l, out = msg.data.l, {}
  for i = 1, math.min(#l - 1, L.MAX_PAIRS * 2), 2 do
    local id, mask = math.floor(num(l[i], 0)), math.floor(num(l[i + 1], -1))
    if id > 0 and mask >= 0 and mask < 2 ^ #L.ORDER then out[#out + 1] = { id = id, mask = mask } end
  end
  return out
end

-- ---------------------------------------------------------------- the model
-- masks: creature id -> mask (never 0); shows: creature id -> {[status] = {part = 'start' | 'loop' | 'stop', t0}}
function L.newModel()
  return { masks = {}, shows = {} }
end

function L.setMask(model, id, mask)
  model.masks[id] = mask ~= 0 and mask or nil
end

-- the statuses of a creature against its mask: the ones that ended begin their stop, new ones begin their start (when
-- `allowed`, the screen cap, lets them). Returns the number of statuses the creature shows after it.
function L.sync(model, id, now, allowed)
  local want = {}
  for _, name in ipairs(L.pick(model.masks[id] or 0, L.CAP_CREATURE)) do want[name] = true end
  local shows = model.shows[id]
  local live = 0
  if shows then
    for name, s in pairs(shows) do
      if not want[name] and s.part ~= 'stop' then
        s.part, s.t0 = 'stop', now
      elseif want[name] and s.part ~= 'stop' then
        live = live + 1
      end
    end
  end
  if allowed ~= false then
    for _, name in ipairs(L.pick(model.masks[id] or 0, L.CAP_CREATURE)) do
      local s = shows and shows[name]
      if live >= L.CAP_CREATURE then break end
      if not s or s.part == 'stop' then
        shows = shows or {}
        model.shows[id] = shows
        shows[name] = { part = 'start', t0 = now }
        live = live + 1
      end
    end
  end
  local n = 0
  if shows then
    for _ in pairs(shows) do n = n + 1 end
  end
  return n
end

-- the effect and phase a show draws now: id, phase (0-based); nil when it is over (take it off). A start that ran out
-- becomes the loop.
function L.frame(show, row, now)
  if type(show) ~= 'table' or type(row) ~= 'table' then return nil end
  local e = row[show.part]
  if not e then return nil end
  local i = math.floor(math.max(0, now - show.t0) / L.FRAME_MS)
  if show.part == 'start' then
    if i < e.n then return e.id, i end
    show.part, show.t0 = 'loop', show.t0 + e.n * L.FRAME_MS
    e = row.loop
    i = math.floor(math.max(0, now - show.t0) / L.FRAME_MS)
  end
  if show.part == 'loop' then return e.id, i % e.n end
  if i < e.n then return e.id, i end
  return nil
end

-- drop the shows that are over; returns the number left on the creature
function L.reap(model, id, cfg, now)
  local shows = model.shows[id]
  if not shows then return 0 end
  local n = 0
  for name, s in pairs(shows) do
    if L.frame(s, cfg.fx[name], now) == nil then shows[name] = nil else n = n + 1 end
  end
  if n == 0 then model.shows[id] = nil end
  return n
end

-- the creatures that may start a new status: ids nearest first, until `cap` statuses are counted. Returns {[id] = true}.
function L.budget(model, idsNearestFirst, cap)
  local out, used = {}, 0
  for _, id in ipairs(idsNearestFirst) do
    local n = #L.pick(model.masks[id] or 0, L.CAP_CREATURE)
    if n > 0 then
      if used + n > cap then break end
      used = used + n
      out[id] = true
    end
  end
  return out
end

-- ---------------------------------------------------------------- drawing
-- the canvas on a creature `tiles` wide (a creature widget is centred on the creature's tile): side, margin left, margin
-- top and the side of one sprite tile. The canvas grows with the creature (1, 1.5, 2 times), its feet point stays on the
-- creature's feet, and a wider outfit, which the engine draws up and to the left of its tile, pulls it the same way.
function L.box(spriteSize, tiles)
  local spr = num(spriteSize, L.SPRITE)
  tiles = math.max(1, math.min(L.MAX_TILES, math.floor(num(tiles, 1))))
  local k = 1 + (tiles - 1) * 0.5
  local unit = spr / L.SPRITE
  local size = math.floor(L.CANVAS * unit * k + 0.5)
  local shift = math.floor(-(tiles - 1) * spr / 2 + 0.5)
  local feet = (L.FEET_Y - L.CANVAS / 2) * unit * k
  local top = math.floor(L.FOOT_DY * unit - feet + 0.5) + shift
  return size, shift, top, math.floor(size / L.TILES + 0.5)
end

-- tiles across of a creature drawn `px` pixels wide; up to a tile and a half counts as one tile (a player look on a
-- 64 px canvas is drawn 40 to 48 px wide and stands on its tile like a 32 px one)
function L.tilesOf(px, spriteSize)
  local spr = num(spriteSize, L.SPRITE)
  px = num(px, 0)
  if px <= 0 then return 1 end
  return math.max(1, math.min(L.MAX_TILES, math.ceil(px / spr - 0.51)))
end

-- the place in a thing's sprite list (1-based) of tile (w, h) of `phase`; w and h count from the bottom right tile
function L.spriteIndex(w, h, phase)
  return (phase * L.TILES + h) * L.TILES + w + 1
end

-- the pixel corner of tile (w, h) on a canvas whose tiles are `tile` px
function L.tileCorner(w, h, tile)
  return (L.TILES - 1 - w) * tile, (L.TILES - 1 - h) * tile
end

return L
