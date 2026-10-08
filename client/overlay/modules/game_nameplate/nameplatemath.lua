-- Pure helpers of the name plates (no client API; tested by nameplatemath_test.lua).
-- Wire format (server/data/scripts/chaos/nameplate_core.lua): one plate per line "cid|title|color|guild|frame".
NameplateMath = {}

NameplateMath.FRAMES = { default = true, gold = true, crimson = true, violet = true, frost = true }
NameplateMath.NAME_COLOR = '#e8c372'      -- the name on its plate: gold
NameplateMath.GUILD_COLOR = '#d9a441'     -- {Guild}: deep gold
NameplateMath.WAR_GUILD_COLOR = '#e8643c' -- guild of a war enemy (red emblem)
NameplateMath.TITLE_COLOR = '#d6c9ae'     -- a title without a colour
NameplateMath.STALE_SECONDS = 60          -- a plate older than this is asked again when its player reappears
NameplateMath.BATCH = 30                  -- ids per query
NameplateMath.RETRY_SECONDS = 3           -- an unanswered query is repeated after this
NameplateMath.MAX_TRIES = 4               -- and given up after this many tries

local function split(line)
  local out, start = {}, 1
  while true do
    local i = line:find('|', start, true)
    if not i then
      out[#out + 1] = line:sub(start)
      return out
    end
    out[#out + 1] = line:sub(start, i - 1)
    start = i + 1
  end
end

-- buffer -> list of { cid, title, color, guild, frame } (malformed lines skipped)
function NameplateMath.parse(buffer)
  local list = {}
  if type(buffer) ~= 'string' then return list end
  for line in buffer:gmatch('[^\n]+') do
    local f = split(line)
    local cid = tonumber(f[1])
    if cid and cid > 0 and #f >= 5 then
      local color = f[3] or ''
      list[#list + 1] = {
        cid = cid,
        title = f[2] ~= '' and f[2] or nil,
        color = color:match('^%x%x%x%x%x%x$') and ('#' .. color) or NameplateMath.TITLE_COLOR,
        guild = f[4] ~= '' and f[4] or nil,
        frame = NameplateMath.FRAMES[f[5]] and f[5] or 'default'
      }
    end
  end
  return list
end

function NameplateMath.guildText(guild)
  if not guild or guild == '' then return '' end
  return '{' .. guild .. '}'
end

-- emblem 2 = red (war enemy, Otc.EmblemRed)
function NameplateMath.guildColor(emblem)
  return emblem == 2 and NameplateMath.WAR_GUILD_COLOR or NameplateMath.GUILD_COLOR
end

function NameplateMath.framePath(frame, dir)
  return (dir or '/modules/game_nameplate/images/') .. 'plate_' .. (NameplateMath.FRAMES[frame] and frame or 'default')
end

-- text for clients without the name plate patch: title and guild as one block above the name
function NameplateMath.fallbackText(rec)
  local lines = {}
  if rec and rec.title then lines[#lines + 1] = rec.title end
  if rec and rec.guild then lines[#lines + 1] = NameplateMath.guildText(rec.guild) end
  return table.concat(lines, '\n')
end

-- does this creature id need a query? entry = cached plate { at = seconds } or nil
function NameplateMath.needsQuery(entry, now, pending)
  if pending then return false end
  if not entry then return true end
  return entry.stale and (now - (entry.at or 0)) >= NameplateMath.STALE_SECONDS or false
end

-- queue (set of ids) -> list of "q|id,id,..." messages of at most BATCH ids, sorted
function NameplateMath.queries(queue)
  local ids = {}
  for id in pairs(queue or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  local out = {}
  for i = 1, #ids, NameplateMath.BATCH do
    local part = {}
    for j = i, math.min(#ids, i + NameplateMath.BATCH - 1) do part[#part + 1] = tostring(ids[j]) end
    out[#out + 1] = 'q|' .. table.concat(part, ',')
  end
  return out
end

-- pending = { [cid] = { at, tries } }: ids to ask again (unanswered for RETRY_SECONDS, fewer than MAX_TRIES tries,
-- still on screen per visible(cid)); ids given up or gone are removed from pending. Sorted.
function NameplateMath.retries(pending, now, visible)
  local out = {}
  for id, p in pairs(pending) do
    if p.tries >= NameplateMath.MAX_TRIES or (visible and not visible(id)) then
      pending[id] = nil
    elseif now - p.at >= NameplateMath.RETRY_SECONDS then
      out[#out + 1] = id
    end
  end
  table.sort(out)
  return out
end
