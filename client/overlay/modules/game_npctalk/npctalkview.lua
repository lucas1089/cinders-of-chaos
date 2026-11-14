-- NPC dialogue window (O571): the widgets. npctalkview.lua turns the plain data of npctalk_logic.lua into the widgets of
-- npctalk.otui and calls back what the player does; it never talks to the game (npctalk.lua does). Tested on a fake widget
-- engine built from the real .otui by npctalkview_test.lua.
NpcTalkView = {}
local V = NpcTalkView
local L = NpcTalkLogic

-- every id the code below looks up in the window (npctalkview_test.lua holds the list to npctalk.otui)
V.IDS = { 'closeButton', 'optionsButton', 'header', 'portraitFrame', 'portrait', 'npcName', 'npcTitle', 'status', 'logPanel',
  'textScroll', 'textScrollBar', 'chips', 'quickButtons', 'yes', 'no', 'trade', 'inputRow', 'input', 'sayButton', 'byeButton' }

local CHIP_H, GAP_X, GAP_Y, LABEL_H, CHIP_PAD = 22, 4, 4, 12, 16
local PORTRAIT_SMALL, PORTRAIT_BIG = 80, 128
V.COLORS = { npc = L.COLORS.npc, keyword = L.COLORS.keyword, speaker = '#e8b84a', player = L.COLORS.player }

local function alive(w)
  return w ~= nil and not w:isDestroyed()
end

-- a font of client_chaos_theme (ChaosTheme.fonts) on a widget, only when that font is loaded: the NPC's lines in
-- 'dialogue' (IM Fell English), its name in 'heading' (Alegreya SC)
local function applyThemeFont(widget, role)
  local theme = modules and modules.client_chaos_theme and modules.client_chaos_theme.ChaosTheme
  if theme and theme.applyFont then theme.applyFont(widget, role) end
end

local function groupName(id)
  if id == 'quest' then return tr('Quests')
  elseif id == 'trade' then return tr('Trade')
  elseif id == 'language' then return tr('Language')
  end
  return tr('Topics')
end

function V.new(window)
  local view = { window = window, ui = {}, on = {}, chipWidgets = {}, labelWidgets = {} }
  for _, id in ipairs(V.IDS) do
    view.ui[id] = window:recursiveGetChildById(id)
    if not view.ui[id] then error('npctalk.otui has no widget ' .. id) end
  end
  setmetatable(view, { __index = V })
  local ui = view.ui
  applyThemeFont(ui.npcName, 'heading')
  ui.closeButton.onClick = function() view:fire('close') end
  ui.optionsButton.onClick = function() view:fire('options') end
  ui.byeButton.onClick = function() view:fire('bye') end
  ui.sayButton.onClick = function()
    local text = ui.input:getText()
    ui.input:clearText()
    view:fire('say', text)
  end
  for _, id in ipairs({ 'yes', 'no', 'trade' }) do
    local word = id
    ui[id].onClick = function() view:fire('say', word) end
  end
  return view
end

function V:fire(name, ...)
  local fn = self.on[name]
  if fn then return fn(...) end
end

-- ---------------------------------------------------------------- the NPC
-- `npc` = {name, title, role, outfit, big}: the heading, the line under it and the portrait of the NPC's own outfit
function V:setNpc(npc)
  local ui = self.ui
  ui.npcName:setText(npc.name or '')
  ui.npcTitle:setText(npc.title or '')
  local big = npc.big == true
  local size = big and PORTRAIT_BIG or PORTRAIT_SMALL
  ui.portrait:setSize({ width = size, height = size })
  ui.portrait:setMarginRight(big and -4 or 0)
  ui.portrait:setMarginBottom(big and -8 or 0)
  if npc.outfit then ui.portrait:setOutfit(npc.outfit) end
  self:setStatus('')
end

function V:setTitle(title)
  self.ui.npcTitle:setText(title or '')
end

function V:setStatus(text)
  self.ui.status:setText(text or '')
end

function V:status()
  return self.ui.status:getText()
end

-- ---------------------------------------------------------------- the conversation log
local function pointer(label)
  label:setEventListener(EVENT_TEXT_CLICK)
  label:setEventListener(EVENT_TEXT_HOVER)
  label.onTextHoverChange = function(widget, _, hovered)
    if hovered and not widget.pointer then
      widget.pointer = true
      g_mouse.pushCursor('pointer')
    elseif not hovered and widget.pointer then
      widget.pointer = nil
      g_mouse.popCursor('pointer')
    end
  end
  label.onDestroy = function(widget)
    if widget.pointer then
      widget.pointer = nil
      g_mouse.popCursor('pointer')
    end
  end
end

-- the NPC's line: "Name: " in gold, then the text in parchment with its {keywords} in bright gold, clickable
local function npcLine(view, parent, entry)
  local label = g_ui.createWidget('NpcTalkNpcLine', parent)
  applyThemeFont(label, 'dialogue')
  local colored, hasKeys = L.coloredText(entry.text, V.COLORS.npc, V.COLORS.keyword, true)
  table.insert(colored, 1, V.COLORS.speaker)
  table.insert(colored, 1, (entry.who or '') .. ': ')
  if hasKeys then
    pointer(label)
    label.onTextClick = function(_, word) view:fire('word', word) end
  end
  label:setColoredText(colored)
  return label
