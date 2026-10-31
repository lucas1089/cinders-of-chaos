-- RmlUi form layer (docs/RMLUI_SPIKE.md, phase 4): what the Options window (client_chaos_rmloptions) and the window mirror
-- (client_chaos_rmlmirror) share. It reads an OTUI widget tree (check boxes, sliders, combo boxes, buttons, labels, text
-- fields, lists, tab bars, progress bars, icons, help icons, panels, tooltips), writes RML for it and keeps both sides in
-- step: a change in RmlUi goes through the OTUI widget's own click or setter, so the module behind the window runs as
-- before.
-- Pure parts (collect, rml, wantedValue, the text conversion) take the widget API only and are unit tested with mocks.
-- Only a client built with -DCHAOS_RMLUI=ON has g_rml; without it nothing here touches the engine.

ChaosRmlForm = ChaosRmlForm or {}
local M = ChaosRmlForm

M.FONTS = '/modules/client_chaos_rmltest/fonts/'
M.SKIN = '/modules/client_chaos_rmlform/skin.rcss'

-- widget classes the layer can draw; any other class in a window (items, creatures, the map, tables...) keeps that
-- window in OTUI. Containers are walked, their children drawn.
M.KNOWN = {
  UIWidget = true, UIWindow = true, UIMessageBox = true, UIInputBox = true, UIScrollArea = true, UITabBar = true,
  UILabel = true, UIButton = true, UICheckBox = true, UIComboBox = true, UIScrollBar = true, UITextEdit = true,
  UISpinBox = true, UIProgressBar = true, UIResizeBorder = true, UIRadioGroup = true,
}

local function textOf(w)
  local t = w.getText and w:getText() or ''
  return t ~= nil and tostring(t) or ''
end
M.textOf = textOf

local function classOf(w)
  return w.getClassName and w:getClassName() or 'UIWidget'
end

local function imageOf(w)
  local src = w.getImageSource and w:getImageSource()
  if type(src) ~= 'string' or src == '' then return nil end
  local clip = w.getImageClip and w:getImageClip()
  local size = w.getSize and w:getSize()
  return {
    src = src,
    clip = (clip and (clip.width or 0) > 0) and { clip.x, clip.y, clip.width, clip.height } or nil,
    w = size and size.width or 0, h = size and size.height or 0,
  }
end

-- a list: a TextList (or any scroll area the module listens to for the focused child); its children are its rows
local function isList(w)
  return classOf(w) == 'UIScrollArea' and (w.getStyleName and w:getStyleName() == 'TextList' or w.onChildFocusChange ~= nil)
end

