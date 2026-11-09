-- luajit hotbar_test.lua && lua5.3 hotbar_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'hotbar_logic.lua')
dofile(dir .. '../game_floatchat/floatchat_logic.lua')
dofile(dir .. '../game_partyframes/partymath.lua')
dofile(dir .. '../client_chaos_settings/settingslist.lua')
local L, F = HotbarLogic, FloatChatLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- bar width from the slot count and the scale
local m = L.metrics({ count = 8, scale = 100, globes = false })
eq(m.cellsW, 8 * 44 + 7 * 4, '8 slots, cells width')
eq(m.width, m.cellsW + 2 * 14 + 2 * 52 + 2 * 26, 'width without globes')
eq(L.metrics({ count = 6, scale = 100, globes = false }).width < m.width, true, 'fewer slots, narrower')
eq(L.metrics({ count = 12, scale = 100, globes = false }).width - m.width, 4 * 48, 'four more slots')
eq(L.metrics({ count = 8, scale = 125, globes = false }).width > m.width, true, 'bigger scale, wider')
eq(L.metrics({ count = 8, scale = 75, globes = false }).width < m.width, true, 'smaller scale, narrower')
eq(L.metrics({ count = 9, scale = 100 }).count, 8, 'a count off the list goes to the nearest')
eq(L.metrics({ count = 7, scale = 100 }).count, 6, 'a tie goes to the smaller count')
eq(L.metrics({ count = 99 }).count, 12, 'count cap')
eq(L.clampScale(10), 75, 'scale floor'); eq(L.clampScale(400), 125, 'scale cap'); eq(L.clampScale(103), 105, 'scale step')
eq(L.clampScale(nil), 100, 'scale default')

-- globes on: caps hold the globes; off: the caps close and the bar is narrower
local on = L.metrics({ count = 8, scale = 100, globes = true })
local off = L.metrics({ count = 8, scale = 100, globes = false })
eq(on.width - off.width, 2 * (on.capW - off.capW), 'globes widen by the two caps')
eq(on.width > off.width, true, 'globes on: wider')
eq(on.orb, 110, 'globe diameter at 100%')
eq(on.capW, 110 + 6, 'cap holds the globe')
eq(off.orb, 0, 'no globe')
eq(on.height, 110, 'a taller globe sets the height')
eq(off.height, 14 + 84, 'no globe: line + body')
eq(on.bodyTop, 110 - 84, 'body sits on the bottom')
eq(L.metrics({ count = 8, scale = 75, globes = true }).orb, 83, 'globe follows the scale')
eq(L.orbDiameter(125), 138, 'orbDiameter')
eq(on.slotsX, on.capW + on.pad + on.socket + on.socketGap, 'slots start after the left socket')
eq(on.socketRX + on.socket + on.pad + on.capW, on.width, 'right socket ends where the cap starts')
eq(on.slotsX + on.cellsW + on.socketGap, on.socketRX, 'right socket after the slots')

-- fit: scale first, then the slot count
local o, cut, fm = L.fit({ count = 12, scale = 125, globes = true }, 2000)
eq(cut, false, 'fits in 2000'); eq(o.count, 12, 'count kept'); eq(fm.width <= 2000, true, 'width')
o, cut, fm = L.fit({ count = 12, scale = 125, globes = true }, 900)
eq(cut, true, 'cut at 900'); eq(fm.width <= 900, true, 'fits 900 afterwards'); eq(o.scale < 125, true, 'scale down first')
o, cut, fm = L.fit({ count = 12, scale = 100, globes = true }, 450)
eq(fm.width <= 450, true, 'fits 450'); eq(o.count < 12, true, 'then slots are dropped')
o, cut, fm = L.fit({ count = 12, scale = 100, globes = true }, 100)
eq(o.count, 4, 'never under 4 slots'); eq(o.scale, 60, 'never under 60%')
eq(L.fit({ count = 8, scale = 100, globes = true }, nil).count, 8, 'no limit')

