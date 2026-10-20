-- The client's stock spell entries lined up with the server (pure Lua: no engine calls; tests: spellfix_test.lua).
--
-- The server tells the client a spell's cooldown by its spell id (ProtocolGame::sendSpellCooldown). The helper, the action
-- bar and the cooldown bar look the spell up by that id, so an entry whose id is not the server's never sees its
-- cooldown (the helper cast it again and the server answered "You are exhausted"), and two entries with one id share
-- every cooldown and every helper rule (a rule on Shadow Step could resolve to the stock Great Fire Wave entry and was
-- skipped). Measured against the installed spells.xml (base server + server/tools/install_all.py, 2026-10-13):
--   * ten stock entries had other ids than the server (STOCK, id) and six more follow the server's spell ids below 256
--     (server/tools/patch_spell_ids.py: the engine keeps a spell id in one byte);
--   * 42 stock entries are spells the server does not have (stock words no rename gives); four of them held the ids of
--     Chaos spells (Divine Dazzle 238 / Shadow Veil, Sap Strength 244 / Iaijutsu, Cancel Magic Shield 245 / Bushido
--     Focus, Find Fiend 248 / Wild Bond). They keep their entry (the spell list and other modules know them by name)
--     but are marked notOnServer and moved to id + OFF_SERVER, out of the one-byte range of the server's ids;
--   * the numbers the helper decides with (mana, level, groups, target, range, the server vocation ids) where the stock
--     entry differs;
--   * the rune table's groups where the server puts the rune in another group.
-- The helper's own id lists (mods/game_helper/spelldata.json, keyed by the stock ids) follow through remapHelper.

ChaosSpellFix = {}
local F = ChaosSpellFix
-- the module is sandboxed: the global must be set on _G for the base's action bar and hotkeys (base patch 0079)
_G.ChaosSpellFix = F

F.OFF_SERVER = 1000

-- by the entry's (Chaos) words; every field given replaces the entry's own
F.STOCK = {
  ["saen gal kin"] = { id = 101, level = 300 },                     -- Heartwood Embrace (client 242)
  ["saen ama brak"] = { id = 102 },                                 -- Iron Salve (239)
  ["saen zar ael"] = { id = 103 },                                  -- Rebirth of Flesh (241)
  ["kah gro"] = { id = 171, group = { [1] = 2000 }, vocations = { 1, 5 } }, -- Sunder Guard (243; server 106 -> 171;
                                                                    -- attack group 2 s, server patch_spell_timings.py)
  ["drai gal pyr ul"] = { id = 163 },                               -- Pyre Torrent (240)
  ["kah tin gor"] = { id = 172 },                                   -- Bog Splatter (174)
  ["saen tin"] = { id = 174 },                                      -- Arcane Stitch (172)
  ["saen tin brak"] = { id = 175 },                                 -- Salve of Scars (170)
  ["drai ira vas sol"] = { id = 34, level = 300, range = 7, needTarget = true, vocations = { 3, 7, 15 } }, -- Radiant Shard (258)
  ["drai zar nyx"] = { id = 35, level = 300, group = { [1] = 2000 }, vocations = { 1, 5 } }, -- Lance of the Grave (260)
  ["kah rek sang"] = { id = 37, level = 300, mana = 100, range = 7, vocations = { 4, 8, 14 } }, -- Headsman's Hurl (261)
  ["drai orr hyr"] = { id = 40, level = 300, group = { [1] = 2000 }, vocations = { 1, 10 } }, -- Shatterfrost (263/262)
  ["drai orr gor"] = { id = 41, level = 300, group = { [1] = 2000 }, vocations = { 1, 10 } }, -- Quakeburst (262/263)
  ["vael mur sol"] = { id = 46, level = 300, vocations = { 3, 7, 15 } },         -- Hallowed Ground (268)
  ["vok rek kal"] = { range = 7, needTarget = true },               -- Duelist's Oath: the server needs a target
  ["saen kin"] = { mana = 140 },                                    -- Kindred Mend
  ["drai gor ul"] = { mana = 180 },                                 -- Bramble Fan (server patch_spell_timings.py)
  ["saen"] = { vocations = { 1, 3, 4, 5, 7, 8, 10, 14, 15, 20, 21, 22 } }, -- Minor Mending: the Warrior line too
  ["kah tin zhul"] = { vocations = { 1, 5, 10 } },                  -- Static Sting: the Illusionist too
  ["kah gal brak"] = { group = { [1] = 4000 } },                    -- Ruinous Cleave
  ["kah zar pyr"] = { group = { [1] = 4000 } },                     -- the Supreme strikes: attack group 4 s, no
  ["kah zar zhul"] = { group = { [1] = 4000 } },                    -- ultimate strikes group on the server
  ["kah zar hyr"] = { group = { [1] = 4000 } },
  ["kah zar gor"] = { group = { [1] = 4000 } },
  ["vyr ira sol"] = { group = { [3] = 10000, [2] = 10000 }, exhaustion = 2000 }, -- Hawkeye: also the healing group
  ["tor ira sol"] = { group = { [3] = 2000 }, exhaustion = 2000 },  -- Windrunner
  ["vyr vas kin"] = { mana = 0 },                                   -- the communions cost no mana on the server
  ["tor vas kin"] = { mana = 0 },
  ["reth vas kin"] = { mana = 0 },
  ["hesh vas kin"] = { mana = 0 },
  ["kah rek zhul"] = { range = 5, exhaustion = 8000 },              -- Skyfang
  ["kah brak"] = { exhaustion = 2000, level = 8, mana = 10 },       -- Bonebreaker: 2 s, level 8, 10 mana (server patch_spell_timings.py)
  ["kah sag"] = { level = 8, mana = 20 },                           -- Phantom Javelin: level 8, 20 mana (server patch_spell_timings.py)
  ["kah vas"] = { mana = 60 },                                      -- Earthrend: the Warrior line's mana runway
  ["kah"] = { mana = 40 },                                          -- Reaver's Spin
  ["kah ti"] = { mana = 55 },                                       -- Scything Arc
  ["kah gal"] = { mana = 100 },                                     -- Butcher's Gyre
  ["hesh sol"] = { exhaustion = 40000 },                            -- Glare of Dawn
  ["tor ael"] = { exhaustion = 2000 },                              -- Ward of the Mind
  ["drai pyr ul"] = { exhaustion = 4000 },                          -- Cinder Fan
  ["drai hyr ul"] = { exhaustion = 4000 },                          -- Glacier Fan
  ["drai nov pyr ul"] = { exhaustion = 4000 },                      -- Novice's Cinders
  ["drai tin pyr ul"] = { exhaustion = 4000 },                      -- Searing Gust
}

