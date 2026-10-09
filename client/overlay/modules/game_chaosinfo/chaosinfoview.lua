-- Pure helpers of the Info & Services window (no UI calls): the pages, which of their commands the server offers,
-- the text sent for a button. Tested by chaosinfoview_test.lua (luajit / lua5.3).
--
-- A page: id, title, text (what it is for), auto (commands run when the page opens; their answers fill the page),
-- rows (controls). A row: label, edit = <field id> (a text field) or combo = 'vocations' (a choice list from the
-- server), and buttons {text, id = <command id>, param = <template>} or {text, fn = <client action>}. A template
-- puts the row's field in with '$'.
ChaosInfoView = {}
local V = ChaosInfoView

V.PAGES = {
  { id = 'character', title = 'Character Info',
    text = 'Your classes, ascension, double experience and position. The buttons show more.',
    auto = { 'classes', 'ascension', 'exp', 'pos' },
    rows = {
      { buttons = { { text = 'Resistances', id = 'resis' }, { text = 'Kills', id = 'kills' },
                    { text = 'Deaths', id = 'deathlist' }, { text = 'Ancestral Tasks', id = 'ancestral' },
                    { text = 'Card Deck', id = 'deck' } } },
    } },
  { id = 'services', title = 'Services',
    text = 'Store tokens (name and vocation change), the free class switch, familiars, the tutorial and web shop items.',
    rows = {
      { label = 'New name', edit = 'name', buttons = { { text = 'Change Name', id = 'changename', param = '$' } } },
      { label = 'Class', combo = 'vocations', buttons = { { text = 'Change Vocation', id = 'changevocation', param = '$' },
                                                         { text = 'Free Switch', id = 'ascend', param = '$' } } },
      { label = 'Familiar', buttons = { { text = 'Summon', id = 'summonfamiliar' }, { text = 'Level', id = 'familiarlevel' },
                                        { text = 'Choose', id = 'choosefamiliar' } } },
      { label = 'Other', buttons = { { text = 'Leave Tutorial', id = 'skiptutorial' }, { text = 'Claim Web Shop Items', id = 'webshop' } } },
    } },
  { id = 'autoseller', title = 'Auto Seller',
    text = 'Loot on this list is sold at NPC prices as it drops; the gold goes to your bank. Uniques are never sold.',
    auto = { 'autosell' },
    rows = {
      { label = 'Item name', edit = 'item', buttons = { { text = 'Add', id = 'autosell', param = 'add $' },
                                                       { text = 'Remove', id = 'autosell', param = 'remove $' } } },
      { label = 'Selling', buttons = { { text = 'On', id = 'autosell', param = 'on' }, { text = 'Off', id = 'autosell', param = 'off' },
                                       { text = 'Clear List', id = 'autosell', param = 'clear' } } },
      { label = 'Rarity items', buttons = { { text = 'Sell Them', id = 'autosell', param = 'rarity on' },
                                            { text = 'Keep Them', id = 'autosell', param = 'rarity off' } } },
    } },
  { id = 'house', title = 'House',
    text = 'Stand in front of a house door to buy it. Selling hands your house to another player.',
    rows = {
      { buttons = { { text = 'Buy This House', id = 'buyhouse' }, { text = 'Leave My House', id = 'leavehouse' } } },
      { label = 'Buyer', edit = 'buyer', buttons = { { text = 'Sell House', id = 'sellhouse', param = '$' } } },
    } },
  { id = 'rift', title = 'Rift Keys',
    text = 'The rift you are in and every Rift Key you carry, with its modifiers. Use a key to open its rift.',
    auto = { 'rift' } },
  { id = 'events', title = 'Events',
    text = 'Server events running today, world buffs and the world boss.',
    auto = { 'events', 'worldbuffs', 'worldboss' },
    rows = {
      { buttons = { { text = 'Event Calendar', fn = 'calendar' }, { text = 'Upcoming Invasions', fn = 'invasions' } } },
    } },
  { id = 'ancestral', title = 'Ancestral Store',
    text = 'Spend your Ancestral Points (from the task NPCs).',
    store = true,
    rows = {
      { label = 'Item', combo = 'store', buttons = { { text = 'Buy', id = 'ancestralstore', param = '$' } } },
    } },
  { id = 'server', title = 'Server Info',
    text = 'Rates, uptime and who is online.',
    auto = { 'serverinfo', 'uptime', 'online' } },
}

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

-- the store entries -> choice list
function V.storeOptions(store)
  local out = {}
  for _, e in ipairs(type(store) == 'table' and store or {}) do
    if type(e.param) == 'string' and type(e.label) == 'string' then
      out[#out + 1] = { text = e.label, value = e.param }
    end
  end
  return out
end

-- the result parts of the server -> the page text (parts in the order asked)
function V.resultText(parts)
  local out = {}
  for _, p in ipairs(type(parts) == 'table' and parts or {}) do
    if type(p.text) == 'string' and p.text ~= '' then out[#out + 1] = p.text end
  end
  return table.concat(out, '\n\n')
end

return V
