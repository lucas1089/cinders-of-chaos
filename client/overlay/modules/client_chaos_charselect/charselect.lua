-- Cinders of Chaos character select (client/MANIFEST.md "Character select").
--
-- The stock character list (client_entergame/characterlist.lua) stays loaded and keeps every function: the login
-- queue, the error boxes, auto reconnect, the sort and pins, the account status, Cancel, logging a character in. This
-- module only changes what the player sees and touches while the list is open before the game:
--   * the stock window is hidden; a full-screen screen shows instead, over the login scene (client_background with
--     client_chaos_login's living scene: the same background as the login screen);
--   * one card per character, in the stock list's order (pins and sort kept): class badge, name, class and ascension,
--     level, world, last login, season tag; click selects, double-click plays, the arrow keys / Home / End / Page keys
--     choose, Enter plays, Escape goes back. The stock list's focus follows the cards, so CharacterList.doLogin()
--     logs in the chosen character exactly as before;
--   * the chosen character large (3 to 4 times) with its real outfit: look type, colours and addons from the login
--     server's list (base patch 0025), wings, aura and shader from the website (accountapi.lua); it walks in place for
--     a moment when chosen, then idles; a click on it turns it;
--   * the footer: account status, "Show hidden characters" (always on, as in the stock window), "Record session",
--     auto reconnect, Create character (charcreate.lua), Back (the stock Cancel) and Play.
-- In the game (the list opened to switch characters) the stock window shows as before.

CharSelect = {}
local Core = CharSelectCore
local Api = ChaosAccountApi

local screen, stage, preview, pedestal, area
local cards = {}           -- { widget, model, row (the stock list's row) }
local selected = 0
local orig = {}
local walkEvent
local direction = 2        -- Otc South
local CLOCKWISE = { [2] = 3, [3] = 0, [0] = 1, [1] = 2 }

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function theme()
  return modules.client_chaos_theme and modules.client_chaos_theme.ChaosTheme
end

local function stockWindow()
  local w = g_ui.getRootWidget():getChildById('charactersWindow')
  return alive(w) and w or nil
end

local function stockList()
  local w = stockWindow()
  return w and w:getChildById('characters') or nil
end

-- the new screen is for the list before the game; in the game (switching characters) the stock window stays
local function wanted()
  return not g_game.isOnline() and g_settings.getString('chaosCharSelect') ~= 'stock'
end

local function place(w, x, y, wd, ht)
  w:breakAnchors()
  w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  w:addAnchor(AnchorTop, 'parent', AnchorTop)
  w:setMarginLeft(math.floor(x))
  w:setMarginTop(math.floor(y))
  if wd then w:setSize({ width = math.floor(wd), height = math.floor(ht) }) end
end

local function characterByName(name)
  for _, c in ipairs(G.characters or {}) do
    if c.name == name then return c end
  end
end

local function worldFallback()
  local allowed = Core.allowedWorlds(Servers)
  return (G and type(G.server) == 'string' and G.server ~= '' and G.server) or allowed[1] or 'Cinders of Chaos'
end

-- ---------------------------------------------------------------- the big character
local function stopWalk()
  if walkEvent then removeEvent(walkEvent) end
  walkEvent = nil
end

local function idle()
  stopWalk()
  if alive(preview) then
    preview:setAnimate(false)
    preview:setIdleAnimate(true)
  end
end

local function walk(ms)
  stopWalk()
  if not alive(preview) then return end
  preview:setIdleAnimate(false)
  preview:setAnimate(true)
  walkEvent = scheduleEvent(idle, ms or 2400)
end

-- the client's size and displacement of a creature thing (for a look outfit_anchors.lua does not know)
local function thingInfo(id)
  local ok, t = pcall(function() return g_things.getThingType(id, ThingCategoryCreature) end)
  if not ok or not t then return nil end
  local function get(m) local okm, v = pcall(t[m], t) return okm and v or nil end
  return { w = get('getWidth'), h = get('getHeight'), dx = get('getDisplacementX'), dy = get('getDisplacementY') }
end

local TOP_ROOM = 56        -- px kept free at the top of the stage (the top menu's System button)
local BELOW_ROOM = 150     -- px under the feet for the name, class and info lines and the hint
local heroFigure           -- CharSelectCore.figure of the shown outfit

-- the feet of the shown character on the pedestal's centre: the look's own feet (outfit_anchors.lua), 4x when the
-- whole picture (wings and aura too) fits under the top menu, else 3x, else 3x with the feet lower
local function relayout()
  if not alive(stage) then return end
  local W, H = stage:getWidth(), stage:getHeight()
  if W < 50 or H < 50 then return end
  local cx = math.floor(W / 2)
  local feet = math.floor(math.min(H * 0.64, H - BELOW_ROOM))
  local fig = heroFigure or Core.figure(CharSelectAnchors, { type = 128 })
  local T, _, drop = Core.fitPreview(fig, { above = feet - TOP_ROOM, half = cx - 8,
    below = math.max(0, H - BELOW_ROOM - feet) })
  feet = feet + drop
  local x, y, size = Core.placeRect(fig, T, cx, feet)
  place(preview, x, y, size, size)
  place(pedestal, cx - 1.1 * T, feet - 0.43 * T, 2.2 * T, 0.86 * T)
  local name = stage:getChildById('heroName')
  name:breakAnchors()
  name:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  name:addAnchor(AnchorTop, 'parent', AnchorTop)
  name:setMarginTop(math.floor(feet + 0.45 * T))
end

local function showHero(m, animate)
  local name, cls, info = stage:getChildById('heroName'), stage:getChildById('heroClass'), stage:getChildById('heroInfo')
  if not m then
    heroFigure = nil
    preview:setVisible(false)
    pedestal:setVisible(false)
    name:setText(tr('No character yet'))
    cls:setText(tr('Create one with the button below.'))
    info:setText('')
    return
  end
  pedestal:setVisible(true)
  preview:setVisible(m.outfit ~= nil)
  heroFigure = Core.figure(CharSelectAnchors, m.outfit, thingInfo)
  if m.outfit then
    preview:setOutfit(m.outfit)
    preview:setDirection(direction)
  end
  relayout()
  name:setText(m.name)
  cls:setText(m.classText .. (m.levelText ~= '' and (', ' .. m.levelText) or ''))
  local parts = { m.world }
  if m.season ~= '' then parts[#parts + 1] = m.season end
  if m.lastLogin ~= '' then parts[#parts + 1] = m.lastLogin end
  info:setText(table.concat(parts, '   '))
  if animate then walk() else idle() end
end

-- ---------------------------------------------------------------- the cards
function CharSelect.select(i, quiet)
  if not alive(screen) then return end
  if i < 1 or i > #cards then
    selected = 0
    showHero(nil)
    return
  end
  local changed = i ~= selected
  selected = i
  for j, c in ipairs(cards) do c.widget:setChecked(j == i) end
  local c = cards[i]
  area:ensureChildVisible(c.widget)
  local list = stockList()
  if list and alive(c.row) and list:getFocusedChild() ~= c.row then
    list:focusChild(c.row, KeyboardFocusReason)
  end
  if changed or quiet then showHero(c.model, changed and not quiet) end
end

local function rebuild()
  if not alive(screen) then return end
  local list = stockList()
  local rows, chars = {}, {}
  for _, row in ipairs(list and list:getChildren() or {}) do
    local ch = characterByName(row.characterName)
    if ch then
      rows[#rows + 1] = row
      chars[#chars + 1] = ch
    end
  end
  local st = Api.state()
  local models = Core.cards(chars, st and st.looks, os.time(), { allowed = Core.allowedWorlds(Servers), fallback = worldFallback() })
  area:destroyChildren()
  cards = {}
  local th = theme()
  for i, m in ipairs(models) do
    local w = g_ui.createWidget('ChaosCharCard', area)
    w.icon:setImageSource(m.icon)
    w.name:setText(m.name)
    if th and th.applyFont then th.applyFont(w.name, 'heading') end
    w.line:setText(m.classText .. (m.levelText ~= '' and (', ' .. m.levelText) or ''))
    w.sub:setText(m.world .. (m.lastShort ~= '' and (', ' .. m.lastShort) or ''))
    w.season:setText(m.season)
    w.onClick = function() CharSelect.select(i) return true end
    w.onDoubleClick = function()
      CharSelect.select(i)
      CharSelect.play()
      return true
    end
    cards[i] = { widget = w, model = m, row = rows[i] }
  end
  local count = screen:recursiveGetChildById('count')
  local text = #cards == 1 and tr('1 character') or tr('%d characters', #cards)
  local slots = st and st.account and st.account.slots
  if type(slots) == 'table' and tonumber(slots.limit) then
    text = text .. tr(', %d of %d slots used', tonumber(slots.used) or #cards, tonumber(slots.limit))
  end
  count:setText(text)
  local focused = list and list:getFocusedChild()
  local index = #cards > 0 and 1 or 0
  for i, c in ipairs(cards) do
    if c.row == focused then index = i end
  end
  selected = 0
  CharSelect.select(index, true)
end

local function pageSize()
  return math.max(1, math.floor(area:getHeight() / 66))
end

function CharSelect.play()
  if selected < 1 or not cards[selected] then return end
  local list, row = stockList(), cards[selected].row
  if list and alive(row) then list:focusChild(row, KeyboardFocusReason) end
  CharacterList.doLogin()
end

function CharSelect.back()
  if CharCreate.isOpen() then
    CharCreate.close()
    return
  end
  CharacterList.hide(true)
end

-- ---------------------------------------------------------------- the footer
local function updateFooter()
  if not alive(screen) then return end
  local footer = screen:getChildById('footer')
  local account = G.characterAccount or {}
  local win = stockWindow()
  local stockLabel = win and win:getChildById('accountStatusLabel')
  footer.accountStatus:setText(stockLabel and stockLabel:getText() or '')
  footer.accountStatus:setOn(stockLabel and stockLabel:isOn() or false)
  local free = SubscriptionStatus and account.subStatus == SubscriptionStatus.Free and (tonumber(account.premDays) or 0) < 1
  footer.accountIcon:setImageSource(free and '/images/game/entergame/nopremium' or '/images/game/entergame/premium')
  footer.recordBox:setChecked(g_settings.getBoolean('recordSession', false))
  footer.autoReconnect:setText(tr('Auto reconnect') .. ': ' .. (g_settings.getBoolean('autoReconnect', false) and tr('On') or tr('Off')))
  local create = footer.createButton
  if Api.enabled() then
    create:setEnabled(true)
    create:setTooltip(tr('Create a new character on this account'))
  else
    create:setEnabled(false)
    create:setTooltip(tr('Character creation in the client is not set up: create characters on the website.'))
  end
end

local function loadLooks()
  updateFooter()
  if not Api.enabled() then return end
  Api.refresh(function(st, err)
    if not alive(screen) or not screen:isVisible() then return end
    if st then
      local keep = selected
      rebuild()
      if keep > 0 and keep <= #cards then CharSelect.select(keep, true) end
    else
      g_logger.info('[charselect] website looks: ' .. tostring(err))
    end
  end)
end

-- ---------------------------------------------------------------- the screen
local function ensureScreen()
  if alive(screen) then return end
  screen = g_ui.createWidget('ChaosCharSelectScreen', g_ui.getRootWidget())
  stage = screen:getChildById('stage')
  preview = stage:getChildById('preview')
  pedestal = stage:getChildById('pedestal')
  area = screen:recursiveGetChildById('cards')
  local th = theme()
  if th and th.applyFont then
    th.applyFont(screen:recursiveGetChildById('title'), 'subtitle')
    th.applyFont(stage:getChildById('heroName'), 'display')
    th.applyFont(stage:getChildById('heroClass'), 'heading')
  end
  preview.onClick = function()
    direction = CLOCKWISE[direction] or 2
    preview:setDirection(direction)
    walk(1200)
    return true
  end
  local footer = screen:getChildById('footer')
  footer.playButton.onClick = CharSelect.play
  footer.cancelButton.onClick = CharSelect.back
  footer.createButton.onClick = function() CharCreate.open() end
  footer.autoReconnect.onClick = function()
    CharacterList.toggleAutoReconnect()
    updateFooter()
  end
  footer.recordBox.onCheckChange = function(_, checked) g_settings.set('recordSession', checked) end
  for _, key in ipairs({ 'Up', 'Down', 'Left', 'Right', 'Home', 'End', 'PageUp', 'PageDown' }) do
    g_keyboard.bindKeyPress(key, function()
      if CharCreate.isOpen() then return end
      CharSelect.select(Core.move(selected, #cards, key, pageSize()))
    end, screen)
  end
  g_keyboard.bindKeyDown('Enter', function() if not CharCreate.isOpen() then CharSelect.play() end end, screen)
  g_keyboard.bindKeyDown('Escape', CharSelect.back, screen)
  connect(stage, { onGeometryChange = relayout })
end

function CharSelect.restoreFocus()
  if alive(screen) and screen:isVisible() then
    g_client.setInputLockWidget(screen)
    screen:focus()
  end
end

function CharSelect.isVisible()
  return alive(screen) and screen:isVisible()
end

-- the login screen's logo (client_chaos_login: chaosLogo with its glow, chaosSparks) would stand behind the character;
-- it is hidden while the select shows and comes back with the login screen,
-- and its server status line (top left, "Server online" / "Connecting..." while the status service has not answered)
-- (login.lua sets the status dot's visibility itself every few seconds, so those two are hidden by opacity)
local LOGO_IDS = { 'chaosLogo', 'chaosSparks' }
local STATUS_IDS = { 'chaosStatus', 'chaosStatusDot' }
local function setLogoHidden(hidden)
  local bg = modules.client_background and modules.client_background.getBackground and modules.client_background.getBackground()
  if not alive(bg) then return end
  for _, id in ipairs(LOGO_IDS) do
    local w = bg:getChildById(id)
    if alive(w) then w:setVisible(not hidden) end
  end
  for _, id in ipairs(STATUS_IDS) do
    local w = bg:getChildById(id)
    if alive(w) then w:setOpacity(hidden and 0 or 1) end
  end
end

local function onShow()
  -- a login that went past the login screen's "press any key" (a launcher, a script) leaves its splash line waiting
  local cl = modules.client_chaos_login and modules.client_chaos_login.ChaosLogin
  if cl and cl.endSplash then pcall(cl.endSplash) end
  local win = stockWindow()
  if not win or not win:isVisible() or not wanted() then
    if alive(screen) then screen:hide() end
    return
  end
  ensureScreen()
  setLogoHidden(true)
  win:hide()
  screen:show()
  screen:raise()
  screen:focus()
  g_client.setInputLockWidget(screen)
  relayout()
  rebuild()
  loadLooks()
end

local function onHide(showLogin)
  CharCreate.close()
  stopWalk()
  if alive(screen) then screen:hide() end
  setLogoHidden(false)
  if showLogin then Api.reset() end
end

-- after a creation: read the character list again from the login server, the new character chosen
function CharSelect.afterCreate(name)
  if type(name) == 'string' and name ~= '' then
    g_settings.set('last-used-character', name)
    local first = G.characters and G.characters[1]
    if first and first.worldName then g_settings.set('last-used-world', first.worldName) end
  end
  CharacterList.hide()
  EnterGame.doLogin(G.account, G.password, G.authenticatorToken, nil, G.gtoken)
end

-- ---------------------------------------------------------------- module
function init()
  if not CharacterList or not CharacterList.show then
    g_logger.warning('[charselect] the stock character list is not loaded: keeping it as it is')
    return
  end
  g_ui.importStyle('charselect')
  for _, k in ipairs({ 'create', 'show', 'hide', 'isVisible', 'destroy', 'rebuildCharactersList' }) do
    orig[k] = CharacterList[k]
  end
  CharacterList.show = function(...)
    local r = orig.show(...)
    onShow()
    return r
  end
  CharacterList.hide = function(showLogin, ...)
    onHide(showLogin)
    return orig.hide(showLogin, ...)
  end
  CharacterList.isVisible = function(...)
    return orig.isVisible(...) or CharSelect.isVisible()
  end
  CharacterList.destroy = function(...)
    onHide(true)
    return orig.destroy(...)
  end
  CharacterList.rebuildCharactersList = function(...)
    local r = orig.rebuildCharactersList(...)
    if CharSelect.isVisible() then rebuild() end
    return r
  end
  -- the list is already open (the module was reloaded)
  if stockWindow() and stockWindow():isVisible() then onShow() end
end

function terminate()
  if CharacterList then
    for k, fn in pairs(orig) do CharacterList[k] = fn end
  end
  orig = {}
  CharCreate.close()
  stopWalk()
  local win = stockWindow()
  local wasShown = CharSelect.isVisible()
  if alive(screen) then screen:destroy() end
  setLogoHidden(false)
  screen, stage, preview, pedestal, area = nil, nil, nil, nil, nil
  cards, selected = {}, 0
  if wasShown and win then
    win:show()
    g_client.setInputLockWidget(win)
  end
end