-- base server spells the client's table has no entry for (the base server's own Illusionist spells, scripts
-- custom/illusionist_class/): without one the helper and the action bar cannot cast them. game_chaosspells adds them like
-- the Chaos spells; the numbers are the installed server's (server/data/spells/stock_spells.csv, checked by
-- spellfix_test.lua), the icon a stock spell's cell (icon = client icon cell). Found by the rotation live check
-- (2026-10-14): the Auto rotation of a Mystic picked Bewitching Hex and Arcane Ripple and the helper had no entry.
F.EXTRA = {
  { id = 168, name = "Riftbolt", words = "kah ath", level = 12, mana = 20, cooldown = 2000, groupCooldown = 2000,
    needTarget = false, range = 3, vocations = { 1, 5, 10 }, icon = 29 },
  { id = 52, name = "Crossfire Hex", words = "drai xir", level = 38, mana = 140, cooldown = 4000, groupCooldown = 2000,
    needTarget = false, range = 0, vocations = { 1, 10 }, icon = 54 },
  { id = 85, name = "Arcane Ripple", words = "drai ondr", level = 40, mana = 175, cooldown = 4000, groupCooldown = 2000,
    needTarget = true, range = 4, vocations = { 1, 10 }, icon = 43 },
  { id = 53, name = "Bewitching Hex", words = "drai glam", level = 60, mana = 75, cooldown = 4000, groupCooldown = 2000,
    needTarget = true, range = 4, vocations = { 1, 10 }, icon = 56 },
  { id = 47, name = "Fading Step", words = "drai gal vas ylth", level = 100, mana = 1350, cooldown = 40000,
    groupCooldown = 4000, needTarget = false, range = 0, vocations = { 1, 10 }, icon = 50 },
  { id = 165, name = "Gravity Snare", words = "rhut mur", level = 150, mana = 370, cooldown = 8000, groupCooldown = 2000,
    needTarget = false, range = 0, vocations = { 1, 10 }, icon = 41 },
}

