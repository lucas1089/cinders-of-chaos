-- Loot beams: the rules without client API (tested by lootbeams_test.lua with luajit and lua5.3).
-- Which tier gets which beam colour, which items of a corpse or a tile may beam under the player's loot filter, the
-- best one per tile, the cap (nearest and best first) and the engine calls that turn the drawn set into the wanted one.
-- The filter rules are game_lootfilter's LootFilterLogic, handed in with LB.setFilterLogic.
-- info = {r = rarity 0..15, u = unique, o = orb, pw = legendary power, g = category, t = best modifier tier}

LootBeamsLogic = {}
local LB = LootBeamsLogic
local LF

function LB.setFilterLogic(logic)
  LF = logic
end

-- The rarities are grouped into four beam colours, so a beam reads at a glance; uniques and orbs have their own. (Until
-- 2026-10-18 there were 15 rarities in six colours; red and violet went with Mythic .. Transcendent.)
-- height: share of the chosen beam height (low tiers stand shorter); order: which group wins on a tile.
LB.GROUPS = {
  white  = { color = '#eef3f8', height = 0.75, order = 1 },
  blue   = { color = '#3d8bff', height = 0.85, order = 2 },
  orange = { color = '#ff8c1a', height = 1.00, order = 3 },
  divine = { color = '#7fe3ff', height = 1.10, order = 4 },
  unique = { color = '#2bff7a', height = 1.15, order = 5 },
  orb    = { color = '#39e0c8', height = 0.80, order = 0 },
}
LB.GROUP_ORDER = { 'white', 'blue', 'orange', 'divine', 'unique', 'orb' }

-- rarity id 1..15 -> group (an id of today: 1 Common, 2 Uncommon, 3 Magic, 4 Rare, 5 Legendary, 10 Divine; the others only
-- exist on items saved before the seven rarities and go with the rarity they became)
LB.TIER_GROUP = {
  'white', 'white',                          -- Common, Uncommon
  'blue', 'blue',                            -- Magic, Rare
  'orange', 'orange', 'orange', 'orange', 'orange', -- Legendary (5, and the old 6 .. 9)
  'divine', 'divine', 'divine', 'divine', 'divine', 'divine', -- Divine (10, and the old 11 .. 15)
}

LB.HEIGHTS = { short = 2.5, normal = 3.5, tall = 4.5 } -- tiles
LB.HEIGHT_ORDER = { 'short', 'normal', 'tall' }
LB.INTENSITIES = { soft = 0.55, normal = 0.8, bright = 1.0 }
LB.INTENSITY_ORDER = { 'soft', 'normal', 'bright' }
LB.MAX_BEAMS = 24 -- the engine caps at 64; a big pull of 10 corpses stays well under this

local function flag(v)
  return v == true or v == 1 or v == '1'
end

local function bool(v, default)
  if v == nil then return default end
  return v == true or v == 1 or v == '1' or v == 'true'
end

-- ---------------------------------------------------------------- settings (g_settings node "lootBeams")
-- enabled  beams at all
-- height   short | normal | tall      intensity  soft | normal | bright
-- orbs     orbs get a beam too        ground     items lying on the ground (not in a corpse) get one (Ground Labels)
function LB.defaults()
  return { enabled = true, height = 'normal', intensity = 'normal', orbs = false, ground = true }
end

function LB.normalize(t)
  local d = LB.defaults()
  if type(t) ~= 'table' then return d end
  return {
    enabled = bool(t.enabled, d.enabled),
    height = LB.HEIGHTS[t.height] and t.height or d.height,
    intensity = LB.INTENSITIES[t.intensity] and t.intensity or d.intensity,
    orbs = bool(t.orbs, d.orbs),
    ground = bool(t.ground, d.ground),
  }
end

-- ---------------------------------------------------------------- tiers and colours
-- the group of one item, or nil when it has no beam colour (no rarity, not unique, not an orb)
function LB.groupOf(info)
  if type(info) ~= 'table' then return nil end
  if flag(info.u) then return 'unique' end
  local r = tonumber(info.r) or 0
  if LB.TIER_GROUP[r] then return LB.TIER_GROUP[r] end
  if flag(info.pw) then return 'orange' end -- a legendary power on gear without a rarity
  if flag(info.o) then return 'orb' end
  return nil
end

function LB.tierColor(r)
  local g = LB.TIER_GROUP[tonumber(r) or 0]
  return g and LB.GROUPS[g].color or nil
end

-- higher wins on a tile: uniques, then the rarity (a power counts as Legendary), orbs last
function LB.rank(info)
  if flag(info.u) then return 100 end
  local r = tonumber(info.r) or 0
  if r >= 1 then return r + (flag(info.pw) and 0.5 or 0) end
  if flag(info.pw) then return 5 end
  if flag(info.o) then return 0.5 end
  return 0
end

-- does this item give its tile a beam: the loot filter makes it glow (a legendary power always does); orbs only when
-- the player wants orb beams
function LB.wants(info, filter, s)
  if type(info) ~= 'table' or not LB.groupOf(info) then return false end
  if flag(info.o) and not flag(info.u) and (tonumber(info.r) or 0) < 1 then
    return s.orbs and true or false
  end
  if flag(info.pw) then return true end
  return LF.classify(info, filter) == 'highlight'
end

