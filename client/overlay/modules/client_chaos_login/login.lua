-- Cinders of Chaos login screen.
--
-- The stock client builds the login screen from two modules: client_background (the full-screen picture, the
-- event / boosted / cast panels) and client_entergame (the account window). This module leaves both in place
-- (their code and every function stay as they are) and restyles them at runtime:
--   * the background picture (data/images/title.png, one replaceable 1920x1080 file) is cropped to cover the
--     window, with an optional flickering glow overlay, rising embers and falling ash on top of it;
--   * the "Cinders of Chaos" wordmark smoulders: its glow image (chaos/login/logo_hot.png) breathes over the charred
--     letters (chaos/logo.png) and sparks leave the letters;
--   * the logo, a framed sign-in panel with two rune medallions, SIGN IN / CREATE ACCOUNT and OPTIONS / CREDITS /
--     EXIT GAME buttons are laid out under it; the stock fields, check boxes and buttons are moved into the panel;
--   * the server drop-down, recordings button, status and version sit in the corners;
--   * "Press any key to start" shows first and reveals the panel (skipped when auto login is on).
-- Art: client/tools/gen_login_art.py (data/images/title.png and data/images/chaos/login/).

ChaosLogin = {}

local IMG = '/images/chaos/login/'
local BG_W, BG_H = 1920, 1080          -- size of data/images/title.png
local PANEL_W, PANEL_H = 540, 180
local LOGO_W, LOGO_H = 1000, 560       -- size of data/images/chaos/logo.png (the wordmark)
local EMBER_COUNT = 30                 -- embers rising through the scene
local ASH_COUNT = 16                   -- ash flakes falling through it
local SPARK_COUNT = 12                 -- sparks rising off the burning letters
local USE_GLOW = true                  -- flicker overlay chaos/login/glow.png (made for the generated picture)
local SPLASH = true                    -- "Press any key to start" before the panel

local root, bg, enterGame
local logo, logoHot, halo, glowW, emberLayer, sparkLayer, pressW, splashW
local medL, medR, crestT, crestB
local verLabel, statusLabel, statusDot, serverCaption
local moved = {}                        -- stock widgets moved out of the window: { widget, original parent }
local embers, ashes, sparks = {}, {}, {}
local animEvent, fadeEvent
local clock = 0
local state = { splash = false }
local origShow

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

