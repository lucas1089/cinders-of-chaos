-- Crafting bench, Salvage tab: the recipe grid's logic without client API (tested by recipeview_test.lua with LuaJIT
-- and Lua 5.3). A recipe of state.salvage.recipes is either a rune shard recipe (paid with rune shards, sv.shards; Shift
-- recycles the orb back) or a shard recipe (Ember / Crown Shards -> their orb: `input` is the item it eats, `have` how
-- many the player has, `inputName` its plural; no recycling). The server checks everything again (salvage.lua combine).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

CraftingRecipeView = CraftingRecipeView or {}
local V = CraftingRecipeView

local floor = math.floor

-- 1500 -> '1,500'
function V.thousands(n)
  local s = string.format('%d', floor(tonumber(n) or 0))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''))
end

function V.isShardRecipe(r)
  return (tonumber(r and r.input) or 0) > 0
end

-- what the player has of the recipe's currency
function V.have(r, sv)
  if V.isShardRecipe(r) then return tonumber(r.have) or 0 end
  return tonumber(sv and sv.shards) or 0
end

-- the plural of the recipe's currency
function V.currency(r, sv)
  if V.isShardRecipe(r) then return r.inputName or 'shards' end
  return (sv and sv.shardName) or 'shards'
end

-- the cost line of the cell: '25 shards' (rune shards), '1,500 Ember Shards' (the server's item name)
function V.costText(r, sv)
  local cost = tonumber(r.cost) or 0
  if V.isShardRecipe(r) then return V.thousands(cost) .. ' ' .. V.currency(r, sv) end
  return tr('%d shards', cost)
end

-- the orbs a click makes: 1, with Ctrl as many as the currency pays for, at most `max` (0 when it pays for none)
function V.combineCount(have, cost, max, ctrl)
  have, cost = tonumber(have) or 0, tonumber(cost) or 0
  if cost <= 0 or have < cost then return 0 end
  if not ctrl then return 1 end
  return math.max(1, math.min(tonumber(max) or 1, floor(have / cost)))
end

-- recycling back into rune shards (Shift+click): only rune shard recipes with a share back
function V.recycleBack(r)
  if V.isShardRecipe(r) then return 0 end
  return tonumber(r.back) or 0
end

-- the button: a shard recipe needs its shards; a rune shard recipe needs salvage installed and shards or an orb to recycle
function V.enabled(r, sv)
  local enough = V.have(r, sv) >= (tonumber(r.cost) or 0)
  if V.isShardRecipe(r) then return enough end
  return sv.installed ~= false and (enough or (V.recycleBack(r) > 0 and (tonumber(r.count) or 0) > 0))
end

function V.tip(r, sv)
  local cost = tonumber(r.cost) or 0
  local name = r.name or r.key or '?'
  local text = tr('%d %s -> 1 %s (you have %d).\nCtrl+click: as many as you can, up to %d.', cost, V.currency(r, sv), name,
    tonumber(r.count) or 0, tonumber(sv.maxCombine) or 1)
  if V.isShardRecipe(r) then
    text = text .. '\n' .. tr('Your %s: %s.', V.currency(r, sv), V.thousands(V.have(r, sv)))
  end
  local back = V.recycleBack(r)
  if back > 0 then
    text = text .. '\n' .. tr('Shift+click: recycle your %s into %d %s each.', name, back, V.currency(r, sv))
  end
  return text
end
