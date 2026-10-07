-- Registers the Chaos spells (spelldata.lua, generated from the server's spells_chaos.xml) in the client's
-- spell tables, so the spell list, the action bar, hotkeys and cooldown display know them:
--   SpellInfo.Default[name]  the spell (same fields as the client's own entries)
--   SpellIcons[iconKey]      {icon cell, server spell id}; the cells 201..236 are appended to the client's
--                            spell icon sheets by tools/append_spell_icons.py (tools/assemble_client.sh does it)
--   SpelllistSettings.Default.spellOrder   so the spell list shows them
-- Without the extended icon sheets the new spells still work but their icons are blank.

local added = {}

function init()
  if not SpellInfo or not SpellInfo.Default or not SpellIcons then
    g_logger.warning('[chaosspells] spell tables not found, Chaos spells not registered')
    return
  end
  local order = SpelllistSettings and SpelllistSettings.Default and SpelllistSettings.Default.spellOrder
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
end
