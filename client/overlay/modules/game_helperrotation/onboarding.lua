-- The first steps of a new character (owner design 2026-10-16: no tutorial island; client/MANIFEST.md "Helper
-- onboarding"). The server's welcome toast (game_chaosnotify, action "newplayer") carries openHelper = true and a hint
-- at a character's first login: the Helper window opens (modules.game_helper.toggle, as the top menu's Helper entry)
-- and its Auto setup button (autosetup_ui.lua) blinks with the hint under it, until it is clicked or for blinkMs.
-- Nothing is set up by itself: the player presses the button. Pure helpers (O.plan, O.blinkFrames) are tested by
-- onboarding_test.lua.
ChaosHelperOnboarding = ChaosHelperOnboarding or {}
local O = ChaosHelperOnboarding

O.HINT_ID = 'chaosOnboardingHint'
O.blinkMs = 12000
O.stepMs = 400
O.GOLD = '#ffd040'

-- what to do for a message: nil (not ours) or {toggle = bool (the window is hidden), hint = text}
function O.plan(data, windowVisible, fallbackHint)
  if type(data) ~= 'table' or not data.openHelper then return nil end
  local hint = type(data.hint) == 'string' and data.hint ~= '' and data.hint or fallbackHint
  return { toggle = not windowVisible, hint = hint }
end

-- the blink: one frame per stepMs over blinkMs, alternating gold and the button's own colour, ending on its own
function O.blinkFrames(blinkMs, stepMs)
  local n = math.max(0, math.floor((blinkMs or 0) / math.max(1, stepMs or 1)))
  if n % 2 == 1 then n = n + 1 end
  local frames = {}
  for i = 1, n do frames[i] = (i % 2 == 1) end
  return frames
end

local blinkEvent = nil

local function stop()
  if blinkEvent then removeEvent(blinkEvent) blinkEvent = nil end
  local root = g_ui and g_ui.getRootWidget()
  local hint = root and root:recursiveGetChildById(O.HINT_ID)
  if hint then hint:destroy() end
  local b = root and ChaosAutoSetupUI and root:recursiveGetChildById(ChaosAutoSetupUI.BUTTON_ID)
  if b and b.chaosOnboardColor then b:setColor(b.chaosOnboardColor) b.chaosOnboardColor = nil end
end
O.stop = stop

local function helperWindow()
  local root = g_ui.getRootWidget()
  return root and root:recursiveGetChildById('helperWindow')
end

-- open the Helper on its Auto setup button (data: the toast's message)
function O.open(data)
  local win = helperWindow()
  local p = O.plan(data, win ~= nil and win:isVisible(), tr('Set up your helper in one click'))
  if not p then return false end
  if p.toggle then
    local m = modules.game_helper
    if not (m and m.toggle) then return false end
    pcall(m.toggle)
    win = helperWindow()
  end
  if not win then return false end
  if win.raise then win:raise() end
  if win.focus then win:focus() end
  if not (ChaosAutoSetupUI and ChaosAutoSetupUI.addButton and ChaosAutoSetupUI.addButton()) then return false end
  local b = win:recursiveGetChildById(ChaosAutoSetupUI.BUTTON_ID)
  if not b then return false end
  stop()
  local hint = g_ui.createWidget('Label', b:getParent())
  hint:setId(O.HINT_ID)
  hint:setText(p.hint)
  hint:setColor(O.GOLD)
  hint:setTextAutoResize(true)
  hint:addAnchor(AnchorBottom, ChaosAutoSetupUI.BUTTON_ID, AnchorTop)
  hint:addAnchor(AnchorLeft, ChaosAutoSetupUI.BUTTON_ID, AnchorLeft)
  hint:setMarginBottom(2)
  b.chaosOnboardColor = b:getColor()
  local own = b.chaosOnboardColor
  local frames, i = O.blinkFrames(O.blinkMs, O.stepMs), 0
  local function step()
    i = i + 1
    if i > #frames or b:isDestroyed() then blinkEvent = nil return end
    b:setColor(frames[i] and O.GOLD or own)
    blinkEvent = scheduleEvent(step, O.stepMs)
  end
  step()
  local click = b.onClick
  b.onClick = function(...)
    stop()
    b.onClick = click
    if click then return click(...) end
  end
  return true
end

local function onGameEnd() stop() end

function O.init()
  connect(g_game, { onGameEnd = onGameEnd })
end

function O.terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  stop()
end
