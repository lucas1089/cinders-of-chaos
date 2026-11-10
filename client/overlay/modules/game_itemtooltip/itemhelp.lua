-- ItemTooltipHelp: the plain lines an item tooltip shows while Alt is held (O372). One line per term on the item:
-- rarity, unique, set, item level, tier, roll range, bound, prefixes and suffixes, corrupted implicit, power, quality,
-- sockets, veil, a few base stats, and each modifier by its key (else by its group). Pure Lua (itemhelp_test.lua).
-- The keys are the modifier attribute keys the server sends (item_tooltip_core.lua: m.k), lower case, without the
-- "chaos_mod_" prefix: server data/lib/chaos_item_mods.lua, chaos_energy_shield.lua, chaos_archery_config.lua (the Chaos
-- modifiers) and chaos_crafting.lua (absorb, skill, element, critical and leech). A key not listed falls back to its
-- group; a modifier with neither gets no line. Every text is a literal tr() key, so check_locales.py sees its pt-BR.
ItemTooltipHelp = {}
local H = ItemTooltipHelp

H.PREFIX = 'chaos_mod_'

local function translate(tr)
  if type(tr) == 'function' then return tr end
  local g = rawget(_G, 'tr')
  if type(g) == 'function' then return g end
  return function(s, ...)
    if select('#', ...) > 0 then return string.format(s, ...) end
    return s
  end
end