-- place: centred in the region, kept inside it, drag, snap
local p = L.place({ regionLeft = 0, regionRight = 1090, width = 744, height = 110, windowHeight = 720 })
eq(p.left, 173, 'centred'); eq(p.x, nil, 'centred has no x'); eq(p.bottom, 4, 'bottom gap'); eq(p.lift, 0, 'no lift')
p = L.place({ regionLeft = 0, regionRight = 1090, width = 744, height = 110, windowHeight = 720, x = 5000, lift = 9000 })
eq(p.left + 744, 1090, 'kept inside the region'); eq(p.lift, 720 - 110 - 4, 'lift limit')
p = L.place({ regionLeft = 100, regionRight = 1090, width = 744, height = 110, windowHeight = 720, x = -50 })
eq(p.left, 100, 'not left of the region')
local x, lift = L.dragPlace({ left = 173, lift = 0, mouseX = 500, mouseY = 700 }, 540, 650, 0)
eq(x, 213, 'drag x'); eq(lift, 50, 'drag up lifts')
x, lift = L.dragPlace({ left = 173, lift = 0, mouseX = 500, mouseY = 700 }, 540, 760, 0)
eq(lift, 0, 'cannot go below the bottom')
p = L.place({ regionLeft = 0, regionRight = 1090, width = 744, height = 110, windowHeight = 720, x = 177, lift = 6 })
x, lift = L.snap(p)
eq(x, nil, 'near the centre snaps back'); eq(lift, 0, 'near the bottom snaps back')
p = L.place({ regionLeft = 0, regionRight = 1090, width = 744, height = 110, windowHeight = 720, x = 40, lift = 60 })
x, lift = L.snap(p)
eq(x, 40, 'far from the centre stays'); eq(lift, 60, 'far from the bottom stays')

