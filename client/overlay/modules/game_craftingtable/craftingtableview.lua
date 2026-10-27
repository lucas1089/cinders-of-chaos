-- Crafting Table window logic (pure, no UI calls): shared by craftingtable.lua and craftingtableview_test.lua.
-- Protocol of the base server's crafting script (data/scripts/customs/crafting/1crafting_mod.lua, extended opcode 91,
-- JSON {action, data}; server/README.md "Base crafting script" and "Crafting Table window"):
--   client -> server  fetch {category, page}         one page of 10 recipes
--                     craft {category, craftId}      craftId = the recipe's index in its category
--                     tip {category, craftId}        the item tooltip of the result (patch_base_crafting_ui.py)
--   server -> client  show {category}                a crafting table was used: open on that category
--                     money <number>                 the gold the player carries
--                     chunkedFetch {chunkData = {msgID, index, count, payload}}   pieces of the JSON text of
--                                  fetch {category, page, totalPages, crafts = [{index, name, id, clientId, level, cost,
--                                  count, storage, playerStorage, storageText, materials = [{id, clientId, count,
--                                  player, name}], bonus}]}   (player = how many the player has; name from the UI
--                                  patch; bonus from patch_base_crafting_bonus.py at the player's skill:
--                                  {kind = "gear", level, odds = [{rarity, name, pct}]} for equipment,
--                                  {kind = "stack", odds = [{extra, pct}]} for potions and runes, absent otherwise)
--                     craft {success = true}         accepted: the item is made 860 ms later
--                     message {kind = ok | error, text}   the answer to a craft (patch_base_crafting_ui.py)
--                     tip {category, craftId, tip}   the tooltip (false when the server has none)
-- The server decides; the checks here only explain why the Craft button is off.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

CraftingTableView = CraftingTableView or {}
local V = CraftingTableView

V.OPCODE = 91
V.PAGE_SIZE = 10
V.CRAFT_MS = 860      -- the server's delay between the accepted request and the item
V.COOLDOWN_MS = 1000  -- the server's minimum time between two requests of a player (patch_base_crafting.py)
V.TABLE_RANGE = 1     -- tiles the player may move from where the table opened the window (the server allows 2 from
                      -- the table, and the player stood next to it)
V.MAX_REPEAT = 50

V.COLORS = { gold = '#e8b84a', bright = '#f6cf72', text = '#d6c9ae', dim = '#8c8070', off = '#6b6258',
  good = '#8fd16a', bad = '#e07060', warn = '#e0a050' }

-- the server's categories in its order; skill = the engine skill (7..13), the client gets them as
-- g_game.onCraftingSkill(skill - 7, ...) (base patch 0012, game_craftskills)
V.CATEGORIES = {
  { key = 'herbalist', name = 'Herbalist', skill = 10 },
  { key = 'woodcutting', name = 'Woodcutting', skill = 8 },
  { key = 'mining', name = 'Mining', skill = 9 },
  { key = 'generalcrafting', name = 'General Crafting', skill = 7 },
  { key = 'armorsmith', name = 'Armorsmith', skill = 11 },
  { key = 'weaponsmith', name = 'Weaponsmith', skill = 12 },
  { key = 'jewelsmith', name = 'Jewelsmith', skill = 13 },
}
V.SKILL_NAMES = { [7] = 'Crafting', [8] = 'Woodcutting', [9] = 'Mining', [10] = 'Herbalist', [11] = 'Armorsmith',
  [12] = 'Weaponsmith', [13] = 'Jewelsmith' }

local function num(v) return tonumber(v) or 0 end

function V.category(key)
  for i, c in ipairs(V.CATEGORIES) do
    if c.key == key then return c, i end
  end
  return nil
end

-- index 0..6 of g_game.onCraftingSkill for a category
function V.skillIndex(key)
  local c = V.category(key)
  return c and (c.skill - 7) or nil
end

