-- cliptourlogic.lua: the pure part of the test-only mechanics clip tour (test_cliptour, tools/ci/clip_tour.sh, O687).
-- Which environment arms it, the shots (one per slot of the website's "mechanics in action" section) and the timeline
-- of the tour after the game is entered. No engine calls.
ChaosClipTourLogic = {}
local L = ChaosClipTourLogic

L.ENV_ON = 'CHAOS_CLIPTOUR'
L.ENV_ACCOUNT = 'CHAOS_LIVE_ACCOUNT'
L.ENV_PASSWORD = 'CHAOS_LIVE_PASSWORD'
L.ENV_CHARACTER = 'CHAOS_LIVE_CHARACTER'
L.ENV_SHOTS = 'CHAOS_CLIPTOUR_SHOTS'   -- comma list of shot ids; empty or unset: every shot

L.GRACE_MS = 3000        -- after "ready": the recording script is waiting for the first begin line, not for this
L.LEAD_MS = 1200         -- after a begin line: the recorder needs about a second to start before the action
L.TAIL_MS = 1500         -- after the clip's seconds: the recorder has stopped, then the cleanup
L.GAP_MS = 2500          -- between the cleanup of a shot and the setup of the next
L.WATCHDOG_MS = 25 * 60000
L.WINDOW = {width = 1920, height = 1080}  -- the virtual screen of clip_tour.sh (the website's name blur boxes are cut for this size)

-- The shots. The ids are the slots of the website (website/overlay/plugins/chaos/media_lib.php chaos_media_action_slots, website/tools/
-- gen_site_media.py CLIPS); website/tools/gen_site_media_clips_test.py holds the three lists equal.
--   seconds  the length of the raw loop the recorder cuts (the site keeps 7 to 8 s of it)
--   setup    {{say = text, wait = ms}, ...}   helper lines said before the recording starts (`wait` ms after each: the answer, the walk)
--   action   {{at = ms after the begin line + LEAD_MS, say = text | window = module name | zoom = tiles | key = hotkey}, ...}
--   cleanup  the same shape as setup, after the end: closes what the shot opened
--   staging  'ready' = only windows, said helper lines the tour of the loot explosion already proved (test_loottour) or plain toggles;
--            'check'  = the helper line is the documented one (tester_helper.lua header) but the run was never filmed: the first run with
--            CLIP_DRY=1 logs every answer, fix the line here when one says "unknown" or "not here". spell-effects needs the
--            tester's attack spells on F1 to F4 (System > Helper > Auto setup, or the hotkeys window) before the run
L.SHOTS = {
  {id = 'loot-explosion', seconds = 8, staging = 'ready',
   action = {{at = 0, say = '!tester explode run'}, {at = 3600, say = '!tester explode run'}}},
  {id = 'loot-beams', seconds = 7, staging = 'ready',
   setup = {{say = '!tester explode set', wait = 1500}},
   action = {{at = 0, say = '!tester explode run'}}},
  {id = 'rift', seconds = 8, staging = 'check',
   setup = {{say = '!tester riftrun layout', wait = 9000}},
   action = {{at = 0, zoom = 11}},
   cleanup = {{say = '!tester rift close', wait = 2500}}},
  {id = 'pinnacle', seconds = 8, staging = 'check',
   setup = {{say = '!tester pinnacle set 1', wait = 2500}, {say = '!tester pinnacle path', wait = 20000}},
   action = {{at = 0, zoom = 11}},
   cleanup = {{say = '!tester pinnacle close', wait = 2500}}},
  {id = 'passive-tree', seconds = 7, staging = 'ready',
   action = {{at = 0, window = 'game_passivetree'}},
   cleanup = {{window = 'game_passivetree', wait = 800}}},
  {id = 'ember-descent', seconds = 8, staging = 'check',
   setup = {{say = '!tester descent sigil', wait = 2500}},
   action = {{at = 0, window = 'game_descent'}},
   cleanup = {{window = 'game_descent', wait = 800}}},
  {id = 'infinity-tower', seconds = 8, staging = 'ready',
   action = {{at = 0, window = 'game_infinitytower'}},
   cleanup = {{window = 'game_infinitytower', wait = 800}}},
  {id = 'dungeon-cards', seconds = 7, staging = 'ready',
   action = {{at = 0, window = 'game_dungeons'}},
   cleanup = {{window = 'game_dungeons', wait = 800}}},
  {id = 'cosmetics', seconds = 8, staging = 'ready',
   action = {{at = 0, window = 'game_cosmetics'}},
   cleanup = {{window = 'game_cosmetics', wait = 800}}},
  {id = 'spell-effects', seconds = 7, staging = 'check',
   setup = {{say = '!tester dummy give', wait = 2500}, {say = '!tester dummy path', wait = 15000}},
   action = {{at = 0, key = 'F1'}, {at = 1200, key = 'F2'}, {at = 2400, key = 'F3'}, {at = 3600, key = 'F4'}},
   cleanup = {{say = '!tester dummy clear', wait = 1500}}},
}

function L.shotIds()
  local out = {}
  for _, s in ipairs(L.SHOTS) do out[#out + 1] = s.id end
  return out
end

-- config from the environment; nil, reason when it is not armed or incomplete. getenv is os.getenv or a fake.
function L.parseEnv(getenv)
  if type(getenv) ~= 'function' then return nil, 'no environment' end
  local function get(name)
    local ok, v = pcall(getenv, name)
    if ok and type(v) == 'string' and v ~= '' then return v end
    return nil
  end
  if get(L.ENV_ON) ~= '1' then return nil, 'off' end
  local account, password = get(L.ENV_ACCOUNT), get(L.ENV_PASSWORD)
  if not account or not password then return nil, 'the environment names no account and password' end
  local ids, err = L.pickShots(get(L.ENV_SHOTS))
  if not ids then return nil, err end
  return {account = account, password = password, character = get(L.ENV_CHARACTER), shots = ids}
end

-- the shot ids a comma list names, in tour order (the order of L.SHOTS, not of the list); nil, reason on an unknown id
function L.pickShots(list)
  if not list then return L.shotIds() end
  local wanted = {}
  for id in tostring(list):gmatch('[^,%s]+') do wanted[id] = true end
  local out, known = {}, {}
  for _, s in ipairs(L.SHOTS) do
    known[s.id] = true
    if wanted[s.id] then out[#out + 1] = s.id end
  end
  for id in pairs(wanted) do
    if not known[id] then return nil, 'unknown shot ' .. id end
  end
  if #out == 0 then return L.shotIds() end
  return out
end

local function shotById(id)
  for _, s in ipairs(L.SHOTS) do if s.id == id then return s end end
end

-- the steps of one shot from t0 (ms after ready): {at, do = 'say' | 'window' | 'zoom' | 'key' | 'mark', ...}; returns steps, end time
local function shotSteps(shot, t0, out)
  local t = t0
  for _, st in ipairs(shot.setup or {}) do
    out[#out + 1] = {at = t, ['do'] = 'say', text = st.say, shot = shot.id}
    t = t + (st.wait or 0)
  end
  out[#out + 1] = {at = t, ['do'] = 'mark', what = 'begin', shot = shot.id, seconds = shot.seconds}
  local begin = t + L.LEAD_MS
  for _, a in ipairs(shot.action or {}) do
    local step = {at = begin + (a.at or 0), shot = shot.id}
    if a.say then step['do'], step.text = 'say', a.say
    elseif a.window then step['do'], step.module = 'window', a.window
    elseif a.zoom then step['do'], step.tiles = 'zoom', a.zoom
    elseif a.key then step['do'], step.key = 'key', a.key end
    out[#out + 1] = step
  end
  t = t + L.LEAD_MS + shot.seconds * 1000 + L.TAIL_MS
  out[#out + 1] = {at = t, ['do'] = 'mark', what = 'end', shot = shot.id}
  for _, c in ipairs(shot.cleanup or {}) do
    local step = {at = t, shot = shot.id}
    if c.say then step['do'], step.text = 'say', c.say else step['do'], step.module = 'window', c.window end
    out[#out + 1] = step
    t = t + (c.wait or 0)
  end
  return t
end

-- the whole tour for the shot ids, ordered by time (a stable order for equal times), ending with {do = 'exit'}
function L.timeline(ids)
  local out = {}
  local t = L.GRACE_MS
  for _, id in ipairs(ids or L.shotIds()) do
    local shot = shotById(id)
    if shot then t = shotSteps(shot, t, out) + L.GAP_MS end
  end
  out[#out + 1] = {at = t, ['do'] = 'exit'}
  for i, s in ipairs(out) do s.n = i end
  table.sort(out, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.n < b.n end)
  return out
end

function L.duration(ids)
  local tl = L.timeline(ids)
  return tl[#tl].at
end

-- the index of the character to enter: the one named character, else the first; nil when the list is empty
function L.pickCharacter(names, wanted)
  if type(names) ~= 'table' or #names == 0 then return nil end
  if wanted then
    for i, n in ipairs(names) do
      if tostring(n):lower() == tostring(wanted):lower() then return i end
    end
  end
  return 1
end

return L
