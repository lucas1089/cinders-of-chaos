-- Cinders of Chaos login screen.
--
-- The stock client builds the login screen from two modules: client_background (the full-screen picture, the
-- event / boosted / cast panels) and client_entergame (the account window). This module leaves both in place
-- (their code and every function stay as they are) and restyles them at runtime:
--   * the background picture (data/images/title.png: the login artwork, 1920x1536 with the artwork in a band in the
--     middle) is cropped to cover the window, with a flickering glow overlay, rising embers and falling ash on top;
--   * the logo layer (chaos/logo.png, cut out of the artwork) sits exactly on the logo painted in the picture; its
--     glow image (chaos/login/logo_hot.png) breathes over the letters and sparks leave them;
--   * the widgets sit where the artwork painted its mock interface: "Press any key to start" on its dark bar, the
--     server status and a spinner under it, then the framed sign-in panel at the bottom centre (SIGN IN / CREATE
--     ACCOUNT, OPTIONS / CREDITS / EXIT GAME; the stock fields, check boxes and buttons are moved into the panel);
--   * the server drop-down, recordings button, server status and version sit in the top corners; the stock event /
--     boosted / cast panels go under the sign-in panel or beside it when there is room;
--   * the small four-pointed mark in the artwork's bottom right corner (left by the image generator) stays visible:
--     no widget is placed on it and particles are not drawn over it.
--   * the living scene (loginscene.lua): a piece of our world built from game tiles with our monsters idling in it,
--     shown instead of the artwork or crossfading with it (setting 'chaosLoginBackground': scene / art / alternate;
--     the small "Background" link in the top right corner switches it). Without the dat/spr pair the artwork shows.
-- Art: client/tools/gen_login_art.py (data/images/title.png and data/images/chaos/login/).

ChaosLogin = {}

