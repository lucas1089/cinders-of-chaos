-- Chaos theme: imports the shared Chaos* styles as early as possible so every
-- other module (client_chaos_topbar, game_*, ...) can use them in its .otui.
--
-- OTUI has no variables, so the palette is written once in styles.otui (header
-- comment) and mirrored here for Lua code that needs the same colours.

ChaosTheme = {
  palette = {
    bg          = '#0d0b0e',
    iron        = '#3a3339',
    ironLight   = '#7d7176',
    text        = '#d6c9ae',
    textDim     = '#8c8070',
    textDisabled= '#6b6258',
    gold        = '#e8b84a',
    goldBright  = '#f6cf72',
    blood       = '#b8160f',
    bloodBright = '#e03a1e',
    bloodDark   = '#5a0a0a',
    health      = '#8a1010',
    mana        = '#1f3f8f',
  },
  imagePath = '/images/chaos/',
}

function init()
  g_ui.importStyle('styles')
  g_ui.importStyle('compat')
end

function terminate()
  ChaosTheme = nil
end

-- Convenience: apply the chaos look to an existing widget tree at runtime.
-- Only changes image/colour properties; never touches layout.
function ChaosTheme.skinWindow(window)
  if not window then return end
  window:setImageSource(ChaosTheme.imagePath .. 'window')
  window:setImageBorder(18)
  window:setImageBorderTop(34)
  window:setColor(ChaosTheme.palette.gold)
end
