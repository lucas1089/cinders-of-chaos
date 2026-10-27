-- Interface skins: the pure logic (client/MANIFEST.md "Interface skins"). Tested by skin_core_test.lua under LuaJIT and
-- Lua 5.3; the engine side is skin_boot.lua (run from init.lua before any module loads, base patch 0159) and
-- chaos_theme.lua (palette, the choice menu).
--
-- The mechanism. A skin is a folder of override images, data/skins/<id>/, that mirrors the client's own virtual paths
-- (images/chaos/window.png, modules/game_shaderfx/images/orb_ring_150.png, ...), plus a manifest.lua that lists them
-- and carries a revision (the hash of their bytes). The engine mounts the write folder in front of the client's own
-- files, so a file copied there at the same virtual path is found first by every image-source of every style. Choosing
-- a skin therefore means: copy the skin's files into the write folder before the first window is built, and take the
-- files of the previous skin out. Textures are cached by path and styles read their images when a widget is made, so
-- the copy runs at client start (the choice is saved in g_settings 'chaos-skin' and applies at the next start).
-- 'classic' is no folder: it is the client's own files, with nothing copied (byte-identical to a client without skins).
--
-- A state file in the write folder (STATE) remembers which skin and revision is installed and which files it wrote,
-- so a start with the same choice copies nothing, and a change or an update of the art replaces exactly those files.
-- A copy that fails half way is undone: the client then runs as classic (never a half skin).

local M = {}

M.SKINS = { 'classic', 'forge', 'abyss' }
M.DEFAULT = 'classic'
M.SETTING = 'chaos-skin'
M.ENV = 'CHAOS_SKIN'                -- test runs: overrides the setting
M.ROOT = '/skins/'                  -- data/skins/<id>/ of the client
M.STATE = '/chaos_skin_state.txt'   -- in the write folder

-- English names (the window shows them through tr(); pt_br.lua translates them)
M.NAMES = { classic = 'Classic', forge = 'Forge and Embers', abyss = 'Abyssal Arcane' }

-- Palettes. OTUI has no variables, so the styles keep their own colours (client/MANIFEST.md lists them); Lua code that
-- paints (window titles, the tooltip, the menu bar) reads ChaosTheme.palette, which is the active skin's table.
M.PALETTES = {
  classic = {
    bg = '#0d0b0e', iron = '#3a3339', ironLight = '#7d7176', text = '#d6c9ae', textDim = '#8c8070',
    textDisabled = '#6b6258', gold = '#e8b84a', goldBright = '#f6cf72', blood = '#b8160f', bloodBright = '#e03a1e',
    bloodDark = '#5a0a0a', health = '#8a1010', mana = '#1f3f8f',
    accent = '#e8b84a', accent2 = '#f6cf72', title = '#e8c477', miniTitle = '#d9b25c', menuNormal = '#d6c9ae',
    menuNew = '#ffd24a', menuLocked = '#7a7466', tooltipText = '#e4d8c0',
  },
  forge = {
    bg = '#0b0908', iron = '#2f2a26', ironLight = '#5c544b', text = '#d8ccb8', textDim = '#9a8f7e',
    textDisabled = '#6b6258', gold = '#ff7a1a', goldBright = '#ffb347', blood = '#c2260f', bloodBright = '#e8431f',
    bloodDark = '#5c1408', health = '#c2260f', mana = '#2d68b8',
    accent = '#ff7a1a', accent2 = '#ffb347', title = '#ffb347', miniTitle = '#ffb347', menuNormal = '#d8ccb8',
    menuNew = '#ffb347', menuLocked = '#7a7062', tooltipText = '#d8ccb8',
  },
  abyss = {
    bg = '#06070b', iron = '#0d1019', ironLight = '#1c2234', text = '#d9d6e6', textDim = '#8d89a3',
    textDisabled = '#585670', gold = '#c9a45a', goldBright = '#e8cf8a', blood = '#d23a5a', bloodBright = '#ee5c7a',
    bloodDark = '#4f1426', health = '#d23a5a', mana = '#25b5c8',
    accent = '#8a5cf0', accent2 = '#2fd0c0', title = '#e8cf8a', miniTitle = '#e8cf8a', menuNormal = '#d9d6e6',
    menuNew = '#2fd0c0', menuLocked = '#6a6784', tooltipText = '#e4e1f0',
  },
}

-- ---------------------------------------------------------------- the choice
function M.isKnown(id)
  for _, s in ipairs(M.SKINS) do
    if s == id then return true end
  end
  return false
end

-- any value to a skin id; anything unknown (nil, a number, "Forge", a stale name) is the default
function M.normalize(value)
  if type(value) ~= 'string' then return M.DEFAULT end
  local id = value:gsub('^%s+', ''):gsub('%s+$', ''):lower()
  if M.isKnown(id) then return id end
  return M.DEFAULT
end

-- the choice to apply: the environment override, else the saved setting
function M.choose(settingValue, envValue)
  if type(envValue) == 'string' and envValue ~= '' then return M.normalize(envValue) end
  return M.normalize(settingValue)
end

function M.palette(id)
  return M.PALETTES[M.normalize(id)]
end