-- modifier key -> help line (built per call: tr follows the language chosen now)
function H.modTexts(tr)
  tr = translate(tr)
  return {
    bossdamage = tr('Damage to Elites and Bosses: more damage to elite monsters and bosses.'),
    dodge = tr('Dodge: a chance to avoid an attack completely.'),
    reflect = tr('Reflect Damage: sends a part of the damage you take back to the attacker.'),
    thorns = tr('Thorns: a monster that hits you takes this much damage.'),
    monsterreduction = tr('Damage Taken from Monsters: monsters hurt you less.'),
    block = tr('Block Chance: a chance to block an attack completely.'),
    spellsuppress = tr('Spell Suppression: a chance that a spell hits you for half damage.'),
    armour = tr('Armour: adds to your armour. It takes more off small hits than off big ones.'),
    fireres = tr('Fire Resistance: you take less fire damage.'),
    coldres = tr('Cold Resistance: you take less ice, water and drowning damage.'),
    lightningres = tr('Lightning Resistance: you take less energy, holy and arcane damage.'),
    chaosres = tr('Chaos Resistance: you take less earth, death, life drain and mana drain damage.'),
    allres = tr('All Elemental Resistances: adds to your fire, cold and lightning resistance.'),
    rarity_physicalabsorb = tr('Physical Reduction: takes a share off the physical damage you take, on top of your armour.'),
    bleedchance = tr('Chance to Bleed: your hits can make the target bleed over time.'),
    ignitechance = tr('Chance to Ignite: your hits can set the target on fire.'),
    poisonchance = tr('Chance to Poison: your hits can poison the target.'),
    chillchance = tr('Chance to Chill: your hits can slow the target down.'),
    shockchance = tr('Chance to Shock: a shocked monster takes more damage from everyone.'),
    physpen = tr('Physical Penetration: your physical hits ignore a part of the monster\'s armour.'),
    elepen = tr('Elemental Penetration: your elemental hits ignore a part of the monster\'s resistance.'),
    execute = tr('Execute: a monster below this share of its health dies at once.'),
    dot = tr('Damage over Time: bleeding, burning and poison you cause hurt more.'),
    attackspeed = tr('Attack Speed: you attack more often.'),
    gearspeed = tr('Attack Speed: you attack more often.'),
    bowspeed = tr('Attack Speed: you attack more often.'),
    movespeed = tr('Movement Speed: you walk faster.'),
    lifeonkill = tr('Life on Kill: heals you each time you kill a monster.'),
    manaonkill = tr('Mana on Kill: gives you mana each time you kill a monster.'),
    lifeonhit = tr('Health on Hit: heals you a little with each hit you land.'),
    manaonhit = tr('Mana on Hit: gives you a little mana with each hit you land.'),
    regen = tr('Health Regeneration: you get health back every second.'),
    experience = tr('Experience: more experience from monsters.'),
    goldfind = tr('Gold Find: monsters drop more gold.'),
    itemfind = tr('Item Find: monsters drop more items.'),
    rarityfind = tr('Rarity Find: the items you find are more often rare.'),
    healing = tr('Healing Done: your healing spells and potions heal more.'),
    goblinchance = tr('Treasure Goblin Chance: a treasure goblin appears near you more often.'),
    cdr = tr('Cooldown Reduction: your spells are ready again sooner.'),
    manacost = tr('Mana Cost Reduction: your spells cost less mana.'),
    energyshield = tr('Energy Shield: a shield that takes damage before your health and refills itself.'),
    energyshieldpct = tr('Energy Shield: a shield that takes damage before your health and refills itself.'),
    esrecharge = tr('Faster Energy Shield Recharge: your energy shield refills faster.'),
    bowdistance = tr('Distance Fighting: adds to your ranged skill while you use a bow.'),
    bowcrit = tr('Critical Strike Chance with Bows: more critical hits with a bow.'),
    multishot = tr('Extra Projectile Chance: a chance to shoot one more arrow.'),
    arrowfire = tr('Element damage with Bows: a part of your bow damage becomes this element.'),
    arrowice = tr('Element damage with Bows: a part of your bow damage becomes this element.'),
    arrowenergy = tr('Element damage with Bows: a part of your bow damage becomes this element.'),
    arrowearth = tr('Element damage with Bows: a part of your bow damage becomes this element.'),
    -- O461: the critical pair is two modifiers; the leech pairs of old items still read as a pair
    rarity_criticalhitchance = tr('Critical Strike Chance: your hits can be critical hits that deal more damage.'),
    rarity_criticalhitamount = tr('Critical Strike Damage: your critical hits deal more damage.'),
    lifeleech = tr('Life Leech: a share of the damage you deal comes back to you as health.'),
    lifeleechw = tr('Life Leech with Weapon: a share of the damage of your weapon attacks comes back as health.'),
    manaleech = tr('Mana Leech: a share of the damage you deal comes back to you as mana.'),
    manaleechw = tr('Mana Leech with Weapon: a share of the damage of your weapon attacks comes back as mana.'),
    maxlife = tr('Maximum Life: adds to your maximum health.'),
    maxmana = tr('Maximum Mana: adds to your maximum mana.'),
    manaregen = tr('Mana Regeneration: your mana comes back faster.'),
    strength = tr('Strength: adds strength points, like the passive tree.'),
    dexterity = tr('Dexterity: adds dexterity points, like the passive tree.'),
    intelligence = tr('Intelligence: adds intelligence points, like the passive tree.'),
    spelldamage = tr('Spell Damage: your spells and wand hits deal more damage.'),
    weapondamage = tr('Weapon Damage: this weapon hits harder.'),
    rarity_lifeleechchance = tr('Life Leech: heals you by a part of the damage you deal.'),
    rarity_manaleechchance = tr('Mana Leech: gives you mana from a part of the damage you deal.'),
    rarity_maglevelskill = tr('Magic: adds magic levels, so your spells hit and heal harder.'),
    rarity_shieldskill = tr('Shielding: adds to your shielding skill, so you block more.'),
  }
end

-- modifier group -> help line (absorb, skill, element: the engine modifiers of chaos_crafting.lua)
function H.groupTexts(tr)
  tr = translate(tr)
  return {
    absorb = tr('Absorb: counts toward the resistance of its group: fire, cold, lightning or chaos.'),
    skill = tr('Skill bonus: adds levels to that skill, as if you trained it.'),
    element = tr('Element damage: adds damage of that element to your hits.'),
  }
