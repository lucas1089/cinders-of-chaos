-- phonetest_core.lua: the pure part of the emulator play test (client_chaos_phonetest, android-client.yml smoke_play).
-- The marker file names the test account; the steps and the windows are listed here, the engine side runs them.
ChaosPhoneTestCore = {}
local M = ChaosPhoneTestCore

M.MARKER = 'phonetest_run'
M.DEFAULTS = {npc = 'Loot Buyer', monster = 'Rat'}
M.STEPS = {'login', 'enter', 'walk', 'windows', 'npc', 'fight', 'loot', 'chat', 'done'}
-- windows a player opens from the menus: each module's own toggle() opens it and closes it again
M.WINDOWS = {
  'game_skills', 'game_inventory', 'game_battle', 'game_spellbook', 'game_passivetree', 'game_codex', 'game_goals',
  'game_hunt', 'game_daily', 'game_achievements', 'game_bestiary', 'game_crafting', 'game_dungeons', 'game_pact',
  'game_battlepass', 'game_season', 'game_partyfinder', 'game_leaderboard', 'game_shop', 'game_market',
}

-- "key=value" lines (account, password, npc, monster); nil, reason without an account and a password
function M.parseMarker(text)
  local out = {}
  for k, v in pairs(M.DEFAULTS) do out[k] = v end
  for line in tostring(text or ''):gmatch('[^\r\n]+') do
    local k, v = line:match('^%s*([%a_]+)%s*=%s*(.-)%s*$')
    if k and v ~= '' then out[k:lower()] = v end
  end
  if not out.account or not out.password then
    return nil, 'the marker names no account and password'
  end
  return out
end

-- a window fits when it lies inside the screen; returns fits, text
function M.fits(x, y, w, h, sw, sh)
  local ok = x >= 0 and y >= 0 and x + w <= sw and y + h <= sh
  return ok, ('%dx%d at %d,%d on %dx%d%s'):format(w, h, x, y, sw, sh, ok and '' or ' (outside the screen)')
end

-- how many of the walk steps moved the character
function M.moved(positions)
  local n = 0
  for i = 2, #positions do
    local a, b = positions[i - 1], positions[i]
    if a and b and (a.x ~= b.x or a.y ~= b.y or a.z ~= b.z) then n = n + 1 end
  end
  return n
end

return M
