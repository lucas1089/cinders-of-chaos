-- game_antibot pure logic (no client API): the presence check payload, countdown text and colour, the report form
-- check and the messages. antibot.lua draws; antibot_logic_test.lua runs this under luajit and lua5.3.
-- Server: data/scripts/chaos/antibot.lua, reports.lua (extended opcode 211).

AntibotLogic = AntibotLogic or {}
local L = AntibotLogic

L.COLORS = { text = '#d6c9ae', dim = '#8c8070', gold = '#f6cf72', warn = '#e8b84a', bad = '#e03a1e', good = '#6fd8a8' }

-- the reasons the server sends; this list only fills the dialog until it arrives
L.DEFAULT_REASONS = {
  { k = 'botting', n = 'Botting' },
  { k = 'cheating', n = 'Cheating / exploiting' },
  { k = 'harassment', n = 'Harassment' },
  { k = 'scam', n = 'Scam' },
  { k = 'name', n = 'Offensive name' },
  { k = 'other', n = 'Other' },
}
L.NOTE_MAX = 200

local function str(v, max)
  if type(v) ~= 'string' then return nil end
  if max and #v > max then return nil end
  return v
end

-- check {t, w, o = [{k, c}], s, a, r} -> {token, word, options, seconds, attempt, retries} or nil
function L.parseCheck(d)
  if type(d) ~= 'table' then return nil end
  local token, word = str(d.t, 32), str(d.w, 40)
  if not token or token == '' or not word or word == '' or type(d.o) ~= 'table' then return nil end
  local options = {}
  for i, o in ipairs(d.o) do
    if i > 6 then break end
    local key, clientId = type(o) == 'table' and str(o.k, 16), type(o) == 'table' and tonumber(o.c)
    if not key or not clientId or clientId <= 0 then return nil end
    options[#options + 1] = { key = key, clientId = math.floor(clientId) }
  end
  if #options < 2 then return nil end
  return {
    token = token, word = word, options = options,
    seconds = math.max(0, math.floor(tonumber(d.s) or 0)),
    attempt = math.max(1, math.floor(tonumber(d.a) or 1)),
    retries = math.max(0, math.floor(tonumber(d.r) or 0)),
  }
end

function L.prompt(word)
  return 'Click the picture of: ' .. tostring(word)
end

-- seconds left -> "1:05"
function L.timeText(seconds)
  seconds = math.max(0, math.floor(seconds or 0))
  return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

function L.timeColor(seconds)
  if seconds <= 10 then return L.COLORS.bad end
  if seconds <= 25 then return L.COLORS.warn end
  return L.COLORS.text
end

-- percent of the time left for the bar
function L.timePercent(seconds, total)
  if not total or total <= 0 then return 0 end
  return math.max(0, math.min(100, math.floor(seconds * 100 / total + 0.5)))
end

function L.answer(check, key)
  return { t = check.token, k = key }
end

function L.retryText(retries)
  if retries > 0 then return 'Another picture' end
  return 'No more pictures'
end

-- ---------------------------------------------------------------- reports
function L.parseReasons(list)
  local out = {}
  if type(list) == 'table' then
    for _, r in ipairs(list) do
      if type(r) == 'table' and str(r.k, 16) and str(r.n, 40) then out[#out + 1] = { k = r.k, n = r.n } end
    end
  end
  if #out == 0 then return L.DEFAULT_REASONS end
  return out
end

function L.cleanNote(note, max)
  note = tostring(note or ''):gsub('[%c]', ' '):gsub('[\128-\255]', ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  max = max or L.NOTE_MAX
  if #note > max then note = note:sub(1, max) end
  return note
end

function L.validName(name)
  return type(name) == 'string' and #name >= 2 and #name <= 29 and name:match("^[A-Za-z][A-Za-z '%-]*$") ~= nil
end

-- the same rules as the server (reports_core.lua R.validate); returns the message or nil, error text
function L.reportMessage(name, reason, note, ownName, noteMax)
  name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if not L.validName(name) then return nil, 'Type the name of the character you want to report.' end
  if ownName and name:lower() == tostring(ownName):lower() then return nil, 'You cannot report yourself.' end
  if type(reason) ~= 'string' or reason == '' then return nil, 'Choose a reason.' end
  note = L.cleanNote(note, noteMax)
  if reason == 'other' and #note < 3 then return nil, 'Describe the problem in the note (reason Other).' end
  return { name = name, reason = reason, note = note }
end

function L.noteCounter(note, noteMax)
  return string.format('%d/%d', #tostring(note or ''), noteMax or L.NOTE_MAX)
end

-- right-click menu: players other than yourself
function L.canReport(isPlayer, isLocalPlayer)
  return isPlayer == true and not isLocalPlayer
end

return L