end

-- the player's line: "You: hi" dim and on the right
local function playerLine(parent, entry)
  local label = g_ui.createWidget('NpcTalkPlayerLine', parent)
  label:setText((entry.who or tr('You')) .. ': ' .. L.plain(entry.text))
  return label
end

-- `entries` = [{side = 'npc' | 'player', who, text}], oldest first; `waiting`: the NPC has not answered yet ("...")
function V:renderLog(entries, waiting)
  local ui = self.ui
  ui.textScroll:destroyChildren()
  for _, entry in ipairs(entries) do
    if entry.side == 'player' then
      playerLine(ui.textScroll, entry)
    else
      npcLine(self, ui.textScroll, entry)
    end
  end
  if waiting then
    local note = g_ui.createWidget('NpcTalkNote', ui.textScroll)
    note:setText('...')
  end
  self:scrollToEnd()
end

function V:scrollToEnd()
  local bar = self.ui.textScrollBar
  scheduleEvent(function()
    if alive(bar) then bar:setValue(bar:getMaximum()) end
  end, 60)
end

-- ---------------------------------------------------------------- the keyword chips
-- `groups` from NpcTalkLogic.groups; `hint`: what to say under the NPC's name while chips are there
function V:setChips(groups)
  local ui = self.ui
  ui.chips:destroyChildren()
  self.chipWidgets, self.labelWidgets, self.groups = {}, {}, groups
  local multi = #groups > 1
  for _, g in ipairs(groups) do
    if multi then
      local label = g_ui.createWidget('NpcTalkGroupLabel', ui.chips)
      label:setText(groupName(g.id))
      label:addAnchor(AnchorTop, 'parent', AnchorTop)
      label:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      self.labelWidgets[g.id] = label
    end
    for _, word in ipairs(g.words) do
      local quest = L.isQuestWord(word)
      local chip = g_ui.createWidget(quest and 'NpcTalkQuestChip' or 'NpcTalkChip', ui.chips)
      chip:setText(quest and ('! ' .. word) or word)
      chip.word = word
      chip.fullWidth = chip:getTextSize().width + CHIP_PAD
      chip:setWidth(chip.fullWidth)
      chip:addAnchor(AnchorTop, 'parent', AnchorTop)
      chip:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      chip.onClick = function() self:fire('word', word) end
      self.chipWidgets[#self.chipWidgets + 1] = chip
    end
  end
end

-- place the chips and the labels in rows for a chips panel `width` wide; sets its height
function V:layoutChips(width)
  local ui = self.ui
  local groups = self.groups or {}
  local byWord = {}
  for _, chip in ipairs(self.chipWidgets) do byWord[chip.word] = chip end
  local flow = L.flowGroups(groups, function(word) return byWord[word] and byWord[word].fullWidth or 40 end, width,
    CHIP_H, GAP_X, GAP_Y, LABEL_H)
  for _, l in ipairs(flow.labels) do
    local w = self.labelWidgets[l.id]
    if w then w:setMarginTop(l.y) w:setMarginLeft(0) end
  end
  local used = {}
  for _, place in ipairs(flow.chips) do
    for _, chip in ipairs(self.chipWidgets) do
      if chip.word == place.word and not used[chip] then
        used[chip] = true
        chip:setMarginLeft(place.x)
        chip:setMarginTop(place.y)
        chip:setWidth(place.width)
        break
      end
    end
  end
  ui.chips:setHeight(flow.height)
  ui.chips:setMarginBottom(flow.height > 0 and 6 or 0)
  return flow.height
end

-- Yes / No / Trade: only those that fit the reply; the row has no height when none shows
function V:setButtons(shown)
  local ui = self.ui
  local any = false
  for _, id in ipairs({ 'yes', 'no', 'trade' }) do
    ui[id]:setVisible(shown[id] == true)
    if shown[id] then any = true end
  end
  ui.quickButtons:setHeight(any and 24 or 0)
  ui.quickButtons:setMarginBottom(any and 6 or 0)
  -- an equal share of the row for the buttons that show
  local count = 0
  for _, id in ipairs({ 'yes', 'no', 'trade' }) do if shown[id] then count = count + 1 end end
  self.shownButtons = count
end

function V:setQuickWidth(inner)
  local count = math.max(1, self.shownButtons or 1)
  local w = math.floor((inner - GAP_X * (count - 1)) / count)
  for _, id in ipairs({ 'yes', 'no', 'trade' }) do self.ui[id]:setWidth(math.min(w, 110)) end
end

-- ---------------------------------------------------------------- the input
function V:focusInput()
  local input = self.ui.input
  if input.recursiveFocus then
    input:recursiveFocus(KeyboardFocusReason)
  else
    self.window:focus()
    input:focus()
  end
end

function V:clearInput()
  self.ui.input:clearText()
end
