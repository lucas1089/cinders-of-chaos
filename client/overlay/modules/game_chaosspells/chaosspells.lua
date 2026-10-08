-- Registers the Chaos spells (spelldata.lua, generated from the server's spells_chaos.xml) in the client's
-- spell tables, so the spell list, the action bar, hotkeys and cooldown display know them:
--   SpellInfo.Default[name]  the spell (same fields as the client's own entries)
--   SpellIcons[iconKey]      {icon cell, server spell id}; the cells 201..236 of the spell icon sheets that
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

-- The helper (mods/game_helper) only offers spells from its own per-vocation id lists (spelldata.json).
-- Add the Chaos spells to them: attack spells to the shooter list, healing spells to the healing list, support
-- spells to the support list. The helper keys vocations 1 knight, 2 paladin, 3 sorcerer, 4 druid, 5 illusionist
-- (its translateVocation of our server ids), and the promoted ids are those + 10.
local HELPER_VOCATION = { [1] = 3, [2] = 4, [3] = 2, [4] = 1, [5] = 3, [6] = 4, [7] = 2, [8] = 1, [9] = 5, [10] = 5 }
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
  connect(g_game, { onGameStart = onGameStartExtend })
  extendHelper()
  for _, s in ipairs(ChaosSpellData) do
    SpellInfo.Default[s.name] = {
      id = s.id, name = s.name, words = s.words, type = 'Instant', level = s.level, mana = s.mana, soul = 0,
      icon = s.iconKey, group = { [s.group] = s.groupCooldown }, needTarget = s.needTarget, parameter = false,
      range = s.range, exhaustion = s.cooldown, premium = s.premium, vocations = s.vocations
    }
    SpellIcons[s.iconKey] = { s.clientId, s.id }
    if order then
      table.insert(order, s.name)
    end
    added[#added + 1] = s.name
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
  disconnect(g_game, { onGameStart = onGameStartExtend })
end