local IMG = '/images/chaos/login/'
local BG_W, BG_H = 1920, 1536          -- size of data/images/title.png
local BAND_Y, BAND_H = 232, 1072       -- the artwork's rows in title.png (above and below: darkened extension)
local ART_K = 1920 / 1376              -- title.png pixels per artwork pixel (the boxes below are artwork pixels)
local LOGO_BOX = { 396, 196, 980, 566 }      -- the logo; chaos/logo.png covers exactly this box
local PRESS_BOX = { 520, 569, 856, 608 }     -- the painted "press any key" bar
local STATUS_Y, SPIN_X, SPIN_Y, SPIN_D = 624, 687.5, 657, 30   -- painted "connecting..." line and spinner
local MARK_BOX = { 1284, 678, 1356, 746 }    -- the generator's sparkle mark: kept free of widgets and particles
local PANEL_Y = 540                    -- top of the sign-in panel (just under the logo's lower spike)
local PANEL_W, PANEL_H = 540, 180
local EMBER_COUNT = 22                 -- embers rising through the scene (the picture has its own)
local ASH_COUNT = 10                   -- ash flakes falling through it
local SPARK_COUNT = 12                 -- sparks rising off the burning letters
local USE_GLOW = true                  -- flicker overlay chaos/login/glow.png (lava and windows of title.png)
local SPLASH = true                    -- "Press any key to start" before the panel

local root, bg, enterGame
local logo, logoHot, glowW, emberLayer, sparkLayer, pressW, splashW, spinner
local medL, medR, crestT, crestB
local verLabel, statusLabel, statusDot, serverCaption, sceneLink, langLink
local view = { cx = 0, cy = 0, sx = 1, sy = 1 }   -- crop of title.png and its scale on screen
local mark = { x0 = -1, y0 = -1, x1 = -1, y1 = -1 } -- the sparkle mark on screen (relative to bg)
local statusChecking = true
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
-- upper case of a translated (cp1252) text: string.upper leaves "\231" (c cedilla) and the other accents alone
local function upperText(s)
  local core = rawget(_G, 'ChaosLocaleCore')
  if core and core.upper then return core.upper(s) end
  return s:upper()
end

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
-- cover crop of title.png for any window shape: from 16:9 to 5:4 the whole width of the artwork shows (the extension
-- above and below fills the height); wider windows crop rows of the artwork, keeping its bottom; narrower ones crop
-- the sides
local function coverClip(w, h)
  local ar = w / math.max(1, h)
  local cw, ch, cx, cy = BG_W, BG_H, 0, 0
  if ar >= BG_W / BAND_H then
    ch = math.floor(BG_W / ar)
    cy = BAND_Y + BAND_H - ch
  elseif ar >= BG_W / BG_H then
    ch = math.floor(BG_W / ar)
    cy = math.floor(BAND_Y + (BAND_H - ch) / 2)
  else
    cw = math.floor(BG_H * ar)
    cx = math.floor((BG_W - cw) / 2)
  end
  return cx, cy, cw, ch
end

-- artwork pixel -> position on screen relative to bg
local function artX(ax) return math.floor((ax * ART_K - view.cx) * view.sx + 0.5) end
local function artY(ay) return math.floor((BAND_Y + ay * ART_K - view.cy) * view.sy + 0.5) end
local function artBox(b) return artX(b[1]), artY(b[2]), artX(b[3]) - artX(b[1]), artY(b[4]) - artY(b[2]) end

local function inMark(x, y, r)
  r = r or 0
  return x + r >= mark.x0 and x - r <= mark.x1 and y + r >= mark.y0 and y - r <= mark.y1
end

local layoutInfo, placeStatus, barTick

local function relayout()
  if not alive(bg) then return end
  local w, h = bg:getWidth(), bg:getHeight()
  if w < 100 or h < 100 then return end
  local cx, cy, cw, ch = coverClip(w, h)
  view.cx, view.cy, view.sx, view.sy = cx, cy, w / cw, h / ch
  local clip = string.format('%d %d %d %d', cx, cy, cw, ch)
  bg:setImageClip(clip)
  if alive(glowW) then glowW:setImageClip(clip) end

  -- the logo layer on the logo of the picture
  local x, y, lw, lh = artBox(LOGO_BOX)
  place(logo, x, y, lw, lh)
  if LoginScene and LoginScene.isActive() then LoginScene.setLogoBox(x, y, lw, lh) end
  mark.x0, mark.y0, mark.x1, mark.y1 = artX(MARK_BOX[1]), artY(MARK_BOX[2]), artX(MARK_BOX[3]), artY(MARK_BOX[4])

  -- splash: the bar, the status line and the spinner where the artwork painted them
  local px, py, pw, ph = artBox(PRESS_BOX)
  place(pressW, px, py, pw, ph)
  local d = math.max(16, math.floor(SPIN_D * ART_K * view.sx))
  place(spinner, artX(SPIN_X) - math.floor(d / 2), artY(SPIN_Y) - math.floor(d / 2), d, d)

  -- the sign-in panel at the bottom centre, under the logo
  local top = math.min(artY(PANEL_Y), h - PANEL_H - 10)
  enterGame:setMarginTop(math.max(0, top))
  if placeStatus then placeStatus() end
  if layoutInfo then layoutInfo() end
  if LoginScene and LoginScene.isActive() then LoginScene.relayout() end
end

-- ---------------------------------------------------------------- living scene (loginscene.lua)
-- where no monster or tall object of the scene goes: behind the logo and the sign-in panel
local function sceneKeep()
  if not alive(bg) then return {} end
  local x, y, lw, lh = artBox(LOGO_BOX)
  local top = alive(enterGame) and enterGame:getMarginTop() or artY(PANEL_Y)
  return { { x = x, y = y, width = lw, height = lh },
           { x = math.floor((bg:getWidth() - PANEL_W) / 2) - 40, y = top - 20, width = PANEL_W + 80, height = PANEL_H + 40 } }
end

local function updateSceneLink()
  if not alive(sceneLink) then return end
  sceneLink:setText(tr('Background') .. ': ' .. tr(LoginSceneCore.MODE_LABEL[LoginScene.mode()]))
end

local function applySceneMode()
  if LoginScene.mode() == 'art' then
    LoginScene.destroy()
  elseif not LoginScene.isActive() then
    LoginScene.create(bg, sceneKeep)
    relayout()
  end
  if alive(glowW) then glowW:setVisible(not LoginScene.isActive() or LoginScene.mode() == 'alternate') end
  updateSceneLink()
end

local function createSceneLink()
  sceneLink = newWidget('ChaosLoginLink', bg, 'chaosSceneLink')
  sceneLink:setPhantom(false)
  sceneLink:setTextAutoResize(true)
  sceneLink:addAnchor(AnchorRight, 'parent', AnchorRight)
  sceneLink:addAnchor(AnchorTop, 'parent', AnchorTop)
  sceneLink:setMarginRight(14)
  sceneLink:setMarginTop(30)
  sceneLink:setTooltip(tr('The login background: the living scene, the artwork, or both in turn'))
  sceneLink.onClick = function()
    LoginScene.setMode(LoginSceneCore.nextMode(LoginScene.mode()))
    applySceneMode()
  end
  updateSceneLink()
end

-- the language (client_chaos_locale): under the background link; a choice reloads the modules, this screen too
local function createLangLink()
  if not ChaosLocale or not ChaosLocale.showMenu then return end
  langLink = newWidget('ChaosLoginLink', bg, 'chaosLangLink')
  langLink:setPhantom(false)
  langLink:setTextAutoResize(true)
  langLink:addAnchor(AnchorRight, 'parent', AnchorRight)
  langLink:addAnchor(AnchorTop, 'parent', AnchorTop)
  langLink:setMarginRight(14)
  langLink:setMarginTop(50)
  langLink:setText(ChaosLocale.buttonText())
  langLink:setTooltip(tr('The language of the client and of the server messages'))
  langLink.onClick = function() ChaosLocale.showMenu(langLink) end
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

-- corelib's message box takes the skinned window style (client_chaos_theme sets its title font and offset) and then
-- puts its own Verdana back on the title: give the title the Chaos title font again, like the other skinned windows
local function infoBox(title, message)
  local box = displayInfoBox(title, message)
  local theme = modules.client_chaos_theme and modules.client_chaos_theme.ChaosTheme
  if box and theme and theme.applyFont and theme.applyFont(box, 'title') then
    local w = box:getTextSize().width + box:getPaddingLeft() + box:getPaddingRight()
    if box:getWidth() < w then box:setWidth(w) end
  end
  return box
end

local function openLink(key, title, message)
  local url = Services and Services[key]
  if type(url) == 'string' and #url > 4 then
    g_platform.openUrl(url)
  else
    infoBox(title, message)
  end
end

-- the Credits window (client_chaos_credits, every source from docs/CREDITS.md); the short box only without it
local function showCredits()
  local m = modules and modules.client_chaos_credits
  if m and type(rawget(m, 'show')) == 'function' then
    m.show()
    return
  end
  infoBox(tr('Credits'), tr('Cinders of Chaos\nA dark-fantasy online adventure.\n\nInterface, art and server: the Cinders of Chaos team.\nThe client runs on the open-source OTClient engine family.\n\n' ..
    'Fonts (SIL Open Font License 1.1, licence texts in data/fonts/chaos):\nCinzel - The Cinzel Project Authors\n' ..
    'Alegreya SC, Alegreya Sans - The Alegreya (Sans) Project Authors, Huerta Tipografica\n' ..
    'IM Fell English - Igino Marini'))
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
  -- the stock texts of the other two boxes stay English without this (base enterGame has no pt-BR)
  local labP = remP and (remP:getChildren()[1] or remP)
  if labP then labP:setText(tr('Remember password')) end
  local labA = auto and (auto:getChildren()[1] or auto)
  if labA then labA:setText(tr('Auto login')) end
  for _, box in ipairs({ rem, remP, auto }) do
    local l = box:getChildren()[1] or box
    l:setFont('verdana-11px-antialised')
    l:setColor('#b3a389')
  end
  place(rem, X0, rowChecks, 150, 16)
  place(remP, X0 + 160, rowChecks, 150, 16)
  place(auto, X0 + 330, rowChecks, 150, 16)  -- "Login autom\225tico" is wider than "Auto Login"
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
    -- right of the caption, whatever its length ("Servidor" is wider than "Server")
    local capW = serverCaption:getTextSize().width
    sel:setMarginLeft(math.max(62, 14 + capW + 8))
    sel:setMarginTop(10)
    sel:setWidth(150)
    sel:setHeight(22)
  end
  if cam then
    moveToBackground(cam, bg)
    cam:breakAnchors()
    cam:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    cam:addAnchor(AnchorTop, 'parent', AnchorTop)
    cam:setMarginLeft((sel and sel:getMarginLeft() or 62) + 158)
    cam:setMarginTop(11)
  end
  verLabel = newWidget('ChaosLoginCorner', bg, 'chaosVersion')
  verLabel:addAnchor(AnchorRight, 'parent', AnchorRight)
  verLabel:addAnchor(AnchorTop, 'parent', AnchorTop)
  verLabel:setMarginRight(14)
  verLabel:setMarginTop(10)
  local ver = tostring(g_app.getVersion() or '')
  verLabel:setText(tr('Version') .. ' ' .. (GameInfo and GameInfo.strVersion or '') .. (ver ~= '' and (tr('  -  client %s', ver)) or ''))

  -- server status: the artwork's "CONNECTING..." line under the splash bar, under the server box once the panel shows
  statusLabel = newWidget('ChaosLoginStatus', bg, 'chaosStatus')
  statusDot = newWidget('UIWidget', bg, 'chaosStatusDot')
  statusDot:setSize({ width = 7, height = 7 })
  statusDot:setPhantom(true)
  statusDot:addAnchor(AnchorRight, 'chaosStatus', AnchorLeft)
  statusDot:addAnchor(AnchorVerticalCenter, 'chaosStatus', AnchorVerticalCenter)
  statusDot:setMarginRight(6)
end

placeStatus = function()
  if not alive(statusLabel) or not alive(bg) then return end
  statusLabel:breakAnchors()
  if state.splash then
    statusLabel:setText(statusLabel.chaosText and upperText(statusLabel.chaosText) or '')
    statusLabel:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    statusLabel:addAnchor(AnchorTop, 'parent', AnchorTop)
    statusLabel:setMarginLeft(artX(688) - math.floor(bg:getWidth() / 2))
    statusLabel:setMarginTop(artY(STATUS_Y) - 7)
  else
    statusLabel:setText(statusLabel.chaosText or '')
    statusLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    statusLabel:addAnchor(AnchorTop, 'parent', AnchorTop)
    statusLabel:setMarginLeft(28)
    statusLabel:setMarginTop(38)
  end
  if alive(spinner) then spinner:setVisible(state.splash and statusChecking) end
  if alive(statusDot) then statusDot:setVisible(not (state.splash and statusChecking)) end
end

local function updateStatus()
  if not alive(statusLabel) then return end
  local text, color = tr('Connecting...'), '#7a6e60'
  local checking = true
  local tm = modules.client_topmenu
  local top = tm and type(rawget(tm, 'getTopMenu')) == 'function' and tm.getTopMenu() or nil
  local lbl = top and top:recursiveGetChildById('onlineLabel')
  local n = lbl and lbl:getText():match('(%d+)')
  if n then
    text, color = tr('Server online') .. ' - ' .. n .. ' ' .. tr('players'), '#4fae5a'
    checking = false
  elseif not (Services and type(Services.status) == 'table' and #Services.status > 0) then
    text = tr('Server status: unknown')
    checking = false
  end
  statusLabel.chaosText = text
  statusChecking = checking
  statusDot:setBackgroundColor(color)
  placeStatus()
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
  local la = alive(bg) and bg:getChildById('loadAfter')
  if la and (state.splash or la.chaosHidden) then la:setVisible(false) end
  placeStatus()
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

  -- the logo, cut out of the artwork: placed exactly on the logo painted in title.png (see relayout)
  logo = newWidget('UIWidget', bg, 'chaosLogo')
  logo:setImageSource('/images/chaos/logo')
  logo:setImageSmooth(true)
  logo:setPhantom(true)
  -- the hottest parts of the letters: same frame as the logo, its opacity breathes in tick()
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
    embers[i] = { w = e, x = math.random(0, 1920), y = math.random(0, 1080), size = math.random(4, 10),
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
  -- the words are an image (serif lettering); a translated text shows on the plate as a label instead
  local pressText = tr('Press any key to start')
  -- with the Chaos splash font (client_chaos_theme ChaosTheme.fonts) the words are always that label
  local theme = modules.client_chaos_theme and modules.client_chaos_theme.ChaosTheme
  local splashFont = theme and theme.font and theme.font('splash')
  if pressText ~= 'Press any key to start' or splashFont then
    pressW:getChildById('words'):setVisible(false)
    if splashFont then pressW:getChildById('text'):setFont(splashFont) end
    pressW:getChildById('text'):setText(upperText(pressText))
    pressW:getChildById('text'):setVisible(true)
  end
  pressW:setVisible(false)
  spinner = newWidget('UIWidget', bg, 'chaosSpinner')
  spinner:setImageSource(IMG .. 'spinner')
  spinner:setImageClip('0 0 32 32')
  spinner:setImageSmooth(true)
  spinner:setPhantom(true)
  spinner:setVisible(false)
end

-- the stock event schedule / boosted / casts panels (client_background): under the sign-in panel when they fit,
-- else beside it (schedule and boosted bottom left, casts bottom right above the corner mark), else hidden
-- which panels show (ChaosLoginBar: only with data; casts only on a server that has them); set by barTick
local barShown = { info = false, boost = false, cast = false }
local barKey = nil

layoutInfo = function()
  local la = alive(bg) and bg:getChildById('loadAfter')
  if not la or not alive(enterGame) then return end
  local info, boost, cast = la:getChildById('informationScroll'), la:getChildById('boostedScroll'), la:getChildById('castScroll')
  if not (info and boost and cast) then return end
  info:setVisible(barShown.info)
  boost:setVisible(barShown.boost)
  cast:setVisible(barShown.cast)
  local w, h = bg:getWidth(), bg:getHeight()
  local panelBottom = enterGame:getMarginTop() + PANEL_H + 8
  local IH, gap = 117, 8
  la:breakAnchors()
  la:fill('parent')
  la:setPhantom(true)
  la.chaosHidden = false
  local function at(wd, x, y)
    wd:breakAnchors()
    wd:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    wd:addAnchor(AnchorTop, 'parent', AnchorTop)
    wd:setMarginLeft(x) wd:setMarginTop(y) wd:setMarginRight(0) wd:setMarginBottom(0)
  end
  local iw, bw, cw = info:getWidth(), boost:getWidth(), cast:getWidth()
  local side = math.floor((w - PANEL_W - 64) / 2)       -- room beside the panel and its medallions
  local widgets = { info = info, boost = boost, cast = cast }
  if panelBottom + IH + 4 <= h then
    -- the shown panels side by side, centred
    for _, p in ipairs(ChaosLoginBar.row({ 'info', 'boost', 'cast' }, barShown,
        { info = iw, boost = bw, cast = cw }, w, 1)) do
      at(widgets[p.id], p.x, h - IH - 2)
    end
  elseif side >= math.max(iw, bw, cw) + 24 and mark.y0 - IH - gap >= 40 and h - 2 * IH - 10 - gap >= 40 then
    -- schedule and boosted bottom left (the shown ones from the bottom up), casts bottom right
    local y = h - IH - 10
    for _, id in ipairs({ 'info', 'boost' }) do
      if barShown[id] then
        at(widgets[id], 12, y)
        y = y - IH - gap
      end
    end
    at(cast, w - cw - 12, mark.y0 - IH - gap)
  else
    la.chaosHidden = true
  end
end

-- the stock event schedule rows (client_background schedule.lua, EventsScheduleLabel) are about 95 px wide and cut
-- a long event name mid-letter ("Tower Ascensio"): such a name ends in whole letters and ".." instead (the row's
-- tooltip keeps the full name and description)
local function elideRow(ui)
  local w = ui:getWidth()
  if w <= 0 and ui:getParent() then w = ui:getParent():getWidth() - 2 end
  if w <= 8 then return end
  local fits = function() return ui:getTextSize().width <= w - 4 end
  if fits() then return end
  local s = ui:getText()
  while #s > 1 do
    s = s:sub(1, -2):gsub('%s+$', '')
    ui:setText(s .. '..')
    if fits() then return end
  end
end

local function elideSchedule(widget)
  if not alive(widget) then return end
  for _, id in ipairs({ 'activeEvent', 'upcomingEvent' }) do
    local list = widget:recursiveGetChildById(id)
    if list then
      for _, ui in ipairs(list:getChildren()) do try(elideRow, ui) end
    end
  end
end

local function scheduleTable()
  local m = modules.client_background
  local es = m and rawget(m, 'EventSchedule')
  return type(es) == 'table' and type(es.configureEvent) == 'function' and es or nil
end

local function hookSchedule()
  local es = scheduleTable()
  if not es or es.chaosConfigure then return end
  local orig = es.configureEvent
  es.chaosConfigure = orig
  es.configureEvent = function(self, widget)
    orig(self, widget)
    try(elideSchedule, widget)
  end
  local la = alive(bg) and bg:getChildById('loadAfter')
  try(elideSchedule, la and la:getChildById('informationScroll'))
end

local function unhookSchedule()
  local es = scheduleTable()
  if es and es.chaosConfigure then
    es.configureEvent = es.chaosConfigure
    es.chaosConfigure = nil
  end
end

-- ---------------------------------------------------------------- animation
-- the bottom bar: shown only with the sign-in panel and with data (ChaosLoginBar); laid out again when that changes
barTick = function()
  local la = alive(bg) and bg:getChildById('loadAfter')
  if not la then return end
  local bgm = modules.client_background
  local es = bgm and rawget(bgm, 'EventSchedule')
  local hasBoosted = bgm and rawget(bgm, 'hasBoostedInfo')
  local csm = modules.client_chaos_charselect
  local cs = csm and rawget(csm, 'CharSelect')
  local st = ChaosLoginBar.state({
    splash = state.splash, noRoom = la.chaosHidden == true,
    loginPanel = alive(enterGame) and enterGame:isVisible(),
    charList = cs ~= nil and type(cs.isVisible) == 'function' and cs.isVisible() == true,
    inGame = g_game.isOnline() or g_game.isLogging(),
    events = ChaosLoginBar.eventCount(type(es) == 'table' and es.events or nil),
    boosted = type(hasBoosted) == 'function' and hasBoosted() == true,
    casts = type(Services) == 'table' and Services.casts == true,
  })
  local key = ChaosLoginBar.key(st)
  if key ~= barKey then
    barKey = key
    barShown = { info = st.info, boost = st.boost, cast = st.cast }
    if layoutInfo then try(layoutInfo) end
  end
  if la:isVisible() ~= (st.bar and not la.chaosHidden) then la:setVisible(st.bar and not la.chaosHidden) end
end

local function tick()
  if not alive(bg) or not bg:isVisible() then
    animEvent = nil -- asleep while the login screen is hidden; its onVisibilityChange wakes it
    return
  end
  animEvent = scheduleEvent(tick, 50)
  clock = clock + 0.05
  local artWeight = 1
  if LoginScene and LoginScene.isActive() then
    LoginScene.tick(0.05)
    artWeight = 1 - LoginScene.opacity()
  end
  if alive(glowW) then
    glowW:setOpacity(artWeight * math.max(0.25, math.min(1, 0.62 + 0.18 * math.sin(clock * 1.6)
      + 0.14 * math.sin(clock * 5.1 + 1.3) + 0.06 * (math.random() - 0.5))))
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
    e.w:setOpacity(inMark(e.x, e.y, e.size) and 0 or (0.35 + 0.65 * math.abs(math.sin(clock * e.fl + e.ph))))
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
    a.w:setOpacity(inMark(a.x, a.y, a.size) and 0 or a.op)
  end
  -- the logo smoulders: the glow of its letters breathes, sparks leave the letters
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
        -- a new spark from the upper edge of one of the two lines of letters (the tops of CINDERS and CHAOS,
        -- as fractions of the logo box)
        local line = math.random() < 0.55 and { 0.25, 0.31, 0.18, 0.82 } or { 0.535, 0.585, 0.26, 0.77 }
        s.x = lx + lw * (line[3] + (line[4] - line[3]) * math.random())
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
      s.w:setOpacity(inMark(s.x, s.y, 8) and 0 or math.max(0, (1 - t)) * (0.7 + 0.3 * math.random()))
    end
  end
  if state.splash and alive(pressW) then
    local o = 0.62 + 0.38 * math.sin(clock * 2.4)
    pressW:getChildById('words'):setOpacity(o)
    pressW:getChildById('text'):setOpacity(o)
  end
  if alive(spinner) and spinner:isVisible() then
    spinner:setImageClip(string.format('%d 0 32 32', (math.floor(clock * 16) % 12) * 32))
  end
  barTick()
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
local function inGame()
  return g_game.isOnline() or g_game.isLogging()
end

-- ends the splash (its keyboard grab too) without showing the login panel
local function endSplash()
  state.splash = false
  if alive(splashW) then
    splashW:ungrabKeyboard()
    splashW:destroy()
    splashW = nil
  end
  if alive(pressW) then pressW:setVisible(false) end
  if alive(spinner) then spinner:setVisible(false) end
end

local function reveal()
  if not state.splash then return end
  endSplash()
  -- a login that did not go through the splash (a script, a launcher) leaves it waiting with the keyboard grabbed: the
  -- first key in the game then showed the login panel next to the game
  if inGame() then return end
  if modules.client_background and modules.client_background.showPanel then modules.client_background.showPanel() end
  if EnterGame and EnterGame.show then EnterGame.show() end
  relayout()
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

-- the game started while the splash still waited (no key was pressed: a scripted or launcher login)
local function onGameStart()
  if state.splash then endSplash() end
  if alive(enterGame) and enterGame:isVisible() then enterGame:hide() end
end

-- the character list opened while the splash still waited (a launcher or scripted login): the splash ends without the
-- login panel, so its "CONNECTING..." line and spinner do not sit over the character select (client_chaos_charselect)
function ChaosLogin.endSplash()
  if not state.splash then return end
  endSplash()
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
  try(createSceneLink)
  try(createLangLink)
  try(applySceneMode)
  updateStatus()
  try(hookSchedule)

  connect(bg, { onGeometryChange = relayout })
  connect(enterGame, { onVisibilityChange = syncVisibility })
  connect(bg, { onVisibilityChange = function(_, visible)
    if visible then
      updateStatus()
      if not animEvent then animEvent = scheduleEvent(tick, 50) end
    end
  end })
  ChaosLogin.statusEvent = cycleEvent(updateStatus, 3000)
  animEvent = scheduleEvent(tick, 50)

  -- EnterGame.show is also called by the error boxes and after a logout: while the splash waits it keeps
  -- the panel hidden, afterwards it is the stock function; never while a character is in the game (a late error
  -- box or timer of the login)
  origShow = EnterGame.show
  EnterGame.show = function(...)
    origShow(...)
    if (state.splash or g_game.isOnline()) and alive(enterGame) then
      enterGame:hide()
    end
    syncVisibility()   -- also puts the medallions back above the window (the stock show raises the window)
  end
  connect(g_game, { onGameStart = onGameStart })

  if shouldSplash() then
    startSplash()
  else
    syncVisibility()
  end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart })
  try(unhookSchedule)
  removeEvent(animEvent)
  removeEvent(fadeEvent)
  if ChaosLogin and ChaosLogin.statusEvent then removeEvent(ChaosLogin.statusEvent) end
  if EnterGame and origShow then EnterGame.show = origShow end
  if alive(bg) then bg.onMousePress = nil end
  for _, m in ipairs(moved) do
    if alive(m[1]) and alive(m[2]) then m[1]:setParent(m[2]) end
  end
  if LoginScene then try(LoginScene.destroy) end
  for _, w in ipairs({ medL, medR, crestT, crestB, logo, glowW, emberLayer, sparkLayer, pressW, spinner, splashW,
                       verLabel, statusLabel, statusDot, serverCaption, sceneLink, langLink }) do
    if alive(w) then w:destroy() end
  end
  ChaosLogin = nil
end
