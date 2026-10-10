-- Registers the Chaos spells (spelldata.lua, generated from the server's spells_chaos.xml) in the client's
-- spell tables, so the spell list, the action bar, hotkeys and cooldown display know them:
--   SpellInfo.Default[name]  the spell (same fields as the client's own entries)
--   SpellIcons[iconKey]      {icon cell, server spell id}; the cells 201..249 of the spell icon sheets that
--                            client/overlay/data/images/game/spells holds (tools/gen_all_spell_icons.py draws them)
--   SpelllistSettings.Default.spellOrder   so the spell list shows them
-- It also gives the client's stock spell entries their Chaos names and words (ChaosSpellNames in spelldata.lua), the
-- same ones server/tools/rename_spells.py gives them on the server.

local added = {}
local renamed = {} -- new name -> {old name, old words} of the client's own entries

-- Give the client's stock spell entries their Chaos names and words (ChaosSpellNames: old words -> {name, words}).
-- Keys of SpellInfo, the spell list order and the rune table all use the name, so all three follow.
local function renameStockSpells(order)
  local newOf, entryOf = {}, {}
  for oldName, spell in pairs(SpellInfo.Default) do
    local entry = spell.words and ChaosSpellNames[spell.words:lower()]
    if entry and (entry.name == oldName or not SpellInfo.Default[entry.name]) then
      newOf[oldName] = entry.name
      entryOf[oldName] = entry
    end
  end
  for oldName, newName in pairs(newOf) do
    local spell = SpellInfo.Default[oldName]
    renamed[newName] = { oldName, spell.words }
    SpellInfo.Default[oldName] = nil
    spell.name = newName
    spell.words = entryOf[oldName].words
    SpellInfo.Default[newName] = spell
  end
  if order then
    for i, name in ipairs(order) do
      order[i] = newOf[name] or name
    end
  end
  for _, rune in pairs(SpellRunesData or {}) do
    if rune.name and newOf[rune.name] then
      rune.name = newOf[rune.name]
    end
  end
  return newOf
end

local function restoreStockSpells(order)
  local oldOf = renamed
  renamed = {}
  local oldNameOf = {}
  for newName, old in pairs(oldOf) do
    oldNameOf[newName] = old[1]
    local spell = SpellInfo.Default[newName]
    if spell then
      SpellInfo.Default[newName] = nil
      spell.name, spell.words = old[1], old[2]
      SpellInfo.Default[old[1]] = spell
    end
  end
  if order then
    for i, name in ipairs(order) do
      order[i] = oldNameOf[name] or name
    end
  end
  for _, rune in pairs(SpellRunesData or {}) do
    if rune.name and oldNameOf[rune.name] then
      rune.name = oldNameOf[rune.name]
    end
  end
end

-- The client's stock spell entries list the old vocation ids; the server moved those kits to the classes
-- (server/tools/add_vocations.py): druid spells -> Mystic (1) and Illusionist (10), elder druid spells -> Illusionist,
-- knight spells also the Berserker (14), paladin spells also the Beastmaster (15), and the casters' stock healing and
-- support instants also the Necromancer line (20-22; no rune conjuring, no stock summon), the stock utility spells
-- also the Thief, Monk and Templar lines (ChaosStockSpellLines). The spell list filters by these lists.
local oldVocations = {} -- spell entry -> its own list, restored at terminate

local function remapStockVocations()
  for name, spell in pairs(SpellInfo.Default) do
    if type(spell.vocations) == 'table' and not oldVocations[spell] then
      local has, list = {}, {}
      for _, v in ipairs(spell.vocations) do
        has[v] = true
        list[#list + 1] = v
      end
      local function add(v)
        if not has[v] then
          has[v] = true
          list[#list + 1] = v
        end
      end
      if has[2] then add(1); add(10) end
      if has[6] then add(10) end
      if has[4] or has[8] then add(14) end
      if has[3] or has[7] then add(15) end
      -- the Necromancer line (20-22): the casters' stock healing and support instants (server/tools/add_vocations.py)
      local group = type(spell.group) == 'table' and spell.group or {}
      if (has[1] or has[2]) and not group[1] and spell.type ~= 'Conjure'
          and spell.words ~= 'utevo res' and spell.words ~= 'vael kal' then
        add(20); add(21); add(22)
      end
      -- the stock utility spells of the Thief, Monk and Templar lines (ChaosStockSpellLines, spelldata.lua)
      for _, v in ipairs(ChaosStockSpellLines and spell.words and ChaosStockSpellLines[spell.words:lower()] or {}) do
        add(v)
      end
      if #list ~= #spell.vocations then
        oldVocations[spell] = spell.vocations
        spell.vocations = list
      end
    end
  end
end

local function restoreStockVocations()
  for spell, list in pairs(oldVocations) do
    spell.vocations = list
  end
  oldVocations = {}
end

-- The helper (mods/game_helper) only offers spells from its own per-vocation id lists (spelldata.json).
-- Add the Chaos spells to them: attack spells to the shooter list, healing spells to the healing list, support
-- spells to the support list. The helper keys its classes 1 warrior, 2 ranger, 3 mystic / elementalist, 4 illusionist
-- (the druid's healing lists), 5 the old illusionist, 6 thief, 7 necromancer, 8 monk, 9 templar (its translateVocation
-- of our server ids, base patch 0016), and the promoted ids are those + 10.
local HELPER_VOCATION = { [1] = 3, [3] = 2, [4] = 1, [5] = 3, [7] = 2, [8] = 1, [10] = 4,
  [11] = 6, [12] = 6, [13] = 6, [14] = 1, [15] = 2, [17] = 8, [18] = 8, [19] = 8, [20] = 7, [21] = 7, [22] = 7,
  [23] = 9, [24] = 9, [25] = 9 }
local helperExtended = false

local function addOnce(list, value)
  if not table.contains(list, value) then
    table.insert(list, value)
  end
end

local function extendHelper()
  if helperExtended then
    return true
  end
  local data = modules.game_helper and modules.game_helper.HelperSpellData or HelperSpellData
  if not data or not data.isLoaded or not data.isLoaded() then
    return false
  end
  local byVocation = data.getSpellFilterByVocation()
  local healing = data.getHealingSpellFilter()
  local support, supportSet = data.getSupportSpellsWhitelist(), data.getSupportSpellsWhitelistSet()
  for _, s in ipairs(ChaosSpellData) do
    local vocs = {}
    for _, v in ipairs(s.vocations) do
      local h = HELPER_VOCATION[v]
      if h then
        vocs[h] = true
        vocs[h + 10] = true
      end
    end
    for v in pairs(vocs) do
      byVocation[v] = byVocation[v] or {}
      addOnce(byVocation[v], s.id)
      if s.group == 2 then
        healing[s.id] = healing[s.id] or {}
        addOnce(healing[s.id], v)
      elseif s.group == 3 then
        support[v] = support[v] or {}
        supportSet[v] = supportSet[v] or {}
        addOnce(support[v], s.id)
        supportSet[v][s.id] = true
      end
    end
  end
  helperExtended = true
  return true
end

-- Spells that cost a percentage of the maximum mana (manaPercent, the server's manapercent): the entry's mana is kept at
-- the local player's current cost, so the action bar shows it and greys the spell out like a flat cost
local function updatePercentMana(localPlayer, mana, maxMana)
  maxMana = maxMana or (localPlayer and localPlayer:getMaxMana()) or 0
  for _, s in ipairs(ChaosSpellData) do
    local spell = s.manaPercent and SpellInfo.Default[s.name]
    if spell then
      spell.mana = math.floor(maxMana * s.manaPercent / 100)
    end
  end
end

local function onGameStartMana()
  updatePercentMana(g_game.getLocalPlayer())
end

-- signal handlers must not return a truthy value: signalcall stops at it, and every onGameStart handler
-- connected after this one (passive tree, dungeons, bank, ...) would never run
local function onGameStartExtend()
  extendHelper()
end

function init()
  if not SpellInfo or not SpellInfo.Default or not SpellIcons then
    g_logger.warning('[chaosspells] spell tables not found, Chaos spells not registered')
    return
  end
  local order = SpelllistSettings and SpelllistSettings.Default and SpelllistSettings.Default.spellOrder
  renameStockSpells(order)
  remapStockVocations()
  connect(g_game, { onGameStart = onGameStartExtend })
  connect(g_game, { onGameStart = onGameStartMana })
  connect(LocalPlayer, { onManaChange = updatePercentMana })
  extendHelper()
  for _, s in ipairs(ChaosSpellData) do
    SpellInfo.Default[s.name] = {
      id = s.id, name = s.name, words = s.words, type = 'Instant', level = s.level, mana = s.mana, soul = 0,
      icon = s.iconKey, group = { [s.group] = s.groupCooldown }, needTarget = s.needTarget, parameter = false,
      range = s.range, exhaustion = s.cooldown, premium = s.premium, vocations = s.vocations, manaPercent = s.manaPercent
    }
    SpellIcons[s.iconKey] = { s.clientId, s.id }
    if order then
      table.insert(order, s.name)
    end
    added[#added + 1] = s.name
  end
  if g_game.isOnline() then
    onGameStartMana()
  end
end

function terminate()
  local mine = {}
  for _, name in ipairs(added) do
    mine[name] = true
    local spell = SpellInfo.Default[name]
    if spell then
      SpellIcons[spell.icon] = nil
    end
    SpellInfo.Default[name] = nil
  end
  local order = SpelllistSettings and SpelllistSettings.Default and SpelllistSettings.Default.spellOrder
  if order then
    for i = #order, 1, -1 do
      if mine[order[i]] then
        table.remove(order, i)
      end
    end
  end
  added = {}
  restoreStockSpells(order)
  restoreStockVocations()
  disconnect(g_game, { onGameStart = onGameStartExtend })
  disconnect(g_game, { onGameStart = onGameStartMana })
  disconnect(LocalPlayer, { onManaChange = updatePercentMana })
end
