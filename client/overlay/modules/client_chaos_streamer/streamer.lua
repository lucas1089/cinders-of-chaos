-- Streamer mode (O411; client/MANIFEST.md "Streamer and cinema modes"). Options > Misc. (base patch 0186) or Ctrl+Shift+S.
-- While on:
--   * an incoming private message shows "(private message hidden: streamer mode)" in the chat and on screen; with
--     "Also hide who sent a private message" the sender is "[hidden]" too (game_console's Chat class, wrapped);
--   * the window title is the client's name alone (g_window.setTitle, wrapped: the base adds " - <character>");
--   * the login screen hides the text of the account field and of the server address field (the password field is
--     always hidden); the character select shows only the chosen character's name (client_chaos_charselect asks
--     ChaosStreamer.listName), the stock character list too;
--   * IP addresses in server messages in the chat are masked;
--   * with "Also hide my name above my character" the own name is not drawn (Creature.setInfoHide, base patch 0186);
--   * a STREAMER badge sits next to the top menu (client_chaos_topbar).
-- There is no private message sound in this client (the base's "Privates Messages" sound box plays nothing), so there
-- is nothing to mute. The options live in g_settings (the base patch's dataset entries write the same keys); without
-- the patch the hotkey still works and the choice is saved.
-- Global (not sandboxed): ChaosStreamer.isOn(), .opts(), .toggle(), .setOption(key, value), .onOption(key, value),
-- .listName(name, isSelected), .setCinema(on), .addListener(fn).

ChaosStreamer = ChaosStreamer or {}
local M = ChaosStreamer
local C = StreamerCore

local TICK_MS = 500          -- while on: the login fields and the stock character list are checked this often
local HOOK_TRIES = 120       -- game_console loads after this module: its Chat class is looked for every 500 ms

local opts = C.normalize(nil)
local listeners = {}
local tickEvent, hookEvent
local hookTries = 0
local origSetTitle
local lastTitle
local chatHooks = nil        -- { class, talk, text, ourTalk, ourText }
local forcedHidden = {}      -- text edits this module hid: [widget] = their own hidden state before
local cinemaOn = false

local function tr(s, ...)
  local f = rawget(_G, 'tr')
  if f then return f(s, ...) end
  if select('#', ...) > 0 then return string.format(s, ...) end
  return s
end

local function alive(w)
  return w ~= nil and w ~= false and not w:isDestroyed()
end

local function readSaved()
  local raw = {}
  for _, k in ipairs(C.KEYS) do
    local ok, v = pcall(g_settings.getBoolean, k, C.DEFAULTS[k])
    if ok then raw[k] = v end
  end
  return C.normalize(raw)
end

function M.opts() return opts end
function M.isOn() return opts.streamerMode == true end

-- what the lists show for a character (client_chaos_charselect and the stock list)
function M.listName(name, isSelected)
  return C.listName(name, isSelected, opts, tr)
end

function M.addListener(fn)
  listeners[#listeners + 1] = fn
end

-- ---------------------------------------------------------------- window title
local function appName()
  return g_app and g_app.getName and g_app.getName() or ''
end

local function applyTitle()
  if not origSetTitle then return end
  local wanted = lastTitle
  if not wanted then
    local online = g_game and g_game.isOnline and g_game.isOnline()
    wanted = online and (appName() .. ' - ' .. g_game.getCharacterName()) or appName()
  end
  pcall(origSetTitle, C.title(wanted, appName(), opts))
end

local function hookTitle()
  if origSetTitle or not g_window or type(g_window.setTitle) ~= 'function' then return end
  origSetTitle = g_window.setTitle
  g_window.setTitle = function(title)
    lastTitle = title
    return origSetTitle(C.title(title, appName(), opts))
  end
end

local function unhookTitle()
  if origSetTitle and g_window then g_window.setTitle = origSetTitle end
  origSetTitle = nil
end

-- ---------------------------------------------------------------- chat
local function consoleChat()
  local console = modules and modules.game_console
  local chat = console and rawget(console, 'Chat')
  if type(chat) == 'table' and type(chat.onTalk) == 'function' then return chat end
  return nil
end

local function hookChat()
  if chatHooks then return true end
  local chat = consoleChat()
  if not chat then return false end
  local h = { class = chat, talk = chat.onTalk, text = chat.onTextMessage }
  h.ourTalk = function(self, name, level, mode, text, ...)
    if opts.streamerMode and C.isPrivateIncoming(mode, MessageModes) then
      -- the ignore list sees the real sender (the masked name would pass it)
      if self.ignoreMessage and not self:ignoreMessage(mode, name) then return end
      name, text = C.maskTalk(opts, name, mode, text, MessageModes, tr)
    end
    return h.talk(self, name, level, mode, text, ...)
  end
  chat.onTalk = h.ourTalk
  if type(h.text) == 'function' then
    h.ourText = function(self, mode, text, ...)
      return h.text(self, mode, C.maskIps(text, opts), ...)
    end
    chat.onTextMessage = h.ourText
  end
  chatHooks = h
  return true
end

local function unhookChat()
  local h = chatHooks
  if not h then return end
  if h.class.onTalk == h.ourTalk then h.class.onTalk = h.talk end
  if h.ourText and h.class.onTextMessage == h.ourText then h.class.onTextMessage = h.text end
  chatHooks = nil
end

local function tryHookChat()
  hookEvent = nil
  if hookChat() then return end
  hookTries = hookTries + 1
  if hookTries < HOOK_TRIES then hookEvent = scheduleEvent(tryHookChat, 500) end
end

-- ---------------------------------------------------------------- login fields and lists
local function hideText(edit, on)
  if not alive(edit) or type(edit.setTextHidden) ~= 'function' then return end
  if on then
    if forcedHidden[edit] == nil then
      local ok, was = pcall(edit.isTextHidden, edit)
      forcedHidden[edit] = ok and was == true
    end
    if not edit:isTextHidden() then edit:setTextHidden(true) end
  elseif forcedHidden[edit] ~= nil then
    edit:setTextHidden(forcedHidden[edit])
    forcedHidden[edit] = nil
  end
end

local function applyLogin(on)
  local root = g_ui.getRootWidget()
  local eg = root and root:recursiveGetChildById('enterGame')
  if alive(eg) then
    hideText(eg:recursiveGetChildById('accountNameTextEdit'), on)
  end
  -- the server address field: the login module moves the server selector onto the background
  hideText(root and root:recursiveGetChildById('serverHostTextEdit'), on)
  for edit in pairs(forcedHidden) do
    if not alive(edit) then forcedHidden[edit] = nil end
  end
end

-- the stock character list (the in-game switch, or the login with the stock look)
local function applyStockList(on)
  local root = g_ui.getRootWidget()
  local w = root and root:getChildById('charactersWindow')
  local list = alive(w) and w:getChildById('characters') or nil
  if not alive(list) or not w:isVisible() then return end
  local focused = list:getFocusedChild()
  for _, row in ipairs(list:getChildren()) do
    local label = row:getChildById('name')
    if label and row.characterName then
      local want = on and C.listName(row.characterName, row == focused, opts, tr) or row.characterName
      if label:getText() ~= want then label:setText(want) end
    end
  end
end

local function applyCharSelect()
  local cs = modules and modules.client_chaos_charselect
  local api = cs and rawget(cs, 'CharSelect')
  if api and api.refreshNames then pcall(api.refreshNames) end
end

local function applyBadge()
  local top = modules and modules.client_chaos_topbar
  local api = top and rawget(top, 'ChaosTopBar')
  if api and api.setBadge then
    pcall(api.setBadge, 'streamer', opts.streamerMode and tr('STREAMER') or nil,
      tr('Streamer mode is on (Ctrl+Shift+S). Options > Misc.'))
  end
end

local function applyInfoHide()
  if Creature and Creature.setInfoHide then
    pcall(Creature.setInfoHide, C.infoHideMask(opts, cinemaOn))
  end
end

local function tick()
  tickEvent = nil
  if not opts.streamerMode then return end
  applyLogin(true)
  applyStockList(true)
  tickEvent = scheduleEvent(tick, TICK_MS)
end

local function applyAll()
  local on = opts.streamerMode
  applyTitle()
  applyLogin(on)
  applyStockList(on)
  applyCharSelect()
  applyBadge()
  applyInfoHide()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if on then tickEvent = scheduleEvent(tick, TICK_MS) end
  for _, fn in ipairs(listeners) do pcall(fn, opts) end
end

-- cinema.lua tells the info mask when cinema mode starts and ends
function M.setCinema(on)
  cinemaOn = on == true
  applyInfoHide()
end

-- ---------------------------------------------------------------- options
-- the options' apply (dataset.lua, base patch 0186) and the hotkeys
function M.onOption(key, value)
  if C.DEFAULTS[key] == nil then return end
  local before = opts.streamerMode
  opts[key] = value == true
  applyAll()
  if key == 'streamerMode' and before ~= opts.streamerMode and modules and modules.game_textmessage then
    local tm = modules.game_textmessage
    if tm.displayStatusMessage and g_game.isOnline() then
      pcall(tm.displayStatusMessage, opts.streamerMode and tr('Streamer mode on.') or tr('Streamer mode off.'))
    end
  end
end

-- writes the option through the settings module (the checkbox follows) or, without base patch 0186, g_settings
function M.setOption(key, value)
  local cs = modules and modules.client_settings
  local go = cs and rawget(cs, 'GameOptions')
  if go and go.getDataSet and go:getDataSet(key) then
    local ok = pcall(go.setOption, go, key, value)
    if ok then
      if opts[key] ~= (value == true) then M.onOption(key, value) end
      return
    end
  end
  pcall(g_settings.set, key, value)
  M.onOption(key, value)
end

function M.toggle()
  M.setOption('streamerMode', C.toggled(opts, 'streamerMode'))
end

-- ---------------------------------------------------------------- lifecycle
local function onGameStart()
  if not chatHooks then
    hookTries = 0
    if hookEvent then removeEvent(hookEvent) end
    tryHookChat()
  end
  applyAll()
end

local function onGameEnd()
  lastTitle = nil
  applyAll()
end

function M.init()
  opts = readSaved()
  hookTitle()
  hookTries = 0
  tryHookChat()
  g_keyboard.bindKeyDown(C.HOTKEY_STREAMER, M.toggle)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  -- after the other modules' first layout (login screen, top menu)
  scheduleEvent(applyAll, 1000)
end

function M.terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  pcall(g_keyboard.unbindKeyDown, C.HOTKEY_STREAMER)
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if hookEvent then removeEvent(hookEvent) hookEvent = nil end
  applyLogin(false)
  applyStockList(false)
  local was = opts.streamerMode
  opts.streamerMode = false
  applyBadge()
  applyCharSelect()
  applyTitle()
  opts.streamerMode = was
  if Creature and Creature.setInfoHide then pcall(Creature.setInfoHide, 0) end
  unhookChat()
  unhookTitle()
  listeners = {}
end
