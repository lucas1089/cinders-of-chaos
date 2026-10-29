-- Clean start after an update: the pure logic (client/MANIFEST.md "Clean start after an update"). Tested by
-- cleanup_core_test.lua under LuaJIT and Lua 5.3; the engine side is cleanup_boot.lua (run from skin_boot.lua, before any
-- module is discovered).
--
-- Why. The engine searches the per-user write folder (%APPDATA%\CindersOfChaos\CindersOfChaos on Windows) before the
-- client's own files, so any copy of a file left there hides the new one of the same virtual path: an old update tree
-- (chaos_update/files, mounted in front of the pack), old skin images, old downloads. On a new client package, and on a
-- new in-game update, everything in that folder that is not the player's own data is removed. The player's data is an
-- explicit keep-list (below); every other name goes. Nothing outside the write folder is ever reached: all paths are
-- virtual paths of the engine, and the engine only deletes inside its write folder.

local M = {}

M.STAMP = '/chaos_clean_stamp.txt'     -- in the write folder: which package and update the folder was cleaned for
M.TREE_NAME = 'chaos_update'           -- the verified update files (updater_core.lua ROOT)
M.ENCRYPTION = 'chaos-blob-1'          -- updater_core.lua ENCRYPTION
M.MAX_DEPTH = 24
M.MAX_REMOVALS = 400000

-- The player's own data: top-level names of the write folder that are never removed (compared in lower case).
M.KEEP_NAMES = {
  ['config.otml'] = true,        -- g_settings: options, hotkeys, action bars, remembered accounts and characters, chat, skin choice
  ['config.otml.bak'] = true,
  ['characterdata'] = true,      -- per character: hotkeys, action bars, helper setup
  ['settings'] = true,           -- client option files
  ['settings.json'] = true,
  ['minimap.otmm'] = true,       -- the explored map
  ['minimap.otmm.bak'] = true,
  ['bot'] = true,                -- the player's own scripts and bot configs
  ['screenshots'] = true,
  [M.STAMP:sub(2)] = true,       -- this module's own marker
}

-- Names kept by shape: logs (optional keep), the engine's other minimap backups, player preferences of this client
-- written as files with a hyphen name (chaos-*; the internal files use an underscore: chaos_update, chaos_skin_state).
function M.keepName(name)
  if type(name) ~= 'string' or name == '' then return true end   -- never touch what cannot be named
  local l = name:lower()
  if M.KEEP_NAMES[l] then return true end
  if l:find('%.log$') or l:find('%.log%.old$') or l:find('%.log%.%d+$') then return true end
  if l:find('^minimap%.otmm') then return true end
  if l:find('^config%.otml') then return true end
  if l:find('^chaos%-') then return true end
  return false
end

-- A name the engine listed is one path segment: no separators, no dots-only, no drive, no control characters.
function M.safeName(name)
  if type(name) ~= 'string' or name == '' or #name > 200 then return false end
  if name == '.' or name == '..' or name:find('[/\\:%c]') or name:find('..', 1, true) then return false end
  return true
end

-- ---------------------------------------------------------------- the stamp
function M.parseStamp(text)
  local st = { package = '', update = 0 }
  for line in tostring(text or ''):gmatch('[^\r\n]+') do
    local k, v = line:match('^(%a+)=(.*)$')
    if k == 'package' then st.package = v elseif k == 'update' then st.update = tonumber(v) or 0 end
  end
  return st
end

function M.formatStamp(packageId, update)
  return ('package=%s\nupdate=%d\n'):format(tostring(packageId or ''), tonumber(update) or 0)
end

-- ---------------------------------------------------------------- the decision
-- The update tree is worth keeping when the last apply finished, for this client package, with encrypted files, and is
-- not older than the package's own files (Services.update.baseline: a pack built after an update went live has newer
-- files than that update; its tree would hide them).
function M.treeUsable(st, packageId, baseline)
  if type(st) ~= 'table' then return false end
  baseline = tonumber(baseline) or 0
  return st.status == 'ok' and st.package == packageId and st.enc == M.ENCRYPTION and (tonumber(st.version) or 0) >= baseline
end

-- ctx = { packageId, stamp (parsed), treeState (updater's parsed state.txt, {} when none), treeExists, baseline }
-- Returns { run, keepTree, update, reason }: whether to sweep, whether chaos_update stays, the update number the stamp
-- will record.
function M.decide(ctx)
  local st = ctx.treeState or {}
  local usable = ctx.treeExists and M.treeUsable(st, ctx.packageId, ctx.baseline) or false
  local update = usable and (tonumber(st.version) or 0) or 0
  -- a half-applied update of this package is the updater's to finish, not stale
  local applying = ctx.treeExists and st.status == 'applying' and st.package == ctx.packageId
  local d = { keepTree = usable or applying or false, update = update, run = false }
  local stamp = ctx.stamp or M.parseStamp('')
  if stamp.package ~= ctx.packageId then
    d.run, d.reason = true, 'new client package'
  elseif ctx.treeExists and not d.keepTree then
    d.run, d.reason = true, 'update files older than the package or from another one'
  elseif stamp.update ~= update and not applying then
    d.run, d.reason = true, 'new update'
  end
  return d
end

-- ---------------------------------------------------------------- the sweep
-- fs = { list(path) -> { names }, isDir(path) -> bool, inWrite(path) -> bool, delete(path) -> bool }.
-- Removes every top-level entry of the write folder that is not kept; a folder is emptied (children first) and removed.
-- A node that the engine finds somewhere else than in the write folder (the client's own files) is left alone.
-- Returns { removed, failed, kept = { names }, stopped }.
function M.sweep(fs, opts)
  opts = opts or {}
  local res = { removed = 0, failed = 0, kept = {}, stopped = false }
  local function remove(path, depth)
    if res.removed >= M.MAX_REMOVALS or depth > M.MAX_DEPTH then res.stopped = true; return false end
    if not fs.inWrite(path) then return false end
    local ok = true
    if fs.isDir(path) then
      local okList, names = pcall(fs.list, path)
      for _, name in ipairs(okList and names or {}) do
        if M.safeName(name) then
          if not remove(path .. '/' .. name, depth + 1) then ok = false end
        else
          ok = false
        end
      end
      if not ok then return false end
    end
    local okDel, done = pcall(fs.delete, path)
    if okDel and done ~= false then
      res.removed = res.removed + 1
      return true
    end
    res.failed = res.failed + 1
    return false
  end
  local okTop, top = pcall(fs.list, '/')
  for _, name in ipairs(okTop and top or {}) do
    if not M.safeName(name) or M.keepName(name) or (opts.keepTree and name == M.TREE_NAME) then
      if M.safeName(name) and M.keepName(name) then res.kept[#res.kept + 1] = name end
    elseif fs.inWrite('/' .. name) then
      remove('/' .. name, 1)
    end
  end
  return res
end

return M
