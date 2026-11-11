-- Spell modifier masteries (O451): the text of the effects of a mastery node that give one named spell a free support effect.
-- O473 (2026-11-10): the three brand effects are no free support any more: while their spell is cast they add increased damage to the
-- one additive damage pool (server damage_pool_config.lua sources.masteries: +3 each, at most 12 from masteries; the config's `damage`).
-- The tree stat of such an effect is spellMod = <id> (treedata/nodes.lua); the server owns the rules and the numbers
-- (server/data/lib/chaos_spell_masteries_config.lua, data/lib/chaos_supports.lua freeEffect). This file only words each choice:
-- the spell, the support and its numbers, as the picker and the node tooltip show them (passivetree.lua getCustomStatString).
-- Pure, no client API (tested by treespellmods_test.lua, which pins every row to the server's numbers).
--   TreeSpellMods.rows[id]   {spell, support, a, b}: the spell's name, the support key, the numbers of its text
--   TreeSpellMods.text(id)   the line in the player's language, or nil for an id that is no choice
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

TreeSpellMods = {}
local T = TreeSpellMods

-- id = the choice of the server config; a, b = the numbers the text names (fork: enemies, share; echo: chance, share; breadth:
-- radius, share; the others: the one number)
T.rows = {
  [1] = {spell = 'Gorehook', support = 'fork', a = 1, b = 26},
  [2] = {spell = 'Colossus Fall', support = 'echo', a = 11, b = 50},
  [3] = {spell = 'Bastion Cry', support = 'breadth', a = 1, b = 26},
  [4] = {spell = 'Sunspear', support = 'shatter', a = 15},
  [5] = {spell = 'Blessed Earth', support = 'dawnbrand', a = 3},
  [6] = {spell = 'Dawnpiercer', support = 'hex', a = 2},
  [7] = {spell = 'Crimson Covenant', support = 'fork', a = 1, b = 26},
  [8] = {spell = 'Prismatic Rupture', support = 'stormbrand', a = 3},
  [9] = {spell = 'Shuriken Toss', support = 'fork', a = 1, b = 26},
  [10] = {spell = 'Smoke Bomb', support = 'breadth', a = 1, b = 26},
  [11] = {spell = 'Blade Flurry', support = 'echo', a = 11, b = 50},
  [12] = {spell = 'Marrow Bolt', support = 'hex', a = 2},
  [13] = {spell = 'Gravewail', support = 'gravebrand', a = 3},
  [14] = {spell = 'Blightbrand', support = 'shatter', a = 15},
  [15] = {spell = 'Mistborne Strike', support = 'breadth', a = 1, b = 26},
  [16] = {spell = 'Sundering Palm', support = 'shatter', a = 15},
  [17] = {spell = 'Whirling Heel', support = 'quickening', a = 4},
  [18] = {spell = 'Consecration', support = 'echo', a = 11, b = 50},
  [19] = {spell = 'Hallowed Cut', support = 'hex', a = 2},
  [20] = {spell = 'Bell of Reckoning', support = 'dawnbrand', a = 3}
}

function T.text(id)
  local r = T.rows[tonumber(id) or -1]
  if not r then return nil end
  local k = r.support
  if k == 'fork' then
    return tr('%s forks to %d more enemy within 3 sqm for %d%% of the hit. A reduced Fork rune, free.', r.spell, r.a, r.b)
  elseif k == 'echo' then
    return tr('%s: %d%% chance that its hits strike again for %d%%. A reduced Echo rune, free.', r.spell, r.a, r.b)
  elseif k == 'breadth' then
    return tr('%s: enemies it missed within %d sqm take %d%% of its hit. A reduced Breadth rune, free.', r.spell, r.a, r.b)
  elseif k == 'shatter' then
    return tr('%s: enemies next to the target take %d%% of the hit. A reduced Shatter rune, free.', r.spell, r.a)
  elseif k == 'hex' then
    return tr('%s: monsters it hits take +%d%% damage from everyone for 4 s. A reduced Hex rune, free.', r.spell, r.a)
  elseif k == 'quickening' then
    return tr('%s: its cooldown is %d%% shorter. A reduced Quickening rune, free.', r.spell, r.a)
  elseif k == 'dawnbrand' or k == 'gravebrand' or k == 'stormbrand' then
    return tr('%s: +%d increased damage while it is cast. It joins the one damage pool of the tree and gear (at most +12 from masteries).', r.spell, r.a)
  end
  return nil
end

return T
