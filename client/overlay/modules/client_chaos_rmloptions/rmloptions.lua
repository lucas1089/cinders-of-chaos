-- Options window in RmlUi (docs/RMLUI_SPIKE.md, phase 3). The classic Options window (client_settings) stays the source of
-- truth: this window reads the controls of its pages (check boxes, sliders, combo boxes, buttons, labels) and drives them
-- through their own setters, so setTempOption, the auto apply and the saved settings work as before.
-- Only a client built with -DCHAOS_RMLUI=ON has g_rml; without it this module does nothing and Options opens the classic window.
--   ChaosRmlOptions.open([pageId])  /  .close()  /  .openClassic([pageId])

ChaosRmlOptions = ChaosRmlOptions or {}

local PATH = '/modules/client_chaos_rmloptions/'

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

-- the page reading and drawing is the shared form layer (client_chaos_rmlform); these names stay for the test and callers
function ChaosRmlOptions.collect(root) return (ChaosRmlForm.collect(root)) end
function ChaosRmlOptions.pageRml(items, escape) return ChaosRmlForm.rml(items, escape) end
function ChaosRmlOptions.wantedValue(item, rmlChecked, rmlValue) return ChaosRmlForm.wantedValue(item, rmlChecked, rmlValue) end

-- The menu on the left: p_<id> buttons, sub pages indented, the current one marked. Pure.
function ChaosRmlOptions.navRml(pages, current, escape, translate)
  local out = {}
  for _, p in ipairs(pages) do
    local cls = 'nav' .. (p.sub and ' sub' or '') .. (p.id == current and ' on' or '') .. (p.classic and ' classic' or '')
    out[#out + 1] = string.format('<button class="%s" id="p_%s">%s</button>', cls, p.id, escape(translate(p.label))) -- i18n-ok: markup
  end
  return table.concat(out)
end

-- engine side ----------------------------------------------------------------------------------------------------------

local doc = 0
local current = nil
local form = nil

local function settings()
  return modules and modules.client_settings
end

function ChaosRmlOptions.available()
  return ChaosRmlForm ~= nil and ChaosRmlForm.available() and settings() ~= nil and settings().loadedWindows ~= nil
end

local function showPage(id)
  local page = pageOf(id)
  local root = page and settings().loadedWindows[id]
  if not root then return false end
  current = id
  g_rml.setInnerRml(doc, 'nav', ChaosRmlOptions.navRml(ChaosRmlOptions.PAGES, current, g_rml.escape, tr))
  g_rml.setText(doc, 'title', tr('Options') .. ' - ' .. tr(page.label))
  form = ChaosRmlForm.newForm(doc, 'content', root)
  if page.classic then
    form.items = {}
    g_rml.setInnerRml(doc, 'content', string.format('<div class="classicnote">%s</div><button class="act primary" id="openclassic">%s</button>', -- i18n-ok: markup
      g_rml.escape(tr('Hotkeys are set in the classic window.')), g_rml.escape(tr('Open the classic window'))))
  else
    form:build()
  end
  g_rml.setScrollTop(doc, 'content', 0)
  return true
end

local function onEvent(elementId, eventType)
  if doc == 0 then return end
  if eventType == 'click' then
    if elementId == 'x' or elementId == 'done' then
      return ChaosRmlOptions.close()
    elseif elementId == 'classic' or elementId == 'openclassic' then
      return ChaosRmlOptions.openClassic(current)
    elseif elementId:match('^p_') then
      local page = pageOf(elementId:sub(3))
      if page and page.id ~= current then showPage(page.id) end
      return
    end
  end
  if form then form:handle(elementId, eventType) end
end

function ChaosRmlOptions.isOpen()
  return doc ~= 0 and g_rml.isVisible(doc)
end

function ChaosRmlOptions.open(pageId)
  if not ChaosRmlOptions.available() then return false end
  if doc == 0 then
    ChaosRmlForm.loadFonts()
    doc = g_rml.loadDocument(PATH .. 'rmloptions.rml')
    if doc == 0 then return false end
    g_rml.setText(doc, 'classic', tr('Classic window'))
    g_rml.setText(doc, 'done', tr('Close'))
  end
  ChaosRmlForm.listen(doc, onEvent)
  local id = pageId or current or 'controls'
  if not pageOf(id) then id = 'controls' end
  if not showPage(id) then return false end
  g_rml.show(doc)
  return true
end

function ChaosRmlOptions.close()
  if doc == 0 then return end
  ChaosRmlForm.unlisten(doc)
  if form then form.alive = false end
  g_rml.close(doc)
  doc, form = 0, nil
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
  if os.getenv and (os.getenv('CHAOS_RMLOPTIONS') or '') ~= '' then
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
