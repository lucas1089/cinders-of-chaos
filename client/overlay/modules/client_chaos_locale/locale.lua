-- client_chaos_locale: the client's language, English or Portuguese (Brazil) (client/MANIFEST.md "Localization").
--
-- * tr(): every Chaos module writes its texts as tr('English %s', x) (OTUI: !text: tr('English')). This module puts
--   its tr in front of the base client's one: the pt-BR table (pt_br.lua) first, then the base client's tr (its own
--   locale files translate the base windows), then the English. A module that defines tr later (client_locales) does
--   not replace it: the global `tr` is served by a hook on _G's metatable and a later `tr = f` becomes the base one.
-- * The choice: g_settings 'chaos-language' ('pt-BR' | 'en'). The first run takes pt-BR when the system's locale is
--   Portuguese (locale_core.lua L.fromSystem), else English. The base client's locale follows (client_locales
--   setLocale 'pt' / 'en', when it has one).
-- * Where to change it: Options > Interface > Language (base patch 0053), the login screen and the character list
--   (client_chaos_login, client_chaos_charselect): ChaosLocale.showMenu(widget) opens the choice.
-- * A change reloads the modules at once when not in game (windows built from OTUI read their texts when loaded); in
--   game it says that the rest follows at the next login and reloads them when the game ends.
-- * The server writes its texts in the player's language too: the language goes with the display scale hello on
--   opcode 157 ({action = 'hello', lang}) at every game start and at a change (server i18n.lua, Chaos.t).

-- the hook below runs for every global lookup that misses: it must not look up globals itself
local type, rawget, rawset, pcall, getmetatable, setmetatable = type, rawget, rawset, pcall, getmetatable, setmetatable

ChaosLocale = ChaosLocale or {}
local M = ChaosLocale
local L = ChaosLocaleCore
local SETTING = 'chaos-language'
local OPCODE = 157

M.lang = M.lang or 'en'
M.tables = M.tables or {}

-- ---------------------------------------------------------------- tr
local function chaosTr(text, ...)
  local hook = rawget(_G, '__chaosTrHook')
  return L.translate(M.table, hook and hook.base or nil, text, ...)
end

local function installHook()
  if rawget(_G, '__chaosTrHook') then
    return true
  end
  local hook = { base = rawget(_G, 'tr') }
  local ok = pcall(function()
    local mt = getmetatable(_G)
    if mt == nil then
      mt = {}
      setmetatable(_G, mt)
    end
    local oldIndex, oldNewIndex = mt.__index, mt.__newindex
    mt.__index = function(t, k)
      if k == 'tr' then return chaosTr end
      if type(oldIndex) == 'function' then return oldIndex(t, k) end
      if type(oldIndex) == 'table' then return oldIndex[k] end
      return nil
    end
    mt.__newindex = function(t, k, v)
      if k == 'tr' then
        if v ~= chaosTr then hook.base = v end
        return
      end
      if type(oldNewIndex) == 'function' then return oldNewIndex(t, k, v) end
      if type(oldNewIndex) == 'table' then oldNewIndex[k] = v return end
      rawset(t, k, v)
    end
    rawset(_G, 'tr', nil)
  end)
  if not ok then
    -- _G's metatable is locked: a plain wrap (re-checked at every game start)
    rawset(_G, 'tr', chaosTr)
    hook.plain = true
  end
  rawset(_G, '__chaosTrHook', hook)
  return ok
end

local function rewrapPlain()
  local hook = rawget(_G, '__chaosTrHook')
  if hook and hook.plain and rawget(_G, 'tr') ~= chaosTr then
    hook.base = rawget(_G, 'tr')
    rawset(_G, 'tr', chaosTr)
  end
end