-- the beam of a list of items: {color, height (tiles), intensity, group, rank} or nil
function LB.beamOf(items, filter, s)
  local best, bestRank
  for _, info in ipairs(type(items) == 'table' and items or {}) do
    if LB.wants(info, filter, s) then
      local rank = LB.rank(info)
      if not bestRank or rank > bestRank then best, bestRank = info, rank end
    end
  end
  if not best then return nil end
  local key = LB.groupOf(best)
  local g = LB.GROUPS[key]
  return { color = g.color, height = LB.HEIGHTS[s.height] * g.height, intensity = LB.INTENSITIES[s.intensity],
    group = key, rank = bestRank }
end

-- ---------------------------------------------------------------- what is known
function LB.posKey(pos)
  return pos.x .. ',' .. pos.y .. ',' .. pos.z
end

function LB.newState()
  return { corpses = {}, ground = {} }
end

-- p = [x, y, z] (server JSON) -> {x, y, z} or nil
function LB.pos3(p)
  if type(p) ~= 'table' then return nil end
  local x, y, z = tonumber(p[1] or p.x), tonumber(p[2] or p.y), tonumber(p[3] or p.z)
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z }
end

-- a server "beam" message {k, p, i}: i = [] (or none) ends the beam of kill k. Returns true when something changed.
function LB.onBeam(st, data)
  if type(data) ~= 'table' then return false end
  local k = tonumber(data.k)
  if not k then return false end
  local items = {}
  for _, x in ipairs(type(data.i) == 'table' and data.i or {}) do
    if type(x) == 'table' then items[#items + 1] = x end
  end
  local pos = LB.pos3(data.p)
  if #items == 0 or not pos then
    local had = st.corpses[k] ~= nil
    st.corpses[k] = nil
    return had
  end
  st.corpses[k] = { pos = pos, items = items }
  return true
end

-- the ground items of the tiles in view: {{pos = {x, y, z}, rows = {info, ...}}, ...} (corpse rows are left out)
function LB.setGround(st, list)
  local ground = {}
  for _, e in ipairs(type(list) == 'table' and list or {}) do
    if type(e) == 'table' and type(e.pos) == 'table' then
      local items = {}
      for _, row in ipairs(type(e.rows) == 'table' and e.rows or {}) do
        if type(row) == 'table' and not flag(row.k) then items[#items + 1] = row end
      end
      if #items > 0 then ground[LB.posKey(e.pos)] = { pos = e.pos, items = items } end
    end
  end
  st.ground = ground
end

-- ---------------------------------------------------------------- what is drawn
-- every tile with a beam, the best one per tile; at most `max` on the player's floor, the best groups first, then the
-- nearest. Returns {[posKey] = {pos, color, height, intensity, group, rank}}.
function LB.resolve(st, filter, s, ppos, max)
  local out = {}
  if not s.enabled or not ppos then return out end
  local per = {}
  local function offer(pos, items)
    if pos.z ~= ppos.z then return end
    local b = LB.beamOf(items, filter, s)
    if not b then return end
    local key = LB.posKey(pos)
    local cur = per[key]
    if not cur or b.rank > cur.rank then
      b.pos = pos
      b.dist = math.max(math.abs(pos.x - ppos.x), math.abs(pos.y - ppos.y))
      per[key] = b
    end
  end
  for _, c in pairs(st.corpses) do offer(c.pos, c.items) end
  if s.ground then
    for _, g in pairs(st.ground) do offer(g.pos, g.items) end
  end
  local list = {}
  for key, b in pairs(per) do
    b.key = key
    list[#list + 1] = b
  end
  table.sort(list, function(a, b)
    local ga, gb = LB.GROUPS[a.group].order, LB.GROUPS[b.group].order
    if ga ~= gb then return ga > gb end
    if a.dist ~= b.dist then return a.dist < b.dist end
    return a.key < b.key
  end)
  for i = 1, math.min(max or LB.MAX_BEAMS, #list) do out[list[i].key] = list[i] end
  return out
end

-- drawn = {[posKey] = {sig, pos}} (what the engine has); want = LB.resolve(...). Returns the calls that make the
-- engine show `want`: {remove = {pos, ...}, set = {beam, ...}}, and the new drawn table. Unchanged beams are left alone.
function LB.sig(b)
  return b.color .. '|' .. string.format('%.2f|%.2f', b.height, b.intensity)
end

function LB.diff(drawn, want)
  local remove, set, nextDrawn = {}, {}, {}
  for key, d in pairs(drawn) do
    if not want[key] then remove[#remove + 1] = d.pos end
  end
  for key, b in pairs(want) do
    local sig = LB.sig(b)
    if not drawn[key] or drawn[key].sig ~= sig then set[#set + 1] = b end
    nextDrawn[key] = { sig = sig, pos = b.pos }
  end
  table.sort(set, function(a, b) return a.key < b.key end)
  return { remove = remove, set = set }, nextDrawn
end

-- the client's settings fingerprint of the loot filter (beams are re-chosen when it changes)
function LB.filterKey(f)
  if type(f) ~= 'table' then return '' end
  local show = type(f.show) == 'table' and f.show or {}
  return table.concat({ tostring(f.highlight), tostring(f.dim), tostring(f.tier), tostring(show.equipment),
    tostring(show.currency), tostring(show.supplies), tostring(show.other) }, ':')
end
