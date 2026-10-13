-- The "Create character" window of the character select. Name, class (the class lock: the Monk, the Necromancer and
-- the Templar only for an account that unlocked them), sex with a preview of the class's look, and an optional season
-- (the running one, with its modes; Hardcore needs "I understand"). The website creates the character with its own
-- checks (website/README.md "Client API"); the character list is then read again from the login server.

CharCreate = {}
local Core = CharSelectCore
local Api = ChaosAccountApi

local win, shade
local form = {}
local choices, seasons = {}, {}
local rules = { minL = 3, maxL = 20, maxW = 3 }
local stateNow

local STARTER = { head = 78, body = 68, legs = 58, feet = 76 } -- the website's starter colours (ZnoteX's defaults)

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function theme()
  return modules.client_chaos_theme and modules.client_chaos_theme.ChaosTheme
end

local function setStatus(text, bad)
  if not alive(win) then return end
  win.status:setText(text or '')
  win.status:setColor(bad and '#e03a1e' or '#d6c9ae')
end

local function chosenClass()
  for _, c in ipairs(choices) do
    if c.id == form.vocation then return c end
  end
end

local function chosenSeason()
  return seasons[form.seasonIndex or 1] or seasons[1]
end

local CREATE_TEXT_ROOM = 26   -- px under the platform for the class name

local function updatePreview()
  if not alive(win) then return end
  local c = chosenClass()
  local look = c and (form.sex == 0 and c.female or c.male) or 0
  local p = win.previewPanel.preview
  if look and look > 0 then
    p:setVisible(true)
    p:setOutfit({ type = look, head = STARTER.head, body = STARTER.body, legs = STARTER.legs, feet = STARTER.feet, addons = 3 })
    -- the feet on the platform's centre (CharSelectCore.placeRect; outfit_anchors.lua): 3x, 2x for a very tall
    -- look; the platform reaches below the feet (top-down view), the class name under it
    local panel = win.previewPanel
    local cx = math.floor(panel:getWidth() / 2)
    local fig = Core.figure(CharSelectAnchors, { type = look })
    local T, feet
    for _, sc in ipairs({ 3, 2 }) do
      T, feet = sc * 32, panel:getHeight() - CREATE_TEXT_ROOM - Core.platformBelow(sc * 32)
      if Core.fitsAt(fig, { above = feet - 6, half = cx - 2 }, sc) then break end
    end
    local x, y, size = Core.placeRect(fig, T, cx, feet)
    local function place(w, px, py, pw, ph)
      w:breakAnchors()
      w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      w:addAnchor(AnchorTop, 'parent', AnchorTop)
      w:setMarginLeft(px)
      w:setMarginTop(py)
      w:setSize({ width = pw, height = ph })
    end
    place(panel.pedestal, Core.platformRect(T, cx, feet))
    place(p, x, y, size, size)
    p:setDirection(2)
    p:setIdleAnimate(false)
    p:setAnimate(true)
    win.previewPanel.previewText:setText(c.name)
  else
    p:setVisible(false)
    win.previewPanel.previewText:setText(c and c.name or tr('Choose a class'))
  end
end

local function updateControls()
  if not alive(win) then return end
  local c = chosenClass()
  if c then
    win.classText:setText(c.locked and (c.name .. ': ' .. tr('locked for this account. Unlock it in the game store (Classes).'))
      or (c.name .. ': ' .. (c.plays ~= '' and c.plays or tr('a base class. You choose its ascension at level 100.'))))
    win.classText:setColor(c.locked and '#e03a1e' or '#d6c9ae')
  else
    win.classText:setText(tr('Choose a class.'))
    win.classText:setColor('#8c8070')
  end
  for _, b in ipairs(win.classes:getChildren()) do
    b:setChecked(b.classId == form.vocation)
  end
  win.male:setChecked(form.sex == 1)
  win.female:setChecked(form.sex == 0)
  local s = chosenSeason()
  win.seasonWarning:setText(s and s.warning or '')
  win.hardcore:setVisible(s ~= nil and s.hc)
  local hint = Core.checkName(win.nameEdit:getText(), rules)
  win.nameHint:setText(hint or tr('%d to %d letters, up to %d words.', rules.minL, rules.maxL, rules.maxW))
  win.nameHint:setColor(hint and win.nameEdit:getText() ~= '' and '#e03a1e' or '#8c8070')
  local terms = not (stateNow and stateNow.account and stateNow.account.terms == false)
  win.termsButton:setVisible(not terms)
  win.createButton:setEnabled(Api.enabled() and stateNow ~= nil and terms and c ~= nil and not c.locked)
  updatePreview()
end

