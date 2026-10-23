-- luajit helper_config_test.lua && lua5.3 helper_config_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helper_logic.lua')
dofile(dir .. 'helper_runes.lua')
dofile(dir .. 'helper_ally.lua')
dofile(dir .. 'helper_config.lua')
local C = ChaosHelperCfg
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- defaults
local d = C.defaults()
eq(#d.spells, 3, 'three heal rows')
eq(#d.potions, 3, 'three potion rows')
eq(#d.shooterProfiles.Default.spells, 5, 'five slots')
eq(d.autoTargetMode, 6, 'mode F by default')
eq(d.helperAutomaticFunctionsEnabled, true, 'automatic functions on')

-- sanitize: wrong types and ranges
eq(C.sanitize('x').selectedShooterProfile, 'Default', 'not a table')
local c = C.sanitize({ spells = { { id = 'abc', percent = 500 } }, autoTargetMode = 99, magicShooterEnabled = 'yes',
  shooterProfiles = { Mine = { spells = { { id = 5, percent = -3, creatures = 40, forceCast = 1 } } } },
  selectedShooterProfile = 'Gone', unknownField = { keep = 1 } })
eq(c.spells[1].id, 0, 'bad id')
eq(c.spells[1].percent, 100, 'percent clamped')
eq(c.autoTargetMode, 8, 'mode out of range is clamped')
eq(c.magicShooterEnabled, false, 'bool fallback')
eq(c.shooterProfiles.Mine.spells[1].percent, 0, 'slot percent clamped')
eq(c.shooterProfiles.Mine.spells[1].creatures, 8, 'creatures clamped')
eq(c.shooterProfiles.Mine.spells[1].forceCast, false, 'forceCast bool')
eq(#c.shooterProfiles.Mine.spells, 5, 'slots padded')
eq(c.selectedShooterProfile, 'Mine', 'selected profile repaired')
eq(c.unknownField.keep, 1, 'unknown fields round-trip')

-- migration: rules -> slots, once
local old = C.sanitize({ shooterProfiles = { Default = { rules = {
  { type = 'spell', spellId = 11, manaPercent = 40, creatures = 2, forceOnTarget = true, enabled = true },
  { type = 'rune', itemId = 3155, enabled = true },
  { type = 'spell', spellId = 12, manaPercent = 20, selfCast = true, enabled = false },
  { type = 'spell', spellId = 13, manaPercent = 10, enabled = true },
} } } })
local p = old.shooterProfiles.Default
eq(p.rules, nil, 'rules gone from the profile')
eq(p.spells[1].id, 11, 'first rule is slot 1')
eq(p.spells[1].percent, 40, 'mana percent kept')
eq(p.spells[1].forceCast, true, 'force kept')
eq(p.spells[2].id, 13, 'the rune and the disabled rule are skipped')
eq(p.legacyRules ~= nil, true, 'the old rules stay aside')
local again = C.sanitize(old)
eq(again.shooterProfiles.Default.spells[1].id, 11, 'second pass keeps the slots')

-- more than five rules
local many = {}
for i = 1, 8 do many[i] = { type = 'spell', spellId = 100 + i, enabled = true } end
local slots, dropped = C.rulesToSlots(many)
eq(#slots, 5, 'five slots')
eq(dropped, 3, 'three rules dropped')

-- slots <-> rules
local rules = C.slotsToRules({ { id = 7, percent = 30, creatures = 3, priority = 2 }, { id = 8, percent = 0, priority = 1 },
  { id = 0 } }, function(id) return { name = 'S' .. id, words = 'w' .. id } end)
eq(#rules, 2, 'empty slots give no rule')
eq(rules[1].spellId, 8, 'priority order')
eq(rules[2].creatures, 3, 'creatures')
eq(rules[2].name, 'S7', 'lookup name')

-- rotation view
local prof = C.newProfile()
local view = C.rotationView(prof)
view.rules = { { type = 'spell', spellId = 21, manaPercent = 50, enabled = true } }
eq(prof.spells[1].id, 21, 'writing rules sets the slots')
eq(view.rules[1].spellId, 21, 'reading rules gives rules')
view.chaosAutoRotation = true
eq(prof.chaosAutoRotation, true, 'the marker passes through')
eq(view.chaosAutoRotation, true, 'the marker reads back')

-- names
eq(C.nameProblem('', nil) ~= nil, true, 'empty name')
eq(C.nameProblem('abcdefghijklmnop', nil) ~= nil, true, 'long name')
eq(C.nameProblem('a/b', nil) ~= nil, true, 'bad character')
eq(C.nameProblem('Boss run', nil), nil, 'good name')
eq(C.nameProblem('Default', function(n) return n == 'Default' end) ~= nil, true, 'name in use')
local cfg = { shooterProfiles = { B = {}, A = {}, C = {} } }
eq(C.nextProfile(cfg, 'A'), 'B', 'next preset')
eq(C.nextProfile(cfg, 'C'), 'A', 'wraps')

-- hud
local h = C.sanitize({ botHud = { size = 'Huge', showEquipment = true } }).botHud
eq(h.size, 'Normal', 'bad hud size')
eq(h.showEquipment, nil, 'old hud section dropped')
eq(h.showHealing, true, 'new section default')

-- timers words
local tw = C.timerWords({ timerConfig = { rules = {
  { type = 'words', value = 'Utani Hur', enabled = true }, { type = 'words', value = 'utani hur' },
  { type = 'item', value = '5' }, { type = 'words', value = 'x', enabled = false } } } })
eq(#tw, 1, 'one distinct words rule')
eq(tw[1], 'utani hur', 'lower-cased')
local m = {}
eq(C.timersMigrated(m), false, 'not migrated')
C.markTimersMigrated(m)
eq(C.timersMigrated(m), true, 'migrated')

-- the four sections of 2026-10-23: defaults and sanitize
local d2 = C.defaults()
eq(d2.autoSell.enabled, false, 'auto sell is off by default')
eq(d2.autoSell.minutes, 30, 'auto sell default interval')
eq(d2.follow.enabled, false, 'follow is off by default')
eq(#d2.runeHeal, 2, 'two heal rune rows')
eq(#d2.shooterProfiles.Default.runes, 3, 'three attack rune rows')
eq(#d2.allies.friends.names, 5, 'five friend names')
local bad = C.sanitize({ autoSell = { enabled = 'yes', minutes = 7, capacity = -5, belowCap = 1 },
  follow = { enabled = true, mode = 'x', name = 'Bad"Name; say hi', distance = 99 },
  runeHeal = { { id = 'a', percent = 500 } },
  allies = { party = { enabled = true, percent = 0 }, friends = { names = { 'Ann', 'ann', 'B"ob', 5 }, percent = 200 },
    spell = -3, group = { id = 82, count = 50 }, rune = 'x' } })
eq(bad.autoSell.enabled, false, 'auto sell bool')
eq(bad.autoSell.minutes, 30, 'auto sell minutes only from the list')
eq(bad.autoSell.capacity, 0, 'capacity clamped')
eq(bad.follow.mode, 'name', 'follow mode')
eq(bad.follow.name, '', 'a name with a quote is dropped')
eq(bad.follow.distance, 5, 'follow distance clamped')
eq(bad.runeHeal[1].id, 0, 'rune id')
eq(bad.runeHeal[1].percent, 99, 'rune percent clamped')
eq(bad.allies.party.percent, 1, 'party percent clamped')
eq(bad.allies.friends.percent, 99, 'friend percent clamped')
eq(bad.allies.friends.names[1], 'Ann', 'a friend name')
eq(bad.allies.friends.names[2], '', 'a repeated name is dropped')
eq(bad.allies.friends.names[3], '', 'a name with a quote is dropped')
eq(bad.allies.spell, 0, 'ally spell id')
eq(bad.allies.group.count, 8, 'group count clamped')
eq(bad.allies.rune.id, 0, 'ally rune')

-- migration of the former helper's follow friend, named Sio, party heals and Auto Sell Loot
local mig = C.sanitize({
  followFriendEnabled = true, followFriendName = '  Ana  Maria ',
  namedSio = { enabled = true, name = 'Bob, Cleo,, "evil"', percent = 85, spell = 'gransio' },
  friendhealing = { knight = { enabled = true, percent = 80 }, druid = { enabled = true, percent = 90 },
    monk = { enabled = false, percent = 99 } },
  masreshealing = { extended = false, paladin = { enabled = true, percent = 60 } },
  autoQuillSell = true, autoQuillSellBelowCap = true, autoQuillSellCapacity = 150,
})
eq(mig.follow.enabled, true, 'follow friend taken over')
eq(mig.follow.name, 'Ana Maria', 'follow name cleaned')
eq(mig.follow.mode, 'name', 'follow by name')
eq(mig.allies.friends.enabled, true, 'named Sio taken over')
eq(mig.allies.friends.names[1], 'Bob', 'first name')
eq(mig.allies.friends.names[2], 'Cleo', 'second name')
eq(mig.allies.friends.names[3], '', 'the evil name is dropped')
eq(mig.allies.friends.percent, 85, 'named percent')
eq(mig.allies.party.enabled, true, 'party heal taken over')
eq(mig.allies.party.percent, 90, 'the highest enabled percent')
eq(mig.allies.spell, 84, 'Heal Friend becomes Kindred Mend')
eq(mig.allies.group.id, 82, 'Mass Healing becomes Circle of Mending')
eq(mig.autoSell.enabled, true, 'auto sell taken over')
eq(mig.autoSell.belowCap, true, 'below capacity taken over')
eq(mig.autoSell.capacity, 150, 'capacity taken over')
eq(mig.autoQuillSell, true, 'the old keys stay in the file')
local gran = C.sanitize({ gransiohealing = { monk = { enabled = true, percent = 70 } } })
eq(gran.allies.spell, 101, 'Nature Embrace becomes Heartwood Embrace')
eq(gran.allies.party.enabled, false, 'no party heal for a gransio only file')
-- once: a file that has the new sections is not migrated again
local once = C.sanitize({ followFriendEnabled = true, followFriendName = 'Old', follow = { enabled = false, name = 'New' },
  autoQuillSell = true, autoSell = { enabled = false } })
eq(once.follow.name, 'New', 'an existing follow section wins')
eq(once.autoSell.enabled, false, 'an existing auto sell section wins')
local again2 = C.sanitize(mig)
eq(again2.follow.name, 'Ana Maria', 'second pass keeps the follow')
eq(again2.allies.friends.names[2], 'Cleo', 'second pass keeps the names')
-- nothing of the old: the defaults
local none = C.sanitize({ spells = {} })
eq(none.follow.enabled, false, 'no follow without the old keys')
eq(none.allies.party.enabled, false, 'no party heal without the old keys')

-- rune rows: from the rules of the former helper and from its old list
local rr = C.sanitize({ shooterProfiles = {
  A = { rules = { { type = 'rune', itemId = 3155, creatures = 2, hpMin = 10, hpMax = 50, enabled = true },
    { type = 'rune', itemId = 3172, enabled = true }, -- a field rune is not carried
    { type = 'rune', itemId = 3191, creatures = 3, countLowerThan = true, enabled = true }, -- "N-" is not carried
    { type = 'rune', itemId = 3174, enabled = false },
    { type = 'spell', spellId = 5, enabled = true } } },
  B = { spells = { { id = 5, percent = 10, creatures = 1, priority = 1 } },
    runes = { { id = 3191, creatures = 4, priority = 2 }, { id = 3198, creatures = 1, priority = 1 } } },
  Cc = { spells = {}, runes = { { id = 3174, creatures = 2, priority = 1 } }, runesVersion = 1 },
} })
local A_, B_, Cc = rr.shooterProfiles.A, rr.shooterProfiles.B, rr.shooterProfiles.Cc
eq(A_.runes[1].id, 3155, 'a rune rule becomes row 1')
eq(A_.runes[1].creatures, 2, 'rune creatures')
eq(A_.runes[1].hpMin, 10, 'rune hp min kept')
eq(A_.runes[1].hpMax, 50, 'rune hp max kept')
eq(A_.runes[2].id, 0, 'field rune, N- rule and disabled rule are not carried')
eq(A_.spells[1].id, 5, 'the spell rule still goes to the slots')
eq(B_.runes[1].id, 3191, 'the old rune list is carried')
eq(B_.runes[2].id, 3198, 'second old rune')
eq(B_.runesVersion, 1, 'the list is marked')
eq(Cc.runes[1].id, 3174, 'a list of this helper is not converted again')
eq(#Cc.runes, 3, 'rune rows padded')
local rows, dr = C.rulesToRunes({ { type = 'rune', itemId = 3152, enabled = true } }, nil)
eq(rows[1].id, 0, 'a healing rune is no attack rune row')
eq(dr, 1, 'and counts as dropped')

if fails > 0 then os.exit(1) end
print('helper_config_test: ok')
