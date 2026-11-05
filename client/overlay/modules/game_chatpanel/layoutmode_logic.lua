-- Layout mode of one character (client/MANIFEST.md "Floating chat and central hotbar (O414)"; layoutmode_test.lua).
-- "classic": the chat in the bottom splitter with the orbs beside it (game_chatpanel, as before).
-- "action": a floating chat (game_floatchat) and the central hotbar (game_hotbar). PC only.
-- Global ChaosLayoutMode (loaded with game_chatpanel, which stands down in the action mode).
ChaosLayoutMode = ChaosLayoutMode or {}
local M = ChaosLayoutMode

M.CLASSIC = 'classic'
M.ACTION = 'action'
M.NODE = 'chaos_layout_mode' -- { [character] = { mode = 'classic' | 'action' } }
-- client settings nodes that only a character that played with an older client has an entry in
M.KNOWN_NODES = { 'chaos_chatpanel', 'chaos_layout', 'chaos_view', 'chaosHudPos' }

function M.valid(mode)
  return mode == M.CLASSIC or mode == M.ACTION
end

-- The mode of a character. saved: the node M.NODE; known: the character already has a saved layout from an older
-- client (an entry in one of M.KNOWN_NODES); phone: phones always keep the classic layout.
-- A pick wins; without one a known character keeps the classic layout, a new one gets the action bar layout.
function M.resolve(saved, name, known, phone)
  if phone then return M.CLASSIC end
  local entry = type(saved) == 'table' and name and saved[name] or nil
  if type(entry) == 'table' and M.valid(entry.mode) then return entry.mode end
  if known then return M.CLASSIC end
  return M.ACTION
end

-- the node with this character's pick set (a bad mode leaves it alone)
function M.store(saved, name, mode)
  saved = type(saved) == 'table' and saved or {}
  if not name or not M.valid(mode) then return saved end
  saved[name] = { mode = mode }
  return saved
end

-- whether any of the nodes holds an entry for the character. read(nodeName) gives the node table (or nil).
function M.isKnown(read, name)
  if not name then return false end
  for _, node in ipairs(M.KNOWN_NODES) do
    local t = read(node)
    if type(t) == 'table' and t[name] ~= nil then return true end
  end
  return false
end

function M.isAction(mode)
  return mode == M.ACTION
end

return M