local function try(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then g_logger.warning('[chaos_login] ' .. tostring(err)) end
  return ok
end

-- ---------------------------------------------------------------- layout helpers
local function place(w, x, y, wd, ht)
  if not alive(w) then return end
  w:breakAnchors()
  w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  w:addAnchor(AnchorTop, 'parent', AnchorTop)
  w:setMarginLeft(x)
  w:setMarginTop(y)
  w:setMarginRight(0)
  w:setMarginBottom(0)
  if wd then w:setWidth(wd) end
  if ht then w:setHeight(ht) end
end

local function newWidget(class, parent, id)
  local w = g_ui.createWidget(class, parent)
  if id then w:setId(id) end
  return w
end

local function findByTooltip(parent, text)
  for _, c in ipairs(parent:getChildren()) do
    local ok, tip = pcall(function() return c:getTooltip() end)
    if ok and tip == text then return c end
  end
end

-- ---------------------------------------------------------------- background
-- cover crop of the 1920x1080 picture for any window shape: the horizon stays at the same height
local function coverClip(w, h)
  local ar = w / math.max(1, h)
  local cw, ch, cx, cy = BG_W, BG_H, 0, 0
  if ar > BG_W / BG_H then
    ch = math.floor(BG_W / ar)
    cy = math.floor((BG_H - ch) * 0.65)
  else
    cw = math.floor(BG_H * ar)
    cx = math.floor((BG_W - cw) * 0.5)
  end
  return string.format('%d %d %d %d', cx, cy, cw, ch)
end

local function relayout()
  if not alive(bg) then return end
  local w, h = bg:getWidth(), bg:getHeight()
  if w < 100 or h < 100 then return end
  local clip = coverClip(w, h)
  bg:setImageClip(clip)
  if alive(glowW) then glowW:setImageClip(clip) end

  local lh = math.max(160, math.min(440, math.floor(h * 0.40)))
  local lw = math.floor(lh * LOGO_W / LOGO_H)
  if lw > w - 40 then
    lw = w - 40
    lh = math.floor(lw * LOGO_H / LOGO_W)
  end
  local lmt = math.floor(h * 0.03)
  logo:setSize({ width = lw, height = lh })
  logo:setMarginTop(lmt)
  halo:setSize({ width = math.floor(lw * 1.15), height = math.floor(lh * 1.1) })
  halo:setMarginTop(lmt - math.floor(lh * 0.05))

  local top = math.max(math.floor(h * 0.50), lmt + lh + 16)
  top = math.min(top, h - PANEL_H - 100)
  enterGame:setMarginTop(top)
  pressW:setMarginBottom(math.floor(h * 0.06))
end

-- ---------------------------------------------------------------- panel
local function skinField(w, normal, focus, rightPad)
  w:setImageSource(IMG .. normal)
  w:setImageBorder(6)
  w:setBackgroundColor('#00000000')
  w:setFont('verdana-11px-antialised')
  w:setColor('#e6d8bc')
  w:setPaddingLeft(7)
  w:setPaddingRight(rightPad or 7)
  w:setPaddingTop(4)
  w:setPaddingBottom(2)
  w:setSelectionColor('#0d0b0e')
  w:setSelectionBackgroundColor('#e8b84a')
  w.chaosNormal, w.chaosFocus = normal, focus
  connect(w, { onFocusChange = function(self, focused)
    self:setImageSource(IMG .. (focused and self.chaosFocus or self.chaosNormal))
  end })
  if w:isFocused() then w:setImageSource(IMG .. focus) end
end

local function skinLabel(w, text, x, y, wd)
  w:setStyle('ChaosLoginLabel')
  w:setTextAutoResize(false)
  w:setText(text)
  place(w, x, y, wd, 12)
end

local function exitClient()
  g_app.exit()
end

local function openLink(key, title, message)
  local url = Services and Services[key]
  if type(url) == 'string' and #url > 4 then
    g_platform.openUrl(url)
  else
    displayInfoBox(title, message)
  end
end

local function showCredits()
  displayInfoBox(tr('Credits'), tr('Cinders of Chaos\nA dark-fantasy online adventure.\n\nInterface, art and server: the Cinders of Chaos team.\nThe client runs on the open-source OTClient engine family.'))
end

local function openOptions()
  for _, name in ipairs({ 'client_settings', 'client_options' }) do
    local m = modules[name]
    if m and type(rawget(m, 'toggle')) == 'function' then
      m.toggle()
      return
    end
  end
end

local function makeButton(style, text, x, y, wd, ht, fn, id)
  local b = newWidget(style, enterGame, id)
  b:setText(text)
  place(b, x, y, wd, ht)
  b.onClick = fn
  return b
end

local function layoutPanel()
  local eg = enterGame
  eg:setText('')
  eg:setImageSource(IMG .. 'panel')
  eg:setImageBorder(26)
  eg:setPaddingTop(0) eg:setPaddingLeft(0) eg:setPaddingRight(0) eg:setPaddingBottom(0)
  eg:setSize({ width = PANEL_W, height = PANEL_H })
  eg:breakAnchors()
  eg:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  eg:addAnchor(AnchorTop, 'parent', AnchorTop)
  eg:setMarginLeft(0) eg:setMarginRight(0) eg:setMarginBottom(0)
  -- the theme adds gold corner pieces to ornate windows; this panel has its own frame
  eg.chaosDecorated = true
  for _, id in ipairs({ 'chaosOrnTL', 'chaosOrnTR', 'chaosOrnBL', 'chaosOrnBR', 'chaosOrnCrest' }) do
    local o = eg:getChildById(id)
    if o then o:destroy() end
  end

  local X0, FW, GAP, TW = 28, 196, 10, 72
  local rowLabel, rowField, rowChecks, rowBtn1, rowBtn2, rowLink = 14, 28, 62, 86, 122, 156

  local acc = eg:getChildById('accountNameTextEdit')
  local pass = eg:getChildById('accountPasswordTextEdit')
  local token = eg:getChildById('accountTokenTextEdit')
  skinLabel(eg:getChildById('emailLabel'), tr('ACCOUNT'), X0, rowLabel, FW)
  skinLabel(eg:getChildById('passwordLabel'), tr('PASSWORD'), X0 + FW + GAP, rowLabel, FW)
  skinLabel(eg:getChildById('tokenLabel'), tr('TOKEN'), X0 + 2 * (FW + GAP), rowLabel, TW)
  place(acc, X0, rowField, FW, 24)
  place(pass, X0 + FW + GAP, rowField, FW, 24)
  place(token, X0 + 2 * (FW + GAP), rowField, TW, 24)
  skinField(acc, 'field', 'field_focus', 26)
  skinField(pass, 'field_pass', 'field_pass_focus')
  skinField(token, 'field', 'field_focus')
  -- show / hide the account text keeps working: the stock eye button sits inside the account field
  place(eg:getChildById('hidden'), X0 + FW - 21, rowField + 3, 18, 18)
  -- accounts are names here, not e-mail addresses: no invalid-address warning
  local es = eg:getChildById('emailStatus')
  if es then es:setOpacity(0) es:setPhantom(true) place(es, 0, 0, 1, 1) end

  -- remember / auto login row
  local rem = eg:getChildById('rememberEmailBox')
  local remP = eg:getChildById('rememberPasswordBox')
  local auto = eg:getChildById('autoLoginBox')
  local lab = rem:getChildren()[1]
  if lab then lab:setText(tr('Remember account')) end
  for _, box in ipairs({ rem, remP, auto }) do
    local l = box:getChildren()[1] or box
    l:setFont('verdana-11px-antialised')
    l:setColor('#b3a389')
  end
  place(rem, X0, rowChecks, 150, 16)
  place(remP, X0 + 160, rowChecks, 150, 16)
  place(auto, X0 + 330, rowChecks, 120, 16)
  for _, id in ipairs({ 'buttonInformation', 'passwordInformation' }) do
    local b = eg:getChildById(id)
    if b then b:setOpacity(0) b:setPhantom(true) place(b, 0, 0, 1, 1) end
  end

  -- buttons (new, in the login art; each calls the stock function)
  local half = math.floor((PANEL_W - 2 * X0 - GAP) / 2)
  makeButton('ChaosLoginButton', tr('SIGN IN'), X0, rowBtn1, half, 30, function() EnterGame.doLogin() end, 'chaosSignIn')
  makeButton('ChaosLoginButtonRed', tr('CREATE ACCOUNT'), X0 + half + GAP, rowBtn1, half, 30, function()
    openLink('createAccount', tr('Create account'), tr('The account creation link is not set up yet. Ask an administrator for an account.'))
  end, 'chaosCreate')
  local third = math.floor((PANEL_W - 2 * X0 - 2 * GAP) / 3)
  makeButton('ChaosLoginButton', tr('OPTIONS'), X0, rowBtn2, third, 26, openOptions, 'chaosOptions')
  makeButton('ChaosLoginButton', tr('CREDITS'), X0 + third + GAP, rowBtn2, third, 26, showCredits, 'chaosCredits')
  makeButton('ChaosLoginButton', tr('EXIT GAME'), X0 + 2 * (third + GAP), rowBtn2, third, 26, exitClient, 'chaosExit')

  -- the stock buttons and links stay, hidden behind the new ones (login keeps working through EnterGame.doLogin)
  for _, id in ipairs({ 'loginButton', 'clickSiteCreateAccount' }) do
    local b = eg:getChildById(id)
    if b then b:setOpacity(0) b:setPhantom(true) place(b, 0, 0, 1, 1) end
  end
  local forgot = eg:getChildById('clickSitePassword')
  if forgot then
    forgot:setStyle('ChaosLoginLink')
    forgot:setTextAutoResize(false)
    forgot:setText(tr('Forgot password and/or email'))
    forgot.onClick = function()
      openLink('recoveryPassword', tr('Recover account'), tr('The password recovery link is not set up yet. Ask an administrator.'))
    end
    place(forgot, X0, rowLink, PANEL_W - 2 * X0, 14)
  end
  -- decorations of the stock layout that have no place in the new one
  for _, c in ipairs(eg:getChildren()) do
    local id = tostring(c:getId())
    local cls = c:getClassName()
    -- the underlines and separator of the stock layout have generated ids (widget123)
    if id == 'serverInfoLabel' or (id:match('^widget%d+$') and (cls == 'UILabel' or cls == 'UIWidget')) then
      c:setVisible(false)
    end
  end
  local gb = eg:getChildById('googleButton')
  if gb then gb:setVisible(false) end
end

-- ---------------------------------------------------------------- corners
local function moveToBackground(w, parentWidget)
  moved[#moved + 1] = { w, w:getParent() }
  w:setParent(parentWidget)
end

local function layoutCorners()
  local sel = enterGame:getChildById('serverSelectorPanel')
  local cam = findByTooltip(enterGame, tr('Open Recordings List'))
  serverCaption = newWidget('ChaosLoginCorner', bg, 'chaosServerCaption')
  serverCaption:setText(tr('Server'))
  serverCaption:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  serverCaption:addAnchor(AnchorTop, 'parent', AnchorTop)
  serverCaption:setMarginLeft(14)
  serverCaption:setMarginTop(13)
  if sel then
    moveToBackground(sel, bg)
    sel:breakAnchors()
    sel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    sel:addAnchor(AnchorTop, 'parent', AnchorTop)
    sel:setMarginLeft(62)
    sel:setMarginTop(10)
    sel:setWidth(150)
    sel:setHeight(22)
  end
  if cam then
    moveToBackground(cam, bg)
    cam:breakAnchors()
    cam:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    cam:addAnchor(AnchorTop, 'parent', AnchorTop)
    cam:setMarginLeft(220)
    cam:setMarginTop(11)
  end
  verLabel = newWidget('ChaosLoginCorner', bg, 'chaosVersion')
  verLabel:addAnchor(AnchorRight, 'parent', AnchorRight)
  verLabel:addAnchor(AnchorTop, 'parent', AnchorTop)
  verLabel:setMarginRight(14)
  verLabel:setMarginTop(10)
  local ver = tostring(g_app.getVersion() or '')
  verLabel:setText(tr('Version') .. ' ' .. (GameInfo and GameInfo.strVersion or '') .. (ver ~= '' and ('  -  client ' .. ver) or ''))

  statusLabel = newWidget('ChaosLoginCorner', bg, 'chaosStatus')
  statusLabel:addAnchor(AnchorRight, 'parent', AnchorRight)
  statusLabel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  statusLabel:setMarginRight(14)
  statusLabel:setMarginBottom(14)
  statusDot = newWidget('UIWidget', bg, 'chaosStatusDot')
  statusDot:setSize({ width = 8, height = 8 })
  statusDot:setPhantom(true)
  statusDot:addAnchor(AnchorRight, 'chaosStatus', AnchorLeft)
  statusDot:addAnchor(AnchorVerticalCenter, 'chaosStatus', AnchorVerticalCenter)
  statusDot:setMarginRight(6)
end

local function updateStatus()
  if not alive(statusLabel) then return end
  local text, color = tr('Server status: checking...'), '#7a6e60'
  local tm = modules.client_topmenu
  local top = tm and type(rawget(tm, 'getTopMenu')) == 'function' and tm.getTopMenu() or nil
  local lbl = top and top:recursiveGetChildById('onlineLabel')
  local n = lbl and lbl:getText():match('(%d+)')
  if n then
    text, color = tr('Server online') .. ' - ' .. n .. ' ' .. tr('players'), '#4fae5a'
  elseif not (Services and type(Services.status) == 'table' and #Services.status > 0) then
    text = tr('Server status: unknown')
  end
  statusLabel:setText(text)
  statusDot:setBackgroundColor(color)
end

-- the corner widgets follow the panel (login screen only, not the character list)
local function syncVisibility()
  if not alive(enterGame) then return end
  local panel = enterGame:isVisible()
  for _, w in ipairs({ medL, medR, crestT, crestB }) do
    if alive(w) then
      w:setVisible(panel)
      if panel then w:raise() end
    end
  end
  local corner = panel or state.splash
  -- opacity and phantom instead of visibility: the drop-down's own style turns it visible again
  for _, m in ipairs(moved) do
    if alive(m[1]) then
      m[1]:setOpacity(corner and 1 or 0)
      m[1]:setPhantom(not corner)
    end
  end
  if alive(serverCaption) then serverCaption:setVisible(corner) end
end

-- ---------------------------------------------------------------- decoration around the panel
local function createDecor()
  local parent = enterGame:getParent()
  local function deco(image, w, h, id)
    local d = newWidget('UIWidget', parent, id)
    d:setImageSource(IMG .. image)
    d:setSize({ width = w, height = h })
    d:setPhantom(true)
    return d
  end
  medL = deco('medallion_left', 64, 64, 'chaosMedL')
  medL:addAnchor(AnchorVerticalCenter, 'enterGame', AnchorTop)
  medL:addAnchor(AnchorHorizontalCenter, 'enterGame', AnchorLeft)
  medL:setMarginTop(46)
  medR = deco('medallion_right', 64, 64, 'chaosMedR')
  medR:addAnchor(AnchorVerticalCenter, 'enterGame', AnchorTop)
  medR:addAnchor(AnchorHorizontalCenter, 'enterGame', AnchorRight)
  medR:setMarginTop(46)
  crestT = deco('crest', 96, 22, 'chaosCrestT')
  crestT:addAnchor(AnchorHorizontalCenter, 'enterGame', AnchorHorizontalCenter)
  crestT:addAnchor(AnchorTop, 'enterGame', AnchorTop)
  crestT:setMarginTop(-6)
  crestB = deco('crest_bottom', 96, 22, 'chaosCrestB')
  crestB:addAnchor(AnchorHorizontalCenter, 'enterGame', AnchorHorizontalCenter)
  crestB:addAnchor(AnchorBottom, 'enterGame', AnchorBottom)
  crestB:setMarginBottom(-6)
  for _, w in ipairs({ medL, medR, crestT, crestB }) do w:raise() end
end

local function createBackgroundLayers()
  if USE_GLOW then
    glowW = newWidget('UIWidget', bg, 'chaosGlow')
    glowW:fill('parent')
    glowW:setImageSource(IMG .. 'glow')
    glowW:setImageSmooth(true)
    glowW:setPhantom(true)
    glowW:lower()
  end
  emberLayer = newWidget('UIWidget', bg, 'chaosEmbers')
  emberLayer:fill('parent')
  emberLayer:setPhantom(true)
  emberLayer:lower()
  if alive(glowW) then glowW:lower() end

  halo = newWidget('UIWidget', bg, 'chaosLogoHalo')
  halo:setImageSource(IMG .. 'logo_halo')
  halo:setImageSmooth(true)
  halo:setPhantom(true)
  halo:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  halo:addAnchor(AnchorTop, 'parent', AnchorTop)
  logo = newWidget('UIWidget', bg, 'chaosLogo')
  logo:setImageSource('/images/chaos/logo')
  logo:setImageSmooth(true)
  logo:setPhantom(true)
  logo:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  logo:addAnchor(AnchorTop, 'parent', AnchorTop)
  -- the glow of the cracks: same frame as the logo, its opacity smoulders in tick()
  logoHot = newWidget('UIWidget', logo, 'chaosLogoHot')
  logoHot:fill('parent')
  logoHot:setImageSource(IMG .. 'logo_hot')
  logoHot:setImageSmooth(true)
  logoHot:setPhantom(true)
  logoHot:setOpacity(0.6)
  sparkLayer = newWidget('UIWidget', bg, 'chaosSparks')
  sparkLayer:fill('parent')
  sparkLayer:setPhantom(true)

  for i = 1, EMBER_COUNT do
    local e = newWidget('UIWidget', emberLayer)
    e:setImageSource(IMG .. 'ember')
    e:setPhantom(true)
    e:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    e:addAnchor(AnchorTop, 'parent', AnchorTop)
    embers[i] = { w = e, x = math.random(0, 1920), y = math.random(0, 1080), size = math.random(5, 12),
                  vy = math.random(14, 46), vx = math.random(4, 22), ph = math.random() * 6.28, fl = 2 + math.random() * 3 }
    e:setSize({ width = embers[i].size, height = embers[i].size })
  end
  for i = 1, ASH_COUNT do
    local a = newWidget('UIWidget', emberLayer)
    a:setImageSource(IMG .. 'ash')
    a:setPhantom(true)
    a:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    a:addAnchor(AnchorTop, 'parent', AnchorTop)
    ashes[i] = { w = a, x = math.random(0, 1920), y = math.random(0, 1080), size = math.random(4, 9),
                 vy = math.random(10, 26), vx = math.random(-8, 8), ph = math.random() * 6.28, op = 0.25 + math.random() * 0.45 }
    a:setSize({ width = ashes[i].size, height = ashes[i].size })
    a:setOpacity(ashes[i].op)
  end
  for i = 1, SPARK_COUNT do
    local sp = newWidget('UIWidget', sparkLayer)
    sp:setImageSource(IMG .. 'spark')
    sp:setPhantom(true)
    sp:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    sp:addAnchor(AnchorTop, 'parent', AnchorTop)
    sp:setOpacity(0)
    -- off screen until the first respawn; staggered lives so they do not all start at once
    sparks[i] = { w = sp, x = -50, y = -50, vx = 0, vy = 0, age = 0, life = math.random() * 2 }
  end

  pressW = newWidget('ChaosLoginPress', bg, 'chaosPressKey')
  pressW:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  pressW:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  pressW:getChildById('text'):setText(tr('Press any key to start'))
  pressW:setVisible(false)
end

-- ---------------------------------------------------------------- animation
local function tick()
  animEvent = scheduleEvent(tick, 50)
  if not alive(bg) or not bg:isVisible() then return end
  clock = clock + 0.05
  if alive(glowW) then
    glowW:setOpacity(math.max(0.25, math.min(1, 0.62 + 0.18 * math.sin(clock * 1.6) + 0.14 * math.sin(clock * 5.1 + 1.3)
      + 0.06 * (math.random() - 0.5))))
  end
  local w, h = bg:getWidth(), bg:getHeight()
  for _, e in ipairs(embers) do
    e.y = e.y - e.vy * 0.05
    e.x = e.x + (e.vx + 10 * math.sin(clock * 0.9 + e.ph)) * 0.05
    if e.y < -20 or e.x > w + 20 then
      e.y = h + math.random(0, 60)
      e.x = math.random(0, w)
    end
    e.w:setMarginLeft(math.floor(e.x))
    e.w:setMarginTop(math.floor(e.y))
    e.w:setOpacity(0.35 + 0.65 * math.abs(math.sin(clock * e.fl + e.ph)))
  end
  for _, a in ipairs(ashes) do
    a.y = a.y + a.vy * 0.05
    a.x = a.x + (a.vx + 12 * math.sin(clock * 0.7 + a.ph)) * 0.05
    if a.y > h + 20 or a.x < -20 or a.x > w + 20 then
      a.y = -math.random(5, 60)
      a.x = math.random(0, w)
    end
    a.w:setMarginLeft(math.floor(a.x))
    a.w:setMarginTop(math.floor(a.y))
  end
  -- the wordmark smoulders: its crack glow breathes, sparks leave the letters
  if alive(logoHot) then
    logoHot:setOpacity(math.max(0.2, math.min(1, 0.58 + 0.2 * math.sin(clock * 1.3) + 0.12 * math.sin(clock * 4.1 + 0.8)
      + 0.08 * (math.random() - 0.5))))
  end
  if alive(logo) then
    local lx, ly = logo:getX() - bg:getX(), logo:getY() - bg:getY()
    local lw, lh = logo:getWidth(), logo:getHeight()
    for _, s in ipairs(sparks) do
      s.age = s.age + 0.05
      if s.age >= s.life then
        -- a new spark from the upper edge of one of the two lines of letters (the tops of CINDERS and CHAOS)
        local line = math.random() < 0.55 and { 0.10, 0.17 } or { 0.53, 0.60 }
        s.x = lx + lw * (0.1 + 0.8 * math.random())
        s.y = ly + lh * (line[1] + (line[2] - line[1]) * math.random())
        s.vy = math.random(28, 70)
        s.vx = math.random(-14, 14)
        s.age, s.life = 0, 1.0 + math.random() * 1.4
        local sz = math.random(6, 11)
        s.w:setSize({ width = sz, height = sz })
      end
      s.y = s.y - s.vy * 0.05
      s.x = s.x + (s.vx + 8 * math.sin(clock * 3 + s.life * 7)) * 0.05
      s.w:setMarginLeft(math.floor(s.x))
      s.w:setMarginTop(math.floor(s.y))
      local t = s.age / s.life
      s.w:setOpacity(math.max(0, (1 - t)) * (0.7 + 0.3 * math.random()))
    end
  end
  if state.splash and alive(pressW) then
    pressW:setOpacity(0.6 + 0.4 * math.sin(clock * 2.4))
    local la = bg:getChildById('loadAfter')
    if la and la:isVisible() then la:setVisible(false) end
  end
end

local function fadeIn()
  local targets = { enterGame, medL, medR, crestT, crestB }
  local step = 0
  removeEvent(fadeEvent)
  local function run()
    step = step + 1
    local o = math.min(1, step / 8)
    for _, t in ipairs(targets) do
      if alive(t) then t:setOpacity(o) end
    end
    if o < 1 then fadeEvent = scheduleEvent(run, 30) else fadeEvent = nil end
  end
  for _, t in ipairs(targets) do
    if alive(t) then t:setOpacity(0) end
  end
  run()
end

-- ---------------------------------------------------------------- press any key
local function reveal()
  if not state.splash then return end
  state.splash = false
  if alive(splashW) then
    splashW:ungrabKeyboard()
    splashW:destroy()
    splashW = nil
  end
  if alive(pressW) then pressW:setVisible(false) end
  if modules.client_background and modules.client_background.showPanel then modules.client_background.showPanel() end
  if EnterGame and EnterGame.show then EnterGame.show() end
  syncVisibility()
  fadeIn()
end

local function startSplash()
  state.splash = true
  pressW:setVisible(true)
  splashW = newWidget('UIWidget', bg, 'chaosSplashKeys')
  splashW:fill('parent')
  splashW:setPhantom(true)
  splashW.onKeyDown = function() reveal() return true end
  splashW:grabKeyboard()
  bg.onMousePress = function(w, pos, button)
    if state.splash then reveal() end
    return false
  end
  if alive(enterGame) then
    enterGame:hide()
  end
  syncVisibility()
end

local function shouldSplash()
  if not SPLASH then return false end
  if g_game.isOnline() or g_game.isLogging() or G.characters then return false end
  local auto = g_settings.getBoolean('autologin')
  local account = g_crypt.decrypt(g_settings.get('account'))
  local password = g_crypt.decrypt(g_settings.get('password'))
  if auto and #account > 0 and #password > 0 then return false end
  return true
end

-- ---------------------------------------------------------------- lifecycle
function init()
  if not EnterGame then return end
  root = g_ui.getRootWidget()
  enterGame = root:getChildById('enterGame')
  bg = modules.client_background and modules.client_background.getBackground()
  if not alive(enterGame) or not alive(bg) then
    g_logger.warning('[chaos_login] login windows not found, keeping the stock look')
    return
  end
  g_ui.importStyle('login')

  bg:setImageSource('/images/title')
  bg:setImageFixedRatio(false)
  bg:setImageSmooth(true)
  bg:setMarginTop(0)

  createBackgroundLayers()
  layoutPanel()
  layoutCorners()
  createDecor()
  relayout()
  updateStatus()

  connect(bg, { onGeometryChange = relayout })
  connect(enterGame, { onVisibilityChange = syncVisibility })
  connect(bg, { onVisibilityChange = function(_, visible)
    if visible then updateStatus() end
  end })
  ChaosLogin.statusEvent = cycleEvent(updateStatus, 3000)
  animEvent = scheduleEvent(tick, 50)

  -- EnterGame.show is also called by the error boxes and after a logout: while the splash waits it keeps
  -- the panel hidden, afterwards it is the stock function
  origShow = EnterGame.show
  EnterGame.show = function(...)
    origShow(...)
    if state.splash and alive(enterGame) then
      enterGame:hide()
    end
    syncVisibility()   -- also puts the medallions back above the window (the stock show raises the window)
  end

  if shouldSplash() then
    startSplash()
  else
    syncVisibility()
  end
end

function terminate()
  removeEvent(animEvent)
  removeEvent(fadeEvent)
  if ChaosLogin and ChaosLogin.statusEvent then removeEvent(ChaosLogin.statusEvent) end
  if EnterGame and origShow then EnterGame.show = origShow end
  if alive(bg) then bg.onMousePress = nil end
  for _, m in ipairs(moved) do
    if alive(m[1]) and alive(m[2]) then m[1]:setParent(m[2]) end
  end
  for _, w in ipairs({ medL, medR, crestT, crestB, logo, halo, glowW, emberLayer, sparkLayer, pressW, splashW, verLabel,
                       statusLabel, statusDot, serverCaption }) do
    if alive(w) then w:destroy() end
  end
  ChaosLogin = nil
end