-- ---------------------------------------------------------------- paths
-- the folder of a skin ('/skins/forge/'); nil for classic (the client's own files)
function M.sourceDir(id)
  id = M.normalize(id)
  if id == M.DEFAULT then return nil end
  return M.ROOT .. id .. '/'
end

function M.manifestPath(id)
  local dir = M.sourceDir(id)
  return dir and (dir .. 'manifest.lua') or nil
end

-- the skin's file for a virtual path ('/images/chaos/window.png' -> '/skins/forge/images/chaos/window.png');
-- nil for classic and for a path that is not a plain absolute one
function M.mapPath(id, virtual)
  local dir = M.sourceDir(id)
  if not dir or type(virtual) ~= 'string' or virtual:sub(1, 1) ~= '/' or virtual:find('..', 1, true) then return nil end
  return dir .. virtual:sub(2)
end

-- a manifest is { rev = 'text', files = { 'images/chaos/window.png', ... } }: relative paths, no '..', no duplicates
function M.checkManifest(m)
  if type(m) ~= 'table' or type(m.rev) ~= 'string' or m.rev == '' or type(m.files) ~= 'table' or #m.files == 0 then
    return false, 'not a manifest'
  end
  local seen = {}
  for _, f in ipairs(m.files) do
    if type(f) ~= 'string' or f == '' or f:sub(1, 1) == '/' or f:find('..', 1, true) or f:find('\\', 1, true) then
      return false, 'bad path ' .. tostring(f)
    end
    if seen[f] then return false, 'twice ' .. f end
    seen[f] = true
  end
  return true
end

-- ---------------------------------------------------------------- the state file
-- "skin=forge\nrev=abc\nfile=images/chaos/window.png\n..."
function M.parseState(text)
  local st = { skin = M.DEFAULT, rev = '', files = {} }
  if type(text) ~= 'string' then return st end
  for line in (text .. '\n'):gmatch('([^\r\n]*)\r?\n') do
    local k, v = line:match('^(%a+)=(.*)$')
    if k == 'skin' then
      st.skin = M.normalize(v)
    elseif k == 'rev' then
      st.rev = v
    elseif k == 'file' and v ~= '' and v:sub(1, 1) ~= '/' and not v:find('..', 1, true) then
      st.files[#st.files + 1] = v
    end
  end
  if st.skin == M.DEFAULT then
    st.rev, st.files = '', {}
  end
  return st
end

function M.formatState(skin, rev, files)
  local out = { 'skin=' .. skin, 'rev=' .. rev }
  for _, f in ipairs(files or {}) do out[#out + 1] = 'file=' .. f end
  return table.concat(out, '\n') .. '\n'
end

-- ---------------------------------------------------------------- the plan
-- What a start has to do so the write folder holds the skin `skin` with `manifest` (nil for classic or no manifest).
-- Returns { skin, noop, remove = { '/images/..' }, dirs = { '/images/chaos' }, copy = { { from, to } }, state }.
function M.plan(state, skin, manifest)
  skin = M.normalize(skin)
  if skin ~= M.DEFAULT and not M.checkManifest(manifest) then skin = M.DEFAULT end
  local p = { skin = skin, remove = {}, dirs = {}, copy = {} }
  if skin == M.DEFAULT then
    for _, f in ipairs(state.files) do p.remove[#p.remove + 1] = '/' .. f end
    p.noop = #p.remove == 0 and state.skin == M.DEFAULT
    p.state = M.formatState(M.DEFAULT, '', {})
    return p
  end
  if state.skin == skin and state.rev == manifest.rev and #state.files == #manifest.files then
    p.noop = true
    p.state = M.formatState(skin, manifest.rev, manifest.files)
    return p
  end
  -- a change of skin, or new art: take out what the last skin wrote, then write this one (no file is overwritten)
  for _, f in ipairs(state.files) do p.remove[#p.remove + 1] = '/' .. f end
  local dirs, seen = {}, {}
  for _, f in ipairs(manifest.files) do
    p.copy[#p.copy + 1] = { from = M.ROOT .. skin .. '/' .. f, to = '/' .. f }
    local d = f:match('^(.*)/[^/]+$')
    if d and not seen[d] then
      seen[d] = true
      dirs[#dirs + 1] = '/' .. d
    end
  end
  table.sort(dirs)
  p.dirs = dirs
  p.state = M.formatState(skin, manifest.rev, manifest.files)
  return p
end

-- Run the plan through `fs` = { exists(path), mkdir(path), copy(from, to), delete(path), read(path), write(path, text),
-- manifest(id) -> table | nil } and return { skin = what is installed now, selected, changed, copied, failed }.
-- A failed copy takes back everything this run wrote and leaves classic.
function M.sync(fs, selected)
  selected = M.normalize(selected)
  local result = { selected = selected, skin = M.DEFAULT, changed = false, copied = 0, failed = 0 }
  local okRead, text = pcall(fs.read, M.STATE)
  local state = M.parseState(okRead and text or '')
  local manifest
  if selected ~= M.DEFAULT then
    local okM, m = pcall(fs.manifest, selected)
    manifest = okM and m or nil
    if manifest == nil then result.error = 'no skin files for ' .. selected end
  end
  local p = M.plan(state, selected, manifest)
  if selected ~= M.DEFAULT and p.skin == M.DEFAULT and not result.error then result.error = 'bad manifest of ' .. selected end
  if p.noop then
    result.skin = p.skin
    return result
  end
  result.changed = true
  for _, path in ipairs(p.remove) do pcall(fs.delete, path) end
  local written = {}
  for _, d in ipairs(p.dirs) do pcall(fs.mkdir, d) end
  for _, c in ipairs(p.copy) do
    local ok, done = pcall(fs.copy, c.from, c.to)
    if ok and done ~= false then
      written[#written + 1] = c.to
      result.copied = result.copied + 1
    else
      result.failed = result.failed + 1
      break
    end
  end
  if result.failed > 0 then
    for _, path in ipairs(written) do pcall(fs.delete, path) end
    result.copied = 0
    result.skin = M.DEFAULT
    result.error = 'copy failed'
    pcall(fs.write, M.STATE, M.formatState(M.DEFAULT, '', {}))
    return result
  end
  result.skin = p.skin
  pcall(fs.write, M.STATE, p.state)
  return result
end

return M