-- slots of the first bar
local plan = L.slotPlan(50, 8)
eq(#plan.shown, 8, '8 shown'); eq(plan.potion, 13, 'potion socket'); eq(plan.utility, 14, 'utility socket')
eq(#plan.hidden, 50 - 8 - 2, 'the rest is hidden')
plan = L.slotPlan(50, 12)
eq(#plan.shown, 12, '12 shown'); eq(plan.potion, 13, 'socket slots do not move with the count')
plan = L.slotPlan(10, 6)
eq(plan.potion, nil, 'a bar with 10 slots has no sockets'); eq(#plan.hidden, 4, 'hidden of a short bar')
plan = L.slotPlan(0, 6)
eq(#plan.shown, 0, 'no bar')
eq(#L.slotPlan(50, 4).shown, 4, 'a fitted bar with 4 slots')

-- key labels
eq(L.keyLabel('1'), '1', 'plain key'); eq(L.keyLabel('Shift+F1'), 'S+F1', 'Shift short'); eq(L.keyLabel(''), '', 'empty')
eq(L.keyLabel('', 'potion'), 'Q', 'potion default key'); eq(L.keyLabel(nil, 'utility'), 'E', 'utility default key')
eq(L.keyLabel('Ctrl+Shift+Z'), 'C+S+Z', 'two modifiers'); eq(L.keyLabel('Ctrl+Alt+Del'):len() <= 5, true, 'at most 5 characters')
eq(L.keyLabel('7', 'potion'), '7', 'its own hotkey wins')

-- cooldown number
local t, share = L.cooldown(10000, 2000)
eq(t, '8', '8 s left'); eq(share, 0.8, 'fill share')
eq((L.cooldown(10000, 9100)), '0.9', 'under 2 s: a decimal')
eq((L.cooldown(10000, 8500)), '1.5', '1.5 s')
eq((L.cooldown(10000, 8000)), '2', '2 s')
eq((L.cooldown(10000, 9990)), '0.1', 'last tenth')
eq((L.cooldown(10000, 10000)), '', 'done')
eq((L.cooldown(0, 0)), '', 'none')
eq((L.cooldown(nil, nil)), '', 'nil')
eq((L.cooldown(90000, 0)), '2m', 'minutes round up')
eq((L.cooldown(59000, 0)), '59', 'under a minute')
eq(select(2, L.cooldown(0, 0)), 0, 'no fill')

-- event line: loot and level messages, five seconds, fading
eq(L.eventFromMessage('Loot of a rat: 3 gold coins, a cheese'), 'Gained 3 gold coins, a cheese', 'loot line')
eq(L.eventFromMessage('Loot of a rat: nothing'), nil, 'no loot')
eq(L.eventFromMessage('You advanced from Level 119 to Level 120.'), 'Level 120', 'level')
eq(L.eventFromMessage('You advanced to Level 8'), 'Level 8', 'level, short form')
eq(L.eventFromMessage('You see a tree.'), nil, 'other text')
eq(L.eventFromMessage(nil), nil, 'nil')
eq(#L.eventFromMessage('Loot of a dragon: ' .. string.rep('x', 200)) <= 7 + 60, true, 'long loot cut')
local ev = L.pushEvent(nil, 'Gained a helm', 1000)
local text, a = L.eventLine(ev, 1000)
eq(text, 'Gained a helm', 'shown'); eq(a, 1, 'full at first')
text, a = L.eventLine(ev, 4900); eq(a, 1, 'full until 4 s')
text, a = L.eventLine(ev, 5500); eq(a, 0.5, 'half at 4.5 s')
text, a = L.eventLine(ev, 6001); eq(text, '', 'gone after 5 s'); eq(a, 0, 'gone')
ev = L.pushEvent(ev, 'Level 9', 2000)
eq((L.eventLine(ev, 2100)), 'Level 9', 'the newest wins')
eq((L.eventLine(nil, 5)), '', 'no event')

-- settings: defaults, clamps, round trip through g_settings
local d = L.settingsFor(nil, 'A')
eq(d.count, 8, 'default count'); eq(d.scale, 100, 'default scale'); eq(d.globes, true, 'globes on by default'); eq(d.x, nil, 'centred')
local node = L.store(nil, 'A', { count = 12, scale = 85, globes = false, x = 30, lift = 20 })
node = L.store(node, 'B', { count = 6, scale = 120, globes = true })
local back = ChaosSettings.roundTrip(node)
local a1, b1 = L.settingsFor(back, 'A'), L.settingsFor(back, 'B')
eq(a1.count, 12, 'count kept'); eq(a1.scale, 85, 'scale kept'); eq(a1.globes, false, 'globes off kept'); eq(a1.x, 30, 'x kept')
eq(a1.lift, 20, 'lift kept'); eq(b1.count, 6, 'B count'); eq(b1.globes, true, 'B globes'); eq(b1.x, nil, 'B centred')
eq(L.settingsFor({ A = { count = 5, scale = 9, lift = -4 } }, 'A').count, 6, 'saved count clamped')
eq(L.settingsFor({ A = { scale = 9 } }, 'A').scale, 75, 'saved scale clamped')
eq(L.settingsFor({ A = { lift = -4 } }, 'A').lift, 0, 'saved lift clamped')
eq(L.settingsFor({ A = { globes = 'false' } }, 'A').globes, false, 'globes as a string')

-- the bar and the other HUD at 1280x720 and 1920x1080 (right panel 190 px wide, as the party frames test assumes)
local overlaps = L.overlap
for _, res in ipairs({ { 1280, 720 }, { 1920, 1080 } }) do
  local W, H = res[1], res[2]
  local region = { left = 0, right = W - 190 }
  local combos = {}
  for _, c in ipairs(L.COUNTS) do
    for _, sc in ipairs({ 75, 100, 125 }) do
      for _, gl in ipairs({ true, false }) do combos[#combos + 1] = { count = c, scale = sc, globes = gl } end
    end
  end
  for _, opt in ipairs(combos) do
    local name = string.format('%dx%d count %d scale %d globes %s', W, H, opt.count, opt.scale, tostring(opt.globes))
    local fo, _, fm = L.fit(opt, region.right - region.left - 16)
    local pl = L.place({ regionLeft = region.left, regionRight = region.right, width = fm.width, height = fm.height,
                         windowHeight = H })
    local bar = L.rect(pl, fm, H)
    eq(bar.x >= 0 and bar.x + bar.width <= region.right, true, name .. ': inside the game area')
    eq(bar.y >= 0 and bar.y + bar.height <= H, true, name .. ': inside the window')
    -- the side panels
    eq(overlaps(bar, { x = region.right, y = 0, width = 190, height = H }), false, name .. ': clear of the side panel')
    -- the party frames default spot (200 px wide, 4 frames of 44 px) with the bar avoided
    local map = { x = 0, y = 0, width = W, height = H }
    local win = { width = W, height = H }
    local sides = { { x = region.right, y = 0, width = 190, height = H } }
    local px, py = PartyMath.defaultAvoiding(map, win, sides, {}, 200, 400, bar, 0, 0)
    local party = { x = px, y = py, width = 200, height = 400 }
    eq(overlaps(party, bar), false, name .. ': party frames clear of the bar')
    eq(party.x >= 0 and party.y >= 0 and party.x + 200 <= region.right and party.y + 400 <= H, true, name .. ': party frames on screen')
    -- the floating chat's first place
    local chat = F.defaultRect({ x = 0, y = 0, width = region.right, height = H }, bar)
    eq(overlaps(chat, bar), false, name .. ': chat clear of the bar')
    eq(chat.x >= 0 and chat.y >= 0 and chat.x + chat.width <= region.right and chat.y + chat.height <= H, true, name .. ': chat on screen')
    eq(overlaps(chat, party), false, name .. ': chat clear of the party frames')
    -- the character sits in the middle of the map, its buff bar under the plate: far above the bar
    local plate = { x = math.floor(region.right / 2) - 60, y = math.floor(H / 2) - 90, width = 120, height = 60 }
    local buffs = { x = plate.x, y = plate.y + plate.height, width = 5 * 20, height = 20 }
    eq(overlaps(buffs, bar), false, name .. ': buff bar clear of the bar')
  end
end
-- without the avoidance the frames do sit on the bar at 1280x720 (so the rule is needed)
do
  local W, H = 1280, 720
  local fo, _, fm = L.fit({ count = 8, scale = 100, globes = true }, 1090 - 16)
  local pl = L.place({ regionLeft = 0, regionRight = 1090, width = fm.width, height = fm.height, windowHeight = H })
  local bar = L.rect(pl, fm, H)
  local free = PartyMath.freeArea({ x = 0, y = 0, width = W, height = H }, { width = W, height = H },
    { { x = 1090, y = 0, width = 190, height = H } }, {})
  -- a full party (4 frames with buffs, 400 px) is moved up above the control strip, onto the bar's right end
  local x, y = PartyMath.defaultPosition(free, 200, 400, 0, 0)
  eq(overlaps({ x = x, y = y, width = 200, height = 400 }, bar), true, 'a tall party default alone would sit on the bar')
  local ax, ay = PartyMath.defaultAvoiding({ x = 0, y = 0, width = W, height = H }, { width = W, height = H },
    { { x = 1090, y = 0, width = 190, height = H } }, {}, 200, 400, bar, 0, 0)
  eq(overlaps({ x = ax, y = ay, width = 200, height = 400 }, bar), false, 'and clear of it with the rule')
end
eq(L.overlap(nil, { x = 0, y = 0, width = 1, height = 1 }), false, 'overlap with nothing')

-- the round chat and gear buttons stay clear above the slot frames at every scale, with and without globes, and the
-- two buttons do not touch each other
for _, globes in ipairs({ true, false }) do
  for scale = L.SCALE_MIN, L.SCALE_MAX, L.SCALE_STEP do
    for _, count in ipairs(L.COUNTS) do
      local mm = L.metrics({ count = count, scale = scale, globes = globes })
      local cb = L.cornerButtons(mm)
      local tag = string.format('%d%% %s', scale, globes and 'globes' or 'no globes')
      eq(cb.top + cb.size <= mm.slotY - L.CORNER_GAP, true, 'buttons end above the slot frames at ' .. tag)
      eq(cb.top >= 0, true, 'buttons inside the bar at ' .. tag)
      eq(cb.size >= 12 and cb.size <= L.CORNER_BUTTON, true, 'button size at ' .. tag)
      eq(cb.chatRight - cb.gearRight >= cb.size + 1, true, 'chat and gear apart at ' .. tag)
      eq(cb.chatRight + cb.size <= mm.width, true, 'chat button inside the bar at ' .. tag)
    end
  end
end

-- default keys: 1..8 on slots 1..8, Q and E on the sockets, Chat Off only, a player's own key stays
do
  local function act(slot, bar) return 'TriggerActionButton_' .. (bar or 1) .. '.' .. slot end
  local function find(list, action, secondary)
    for _, e in ipairs(list) do
      if e.actionsetting and e.actionsetting.action == action and (e.secondary and true or false) == (secondary and true or false) then return e end
    end
  end
  local function stock()
    local l = {}
    for i = 1, 12 do l[#l + 1] = { actionsetting = { action = act(i) }, keysequence = 'F' .. i } end
    l[#l + 1] = { actionsetting = { action = act(1, 2) }, keysequence = 'F1' } -- bar 2 is not ours
    l[#l + 1] = { actionsetting = { action = 'GoNorthWest' }, keysequence = 'Q' }
    l[#l + 1] = { actionsetting = { action = 'GoNorthEast' }, keysequence = 'E' }
    l[#l + 1] = { actionsetting = { action = 'GoNorth' }, keysequence = 'W' }
    return l
  end
  local list = stock()
  local changed, skipped = L.applyDefaultKeys(list, 1)
  eq(changed, true, 'stock list changes'); eq(#skipped, 0, 'nothing skipped')
  for i = 1, 8 do eq(find(list, act(i)).keysequence, tostring(i), 'slot ' .. i .. ' gets ' .. i) end
  for i = 9, 12 do eq(find(list, act(i)).keysequence, 'F' .. i, 'slot ' .. i .. ' keeps F' .. i) end
  eq(find(list, act(1, 2)).keysequence, 'F1', 'another bar untouched')
  eq(find(list, act(13)).keysequence, 'Q', 'socket 13 gets Q'); eq(find(list, act(14)).keysequence, 'E', 'socket 14 gets E')
  eq(find(list, 'GoNorthWest'), nil, 'Q taken from Go North-West'); eq(find(list, 'GoNorthEast'), nil, 'E taken from Go North-East')
  eq(find(list, 'GoNorth').keysequence, 'W', 'W stays')
  eq(L.applyDefaultKeys(list, 1), false, 'second run changes nothing')

  -- the player's own keys stay (a letter, a modifier combo, a digit on another slot), also when he cleared one slot's stock key
  local own = stock()
  find(own, act(1)).keysequence = 'Ctrl+1'
  find(own, act(2)).keysequence = 'x'
  find(own, act(3)).keysequence = '3'
  table.remove(own, 5) -- slot 5 had its entry removed
  L.applyDefaultKeys(own, 1)
  eq(find(own, act(1)).keysequence, 'Ctrl+1', 'own combo kept'); eq(find(own, act(2)).keysequence, 'x', 'own letter kept')
  eq(find(own, act(3)).keysequence, '3', 'already a digit'); eq(find(own, act(4)).keysequence, '4', 'stock replaced')
  eq(find(own, act(5)) and find(own, act(5)).keysequence, '5', 'no entry (fresh) gets the default')

  -- a key held by anything else is not taken: slot stays on F, reported
  local held = stock()
  held[#held + 1] = { actionsetting = { action = 'Screenshot' }, keysequence = '2' }
  held[#held + 1] = { actionsetting = { action = 'Custom' }, keysequence = 'q' }
  local ch, sk = L.applyDefaultKeys(held, 1)
  eq(ch, true, 'the rest still changes'); eq(find(held, act(2)).keysequence, 'F2', 'slot 2 keeps F2')
  eq(find(held, act(13)), nil, 'no entry for Q when another action holds q')
  eq(sk[1], 2, 'slot 2 reported'); eq(sk[2], 13, 'slot 13 reported')
  eq(find(held, 'GoNorthWest').keysequence, 'Q', 'Go North-West stays when Q is not given away')

  -- a blank key row counts as unset; a secondary row never counts as the slot's key
  local blank = { { actionsetting = { action = act(1) }, keysequence = '' },
                  { actionsetting = { action = act(1) }, keysequence = 'F1', secondary = true } }
  L.applyDefaultKeys(blank, 1)
  eq(find(blank, act(1)).keysequence, '1', 'blank row gets 1'); eq(find(blank, act(1), true).keysequence, 'F1', 'secondary row stays')
  eq(L.applyDefaultKeys(nil, 1), false, 'no list')
  eq(L.keyLabel('1'), '1', 'label of a digit')

  -- over all sets, one time: Chat On is never touched
  local sets = { Knight = { chatOn = stock(), chatOff = stock() }, Mage = { chatOn = {}, chatOff = {} }, Broken = 5 }
  local cur, any, done = L.applyToSets(sets, nil, 'Knight', 1)
  eq(cur, true, 'current set changed'); eq(any, true, 'a set changed')
  eq(done.Knight, true, 'done flag'); eq(done.Mage, true, 'empty set done too'); eq(done.Broken, nil, 'a non-table set is skipped')
  eq(find(sets.Knight.chatOn, act(1)).keysequence, 'F1', 'Chat On keeps F1')
  eq(find(sets.Knight.chatOff, act(1)).keysequence, '1', 'Chat Off has 1')
  eq(find(sets.Mage.chatOff, act(8)).keysequence, '8', 'a fresh set gets 8')
  find(sets.Knight.chatOff, act(1)).keysequence = 'F1' -- the player goes back to F1 later
  cur, any = L.applyToSets(sets, done, 'Knight', 1)
  eq(cur or any, false, 'done sets are not run again: his F1 stays')
  eq(find(sets.Knight.chatOff, act(1)).keysequence, 'F1', 'F1 still F1')
end

-- finding the base bar after a death or any relog (Death and re-login, 2026-11-09): the bar's own visible flag counts
do
  local function c(id, slots, shown) return { id = id, slots = slots, shown = shown } end
  eq(L.pickBar({ c('actionbar.1', 50, true), c('actionbar.2', 50, true) }), 1, 'the base id wins')
  eq(L.pickBar({ c('actionbar.2', 50, true), c('actionbar.3', 50, true), c('actionbar.1', 50, true) }), 3, 'the base id wins, whatever its place')
  eq(L.pickBar({ c('actionbar.1', 50, false), c('actionbar.2', 50, true) }), 2, 'a bar the player hid is not taken')
  eq(L.pickBar({ c('actionbar.1', 4, true), c('actionbar.2', 50, true) }), 2, 'too few slots')
  eq(L.pickBar({ c('actionbar.1', 50, false) }), nil, 'nothing shown: none')
  eq(L.pickBar({ c('other', 50, true), c('x', 50, true) }), 1, 'no base id: the first shown')
  eq(L.pickBar({}), nil, 'no children'); eq(L.pickBar(nil), nil, 'no list')
  eq(L.adoptDelay(0), 300, 'fast first'); eq(L.adoptDelay(69), 300, 'fast until the 70th')
  eq(L.adoptDelay(70), 2000, 'then slow'); eq(L.adoptDelay(5000), 2000, 'slow for ever')
  local f = {}
  eq(L.barLost(true, f, f), false, 'bar in the frame'); eq(L.barLost(false, nil, f), true, 'bar destroyed')
  eq(L.barLost(true, {}, f), true, 'bar taken back by the base'); eq(L.barLost(false, f, f), true, 'dead bar')
end

if fails == 0 then print('hotbar_test: ok') end
os.exit(fails == 0 and 0 or 1)
