-- luajit dungeons_widgets_test.lua && lua5.3 dungeons_widgets_test.lua (CI runs every client *_test.lua from the repo root)
-- dungeons.lua on a fake widget engine. The fake builds every widget from the REAL dungeons.otui, killcounter.otui and
-- challenge.otui (styles, bases, nested children, ids, !text, visible, checked, @events), so a Lua lookup of an id or a style
-- the .otui lacks fails here as it would in the client, and a call of an engine method the fake does not know raises. It
-- plays the opening, the payloads of a server (9 dungeons and the Weekly Challenge), the card rail with its groups and filter
-- chips, a card click, a difficulty click, the queue, the level veil, the Loot / Ranking tabs, the phone pages and the kill counter.
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

-- ---------------------------------------------------------------- the .otui files as trees
local function readFile(name)
  local f = assert(io.open(here .. name, 'r'))
  local s = f:read('*a')
  f:close()
  return s
end

local styles, roots, allIds = {}, {}, {}

local function parse(text, rootKey)
  local stack = { { indent = -1, node = { children = {}, props = {} } } }
  local skipAt = nil
  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    local indent = #line:match('^( *)')
    local body = line:match('^%s*(.-)%s*$')
    if body ~= '' and body:sub(1, 2) ~= '//' then
      if skipAt and indent > skipAt then
        -- inside a $state or layout block
      else
        skipAt = nil
        while #stack > 1 and stack[#stack].indent >= indent do stack[#stack] = nil end
        local parent = stack[#stack].node
        if body:sub(1, 1) == '$' or body == 'layout:' then
          skipAt = indent
        elseif body:match('^[%a][%w_]*$') then
          local node = { style = body, children = {}, props = {}, events = {} }
          parent.children[#parent.children + 1] = node
          stack[#stack + 1] = { indent = indent, node = node }
        elseif body:match('^[%a][%w_]*%s*<%s*[%a][%w_]*$') then
          local name, base = body:match('^([%a][%w_]*)%s*<%s*([%a][%w_]*)$')
          local node = { style = name, base = base, children = {}, props = {}, events = {} }
          styles[name] = node
          stack[#stack + 1] = { indent = indent, node = node }
        else
          local key, value = body:match('^([^:]+):%s*(.*)$')
          assert(key, 'cannot read ' .. rootKey .. ': ' .. body)
          if key:sub(1, 1) == '@' then
            parent.events[key:sub(2)] = value
          else
            parent.props[key] = value
          end
          if key == 'id' then allIds[value] = true end
        end
      end
    end
  end
  local top = stack[1].node.children[1]
  -- a file's first top-level node that is not a style is its widget (ChaosMainWindow, Panel)
  for _, node in ipairs(stack[1].node.children) do
    if not node.base then top = node end
  end
  roots[rootKey] = top
end

parse(readFile('dungeons.otui'), 'dungeons')
parse(readFile('killcounter.otui'), 'killcounter')
parse(readFile('challenge.otui'), 'challenge')
eq(roots.dungeons.style, 'ChaosMainWindow', 'the window is a ChaosMainWindow')
eq(styles.DungeonCard ~= nil, true, 'the card style')

-- ---------------------------------------------------------------- the fake engine
local Widget = {}
Widget.__index = function(t, k)
  if Widget[k] then return Widget[k] end
  return rawget(t, k)
end
local all = {}
local function new(style, parent)
  local w = setmetatable({ style = style, parent = parent, kids = {}, text = '', visible = true, enabled = true,
    checked = false, focused = false, events = {}, destroyed = false, rows = {}, value = 0 }, Widget)
  if parent then parent.kids[#parent.kids + 1] = w end
  all[#all + 1] = w
  return w
end

local envModules
local function compile(expr)
  local f = assert(load('return function(self) ' .. expr .. ' end', 'event', 't', setmetatable({ modules = envModules }, { __index = _G })))
  return f()
end

local function applyNode(node, w)
  local p = node.props
  if p.id then w.id = p.id end
  if p.visible == 'false' then w.visible = false end
  if p.checked == 'true' then w.checked = true end
  local t = p['!text'] or p.text
  if t then w.text = (t:match("^tr%('(.*)'%)$") or t):gsub('\\n', '\n') end
  for ev, expr in pairs(node.events or {}) do w.events[ev] = compile(expr) end
  for _, child in ipairs(node.children) do
    local cw = w:build(child.style)
    applyNode(child, cw)
  end
end
local function applyStyle(name, w, seen)
  local def = styles[name]
  if not def then return end
  assert(not seen[name], 'style loop ' .. name)
  seen[name] = true
  if def.base then applyStyle(def.base, w, seen) end
  applyNode(def, w)
end
function Widget:build(style)
  local w = new(style, self)
  applyStyle(style, w, {})
  return w
end

local function instantiate(rootKey, parent)
  local node = roots[rootKey]
  local w = new(node.style, parent)
  applyStyle(node.style, w, {})
  applyNode(node, w)
  return w
end

function Widget:getId() return self.id end
function Widget:setId(id) self.id = id end
function Widget:getChildById(id)
  for _, k in ipairs(self.kids) do if k.id == id then return k end end
  return nil
end
function Widget:recursiveGetChildById(id)
  for _, k in ipairs(self.kids) do
    if k.id == id then return k end
    local r = k:recursiveGetChildById(id)
    if r then return r end
  end
  return nil
end
function Widget:getChildByIndex(i) return self.kids[i] end
function Widget:getChildCount() return #self.kids end
function Widget:getChildren() return self.kids end
function Widget:destroy()
  self.destroyed = true
  if self.parent then
    for i, k in ipairs(self.parent.kids) do if k == self then table.remove(self.parent.kids, i) break end end
  end
end
function Widget:destroyChildren() for i = #self.kids, 1, -1 do self.kids[i]:destroy() end end
function Widget:getParent() return self.parent end
function Widget:setText(t) self.text = t end
function Widget:getText() return self.text end
function Widget:getTextSize() return { width = #self.text * 6, height = 12 } end
function Widget:setVisible(v) self.visible = v and true or false end
function Widget:isVisible() return self.visible end
function Widget:show() self.visible = true end
function Widget:hide() self.visible = false end
function Widget:raise() end
function Widget:focus() end
function Widget:enable() self.enabled = true end
function Widget:disable() self.enabled = false end
function Widget:isEnabled() return self.enabled end
function Widget:setEnabled(v) self.enabled = v and true or false end
function Widget:setChecked(v) self.checked = v and true or false end
function Widget:isChecked() return self.checked end
function Widget:setOn(v) self.on = v end
function Widget:isOn() return self.on == true end
function Widget:setColor(c) self.color = c end
function Widget:setWidth(w) self.width = w end
function Widget:setHeight(h) self.height = h end
function Widget:setMarginTop() end
function Widget:addAnchor() end
function Widget:setImageSource(s) self.image = s end
function Widget:setOutfit(o) self.outfit = o end
function Widget:setItemId(i) self.itemId = i end
function Widget:setItemCount(c) self.itemCount = c end
function Widget:setItem(i) self.itemId = nil self.itemCount = nil end
function Widget:setTooltip(t) self.tooltip = t end
function Widget:containsPoint() return true end
function Widget:setValue(v) self.value = v end
function Widget:getValue() return self.value end
function Widget:ensureChildVisible(c) self.shown = c end
function Widget:focusChild(child)
  for _, k in ipairs(self.kids) do
    if k == child then
      if not k.focused then k.focused = true if k.events.onFocusChange then k.events.onFocusChange(k) end end
    elseif k.focused then
      k.focused = false
      if k.events.onFocusChange then k.events.onFocusChange(k) end
    end
  end
end
function Widget:isFocused() return self.focused end
function Widget:clearData() self.rows = {} end
function Widget:addRow(cols, height, color) self.rows[#self.rows + 1] = { cols = cols, height = height, color = color } end
function Widget:getTextSize() return { width = #self.text * 6, height = 12 } end

local function find(w, id) return w:recursiveGetChildById(id) end
local function fire(w, ev, ...) return w[ev](w, ...) end

-- the globals of the client
local sent = {}
local pending = {}
local mobile = false
local playerLevel = 600
local logged = {}
tr = function(s, ...) if select('#', ...) > 0 then return string.format(s, ...) end return s end
formatShortNumber = function(v) return tostring(v) end
MouseLeftButton, MouseRightButton, MouseWheelUp, MouseWheelDown = 1, 2, 3, 4
g_app = { isMobile = function() return mobile end }
g_logger = { error = function(m) logged[#logged + 1] = m end, warning = function(m) logged[#logged + 1] = m end }
g_effects = { fadeIn = function() end, fadeOut = function() end }
g_resources = { fileExists = function(p) return p:match('/images/dungeons/') ~= nil end }
local mapPanel
g_ui = {
  displayUI = function(name) assert(name == 'dungeons') return instantiate('dungeons', nil) end,
  loadUI = function(name, parent) assert(roots[name], 'unknown ui ' .. name) return instantiate(name, parent) end,
  createWidget = function(style, parent)
    assert(styles[style] or style:match('^UI') or style:match('^Chaos'), 'unknown style ' .. style)
    local w = new(style, parent)
    applyStyle(style, w, {})
    return w
  end,
}
local protocol = { sendExtendedOpcode = function(_, code, buffer) sent[#sent + 1] = { code = code, buffer = buffer } end }
g_game = { isOnline = function() return true end, getProtocolGame = function() return protocol end,
  getLocalPlayer = function() return { getLevel = function() return playerLevel end } end }
json = { encode = function(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return 'json:' .. tostring(t.action) .. ':' .. (t.data and tostring(t.data.id) or '') .. ':' .. (t.data and tostring(t.data.difficulty) or '')
end, decode = function(s) return s end }
connect = function() end
disconnect = function() end
LocalPlayer = {}
ProtocolGame = { registerExtendedOpcode = function() end, unregisterExtendedOpcode = function() end }
function scheduleEvent(fn, ms) pending[#pending + 1] = { fn = fn, ms = ms } return #pending end
function removeEvent(id) if pending[id] then pending[id].dead = true end end
local function flush(limit)
  local ran = 0
  while ran < (limit or 50) do
    local ev
    for i, e in ipairs(pending) do if not e.dead and not e.done then ev = e break end end
    if not ev then break end
    ev.done = true
    ev.fn()
    ran = ran + 1
  end
  return ran
end
local button = new('topbutton', nil)
local topbarCalls = 0
modules = { client_topmenu = { addRightGameToggleButton = function() topbarCalls = topbarCalls + 1 return button end },
  game_interface = { getMapPanel = function() mapPanel = mapPanel or new('map', nil) return mapPanel end } }
modules.game_dungeons = _G
envModules = modules
function Widget:isDestroyed() return self.destroyed end

-- ---------------------------------------------------------------- every id and style the Lua code names is in the .otui files
do
  local src = readFile('dungeons.lua')
  local missing = {}
  local function need(id) if not allIds[id] and not missing[id] then missing[id] = true end end
  for id in src:gmatch('ui%("([%w_]+)"%)') do need(id) end
  for id in src:gmatch("ui%('([%w_]+)'%)") do need(id) end
  for id in src:gmatch('getChildById%("([%w_]+)"%)') do need(id) end
  for id in src:gmatch("getChildById%('([%w_]+)'%)") do need(id) end
  for id in src:gmatch('safeRecursiveGet%(window, "([%w_]+)"%)') do need(id) end
  local list = {}
  for id in pairs(missing) do list[#list + 1] = id end
  table.sort(list)
  eq(table.concat(list, ','), '', 'ids the Lua code looks up that no .otui has')
  for style in (src:gsub('%-%-[^\n]*', '')):gmatch('createWidget%("([%w_]+)"') do eq(styles[style] ~= nil, true, 'style ' .. style) end
  for style in (src:gsub('%-%-[^\n]*', '')):gmatch("createWidget%('([%w_]+)'") do eq(styles[style] ~= nil, true, 'style ' .. style) end
end


-- ---------------------------------------------------------------- load the module
dofile(here .. 'dungeonsview.lua')
dofile(here .. 'dungeons.lua')
init()
eq(topbarCalls, 1, 'the top bar button is added once')
local function theWindow()
  for _, w in ipairs(all) do if w.style == 'ChaosMainWindow' and not w.destroyed then return w end end
end
local window = theWindow()
eq(window ~= nil, true, 'the window exists')
eq(window.visible, false, 'hidden until opened')
eq(sent[1].code, 109, 'fetch goes out on opcode 109')
eq(sent[1].buffer:match('^json:fetch'), 'json:fetch', 'the first message is fetch')

-- ---------------------------------------------------------------- the payloads of a server
local function dungeon(id, title, level, opts)
  opts = opts or {}
  local loot = {}
  for i = 1, (opts.loot or 12) do loot[i] = { clientId = 3000 + i, count = i == 2 and 5 or 1, name = 'Thing ' .. i } end
  return { id = id, title = title, difficulty = opts.difficulty or 1, req = { level = level, party = opts.party, gold = opts.gold,
    quests = opts.quests, items = opts.items, iLvl = opts.iLvl }, loot = loot,
    queue = { players = opts.queue or 0, estimated = opts.estimated or 0 }, challenges = opts.challenges or {},
    health = opts.health, weekly = opts.weekly }
end
local specs = {
  { 1, 'Bones Dungeon', 150, { party = '1-2', difficulty = 3, challenges = { { title = 'Speed Runner', points = 5, desc = 'Fast.', completed = true } } } },
  { 2, 'Master of the Elements', 200, { party = '1-2' } },
  { 3, 'Forbidden Chevalier', 500, { party = '1-2', gold = 100000, quests = { 'Q one', 'Q two' }, items = { { clientId = 100, count = 3 } } } },
  { 4, 'Rootmaw', 600, { queue = 4, estimated = 90000 } },
  { 5, 'The Hollow Vault', 800, { difficulty = 6, queue = 7, iLvl = 350 } },
  { 6, 'The Marrow Crypts', 1000, {} },
  { 7, 'The Iron Crucible', 1300, {} },
  { 8, 'The Fallen Sanctum', 1600, {} },
  { 9, 'The Pyre Throne', 2000, {} },
  { 10, 'Weekly Challenge', 800, { weekly = { label = '2026-W46', theme = 'Marrow Crypts', current = true, resetIn = 3600 } } },
}
local payloads, list = {}, {}
for _, s in ipairs(specs) do
  payloads[s[1]] = dungeon(s[1], s[2], s[3], s[4])
  list[#list + 1] = { id = s[1], title = s[2], level = s[3], boss = { type = 100 + s[1] }, queue = (s[4] or {}).queue or 0 }
end
local function opcode(action, data) onExtendedOpcode(nil, 109, { action = action, data = data }) end
for _, s in ipairs(specs) do opcode('dungeon', payloads[s[1]]) end
opcode('solo', { id = 1, diff = 3, top = { { name = 'Ash', time = 61000 }, { name = 'Me', time = 70000, self = 2 } } })
opcode('group', { id = 1, diff = 3, top = { { name = 'A\nB', time = 90000 } } })
-- the list arrives last, in no order
local shuffled = {}
for _, i in ipairs({ 9, 3, 1, 10, 5, 2, 7, 4, 8, 6 }) do shuffled[#shuffled + 1] = list[i] end
opcode('list', shuffled)
eq(#logged, 0, 'no error logged: ' .. tostring(logged[1]))

-- ---------------------------------------------------------------- the rail
local rail = find(window, 'dungeonsRail')
local function groupsOnRail()
  local out = {}
  for _, box in ipairs(rail.kids) do
    local heading = box:getChildById('heading').text
    local ids = {}
    for _, card in ipairs(box:getChildById('row').kids) do ids[#ids + 1] = card.dungeonId end
    out[#out + 1] = heading .. '=' .. table.concat(ids, ',')
  end
  return table.concat(out, ' | ')
end
eq(groupsOnRail(), 'Levels 1-499=1,2 | Levels 500-999=3,4,5 | Levels 1000+=6,7,8,9 | Weekly=10', 'four groups in order, cards by level')
eq(rail.kids[1].width, 2 * (156 + 8), 'a group is as wide as its cards')
eq(rail.kids[3].width, 4 * (156 + 8), 'a group of four')
local chips = find(window, 'filters')
local chipTexts = {}
for _, c in ipairs(chips.kids) do chipTexts[#chipTexts + 1] = c.text end
eq(table.concat(chipTexts, '|'), 'All|Levels 1-499|Levels 500-999|Levels 1000+|Weekly', 'the filter chips')
eq(chips.visible, true, 'the chips show with several groups')
eq(chips.kids[1].checked, true, 'All is chosen')

local function card(id)
  for _, box in ipairs(rail.kids) do
    for _, c in ipairs(box:getChildById('row').kids) do if c.dungeonId == id then return c end end
  end
end
local function click(c) return c.onMouseRelease(c, { x = 1, y = 1 }, MouseLeftButton) end
eq(card(1).checked, true, 'the lowest dungeon is chosen first')
eq(card(2).checked, false, 'only one card is chosen')
eq(find(window, 'bannerTitle').text, 'Bones Dungeon', 'the header title')
eq(find(window, 'banner').image, '/images/dungeons/Bones', 'the header art')
eq(card(1):getChildById('art').image, '/images/dungeons/Bones', 'the card art')
eq(card(2):getChildById('art').image, '/images/dungeons/MasterElement', 'the card art of Master of the Elements')
eq(card(10):getChildById('art').image, '/images/dungeons/MarrowCrypts', 'the weekly card shows the week theme')
eq(card(1):getChildById('title').text, 'Bones Dungeon', 'card title')
eq(card(1):getChildById('level').text, '150+ Level', 'card level')
eq(card(4):getChildById('queue').text, 'Queue: 4 Players', 'card queue')
eq(card(4):getChildById('queue').color, 'orange', 'queue 4 is orange')
eq(card(5):getChildById('queue').color, 'red', 'queue 7 is red')
eq(card(1):getChildById('queue').text, 'Queue: Open', 'an open queue')
eq(card(1):getChildById('queue').color, 'green', 'an open queue is green')
eq(card(1):getChildById('party').text, 'Party: 1-2', 'card party line')
eq(card(1):getChildById('party').visible, true, 'the party line shows when the dungeon asks for one')
eq(card(4):getChildById('party').visible, false, 'and not when it does not')
eq(card(1):getChildById('group').text, ' Early ', 'group tag')
eq(card(10):getChildById('group').text, ' Weekly ', 'weekly tag')
eq(card(1):getChildById('boss').outfit.type, 101, 'the boss outfit on the card')
eq(card(1):getChildById('best').visible, true, 'Bones was beaten on Expert')
eq(card(1):getChildById('best').text, ' Best: Expert ', 'best difficulty chip')
eq(card(2):getChildById('best').visible, false, 'nothing to say on the first difficulty')
eq(find(window, 'chipLevel').text, ' 150+ Level ', 'header level chip')
eq(find(window, 'chipBest').visible, true, 'header best chip')
eq(find(window, 'reqLevel').text, ' Level: 150 ', 'requirement chip: level')
eq(find(window, 'reqParty').text, ' Party: 1-2 ', 'requirement chip: party')
eq(find(window, 'reqGold').visible, false, 'no gold requirement')
eq(find(window, 'quests').visible, false, 'no quests')
eq(find(window, 'items').visible, false, 'no items')
eq(find(window, 'bossLoot'):getChildByIndex(1).itemId, 3001, 'loot slot 1')
eq(find(window, 'bossLoot'):getChildByIndex(2).tooltip, '5x Thing 2', 'loot tooltip with a count')
eq(find(window, 'bossLoot'):getChildByIndex(13).itemId, nil, 'empty loot slot')
local diffs = find(window, 'difficulties')
eq(#diffs.kids, 6, 'six difficulty tiles')
eq(diffs:getChildByIndex(3).enabled, true, 'Expert is open')
eq(diffs:getChildByIndex(4).enabled, false, 'Master is locked')
eq(diffs:getChildByIndex(4):getChildById('lockImg').visible, true, 'Master shows its padlock')
eq(diffs:getChildByIndex(3):getChildById('lockImg').visible, false, 'Expert shows none')
eq(diffs:getChildByIndex(1):getChildById('info').text, 'Monster Health 100%\nMonster Damage 100%', 'a difficulty text')
eq(diffs:getChildByIndex(3).focused, true, 'the lit tile is the hardest one unlocked')
eq(#find(window, 'challenges').kids, 1, 'one challenge')
eq(find(window, 'challenges').kids[1]:getChildById('checkbox').checked, true, 'the challenge is done')

-- the ranking waits for the 50 ms event of the difficulty focus
flush()
eq(#find(window, 'soloTable').rows, 2, 'solo rows')
eq(find(window, 'soloTable').rows[2].color, '#2daadb', 'my own row is blue')
eq(find(window, 'soloTable').rows[2].cols[1].text, 2, 'my own rank')
eq(#find(window, 'groupTable').rows, 1, 'group rows')

-- ---------------------------------------------------------------- the status of the queue and the level veil
eq(find(window, 'queueStatus').text, 'Open', 'status of an open queue')
eq(card(5):getChildById('lock').visible, true, 'a level 800 dungeon is veiled for a level 600 character')
eq(card(5):getChildById('lock'):getChildById('lockText').text, 'Needs level 800', 'the veil text')
eq(card(4):getChildById('lock').visible, false, 'a level 600 dungeon is open')
eq(card(1):getChildById('lock').visible, false, 'a level 150 dungeon is open')

-- ---------------------------------------------------------------- a click on a card
eq(click(card(3)), true, 'a left click is taken')
eq(card(3).checked, true, 'the card is chosen')
eq(card(1).checked, false, 'the old card is not')
eq(find(window, 'bannerTitle').text, 'Forbidden Chevalier', 'the header follows')
eq(find(window, 'reqGold').text, ' Gold: 100000 ', 'gold chip')
eq(find(window, 'reqGold').tooltip, '100.000', 'gold tooltip')
eq(find(window, 'quests').text, 'Quests: Q one, Q two.', 'quests line')
eq(find(window, 'quests').visible, true, 'quests show')
eq(find(window, 'items').visible, true, 'items show')
eq(find(window, 'items'):getChildByIndex(1).itemId, 100, 'required item')
eq(find(window, 'items'):getChildByIndex(1).itemCount, 3, 'required item count')
eq(find(window, 'chipBest').visible, false, 'no best chip on difficulty 1')
eq(diffs:getChildByIndex(1).focused, true, 'a new dungeon lights Normal')
eq(diffs:getChildByIndex(3).focused, false, 'and puts the old tile out')
eq(card(3).onMouseRelease(card(3), {}, MouseRightButton), false, 'a right click is not taken')
eq(click(card(5)), true, 'a veiled card can still be looked at')
eq(find(window, 'queueStatus').text, 'Needs level 800', 'the status says what is missing')
eq(find(window, 'queueStatus').color, '#e03a1e', 'in red')
eq(find(window, 'chipLevel').color, '#e03a1e', 'the level chip turns red')
for i = 2, 6 do eq(diffs:getChildByIndex(i).enabled, true, 'vault tile ' .. i) end
eq(diffs:getChildByIndex(6).focused, true, 'the Vault lights Hell')
-- the Weekly Challenge: difficulty 2-6 locked whatever the progress
click(card(10))
for i = 2, 6 do eq(diffs:getChildByIndex(i).enabled, false, 'weekly tile ' .. i) end
eq(diffs:getChildByIndex(1).focused, true, 'the weekly lights Normal')
eq(find(window, 'banner').image, '/images/dungeons/MarrowCrypts', 'the weekly header art')
eq(find(window, 'challenges').kids[1].text, 'Weekly Challenge 2026-W46: Marrow Crypts', 'the weekly line')
flush()

-- ---------------------------------------------------------------- the filter chips
local weeklyChip = find(window, 'filter_weekly')
eq(weeklyChip ~= nil, true, 'a Weekly chip')
weeklyChip.onClick()
eq(groupsOnRail(), 'Weekly=10', 'the Weekly filter leaves one group')
eq(card(10).checked, true, 'the chosen weekly card stays chosen')
find(window, 'filter_high').onClick()
eq(groupsOnRail(), 'Levels 1000+=6,7,8,9', 'the high band')
eq(find(window, 'bannerTitle').text, 'The Marrow Crypts', 'the first card of the band is chosen')
eq(card(6).checked, true, 'and shows as chosen')
eq(find(window, 'filter_high').checked, true, 'the chip shows the filter')
eq(find(window, 'filter_all').checked, false, 'All is not')
find(window, 'filter_all').onClick()
eq(#rail.kids, 4, 'All brings every group back')
eq(card(6).checked, true, 'the chosen card is kept')

-- ---------------------------------------------------------------- the queue
playerLevel = 1500
onPlayerLevelChange()
opcode('queueUpdate', { id = 6, queue = 3, estimated = 120000 })
eq(card(6):getChildById('queue').text, 'Queue: 3 Players', 'a queue update reaches the card')
eq(card(6):getChildById('queue').color, 'orange', 'in orange')
eq(find(window, 'queueStatus').text, '3 Players', 'and the status of the chosen dungeon')
eq(find(window, 'queueTime').text, '00:02:00', 'and its estimated time')
eq(find(window, 'chipQueue').text, ' Queue: 3 Players ', 'and the header chip')
opcode('queueUpdate', { id = 99, queue = 1, estimated = 1 })   -- a dungeon the window does not know
eq(#logged, 0, 'an unknown dungeon is no error')
flush()
sent = {}
joinQueue()
eq(sent[1].buffer, 'json:queue:6:1', 'Join asks for the chosen dungeon at the lit difficulty')
opcode('queue', { id = 6, joined = true })
eq(find(window, 'queueButton').text, 'Leave', 'the button says Leave')
eq(find(window, 'queueDungeon').text, 'The Marrow Crypts', 'the dungeon waited for')
flush(3)
eq(find(window, 'queueWaiting').text ~= '00:00:00', true, 'the waiting time runs')
opcode('stopQueue')
eq(find(window, 'queueButton').text, 'Join', 'the button says Join again')
eq(find(window, 'queueDungeon').text, '------', 'nothing waited for')
eq(find(window, 'queueWaiting').text, '00:00:00', 'the clock is reset')

-- ---------------------------------------------------------------- a better difficulty, the level, the tabs
opcode('difficulty', { id = 6, difficulty = 2 })
eq(card(6):getChildById('best').text, ' Best: Hard ', 'a new difficulty shows on the card')
eq(find(window, 'chipBest').visible, true, 'and on the header')
eq(find(window, 'difficulties'):getChildByIndex(2).enabled, true, 'Hard opens')
playerLevel = 900
onPlayerLevelChange()
eq(card(5):getChildById('lock').visible, false, 'a level 900 character enters the Vault')
eq(card(6):getChildById('lock').visible, true, 'but not the level 1000 dungeon')
eq(find(window, 'lootPage').visible, true, 'the loot tab shows first')
showSideTab(2)
eq(find(window, 'lootPage').visible, false, 'the ranking tab hides the loot')
eq(find(window, 'rankPage').visible, true, 'and shows the tables')
eq(find(window, 'rankTab').checked, true, 'the tab is lit')
showSideTab(1)
eq(find(window, 'lootPage').visible, true, 'back to the loot')
setMobilePage(2)
eq(find(window, 'infoPanel').visible, true, 'the pages do nothing on a desktop')

-- ---------------------------------------------------------------- open and close
show()
eq(window.visible, true, 'show opens the window')
eq(card(6).checked, true, 'show keeps the chosen dungeon')
opcode('open')
eq(button.on, true, 'the entry tile lights the button')
toggle()
eq(window.visible, false, 'toggle closes the window')

-- ---------------------------------------------------------------- the kill counter
opcode('start', { boss = 'Ossivane', left = 120, duration = 900000, need = 85, objectives = { 'No deaths', 'Fast' } })
local counter = getKillCounter()
eq(counter.visible, true, 'the counter shows')
eq(counter:getChildById('mainObjective').text, 'Kill 85% of the monsters to unlock Ossivane', 'the main objective')
opcode('killed', { percent = 40, left = 70 })
eq(counter:getChildById('label').text, '40%', 'percent')
opcode('killed', { percent = 90, left = 12, unlocked = true })
eq(counter:getChildById('label').text, 'Boss unlocked!', 'the boss is unlocked')
opcode('objective', { id = 1, finished = true })
opcode('killed', { boss = true })
eq(counter:getChildById('bossObjective').checked, true, 'the boss is down')
opcode('finish')
eq(counter.visible, false, 'the counter hides')
opcode('challenge', 'Speed Runner')

-- ---------------------------------------------------------------- one group only: no chips; the phone
mobile = true
terminate()
button = new('topbutton', nil)
init()
local window2 = theWindow()
eq(window2 ~= nil and window2 ~= window, true, 'a new window after terminate and init')
for _, s in ipairs(specs) do
  if s[1] <= 2 then opcode('dungeon', payloads[s[1]]) end
end
opcode('list', { list[1], list[2] })
local rail2 = find(window2, 'dungeonsRail')
eq(#rail2.kids, 1, 'two low dungeons: one group')
eq(find(window2, 'filters').visible, false, 'one group: no chips')
eq(rail2.kids[1].width, 2 * (128 + 8), 'phone cards are 128 wide')
eq(find(window2, 'dungeon1'):getChildById('party').visible, false, 'no party line on a phone card')
eq(find(window2, 'infoPanel').visible, true, 'phone page 1')
eq(find(window2, 'sidePanel').visible, false, 'the pages start with page 1 (set on create)')
setMobilePage(2)
eq(find(window2, 'infoPanel').visible, false, 'phone page 2 hides the info')
eq(find(window2, 'sidePanel').visible, true, 'and shows the tabs')
eq(find(window2, 'pageLootTab').checked, true, 'the page tab is lit')
setMobilePage(1)
eq(find(window2, 'sidePanel').visible, false, 'page 1 hides the tabs')
eq(#logged, 0, 'no error logged: ' .. tostring(logged[1]))

print(n .. ' dungeons widget checks passed')
