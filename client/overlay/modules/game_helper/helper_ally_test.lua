-- luajit helper_ally_test.lua && lua5.3 helper_ally_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
for _, f in ipairs({ 'helper_logic', 'helper_potions', 'helper_runes', 'helper_spells', 'helper_ally' }) do
  dofile(dir .. f .. '.lua')
end
local A = ChaosHelperAlly
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- names
eq(A.cleanName('  Ann   Lee '), 'Ann Lee', 'a name is trimmed and single spaced')
eq(A.cleanName("D'Arc-Smith"), "D'Arc-Smith", "' and - are fine")
eq(A.cleanName('A'), nil, 'too short')
eq(A.cleanName(string.rep('a', 30)), nil, 'too long')
eq(A.cleanName('Ann"; say "x'), nil, 'a quote or semicolon is refused')
eq(A.cleanName('Ann\nBob'), 'Ann Bob', 'a line break becomes a space: no break reaches the chat line')
eq(A.cleanName('1Ann'), nil, 'a name starts with a letter')
eq(A.cleanName('Ann!'), nil, 'no punctuation')
eq(A.cleanName(nil), nil, 'nil')
eq(A.cleanName(42), nil, 'a number')
local names = A.parseNames('Ann, Bob; ann\nCy,, "bad", Dee, Eve, Fay', 5)
eq(#names, 5, 'at most five names')
eq(names[1], 'Ann', 'first')
eq(names[2], 'Bob', 'second; the repeat of Ann is dropped')
eq(names[3], 'Cy', 'third')
eq(names[4], 'Dee', 'the bad name is dropped')
eq(#A.parseNames('', 5), 0, 'empty text')

-- shields
eq(A.isPartyShield(3), true, 'blue is a member')
eq(A.isPartyShield(10), true, 'yellow is a member')
eq(A.isPartyShield(1), false, 'an invitation is no member')
eq(A.isPartyShield(0), false, 'no shield')
eq(A.isPartyShield(11), false, 'gray is no member')
eq(A.isLeaderShield(4), true, 'yellow leads')
eq(A.isLeaderShield(3), false, 'blue does not lead')

-- ---------------------------------------------------------------- who needs a heal
local from = { x = 100, y = 100, z = 7 }
local function pl(id, name, hp, x, y, shield, z)
  return { id = id, name = name, health = hp, position = { x = x, y = y, z = z or 7 }, shield = shield or 0 }
end
local cfg = {
  party = { enabled = true, percent = 70 },
  friends = { enabled = true, percent = 60, names = { 'Zed', 'Yan', '', '', '' } },
  spell = 84, group = { id = 0, count = 2 }, rune = { id = 0 },
}
local crowd = {
  pl(1, 'Mate', 50, 102, 100, 3),            -- party, hurt
  pl(2, 'Mate2', 80, 103, 100, 3),           -- party, above the percent
  pl(3, 'Zed', 55, 101, 101),                -- friend, hurt
  pl(4, 'Yan', 65, 101, 99),                 -- friend, above the friend percent
  pl(5, 'Stranger', 10, 100, 101),           -- nobody's friend
  pl(6, 'Far', 10, 120, 100, 3),             -- out of view
  pl(7, 'Floor', 10, 101, 100, 3, 6),        -- another floor
  pl(8, 'Dead', 0, 101, 100, 3),             -- dead
  pl(9, 'Full', 100, 101, 100, 3),           -- full health
  { id = 99, name = 'Me', health = 10, position = from, shield = 4, isSelf = true },
}
local cands = A.candidates(cfg, crowd, from)
eq(#cands, 2, 'two players need a heal')
eq(cands[1].name, 'Mate', 'the most hurt first')
eq(cands[2].name, 'Zed', 'then the next one')
eq(cands[1].party, true, 'a party member is marked')
eq(cands[2].friend, true, 'a friend is marked')
eq(cands[1].distance, 2, 'with its distance')
-- ties: the nearer, then the lower id
local tie = A.candidates(cfg, { pl(7, 'Mate', 50, 104, 100, 3), pl(5, 'Mate', 50, 102, 100, 3), pl(4, 'Mate', 50, 102, 100, 3) }, from)
eq(tie[1].id, 4, 'a tie goes to the nearer and then the lower id')
eq(tie[3].id, 7, 'the farthest last')
-- the switches
local onlyParty = A.candidates({ party = cfg.party, friends = { enabled = false, percent = 60, names = cfg.friends.names } },
  crowd, from)
eq(#onlyParty, 1, 'friends off: the party only')
local onlyFriends = A.candidates({ party = { enabled = false, percent = 70 }, friends = cfg.friends }, crowd, from)
eq(#onlyFriends, 1, 'party off: the friends only')
eq(onlyFriends[1].name, 'Zed', 'the friend')
eq(#A.candidates({ party = { enabled = false }, friends = { enabled = false } }, crowd, from), 0, 'both off: nobody')
eq(#A.candidates(nil, crowd, from), 0, 'no config')
eq(#A.candidates(cfg, crowd, nil), 0, 'no position')
-- line of sight
local blocked = A.candidates(cfg, crowd, from, { sight = function(_, to) return to.x ~= 102 end })
eq(#blocked, 1, 'a player behind a wall is not healed')
eq(blocked[1].name, 'Zed', 'the one in sight')
-- a friend name is compared case-blind, a bad name in the list never matches
local ci = A.candidates({ party = { enabled = false }, friends = { enabled = true, percent = 90, names = { 'zed', 'Bad"Name' } } },
  { pl(3, 'ZED', 55, 101, 101), pl(4, 'Bad"Name', 10, 101, 99) }, from)
eq(#ci, 1, 'case-blind match; a bad name never matches')

-- ---------------------------------------------------------------- the character comes first
local hcfg = { spells = { { id = 5, percent = 50 }, { id = 0, percent = 90 } }, potions = {}, runeHeal = { { id = 3152, percent = 40 } } }
eq(A.selfFirst(hcfg, 80), false, 'healthy: allies may be healed')
eq(A.selfFirst(hcfg, 45), true, 'a heal row is due: self first')
eq(A.selfFirst({ spells = {}, potions = {}, runeHeal = { { id = 3152, percent = 40 } } }, 30), true, 'a healing rune row is due')
eq(A.selfFirst({ spells = { { id = 0, percent = 90 } }, potions = {}, runeHeal = {} }, 10), false, 'an empty row never counts')

-- ---------------------------------------------------------------- the pick
local function spell(id, words) return { id = id, words = words, name = 'S' .. id } end
local spells = { [84] = spell(84, 'saen kin'), [101] = spell(101, 'saen gal kin'), [82] = spell(82, 'saen gal vas kal'),
  [96] = spell(96, 'saen spek'), [66] = spell(66, 'saen qhal'), [128] = spell(128, 'reth vas kin') }
local function ctx(over)
  local c = { from = from, cands = cands, selfFirst = false, manaPct = 80,
    spellOf = function(id) return spells[id] end, ready = function() return true end,
    runeAvailable = function() return false end }
  for k, v in pairs(over or {}) do c[k] = v end
  return c
end
local pick = A.pick(cfg, ctx())
eq(pick.kind, 'spell', 'a single spell on the most hurt player')
eq(pick.words, 'saen kin "Mate"', 'the words carry the cleaned name')
eq(pick.target.name, 'Mate', 'target')
eq(A.pick(cfg, ctx({ selfFirst = true })), nil, 'self first: nobody else')
eq(A.pick(cfg, ctx({ cands = {} })), nil, 'nobody needs a heal')
eq(A.pick(cfg, ctx({ manaPct = 5 })), nil, 'low mana: no ally heal')
eq(A.pick(cfg, ctx({ ready = function() return false end })), nil, 'not ready')
eq(A.pick(nil, ctx()), nil, 'no config')
eq(A.pick(cfg, ctx({ from = false })), nil, 'no position')
-- a group spell when enough players need it (the group spell goes first)
local gcfg = { party = cfg.party, friends = cfg.friends, spell = 84, group = { id = 82, count = 2 }, rune = { id = 0 } }
pick = A.pick(gcfg, ctx())
eq(pick.kind, 'group', 'two hurt in the area: the group spell')
eq(pick.words, 'saen gal vas kal', 'the group words have no name')
gcfg.group.count = 3
eq(A.pick(gcfg, ctx()).kind, 'spell', 'too few hurt: the single spell')
-- Circle of Mending has an area of 3 tiles round the caster
local wide = { pl(1, 'Mate', 50, 106, 100, 3), pl(2, 'Mate2', 60, 106, 101, 3) }
gcfg.group.count = 2
eq(A.pick(gcfg, ctx({ cands = A.candidates(cfg, wide, from) })).kind, 'spell', 'players beyond 3 tiles are not in the area')
gcfg.group = { id = 128, count = 2 }
eq(A.pick(gcfg, ctx({ cands = A.candidates(cfg, wide, from) })).kind, 'group', 'a party spell counts the whole party')
-- party-only spells skip a friend who is not in the party
local pcfg = { party = cfg.party, friends = cfg.friends, spell = 96, group = { id = 0, count = 1 }, rune = { id = 0 } }
local friendOnly = A.candidates({ party = { enabled = false }, friends = cfg.friends }, crowd, from)
eq(A.pick(pcfg, ctx({ cands = friendOnly })), nil, 'Mirror Mend does not heal a friend outside the party')
eq(A.pick(pcfg, ctx()).target.name, 'Mate', 'but the party member')
-- an auto spell has no name
local acfg = { party = cfg.party, friends = cfg.friends, spell = 66, group = { id = 0, count = 1 }, rune = { id = 0 } }
eq(A.pick(acfg, ctx()).words, 'saen qhal', 'Kindled Breath has no name')
-- a name that cannot be said stops the spell
local odd = { pl(1, 'Bad"Name', 10, 102, 100, 3) }
eq(A.pick(cfg, ctx({ cands = A.candidates(cfg, odd, from) })), nil, 'a bad name is never put into a chat line')
-- a rune when no spell goes
local rcfg = { party = cfg.party, friends = cfg.friends, spell = 0, group = { id = 0, count = 1 }, rune = { id = 3152 } }
pick = A.pick(rcfg, ctx({ runeAvailable = function(id) return id == 3152 end }))
eq(pick.kind, 'rune', 'a healing rune when there is no spell')
eq(pick.id, 3152, 'the rune id')
eq(A.pick(rcfg, ctx()), nil, 'no rune at hand')
rcfg.rune.id = 3155
eq(A.pick(rcfg, ctx({ runeAvailable = function() return true end })), nil, 'a damage rune is never thrown at an ally')
-- the spell wins over the rune
rcfg.rune.id = 3152
rcfg.spell = 84
eq(A.pick(rcfg, ctx({ runeAvailable = function() return true end })).kind, 'spell', 'spell before rune')
-- a spell the table does not have
eq(A.pick({ party = cfg.party, friends = cfg.friends, spell = 9999, group = { id = 0 }, rune = { id = 0 } }, ctx()), nil, 'unknown spell')

-- ---------------------------------------------------------------- no spam
local st = A.newState()
eq(A.allowed(st, 1, 1000), true, 'the first heal')
A.noted(st, 1, 1000)
eq(A.allowed(st, 1, 1500), false, 'the same player not within the gap')
eq(A.allowed(st, 2, 1500), true, 'another player may go')
eq(A.allowed(st, 1, 1000 + A.TARGET_GAP_MS), true, 'the same player after the gap')
st = A.newState()
for i = 1, A.BUDGET_MAX do
  eq(A.allowed(st, i, 1000 + i), true, 'within the budget ' .. i)
  A.noted(st, i, 1000 + i)
end
eq(A.allowed(st, 100, 2000), false, 'the budget is used up')
eq(A.allowed(st, 100, 1000 + A.BUDGET_MS + A.BUDGET_MAX + 1), true, 'and comes back')

-- ---------------------------------------------------------------- the pickers
local lists = {}
for _, e in ipairs(A.SINGLE) do lists[#lists + 1] = e.id end
eq(#lists >= 4, true, 'the single spells are listed')
local cast = function(s) return s.id ~= 96 end
local off = A.offered(A.SINGLE, function(id) return spells[id] end, cast, 3)
local ids = {}
for _, o in ipairs(off) do ids[o.spell.id] = true end
eq(ids[84], true, 'Kindred Mend offered')
eq(ids[96], nil, 'a spell the class cannot cast is not offered')
eq(ids[66], nil, 'Kindled Breath only for the Iron Sage')
off = A.offered(A.SINGLE, function(id) return spells[id] end, cast, 19)
ids = {}
for _, o in ipairs(off) do ids[o.spell.id] = true end
eq(ids[66], true, 'Kindled Breath for the Iron Sage')
eq(#A.offered(A.GROUP, function(id) return spells[id] end, function() return true end, 3), 2, 'the group spells the table has (not Lucid Reverie)')

-- ---------------------------------------------------------------- never a utility
-- the heal-others spells are healing spells, none of them in the helper's utility lists
dofile(dir .. '../game_helpersupport/supportspells.lua')
local H = ChaosHelperSupport
for _, e in ipairs(A.SINGLE) do eq(H.NEVER_IDS[e.id], nil, 'single ' .. e.id .. ' is no utility') end
for _, e in ipairs(A.GROUP) do eq(H.NEVER_IDS[e.id], nil, 'group ' .. e.id .. ' is no utility') end
for _, e in ipairs(A.SINGLE) do eq(ChaosHelperSpells.TOGGLE_IDS[e.id], nil, 'single ' .. e.id .. ' is no toggle') end
-- the spell words in the client's table are not in the never lists either
local f = io.open(dir .. '../game_chaosspells/spelldata.lua', 'r')
if f then
  local text = f:read('*a')
  f:close()
  for _, e in ipairs({ { 84, 'saen kin' }, { 101, 'saen gal kin' }, { 82, 'saen gal vas kal' }, { 128, 'reth vas kin' } }) do
    eq(text:find('words = "' .. e[2] .. '"', 1, true) ~= nil or text:find('words = "' .. e[2] .. '" }', 1, true) ~= nil, true,
      e[2] .. ' is a spell of the client table')
    eq(H.NEVER_WORDS[e[2]], nil, e[2] .. ' is not in NEVER_WORDS')
  end
end

if fails > 0 then os.exit(1) end
print('helper_ally_test: ok')
