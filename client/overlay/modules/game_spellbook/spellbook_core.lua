-- Spellbook and spell picker logic, no UI calls of its own (spellbook_core_test.lua runs it under LuaJIT and Lua 5.3).
-- Shared as the global ChaosSpellCore: the Spellbook window (spellbook.lua) and, through base patch 0057, every spell
-- picker of the helper, the action bar and the custom hotkeys use the same order, the same "learned" rule and the same
-- learned-spell list.
--
-- "Learned" (castable now) is what the server checks on a cast: the spell is of the character's vocation, the level and
-- magic level are reached, and a needlearn spell is among the learned ones. The learned names come from the server's
-- spellbook reply (opcode 219, open.learned); the client's own spell list packet is no help, since the base server
-- fills it with every spell id.

local Core = {}

Core.SOON_LEVELS = 10 -- "Available soon": the spells of the next 10 levels
Core.FILTERS = {
  { key = 'learned', text = 'Learned' },
  { key = 'soon', text = 'Available soon' },
  { key = 'vocation', text = 'My vocation' },
  { key = 'all', text = 'All spells' },
  { key = 'runes', text = 'Runes' } -- the rune entries only; every other filter lists spells only
}
Core.DEFAULT_FILTER = 'learned'
-- second drop-down: attack or support spells (any spell that does not hurt: healing, buffs, summons, utility)
Core.KINDS = {
  { key = 'all', text = 'All types' },
  { key = 'attack', text = 'Attack' },
  { key = 'support', text = 'Support' }
}
Core.DEFAULT_KIND = 'all'
Core.SETTINGS_NODE = 'chaosSpellbook'       -- g_settings node: {[character name] = filter key}
Core.PICKER_SETTING = 'chaosPickerLearnedOnly' -- the pickers' "Only show learned spells" box

Core.learnedNames = {} -- lower-case names of the learned needlearn spells (server reply)

local function lower(s)
  return tostring(s or ''):lower()
end

function Core.setLearned(names)
  local set = {}
  if type(names) == 'table' then
    for _, name in pairs(names) do set[lower(name)] = true end
  end
  Core.learnedNames = set
  return set
end

function Core.normalizeFilter(key)
  for _, f in ipairs(Core.FILTERS) do
    if f.key == key then return key end
  end
  return Core.DEFAULT_FILTER
end

-- the filter saved for one character in a settings node (a plain table)
function Core.loadFilter(node, character)
  if type(node) ~= 'table' or not character or character == '' then return Core.DEFAULT_FILTER end
  return Core.normalizeFilter(node[character])
end

function Core.saveFilter(node, character, key)
  node = type(node) == 'table' and node or {}
  if character and character ~= '' then node[character] = Core.normalizeFilter(key) end
  return node
end

