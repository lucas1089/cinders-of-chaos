-- Chaos theme: imports the shared Chaos* styles as early as possible so every
-- other module (client_chaos_topbar, game_*, ...) can use them in its .otui.
--
-- OTUI has no variables, so the palette is written once in styles.otui (header
-- comment) and mirrored here for Lua code that needs the same colours.

ChaosTheme = {
  palette = {
    bg          = '#0d0b0e',
    iron        = '#3a3339',
    ironLight   = '#7d7176',
    text        = '#d6c9ae',
    textDim     = '#8c8070',
    textDisabled= '#6b6258',
    gold        = '#e8b84a',
    goldBright  = '#f6cf72',
    blood       = '#b8160f',
    bloodBright = '#e03a1e',
    bloodDark   = '#5a0a0a',
    health      = '#8a1010',
    mana        = '#1f3f8f',
  },
  imagePath = '/images/chaos/',
}

-- Widget helpers some of our modules were written against; this engine does not ship them.
local function installWidgetHelpers()
  -- "[color=#rrggbb]text[/color]" markup -> the engine's coloured text {text, colour, text, colour, ...}
  if not UIWidget.parseColoredText then
    UIWidget.parseColoredText = function(self, text, defaultColor)
      defaultColor = defaultColor or '#ffffff'
      local parts, pos = {}, 1
      text = tostring(text or '')
      while true do
        local s, e, color, inner = text:find('%[color=(#?%x+)%](.-)%[/color%]', pos)
        if not s then break end
        if s > pos then
          parts[#parts + 1] = text:sub(pos, s - 1)
          parts[#parts + 1] = defaultColor
        end
        parts[#parts + 1] = inner
        parts[#parts + 1] = color
        pos = e + 1
      end
      if pos <= #text then
        parts[#parts + 1] = text:sub(pos)
        parts[#parts + 1] = defaultColor
      end
      if self.setColoredText then
        self:setColoredText(parts)
      else
        self:setText((text:gsub('%[/?color[^%]]*%]', '')))
      end
    end
  end

  -- rich tooltip (title + list of lines) -> plain multi-line tooltip
  if not UIWidget.setExtendedTooltip then
    UIWidget.setExtendedTooltip = function(self, title, texts, style)
      self.extendedTooltip = { title = title, texts = texts, style = style }
      local lines = { tostring(title or '') }
      if type(texts) == 'table' then
        for _, line in ipairs(texts) do
          lines[#lines + 1] = type(line) == 'table' and tostring(line.text or line[1] or '') or tostring(line)
        end
      elseif texts then
        lines[#lines + 1] = tostring(texts)
      end
      self:setTooltip(table.concat(lines, '\n'))
    end
    UIWidget.removeExtendedTooltip = function(self)
      self.extendedTooltip = nil
      self:removeTooltip()
    end
    UIWidget.getExtendedTooltip = function(self)
      return self.extendedTooltip
    end
  end
  -- the rich tooltip controller of the same family; the plain tooltip above needs no control
  if not rawget(_G, 'g_extendedtooltip') then
    local noop = function() end
    rawset(_G, 'g_extendedtooltip', { init = noop, terminate = noop, show = noop, hide = noop })
  end
end

-- ---------------------------------------------------------------- window ornaments
-- Styles with `&chaosOrnate: true` (the skinned Window in data/styles/10-windows.otui) get gold corner
-- pieces and a crest. They are phantom children added after the window's own children (next frame),
-- so `prev` anchors and child indexes of the window's own layout are not affected.
local SKIN = '/images/chaos/skin/'
local ORN_SIZE = 44      -- corner piece size; its gem sits at (14, 14)
local ORN_INSET = 8      -- how far the piece sticks out of the window
local CREST_W, CREST_H, CREST_UP = 84, 30, 17

local function addOrnament(win, id, image, w, h, hEdge, vEdge, mx, my)
  local o = g_ui.createWidget('UIWidget', win)
  o:setId(id)
  o:setImageSource(image)
  o:setSize({ width = w, height = h })
  o:setPhantom(true)
  o:setFocusable(false)
  -- anchoring to the parent uses its padding rect, so take the padding back out
  if hEdge == AnchorLeft then
    o:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    o:setMarginLeft(mx - win:getPaddingLeft())
  elseif hEdge == AnchorRight then
    o:addAnchor(AnchorRight, 'parent', AnchorRight)
    o:setMarginRight(mx - win:getPaddingRight())
  else
    o:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    o:setMarginLeft((win:getPaddingRight() - win:getPaddingLeft()))
  end
  if vEdge == AnchorTop then
    o:addAnchor(AnchorTop, 'parent', AnchorTop)
    o:setMarginTop(my - win:getPaddingTop())
  else
    o:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    o:setMarginBottom(my - win:getPaddingBottom())
  end
  return o
end

local function updateOrnaments(win)
  local crest = win:getChildById('chaosOrnCrest')
  if crest then
    crest:setVisible(win:getWidth() >= 170)
  end
  local small = win:getWidth() < 90 or win:getHeight() < 70
  for _, id in ipairs({ 'chaosOrnTL', 'chaosOrnTR', 'chaosOrnBL', 'chaosOrnBR' }) do
    local o = win:getChildById(id)
    if o then o:setVisible(not small) end
  end
end

function ChaosTheme.decorateWindow(win)
  if not win or win:isDestroyed() or win.chaosDecorated then return end
  win.chaosDecorated = true
  local s, i = ORN_SIZE, -(tonumber(win.chaosOrnInset) or ORN_INSET)
  local crestUp = tonumber(win.chaosCrestUp) or CREST_UP
  addOrnament(win, 'chaosOrnTL', SKIN .. 'orn_corner_tl', s, s, AnchorLeft, AnchorTop, i, i)
  addOrnament(win, 'chaosOrnTR', SKIN .. 'orn_corner_tr', s, s, AnchorRight, AnchorTop, i, i)
  addOrnament(win, 'chaosOrnBL', SKIN .. 'orn_corner_bl', s, s, AnchorLeft, AnchorBottom, i, i)
  addOrnament(win, 'chaosOrnBR', SKIN .. 'orn_corner_br', s, s, AnchorRight, AnchorBottom, i, i)
  addOrnament(win, 'chaosOrnCrest', SKIN .. 'orn_crest', CREST_W, CREST_H, nil, AnchorTop, 0, -crestUp)
  connect(win, { onGeometryChange = updateOrnaments })
  updateOrnaments(win)
end

local TITLE_COLOR = '#e8c477'

local function onStyleApply(widget, styleName, styleNode)
  if not widget.chaosOrnate then return end
  -- many window styles of the base modules move the title for the old 17 px title bar and paint it grey:
  -- keep it centred on the skin's title plate, in gold
  local ty = tonumber(widget.chaosTitleY)
  if ty then
    local off = widget:getTextOffset()
    if off.y ~= ty then
      widget:setTextOffset({ x = off.x, y = ty })
    end
    widget:setColor(TITLE_COLOR)
  end
  if not widget.chaosDecorated and not widget.chaosDecorPending then
    widget.chaosDecorPending = true
    addEvent(function()
      if not widget:isDestroyed() and widget.chaosOrnate then
        ChaosTheme.decorateWindow(widget)
      end
    end)
  end
end

local function decorateExisting(widget)
  for _, child in ipairs(widget:getChildren()) do
    if child.chaosOrnate then
      ChaosTheme.decorateWindow(child)
    end
    decorateExisting(child)
  end
end

-- ---------------------------------------------------------------- tooltips
-- corelib paints the tooltip label light grey with dark text after every display call; repaint it as a
-- dark gold-rimmed plate. Coloured (table) tooltips keep their own colours.
local tooltipWrapped = {}

local function skinTooltip()
  local label = rootWidget and rootWidget:getChildById('toolTip')
  if not label then return end
  label:setBackgroundColor('#00000000')
  label:setBorderWidth(0)
  label:setImageSource(SKIN .. 'tooltip')
  label:setImageBorder(4)
  label:setColor('#e4d8c0')
  label:resize(label:getWidth() + 8, label:getHeight() + 4)
  label:setTextOffset({ x = 7, y = 4 })
end

local function wrapTooltip()
  if not g_tooltip then return end
  for _, name in ipairs({ 'display', 'displayText', 'parseColoreDisplay' }) do
    local orig = g_tooltip[name]
    if type(orig) == 'function' and not tooltipWrapped[name] then
      tooltipWrapped[name] = orig
      g_tooltip[name] = function(...)
        local r = orig(...)
        skinTooltip()
        return r
      end
    end
  end
end

local function unwrapTooltip()
  if not g_tooltip then return end
  for name, orig in pairs(tooltipWrapped) do
    g_tooltip[name] = orig
  end
  tooltipWrapped = {}
end

function init()
  wrapTooltip()
  g_ui.importStyle('styles')
  g_ui.importStyle('compat')
  installWidgetHelpers()
  connect(UIWidget, { onStyleApply = onStyleApply })
  decorateExisting(rootWidget)
end

function terminate()
  disconnect(UIWidget, { onStyleApply = onStyleApply })
  unwrapTooltip()
  ChaosTheme = nil
end

-- Convenience: apply the chaos look to an existing widget tree at runtime.
-- Only changes image/colour properties; never touches layout.
function ChaosTheme.skinWindow(window)
  if not window then return end
  window:setImageSource(ChaosTheme.imagePath .. 'window')
  window:setImageBorder(18)
  window:setImageBorderTop(34)
  window:setColor(ChaosTheme.palette.gold)
end