local function fill(state)
  if not alive(win) then return end
  stateNow = state
  local acc = state and state.account or {}
  if type(acc.rules) == 'table' then
    rules = { minL = tonumber(acc.rules.minL) or 3, maxL = tonumber(acc.rules.maxL) or 20, maxW = tonumber(acc.rules.maxW) or 3 }
    win.nameEdit:setMaxLength(rules.maxL)
  end
  choices = Core.classChoices(state)
  for _, c in ipairs(choices) do
    for _, a in ipairs(acc.classes or {}) do
      if tonumber(a.id) == c.id then
        c.male, c.female = tonumber(a.male) or 0, tonumber(a.female) or 0
      end
    end
  end
  win.classes:destroyChildren()
  for _, c in ipairs(choices) do
    local b = g_ui.createWidget('ChaosCreateClass', win.classes)
    b.classId = c.id
    b.icon:setImageSource(c.icon)
    if c.locked then
      b.icon:setImageColor('#ffffff55')
      b:setTooltip(c.name .. ': ' .. tr('locked for this account. Unlock it in the game store (Classes).'))
    else
      b:setTooltip(c.name .. (c.plays ~= '' and (': ' .. c.plays) or ''))
    end
    b.onClick = function()
      form.vocation = c.id
      updateControls()
    end
  end
  if not chosenClass() then
    for _, c in ipairs(choices) do
      if not c.locked then form.vocation = c.id break end
    end
  end
  seasons = Core.seasonChoices(state)
  win.season:clearOptions()
  for i, s in ipairs(seasons) do win.season:addOption(s.label, i) end
  form.seasonIndex = 1
  win.season:setCurrentIndex(1)
  local slots = acc.slots
  if type(slots) == 'table' and tonumber(slots.limit) then
    setStatus(Core.slotsLine(slots))
  else
    setStatus('')
  end
  if acc.terms == false then
    setStatus(tr('Accept the current Terms of Use on the website first, then come back.'), true)
  end
  updateControls()
end

function CharCreate.isOpen()
  return alive(win)
end

function CharCreate.open()
  if alive(win) then
    win:raise()
    win:focus()
    return
  end
  if not alive(shade) then shade = g_ui.createWidget('ChaosCreateShade', g_ui.getRootWidget()) end
  shade:raise()
  win = g_ui.createWidget('ChaosCreateWindow', g_ui.getRootWidget())
  local th = theme()
  if th and th.decorateWindow then pcall(th.decorateWindow, win) end
  form = { name = '', vocation = nil, sex = 1, seasonIndex = 1, hardcore = false }
  win.male.onClick = function() form.sex = 1 updateControls() end
  win.female.onClick = function() form.sex = 0 updateControls() end
  win.nameEdit.onTextChange = function() updateControls() end
  win.season.onOptionChange = function(_, _, data)
    form.seasonIndex = tonumber(data) or 1
    form.hardcore = false
    win.hardcore:setChecked(false)
    updateControls()
  end
  win.hardcore.onCheckChange = function(_, checked) form.hardcore = checked end
  win.termsButton.onClick = function()
    local url = stateNow and stateNow.account and stateNow.account.termsUrl
    if url and g_platform and g_platform.openUrl then g_platform.openUrl(url) end
  end
  win.createButton.onClick = CharCreate.submit
  win.cancelButton.onClick = CharCreate.close
  win.onEscape = CharCreate.close
  g_keyboard.bindKeyPress('Enter', CharCreate.submit, win)
  g_client.setInputLockWidget(win)
  win:show()
  win:raise()
  win:focus()
  win.nameEdit:focus()
  fill(Api.state())
  if not Api.enabled() then
    setStatus(tr('Character creation in the client is not set up. Create characters on the website.'), true)
    return
  end
  setStatus(tr('Reading your account from the website...'))
  Api.refresh(function(state, err)
    if not alive(win) then return end
    if state then
      fill(state)
    else
      setStatus(err, true)
    end
  end)
end

function CharCreate.submit()
  if not alive(win) or not win.createButton:isEnabled() then return end
  form.name = win.nameEdit:getText()
  local hint = Core.checkName(form.name, rules)
  if hint then setStatus(hint, true) return end
  local c = chosenClass()
  if not c then setStatus(tr('Choose a class.'), true) return end
  local s = chosenSeason()
  if s and s.hc and not form.hardcore then
    setStatus(tr('Hardcore has one life: tick "I understand" to choose it.'), true)
    return
  end
  win.createButton:setEnabled(false)
  setStatus(tr('Creating your character...'))
  Api.create({ name = form.name, vocation = c.id, sex = form.sex, season = s and s.season or 0, mode = s and s.mode or '',
    hardcore = form.hardcore }, function(ok, text, body)
    if not alive(win) then return end
    if ok then
      setStatus(text)
      local name = body and body.name or form.name
      scheduleEvent(function()
        CharCreate.close()
        if CharSelect and CharSelect.afterCreate then CharSelect.afterCreate(name) end
      end, 900)
    else
      setStatus(text, true)
      if body and body.error == 'terms' then
        stateNow = stateNow or { account = {} }
        stateNow.account = stateNow.account or {}
        stateNow.account.terms = false
        stateNow.account.termsUrl = body.url or stateNow.account.termsUrl
      end
      updateControls()
      win.createButton:setEnabled(body == nil or body.error ~= 'terms')
    end
  end)
end

function CharCreate.close()
  if alive(win) then
    win:destroy()
  end
  if alive(shade) then
    shade:destroy()
  end
  win, shade = nil, nil
  if CharSelect and CharSelect.restoreFocus then CharSelect.restoreFocus() end
end
