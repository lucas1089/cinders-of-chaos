-- Auto build window maths (no client API, tested by autobuildview_test.lua). The server's lists and previews
-- (server/data/scripts/chaos/passive_builds.lua) come already in the player's language; the labels around them go through tr().
--   autobuildList {group = "role" | "focus", builds = [{id, name, text, summary, points, fit}], owned, held, free, cap}
--   autobuildPreview {build, name, owned, held, wanted, add = {nodes, added, skipped, other, masteries, keystones, capText},
--                     reset = {nodes, added, skipped, other, removed, cost, free, masteries, keystones, capText}}
--   capText (O447): the keystone cap's refusal in the player's language when that side would hold too many keystones
local function tr(s, ...) local g = (rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr) if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
AutoBuildView = {}
local V = AutoBuildView

V.TEXT, V.DIM, V.GOOD, V.WARN = '#d8cfc0', '#8c8070', '#80c070', '#c0b080'

local function lnum(text) local c = rawget(_G, 'ChaosLocale') if c and c.localize then return c.localize(text) end return text end
function V.gold(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return lnum((out:gsub('^,', '')))
end

local function num(v) return math.floor(tonumber(v) or 0) end

-- the text of one dropdown entry: the build name, its points, and how well it fits the class's Primary / Secondary stats
function V.label(b)
  local text = string.format('%s - %s', tostring(b.name or b.id or '?'), tr('%d points', num(b.points)))
  if b.fit == 'primary' then
    text = text .. ' [' .. tr('Primary') .. ']'
  elseif b.fit == 'secondary' then
    text = text .. ' [' .. tr('Secondary') .. ']'
  end
  return text
end

-- the dropdown rows: a heading for every group that has builds, then its builds. groups = {role = list, focus = list}
function V.rows(groups)
  local rows = {}
  for _, g in ipairs({{'role', tr('Recommended')}, {'focus', tr('Focus')}}) do
    local list = groups and groups[g[1]]
    if type(list) == 'table' and #list > 0 then
      rows[#rows + 1] = {heading = true, text = '- ' .. g[2] .. ' -'}
      for _, b in ipairs(list) do
        rows[#rows + 1] = {id = b.id, build = b, text = V.label(b)}
      end
    end
  end
  return rows
end

-- index of the first row that is a build (the heading is not pickable); of the row with this id; nil when none
function V.firstBuild(rows)
  for i, r in ipairs(rows) do
    if not r.heading then return i end
  end
end
function V.indexOf(rows, id)
  for i, r in ipairs(rows) do
    if r.id == id then return i end
  end
end

local function priceText(reset)
  local cost = num(reset.cost)
  if cost > 0 then
    return tr('%s gold coins', V.gold(cost))
  end
  if reset.free and num(reset.free) > 0 then
    return tr('free (a free reset is used)')
  end
  return tr('free')
end

-- the text under the dropdown: what the build is, how many points it needs, and what Apply / Reset and apply would do
-- once the preview arrived. state = {owned, held, free, cap} of the list. note = {text, color} (an answer of the server:
-- an error, the applied message) is the last line, in its colour; it stands in for "Asking..." when there is no
-- preview. Returns text, colour.
function V.detail(b, state, preview, note)
  if not b then
    return tr('Pick a build. The tree shows what it would take.'), V.DIM
  end
  local lines = {}
  if b.text and b.text ~= '' then lines[#lines + 1] = b.text end
  if b.summary and b.summary ~= '' then lines[#lines + 1] = b.summary end
  local owned = num(state and state.owned)
  lines[#lines + 1] = tr('The build uses %d points. You own %d and %d are free.', num(b.points), owned, num(state and state.free))
  if not preview or preview.build ~= b.id then
    if note and note.text then
      lines[#lines + 1] = note.text
      return table.concat(lines, '\n'), note.color or V.TEXT
    end
    lines[#lines + 1] = tr('Asking the server for a preview...')
    return table.concat(lines, '\n'), V.TEXT
  end
  local add, reset = preview.add or {}, preview.reset or {}
  lines[#lines + 1] = ''
  if add.capText then
    -- the keystone cap (O447): the build on top of the keystones held would hold too many; the server's own line
    lines[#lines + 1] = tr('Apply: not possible.') .. ' ' .. tostring(add.capText)
  else
    lines[#lines + 1] = tr('Apply: adds %d nodes, takes nothing back, free.', num(add.added))
    if num(add.skipped) > 0 then
      lines[#lines + 1] = tr('%d more nodes of the build need points you do not have yet.', num(add.skipped))
    end
    if num(add.other) > 0 then
      lines[#lines + 1] = tr('%d nodes your class cannot hold are left out.', num(add.other))
    end
  end
  if num(reset.removed) > 0 then
    lines[#lines + 1] = tr('Reset and apply: takes back %d nodes and builds this one (%d nodes). Price: %s.', num(reset.removed),
      #(reset.nodes or {}), priceText(reset))
  else
    lines[#lines + 1] = tr('Reset and apply: your tree already fits this build, nothing is taken back.')
  end
  if note and note.text then
    lines[#lines + 1] = ''
    lines[#lines + 1] = note.text
    return table.concat(lines, '\n'), note.color or V.TEXT
  end
  return table.concat(lines, '\n'), V.TEXT
end

-- ------------------------------------------------------------------------------------------------ the preview request
-- autobuild.lua asks for the preview of the picked build and waits for autobuildPreview or autobuildError. Every wait
-- has an end: no answer within PREVIEW_TIMEOUT_MS asks again, MAX_TRIES asks in all, then an error is shown.
V.PREVIEW_TIMEOUT_MS = 4000
V.RETRY_DELAY_MS = 700 -- after "too fast" (autobuildError {retry}): a little over the server's preview limit
V.MAX_TRIES = 3

-- O560: quick picks in the dropdown. The pick shows at once; the request goes out at most every MIN_GAP_MS (the server's
-- previewRateMs) and always asks for the LAST pick; every request carries a number the server sends back, an answer to an
-- older number is dropped, so a slow answer never overwrites a newer pick.
V.MIN_GAP_MS = 150
V.RETRY_MARGIN_MS = 30

-- ms to wait before the next request may go out (0 = now); lastSentAt nil = none sent yet
function V.gateDelay(lastSentAt, now)
  if lastSentAt == nil or now < lastSentAt then
    return lastSentAt == nil and 0 or V.MIN_GAP_MS
  end
  local d = lastSentAt + V.MIN_GAP_MS - now
  return d > 0 and d or 0
end

-- is this answer to an older request than the latest one sent? (an answer without a number is judged by its build)
function V.isStale(latestSeq, data)
  local n = type(data) == 'table' and tonumber(data.seq) or nil
  return n ~= nil and latestSeq ~= nil and n < latestSeq
end

-- ms until a refused request (autobuildError {retry}) is asked again: the server says how long (wait), else the old delay
function V.retryDelay(data)
  local w = type(data) == 'table' and tonumber(data.wait) or nil
  if w and w >= 0 and w <= 5000 then
    return math.floor(w) + V.RETRY_MARGIN_MS
  end
  return V.RETRY_DELAY_MS
end

-- ask for the preview of `selected` now? Not when it is shown already, asked already, or failed (until a new pick)
function V.needsPreview(selected, preview, pending, failed)
  if selected == nil or failed == selected then
    return false
  end
  if preview ~= nil and preview.build == selected then
    return false
  end
  return not (pending ~= nil and pending.build == selected)
end

-- the pending request after asking for `build`: a new pick starts at try 1, asking again the same build counts on
function V.ask(pending, build)
  local tries = (pending ~= nil and pending.build == build) and pending.tries + 1 or 1
  return {build = build, tries = tries}
end

-- what to do when the asked preview did not come in time: 'retry' or 'fail'
function V.onTimeout(pending)
  return (pending ~= nil and pending.tries < V.MAX_TRIES) and 'retry' or 'fail'
end

-- how an autobuildError answers the pending preview: 'ignore' (another build's, or nothing asked), 'retry' (too fast,
-- tries left) or 'fail'. data.build is the asked id (servers before 2026-10-20 do not send it: then it answers the pending one)
function V.onError(pending, data)
  if pending == nil then
    return 'ignore'
  end
  local build = type(data) == 'table' and data.build or nil
  if build ~= nil and build ~= pending.build then
    return 'ignore'
  end
  if type(data) == 'table' and data.retry and pending.tries < V.MAX_TRIES then
    return 'retry'
  end
  return 'fail'
end

-- Apply does something when the build adds at least one node; Reset and apply when it adds or takes back something
function V.canApply(preview)
  return preview ~= nil and num(preview.add and preview.add.added) > 0 and not (preview.add and preview.add.capText)
end
function V.canReset(preview)
  return preview ~= nil and (num(preview.reset and preview.reset.added) > 0 or num(preview.reset and preview.reset.removed) > 0)
end

-- the question before Reset and apply: the price the preview showed is the one sent back (the server refuses a higher one)
function V.confirmText(preview)
  local reset = preview.reset or {}
  return tr('Reset your tree and apply %s?\nNodes taken back: %d. Price: %s.', tostring(preview.name or preview.build),
    num(reset.removed), priceText(reset))
end

-- ------------------------------------------------------------------------------------------------ save to a loadout slot (O448)
-- "Save to a loadout slot": the picked build's tree goes into a loadout slot the player picks. The server decides everything
-- (passive_builds.lua autobuildSlots / autobuildSaveSlot, loadouts.lua saveBuild); this is the text and the list of slots.
--   autobuildSlots {slots = [{slot, name, empty, locked, active}], limit, max, level, minLevel, nextUnlock}
--   autobuildSlotSaved {message, lines, slot, build}
--   autobuildError {message, slot, build, needConfirm, name} answers a save the server refused (a slot answer has a slot)
function V.note()
  return tr('Only the passive tree of the slot is written. Its gear, runes and Paragon stay as they were, and your live tree does not change.')
end

-- the slots the picker offers: not locked, not the active one (it holds the live build). {slot, name, empty, text}
function V.slotRows(choices)
  local rows = {}
  for _, s in ipairs(type(choices) == 'table' and type(choices.slots) == 'table' and choices.slots or {}) do
    if not s.locked and not s.active then
      local what = s.empty and tr('(empty)') or tostring(s.name or '?')
      rows[#rows + 1] = {slot = num(s.slot), name = s.name, empty = s.empty and true or false,
        text = tr('Slot %d - %s', num(s.slot), what)}
    end
  end
  return rows
end

-- the line shown when no slot can be picked
function V.noSlotText(choices)
  local c = type(choices) == 'table' and choices or {}
  if num(c.minLevel) > 0 and num(c.level) < num(c.minLevel) then
    return tr('Loadouts open at level %d.', num(c.minLevel))
  end
  if c.nextUnlock then
    return tr('No loadout slot is free to pick: the active one holds your live build and the others are locked. One more opens at level %d.', num(c.nextUnlock))
  end
  return tr('No loadout slot is free to pick: the active one holds your live build and the others are locked.')
end

-- the picker's text: what is written and what is not
function V.pickText(build)
  return tr('Save %s into one of your loadout slots.', tostring(build and (build.name or build.id) or '?')) .. '\n' .. V.note()
end

-- the question before a held slot is replaced
function V.replaceText(slot, name, buildName)
  return tr('Slot %d holds %s.\nReplace its passive tree with %s?', num(slot), tostring(name or '?'), tostring(buildName or '?')) .. '\n' ..
    V.note()
end

-- the server's answer after a save: its message and its extra lines
function V.savedText(data)
  local lines = {}
  if type(data) == 'table' then
    if data.message and data.message ~= '' then lines[#lines + 1] = data.message end
    for _, l in ipairs(type(data.lines) == 'table' and data.lines or {}) do
      if l and l ~= '' then lines[#lines + 1] = l end
    end
  end
  if #lines == 0 then lines[1] = tr('Build saved.') end
  return table.concat(lines, '\n')
end

-- is this autobuildError the answer to a save into a slot? (a preview or apply error never has a slot)
function V.isSlotAnswer(data)
  return type(data) == 'table' and data.slot ~= nil
end

return V