-- rune item (client id) -> the server's group (1 attack, 2 healing, 3 support)
F.RUNES = {
  [3153] = { group = 2 }, -- Purge Rune
  [3156] = { group = 1 }, -- Thicket Rune
  [3180] = { group = 1 }, -- Bastion Rune
  [3177] = { group = 3 }, -- Beastbond Rune
}

-- Chaos spells the helper does not offer: toggles (a second cast switches a vigil off again), the teleport home and the
-- dash (a rotation would throw the character around)
F.HELPER_EXCLUDE = {
  [179] = true, [255] = true, [161] = true, [162] = true, -- Vigil of Wrath, Iron, Haste, Clarity
  [254] = true,                                           -- Town Portal
  [232] = true,                                           -- Flickerdash
}

local function set(undo, t, k, v)
  undo[#undo + 1] = { t, k, t[k] }
  t[k] = v
end

-- info: SpellInfo.Default; icons: SpellIcons; runes: SpellRunesData; serverWords: set of the words the server has (the
-- renamed stock words and the Chaos words); removedWords: set of the words of the spells the server took out again
-- (ChaosRemovedSpells, old and new words: the conjure spells). Returns the undo list, the id map of the stock ids that
-- changed (idMap[old] = new id, or false for a spell the server does not have) and the set of the ids of the removed
-- spells. A removed spell keeps its entry and its id (the rune cooldown icons use the conjure ids) but is marked
-- notOnServer, so the helper never casts it, and remapHelper takes it out of the helper's lists.
function F.apply(info, icons, runes, serverWords, removedWords)
  local undo, idMap, removedIds = {}, {}, {}
  for _, spell in pairs(info) do
    local words = spell.words and spell.words:lower()
    local fix = words and F.STOCK[words]
    local old = spell.id
    if words and removedWords and removedWords[words] then
      if not spell.notOnServer then
        set(undo, spell, "notOnServer", true)
      end
      if type(old) == "number" then
        removedIds[old] = true
      end
    elseif fix then
      for k, v in pairs(fix) do
        set(undo, spell, k, v)
      end
    elseif words and not serverWords[words] and not spell.notOnServer then
      set(undo, spell, "notOnServer", true)
      if type(old) == "number" and old < F.OFF_SERVER then
        set(undo, spell, "id", old + F.OFF_SERVER)
      end
    end
    -- every spell and rune is free (server patch_free_spells.py, server/README.md "Free spells")
    if spell.premium then
      set(undo, spell, "premium", false)
    end
    if spell.id ~= old and type(old) == "number" then
      idMap[old] = not spell.notOnServer and spell.id or false
      local icon = icons and spell.icon and icons[spell.icon]
      if icon and icon[2] == old then
        set(undo, icon, 2, spell.id)
      end
    end
  end
  for item, fix in pairs(F.RUNES) do
    local rune = runes and runes[item]
    if rune then
      for k, v in pairs(fix) do
        set(undo, rune, k, v)
      end
    end
  end
  for _, rune in pairs(runes or {}) do
    if rune.premium then
      set(undo, rune, "premium", false)
    end
  end
  return undo, idMap, removedIds
end

-- the words of ChaosRemovedSpells (old -> new words) as a set
function F.removedWords(removed)
  local s = {}
  for old, new in pairs(removed or {}) do
    s[old:lower()] = true
    s[new:lower()] = true
  end
  return s
end

function F.restore(undo)
  for i = #undo, 1, -1 do
    local u = undo[i]
    u[1][u[2]] = u[3]
  end
end

-- the stock id a current id stood for in the helper's lists: nil when that stock spell moved away and nothing else
-- of the stock list took the id (a Chaos spell has it now)
local function oldIdFunc(idMap)
  local inverse, moved = {}, {}
  for old, new in pairs(idMap) do
    moved[old] = true
    if new then
      inverse[new] = old
    end
  end
  return function(id)
    if inverse[id] then
      return inverse[id]
    end
    if moved[id] then
      return nil
    end
    return id
  end
end

local function newId(idMap, id)
  local new = idMap[id]
  if new == nil then
    return id
  end
  return new or nil
end

local function remapArray(list, idMap)
  if type(list) ~= "table" then
    return
  end
  local out = {}
  for _, id in ipairs(list) do
    local n = newId(idMap, id)
    if n then
      out[#out + 1] = n
    end
  end
  for i = #list, 1, -1 do
    list[i] = nil
  end
  for i, id in ipairs(out) do
    list[i] = id
  end
end

local function remapKeys(map, idMap)
  if type(map) ~= "table" then
    return
  end
  local pairsList = {}
  for k, v in pairs(map) do
    pairsList[#pairsList + 1] = { k, v }
  end
  for _, kv in ipairs(pairsList) do
    map[kv[1]] = nil
  end
  for _, kv in ipairs(pairsList) do
    local n = kv[1]
    if type(n) == "number" then
      n = newId(idMap, n)
    end
    if n then
      map[n] = kv[2]
    end
  end
end

-- data: the helper's HelperSpellData (mods/game_helper/spelldata.lua). Its lists are keyed by the stock ids: the
-- arrays and sets it hands out are rewritten in place, the lookups of its private sets (ranged monster, expose
-- weakness, sap strength spells, buff durations) are wrapped to ask with the stock id.
function F.remapHelper(data, idMap, removedIds)
  if not data or data.chaosRemapped then
    return false
  end
  -- the removed spells (removedIds, current ids) leave every list as a dropped id would
  local map = {}
  for k, v in pairs(idMap) do
    map[k] = v
  end
  for id in pairs(removedIds or {}) do
    if map[id] == nil then
      map[id] = false
    end
  end
  idMap = map
  local function each(map, fn)
    if type(map) == "table" then
      for _, v in pairs(map) do
        fn(v)
      end
    end
  end
  local byVoc = data.getSpellFilterByVocation and data.getSpellFilterByVocation()
  each(byVoc, function(list) remapArray(list, idMap) end)
  if data.getHasteWhiteList then
    each(data.getHasteWhiteList(), function(list) remapArray(list, idMap) end)
  end
  if data.getTrainingHealSpells then
    each(data.getTrainingHealSpells(), function(list) remapArray(list, idMap) end)
  end
  if data.getTrainingHealSpellsSet then
    each(data.getTrainingHealSpellsSet(), function(s) remapKeys(s, idMap) end)
  end
  if data.getSupportSpellsWhitelist then
    each(data.getSupportSpellsWhitelist(), function(list) remapArray(list, idMap) end)
  end
  if data.getSupportSpellsWhitelistSet then
    each(data.getSupportSpellsWhitelistSet(), function(s) remapKeys(s, idMap) end)
  end
  if data.getHealingSpellFilter then
    remapKeys(data.getHealingSpellFilter(), idMap)
  end
  if data.getIgnoredSpellsIds then
    remapKeys(data.getIgnoredSpellsIds(), idMap)
  end
  if data.getRangedMonsterSpells then
    remapArray(data.getRangedMonsterSpells(), idMap)
  end
  local oldId = oldIdFunc(idMap)
  local function wrap(name, default)
    local fn = data[name]
    if type(fn) ~= "function" then
      return
    end
    data[name] = function(id)
      local o = oldId(id)
      if o == nil then
        return default
      end
      return fn(o)
    end
  end
  wrap("isRangedMonsterSpell", false)
  wrap("isExposeWeaknessSpell", false)
  wrap("isSapStrengthSpell", false)
  wrap("getBuffDuration", 0)
  wrap("getDefaultRangedMonsterNames", nil)
  data.chaosRemapped = true
  return true
end

-- Does the character's class list this spell in a picker (base patch 0079: the action bar's Assign Spell, the custom
-- hotkeys' Assign Spell, and the bar's can-cast checks)? The base compared the spell's vocation list with
-- translateVocation(vocation), which folds the Chaos classes onto old ids (Beastmaster / Deadeye / Ranger 7, Illusionist
-- 6, Mystic / Elementalist 5, ...). A Chaos spell lists the server ids (Moonfang Pack {10}, Wild Bond {15}), so it never
-- matched and the Beastmaster saw only the stock "Summon Paladin Familiar" (owner report 2026-10-17: "the wolf is not
-- in the hotbar list, only a paladin summon that does not work"). A spell matches by the server id or the folded id (so
-- nothing the base listed disappears); an entry the server does not have (notOnServer) never matches.
-- spell: a SpellInfo entry; vocation: the player's server vocation id; translate: translateVocation (default: the global)
function F.allowsVocation(spell, vocation, translate)
  if type(spell) ~= 'table' or spell.notOnServer then
    return false
  end
  local list = spell.vocations
  if type(list) ~= 'table' then
    return true
  end
  translate = translate or rawget(_G, 'translateVocation')
  local folded = translate and translate(vocation) or nil
  for _, v in ipairs(list) do
    if v == vocation or (folded ~= nil and folded ~= 0 and v == folded) then
      return true
    end
  end
  return false
end

-- the words the server has: the Chaos spells' and the renamed stock spells' (ChaosSpellNames values)
function F.serverWords(chaosSpells, chaosNames)
  local s = {}
  for _, c in ipairs(chaosSpells or {}) do
    s[c.words:lower()] = true
  end
  for _, e in pairs(chaosNames or {}) do
    s[e.words:lower()] = true
  end
  return s
end

-- The helper offers a spell only from its own per-vocation id lists (HelperSpellData). Adds every spell of `spells` to
-- them, for each helper class of its server vocations (and the promoted class, +10): the attack-type spells to the
-- vocation list, healing ones (group 2) also to the healing filter, support ones (group 3) also to the support
-- whitelist. Owner report 2026-10-17 ("some spells appear in the spellbook but not in the helper"): the base spells the
-- client had no entry for (F.EXTRA) were never added, and a stock spell the helper's own list lacks stayed out.
--   data: HelperSpellData; helperVocation: server vocation id -> helper class; exclude: set of ids never offered;
--   spells: {{id, groups = {group numbers}, vocations = {server ids}, name}}; skipIgnored: leave out the ids the
--   helper itself ignores (data.getIgnoredSpellsIds)
-- Returns the list of additions {id, name, vocation} (empty when everything was already there; idempotent).
function F.extendHelperLists(data, spells, helperVocation, exclude, skipIgnored)
  local added = {}
  if not data or not data.getSpellFilterByVocation then
    return added
  end
  local byVocation = data.getSpellFilterByVocation()
  local healing = data.getHealingSpellFilter and data.getHealingSpellFilter() or {}
  local support = data.getSupportSpellsWhitelist and data.getSupportSpellsWhitelist() or {}
  local supportSet = data.getSupportSpellsWhitelistSet and data.getSupportSpellsWhitelistSet() or {}
  local ignored = skipIgnored and data.getIgnoredSpellsIds and data.getIgnoredSpellsIds() or {}
  local function has(list, id)
    for _, v in ipairs(list or {}) do
      if v == id then return true end
    end
    return false
  end
  for _, s in ipairs(spells) do
    if not (exclude and exclude[s.id]) and not ignored[s.id] then
      local vocs = {}
      for _, v in ipairs(s.vocations or {}) do
        local h = helperVocation[v]
        if h then
          vocs[h] = true
          vocs[h + 10] = true
        end
      end
      local isHealing, isSupport = false, false
      for _, g in ipairs(s.groups or {}) do
        if g == 2 then isHealing = true elseif g == 3 then isSupport = true end
      end
      for v in pairs(vocs) do
        byVocation[v] = byVocation[v] or {}
        local new = false
        if not has(byVocation[v], s.id) then
          table.insert(byVocation[v], s.id)
          new = true
        end
        if isHealing then
          healing[s.id] = healing[s.id] or {}
          if not has(healing[s.id], v) then
            table.insert(healing[s.id], v)
            new = true
          end
        elseif isSupport then
          support[v] = support[v] or {}
          supportSet[v] = supportSet[v] or {}
          if not has(support[v], s.id) then
            table.insert(support[v], s.id)
            new = true
          end
          supportSet[v][s.id] = true
        end
        if new then
          added[#added + 1] = { id = s.id, name = s.name, vocation = v }
        end
      end
    end
  end
  return added
end

-- the castable spells of the client's own spell table (SpellInfo.Default after the fixes): instants the server has, as
-- {id, name, groups, vocations}. notOnServer entries, ids past the server's byte range, runes and conjure spells, and the
-- ids of removedIds (the spells the server removed) are left out.
function F.castableFromInfo(info, removedIds)
  local out = {}
  for name, s in pairs(info or {}) do
    if type(s) == 'table' and type(s.id) == 'number' and s.id < F.OFF_SERVER and not s.notOnServer
        and (s.type == nil or s.type == 'Instant') and type(s.vocations) == 'table' and #s.vocations > 0
        and not (removedIds and removedIds[s.id]) then
      local groups = {}
      if type(s.group) == 'table' then
        for g in pairs(s.group) do groups[#groups + 1] = g end
        table.sort(groups)
      end
      out[#out + 1] = { id = s.id, name = name, groups = groups, vocations = s.vocations }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end
