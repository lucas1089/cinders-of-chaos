-- Customise Character extras (owner 2026-10-17: "Janela de customize character so mostra outfit, mount, aura, shader e
-- preset; faltam as outras opcoes"). The base window (game_outfit, hooks of base patch 0075) hands its window here when
-- it opens; this adds a panel of dropdowns under its lower panels and makes the window taller by the panel's height:
--   Wings            the owned wings of the outfit packet (they travel with the outfit, preview included)
--   Outline, Footprints, Kill effect, Loot label, Chat colour, Spell effect (class line)    server cosmetics.lua (225)
--   Name plate frame                                                                         server commands_ui.lua (237)
--   Pet                                                                                      server pets.lua (254)
-- Each dropdown lists "default / none" and what the account owns; the locked count is in its tooltip. Changes are kept
-- while the window is open and sent with Ok (the same rule as the rest of the window: Cancel throws them away). The data
-- comes from the modules that already hold it (game_cosmetics, game_pets, game_chaosinfo, game_unlocks): this asks them
-- for a fresh state when the window opens and is told (onData) when one arrives. A dropdown whose data has not come yet
-- stays off. The rules: outfitextrascore.lua.
-- API (modules.game_outfitextras), called by the base patch 0075 hooks:
--   attach(window, ctx)   ctx = {wings = the outfit packet's wing list, current = the current outfit, setWings(id)}
--   refresh()             the wardrobe catalogue came: recount the locked wings
--   apply()               Ok: send the changed choices
--   detach()              the window is closed
--   onData(source)        a source ('cosmetics' | 'pets' | 'services') has a new state

local E = OutfitExtrasCore

local PANEL_HEIGHT = 160
local GAP = 4
local PANEL_TOP = 519 -- under the appearance panel of the window's style (255 + 260), plus the gap

local win, panel, ctx
local widgets = {} -- key -> {row, combo, data}
local rows = {}    -- the rows as shown
local chosen = {}  -- key -> value the player picked
local updating = false

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function warn(where, err)
  g_logger.warning('[outfitextras] ' .. where .. ': ' .. tostring(err))
end

local function sources()
  local src = {}
  local c = modules.game_cosmetics
  if c and type(c.getState) == 'function' then src.cosmetics = c.getState() end
  local p = modules.game_pets
  if p and type(p.getState) == 'function' then src.pets = p.getState() end
  local i = modules.game_chaosinfo
  if i and type(i.getServices) == 'function' then src.services = i.getServices() end
  if ctx then
    local u = modules.game_unlocks
    local wardrobe = u and type(u.wardrobe) == 'function' and u.wardrobe() or nil
    src.wings = { stock = ctx.wings, wardrobe = wardrobe and wardrobe.wings or nil,
      current = chosen.wings ~= nil and chosen.wings or (ctx.current and ctx.current.wings) }
  end
  return src
end

local function enableOk()
  if alive(win) and win.okButton and (win.okButton:getTooltip() or '') == '' then win.okButton:setEnabled(true) end
end

local function onPick(key, combo)
  if updating then return end
  local opt = combo:getCurrentOption()
  if not opt then return end
  chosen[key] = opt.data
  if key == 'wings' and ctx and type(ctx.setWings) == 'function' then
    ctx.setWings(tonumber(opt.data) or 0)
    local o = modules.game_outfit
    if o and type(o.updatePreview) == 'function' then o.updatePreview() end
  end
  enableOk()
end

-- (re)fill every dropdown from the sources; a picked value stays picked
local function fill()
  if not alive(panel) then return end
  rows = E.rows(sources())
  local byKey = {}
  for _, r in ipairs(rows) do byKey[r.key] = r end
  updating = true
  for _, key in ipairs(E.KEYS) do
    local w = widgets[key]
    local r = byKey[key]
    if w and alive(w.combo) then
      w.combo:clearOptions()
      if r then
        for _, o in ipairs(r.options) do w.combo:addOption(o.text, o.value) end
        local value = chosen[key]
        local index = value ~= nil and E.indexOf(r, value) or nil
        index = index or E.indexOf(r, r.current) or 1
        w.combo:setCurrentIndex(index, true)
        w.combo:setEnabled(true)
        local tip = E.tooltip(r)
        if tip then w.combo:setTooltip(tip) else w.combo:removeTooltip() end
      else
        w.combo:addOption(tr('Loading...'), '')
        w.combo:setEnabled(false)
        w.combo:removeTooltip()
      end
    end
  end
  updating = false
end

local function build()
  local left, right = panel:getChildById('left'), panel:getChildById('right')
  for i, key in ipairs(E.KEYS) do
    local holder = (i % 2 == 1) and left or right
    local row = g_ui.createWidget('OutfitExtrasRow', holder)
    row:getChildById('label'):setText(E.label(key))
    local combo = row:getChildById('combo')
    combo.onOptionChange = function() onPick(key, combo) end
    widgets[key] = { row = row, combo = combo }
  end
end

local function ask()
  local c = modules.game_cosmetics
  if c and type(c.requestState) == 'function' then c.requestState() end
  local p = modules.game_pets
  if p and type(p.requestState) == 'function' then p.requestState() end
  local i = modules.game_chaosinfo
  if i and type(i.requestServices) == 'function' then i.requestServices() end
end

function attach(window, context)
  detach()
  win, ctx = window, context
  chosen = {}
  local ok, err = pcall(function()
    g_ui.importStyle('outfitextras')
    panel = g_ui.createWidget('OutfitExtrasPanel', window)
    panel:addAnchor(AnchorTop, 'parent', AnchorTop)
    panel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    panel:setMarginTop(PANEL_TOP)
    panel:setMarginLeft(16)
    window:setHeight(PANEL_TOP + PANEL_HEIGHT + (window:getHeight() - 515))
    local root = g_ui.getRootWidget()
    window:setY(math.max(0, math.floor((root:getHeight() - window:getHeight()) / 2)))
    build()
    fill()
    ask()
  end)
  if not ok then warn('attach', err) end
end

function refresh()
  if alive(panel) then pcall(fill) end
end

function onData(source)
  if alive(panel) then
    local ok, err = pcall(fill)
    if not ok then warn('onData ' .. tostring(source), err) end
  end
end

-- Ok: the changed choices go to their modules; wings went into the outfit already
function apply()
  if not alive(panel) then return end
  for _, a in ipairs(E.plan(rows, chosen)) do
    local ok, err = pcall(function()
      if a.act == 'cosmetic' then
        local c = modules.game_cosmetics
        if c and c.selectCosmetic then c.selectCosmetic(a.kind, a.id, a.line) end
      elseif a.act == 'frame' then
        local i = modules.game_chaosinfo
        if i and i.usePlateFrame then i.usePlateFrame(a.value) end
      elseif a.act == 'pet' then
        local p = modules.game_pets
        if p then
          if a.value == '' then p.dismiss() else p.summonSpecies(a.value) end
        end
      end
    end)
    if not ok then warn('apply ' .. tostring(a.act), err) end
  end
end

function detach()
  if alive(panel) then panel:destroy() end
  panel, win, ctx = nil, nil, nil
  widgets, rows, chosen = {}, {}, {}
end

function init() end

function terminate()
  detach()
end
