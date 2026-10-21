-- Loot filter (Hunt -> Loot Filter), corpse highlights and the loot feed (monster and item icons over the Loot tab).
-- Server: server/data/scripts/chaos/lootfilter.lua, extended opcode 238 (JSON {action, data}).
--   server -> client  settings {s, unlocked, presets, samples, open}
--                     peek {cid, corpse, items = [{i, id, c, r, u, o, g}]}      rarity data of an open container
--                     kill {k, m, look, p, items = [{n, id, c, r, u, o, g, nm, left}], drops = [{text, color, rank}]}
--                       one loot feed row: the monster's icon (look, a UICreature) and the item icons, no text
--                     update {k, left = [...]}   decay {k}   msg {text}
--                     beam {k, p, i}   handed to game_lootbeams (the light pillar over a corpse)
--                     settings also carry snd (sound per rule, vol, mute, hunt) and counts {session, total};
--                     kill carries hits {rule = items} and counts when a rule matched; counts {session, total}
--   client -> server  open | sync | set {s} | preset {name} | peek {cid} | take {k, n, id, one}
--                     sound {s = snd} | reset {scope = session | total | all, rule}
-- Rule counters and sounds: the server counts the drops of your kills per filter rule (lootfilter_core.lua F.RULES);
-- this module shows them (filter window, optionally the Hunt Tracker's Chaos Drops tab) and plays the rule's sound
-- (sounds/*.ogg, made by client/tools/gen_lootfilter_sounds.py) on the Effect sound channel.
-- The rules used for drawing are in lootfilterlogic.lua (a mirror of the server's lootfilter_core.lua).

local OPCODE = 238
local L = LootFilterLogic

local MAX_ROWS = 50
local DIM_OPACITY = 0.45
local GONE_OPACITY = 0.6 -- with the dark veil and the check mark
local PEEK_DELAY = 60

local settings = L.defaults()
local snd = L.soundDefaults()
local counts = { session = L.counts(nil), total = L.counts(nil) }
local ruleRows = {}   -- [rule key] = row widget of the counters panel
local soundSaveEvent
local lastPlayed      -- {file, gain, rule, at}: the last alert played (for the in-game check)
local onCounts, playKillSound -- defined with the counters panel below (used by the loot channel)
local unlocked = false
local presets = {}
local samples = {}

local window
local updatingUi = false
local saveEvent

local peekData = {}   -- [cid] = {corpse = bool, items = {[index] = row}}
local peekEvents = {}

local lootPanel       -- LootChannelPanel inside the console content panel
local rows = {}       -- [kill id] = {widget, icons = {[n] = {w, info}}}
local rowOrder = {}
local flashLabel, flashEvent

-- every handler the engine or another module calls runs through this: an error here is logged once per kind
-- and never reaches the caller (game_containers, the console, the protocol)
local reported = {}
local handlers = {} -- the wrapped callbacks connected in init()
local function safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok and not reported[name] then
      reported[name] = true
      g_logger.warning('[lootfilter] ' .. name .. ': ' .. tostring(err))
    end
  end
end

-- ---------------------------------------------------------------- protocol
local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function list(v)
  local out = {}
  if type(v) == 'table' then
    for _, x in ipairs(v) do out[#out + 1] = x end
  end
  return out
end

-- ---------------------------------------------------------------- item widget decoration
local imageOk = {}
local function setImage(widget, path)
  if imageOk[path] == nil then
    imageOk[path] = not g_resources or not g_resources.fileExists
      or g_resources.fileExists(path .. '.png') or g_resources.fileExists(path) or false
  end
  if imageOk[path] then widget:setImageSource(path) end
end

local function child(widget, id, style)
  local c = widget:getChildById(id)
  if not c then
    c = g_ui.createWidget('UIWidget', widget)
    c:setId(id)
    c:setPhantom(true)
    c:setFocusable(false)
    c:fill('parent')
    if style == 'glow' then
      setImage(c, '/modules/game_lootfilter/images/lf_glow')
    elseif style == 'soft' then
      setImage(c, '/modules/game_lootfilter/images/lf_glow_soft')
    elseif style == 'frame' then
      setImage(c, '/modules/game_lootfilter/images/lf_frame')
    elseif style == 'empty' then
      setImage(c, '/modules/game_lootfilter/images/lf_empty')
    elseif style == 'gone' then
      c:setBackgroundColor('#0a080cc8')
      setImage(c, '/modules/game_lootfilter/images/lf_taken')
    end
  end
  return c
end

local function clearDecoration(widget)
  if not widget or widget:isDestroyed() then return end
  for _, id in ipairs({ 'lfGlow', 'lfGlowSoft', 'lfFrame', 'lfGone' }) do
    local c = widget:getChildById(id)
    if c then c:hide() end
  end
  if widget.lfDimmed then
    widget:setOpacity(1)
    widget.lfDimmed = nil
  end
end

-- state: 'highlight' | 'normal' | 'dim'; gone: looted (loot channel only)
local function decorate(widget, info, allowDim, gone)
  if not widget or widget:isDestroyed() then return end
  local state = L.classify(info, settings)
  local color = L.color(info)
  -- orbs: a thin faint ring instead of the wide glow, and no frame on top (L.glowStyle)
  local soft = L.glowStyle(info) == 'soft'
  local glow = child(widget, 'lfGlow', 'glow')
  local softGlow = child(widget, 'lfGlowSoft', 'soft')
  local frame = child(widget, 'lfFrame', 'frame')
  local lit = color and state == 'highlight' and not gone
  if lit and not soft then
    glow:setImageColor(color)
    glow:show()
  else
    glow:hide()
  end
  if lit and soft then
    softGlow:setImageColor(color)
    softGlow:show()
  else
    softGlow:hide()
  end
  -- one frame per slot: game_itemrarity draws one from the item's custom attributes (widget.irColor)
  if color and not gone and not widget.irColor and not (lit and soft) then
    frame:setImageColor(color)
    frame:show()
  else
    frame:hide()
  end
  local goneOverlay = widget:getChildById('lfGone')
  if gone then
    child(widget, 'lfGone', 'gone'):show()
    widget:setOpacity(GONE_OPACITY)
    widget.lfDimmed = true
  else
    if goneOverlay then goneOverlay:hide() end
    if allowDim and state == 'dim' then
      widget:setOpacity(DIM_OPACITY)
      widget.lfDimmed = true
    elseif widget.lfDimmed then
      widget:setOpacity(1)
      widget.lfDimmed = nil
    end
  end
end

-- ---------------------------------------------------------------- containers
local function decorateContainer(container)
  if not container or not container.itemsPanel or container.itemsPanel:isDestroyed() then return end
  local data = peekData[container:getId()]
  local first = container.getFirstIndex and container:getFirstIndex() or 0
  for slot = 0, container:getCapacity() - 1 do
    local widget = container.itemsPanel:getChildById('item' .. slot)
    if widget then
      local item = container:getItem(slot)
      local row = data and data.items[first + slot]
      if item and row and row.id == item:getId() then
        decorate(widget, row, data.corpse, false)
      else
        clearDecoration(widget)
      end
    end
  end
end

local function requestPeek(container)
  local cid = container:getId()
  if peekEvents[cid] then removeEvent(peekEvents[cid]) end
  peekEvents[cid] = scheduleEvent(function()
    peekEvents[cid] = nil
    if g_game.isOnline() then send('peek', { cid = cid }) end
  end, PEEK_DELAY)
end

-- one redraw per container per frame (L.coalescer): a big Auto Seller sale or Loot Bag sort is one engine call per item
-- (onSizeChange and onRemoveItem each), and every call walked every slot of the window. The run looks the container up
-- by id, so a window opened in its place in between is the one drawn; stale rows are cleared then.
local decorateLater = L.coalescer(function(fn) addEvent(fn) end)
local function onContainerChange(container)
  local cid = container:getId()
  decorateLater(cid, safe('decorate', function()
    local c = g_game.getContainer(cid)
    if c then decorateContainer(c) end
  end))
  requestPeek(container)
end

local function onContainerOpen(container)
  peekData[container:getId()] = nil
  requestPeek(container)
end

local function onContainerClose(container)
  peekData[container:getId()] = nil
end

local function onPeek(data)
  local cid = tonumber(data.cid)
  if not cid then return end
  local items = {}
  for _, r in ipairs(list(data.items)) do
    if type(r) == 'table' then items[tonumber(r.i) or -1] = r end
  end
  peekData[cid] = { corpse = data.corpse and true or false, items = items }
  local container = g_game.getContainer(cid)
  if container then decorateContainer(container) end
end

local function redrawContainers()
  for _, container in pairs(g_game.getContainers()) do
    decorateContainer(container)
  end
end

-- ---------------------------------------------------------------- loot channel
local function getChat()
  local console = modules.game_console
  local chat = console and console.g_chat or nil
  if type(chat) ~= 'table' and type(chat) ~= 'userdata' then return nil end
  return chat
end

local function updatePanelVisibility()
  if not lootPanel or lootPanel:isDestroyed() then return end
  local chat = getChat()
  local current = chat and chat.getCurrentTabName and chat:getCurrentTabName() or ''
  lootPanel:setVisible(settings.icons and current == 'Loot')
end

local function ensureLootTab()
  local chat = getChat()
  if not settings.icons or not chat then return end
  if chat.getTabByName and not chat:getTabByName('Loot') and modules.game_console.openLootChannel then
    modules.game_console.openLootChannel()
  end
end

local function ensureLootPanel()
  if lootPanel and not lootPanel:isDestroyed() then return lootPanel end
  local chat = getChat()
  if not chat or not chat.contentPanel then return nil end
  local ok, panel = pcall(g_ui.createWidget, 'LootChannelPanel', chat.contentPanel)
  if not ok or not panel then return nil end
  lootPanel = panel
  lootPanel:hide()
  if chat.tabBar then
    connect(chat.tabBar, { onTabChange = handlers.tab or updatePanelVisibility })
  end
  updatePanelVisibility()
  return lootPanel
end

local function setIconState(icon)
  local info = icon.info
  local count, gone = L.iconCount(info)
  icon.w:setItemCount(count)
  decorate(icon.w, info, true, gone)
  icon.w:setTooltip(L.tooltip(info))
end

local function onIconClick(row, icon)
  local left = tonumber(icon.info.left) or 0
  if left <= 0 then return end
  send('take', { k = row.k, n = icon.info.n, id = icon.info.id, one = g_keyboard.isShiftPressed() })
end

local function dropRow(k)
  local row = rows[k]
  rows[k] = nil
  if row and row.widget and not row.widget:isDestroyed() then
    row.widget:destroy()
  end
end

local function showFlash(list)
  local drops = {} -- an entry that is no table is left out
  for _, x in ipairs(type(list) == 'table' and list or {}) do
    if type(x) == 'table' then drops[#drops + 1] = x end
  end
  if #drops == 0 then return end
  local gi = modules.game_interface
  local root = gi and ((gi.getMapPanel and gi.getMapPanel()) or (gi.getRootPanel and gi.getRootPanel()))
  if not root then return end
  if flashLabel and not flashLabel:isDestroyed() and flashLabel:getParent() ~= root then
    flashLabel:destroy()
    flashLabel = nil
  end
  if not flashLabel or flashLabel:isDestroyed() then
    flashLabel = g_ui.createWidget('UILabel', root)
    flashLabel:setFont('verdana-11px-rounded')
    flashLabel:setTextAutoResize(true)
    flashLabel:setPhantom(true)
    flashLabel:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    flashLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    flashLabel:setMarginBottom(150) -- above the character (the map panel may reach above the screen)
    flashLabel:setId('lfFlash')
  end
  local d = drops[1] -- the best one: a unique, else the highest rarity
  for _, x in ipairs(drops) do
    if (tonumber(x.rank) or 0) > (tonumber(d.rank) or 0) then d = x end
  end
  flashLabel:setText(d.text or '')
  flashLabel:setColor(d.color or '#ffffff')
  flashLabel:show()
  flashLabel:raise()
  if flashEvent then removeEvent(flashEvent) end
  flashEvent = scheduleEvent(function()
    flashEvent = nil
    if flashLabel and not flashLabel:isDestroyed() then flashLabel:hide() end
  end, 4000)
end

local function onKill(data)
  local drops = list(data.drops)
  showFlash(drops)
  if type(data.counts) == 'table' then onCounts(data.counts) end
  if type(data.hits) == 'table' then playKillSound(data.hits) end
  local panel = ensureLootPanel()
  if not panel then return end
  ensureLootTab()
  local r = L.feedRow(data, os.time())
  if not r then return end
  local k = r.k
  if rows[k] then -- the same id again (the server's counter restarted): the new row replaces the old one
    dropRow(k)
    for i = #rowOrder, 1, -1 do
      if rowOrder[i] == k then table.remove(rowOrder, i) end
    end
  end
  panel.hint:hide() -- the how-to line only while the tab is empty
  -- one row: the monster's icon, then the item icons (no text; names, counts and times are in the tooltips)
  local widget = g_ui.createWidget('LootChannelRow', panel.list)
  local mob = g_ui.createWidget('LootChannelMonster', widget)
  -- fit the look's own size into the cell, centred: a rat stays 1:1, a dragon is scaled down (not a fixed 64 px box)
  pcall(mob.setOldScaling, mob, true)
  pcall(mob.setCenter, mob, true)
  if r.outfit then
    local ok = pcall(mob.setOutfit, mob, r.outfit)
    if not ok then pcall(mob.setOutfit, mob, { type = r.outfit.type, auxType = r.outfit.auxType }) end
  end
  mob:setTooltip(r.tip)
  if r.empty then child(mob, 'lfEmpty', 'empty'):show() end -- a veil and a small empty mark, no text
  local row = { k = k, widget = widget, icons = {} }
  for _, info in ipairs(r.items) do
    local w = g_ui.createWidget('LootChannelItem', widget)
    w:setItemId(tonumber(info.id) or 0)
    w:setVirtual(true)
    local icon = { w = w, info = info }
    row.icons[info.n] = icon
    w.onMouseRelease = function(self, mousePos, button)
      if button == MouseLeftButton and self:containsPoint(mousePos) then
        onIconClick(row, icon)
        return true
      end
      return false
    end
    if modules.game_itemfinder and modules.game_itemfinder.attach then modules.game_itemfinder.attach(w, tonumber(info.id)) end -- right-click: Where to find
    setIconState(icon)
  end
  rows[k] = row
  rowOrder[#rowOrder + 1] = k
  for _, old in ipairs(L.trim(rowOrder, MAX_ROWS)) do
    dropRow(old)
  end
end

local function onUpdate(data)
  local row = rows[tonumber(data.k) or -1]
  if not row then return end
  for n, left in ipairs(list(data.left)) do
    local icon = row.icons[n]
    if icon then
      icon.info.left = tonumber(left) or 0
      setIconState(icon)
    end
  end
end

local function onDecay(data)
  local row = rows[tonumber(data.k) or -1]
  if not row then return end
  row.decayed = true
  for _, icon in pairs(row.icons) do
    icon.info.left = 0
    setIconState(icon)
  end
end

local function redrawRows()
  for _, row in pairs(rows) do
    for _, icon in pairs(row.icons) do setIconState(icon) end
  end
end

local function clearRows()
  for k in pairs(rows) do dropRow(k) end
  rows, rowOrder = {}, {}
  if lootPanel and not lootPanel:isDestroyed() then lootPanel.hint:show() end
end

-- ---------------------------------------------------------------- rule counters and sounds
local noSoundLogged = false
local function playFile(file, gain, rule)
  if not file then return false end
  lastPlayed = { file = file, gain = gain, rule = rule, at = os.time(), played = false }
  if not g_sounds then
    -- a client built without its sound framework (CMake FRAMEWORK_SOUND, client base-patch 0032)
    if not noSoundLogged then
      noSoundLogged = true
      g_logger.warning('[lootfilter] this client has no sound support (g_sounds): rule sounds are not played')
    end
    return false
  end
  local channel = g_sounds.getChannel and SoundChannels and g_sounds.getChannel(SoundChannels.Effect)
  local ok, err
  if channel then
    ok, err = pcall(channel.play, channel, file, 0, gain)
  else
    ok, err = pcall(g_sounds.play, file, 0, gain)
  end
  if not ok then g_logger.warning('[lootfilter] sound ' .. file .. ': ' .. tostring(err)) end
  lastPlayed.played = ok and err ~= nil -- the source (nil when audio is off or the channel disabled)
  return ok
end

playKillSound = function(hits)
  local file, gain, rule = L.pickSound(hits, snd)
  if file then playFile(file, gain, rule) end
end

local function notifyHunt()
  local hunt = modules.game_hunt
  if hunt and hunt.onLootFilterCounts then pcall(hunt.onLootFilterCounts) end
end

local function refreshRules()
  if not window or not window.rulesPanel then return end
  local p = window.rulesPanel
  updatingUi = true
  for _, r in ipairs(L.RULES) do
    local row = ruleRows[r.key]
    if row then
      row.count:setText(L.countLine(counts, r.key))
      row.sound:setCurrentIndex((snd.rules[r.key] or 0) + 1)
    end
  end
  p.volumeCombo:setCurrentIndex(math.floor((snd.vol or 0) / 10) + 1)
  p.muteCheck:setChecked(snd.mute)
  p.huntCheck:setChecked(snd.hunt)
  for _, row in pairs(ruleRows) do row.play:setEnabled(not snd.mute and (snd.vol or 0) > 0) end
  updatingUi = false
end

local function scheduleSoundSave()
  if soundSaveEvent then removeEvent(soundSaveEvent) end
  soundSaveEvent = scheduleEvent(function()
    soundSaveEvent = nil
    send('sound', { s = snd })
  end, 250)
end

local function onSoundUi()
  if updatingUi or not window then return end
  local p = window.rulesPanel
  for _, r in ipairs(L.RULES) do
    local row = ruleRows[r.key]
    local o = row and row.sound:getCurrentOption()
    if o then snd.rules[r.key] = tonumber(o.data) or 0 end
  end
  local v = p.volumeCombo:getCurrentOption()
  snd.vol = v and tonumber(v.data) or snd.vol
  snd.mute = p.muteCheck:isChecked()
  snd.hunt = p.huntCheck:isChecked()
  refreshRules()
  notifyHunt()
  scheduleSoundSave()
end

local function buildRules()
  if not window or not window.rulesPanel then return end
  local p = window.rulesPanel
  p.ruleRows:destroyChildren()
  ruleRows = {}
  updatingUi = true
  for _, r in ipairs(L.RULES) do
    local row = g_ui.createWidget('LootFilterRuleRow', p.ruleRows)
    row:setId('rule_' .. r.key)
    row.name:setText(tr(r.name))
    row.name:setColor(r.color)
    row.sound:addOption(tr('No sound'), 0)
    for i, x in ipairs(L.SOUNDS) do row.sound:addOption(tr(x.name), i) end
    local key = r.key
    row.sound.onOptionChange = safe('ui', onSoundUi)
    row.play.onClick = function()
      playFile(L.soundFile(snd.rules[key]), (snd.vol or 0) / 100, key)
    end
    row.reset.onClick = function() send('reset', { scope = 'all', rule = key }) end
    ruleRows[key] = row
  end
  p.volumeCombo:clearOptions()
  for v = 0, 100, 10 do p.volumeCombo:addOption(v .. '%', v) end
  updatingUi = false
  p.volumeCombo.onOptionChange = safe('ui', onSoundUi)
  p.muteCheck.onCheckChange = safe('ui', onSoundUi)
  p.huntCheck.onCheckChange = safe('ui', onSoundUi)
  refreshRules()
end

onCounts = function(data)
  counts = { session = L.counts(data.session), total = L.counts(data.total) }
  refreshRules()
  notifyHunt()
end

function resetCounters(scope)
  if scope ~= 'total' then
    send('reset', { scope = 'session' })
    return
  end
  local box
  local function close() if box then box:destroy() box = nil end end
  local function yes() close() send('reset', { scope = 'total' }) end
  if displayGeneralBox then
    box = displayGeneralBox(tr('Reset totals'), tr('Set the total of every rule back to zero?'),
      { { text = tr('Yes'), callback = yes }, { text = tr('No'), callback = close }, anchor = AnchorHorizontalCenter }, yes, close)
  else
    yes()
  end
end

-- the counters for the Hunt Tracker: {show, rows = L.huntRows}
function getCounters()
  return { show = snd.hunt and true or false, rows = L.huntRows(counts) }
end

function getLastSound()
  return lastPlayed
end

-- ---------------------------------------------------------------- window
local function rarityCombo(combo, offText, value, suffix)
  combo:clearOptions()
  combo:addOption(offText, 0)
  local at = 1
  for i, id in ipairs(L.RARITY_IDS) do
    combo:addOption(L.rarityName(id) .. (suffix or ''), id)
    if id == L.canon(value) then at = i + 1 end
  end
  combo:setCurrentIndex(at)
end

-- modifier tier threshold: Off, T1+ .. T8+
local function tierCombo(combo, value)
  combo:clearOptions()
  combo:addOption(tr('Off'), 0)
  for t = 1, L.MAX_TIER do
    combo:addOption(string.format('T%d+', t), t)
  end
  combo:setCurrentIndex((value or 0) + 1)
end

local function scheduleSave()
  if saveEvent then removeEvent(saveEvent) end
  saveEvent = scheduleEvent(function()
    saveEvent = nil
    send('set', { s = settings })
  end, 250)
end

local function buildPreview()
  if not window then return end
  local panel = window.preview
  panel:destroyChildren()
  local gear = tonumber(samples.gear) or 0
  local entries = {}
  entries[#entries + 1] = { id = gear, r = 0, g = 'equipment', nm = tr('Gear without rarity') }
  for _, id in ipairs(L.RARITY_IDS) do
    entries[#entries + 1] = { id = gear, r = id, g = 'equipment', nm = tr('%s gear', L.rarityName(id)) }
  end
  if (settings.tier or 0) > 0 then
    entries[#entries + 1] = { id = gear, r = 1, t = settings.tier, g = 'equipment',
      nm = string.format(tr('Common gear with a T%d modifier'), settings.tier) }
  end
  entries[#entries + 1] = { id = tonumber(samples.unique) or gear, u = 1, g = 'equipment', nm = tr('A unique') }
  entries[#entries + 1] = { id = tonumber(samples.orb) or 0, o = 1, g = 'currency', nm = tr('An orb') }
  entries[#entries + 1] = { id = tonumber(samples.coin) or 0, g = 'currency', nm = tr('Coins') }
  entries[#entries + 1] = { id = tonumber(samples.supply) or 0, g = 'supplies', nm = tr('A potion') }
  entries[#entries + 1] = { id = tonumber(samples.other) or 0, g = 'other', nm = tr('Other loot') }
  for _, e in ipairs(entries) do
    local w = g_ui.createWidget('LootFilterPreview', panel)
    w:setItemId(e.id)
    w:setVirtual(true)
    local state = L.classify(e, settings)
    w:setTooltip(L.label(e) .. '\n' .. (state == 'highlight' and tr('glows') or state == 'dim' and tr('dimmed') or tr('shown')))
    decorate(w, e, true, false)
  end
end

local function refreshWindow()
  if not window then return end
  updatingUi = true
  rarityCombo(window.highlightCombo, tr('Off'), settings.highlight, '+')
  rarityCombo(window.dimCombo, tr('Off'), settings.dim)
  if window.tierCombo then tierCombo(window.tierCombo, settings.tier) end
  rarityCombo(window.autolootPanel.lootMinCombo, tr('Off'), settings.lootMin)
  rarityCombo(window.autolootPanel.lootFromCombo, tr('Off'), settings.lootFrom, '+')
  for _, c in ipairs(L.CATEGORIES) do
    window['show_' .. c]:setChecked(settings.show[c])
  end
  window.icons:setChecked(settings.icons)
  window.notify:setChecked(settings.notify)
  local ap = window.autolootPanel
  ap.lootMinCombo:setEnabled(unlocked)
  ap.lootFromCombo:setEnabled(unlocked)
  ap.lootMinLabel:setEnabled(unlocked)
  ap.lootFromLabel:setEnabled(unlocked)
  ap.storeButton:setVisible(not unlocked)
  if unlocked then
    ap.lockLabel:setColor('#8c8070')
    ap.lockLabel:setText(tr('Unlocked. Uniques and orbs are never held back.'))
  else
    ap.lockLabel:setColor('#e03a1e')
    ap.lockLabel:setText(tr('Locked: buy "Rarity Autoloot" in the Store (Convenience).'))
  end
  window.presets:destroyChildren()
  for _, p in ipairs(presets) do
    local b = g_ui.createWidget('LootFilterPreset', window.presets)
    b:setText(p.name or p.key)
    b:setTooltip(p.desc or '')
    local key = p.key
    b.onClick = function() send('preset', { name = key }) end
    b.onHoverChange = function(_, hovered)
      if window then window.presetInfo:setText(hovered and (p.desc or '') or '') end
    end
  end
  updatingUi = false
  buildPreview()
end

local function onUiChange()
  if updatingUi or not window then return end
  local function comboValue(c)
    return tonumber(c:getCurrentOption() and c:getCurrentOption().data) or 0
  end
  settings.highlight = comboValue(window.highlightCombo)
  settings.dim = comboValue(window.dimCombo)
  if window.tierCombo then settings.tier = comboValue(window.tierCombo) end
  if unlocked then
    settings.lootMin = comboValue(window.autolootPanel.lootMinCombo)
    settings.lootFrom = comboValue(window.autolootPanel.lootFromCombo)
  end
  for _, c in ipairs(L.CATEGORIES) do
    settings.show[c] = window['show_' .. c]:isChecked()
  end
  settings.icons = window.icons:isChecked()
  settings.notify = window.notify:isChecked()
  buildPreview()
  redrawContainers()
  redrawRows()
  updatePanelVisibility()
  scheduleSave()
end

local function onSettings(data)
  settings = L.normalize(data.s)
  unlocked = data.unlocked and true or false
  presets = {} -- tables with a key (sent back by a click); anything else is left out
  for _, p in ipairs(list(data.presets)) do
    if type(p) == 'table' and type(p.key) == 'string' then presets[#presets + 1] = p end
  end
  if type(data.samples) == 'table' then samples = data.samples end
  if type(data.snd) == 'table' then snd = L.normalizeSound(data.snd) end
  if type(data.counts) == 'table' then
    counts = { session = L.counts(data.counts.session), total = L.counts(data.counts.total) }
  end
  refreshRules()
  notifyHunt()
  redrawContainers()
  redrawRows()
  ensureLootPanel()
  ensureLootTab()
  updatePanelVisibility()
  if window and (window:isVisible() or data.open) then
    refreshWindow()
  end
  if data.open then show() end
end

-- registered with registerExtendedJSONOpcode: the message arrives decoded, and a payload over 8192 bytes (the server
-- sends it in parts, Chaos.send) is joined first. A raw string is decoded here (tests).
local function onExtendedOpcode(protocol, opcode, buffer)
  local msg = buffer
  if type(buffer) == 'string' then
    local ok, decoded = pcall(json.decode, buffer)
    if not ok then
      g_logger.error('[lootfilter] invalid JSON: ' .. tostring(decoded))
      return
    end
    msg = decoded
  end
  if type(msg) ~= 'table' then
    g_logger.error('[lootfilter] invalid JSON: ' .. tostring(msg))
    return
  end
  local data = type(msg.data) == 'table' and msg.data or {}
  if msg.action == 'settings' then onSettings(data)
  elseif msg.action == 'peek' then onPeek(data)
  elseif msg.action == 'kill' then onKill(data)
  elseif msg.action == 'update' then onUpdate(data)
  elseif msg.action == 'decay' then onDecay(data)
  elseif msg.action == 'msg' then showFlash({ { text = data.text or '', color = '#ff7a5a' } })
  elseif msg.action == 'counts' then onCounts(data)
  elseif msg.action == 'beam' then -- loot beams over corpses (game_lootbeams draws them)
    local lb = modules.game_lootbeams
    if lb and lb.onBeam then lb.onBeam(data) end
  end
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if window then window:hide() end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
  else
    send('open') -- the server answers with the settings (open = true)
  end
end

-- the filter settings as the client has them (game_groundlabels labels ground items by the same rules)
function getSettings()
  return settings
end

function openStore()
  if modules.game_shop and modules.game_shop.toggle then
    modules.game_shop.toggle()
  end
end

local function onGameStart()
  peekData = {}
  clearRows()
  ensureLootPanel()
  -- ask for the settings (the server also pushes them after login; an older server simply never answers)
  scheduleEvent(function() if g_game.isOnline() then send('sync') end end, 1000)
end

local function onGameEnd()
  hide()
  peekData = {}
  clearRows()
  if flashLabel and not flashLabel:isDestroyed() then flashLabel:hide() end
end

function init()
  handlers.container = {
    onOpen = safe('open', onContainerOpen), onClose = safe('close', onContainerClose),
    onAddItem = safe('add', onContainerChange), onRemoveItem = safe('remove', onContainerChange),
    onUpdateItem = safe('update', onContainerChange), onSizeChange = safe('size', onContainerChange)
  }
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  handlers.tab = safe('tab', updatePanelVisibility)
  handlers.opcode = safe('opcode', onExtendedOpcode)

  local ok, ui = pcall(g_ui.displayUI, 'lootfilter')
  if ok and ui then
    window = ui
    window:hide()
    local function hook(widget, field, fn)
      if widget then widget[field] = safe('ui', fn) end
    end
    hook(window.highlightCombo, 'onOptionChange', onUiChange)
    hook(window.dimCombo, 'onOptionChange', onUiChange)
    hook(window.tierCombo, 'onOptionChange', onUiChange)
    local ap = window.autolootPanel
    hook(ap and ap.lootMinCombo, 'onOptionChange', onUiChange)
    hook(ap and ap.lootFromCombo, 'onOptionChange', onUiChange)
    for _, c in ipairs(L.CATEGORIES) do
      hook(window['show_' .. c], 'onCheckChange', onUiChange)
    end
    hook(window.icons, 'onCheckChange', onUiChange)
    hook(window.notify, 'onCheckChange', onUiChange)
    local okR, errR = pcall(buildRules)
    if not okR then g_logger.warning('[lootfilter] rule counters panel: ' .. tostring(errR)) end
  else
    window = nil
    g_logger.warning('[lootfilter] window not loaded (theme styles missing?): ' .. tostring(ui))
  end
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, handlers.opcode)
  connect(Container, handlers.container)
  connect(g_game, handlers.game)
  if g_game.isOnline() then handlers.game.onGameStart() end
end

function terminate()
  if handlers.container then disconnect(Container, handlers.container) end
  if handlers.game then disconnect(g_game, handlers.game) end
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, OPCODE)
  for _, e in pairs(peekEvents) do removeEvent(e) end
  peekEvents = {}
  if saveEvent then removeEvent(saveEvent) saveEvent = nil end
  if soundSaveEvent then removeEvent(soundSaveEvent) soundSaveEvent = nil end
  ruleRows = {}
  if flashEvent then removeEvent(flashEvent) flashEvent = nil end
  local chat = getChat()
  if chat and chat.tabBar and handlers.tab then pcall(disconnect, chat.tabBar, { onTabChange = handlers.tab }) end
  clearRows()
  if lootPanel and not lootPanel:isDestroyed() then lootPanel:destroy() end
  lootPanel = nil
  if flashLabel and not flashLabel:isDestroyed() then flashLabel:destroy() end
  flashLabel = nil
  if window then window:destroy() window = nil end
  handlers = {}
end
