-- Crafting Guide (owner request 2026-11-03: "explain the crafting gems better"): the pure part of the Guide window of
-- the crafting bench (craftguide.lua). Orbs: the basics, a safe first plan, and per orb when to use it and how risky
-- it is. Gems: how they work and the table of every gem's bonus per slot group and quality, from the server's gemguide
-- message (ChaosGems.guide()). No engine calls; tr is passed in (craftguideview_test.lua). Lua 5.1 / LuaJIT and 5.3.
CraftGuideView = {}
local V = CraftGuideView

-- risk of an orb: safe (does what it says), gamble (may not help), final (cannot be undone)
V.RISK = {
  transmutation = 'safe', alchemy = 'safe', exalted = 'safe', annulment = 'gamble', scouring = 'safe',
  chaos = 'gamble', divine = 'gamble', sockets = 'gamble', tempering = 'safe', binding = 'safe', excision = 'safe',
  reforging = 'gamble', ruin = 'gamble', whetstone = 'safe', unveiling = 'final', ember = 'safe', crown = 'safe',
  void = 'final',
}
V.RISK_COLOR = { safe = '#9fdc7f', gamble = '#f6cf72', final = '#ff8a5a' }

function V.riskText(risk, tr)
  if risk == 'safe' then return tr('Safe: it does what it says.') end
  if risk == 'gamble' then return tr('Gamble: the result is random.') end
  if risk == 'final' then return tr('Final: it cannot be undone.') end
  return ''
end

-- when to use an orb, in plain words ('' for an orb this guide does not know)
function V.advice(key, tr)
  if key == 'transmutation' then return tr('Your first orb. Use it on a plain item to give it a rarity and a few bonuses.') end
  if key == 'alchemy' then return tr('Like Awakening, but it can give a better rarity. Save it for a plain item with a good base and a high item level.') end
  if key == 'exalted' then return tr('Use it when the item has a free prefix or suffix: it adds one more bonus.') end
  if key == 'annulment' then return tr('Removes a random bonus. Bind the bonuses you want to keep first.') end
  if key == 'scouring' then return tr('Start over: the item becomes plain again, ready for a new Awakening or Gilding.') end
  if key == 'chaos' then return tr('Rerolls every bonus that is not bound. Bind your best bonus first, then reroll the rest.') end
  if key == 'divine' then return tr('Raises the rarity, but the bonuses are rolled again. Use the Crown Orb to keep them.') end
  if key == 'sockets' then return tr('Rolls a new number of sockets. Gems already in the item stay.') end
  if key == 'tempering' then return tr('The bonuses keep their tiers and get new numbers. Good when the tiers are right but the numbers are low.') end
  if key == 'binding' then return tr('Protects one bonus you pick from every orb. Use it before Upheaval or Unmaking.') end
  if key == 'excision' then return tr('Removes the bonus you pick. The safe way to get rid of a bad one.') end
  if key == 'reforging' then return tr('Rolls the tier and number of one bonus you pick again. It can go up or down.') end
  if key == 'ruin' then return tr('Often nothing happens; sometimes the bonuses get better. It never makes the item worse.') end
  if key == 'whetstone' then return tr('Adds 1% quality. Quality makes the whole item a little stronger.') end
  if key == 'unveiling' then return tr('Shows three choices for a veiled bonus. Pick one; the choice stays.') end
  if key == 'ember' then return tr('The best upgrade: one bonus you pick goes up exactly one tier.') end
  if key == 'crown' then return tr('Raises the rarity one step, keeps every bonus and adds one.') end
  if key == 'void' then return tr('The last orb for a finished Rare or better item: a big gamble, and after it no orb changes the item.') end
  return ''
end

-- the basics, one paragraph each: {heading, text}
function V.basics(tr)
  return {
    { tr('Rarity'), tr('Common, Uncommon, Magic, Rare, Legendary, Divine. A better rarity has room for more bonuses. Uniques are fixed: orbs do not change them.') },
    { tr('Bonuses'), tr('Each line of an item is a bonus (a modifier). Bonuses are prefixes or suffixes, and each rarity has a limit of each.') },
    { tr('Tiers'), tr('A bonus has a tier from T1 (weak) to T8 (best). The item level decides the best tier it can roll.') },
    { tr('Bound'), tr('A bound bonus is safe: orbs leave it alone. Only an Orb of Erasure frees it.') },
    { tr('Preview'), tr('Put the item on the bench: the green line under each orb shows what it would do. Orbs also work with Use on the item.') },
  }
end