-- The controls of a widget tree in reading order. Kinds: group/endgroup (a FlatPanel), list/endlist, row/endrow (a list
-- child), tabs/tab/endtabs (a TabBar), label, para (text with line breaks), check, range, select, button, input, progress, image, sep, help.
-- Returns items and the classes it could not draw (sorted, unique); a non-empty list means "leave this window in OTUI".
function M.collect(root)
  local items, unsupported, seen = {}, {}, {}
  local function add(item)
    -- the widget's tooltip, shown in RmlUi while the mouse is over its element
    local tip = item.widget and item.kind ~= 'help' and item.widget.getTooltip and item.widget:getTooltip()
    if type(tip) == 'string' and tip ~= '' then item.tip = tip end
    items[#items + 1] = item
  end
  local function walk(w, inRow)
    for _, c in ipairs(w:getChildren()) do
      -- a widget a module hid with opacity 0 (moved away, faded out) is not drawn either
      -- the theme's corner pieces and crest (client_chaos_theme) are window furniture the skin draws itself
      if c:isExplicitlyVisible() and (not c.getOpacity or c:getOpacity() > 0) and not tostring(c:getId()):find('^chaosOrn') then
        local cls = classOf(c)
        if not M.KNOWN[cls] then
          if not seen[cls] then seen[cls] = true unsupported[#unsupported + 1] = cls end
        elseif cls == 'UICheckBox' then
          add({ kind = 'check', widget = c, text = textOf(c) })
        elseif cls == 'UIComboBox' then
          local opts = {}
          for i, o in ipairs(c.options or {}) do opts[i] = tostring(o.text) end
          add({ kind = 'select', widget = c, options = opts })
        elseif cls == 'UIScrollBar' then
          if c:getOrientation() ~= 'vertical' then
            add({ kind = 'range', widget = c, min = c:getMinimum() or 0, max = c:getMaximum() or 0 })
          end
        elseif cls == 'UIButton' then
          if textOf(c) ~= '' then
            add({ kind = 'button', widget = c, text = textOf(c) })
          else
            local img = imageOf(c)
            if img then add({ kind = 'button', widget = c, text = '', image = img }) end
          end
        elseif cls == 'UILabel' then
          local t = textOf(c)
          if t ~= '' then add({ kind = t:find('\n', 1, true) and 'para' or 'label', widget = c, text = t }) end
        elseif cls == 'UITextEdit' or cls == 'UISpinBox' then
          add({ kind = 'input', widget = c, password = c.isTextHidden and c:isTextHidden() or false,
                multiline = c.isMultiline and c:isMultiline() or false })
        elseif cls == 'UIProgressBar' then
          add({ kind = 'progress', widget = c })
        elseif cls == 'UITabBar' then
          -- its tab buttons (the current panel lies in the content widget the module set, read where it is)
          local tabs = c.tabs
          if type(tabs) ~= 'table' or #tabs == 0 then
            local bp = c.buttonsPanel or (c.getChildById and c:getChildById('buttonsPanel'))
            tabs = bp and bp:getChildren() or {}
          end
          add({ kind = 'tabs', widget = c })
          for _, t in ipairs(tabs) do
            if t:isExplicitlyVisible() then add({ kind = 'tab', widget = t, text = textOf(t) }) end
          end
          add({ kind = 'endtabs' })
        elseif cls == 'UIResizeBorder' or cls == 'UIRadioGroup' then
          -- window furniture
        elseif isList(c) then
          add({ kind = 'list', widget = c })
          for _, row in ipairs(c:getChildren()) do
            if row:isExplicitlyVisible() then
              add({ kind = 'row', widget = row, list = c, text = row:getChildCount() == 0 and textOf(row) or '' })
              if row:getChildCount() > 0 then walk(row, true) end
              add({ kind = 'endrow' })
            end
          end
          add({ kind = 'endlist' })
        elseif c:getChildCount() == 0 then
          local tip = c.getTooltip and c:getTooltip()
          local style = c.getStyleName and c:getStyleName() or ''
          if type(tip) == 'string' and tip ~= '' and textOf(c) == '' then
            add({ kind = 'help', text = tip })
          elseif textOf(c) ~= '' then
            local t = textOf(c)
            add({ kind = t:find('\n', 1, true) and 'para' or 'label', widget = c, text = t })
          elseif style == 'HorizontalSeparator' then
            if not inRow then add({ kind = 'sep' }) end
          else
            local img = imageOf(c)
            -- an icon, not a background or a frame: small, drawn from a clip or a file of its own
            if img and img.w > 0 and img.w <= 64 and img.h > 0 and img.h <= 64 then add({ kind = 'image', widget = c, image = img }) end
          end
        else
          local group = not inRow and c.getStyleName and c:getStyleName() == 'FlatPanel'
          if group then add({ kind = 'group' }) end
          walk(c, inRow)
          if group then add({ kind = 'endgroup' }) end
        end
      end
    end
  end
  walk(root, false)
  table.sort(unsupported)
  return items, unsupported
end

local function imgRml(img, escape)
  local rect = img.clip and string.format(' rect="%d %d %d %d"', img.clip[1], img.clip[2], img.clip[3], img.clip[4]) or '' -- i18n-ok: markup
  local w = (img.clip and img.clip[3]) or img.w
  local h = (img.clip and img.clip[4]) or img.h
  if img.w > 0 then w, h = img.w, img.h end
  return string.format('<img src="%s"%s style="width: %ddp; height: %ddp;"/>', escape(img.src), rect, w, h) -- i18n-ok: markup
end

-- RML of the items. Controls get the ids c<N> (items[N].el), help icons h<N> with their text in t<N>. Loose items at the
-- top level (outside any panel or list) go into rows of their own like a panel. Pure: escape comes in.
function M.rml(items, escape)
  local out, helps = {}, {}
  local depth, loose, pair = 0, false, false
  local function push(s) out[#out + 1] = s end
  local function endLoose()
    if not loose then return end
    push('</div>') -- i18n-ok: markup
    for _, h in ipairs(helps) do push(h) end
    helps, loose = {}, false
  end
  for n, it in ipairs(items) do
    local id = 'c' .. n
    local k = it.kind
    if k == 'group' then
      endLoose()
      push('<div class="group">') -- i18n-ok: markup
      depth = depth + 1
    elseif k == 'endgroup' then
      push('</div>') -- i18n-ok: markup
      for _, h in ipairs(helps) do push(h) end
      helps = {}
      depth = depth - 1
    elseif k == 'list' then
      endLoose()
      it.el = id
      push(string.format('<div class="list" id="%s">', id)) -- i18n-ok: markup
      depth = depth + 1
    elseif k == 'endlist' then
      push('</div>') -- i18n-ok: markup
      depth = depth - 1
    elseif k == 'tabs' then
      endLoose()
      push('<div class="tabs">') -- i18n-ok: markup
      depth = depth + 1
    elseif k == 'endtabs' then
      push('</div>') -- i18n-ok: markup
      depth = depth - 1
    elseif k == 'tab' then
      it.el = id
      push(string.format('<button class="tab" id="%s">%s</button>', id, escape(it.text))) -- i18n-ok: markup
    elseif k == 'row' then
      it.el = id
      -- text in a span: a flex box draws no loose text
      local t = (it.text or '') ~= '' and string.format('<span>%s</span>', escape(it.text)) or '' -- i18n-ok: markup
      push(string.format('<div class="row" id="%s">%s', id, t)) -- i18n-ok: markup
      depth = depth + 1
    elseif k == 'endrow' then
      push('</div>') -- i18n-ok: markup
      depth = depth - 1
    else
      if depth == 0 and not loose then
        push('<div class="group loose">') -- i18n-ok: markup
        loose = true
      end
      local nextKind = items[n + 1] and items[n + 1].kind
      if k == 'label' and (nextKind == 'range' or nextKind == 'select' or nextKind == 'input') then
        -- a label and the control it names share one full row
        it.el = id
        push(string.format('<div class="pair"><span class="lbl" id="%s">%s</span>', id, escape(it.text))) -- i18n-ok: markup
        pair = true
      elseif k == 'label' then
        it.el = id
        push(string.format('<span class="lbl" id="%s">%s</span>', id, escape(it.text))) -- i18n-ok: markup
      elseif k == 'para' then
        it.el = id
        push(string.format('<p class="para" id="%s">%s</p>', id, (escape(it.text):gsub('\n', '<br/>')))) -- i18n-ok: markup
      elseif k == 'check' then
        it.el = id
        push(string.format('<label class="check"><input type="checkbox" id="%s"/><span id="%sl">%s</span></label>', -- i18n-ok: markup
          id, id, escape(it.text)))
      elseif k == 'range' then
        it.el = id
        push(string.format('<input type="range" id="%s" min="%d" max="%d" step="1"/>', id, it.min, it.max)) -- i18n-ok: markup
      elseif k == 'select' then
        it.el = id
        local opts = {}
        for i, o in ipairs(it.options) do
          opts[#opts + 1] = string.format('<option value="%d">%s</option>', i, escape(o)) -- i18n-ok: markup
        end
        push(string.format('<select id="%s">%s</select>', id, table.concat(opts))) -- i18n-ok: markup
      elseif k == 'input' then
        it.el = id
        if it.multiline then
          push(string.format('<textarea class="field" id="%s" rows="4"></textarea>', id)) -- i18n-ok: markup
        else
          push(string.format('<input class="field" type="%s" id="%s"/>', it.password and 'password' or 'text', id)) -- i18n-ok: markup
        end
      elseif k == 'progress' then
        it.el = id
        push(string.format('<div class="progress" id="%s"><div class="fill" id="%sf"></div><span class="ptext" id="%st"></span></div>', -- i18n-ok: markup
          id, id, id))
      elseif k == 'image' then
        push(imgRml(it.image, escape))
      elseif k == 'sep' then
        push('<div class="hsep"></div>') -- i18n-ok: markup
      end
      if pair and (k == 'range' or k == 'select' or k == 'input') then
        push('</div>') -- i18n-ok: markup
        pair = false
      end
      if k == 'button' then
        it.el = id
        if it.image then
          push(string.format('<button class="act icon" id="%s">%s</button>', id, imgRml(it.image, escape))) -- i18n-ok: markup
        else
          push(string.format('<button class="act" id="%s">%s</button>', id, escape(it.text))) -- i18n-ok: markup
        end
      elseif k == 'help' then
        push(string.format('<span class="help" id="h%d"></span>', n)) -- i18n-ok: markup
        helps[#helps + 1] = string.format('<div class="helptext" id="t%d">%s</div>', n, -- i18n-ok: markup
          (escape(it.text):gsub('\n', '<br/>')))
      end
    end
  end
  endLoose()
  return table.concat(out)
end

-- A widget reaches Lua as a new userdata each time (tostring and table keys differ), so it is known by a number kept in
-- its Lua fields.
local lastKey = 0
function M.keyOf(w)
  local k = w.chaosRmlKey
  if not k then
    lastKey = lastKey + 1
    k = lastKey
    w.chaosRmlKey = k
  end
  return k
end

-- The shape of a tree: kinds and widgets in order. A window is drawn again only when this changes (a panel shown or
-- hidden, rows added), so a refresh never resets a scroll position or a field being typed in.
function M.signature(items)
  local parts = {}
  for i, it in ipairs(items) do
    parts[i] = it.kind .. (it.kind == 'select' and #it.options or '') .. (it.widget and ('#' .. M.keyOf(it.widget)) or '')
  end
  return table.concat(parts, ';')
end

-- what a "change" event of an RML control means for the OTUI widget: nil = nothing to do (already equal, or a change
-- the sync itself made). Pure: the value comes in as RmlUi gives it (a string, UTF-8).
function M.wantedValue(item, rmlChecked, rmlValue)
  local w = item.widget
  if item.kind == 'check' then
    if w:isChecked() ~= rmlChecked then return rmlChecked end
  elseif item.kind == 'range' then
    local v = tonumber(rmlValue)
    if v then
      v = math.floor(v + 0.5)
      if v ~= w:getValue() then return v end
    end
  elseif item.kind == 'select' then
    local i = tonumber(rmlValue)
    if i and i ~= w.currentIndex then return i end
  elseif item.kind == 'input' then
    local t = M.toCp1252(rmlValue or '')
    if t ~= textOf(w) then return t end
  end
  return nil
end

-- engine text is cp1252, RmlUi keeps UTF-8 ------------------------------------------------------------------------------
local CP = { [0x80] = 0x20AC, [0x82] = 0x201A, [0x83] = 0x0192, [0x84] = 0x201E, [0x85] = 0x2026, [0x86] = 0x2020,
  [0x87] = 0x2021, [0x88] = 0x02C6, [0x89] = 0x2030, [0x8A] = 0x0160, [0x8B] = 0x2039, [0x8C] = 0x0152, [0x8E] = 0x017D,
  [0x91] = 0x2018, [0x92] = 0x2019, [0x93] = 0x201C, [0x94] = 0x201D, [0x95] = 0x2022, [0x96] = 0x2013, [0x97] = 0x2014,
  [0x98] = 0x02DC, [0x99] = 0x2122, [0x9A] = 0x0161, [0x9B] = 0x203A, [0x9C] = 0x0153, [0x9E] = 0x017E, [0x9F] = 0x0178 }
local BACK = {}
for b, cp in pairs(CP) do BACK[cp] = b end

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

function M.toUtf8(s)
  return (tostring(s or ''):gsub('[\128-\255]', function(c)
    local b = c:byte()
    return utf8char(CP[b] or b)
  end))
end

-- UTF-8 to cp1252: a character cp1252 does not have becomes '?'
function M.toCp1252(s)
  s = tostring(s or '')
  local out, i, n = {}, 1, #s
  while i <= n do
    local b = s:byte(i)
    local cp, len
    if b < 0x80 then cp, len = b, 1
    elseif b >= 0xF0 then cp, len = -1, 4
    elseif b >= 0xE0 then cp, len = ((b % 16) * 4096) + ((s:byte(i + 1) or 128) % 64) * 64 + ((s:byte(i + 2) or 128) % 64), 3
    elseif b >= 0xC0 then cp, len = ((b % 32) * 64) + ((s:byte(i + 1) or 128) % 64), 2
    else cp, len = -1, 1 end
    if cp >= 0 and cp < 0x80 then out[#out + 1] = string.char(cp)
    elseif BACK[cp] then out[#out + 1] = string.char(BACK[cp])
    elseif cp >= 0xA0 and cp <= 0xFF then out[#out + 1] = string.char(cp)
    else out[#out + 1] = '?' end
    i = i + len
  end
  return table.concat(out)
end

-- engine side ----------------------------------------------------------------------------------------------------------

function M.available()
  return g_rml ~= nil and g_rml.init() and g_rml.getValue ~= nil
end

-- fonts once per client run
function M.loadFonts()
  if M.fontsLoaded then return end
  M.fontsLoaded = true
  g_rml.loadFont(M.FONTS .. 'AlegreyaSans-Medium.ttf', true)
  g_rml.loadFont(M.FONTS .. 'AlegreyaSC-Bold.ttf', false)
end

-- one event callback for every RmlUi document: each module listens to its own documents
M.listeners = M.listeners or {}
local function route(docId, elementId, eventType)
  local fn = M.listeners[docId]
  if fn then fn(elementId, eventType) end
end
function M.listen(doc, fn)
  M.listeners[doc] = fn
  g_rml.setEventCallback(route)
end
function M.unlisten(doc)
  M.listeners[doc] = nil
end

-- A form: one OTUI tree drawn into one element of an RmlUi document and kept in step with it.
--   local f = ChaosRmlForm.newForm(doc, 'content', rootWidget, { onEnter = fn, onEscape = fn })
--   f:build()  f:refresh()  f:handle(elementId, eventType) -> true when the event was the form's
local Form = {}
Form.__index = Form

function M.newForm(doc, elementId, root, hooks)
  return setmetatable({ doc = doc, el = elementId, root = root, hooks = hooks or {}, items = {}, sig = '', open = {} }, Form)
end

function Form:build(items)
  local unsupported
  if not items then items, unsupported = M.collect(self.root) end
  self.items, self.sig, self.open = items, M.signature(items), {}
  self:hideTip()
  g_rml.setInnerRml(self.doc, self.el, M.rml(items, g_rml.escape))
  self:refresh()
  return unsupported
end

local function setText(self, it, text)
  if it.lastText == text then return end
  it.lastText = text
  g_rml.setText(self.doc, it.el, text)
end

function Form:refresh()
  local doc = self.doc
  for _, it in ipairs(self.items) do
    local w, el = it.widget, it.el
    if w and el and not (w.isDestroyed and w:isDestroyed()) then
      local k = it.kind
      if k == 'check' then
        g_rml.setChecked(doc, el, w:isChecked())
        if it.lastText ~= textOf(w) then it.lastText = textOf(w) g_rml.setText(doc, el .. 'l', textOf(w)) end
      elseif k == 'range' then
        g_rml.setValue(doc, el, tostring(w:getValue()))
      elseif k == 'select' then
        g_rml.setValue(doc, el, tostring(w.currentIndex))
      elseif k == 'input' then
        local v = M.toUtf8(textOf(w))
        if it.lastValue ~= v then
          it.lastValue = v
          g_rml.setValue(doc, el, v)
        end
      elseif k == 'label' or k == 'tab' or (k == 'button' and not it.image) then
        setText(self, it, textOf(w))
      elseif k == 'para' then
        local t = textOf(w)
        if it.lastText ~= t then
          it.lastText = t
          g_rml.setInnerRml(doc, el, (g_rml.escape(t):gsub('\n', '<br/>')))
        end
      elseif k == 'progress' then
        local p = w.getPercent and w:getPercent() or 0
        g_rml.setProperty(doc, el .. 'f', 'width', string.format('%d%%', math.max(0, math.min(100, math.floor(p + 0.5)))))
        local t = textOf(w)
        if it.lastText ~= t then it.lastText = t g_rml.setText(doc, el .. 't', t) end
      elseif k == 'row' then
        local focused = it.list.getFocusedChild and it.list:getFocusedChild() == w
        g_rml.setClass(doc, el, 'on', focused or false)
      end
      if k ~= 'label' and k ~= 'para' and k ~= 'row' and k ~= 'progress' then g_rml.setDisabled(doc, el, not w:isEnabled()) end
      if k ~= 'row' then g_rml.setClass(doc, el, 'off', not w:isEnabled()) end
      if k == 'button' then g_rml.setClass(doc, el, 'on', (w.isOn and w:isOn()) or (w.isChecked and w:isChecked()) or false) end
      if k == 'tab' then g_rml.setClass(doc, el, 'on', (w.isChecked and w:isChecked()) or false) end
    end
  end
end

-- the tree changed shape (a panel shown, rows added): draw it again
function Form:changed()
  local items = M.collect(self.root)
  if M.signature(items) ~= self.sig then
    self:build(items)
    return true
  end
  return false
end

local function itemOf(self, elementId)
  local n = tonumber(elementId:match('^c(%d+)$') or '')
  return n and self.items[n], n
end

-- Pure: the item whose element (or one of its parts: c<N>l the text of a check box, c<N>f / c<N>t the bar and text of a
-- progress bar) the id names, if it has a tooltip.
function M.tipItem(items, elementId)
  local n = tonumber(tostring(elementId):match('^c(%d+)[lft]?$') or '')
  local it = n and items[n]
  if it and it.tip then return it end
end

-- Pure: where a tooltip goes, in document pixels: under the element, kept on the screen (width = the screen's).
M.TIP_MAX_W = 300
function M.tipPos(rect, width, height)
  local x = math.max(0, math.min(rect.x, (width or 0) - M.TIP_MAX_W - 4))
  local y = rect.y + rect.height + 4
  if height and y + 40 > height then y = math.max(0, rect.y - 44) end
  return x, y
end

-- The tooltip lives in the document's element "tip" (a document without one shows none).
function Form:showTip(it)
  local doc = self.doc
  local r = g_rml.getRect(doc, it.el)
  if not r or r.width == 0 then return end
  local root = g_ui and g_ui.getRootWidget and g_ui.getRootWidget()
  local x, y = M.tipPos(r, root and root:getWidth(), root and root:getHeight())
  self.tipFor = it.el
  g_rml.setInnerRml(doc, 'tip', (g_rml.escape(it.tip):gsub('\n', '<br/>')))
  g_rml.setProperty(doc, 'tip', 'left', x .. 'px')
  g_rml.setProperty(doc, 'tip', 'top', y .. 'px')
  g_rml.setClass(doc, 'tip', 'on', true)
end

function Form:hideTip()
  if not self.tipFor then return end
  self.tipFor = nil
  g_rml.setClass(self.doc, 'tip', 'on', false)
end

function Form:handle(elementId, eventType)
  local doc = self.doc
  if eventType == 'mouseover' then
    local it = M.tipItem(self.items, elementId)
    if it then
      if self.tipFor ~= it.el then self:showTip(it) end
    else
      self:hideTip()
    end
    return true
  elseif eventType == 'mouseout' then
    -- leaving for a child of the same element sends a mouseover for it right after
    self:hideTip()
    return true
  elseif eventType == 'enter' then
    if self.hooks.onEnter then self.hooks.onEnter() end
    return true
  elseif eventType == 'escape' then
    if self.hooks.onEscape then self.hooks.onEscape() end
    return true
  end
  local help = elementId:match('^h(%d+)$')
  if help and eventType == 'click' then
    local t = 't' .. help
    self.open[t] = not self.open[t]
    g_rml.setClass(doc, t, 'open', self.open[t])
    return true
  end
  local it = itemOf(self, elementId)
  if not it or not it.widget then return false end
  local w = it.widget
  if eventType == 'change' then
    local want = M.wantedValue(it, g_rml.isChecked(doc, it.el), g_rml.getValue(doc, it.el))
    if want == nil then return true end
    if not w:isEnabled() then self:refresh() return true end
    if it.kind == 'check' then
      -- a click as on the OTUI box: its own onClick (a radio group, a custom handler) or the toggle
      if w.onClick then signalcall(w.onClick, w) else w:setChecked(want) end
    elseif it.kind == 'range' then
      w:setValue(want)
    elseif it.kind == 'select' then
      w:setCurrentIndex(want)
    elseif it.kind == 'input' then
      it.lastValue = g_rml.getValue(doc, it.el)
      w:setText(want)
    end
  elseif eventType == 'click' then
    if (it.kind == 'button' or it.kind == 'tab') and w:isEnabled() then
      signalcall(w.onClick, w)
    elseif it.kind == 'row' then
      it.list:focusChild(w, MouseFocusReason or 0)
      if w.onClick then signalcall(w.onClick, w) end
    else
      return true
    end
  elseif eventType == 'dblclick' then
    if it.kind == 'row' and w.onDoubleClick then
      signalcall(w.onDoubleClick, w, w:getPosition())
    elseif it.kind == 'button' and w.onDoubleClick then
      signalcall(w.onDoubleClick, w, w:getPosition())
    else
      return true
    end
  else
    return false
  end
  self:refresh()
  if addEvent then addEvent(function() if self.alive ~= false then self:refresh() end end) end
  return true
end

function init() end
function terminate() end
