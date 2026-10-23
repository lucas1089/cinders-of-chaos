-- ChaosHelperAlly: healing the party and a list of friends (pure Lua: no engine calls; tests: helper_ally_test.lua).
-- The old helper healed party members and a named list with Heal Friend, Nature's Embrace and Mass Healing (and the
-- Ultimate Healing rune). Here the same job with the heal-others spells this server has (client/MANIFEST.md "Helper"):
--   * a single-target spell chosen in the window: Kindred Mend (84) and Heartwood Embrace (101) take a name and heal any
--     player in view; Mirror Mend (96, Illusionist) and Lay on Hands (253, Sentinel) take a name or none and heal only the
--     caster and the party (server/data/spells/chaos/*: "heals only you or a member of your party"), 7 and 5 tiles;
--     Kindled Breath (66, Iron Sage) takes no name and heals the most hurt party member within 5 tiles;
--   * a group spell chosen in the window, cast when enough hurt players are in its reach: Circle of Mending (82, an area
--     of 3 tiles round the caster, heals every player in it), Mending Communion (128) and Lucid Reverie (97, the party);
--   * optionally a healing rune (Mending, Grand Mending; helper_runes.lua) on the most hurt player when no spell can go.
-- Who is healed: party members below the party percent, and the friends of the list below the friend percent. A friend is
-- named, so the name goes into the spell words in quotes: it is cleaned first (letters, spaces, ' and - only, 2 to 29
-- characters), so a typed name can never put other text into the chat line. Only players in the 7 x 5 window of the helper,
-- on the same floor and in line of sight, are healed.
-- The character comes first: while one of its own healing rows (spell, potion, rune) is due by the numbers, nobody else is
-- healed. A heal-others spell is never a utility (ChaosHelperSupport.NEVER_*); a refused cast is backed off by
-- ChaosHelperRotation like every cast, and here a target gets a gap and the whole job a budget, so a heal never spams.
ChaosHelperAlly = ChaosHelperAlly or {}
local A = ChaosHelperAlly

A.NAME_MIN, A.NAME_MAX = 2, 29
A.TARGET_GAP_MS = 1200        -- the least time between two heals of the same player
A.BUDGET_MS, A.BUDGET_MAX = 10000, 8   -- at most this many ally heals in this long
A.MIN_MANA_PERCENT = 10       -- no ally heal below this mana percent (the character's own heals need the mana)
A.GROUP_COUNT_MAX = 8

-- single-target spells: mode 'name' (the name goes after the words) or 'auto' (the server picks the most hurt party member)
-- partyOnly: the server heals only the caster and the party; range: tiles (Chebyshev) on top of the helper's window;
-- vocations: the classes that really heal others with it (Kindled Breath heals only the caster for the other Monk lines)
A.SINGLE = {
  { id = 84, mode = 'name' },                                                -- Kindred Mend (stock Heal Friend)
  { id = 101, mode = 'name' },                                               -- Heartwood Embrace (stock Nature's Embrace)
  { id = 96, mode = 'name', partyOnly = true, range = 7 },                   -- Mirror Mend
  { id = 253, mode = 'name', partyOnly = true, range = 5 },                  -- Lay on Hands
  { id = 66, mode = 'auto', partyOnly = true, range = 5, vocations = { 19 } }, -- Kindled Breath (Iron Sage)
}
-- group spells: they are cast on the caster's words, no name. radius: the area round the caster (nil: the helper's window);
-- partyOnly: only party members count
A.GROUP = {
  { id = 82, radius = 3 },                       -- Circle of Mending (stock Mass Healing): every player in the area
  { id = 128, partyOnly = true },                -- Mending Communion (stock Heal Party)
  { id = 97, partyOnly = true },                 -- Lucid Reverie
}

local singleById, groupById = {}, {}
for _, e in ipairs(A.SINGLE) do singleById[e.id] = e end
for _, e in ipairs(A.GROUP) do groupById[e.id] = e end
function A.single(id) return singleById[tonumber(id) or -1] end
function A.group(id) return groupById[tonumber(id) or -1] end

-- ---------------------------------------------------------------- names
-- a player name the helper may put into a chat line, or nil: trimmed, single spaces, letters / space / ' / - only
function A.cleanName(s)
  if type(s) ~= 'string' then return nil end
  s = s:gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
  if #s < A.NAME_MIN or #s > A.NAME_MAX then return nil end
  if not s:match("^[A-Za-z][A-Za-z' %-]*$") then return nil end
  return s
end

-- "Ann, Bob Smith" -> { 'Ann', 'Bob Smith' } (at most `max`, bad names and repeats dropped)
function A.parseNames(text, max)
  local out, seen = {}, {}
  for part in tostring(text or ''):gmatch('[^,;\n]+') do
    local n = A.cleanName(part)
    if n and not seen[n:lower()] then
      seen[n:lower()] = true
      out[#out + 1] = n
      if max and #out >= max then break end
    end
  end
  return out
end

local function friendSet(names)
  local set = {}
  for _, n in ipairs(names or {}) do
    local c = A.cleanName(n)
    if c then set[c:lower()] = true end
  end
  return set
end
A.friendSet = friendSet

-- ---------------------------------------------------------------- the party
-- the shield numbers of a party member (the engine's Shield enum: 3 / 5 / 7 / 9 blue = member, 4 / 6 / 8 / 10 yellow =
-- leader; 1 and 2 are only an invitation). Falls back to the numbers when the client's constants are not there.
local MEMBER_SHIELDS = { [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true }
local LEADER_SHIELDS = { [4] = true, [6] = true, [8] = true, [10] = true }
function A.isPartyShield(shield) return MEMBER_SHIELDS[tonumber(shield) or -1] == true end
function A.isLeaderShield(shield) return LEADER_SHIELDS[tonumber(shield) or -1] == true end

-- ---------------------------------------------------------------- who needs a heal
-- players: { { id, name, health (percent), position, shield, isSelf } }. Returns the players to heal, the most hurt first
-- (then the nearer, then the lower id), each as { id, name, health, position, party, friend, distance }.
-- ctx.sight(from, to) -> true when the line is clear (optional).
function A.candidates(cfg, players, from, ctx)
  ctx = ctx or {}
  local out = {}
  if type(cfg) ~= 'table' or not from then return out end
  local party, friends = cfg.party or {}, cfg.friends or {}
  local set = friendSet(friends.names)
  for _, p in ipairs(players or {}) do
    local hp = tonumber(p.health)
    local pos = p.position
    if not p.isSelf and hp and hp > 0 and hp < 100 and pos and ChaosHelperLogic.inReach(from, pos) then
      local name = A.cleanName(p.name)
      local isParty = party.enabled == true and A.isPartyShield(p.shield) and hp <= (tonumber(party.percent) or 0)
      local isFriend = friends.enabled == true and name ~= nil and set[name:lower()] == true
        and hp <= (tonumber(friends.percent) or 0)
      if (isParty or isFriend) and (not ctx.sight or ctx.sight(from, pos)) then
        out[#out + 1] = { id = p.id, name = name, health = hp, position = pos, party = A.isPartyShield(p.shield),
          friend = name ~= nil and set[name:lower()] == true, distance = ChaosHelperLogic.distance(from, pos) }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.health ~= b.health then return a.health < b.health end
    if a.distance ~= b.distance then return a.distance < b.distance end
    return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
  end)
  return out
end

-- Does the character need a heal of its own first? helperCfg: the helper's config (spells, potions, runeHeal rows).
-- The rows count by the numbers alone; a potion row counts for health only.
function A.selfFirst(helperCfg, healthPct)
  local hp = tonumber(healthPct) or 100
  for _, r in ipairs(helperCfg.spells or {}) do
    if (tonumber(r.id) or 0) > 0 and hp <= (tonumber(r.percent) or 0) then return true end
  end
  local Pot = rawget(_G, 'ChaosHelperPotions')
  if Pot and Pot.healthDue(helperCfg.potions, hp) then return true end
  local Runes = rawget(_G, 'ChaosHelperRunes')
  if Runes and Runes.healDue(helperCfg.runeHeal, hp) then return true end
  return false
end

-- ---------------------------------------------------------------- the pick
-- the words to say for a single-target entry on a target
function A.words(spell, entry, target)
  if entry and entry.mode == 'name' then
    local name = target and A.cleanName(target.name)
    if not name then return nil end
    return string.format('%s "%s"', spell.words, name)
  end
  return spell.words
end

-- may the entry heal this target (party only, reach)
local function reaches(entry, from, target)
  if entry.partyOnly and not target.party then return false end
  if entry.range and ChaosHelperLogic.distance(from, target.position) > entry.range then return false end
  return true
end

-- how many of the candidates a group spell would heal from `from`
function A.groupHits(entry, from, cands)
  local n = 0
  for _, c in ipairs(cands) do
    if (not entry.partyOnly or c.party) then
      if not entry.radius or ChaosHelperLogic.distance(from, c.position) <= entry.radius then n = n + 1 end
    end
  end
  return n
end

-- The heal to send now, or nil. cfg = the allies section; ctx = {
--   from = the player's position, cands = A.candidates(...), selfFirst = true when the character needs its own heal,
--   manaPct, spellOf(id) -> the spell entry or nil, ready(spell) -> true when it can be cast now,
--   runeAvailable(id) -> true when the rune can be used now }
-- Returns { kind = 'spell', spell, words, target } | { kind = 'group', spell, words } | { kind = 'rune', id, target }.
function A.pick(cfg, ctx)
  if type(cfg) ~= 'table' or not ctx.from or ctx.selfFirst then return nil end
  if #ctx.cands == 0 then return nil end
  if (tonumber(ctx.manaPct) or 100) < A.MIN_MANA_PERCENT then return nil end
  local from = ctx.from
  -- a group spell when enough players need it
  local g = A.group(cfg.group and cfg.group.id)
  if g then
    local spell = ctx.spellOf(g.id)
    if spell and A.groupHits(g, from, ctx.cands) >= math.max(1, tonumber(cfg.group.count) or 1) and ctx.ready(spell) then
      return { kind = 'group', spell = spell, words = spell.words }
    end
  end
  -- the single-target spell on the most hurt player it can reach
  local s = A.single(cfg.spell)
  local spell = s and ctx.spellOf(s.id)
  if s and spell and ctx.ready(spell) then
    for _, c in ipairs(ctx.cands) do
      if reaches(s, from, c) then
        local words = A.words(spell, s, c)
        if words then return { kind = 'spell', spell = spell, words = words, target = c } end
      end
    end
  end
  -- a rune when no spell went
  local rune = cfg.rune
  if type(rune) == 'table' and (tonumber(rune.id) or 0) > 0 and ChaosHelperRunes.isHeal(rune.id)
      and ctx.runeAvailable and ctx.runeAvailable(rune.id) then
    for _, c in ipairs(ctx.cands) do
      if ChaosHelperLogic.distance(from, c.position) <= ChaosHelperLogic.REACH_X then
        return { kind = 'rune', id = tonumber(rune.id), target = c }
      end
    end
  end
  return nil
end

-- ---------------------------------------------------------------- the guard: a gap per target and a budget
function A.newState() return { last = {}, sent = {} } end

function A.allowed(st, key, now)
  local last = st.last[key]
  if last and now - last < A.TARGET_GAP_MS then return false end
  local recent = 0
  for _, t in ipairs(st.sent) do
    if now - t < A.BUDGET_MS then recent = recent + 1 end
  end
  return recent < A.BUDGET_MAX
end

function A.noted(st, key, now)
  st.last[key] = now
  local keep = {}
  for _, t in ipairs(st.sent) do
    if now - t < A.BUDGET_MS then keep[#keep + 1] = t end
  end
  keep[#keep + 1] = now
  st.sent = keep
end

-- ---------------------------------------------------------------- the pickers
-- The heal-others spells the class may use: { { name, spell, entry } } in catalogue order. castable(spell) -> true when the
-- class lists it, the level is reached and it is no utility (Spl.castable with allowParameter); spellOf(id) -> the entry.
function A.offered(list, spellOf, castable, vocation)
  local out = {}
  for _, e in ipairs(list) do
    local s = spellOf(e.id)
    local classOk = true
    if e.vocations then
      classOk = false
      for _, v in ipairs(e.vocations) do
        if v == vocation then classOk = true end
      end
    end
    if s and classOk and castable(s) then out[#out + 1] = { name = s.name, spell = s, entry = e } end
  end
  return out
end

return ChaosHelperAlly