-- a safe order to try things, one step per line
function V.plan(tr)
  return {
    tr('1. Lock the gear you want to keep. Salvage the rest into shards and combine the shards into orbs (Salvage tab).'),
    tr('2. A plain item with a good base: Orb of Awakening, or Orb of Gilding for a better rarity.'),
    tr('3. A free prefix or suffix: Orb of Grafting adds a bonus.'),
    tr('4. A bad bonus: Orb of Excision removes the one you pick.'),
    tr('5. A great bonus: Orb of Binding keeps it safe, then Orb of Upheaval rerolls the others.'),
    tr('6. Make good bonuses better: Ember Orb (one tier up), Orb of Tempering (new numbers), Whetstone (quality).'),
    tr('7. Raise the rarity: Crown Orb keeps every bonus and adds one.'),
    tr('8. Only at the end: the gambles. A Void Orb is for good.'),
  }
end

-- gems: one paragraph each
function V.gemBasics(guide, tr)
  guide = type(guide) == 'table' and guide or {}
  local cost = type(guide.removeCost) == 'table' and guide.removeCost or {}
  local costs = {}
  for i, c in ipairs(cost) do costs[i] = V.number(c) end
  local tiers = type(guide.tiers) == 'table' and guide.tiers or {}
  return {
    { tr('What a gem does'), tr('A gem sits in a socket of your gear and gives one bonus. The same gem gives a different bonus in a weapon, in armour (helmet, armour, legs, boots, shield) and in jewellery (amulet, ring): see the table below.') },
    { tr('Where gems come from'), tr('Monsters drop them, stronger monsters more often; higher monster levels drop better qualities. Bounties, rifts and bosses give them too, and the Candlemarks shop sells some.') },
    { tr('Putting a gem in'), tr('Use the gem, then click the item. The item needs an empty socket. An %s rolls a new number of sockets; better rarities can hold more.', guide.socketOrb or 'Orb of Sockets') },
    { tr('Better gems'), tr('Three gems of the same kind and quality become one of the next quality: use the stack, then click the same stack. Qualities: %s.', table.concat(tiers, ', ')) },
    { tr('Taking a gem out'), tr('On the crafting bench, under the bonuses of the item: Remove gives the gem back for gold (%s by quality), Shatter is free and destroys it.', table.concat(costs, ' / ')) },
    { tr('Limits'), tr('Each bonus has a total limit from all your gems together, shown after it in the table.') },
  }
end

-- 12345 -> "12,345"
function V.number(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''))
end

-- "2 / 4 / 6 / 9 / 12%" (pct), "20 / 45 / ..." (flat), a pair as two parts joined by ", "
local function series(values, suffix)
  local parts = {}
  for i, v in ipairs(values or {}) do parts[i] = tostring(v) end
  return table.concat(parts, ' / ') .. (suffix or '')
end

function V.effectText(def, values, values2, tr)
  def = type(def) == 'table' and def or {}
  local label = def.label and tr(def.label) or '?'
  if def.fmt == 'flat' then
    return label .. ' +' .. series(values)
  elseif def.fmt == 'pair' then
    return label .. ' +' .. series(values, '%') .. ', ' .. (def.label2 and tr(def.label2) or '?') .. ' +' .. series(values2, '%')
  end
  return label .. ' +' .. series(values, '%')
end

function V.capText(def)
  def = type(def) == 'table' and def or {}
  if not def.cap then return '' end
  local unit = def.fmt == 'flat' and '' or '%'
  return tostring(def.cap) .. unit
end

-- the gem table: one row per gem kind {name, color, look (client id of the best quality), groups = [{label, text, cap}]}
function V.gemRows(guide, tr)
  local rows = {}
  if type(guide) ~= 'table' or type(guide.types) ~= 'table' then return rows end
  local effects = type(guide.effects) == 'table' and guide.effects or {}
  local labels = { weapon = tr('Weapon'), armour = tr('Armour'), jewel = tr('Jewellery') }
  for _, t in ipairs(guide.types) do
    local looks = type(t.look) == 'table' and t.look or {}
    local row = { name = t.name or '?', color = t.color or '#d6c9ae', look = looks[#looks] or 0, groups = {} }
    for _, group in ipairs({ 'weapon', 'armour', 'jewel' }) do
      local e = t[group]
      if type(e) == 'table' then
        local def = effects[e.effect]
        row.groups[#row.groups + 1] = { label = labels[group], text = V.effectText(def, e.values, e.values2, tr),
          cap = V.capText(def) }
      end
    end
    rows[#rows + 1] = row
  end
  return rows
end

return CraftGuideView
