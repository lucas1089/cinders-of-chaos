-- Options window in RmlUi (docs/RMLUI_SPIKE.md, phase 3). The classic Options window (client_settings) stays the source of
-- truth: this window reads the controls of its pages (check boxes, sliders, combo boxes, buttons, labels) and drives them
-- through their own setters, so setTempOption, the auto apply and the saved settings work as before.
-- Only a client built with -DCHAOS_RMLUI=ON has g_rml; without it this module does nothing and Options opens the classic window.
--   ChaosRmlOptions.open([pageId])  /  .close()  /  .openClassic([pageId])

ChaosRmlOptions = ChaosRmlOptions or {}

local PATH = '/modules/client_chaos_rmloptions/'
local FONTS = '/modules/client_chaos_rmltest/fonts/'

-- the menu of client_settings, in its order; classic = hotkey pages (key capture and lists), opened in the classic window
ChaosRmlOptions.PAGES = {
  { id = 'controls', label = 'Controls' },
  { id = 'generalHotkeys', label = 'General Hotkeys', sub = true, classic = true },
  { id = 'actionsHotkeys', label = 'Action Bar Hotkeys', sub = true, classic = true },
  { id = 'customHotkeys', label = 'Custom Hotkeys', sub = true, classic = true },
  { id = 'interface', label = 'Interface' },
  { id = 'hud', label = 'HUD', sub = true },
  { id = 'console', label = 'Console', sub = true },
  { id = 'gameWindow', label = 'Game Window', sub = true },
  { id = 'actionsBars', label = 'Action Bars', sub = true },
  { id = 'graphics', label = 'Graphics' },
  { id = 'effects', label = 'Effects', sub = true },
  { id = 'misc', label = 'Misc.' },
  { id = 'gameplay', label = 'Gameplay', sub = true },
  { id = 'screenshot', label = 'Screenshot', sub = true },
}

local function pageOf(id)
  for _, p in ipairs(ChaosRmlOptions.PAGES) do
    if p.id == id then return p end
  end
end

local function textOf(w)
  local t = w.getText and w:getText() or ''
  return t ~= nil and tostring(t) or ''
end

