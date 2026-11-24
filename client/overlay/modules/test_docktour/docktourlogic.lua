-- docktourlogic.lua: the pure part of the test-only side dock tour (test_docktour, tools/ci/dock_video.sh, O732).
-- Which environment arms it and the step timeline after the game is entered. No engine calls.
ChaosDockTourLogic = {}
local L = ChaosDockTourLogic

L.ENV_ON = 'CHAOS_DOCKTOUR'
L.ENV_ACCOUNT = 'CHAOS_LIVE_ACCOUNT'
L.ENV_PASSWORD = 'CHAOS_LIVE_PASSWORD'
L.ENV_CHARACTER = 'CHAOS_LIVE_CHARACTER'

L.GRACE_MS = 4000         -- the recording starts on the ready line and needs about a second; the dock is closed until then
L.KEY_CHECK_MS = 1500     -- a key step looks this long after its line whether the key (sent by the recording script) worked
L.CARD_SHOW_MS = 1500     -- a How it works card stays this long (its place beside the dock is filmed), then closes
L.WINDOW = {width = 1280, height = 720}
L.WATCHDOG_MS = 10 * 60000

-- the steps: do = 'key' (the script presses `key`; the dock must then be `open`), 'tab' (a click on the tab button `tab`),
-- 'sub' (a click on the sub tab `sub` of the tab shown), 'scroll' (the dock's scroll bar to its end, a window taller
-- than the dock: nothing cut, O732 follow-up), 'still' (a picture is cut here: `name`), 'exit'. gap = ms after
-- the step before.
L.STEPS = {
  {gap = 0, ['do'] = 'still', name = 'closed'},
  {gap = 0, ['do'] = 'key', key = 'Alt+D', open = true, tab = 'equip'},
  {gap = 3500, ['do'] = 'still', name = 'equip'},
  {gap = 1000, ['do'] = 'key', key = 'Alt+Q', open = true, tab = 'quests'},
  {gap = 3500, ['do'] = 'still', name = 'quests'},
  {gap = 500, ['do'] = 'scroll'},
  {gap = 2000, ['do'] = 'still', name = 'quests_bottom'},
  {gap = 500, ['do'] = 'sub', sub = 2},
  {gap = 3500, ['do'] = 'still', name = 'main_quest'},
  {gap = 500, ['do'] = 'sub', sub = 3},
  {gap = 3500, ['do'] = 'key', key = 'Alt+A', open = true, tab = 'attributes'},
  {gap = 3500, ['do'] = 'still', name = 'attributes'},
  {gap = 500, ['do'] = 'sub', sub = 2},
  {gap = 3500, ['do'] = 'still', name = 'character_info'},
  {gap = 500, ['do'] = 'scroll'},
  {gap = 2000, ['do'] = 'still', name = 'character_info_bottom'},
  {gap = 500, ['do'] = 'tab', tab = 'spells'},
  {gap = 3500, ['do'] = 'still', name = 'spells_wide'},
  {gap = 500, ['do'] = 'sub', sub = 2},
  {gap = 3500, ['do'] = 'still', name = 'spell_supports'},
  {gap = 500, ['do'] = 'scroll'},
  {gap = 2000, ['do'] = 'still', name = 'spell_supports_bottom'},
  {gap = 500, ['do'] = 'tab', tab = 'shop'},
  {gap = 4000, ['do'] = 'still', name = 'shop_market'},
  {gap = 500, ['do'] = 'scroll'},
  {gap = 2000, ['do'] = 'still', name = 'shop_market_bottom'},
  {gap = 500, ['do'] = 'sub', sub = 2},
  {gap = 4000, ['do'] = 'still', name = 'shop_store'},
  {gap = 500, ['do'] = 'scroll'},
  {gap = 2000, ['do'] = 'still', name = 'shop_store_bottom'},
  {gap = 500, ['do'] = 'tab', tab = 'equip'},
  {gap = 3500, ['do'] = 'key', key = 'Alt+D', open = false},
  {gap = 3000, ['do'] = 'still', name = 'closed_again'},
  {gap = 1500, ['do'] = 'exit'},
}

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
  return {account = account, password = password, character = get(L.ENV_CHARACTER)}
end

-- the steps with their time from the ready line: a copy of STEPS with at = GRACE_MS + the gaps so far
function L.timeline()
  local out, t = {}, L.GRACE_MS
  for _, s in ipairs(L.STEPS) do
    t = t + s.gap
    local c = {at = t}
    for k, v in pairs(s) do c[k] = v end
    out[#out + 1] = c
  end
  return out
end

function L.duration()
  local tl = L.timeline()
  return tl[#tl].at
end

-- whether a key step worked: the dock's open state (and tab when named) as the step wants it
function L.keyWorked(step, isOpen, tab)
  if step.open ~= (isOpen == true) then return false end
  if step.open and step.tab and step.tab ~= tab then return false end
  return true
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