-- ---------------------------------------------------------------- the system's language
local function systemNames()
  local names = {}
  if os and os.getenv then
    for _, v in ipairs({ 'LC_ALL', 'LC_MESSAGES', 'LANG', 'LANGUAGE' }) do
      local ok, val = pcall(os.getenv, v)
      if ok and val then names[#names + 1] = val end
    end
  end
  -- the C library's name of the user's locale ("Portuguese_Brazil.1252" on Windows, "pt_BR.UTF-8" on Linux); the
  -- process keeps its own locale (number formatting stays as it is)
  if os and os.setlocale then
    local ok, current = pcall(os.setlocale, nil)
    local ok2, native = pcall(os.setlocale, '')
    if ok and current then pcall(os.setlocale, current) end
    if ok2 and native then names[#names + 1] = native end
  end
  return names
end

-- ---------------------------------------------------------------- base client, server
local function baseLocaleName()
  local cl = modules and modules.client_locales
  if not cl or not cl.getCurrentLocale then return nil end
  local ok, cur = pcall(cl.getCurrentLocale)
  return ok and type(cur) == 'table' and cur.name or nil
end

-- the base client's locale to the one of `lang`; true when it changed
local function syncBase(lang)
  local cl = modules and modules.client_locales
  if not cl or not cl.setLocale then return false end
  local before = baseLocaleName()
  for _, name in ipairs(L.BASE_NAMES[lang] or {}) do
    if before == name then return false end
    local ok, r = pcall(cl.setLocale, name)
    if ok and r ~= false and baseLocaleName() == name then return true end
  end
  return false
end

local function sendHello()
  if not (g_game and g_game.isOnline and g_game.isOnline()) then return end
  local protocol = g_game.getProtocolGame()
  if protocol and json then
    protocol:sendExtendedOpcode(OPCODE, json.encode(L.hello(M.lang)))
  end
end

-- ---------------------------------------------------------------- the choice
local reloadOnEnd = false

local function reload()
  if g_modules and g_modules.reloadModules then
    scheduleEvent(function() pcall(g_modules.reloadModules) end, 50)
  end
end

local function onGameStart()
  rewrapPlain()
  sendHello()
end

local function onGameEnd()
  if reloadOnEnd then
    reloadOnEnd = false
    reload()
  end
end

function M.get()
  return M.lang
end

function M.name(lang)
  return L.NAMES[lang or M.lang] or tostring(lang)
end

function M.set(lang, quiet)
  lang = L.normalize(lang)
  if not lang then return false end
  local changed = lang ~= M.lang
  M.lang = lang
  M.table = lang ~= 'en' and M.tables[lang] or nil
  pcall(g_settings.set, SETTING, lang)
  local baseChanged = syncBase(lang)
  sendHello()
  if quiet or not (changed or baseChanged) then return true end
  if g_game and g_game.isOnline and g_game.isOnline() then
    reloadOnEnd = true
    if displayInfoBox then
      displayInfoBox(tr('Language'), tr('Language: %s. New windows and the server messages use it now; the rest follows at the next login.', M.name(lang)))
    end
  else
    reload()
  end
  return true
end

-- a menu with the languages under `widget` (Options, the login screen and the character list)
function M.showMenu(widget)
  local menu = g_ui.createWidget('PopupMenu')
  if menu.setGameMenu then menu:setGameMenu(g_game and g_game.isOnline and g_game.isOnline() or false) end
  for _, lang in ipairs(L.LANGS) do
    local mark = lang == M.lang and '> ' or '   '
    menu:addOption(mark .. M.name(lang), function() M.set(lang) end)
  end
  local pos = widget and widget.getPosition and widget:getPosition() or g_window.getMousePosition()
  if widget and widget.getHeight then pos = { x = pos.x, y = pos.y + widget:getHeight() } end
  menu:display(pos)
  return menu
end

-- the text of a language button: "Idioma: Português (Brasil)" / "Language: English"
function M.buttonText()
  return tr('Language: %s', M.name(M.lang))
end

function init()
  M.tables['pt-BR'] = L.prepare(ChaosLocaleStrings and ChaosLocaleStrings['pt-BR'])
  installHook()
  local ok, saved = pcall(g_settings.getString, SETTING)
  local lang = L.choose(ok and saved ~= '' and saved or nil, systemNames())
  M.set(lang, true)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  -- the base client's locales load after this module: match them once everything is loaded (the base windows of a
  -- first Portuguese run are rebuilt in Portuguese then)
  scheduleEvent(function()
    rewrapPlain()
    if syncBase(M.lang) and not (g_game and g_game.isOnline and g_game.isOnline()) then
      reload()
    end
  end, 100)
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
end