-- The controls of one classic page, in reading order. Pure walk over the widget API (getChildren, getClassName,
-- getStyleName, isExplicitlyVisible, getText, getTooltip), so the test runs it on mock widgets. Kinds: group/endgroup
-- (a FlatPanel), label, check, range, select, button, help (a "?" icon with a tooltip).
function ChaosRmlOptions.collect(root)
  local items = {}
  local function add(item) items[#items + 1] = item end
  local function walk(w)
    for _, c in ipairs(w:getChildren()) do
      if c:isExplicitlyVisible() then
        local cls = c.getClassName and c:getClassName() or 'UIWidget'
        if cls == 'UICheckBox' then
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
          if textOf(c) ~= '' then add({ kind = 'button', widget = c, text = textOf(c) }) end
        elseif cls == 'UILabel' then
          if textOf(c) ~= '' then add({ kind = 'label', widget = c, text = textOf(c) }) end
        elseif cls == 'UITextList' then
          -- lists of the HUD page: classic window only
        elseif c:getChildCount() == 0 then
          local tip = c.getTooltip and c:getTooltip()
          if type(tip) == 'string' and tip ~= '' then
            add({ kind = 'help', text = tip })
          elseif textOf(c) ~= '' then
            add({ kind = 'label', widget = c, text = textOf(c) })
          end
        else
          local group = c.getStyleName and c:getStyleName() == 'FlatPanel'
          if group then add({ kind = 'group' }) end
          walk(c)
          if group then add({ kind = 'endgroup' }) end
        end
      end
    end
  end
  walk(root)
  return items
end

-- RML of one page. Controls get the ids c<N>, help icons h<N> with their text in t<N>; items[N].el is set to the id.
-- Loose items (outside any FlatPanel) go into rows of their own like a group. Pure: escape and the strings come in.
function ChaosRmlOptions.pageRml(items, escape)
  local out, helps = {}, {}
  local open, pair = false, false
  local function startGroup(loose)
    out[#out + 1] = loose and '<div class="group loose">' or '<div class="group">' -- i18n-ok: markup
    open = true
  end
  local function endGroup()
    if not open then return end
    out[#out + 1] = '</div>' -- i18n-ok: markup
    for _, h in ipairs(helps) do out[#out + 1] = h end
    helps, open = {}, false
  end
  for n, it in ipairs(items) do
    local id = 'c' .. n
    if it.kind == 'group' then
      endGroup()
      startGroup(false)
    elseif it.kind == 'endgroup' then
      endGroup()
    else
      if not open then startGroup(true) end
      local nextKind = items[n + 1] and items[n + 1].kind
      if it.kind == 'label' and (nextKind == 'range' or nextKind == 'select') then
        -- a label and the slider or combo box it names share one full row
        it.el = id
        out[#out + 1] = string.format('<div class="pair"><span class="lbl" id="%s">%s</span>', id, escape(it.text)) -- i18n-ok: markup
        pair = true
      elseif it.kind == 'label' then
        it.el = id
        out[#out + 1] = string.format('<span class="lbl" id="%s">%s</span>', id, escape(it.text)) -- i18n-ok: markup
      elseif it.kind == 'check' then
        it.el = id
        out[#out + 1] = string.format('<label class="check"><input type="checkbox" id="%s"/><span id="%sl">%s</span></label>', -- i18n-ok: markup
          id, id, escape(it.text))
      elseif it.kind == 'range' then
        it.el = id
        out[#out + 1] = string.format('<input type="range" id="%s" min="%d" max="%d" step="1"/>', id, it.min, it.max) -- i18n-ok: markup
      elseif it.kind == 'select' then
        it.el = id
        local opts = {}
        for i, o in ipairs(it.options) do
          opts[#opts + 1] = string.format('<option value="%d">%s</option>', i, escape(o)) -- i18n-ok: markup
        end
        out[#out + 1] = string.format('<select id="%s">%s</select>', id, table.concat(opts)) -- i18n-ok: markup
      end
      if pair and (it.kind == 'range' or it.kind == 'select') then
        out[#out + 1] = '</div>' -- i18n-ok: markup
        pair = false
      end
      if it.kind == 'button' then
        it.el = id
        out[#out + 1] = string.format('<button class="act" id="%s">%s</button>', id, escape(it.text)) -- i18n-ok: markup
      elseif it.kind == 'help' then
        out[#out + 1] = string.format('<span class="help" id="h%d">?</span>', n) -- i18n-ok: markup
        helps[#helps + 1] = string.format('<div class="helptext" id="t%d">%s</div>', n, -- i18n-ok: markup
          (escape(it.text):gsub('\n', '<br/>')))
      end
    end
  end
  endGroup()
  return table.concat(out)
end

-- The menu on the left: p_<id> buttons, sub pages indented, the current one marked. Pure.
function ChaosRmlOptions.navRml(pages, current, escape, translate)
  local out = {}
  for _, p in ipairs(pages) do
    local cls = 'nav' .. (p.sub and ' sub' or '') .. (p.id == current and ' on' or '') .. (p.classic and ' classic' or '')
    out[#out + 1] = string.format('<button class="%s" id="p_%s">%s</button>', cls, p.id, escape(translate(p.label))) -- i18n-ok: markup
  end
  return table.concat(out)
end

-- what a "change" event of the RML control means for the classic widget: nil = nothing to do (already equal, or a
-- change that the window itself made while syncing). Pure: the value comes in as RmlUi gives it (a string).
function ChaosRmlOptions.wantedValue(item, rmlChecked, rmlValue)
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
  end
  return nil
end

-- engine side ----------------------------------------------------------------------------------------------------------

local doc = 0
local current = nil
local items = {}

local function settings()
  return modules and modules.client_settings
end

function ChaosRmlOptions.available()
  return g_rml ~= nil and g_rml.init() and g_rml.getValue ~= nil and settings() ~= nil and settings().loadedWindows ~= nil
end

local function refresh()
  if doc == 0 then return end
  for _, it in ipairs(items) do
    local w, el = it.widget, it.el
    if w and el then
      if it.kind == 'check' then
        g_rml.setChecked(doc, el, w:isChecked())
        g_rml.setText(doc, el .. 'l', textOf(w))
      elseif it.kind == 'range' then
        g_rml.setValue(doc, el, tostring(w:getValue()))
      elseif it.kind == 'select' then
        g_rml.setValue(doc, el, tostring(w.currentIndex))
      elseif it.kind == 'label' or it.kind == 'button' then
        g_rml.setText(doc, el, textOf(w))
      end
      if it.kind ~= 'label' then g_rml.setDisabled(doc, el, not w:isEnabled()) end
      g_rml.setClass(doc, el, 'off', not w:isEnabled())
    end
  end
end

local function showPage(id)
  local page = pageOf(id)
  local root = page and settings().loadedWindows[id]
  if not root then return false end
  current = id
  items = ChaosRmlOptions.collect(root)
  g_rml.setInnerRml(doc, 'nav', ChaosRmlOptions.navRml(ChaosRmlOptions.PAGES, current, g_rml.escape, tr))
  g_rml.setText(doc, 'title', tr('Options') .. ' - ' .. tr(page.label))
  if page.classic then
    g_rml.setInnerRml(doc, 'content', string.format('<div class="classicnote">%s</div><button class="act primary" id="openclassic">%s</button>', -- i18n-ok: markup
      g_rml.escape(tr('Hotkeys are set in the classic window.')), g_rml.escape(tr('Open the classic window'))))
  else
    g_rml.setInnerRml(doc, 'content', ChaosRmlOptions.pageRml(items, g_rml.escape))
  end
  g_rml.setScrollTop(doc, 'content', 0)
  refresh()
  return true
end

local function onChange(n)
  local it = items[n]
  if not it or not it.widget then return end
  local want = ChaosRmlOptions.wantedValue(it, g_rml.isChecked(doc, it.el), g_rml.getValue(doc, it.el))
  if want == nil then return end
  local w = it.widget
  if not w:isEnabled() then return refresh() end
  if it.kind == 'check' then
    -- a click as on the classic box: its own onClick (a radio group, a custom handler) or the toggle
    if w.onClick then signalcall(w.onClick, w) else w:setChecked(want) end
  elseif it.kind == 'range' then
    w:setValue(want)
  elseif it.kind == 'select' then
    w:setCurrentIndex(want)
  end
  refresh()
  addEvent(refresh) -- options applied by a scheduled event change other controls a moment later
end

local function onEvent(docId, elementId, eventType)
  if docId ~= doc or doc == 0 then return end
  if eventType == 'change' then
    local n = tonumber(elementId:match('^c(%d+)$') or '')
    if n then onChange(n) end
    return
  end
  if eventType ~= 'click' then return end
  if elementId == 'x' or elementId == 'done' then
    ChaosRmlOptions.close()
  elseif elementId == 'classic' or elementId == 'openclassic' then
    ChaosRmlOptions.openClassic(current)
  elseif elementId:match('^p_') then
    local page = pageOf(elementId:sub(3))
    if page and page.id ~= current then showPage(page.id) end
  elseif elementId:match('^h%d+$') then
    local t = 't' .. elementId:sub(2)
    ChaosRmlOptions.helpOpen = ChaosRmlOptions.helpOpen or {}
    ChaosRmlOptions.helpOpen[t] = not ChaosRmlOptions.helpOpen[t]
    g_rml.setClass(doc, t, 'open', ChaosRmlOptions.helpOpen[t])
  else
    local n = tonumber(elementId:match('^c(%d+)$') or '')
    local it = n and items[n]
    if it and it.kind == 'button' and it.widget:isEnabled() then
      signalcall(it.widget.onClick, it.widget)
      refresh()
      addEvent(refresh)
    end
  end
end

function ChaosRmlOptions.isOpen()
  return doc ~= 0 and g_rml.isVisible(doc)
end

function ChaosRmlOptions.open(pageId)
  if not ChaosRmlOptions.available() then return false end
  if doc == 0 then
    g_rml.loadFont(FONTS .. 'AlegreyaSans-Medium.ttf', true)
    g_rml.loadFont(FONTS .. 'AlegreyaSC-Bold.ttf', false)
    doc = g_rml.loadDocument(PATH .. 'rmloptions.rml')
    if doc == 0 then return false end
    g_rml.setText(doc, 'classic', tr('Classic window'))
    g_rml.setText(doc, 'done', tr('Close'))
  end
  g_rml.setEventCallback(onEvent)
  ChaosRmlOptions.helpOpen = {}
  local id = pageId or current or 'controls'
  if not pageOf(id) then id = 'controls' end
  if not showPage(id) then return false end
  g_rml.show(doc)
  return true
end

function ChaosRmlOptions.close()
  if doc == 0 then return end
  g_rml.close(doc)
  doc, items = 0, {}
  -- applies what is still pending and saves, as the classic window's close does
  local cs = settings()
  if cs and cs.closeOptions then cs.closeOptions() end
end

function ChaosRmlOptions.openClassic(pageId)
  ChaosRmlOptions.close()
  local cs = settings()
  if not cs or not ChaosRmlOptions.original then return end
  -- the classic window only redirects to the hotkey pages under Controls; any other page opens it on Controls
  local page = pageId and pageOf(pageId)
  ChaosRmlOptions.original(cs, page and page.classic and pageId or nil)
end

-- client_settings opens its window through openOptions (the top menu button, the hotkeys, toggleShortcuts). The hook
-- sends it here; a hotkey page still opens the classic window.
local function hook()
  local cs = settings()
  if not cs or type(cs.openOptions) ~= 'function' then return false end
  if ChaosRmlOptions.hooked == cs.openOptions then return true end
  ChaosRmlOptions.original = cs.openOptions
  local wrapper = function(self, redirectId)
    local page = redirectId and pageOf(redirectId)
    if ChaosRmlOptions.available() and not (page and page.classic) then
      if ChaosRmlOptions.isOpen() and not redirectId then return ChaosRmlOptions.close() end
      if ChaosRmlOptions.open(redirectId) then return end
    end
    return ChaosRmlOptions.original(self, redirectId)
  end
  cs.openOptions = wrapper
  ChaosRmlOptions.hooked = wrapper
  return true
end

local hookTries = 0
local function tryHook()
  if hook() then return end
  hookTries = hookTries + 1
  if hookTries < 40 then scheduleEvent(tryHook, 250) end
end

function init()
  if not g_rml then return end
  hookTries = 0
  tryHook()
  if os.getenv and os.getenv('CHAOS_RMLOPTIONS') then
    -- scripted check (Xvfb): CHAOS_RMLOPTIONS="graphics" opens that page after the start
    scheduleEvent(function() ChaosRmlOptions.open(os.getenv('CHAOS_RMLOPTIONS')) end, 3000)
  end
end

function terminate()
  if not g_rml then return end
  ChaosRmlOptions.close()
  local cs = settings()
  if cs and ChaosRmlOptions.hooked and cs.openOptions == ChaosRmlOptions.hooked then
    cs.openOptions = ChaosRmlOptions.original
  end
  ChaosRmlOptions.hooked, ChaosRmlOptions.original = nil, nil
end