-- 1234567 -> "1,234,567"
function V.fmtNum(n)
  n = math.floor(num(n))
  local s = tostring(math.abs(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return (n < 0 and '-' or '') .. out
end

function V.goldText(n)
  return V.fmtNum(n) .. ' gp'
end

-- ---------------------------------------------------------------- state
function V.newState()
  return { cats = {}, money = nil, chunks = {} }
end

function V.catState(state, key)
  local c = state.cats[key]
  if not c then
    c = { recipes = {}, pages = {}, totalPages = nil }
    state.cats[key] = c
  end
  return c
end

-- one piece of a chunked message; returns the joined text when the last piece is in, else nil
function V.addChunk(state, cd)
  if type(cd) ~= 'table' or type(cd.payload) ~= 'string' then return nil end
  local id, i, n = tostring(cd.msgID or ''), math.floor(num(cd.index)), math.floor(num(cd.count))
  if i < 1 or n < 1 or i > n or n > 10000 then return nil end
  local e = state.chunks[id]
  if not e or e.count ~= n then
    e = { count = n, parts = {}, have = 0 }
    state.chunks[id] = e
  end
  if not e.parts[i] then
    e.have = e.have + 1
  end
  e.parts[i] = cd.payload
  if e.have < n then return nil end
  state.chunks[id] = nil
  return table.concat(e.parts, '', 1, n)
end

local function material(m)
  if type(m) ~= 'table' then return nil end
  return { id = num(m.id), clientId = num(m.clientId), need = math.max(1, num(m.count)), have = num(m.player),
    name = type(m.name) == 'string' and m.name ~= '' and m.name or nil }
end

-- the crafting bonus of a recipe (server craft_bonus.lua): rarity odds of equipment, extra pieces of potions and runes
local function bonus(b)
  if type(b) ~= 'table' or type(b.odds) ~= 'table' then return nil end
  local odds = {}
  if b.kind == 'gear' then
    for _, o in ipairs(b.odds) do
      if type(o) == 'table' and num(o.pct) > 0 then
        odds[#odds + 1] = { rarity = num(o.rarity), name = tostring(o.name or ('Rarity ' .. num(o.rarity))), pct = num(o.pct) }
      end
    end
    table.sort(odds, function(a, c) return a.rarity < c.rarity end)
    return { kind = 'gear', level = num(b.level), odds = odds }
  elseif b.kind == 'stack' then
    for _, o in ipairs(b.odds) do
      if type(o) == 'table' and num(o.pct) > 0 and num(o.extra) > 0 then
        odds[#odds + 1] = { extra = math.floor(num(o.extra)), pct = num(o.pct) }
      end
    end
    table.sort(odds, function(a, c) return a.extra < c.extra end)
    return { kind = 'stack', odds = odds }
  end
  return nil
end

-- 12 -> "12%", 0.4 -> "0.4%", 17.25 -> "17.25%"
function V.pctText(p)
  local s = string.format('%.2f', num(p)):gsub('0+$', ''):gsub('%.$', '')
  return s .. '%'
end

-- the line under the gold: "Rarity at item level 37: Common 18% / ... / Legendary 0.6%" or
-- "Bonus yield: +3 at 17.5% / +5 at 4%" ('' when the recipe has none)
function V.bonusText(r)
  local b = r and r.bonus
  if not b or #b.odds == 0 then return '' end
  local parts = {}
  if b.kind == 'gear' then
    for _, o in ipairs(b.odds) do parts[#parts + 1] = o.name .. ' ' .. V.pctText(o.pct) end
    return tr('Rarity at item level %d: %s', b.level, table.concat(parts, ' / '))
  end
  for _, o in ipairs(b.odds) do parts[#parts + 1] = string.format('+%d at %s', o.extra, V.pctText(o.pct)) end
  return tr('Bonus yield: %s', table.concat(parts, ' / '))
end

function V.recipe(raw, category)
  if type(raw) ~= 'table' or num(raw.index) < 1 then return nil end
  local r = {
    category = category, index = math.floor(num(raw.index)), name = tostring(raw.name or '?'), id = num(raw.id),
    clientId = num(raw.clientId), level = num(raw.level), cost = num(raw.cost), count = math.max(1, num(raw.count)),
    materials = {},
  }
  local storage = num(raw.storage)
  r.locked = storage > 0 and num(raw.playerStorage) ~= 1
  r.lockText = type(raw.storageText) == 'string' and raw.storageText or ''
  r.bonus = bonus(raw.bonus)
  for _, m in ipairs(type(raw.materials) == 'table' and raw.materials or {}) do
    local mm = material(m)
    if mm then r.materials[#r.materials + 1] = mm end
  end
  return r
end

-- a fetch answer: stores its recipes; returns the category key (nil when the data is not usable)
function V.applyFetch(state, data)
  if type(data) ~= 'table' or not V.category(data.category) then return nil end
  local c = V.catState(state, data.category)
  local total = math.floor(num(data.totalPages))
  if total >= 0 then c.totalPages = total end
  local page = math.floor(num(data.page))
  if page >= 1 then c.pages[page] = true end
  for _, raw in ipairs(type(data.crafts) == 'table' and data.crafts or {}) do
    local r = V.recipe(raw, data.category)
    if r then c.recipes[r.index] = r end
  end
  return data.category
end

-- pages of a category not received yet (all of them while the page count is unknown: just page 1)
function V.missingPages(state, key)
  local c = V.catState(state, key)
  if not c.totalPages then return { 1 } end
  local out = {}
  for p = 1, c.totalPages do
    if not c.pages[p] then out[#out + 1] = p end
  end
  return out
end

function V.loaded(state, key)
  local c = state.cats[key]
  return c ~= nil and c.totalPages ~= nil and #V.missingPages(state, key) == 0
end

-- forget the pages (counts change); the recipes stay on screen until the new pages come
function V.markStale(state, key)
  local c = V.catState(state, key)
  c.pages, c.totalPages = {}, c.totalPages
end

function V.pageOf(index)
  return math.floor((math.max(1, num(index)) - 1) / V.PAGE_SIZE) + 1
end

function V.recipes(state, key)
  local c = state.cats[key]
  local out = {}
  for _, r in pairs(c and c.recipes or {}) do out[#out + 1] = r end
  table.sort(out, function(a, b) return a.index < b.index end)
  return out
end

-- ---------------------------------------------------------------- checks
-- ctx = {money, skill (nil = unknown), atTable (category key or nil), near (bool)}
function V.check(r, ctx)
  ctx = ctx or {}
  local out = { ok = true, reasons = {}, mats = {} }
  local function fail(k) out.ok = false out.reasons[#out.reasons + 1] = k end
  if r.locked then fail('locked') end
  if ctx.skill and ctx.skill < r.level then fail('skill') end
  if ctx.money and ctx.money < r.cost then fail('gold') end
  local short = false
  for i, m in ipairs(r.materials) do
    local enough = m.have >= m.need
    out.mats[i] = enough
    if not enough then short = true end
  end
  if short then fail('materials') end
  out.recipeOk = out.ok -- what the player has for this recipe, the table aside
  if ctx.atTable ~= r.category then fail('table') elseif ctx.near == false then fail('away') end
  return out
end

-- how many times the player can craft it with what he carries (materials and gold; no skill or unlock check)
function V.maxCraftable(r, money)
  local n = math.huge
  for _, m in ipairs(r.materials) do
    n = math.min(n, math.floor(m.have / m.need))
  end
  if r.cost > 0 and money then n = math.min(n, math.floor(money / r.cost)) end
  if n == math.huge then n = V.MAX_REPEAT end
  return math.max(0, math.min(n, V.MAX_REPEAT))
end

function V.reasonText(key, r, ctx)
  local cat = V.category(r.category)
  if key == 'locked' then
    return tr('Recipe not unlocked yet.%s', (r.lockText ~= '' and (' ' .. r.lockText) or ''))
  elseif key == 'skill' then
    return tr('Needs %s %d (yours %d).', tr(V.SKILL_NAMES[cat and cat.skill or 7]), r.level, num(ctx.skill))
  elseif key == 'gold' then
    return tr('Needs %s (you carry %s).', V.goldText(r.cost), V.goldText(ctx.money))
  elseif key == 'materials' then
    return tr('Materials missing.')
  elseif key == 'table' then
    return tr('Use a %s table to craft this.', cat and cat.name or 'crafting')
  elseif key == 'away' then
    return tr('Go back to the crafting table.')
  end
  return ''
end

-- the first reason, as the hint under the Craft button
function V.blockText(check, r, ctx)
  local k = check.reasons[1]
  return k and V.reasonText(k, r, ctx) or ''
end

-- ---------------------------------------------------------------- list
local function lower(s) return tostring(s or ''):lower() end

function V.matches(r, text)
  text = lower(text):gsub('^%s+', ''):gsub('%s+$', '')
  if text == '' then return true end
  if lower(r.name):find(text, 1, true) then return true end
  for _, m in ipairs(r.materials) do
    if m.name and lower(m.name):find(text, 1, true) then return true end
  end
  return false
end

-- mode 'all' or 'craftable' (what the player has now: unlock, skill, gold, materials; the table aside)
function V.filter(list, search, mode, ctx)
  local out = {}
  for _, r in ipairs(list) do
    if V.matches(r, search) and (mode ~= 'craftable' or V.check(r, ctx).recipeOk) then
      out[#out + 1] = r
    end
  end
  return out
end

function V.rowSub(r)
  local t = string.format('Lv %d  -  %s', r.level, V.goldText(r.cost))
  if r.count > 1 then t = string.format('x%d  -  ', r.count) .. t end
  return t
end

-- "have/need" of a material
function V.haveNeed(m)
  return string.format('%s/%s', V.fmtNum(m.have), V.fmtNum(m.need))
end

function V.materialName(m, fallback)
  return m.name or fallback or ('item ' .. m.id)
end

-- ---------------------------------------------------------------- craft progress and repeat
function V.progress(startMs, nowMs, delay)
  delay = delay or V.CRAFT_MS
  if not startMs then return 0 end
  return math.max(0, math.min(100, math.floor((nowMs - startMs) * 100 / delay)))
end

-- ms to wait before the next request of a repeat (the server's cooldown counts from the previous request)
function V.repeatDelay(lastStartMs, nowMs)
  if not lastStartMs then return 0 end
  return math.max(0, lastStartMs + V.COOLDOWN_MS + 150 - nowMs)
end

function V.clampQty(q, max)
  q = math.floor(num(q))
  return math.max(1, math.min(q, math.max(1, max or 1), V.MAX_REPEAT))
end

-- ---------------------------------------------------------------- messages
-- one decoded opcode 91 message -> {kind, ...}; kind nil = ignore
function V.parse(msg)
  if type(msg) ~= 'table' then return {} end
  local a, d = msg.action, msg.data
  if a == 'chunkedFetch' and type(msg.chunkData) == 'table' then
    return { kind = 'chunk', chunk = msg.chunkData }
  elseif a == 'fetch' and type(d) == 'table' then
    return { kind = 'fetch', data = d }
  elseif a == 'show' and type(d) == 'table' and V.category(d.category) then
    return { kind = 'show', category = d.category }
  elseif a == 'money' and tonumber(d) then
    return { kind = 'money', money = tonumber(d) }
  elseif a == 'craft' and type(d) == 'table' then
    return { kind = 'accepted', ok = d.success == true }
  elseif a == 'message' and type(d) == 'table' then
    return { kind = 'message', ok = d.kind == 'ok', text = tostring(d.text or '') }
  elseif a == 'tip' and type(d) == 'table' then
    return { kind = 'tip', category = d.category, craftId = num(d.craftId), tip = type(d.tip) == 'table' and d.tip or nil }
  end
  return {}
end

function V.tipKey(category, index)
  return 'craftingtable:' .. tostring(category) .. ':' .. tostring(index)
end

-- plain text tooltip when the server sends none
function V.plainTip(r)
  local lines = { r.name .. (r.count > 1 and (' x' .. r.count) or '') }
  local cat = V.category(r.category)
  lines[#lines + 1] = tr('%s level %d, %s', tr(V.SKILL_NAMES[cat and cat.skill or 7]), r.level, V.goldText(r.cost))
  local b = V.bonusText(r)
  lines[#lines + 1] = b ~= '' and b or tr('A crafted item may roll a rarity.')
  return table.concat(lines, '\n')
end

function V.request(action, data)
  return { action = action, data = data or {} }
end

return V