local function vocationList(spell)
  local out = {}
  if type(spell.vocations) == 'table' then
    for _, v in pairs(spell.vocations) do out[#out + 1] = tonumber(v) end
  end
  return out
end

-- ctx.vocation nil: the caller already kept only the character's spells (the pickers)
-- fold: the vocation as the client folds it (translateVocation), also accepted when it is not 0
function Core.vocationOk(spell, vocation, fold)
  if vocation == nil then return true end
  local ids = vocationList(spell)
  if #ids == 0 then return true end
  fold = tonumber(fold)
  for _, id in ipairs(ids) do
    if id == tonumber(vocation) or (fold and fold ~= 0 and id == fold) then return true end
  end
  return false
end

local function spellLevel(spell)
  return tonumber(spell.level) or 0
end

local function spellMagicLevel(spell)
  return tonumber(spell.maglevel) or tonumber(spell.mlevel) or 0
end

-- ctx = {vocation, level, magicLevel, learned = set of lower-case names}
-- 'ready' castable now; 'vocation' not of this vocation; 'learn' needs learning; 'level' level or magic level too low
function Core.status(spell, ctx)
  ctx = ctx or {}
  if not Core.vocationOk(spell, ctx.vocation, ctx.fold) then return 'vocation' end
  if spell.needLearn then
    local learned = ctx.learned or Core.learnedNames
    if not learned[lower(spell.name)] then return 'learn' end
  end
  local level, ml = tonumber(ctx.level), tonumber(ctx.magicLevel)
  if level and spellLevel(spell) > level then return 'level' end
  if ml and spellMagicLevel(spell) > ml then return 'level' end
  return 'ready'
end

function Core.textMatches(spell, text)
  text = lower(text):gsub('^%s+', ''):gsub('%s+$', '')
  if text == '' then return true end
  return lower(spell.name):find(text, 1, true) ~= nil or lower(spell.words):find(text, 1, true) ~= nil
end

-- a rune entry (the server's <rune>: a rune item id; a client SpellInfo entry of type "Rune"); a conjure spell, which
-- makes runes, is a spell
function Core.isRune(spell)
  return spell.rune ~= nil and spell.rune ~= false or tostring(spell.type or ''):lower() == 'rune'
end

function Core.filterMatches(spell, ctx, filter)
  filter = Core.normalizeFilter(filter)
  if filter == 'runes' then return Core.isRune(spell) end
  if Core.isRune(spell) then return false end
  if filter == 'all' then return true end
  local status = Core.status(spell, ctx)
  if filter == 'learned' then return status == 'ready' end
  if filter == 'vocation' then return status ~= 'vocation' end
  -- soon: of this vocation, not castable yet, at most SOON_LEVELS above the character's level
  if status == 'ready' or status == 'vocation' then return false end
  local level = tonumber(ctx and ctx.level) or 0
  return spellLevel(spell) <= level + Core.SOON_LEVELS
end

function Core.normalizeKind(key)
  for _, k in ipairs(Core.KINDS) do
    if k.key == key then return key end
  end
  return Core.DEFAULT_KIND
end

-- 'attack' or 'support' from the spell's data. The server's kind (type, read from the spell script) decides: damage is
-- an attack, healing, buffs, summons, conjures and utility are support. A spell without a type falls back to the XML
-- group (attack; healing and support are support). Runes: their group (a rune has no script kind).
function Core.kindOf(spell)
  local t = lower(spell.type)
  if t == 'damage' then return 'attack' end
  if t == 'heal' or t == 'buff' or t == 'summon' or t == 'conjure' or t == 'utility' then return 'support' end
  local g = spell.group
  if g == 1 or lower(g) == 'attack' then return 'attack' end
  return 'support'
end

-- number of tiles the area matrix hits (1 = hit, 3 = centre and hit)
local function hitCells(area)
  local n = 0
  if type(area) ~= 'table' then return n end
  for _, row in pairs(area) do
    if type(row) == 'table' then
      for _, v in pairs(row) do
        v = tonumber(v)
        if v == 1 or v == 3 then n = n + 1 end
      end
    end
  end
  return n
end
Core.hitCells = hitCells

-- an attack spell that hits an area: target "area" (round) or "front" (wave / beam), more than one tile hit. A spell
-- without an area matrix counts when the server called its target an area.
function Core.isAoE(spell)
  if Core.kindOf(spell) ~= 'attack' then return false end
  local target = lower(spell.target)
  if target ~= 'area' and target ~= 'front' then return false end
  if type(spell.area) == 'table' and next(spell.area) ~= nil then return hitCells(spell.area) > 1 end
  return true
end

function Core.kindMatches(spell, kind)
  kind = Core.normalizeKind(kind)
  if kind == 'all' then return true end
  return Core.kindOf(spell) == kind
end

function Core.matches(spell, ctx, filter, text, kind)
  return Core.filterMatches(spell, ctx, filter) and Core.kindMatches(spell, kind) and Core.textMatches(spell, text)
end

-- level, then name, then words (every spell list and picker)
function Core.compare(a, b)
  local la, lb = spellLevel(a), spellLevel(b)
  if la ~= lb then return la < lb end
  local na, nb = lower(a.name), lower(b.name)
  if na ~= nb then return na < nb end
  return lower(a.words) < lower(b.words)
end

function Core.sort(list)
  table.sort(list, Core.compare)
  return list
end

-- indexes of `spells` that pass, in order
function Core.visibleIndexes(spells, ctx, filter, text, kind)
  local out = {}
  for i, spell in ipairs(spells) do
    if Core.matches(spell, ctx, filter, text, kind) then out[#out + 1] = i end
  end
  return out
end

-- seconds left of a cooldown that ends at `endsAt` (ms clock), nil when it is over
function Core.cooldownLeft(endsAt, now)
  endsAt, now = tonumber(endsAt), tonumber(now)
  if not endsAt or not now or endsAt <= now then return nil end
  return math.ceil((endsAt - now) / 1000)
end

-- --------------------------------------------------------------------------------------------- spell pickers
-- The pickers (SpellPreview rows: id = spell id, text = "name\nwords") of mods/game_helper, modules/game_actionbar and
-- mods/client_settings call Core.setupPicker(window, player, spells) after building their rows (base patch 0057):
-- rows sorted by level then name, rows above the character's level dimmed, the "Only show learned spells" box and the
-- search box filter together, and the empty preview at the top says what to do.
-- env (optional, for tests): {tr, getSetting(key) -> bool|nil, setSetting(key, bool)}
local function defaultEnv()
  return {
    tr = rawget(_G, 'tr') or function(s) return s end,
    getSetting = function(key)
      local s = rawget(_G, 'g_settings')
      if not s then return nil end
      local ok, has = pcall(s.exists, key)
      if not (ok and has) then return nil end
      local okv, v = pcall(s.getBoolean, key)
      return okv and v or false
    end,
    setSetting = function(key, value)
      local s = rawget(_G, 'g_settings')
      if s then pcall(s.set, key, value) end
    end
  }
end

local function child(window, id)
  local ok, w = pcall(function() return window:recursiveGetChildById(id) end)
  return ok and w or nil
end

-- player context of a picker: vocation, level and magic level of the local player (the Spellbook's rule, so both lists
-- agree). translate: translateVocation (default: the global)
function Core.pickerContext(player, translate)
  local ctx = { learned = Core.learnedNames }
  if player then
    local okv, voc = pcall(function() return player:getVocation() end)
    if okv and tonumber(voc) then
      ctx.vocation = tonumber(voc)
      translate = translate or rawget(_G, 'translateVocation')
      if translate then
        local okt, folded = pcall(translate, ctx.vocation)
        if okt then ctx.fold = tonumber(folded) end
      end
    end
    local ok, level = pcall(function() return player:getLevel() end)
    if ok then ctx.level = tonumber(level) end
    local okm, ml = pcall(function() return player:getMagicLevel() end)
    if okm then ctx.magicLevel = tonumber(ml) end
  end
  return ctx
end

-- spells: name -> spell data (SpellInfo.Default). Returns the refilter function (tests call it).
function Core.setupPicker(window, player, spells, env)
  env = env or defaultEnv()
  local tr = env.tr or function(s) return s end
  local list = window and child(window, 'spellList')
  if not list then return nil end
  spells = spells or {}
  local ctx = Core.pickerContext(player, env.translate)

  local rows = {}
  for _, w in ipairs(list:getChildren()) do
    local text = w:getText() or ''
    local name = text:match('^(.-)\n') or text
    local words = text:match('\n(.*)$') or ''
    local data = spells[name] or {}
    local row = {
      widget = w,
      spell = { name = name, words = words, level = data.level, maglevel = data.mlevel or data.maglevel,
        needLearn = data.needLearn, type = data.type, rune = data.rune, vocations = data.vocations }
    }
    -- a spell picker lists spells; a rune entry stays out unless the caller picks runes (env.runes)
    row.hidden = Core.isRune(row.spell) and not env.runes
    rows[#rows + 1] = row
  end
  table.sort(rows, function(a, b) return Core.compare(a.spell, b.spell) end)
  for i, row in ipairs(rows) do
    list:moveChildToIndex(row.widget, i)
    row.status = Core.status(row.spell, ctx)
    if row.status ~= 'ready' then
      -- above the character's level (or not learned): dimmed, the icon dithered
      if row.widget.image and row.widget.image.gray then row.widget.image.gray:setVisible(true) end
      row.widget:setOpacity(0.5)
    end
  end

  local tick, search = child(window, 'tick'), child(window, 'searchText')
  local function refilter()
    local learnedOnly = tick and tick:isChecked() or false
    local text = search and search:getText() or ''
    for _, row in ipairs(rows) do
      local visible = not row.hidden and (not learnedOnly or row.status == 'ready') and Core.textMatches(row.spell, text)
      row.widget:setVisible(visible)
    end
  end
  if tick then
    tick:setText(tr('Only show learned spells'))
    tick:setEnabled(true)
    local saved = env.getSetting and env.getSetting(Core.PICKER_SETTING)
    tick:setChecked(saved == true)
    tick.onCheckChange = function(_, checked)
      if env.setSetting then env.setSetting(Core.PICKER_SETTING, checked == true) end
      refilter()
    end
  end
  if search then
    search.onTextChange = function() refilter() end
  end
  local preview = child(window, 'preview')
  if preview and (preview:getText() or '') == '' then
    preview:setText(tr('Select a spell from the list.'))
  end
  refilter()
  return refilter, rows
end

_G.ChaosSpellCore = Core
return Core
