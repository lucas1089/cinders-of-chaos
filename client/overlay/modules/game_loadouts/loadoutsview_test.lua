-- luajit loadoutsview_test.lua (CI runs every client *_test.lua)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'loadoutsview.lua')
local V = LoadoutsView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function has(text, part, m) n = n + 1 if not tostring(text):find(part, 1, true) then error((m or '') .. ': ' .. tostring(text), 2) end end

local s = {
  level = 300, minLevel = 8, limit = 4, max = 5, baseSlots = 3, unlockLevels = { 200, 500 }, active = 1, cooldown = 30,
  castMs = 3000, inPz = false, icons = { 'skills', 'spells', 'pvp' },
  slots = {
    { slot = 1, name = 'Hunting', icon = 'pvp', active = true, voc = 'Juggernaut', cls = 'warrior', points = 40, pointsTotal = 73,
      keystones = { 'Immovable', 'Cleaving Arc' }, paragon = 0,
      supports = { count = 2, spells = { { name = 'Fire Wave', runes = { 'Echo I', 'Fork II' } } } },
      gear = { total = 7, ready = 7, missing = {} }, warnings = {} },
    { slot = 2, name = 'Bossing', icon = 'skills', voc = 'Juggernaut', cls = 'warrior', points = 38, pointsTotal = 73,
      keystones = {}, paragon = 5, supports = { count = 0, spells = {} },
      gear = { total = 7, ready = 6, missing = { { slot = 6, name = 'fire sword', where = 'in your depot (Emberfall)' } } },
      warnings = { 'When loaded: Refunded for free: 2 nodes that left the tree.' } },
    { slot = 3, empty = true },
    { slot = 4, empty = true },
    { slot = 5, empty = true, locked = true },
  }
}

-- rows
local r = V.slotRow(s, s.slots[1])
eq(r.title, 'Hunting', 'name'); eq(r.tag, 'ACTIVE', 'active tag'); eq(r.icon, '/images/chaos/small/topbutton_pvp', 'icon')
has(r.sub, '40 pts', 'points'); has(r.sub, '2 runes', 'runes'); has(r.sub, 'gear 7/7', 'gear')
r = V.slotRow(s, s.slots[2])
eq(r.tag, 'CHECK', 'warnings tag'); has(r.sub, 'gear 6/7', 'gear incomplete')
r = V.slotRow(s, s.slots[3])
eq(r.title, 'Empty slot', 'empty'); eq(r.dim, true, 'dim')
r = V.slotRow(s, s.slots[5])
eq(r.title, 'Locked slot', 'locked'); has(r.sub, 'level 500', 'unlock level')
eq(V.unlockLevel(s, 4), 200, 'slot 4 at 200'); eq(V.unlockLevel(s, 2), nil, 'free slot')

-- summary
local lines = V.summary(s, s.slots[1], 'Hunt bar')
local all = {}
for _, l in ipairs(lines) do all[#all + 1] = l.text end
local text = table.concat(all, '\n')
has(text, 'Class: Warrior (Juggernaut)', 'class and ascension')
has(text, 'Passive points: 40 / 73', 'points')
has(text, 'Keystones: Immovable, Cleaving Arc', 'keystones')
has(text, 'Fire Wave: Echo I, Fork II', 'supports per spell')
has(text, 'Gear set: complete (7/7)', 'gear complete')
has(text, 'Action bar: Hunt bar', 'profile')
has(text, 'Active', 'active note')
lines = V.summary(s, s.slots[2])
all = {}
for _, l in ipairs(lines) do all[#all + 1] = l.text end
text = table.concat(all, '\n')
has(text, 'Missing: fire sword (in your depot (Emberfall))', 'missing item and where')
has(text, 'Paragon points: 5', 'paragon')
has(text, 'Refunded for free', 'warning')
has(text, 'Keystones: none', 'no keystones')
local found
for _, l in ipairs(lines) do if l.text:find('Missing', 1, true) then found = l.color end end
eq(found, V.COLORS.bad, 'missing in red')
lines = V.summary(s, s.slots[5])
has(lines[1].text, 'level 500', 'locked slot explains'); has(lines[1].text, 'never sold', 'earned, not sold')
lines = V.summary(s, s.slots[3])
has(lines[1].text, 'Save copies', 'empty slot explains')

-- gear line
local t, c = V.gearLine({ total = 0 })
has(t, 'none', 'no gear'); eq(c, V.COLORS.dim, 'dim')
t, c = V.gearLine({ total = 3, ready = 1 })
eq(t, 'Gear set: 1/3 ready', 'partial'); eq(c, V.COLORS.warn, 'warn')

-- switching hint and buttons
eq(V.cooldownLeft(s, 10), 20, 'cooldown counts down')
eq(V.cooldownLeft(s, 40), 0, 'cooldown over')
t = V.switchHint(s, 0)
has(t, 'Next switch in 30 s', 'cooldown hint')
t = V.switchHint(s, 31)
has(t, '3.0 s', 'cast time hint')
s.inPz = true
t = V.switchHint(s, 31)
has(t, 'instant', 'pz hint')
s.busy = 'a rift'
t = V.switchHint(s, 31)
has(t, 'a rift', 'instance hint')
local b = V.buttons(s, s.slots[2], 31)
eq(b.load, false, 'no load inside an instance')
s.busy = nil
b = V.buttons(s, s.slots[2], 31)
eq(b.load, true, 'load'); eq(b.save, true, 'save'); eq(b.saveText, 'Overwrite', 'overwrite text'); eq(b.delete, true, 'delete')
b = V.buttons(s, s.slots[2], 0)
eq(b.load, false, 'cooldown blocks load')
b = V.buttons(s, s.slots[1], 31)
eq(b.load, false, 'active cannot be loaded'); eq(b.saveText, 'Save', 'save active')
b = V.buttons(s, s.slots[3], 31)
eq(b.load, false, 'empty cannot be loaded'); eq(b.rename, false, 'empty cannot be renamed'); eq(b.saveText, 'Save here', 'save here')
b = V.buttons(s, s.slots[5], 31)
eq(b.save, false, 'locked cannot be saved')
s.level = 5
b = V.buttons(s, s.slots[3], 31)
eq(b.save, false, 'low level')
has(V.switchHint(s, 31), 'level 8', 'low level hint')
s.level = 300

-- small helpers
eq(V.nextIcon(s.icons, 'skills'), 'spells', 'next icon'); eq(V.nextIcon(s.icons, 'pvp'), 'skills', 'wraps')
eq(V.nextIcon(s.icons, 'nope'), 'skills', 'unknown -> first')
eq(V.profileKey('Ash Bringer', 2), 'ash bringer:2', 'profile key')
eq(V.resultText({ text = 'Saved.', lines = { 'a', 'b' } }), 'Saved.\na\nb', 'result text')
eq(V.pickSelection(s, 2), 2, 'keeps selection'); eq(V.pickSelection(s, 9), 1, 'active one'); eq(V.pickSelection(nil, 1), nil, 'no state')

print('loadoutsview_test: ' .. n .. ' checks passed')
