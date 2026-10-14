-- Season join dialog and modes: pure logic (no client API), used by season.lua and tested by seasonjoin_test.lua.
-- The server's "confirm" message carries modes = [{key, name, short, ssf, hc, warning}] (season_modes.lua); an older server
-- sends none and the dialog offers Standard only. A Hardcore choice needs the "I understand" box ticked.
-- The state's mine = {mode, modeName, ssf, hc, fallen = {level, cause}, heartbeat} feeds modeLine and the heartbeat.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

SeasonJoin = {}

SeasonJoin.DEFAULT = 'standard'

-- the choices of a confirm message, cleaned: always at least Standard, keys unique, in the server's order
function SeasonJoin.choices(data)
  local out, seen = {}, {}
  local list = type(data) == 'table' and type(data.modes) == 'table' and data.modes or {}
  for _, m in ipairs(list) do
    if type(m) == 'table' and type(m.key) == 'string' and m.key ~= '' and not seen[m.key] then
      seen[m.key] = true
      out[#out + 1] = { key = m.key, name = tostring(m.name or m.key), short = tostring(m.short or m.name or m.key),
                        warning = tostring(m.warning or ''),
                        ssf = m.ssf == true, hc = m.hc == true }
    end
  end
  if not seen[SeasonJoin.DEFAULT] then
    table.insert(out, 1, { key = SeasonJoin.DEFAULT, name = 'Standard', short = 'Standard', warning = '', ssf = false,
                           hc = false })
  end
  return out
end

function SeasonJoin.find(choices, key)
  for _, c in ipairs(choices or {}) do
    if c.key == key then return c end
  end
  return nil
end

-- a Hardcore choice asks the player to tick "I understand"
function SeasonJoin.needsAck(choice)
  return choice ~= nil and choice.hc == true
end

function SeasonJoin.canJoin(choice, acked)
  if not choice then return false end
  return not SeasonJoin.needsAck(choice) or acked == true
end

-- the join message's data, or nil while the dialog may not join yet
function SeasonJoin.payload(choice, acked)
  if not SeasonJoin.canJoin(choice, acked) then return nil end
  return { confirm = true, mode = choice.key }
end

function SeasonJoin.joinLabel(choice)
  if choice and choice.hc then return tr('Join (one life)') end
  return 'Join'
end

-- the dialog text under the mode buttons: the mode's warning (Standard: the plain terms are enough)
function SeasonJoin.warningText(choice)
  if not choice then return '' end
  if choice.warning ~= '' then return choice.warning end
  return choice.name
end

-- the line of the Season window about the character's mode, or nil (no mode played, never fallen)
function SeasonJoin.modeLine(mine)
  if type(mine) ~= 'table' then return nil end
  if type(mine.fallen) == 'table' then
    return tr('Fallen in Hardcore at level %d (%s).', tonumber(mine.fallen.level) or 0,
      tostring(mine.fallen.cause or 'died'))
  end
  if mine.mode and mine.mode ~= SeasonJoin.DEFAULT then
    return 'Mode: ' .. tostring(mine.modeName or mine.mode) .. '.'
  end
  return nil
end

-- seconds between heartbeats (a Hardcore character), or nil
function SeasonJoin.heartbeat(mine)
  if type(mine) ~= 'table' or mine.hc ~= true then return nil end
  local s = tonumber(mine.heartbeat)
  if not s or s < 1 then return nil end
  return s
end

-- the general box does not wrap: break the text into lines of about `width` characters
function SeasonJoin.wrap(text, width)
  local lines, line = {}, ''
  for word in tostring(text or ''):gmatch('%S+') do
    if line ~= '' and #line + 1 + #word > width then
      lines[#lines + 1] = line
      line = word
    else
      line = line == '' and word or (line .. ' ' .. word)
    end
  end
  if line ~= '' then lines[#lines + 1] = line end
  return table.concat(lines, '\n')
end

return SeasonJoin
