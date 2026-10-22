-- Pure helpers of the Info & Services window (no UI calls): the pages, which of their commands the server offers,
-- the text sent for a button, how a row's buttons wrap, which buttons the Services state allows, the Ancestral Store
-- rows. Tested by chaosinfoview_test.lua (luajit / lua5.3).
--
-- A page: id, title, text (what it is for), auto (commands run when the page opens; their answers fill the page),
-- headings (command id -> a heading over its answer), idle (the text shown before any answer), ids (more command ids
-- that make the page offered), state ('services': the page asks the server its state and enables its buttons by it),
-- store (the Ancestral Store list instead of the text box), rows (controls). A row: label, hint (its tooltip),
-- edit = <field id> (a text field) or combo = 'vocations' / 'frames' (a choice list from the server), and buttons
-- {text, id = <command id>, param = <template>, hint, need = <state field>, why = <tooltip while disabled>} or
-- {text, fn = <client action>}. A template puts the row's field in with '$'. Every text here goes through tr() where it
-- is shown (pt-BR: client_chaos_locale/pt_br.lua, "Run-time keys").
ChaosInfoView = {}
local V = ChaosInfoView

V.PAGES = {
  { id = 'character', title = 'Character Info',
    text = 'Your classes, ascension, double experience, position and the item sets you wear. The buttons show more.',
    auto = { 'classes', 'ascension', 'exp', 'pos', 'sets' },
    headings = { classes = 'Classes', ascension = 'Ascension', exp = 'Double EXP', pos = 'Position', sets = 'Item Sets',
                 resis = 'Resistances', kills = 'Kills', deathlist = 'Deaths', ancestral = 'Ancestral Tasks',
                 deck = 'Card Deck' },
    rows = {
      { buttons = { { text = 'Resistances', id = 'resis', hint = 'Your elemental resistances.' },
                    { text = 'Kills', id = 'kills', hint = 'Your player kills.' },
                    { text = 'Deaths', id = 'deathlist', hint = 'Your last deaths.' },
                    { text = 'Ancestral Tasks', id = 'ancestral', hint = 'Your task rank, points and current tasks.' },
                    { text = 'Card Deck', id = 'deck', hint = 'The cards of your deck.' },
                    { text = 'Item Sets', id = 'sets', hint = 'The item sets you wear and their bonuses.' } } },
    } },
  { id = 'services', title = 'Services',
    text = 'Store tokens (name and vocation change), the free class switch, familiars, the tutorial and web shop items.',
    state = 'services',
    rows = {
      { label = 'New name', edit = 'name', hint = 'Type the new name. You are logged out to apply it.',
        buttons = { { text = 'Change Name', id = 'changename', param = '$', need = 'nameTokens',
                      hint = 'Uses one Name Change token.', why = 'You have no Name Change token. Buy one in the store.' } } },
      { label = 'Class', combo = 'vocations', hint = 'The class to change to.',
        buttons = { { text = 'Change Vocation', id = 'changevocation', param = '$', need = 'vocationTokens',
                      hint = 'Uses one Vocation Change token.',
                      why = 'You have no Vocation Change token. Buy one in the store.' },
                    { text = 'Free Switch', id = 'ascend', param = '$', need = 'freeSwitch',
                      hint = 'Your one free switch to the other class of your line.',
                      why = 'You have no free switch.' } } },
      { label = 'Familiar', hint = 'Familiars answer from level 200.',
        buttons = { { text = 'Summon', id = 'summonfamiliar', need = 'familiarReady', hint = 'Summon your familiar.',
                      why = 'Familiars need level 200.' },
                    { text = 'Level', id = 'familiarlevel', need = 'familiarReady', hint = "Your familiar's level.",
                      why = 'Familiars need level 200.' },
                    { text = 'Choose', id = 'choosefamiliar', hint = 'Choose your familiar.' } } },
      { label = 'Other', hint = 'The tutorial, boss rooms and the web shop.',
        buttons = { { text = 'Leave Tutorial', id = 'skiptutorial', need = 'inTutorial',
                      hint = 'Leave the tutorial island now.', why = 'You are not in the tutorial.' },
                    -- server instance_limits.lua ChaosBossRooms.leave: out to the room's exit, not in a fight
                    { text = 'Leave Boss Room', id = 'leaveroom', need = 'inBossRoom',
                      hint = 'Leave the boss room you are in, out to its exit. Not while you are in a fight.',
                      why = 'You are not in a boss room.' },
                    { text = 'Claim Web Shop Items', id = 'webshop', need = 'webshopOrders',
                      hint = 'Collect what you bought on the website.', why = 'Nothing to claim.' } } },
      -- name plate frames from the store and the exclusives (server shop.lua, command id plateframe): a list of the
      -- character's own frames (the Services state)
      { label = 'Plate frame', combo = 'frames', hint = 'The frame around your name plate.',
        buttons = { { text = 'Use Frame', id = 'plateframe', param = '$', need = 'frames',
                      hint = 'Show the chosen frame.', why = 'You own no frame. Store > Name Plates.' },
                    { text = 'My Frames', id = 'plateframe', param = 'list', hint = 'List the frames you own.' },
                    { text = 'Title Frame', id = 'plateframe', param = 'off', need = 'activeFrame',
                      hint = "Go back to your title's own frame.", why = "Your title's own frame is shown already." } } },
    } },
  { id = 'house', title = 'House',
    text = 'Stand in front of a house door to buy it. Selling hands your house to another player.',
    idle = 'Stand in front of a house door and press Buy This House. The answer shows here.',
    rows = {
      { buttons = { { text = 'Buy This House', id = 'buyhouse', hint = 'Buy the house whose door you face.' },
                    { text = 'Leave My House', id = 'leavehouse', hint = 'Give up your house.' } } },
      { label = 'Buyer', edit = 'buyer', hint = 'The character that gets your house.',
        buttons = { { text = 'Sell House', id = 'sellhouse', param = '$', hint = 'Hand your house to this character.' } } },
    } },
  { id = 'rift', title = 'Rift Keys',
    text = 'The rift you are in and every Rift Key you carry, with its modifiers. Use a key to open its rift.',
    auto = { 'rift' } },
  { id = 'events', title = 'Events',
    text = 'Server events running today, world buffs and the world boss.',
    auto = { 'events', 'worldbuffs', 'worldboss' },
    headings = { events = 'Events today', worldbuffs = 'World buffs', worldboss = 'World boss' },
    rows = {
      { buttons = { { text = 'Event Calendar', fn = 'calendar' }, { text = 'Upcoming Invasions', fn = 'invasions' } } },
    } },
  { id = 'ancestral', title = 'Ancestral Store',
    text = 'Spend your Ancestral Points (from the task NPCs).',
    store = true, ids = { 'ancestralstore' } },
  { id = 'server', title = 'Server Info',
    text = 'Rates, uptime and who is online.',
    auto = { 'serverinfo', 'uptime', 'online' } },
}