end

-- the base stat rows (tip.base, k) worth a line
function H.baseTexts(tr)
  tr = translate(tr)
  return {
    attack = tr('Attack: the base damage of the weapon.'),
    defense = tr('Defense: blocks a part of the hits you take.'),
    armor = tr('Armour: lowers the physical damage you take.'),
    dps = tr('Estimated DPS: about how much damage per second your auto attack deals with it.'),
    yourinterval = tr('Your Attack Interval: the seconds between your auto attacks with it.'),
  }
end

-- the key of a modifier as the tables above know it
function H.key(k)
  k = tostring(k or ''):lower()
  if k:sub(1, #H.PREFIX) == H.PREFIX then k = k:sub(#H.PREFIX + 1) end
  return k
end

-- the help line of one modifier row {k, g} (nil: none)
function H.modLine(m, mods, groups)
  if type(m) ~= 'table' then return nil end
  return mods[H.key(m.k)] or (m.g and groups[m.g]) or nil
end

-- the help lines of a tooltip (no repeats, in reading order)
function H.lines(tip, tr)
  tr = translate(tr)
  local out = {}
  if type(tip) ~= 'table' then return out end
  local function add(line) if line then out[#out + 1] = line end end

  if tip.unique and tip.unique.set then
    add(tr('Set: wear more pieces of the set for extra bonuses.'))
  elseif tip.unique then
    add(tr('Unique: a named item with fixed modifiers, often with a power of its own.'))
  elseif type(tip.rarityName) == 'string' then
    add(tr('%s: the rarity. Rarer items roll more modifiers.', tr(tip.rarityName)))
  end
  if tip.set and not tip.unique then add(tr('Set: wear more pieces of the set for extra bonuses.')) end
  if tip.level then add(tr('Item Level: a higher item level can roll higher tiers.')) end
  if tip.quality and (tonumber(tip.quality.q) or 0) > 0 then add(tr('Quality: makes the base stats stronger.')) end

  local base = H.baseTexts(tr)
  for _, b in ipairs(tip.base or {}) do
    add(type(b) == 'table' and base[b.k] or nil)
  end

  local best, range, bound, sides, implicit, power = nil, false, false, false, false, false
  for _, m in ipairs(tip.mods or {}) do
    if type(m) == 'table' then
      local t = tonumber(m.tr)
      if t and (not best or t > best) then best = t end
      if m.lo and m.hi then range = true end
      if m.bd then bound = true end
      if m.sd == 'p' or m.sd == 's' then sides = true end
      if m.sd == 'i' then implicit = true end
      if m.pw then power = true end
    end
  end
  if best then add(tr('T%d: the tier, T1 weak to T8 best.', best)) end
  if range then add(tr('[low-high]: the range this modifier can roll in.')) end
  if sides then add(tr('Prefixes and Suffixes: an item holds a few of each; orbs add, change or remove them.')) end
  if implicit then add(tr('Corrupted implicit: an extra modifier the corruption gave.')) end
  if bound then add(tr('Bound: orbs do not change this modifier.')) end
  if power then add(tr('Power: a special effect; its line says what it does.')) end

  local mods, groups = H.modTexts(tr), H.groupTexts(tr)
  for _, m in ipairs(tip.mods or {}) do
    add(H.modLine(m, mods, groups))
  end

  local s = tip.sockets
  if type(s) == 'table' and (tonumber(s.count) or 0) > 0 then
    add(tr('Sockets: put gems in them for extra bonuses.'))
  end
  if type(tip.veil) == 'table' then
    add(tr('Veiled: a hidden modifier; an Orb of Unveiling shows it.'))
  end

  -- no repeats (two modifiers of one group share a line)
  local seen, list = {}, {}
  for _, line in ipairs(out) do
    if not seen[line] then
      seen[line] = true
      list[#list + 1] = line
    end
  end
  return list
end

return ItemTooltipHelp
