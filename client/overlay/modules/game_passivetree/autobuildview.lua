-- Auto build window maths (no client API, tested by autobuildview_test.lua). The server's lists and previews
-- (server/data/scripts/chaos/passive_builds.lua) come already in the player's language; the labels around them go through tr().
--   autobuildList {group = "role" | "focus", builds = [{id, name, text, summary, points, fit}], owned, held, free, cap}
--   autobuildPreview {build, name, owned, held, wanted, add = {nodes, added, skipped, other, masteries},
--                     reset = {nodes, added, skipped, other, removed, cost, free, masteries}}
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
AutoBuildView = {}
local V = AutoBuildView

V.TEXT, V.DIM, V.GOOD, V.WARN = '#d8cfc0', '#8c8070', '#80c070', '#c0b080'

function V.gold(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''))
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
-- once the preview arrived. state = {owned, held, free, cap} of the list. Returns text, colour.
function V.detail(b, state, preview)
  if not b then
    return tr('Pick a build. The tree shows what it would take.'), V.DIM
  end
  local lines = {}
  if b.text and b.text ~= '' then lines[#lines + 1] = b.text end
  if b.summary and b.summary ~= '' then lines[#lines + 1] = b.summary end
  local owned = num(state and state.owned)
  lines[#lines + 1] = tr('The build uses %d points. You own %d and %d are free.', num(b.points), owned, num(state and state.free))
  if not preview or preview.build ~= b.id then
    lines[#lines + 1] = tr('Asking the server for a preview...')
    return table.concat(lines, '\n'), V.TEXT
  end
  local add, reset = preview.add or {}, preview.reset or {}
  lines[#lines + 1] = ''
  lines[#lines + 1] = tr('Apply: adds %d nodes, takes nothing back, free.', num(add.added))
  if num(add.skipped) > 0 then
    lines[#lines + 1] = tr('%d more nodes of the build need points you do not have yet.', num(add.skipped))
  end
  if num(add.other) > 0 then
    lines[#lines + 1] = tr('%d nodes your class cannot hold are left out.', num(add.other))
  end
  if num(reset.removed) > 0 then
    lines[#lines + 1] = tr('Reset and apply: takes back %d nodes and builds this one (%d nodes). Price: %s.', num(reset.removed),
      #(reset.nodes or {}), priceText(reset))
  else
    lines[#lines + 1] = tr('Reset and apply: your tree already fits this build, nothing is taken back.')
  end
  return table.concat(lines, '\n'), V.TEXT
end

-- Apply does something when the build adds at least one node; Reset and apply when it adds or takes back something
function V.canApply(preview)
  return preview ~= nil and num(preview.add and preview.add.added) > 0
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

return V
