-- Runtime of the layout mode (client/MANIFEST.md "Floating chat and central hotbar (O414)"): the mode of the logged-in
-- character, kept per character in g_settings (node chaos_layout_mode, rules in layoutmode_logic.lua), and the modules
-- that follow it. ChaosLayoutMode.get() / isAction() / set(mode) / subscribe(fn(mode)). A phone always reads classic.
-- The subscribers (game_chatpanel, game_floatchat, game_hotbar) run one frame after game start, after game_chatpanel
-- has placed the classic chat, and when the game ends. A pick made in the options is saved and used at the next login.
local M = ChaosLayoutMode

local current = M.CLASSIC
local listeners = {}
local character = nil

local function isPhone()
  local ok, v = pcall(function() return g_app.isMobile() end)
  return ok and v == true
end

local function notify()
  for _, fn in ipairs(listeners) do pcall(fn, current) end
end

function M.get() return current end
function M.isAction() return current == M.ACTION end
function M.character() return character end

-- fn(mode) is called on every change; it is called at once when the character is already loaded
function M.subscribe(fn)
  listeners[#listeners + 1] = fn
  if character then pcall(fn, current) end
end

function M.unsubscribe(fn)
  for i = #listeners, 1, -1 do
    if listeners[i] == fn then table.remove(listeners, i) end
  end
end

local function readNode(name)
  local ok, v = pcall(g_settings.getNode, name)
  return ok and v or nil
end

local function resolve()
  local player = g_game.getLocalPlayer()
  character = player and player:getName() or nil
  local node = readNode(M.NODE)
  local mode = M.resolve(node, character, M.isKnown(readNode, character), isPhone())
  -- the first resolution is kept as a pick: a new character must stay on its layout when older layout nodes get
  -- an entry for it later (game_chatpanel saves one at every logout), and a known one keeps classic until it picks
  local entry = type(node) == 'table' and character and node[character] or nil
  if character and not isPhone() and not (type(entry) == 'table' and M.valid(entry.mode)) then
    pcall(g_settings.setNode, M.NODE, M.store(node or {}, character, mode))
    pcall(g_settings.save)
  end
  return mode
end

-- The player picks a mode (the layout options, the hotbar's right-click menu). It is kept now and takes effect at the next
-- login: the two layouts move the base console and action bar between panels, which is only done once per login.
function M.set(mode)
  if not M.valid(mode) or isPhone() or not character then return false end
  local saved = M.store(readNode(M.NODE) or {}, character, mode)
  pcall(g_settings.setNode, M.NODE, saved)
  pcall(g_settings.save)
  return true
end

-- the mode the character has picked (what the next login uses); the running one is get()
function M.picked()
  local node = readNode(M.NODE)
  local entry = type(node) == 'table' and character and node[character] or nil
  return type(entry) == 'table' and M.valid(entry.mode) and entry.mode or current
end

local function onGameStart()
  addEvent(function()
    if not g_game.isOnline() then return end
    current = resolve()
    notify()
  end)
end

local function onGameEnd()
  character = nil
  current = M.CLASSIC
  notify()
end

function M.init()
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function M.terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  character = nil
  current = M.CLASSIC
  notify()
  listeners = {}
end