V.IDLE = 'Press a button above. The answer shows here.'

function V.page(id)
  for _, p in ipairs(V.PAGES) do
    if p.id == id then return p end
  end
  return nil
end

-- set of command ids from the server's catalog list
function V.idSet(list)
  local set = {}
  for _, id in ipairs(type(list) == 'table' and list or {}) do
    if type(id) == 'string' then set[id] = true end
  end
  return set
end

-- the auto commands of a page the server offers
function V.autoIds(page, set)
  local out = {}
  for _, id in ipairs(page and page.auto or {}) do
    if set[id] then out[#out + 1] = id end
  end
  return out
end

-- a button is shown when the server offers its command (client actions always)
function V.buttonShown(button, set)
  return button.fn ~= nil or (button.id ~= nil and set[button.id] == true)
end

-- a page is shown when the server offers at least one of its commands
function V.pageShown(page, set)
  if not page then return false end
  for _, id in ipairs(page.auto or {}) do
    if set[id] then return true end
  end
  for _, id in ipairs(page.ids or {}) do
    if set[id] then return true end
  end
  for _, row in ipairs(page.rows or {}) do
    for _, b in ipairs(row.buttons or {}) do
      if b.id and set[b.id] then return true end
    end
  end
  return false
end

-- the param sent for a button: its template with '$' replaced by the field's text (trimmed); nil when the template
-- needs the field and it is empty
function V.param(template, field)
  if not template then return '' end
  if not template:find('%$') then return template end
  local value = tostring(field or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if value == '' then return nil end
  return (template:gsub('%$', function() return value end))
end

-- "warrior|juggernaut" -> {"Warrior", "Juggernaut"} (choice list), values in lower case
function V.vocationOptions(words)
  local out = {}
  for w in tostring(words or ''):gmatch('[^|]+') do
    out[#out + 1] = { text = w:sub(1, 1):upper() .. w:sub(2), value = w:lower() }
  end
  return out
end

-- the owned frames of the Services state -> choice list ("frost" -> "Frost")
function V.frameOptions(frames)
  local out = {}
  for _, f in ipairs(type(frames) == 'table' and frames or {}) do
    if type(f) == 'string' and f ~= '' then
      out[#out + 1] = { text = f:sub(1, 1):upper() .. f:sub(2), value = f }
    end
  end
  return out
end

-- Is the state field a button needs met? No state yet (or no need): yes. A number > 0 (-1 = unknown: yes), a
-- non-empty string, a non-empty list, true.
function V.needMet(need, state)
  if not need or type(state) ~= 'table' then return true end
  local v = state[need]
  if v == nil then return true end
  if type(v) == 'number' then return v > 0 or v == -1 end
  if type(v) == 'string' then return v ~= '' end
  if type(v) == 'table' then return #v > 0 end
  return v == true
end

-- How a row's buttons wrap so none sticks out: `first` = width already used on the first line (label, field),
-- widths = the buttons' widths, avail = the row's width, indent = where the next lines start (under the field),
-- spacing = the gap between controls. Returns the lines as lists of button indices. A button wider than a line gets a
-- line of its own.
function V.wrapRow(first, widths, avail, indent, spacing)
  local lines, line = {}, {}
  local used = first or 0
  for i, w in ipairs(widths) do
    local start = (used > 0) and (used + spacing) or used
    if #line > 0 and start + w > avail then
      lines[#lines + 1] = line
      line = {}
      used = indent or 0
      start = (used > 0) and (used + spacing) or used
    elseif #line == 0 and #lines == 0 and used > 0 and start + w > avail then
      -- the first button does not fit next to the label and field: it starts the second line
      lines[#lines + 1] = line
      line = {}
      used = indent or 0
      start = (used > 0) and (used + spacing) or used
    end
    line[#line + 1] = i
    used = start + w
  end
  lines[#lines + 1] = line
  return lines
end

-- the Ancestral Store answer -> rows {id, kind, name, item, price, afford, missing}, sorted by kind then price;
-- entries with a bad field are left out
function V.storeRows(data)
  local out = {}
  local points = type(data) == 'table' and tonumber(data.points) or 0
  points = points or 0
  for _, e in ipairs(type(data) == 'table' and type(data.entries) == 'table' and data.entries or {}) do
    local price, id = tonumber(e.price), tonumber(e.id)
    if type(e) == 'table' and price and id and type(e.name) == 'string' then
      out[#out + 1] = { id = id, kind = type(e.kind) == 'string' and e.kind or 'Other', name = e.name,
        item = tonumber(e.item) or 0, price = price, afford = points >= price,
        missing = math.max(0, price - points) }
    end
  end
  table.sort(out, function(a, b)
    if a.kind ~= b.kind then return a.kind < b.kind end
    if a.price ~= b.price then return a.price < b.price end
    return a.id < b.id
  end)
  return out, points
end

-- the result parts of the server -> the page text (parts in the order asked). headings: id -> heading text;
-- translate(text) -> the heading in the player's language
function V.resultText(parts, headings, translate)
  local out = {}
  for _, p in ipairs(type(parts) == 'table' and parts or {}) do
    if type(p.text) == 'string' and p.text ~= '' then
      local h = headings and headings[p.id]
      if h then
        out[#out + 1] = '[ ' .. (translate and translate(h) or h) .. ' ]\n' .. p.text
      else
        out[#out + 1] = p.text
      end
    end
  end
  return table.concat(out, '\n\n')
end

return V
