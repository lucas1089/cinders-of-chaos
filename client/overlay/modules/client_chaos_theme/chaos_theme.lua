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

-- Widget helpers some of our modules were written against; this engine does not ship them.
local function installWidgetHelpers()
  -- "[color=#rrggbb]text[/color]" markup -> the engine's coloured text {text, colour, text, colour, ...}
  if not UIWidget.parseColoredText then
    UIWidget.parseColoredText = function(self, text, defaultColor)
      defaultColor = defaultColor or '#ffffff'
      local parts, pos = {}, 1
      text = tostring(text or '')
      while true do
        local s, e, color, inner = text:find('%[color=(#?%x+)%](.-)%[/color%]', pos)
        if not s then break end
        if s > pos then
          parts[#parts + 1] = text:sub(pos, s - 1)
          parts[#parts + 1] = defaultColor
        end
        parts[#parts + 1] = inner
        parts[#parts + 1] = color
        pos = e + 1
      end
      if pos <= #text then
        parts[#parts + 1] = text:sub(pos)
        parts[#parts + 1] = defaultColor
      end
      if self.setColoredText then
        self:setColoredText(parts)
      else
        self:setText((text:gsub('%[/?color[^%]]*%]', '')))
      end
    end
  end

  -- rich tooltip (title + list of lines) -> plain multi-line tooltip
  if not UIWidget.setExtendedTooltip then
    UIWidget.setExtendedTooltip = function(self, title, texts, style)
      self.extendedTooltip = { title = title, texts = texts, style = style }
      local lines = { tostring(title or '') }
      if type(texts) == 'table' then
        for _, line in ipairs(texts) do
          lines[#lines + 1] = type(line) == 'table' and tostring(line.text or line[1] or '') or tostring(line)
        end
      elseif texts then
        lines[#lines + 1] = tostring(texts)
      end
      self:setTooltip(table.concat(lines, '\n'))
    end
    UIWidget.removeExtendedTooltip = function(self)
      self.extendedTooltip = nil
      self:removeTooltip()
    end
    UIWidget.getExtendedTooltip = function(self)
      return self.extendedTooltip
    end
  end
  -- the rich tooltip controller of the same family; the plain tooltip above needs no control
  if not rawget(_G, 'g_extendedtooltip') then
    local noop = function() end
    rawset(_G, 'g_extendedtooltip', { init = noop, terminate = noop, show = noop, hide = noop })
  end
end

function init()
  g_ui.importStyle('styles')
  g_ui.importStyle('compat')
  installWidgetHelpers()
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
