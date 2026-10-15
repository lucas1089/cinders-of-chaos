-- Credits window: every third-party source of the game (docs/CREDITS.md, generated into credits_data.lua by
-- client/tools/gen_credits.py). Opened by the login screen's CREDITS button (client_chaos_login) and by
-- System > Credits in the Chaos menu bar (client_chaos_topbar), also on the login screen. What it draws: creditsview.lua.

local window
local STYLE = {
  intro = 'CreditsIntro', section = 'CreditsSection', note = 'CreditsNote', name = 'CreditsName',
  line = 'CreditsLine', credit = 'CreditsCredit'
}

local function render()
  local area = window.creditsArea
  area:destroyChildren()
  for _, b in ipairs(CreditsView.blocks(ChaosCreditsData, tr)) do
    local label = g_ui.createWidget(STYLE[b.style] or 'CreditsLine', area)
    label:setText(b.text)
    label:setColor(b.color)
  end
  if window.creditsScroll then window.creditsScroll:setValue(0) end
end

function show()
  if not window then return end
  render() -- each time: the headings follow the language chosen since
  window:show()
  window:raise()
  window:focus()
end

function hide()
  if window then window:hide() end
end

function toggle()
  if window and window:isVisible() then
    hide()
  else
    show()
  end
end

function init()
  window = g_ui.displayUI('credits')
  window:hide()
end

function terminate()
  if window then
    window:destroy()
    window = nil
  end
end
