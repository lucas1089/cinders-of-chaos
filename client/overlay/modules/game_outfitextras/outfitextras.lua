-- Customise Character extras (owner 2026-10-17: "Janela de customize character so mostra outfit, mount, aura, shader e
-- preset; faltam as outras opcoes"; 2026-10-20: put every option inside Change Appearance). The base window (game_outfit,
-- hooks of base patches 0075 and 0090) hands its window here when it opens; this adds one row per cosmetic to its
-- Change Appearance panel, under Preset, in the same style (a radio and a box with the current choice):
--   Wings            the owned wings of the outfit packet (they travel with the outfit, preview included)
--   Outline, Footprints, Kill effect, Loot label, Chat colour, Spell effect (class line)    server cosmetics.lua (225)
--   Plate frame (name plate frame)                                                           server commands_ui.lua (237)
--   Pet                                                                                      server pets.lua (254)
-- The radios are in the window's group: selecting a row lists its choices in the right-hand area (where Outfit and
-- Mount list theirs): "Default / None" and the owned ones selectable, the locked ones greyed out with their source in
-- the tooltip ("Only mine" hides them; the search box filters). Changes are kept while the window is open and sent
-- with Ok (the same rule as the rest of the window: Cancel throws them away). The data comes from the modules that
-- already hold it (game_cosmetics, game_pets, game_chaosinfo, game_unlocks): this asks them for a fresh state when the
-- window opens and is told (onData) when one arrives. A row whose data has not come yet is off. Rules:
-- outfitextrascore.lua.
-- API (modules.game_outfitextras), called by the base patch hooks:
--   attach(window, ctx)   ctx = {wings = the outfit packet's wing list, current = the current outfit, setWings(id),
--                         addRow(check) (into the window's radio group), prepareList() (clear the right-hand area),
--                         syncOnlyMine(list) (the "Only mine" box shows this list's setting)}
--   rowKey(id)            the cosmetic of a radio id, or nil (a base row)
--   show(key, search)     list the choices of a row in the right-hand area
--   activeKey()           the row whose list is shown, or nil
--   leave()               a base row was selected: give the right-hand area back
--   refresh()             the wardrobe catalogue came: recount the locked wings
--   apply()               Ok: send the changed choices
--   detach()              the window is closed
--   onData(source)        a source ('cosmetics' | 'pets' | 'services') has a new state

local E = OutfitExtrasCore

local FIRST_TOP = 132 -- the first row's value box, under Preset (110) in the Change Appearance panel
local PITCH = 22      -- the spacing of the window's own rows

local win, ctx, listPanel
local checks, values = {}, {} -- key -> widget
local rowsByKey = {}
local rows = {}    -- the rows with data, as shown
local chosen = {}  -- key -> value the player picked
local active, lastSearch

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
      current = ctx.current and ctx.current.wings }
  end
  return src
end

local function enableOk()
  if alive(win) and win.okButton and (win.okButton:getTooltip() or '') == '' then win.okButton:setEnabled(true) end
end

-- the value a row shows: the player's pick, else the character's current one
local function shownValue(key)
  if chosen[key] ~= nil then return chosen[key] end
  local row = rowsByKey[key]
  return row and row.current
end

-- the rows' radios and value boxes from the sources; a picked value stays picked
local function fillRows()
  rows = E.rows(sources())
  rowsByKey = {}
  for _, r in ipairs(rows) do rowsByKey[r.key] = r end
  for _, key in ipairs(E.KEYS) do
    local check, value = checks[key], values[key]
    local row = rowsByKey[key]
    if alive(check) and alive(value) then
      if row then
        if chosen[key] ~= nil and not E.indexOf(row, chosen[key]) then chosen[key] = nil end
        check:setEnabled(true)
        value:setText(E.textOf(row, shownValue(key)) or '')
        local tip = E.tooltip(row)
        if tip then value:setTooltip(tip) else value:removeTooltip() end
      else
        if active ~= key then check:setEnabled(false) end
        value:setText(tr('Loading...'))
        value:removeTooltip()
      end
    end
  end
end

local function pick(key, v)
  local row = rowsByKey[key]
  if not row or not E.indexOf(row, v) then return end
  chosen[key] = v
  if alive(values[key]) then values[key]:setText(E.textOf(row, v) or '') end
  if key == 'wings' and ctx and type(ctx.setWings) == 'function' then
    ctx.setWings(tonumber(v) or 0)
    local o = modules.game_outfit
    if o and type(o.updatePreview) == 'function' then o.updatePreview() end
  end
  enableOk()
end

-- a choice not owned: greyed out, its source in the tooltip, not selectable
local function styleLocked(widget, entry)
  local u = modules.game_unlocks
  if u and type(u.styleEntry) == 'function' then
    u.styleEntry(widget, { entry.text, locked = true, how = entry.how })
  else
    widget:setOpacity(0.45)
    widget:setTooltip(tr('Not unlocked yet.'))
  end
  widget.locked = true
  widget:setFocusable(false)
end

local function buildRows()
  local panel = win.appearance
  for i, key in ipairs(E.KEYS) do
    local top = FIRST_TOP + (i - 1) * PITCH
    local value = g_ui.createWidget('OutfitExtrasValue', panel)
    value:setId('extras_' .. key)
    value:setMarginTop(top)
    local check = g_ui.createWidget('OutfitExtrasCheck', panel)
    check:setId(key .. 'ExtrasCheck')
    check:setText(E.label(key) .. ':')
    check:setMarginTop(top + 4)
    check:setEnabled(false)
    checks[key], values[key] = check, value
    if type(ctx.addRow) == 'function' then ctx.addRow(check) end
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

function rowKey(id)
  return E.keyOfId(id)
end

function activeKey()
  return active
end

function show(key, search)
  if not alive(win) or not alive(listPanel) or not E.keyOfId(tostring(key) .. 'ExtrasCheck') then return end
  local ok, err = pcall(function()
    if type(ctx.prepareList) == 'function' then ctx.prepareList() end
    if type(ctx.syncOnlyMine) == 'function' then ctx.syncOnlyMine(key) end
    active, lastSearch = key, search
    win.ScrollBar.selectionList:hide()
    win.ScrollBar.outfitScrollBar:hide()
    listPanel:show()
    listPanel:raise()
    local list = listPanel.list
    list.onChildFocusChange = nil
    list:destroyChildren()

    local choices = E.choices(sources(), key, win.filter_outfits.onlyCheck:isChecked(), search)
    if not choices then
      local w = g_ui.createWidget('OutfitExtrasOption', list)
      w:setText(tr('Loading...'))
      w:setFocusable(false)
      return
    end
    local current = shownValue(key)
    local focus
    for _, c in ipairs(choices) do
      local w = g_ui.createWidget('OutfitExtrasOption', list)
      w:setText(c.text)
      w.extrasValue = c.value
      if c.locked then
        styleLocked(w, c)
      elseif c.value == current then
        focus = w
      end
    end
    if focus then
      list:focusChild(focus, KeyboardFocusReason)
      list:ensureChildVisible(focus)
    end
    list.onChildFocusChange = function(_, child)
      if child and child.extrasValue ~= nil and not child.locked then pick(key, child.extrasValue) end
    end
  end)
  if not ok then warn('show ' .. tostring(key), err) end
end

function leave()
  active, lastSearch = nil, nil
  if alive(listPanel) then
    listPanel.list.onChildFocusChange = nil
    listPanel.list:destroyChildren()
    listPanel:hide()
  end
  if alive(win) then
    win.ScrollBar.selectionList:show()
    win.ScrollBar.outfitScrollBar:show()
  end
end

function attach(window, context)
  detach()
  win, ctx = window, context or {}
  local ok, err = pcall(function()
    g_ui.importStyle('outfitextras')
    buildRows()
    listPanel = g_ui.createWidget('OutfitExtrasList', window.ScrollBar)
    fillRows()
    ask()
  end)
  if not ok then warn('attach', err) end
end

local function update(where)
  if not alive(win) then return end
  local ok, err = pcall(fillRows)
  if not ok then warn(where, err) end
  if active then show(active, lastSearch) end
end

function refresh()
  update('refresh')
end

function onData(source)
  update('onData ' .. tostring(source))
end

-- Ok: the changed choices go to their modules; wings went into the outfit already
function apply()
  if not alive(win) then return end
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

-- the widgets are children of the window and go with it
function detach()
  win, ctx, listPanel = nil, nil, nil
  checks, values, rowsByKey, rows, chosen = {}, {}, {}, {}, {}
  active, lastSearch = nil, nil
end

function init() end

function terminate()
  detach()
end
