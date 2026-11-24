-- The column layouts of the side dock (O755, owner 2026-11-24: "do tamanho de 1 coluna mesmo, como a bp fica hoje"). Pure
-- data and two pure helpers, no engine calls; chaosdock.lua applies them, chaosdock_test.lua checks them in the client loop.
-- A two pane window (a list left, the details right) is too wide for one right panel column. In the dock its panes stack:
-- the list on top at the column's width, the details under it, and the window is as tall as `height` (the dock scrolls
-- it when that is taller than the room under the tabs). Given back, every part has its own anchors and size again.
-- A rule: id = a part of the window (found by id inside it), col = what changes in the column, home = the anchors it has
-- again when given back. An anchor key (top, bottom, left, right) names 'otherId.edge' or false (no anchor on that edge);
-- every anchor col sets is in home too (chaosdock_test.lua). Other keys of col (width, height, marginTop, marginLeft,
-- marginRight, marginBottom, visible) are set in the column; their values of before come back by themselves (chaosdock.lua
-- reads them before it changes them), and so do the width and height of every part a rule names.
-- col.wrap = true (O760): a label whose text runs past the column's edge wraps there and is as tall as its lines; given
-- back it has its own wrap again and the text-auto-resize of its .otui, named by the rule (autoResize, default false).
-- otui = the file the window is in (the test finds every id there); a window of a base module (the Quest Log of
-- mods/game_questlog) has none in this repository.
ChaosDockColumn = {}
local C = ChaosDockColumn

C.EDGES = { 'top', 'bottom', 'left', 'right' }
C.PROPS = { 'width', 'height', 'marginTop', 'marginLeft', 'marginRight', 'marginBottom', 'visible', 'wrap' }

-- the narrowest room a window has in the column: 164 px of content at 1280 x 720, 148 with the dock's scroll bar (O755;
-- 6 px less since the left padding moved off the frame's gold line, owner 2026-11-24).
-- No part of a column window may be wider unless both its sides are anchored there (chaosdock_test.lua, O760).
C.COLUMN = 148

C.LAYOUTS = {
  -- base module (mods/game_questlog/questlog.otui): Quest Lines over the missions, the lists, the sort and the search at
  -- full width; the completed / hidden counts have no room beside their boxes in a column and hide
  ['Quest Log'] = { height = 780, rules = {
    { id = 'questLines', col = { right = 'parent.right', height = 290 }, home = { right = false } },
    { id = 'questContent', col = { right = 'parent.right', height = 160 }, home = { right = false } },
    { id = 'filterQuests', col = { right = 'parent.right' }, home = { right = false } },
    { id = 'searchfilter', col = { right = 'parent.right' }, home = { right = false } },
    { id = 'completQuestsLabel', col = { visible = false } },
    { id = 'completQuestsValue', col = { visible = false } },
    { id = 'hiddenQuestsLabel', col = { visible = false } },
    { id = 'hiddenQuestsValue', col = { visible = false } },
    -- the quest name (or "No quest line selected") wraps over two lines at most, the missions start under it (O760)
    { id = 'questTitle', col = { width = 136, wrap = true }, autoResize = true },
    { id = 'missionContentPanel', col = { marginTop = 36 } },
    { id = 'missionsPanel', col = { top = 'questLines.bottom', left = 'parent.left', marginTop = 6, height = 400 },
      home = { top = 'parent.top', left = false } },
    { id = 'missionTitle', col = { right = 'parent.right' }, home = { right = false } },
    { id = 'missionContent', col = { right = 'parent.right', height = 186 }, home = { right = false } },
    -- "Show in quest tracker" wraps to two lines over the bottom (it was cut at the column's edge, O760)
    { id = 'showInTracker', col = { width = 136, wrap = true }, autoResize = true },
  } },
  -- the chapters over the steps of the chapter; the two buttons share the width (the intro and the step rows grow to their
  -- wrapped lines by game_goals mainquest.lua itself)
  ['Main Quest'] = { otui = 'game_goals/mainquest.otui', height = 720, rules = {
    { id = 'chapterFrame', col = { right = 'parent.right', bottom = false, height = 150 },
      home = { right = false, bottom = 'closeButton.top' } },
    { id = 'stepFrame', col = { top = 'chapterFrame.bottom', left = 'parent.left', marginLeft = 0 },
      home = { top = 'introLabel.bottom', left = 'chapterFrame.right' } },
    { id = 'skipChapterButton', col = { width = 94 } },
    { id = 'goButton', col = { width = 54, marginLeft = 4 } },
  } },
  -- the dock shows the Character Info page only: the list of the other Info pages hides, the page takes the width
  ['Character Info'] = { otui = 'game_chaosinfo/chaosinfo.otui', rules = {
    { id = 'pageList', col = { visible = false } },
    { id = 'pageTitle', col = { left = 'parent.left', marginLeft = 0 }, home = { left = 'pageList.right' } },
  } },
  -- the search and the spell list over the details; in the details the numbers over the area of effect
  ['Spellbook'] = { otui = 'game_spellbook/spellbook.otui', height = 860, rules = {
    { id = 'searchEdit', col = { right = 'parent.right' }, home = { right = false } },
    -- the area legend (150 wide, centred under the area box) fits the column at 148 (left padding off the gold line)
    { id = 'legend', col = { width = 148 } },
    -- the two filters one over the other: side by side in the column the arrow covered "Learned" and "All types" (O760)
    { id = 'filterCombo', col = { right = 'parent.right' }, home = { right = false } },
    { id = 'kindCombo', col = { top = 'filterCombo.bottom', left = 'parent.left', marginTop = 4, marginLeft = 0 },
      home = { top = 'filterCombo.top', left = 'filterCombo.right' } },
    { id = 'listFrame', col = { top = 'kindCombo.bottom', right = 'parent.right', bottom = false, height = 200 },
      home = { top = 'filterCombo.bottom', right = false, bottom = 'closeButton.top' } },
    { id = 'details', col = { top = 'listFrame.bottom', left = 'parent.left', marginTop = 6, marginLeft = 0 },
      home = { top = 'parent.top', left = 'listFrame.right' } },
    { id = 'stats', col = { right = 'parent.right' }, home = { right = false } },
    { id = 'areaTitle', col = { top = 'stats.bottom', left = 'parent.left', marginLeft = 0 },
      home = { top = 'headerSeparator.bottom', left = 'stats.right' } },
    { id = 'descSeparator', col = { top = 'areaNote.bottom', marginTop = 8 }, home = { top = 'stats.bottom' } },
    -- hidden in the dock (its close is the dock's): no width, so the buttons left of it keep their room
    { id = 'closeButton', col = { width = 0 } },
    { id = 'supportsButton', col = { width = 70 } },
    { id = 'upgradesButton', col = { width = 70 } },
  } },
  -- the spells over the sockets, the runes and the result
  ['Spell Supports'] = { otui = 'game_spellsupports/spellsupports.otui', height = 820, rules = {
    { id = 'listTitle', col = { right = 'parent.right' }, home = { right = false } },
    { id = 'listFrame', col = { right = 'parent.right', bottom = false, height = 180 },
      home = { right = false, bottom = 'closeButton.top' } },
    { id = 'details', col = { top = 'listFrame.bottom', left = 'parent.left', marginTop = 6, marginLeft = 0 },
      home = { top = 'parent.top', left = 'listFrame.right' } },
    -- the runes title and the empty-runes line wrap at the column's edge (O760: both were cut there)
    { id = 'runesTitle', col = { right = 'parent.right', wrap = true }, home = { right = false } },
    { id = 'noRunes', col = { width = 130, wrap = true }, autoResize = true },
    { id = 'closeButton', col = { width = 0 } },
  } },
}

function C.layout(entry)
  return C.LAYOUTS[entry]
end

-- 'otherId.edge' -> otherId, edge; nil for a bad target
function C.target(text)
  if type(text) ~= 'string' then return nil end
  local id, edge = text:match('^([%w_]+)%.(%a+)$')
  if not id then return nil end
  for _, e in ipairs(C.EDGES) do
    if e == edge then return id, edge end
  end
  return nil
end

-- the faults of a layout (an empty list when sound): unknown keys, bad anchor targets, an anchor col sets and home does
-- not put back
function C.faults(layout)
  local out = {}
  local known = {}
  for _, k in ipairs(C.EDGES) do known[k] = 'edge' end
  for _, k in ipairs(C.PROPS) do known[k] = 'prop' end
  for i, rule in ipairs(layout.rules or {}) do
    local name = tostring(rule.id or ('rule ' .. i))
    if type(rule.id) ~= 'string' or rule.id == '' then out[#out + 1] = name .. ': no id' end
    for k, v in pairs(rule.col or {}) do
      if not known[k] then out[#out + 1] = name .. ': unknown key ' .. tostring(k)
      elseif k == 'wrap' and type(v) ~= 'boolean' then out[#out + 1] = name .. ': wrap is true or false'
      elseif known[k] == 'edge' then
        if v ~= false and not C.target(v) then out[#out + 1] = name .. ': bad target ' .. tostring(v) end
        if (rule.home or {})[k] == nil then out[#out + 1] = name .. ': ' .. k .. ' not put back' end
      end
    end
    if rule.autoResize ~= nil and type(rule.autoResize) ~= 'boolean' then
      out[#out + 1] = name .. ': autoResize is true or false'
    end
    if rule.autoResize ~= nil and not (rule.col or {}).wrap then out[#out + 1] = name .. ': autoResize without wrap' end
    for k, v in pairs(rule.home or {}) do
      if known[k] ~= 'edge' then out[#out + 1] = name .. ': home sets ' .. tostring(k) .. ' (only anchors)'
      elseif v ~= false and not C.target(v) then out[#out + 1] = name .. ': bad home target ' .. tostring(v) end
    end
  end
  return out
end

-- ---------------------------------------------------------------- widgets wider than the column (O760)
-- The widgets of an .otui text (styles and the window), each { id, line, width, left, right, fill, depth }: the fixed width
-- of `width:` or `size:` and its horizontal anchors. A state block ($mobile, $hover, ...) is left out (the dock lays a
-- window out for the column only off the phone), so is a script block (`@onSetup: |`).
function C.otuiWidgets(text)
  local out, stack = {}, {}
  local skipBelow = nil
  local n = 0
  for raw in (tostring(text) .. '\n'):gmatch('([^\n]*)\n') do
    n = n + 1
    local indent = #(raw:match('^( *)'))
    local line = raw:gsub('^%s+', ''):gsub('%s+$', '')
    if skipBelow and line ~= '' and indent <= skipBelow then skipBelow = nil end
    if skipBelow or line == '' or line:sub(1, 2) == '//' then
      -- inside a skipped block, empty or a comment
    elseif line:sub(1, 1) == '$' or line:match('^[@!&]?[%w%.%-]+:%s*|$') then
      skipBelow = indent
    elseif line:match('^[%w_]+$') or line:match('^[%w_]+%s*<%s*[%w_]+$') then
      while #stack > 0 and stack[#stack].indent >= indent do table.remove(stack) end
      local w = { line = n, indent = indent, depth = #stack, style = line:find('<', 1, true) ~= nil }
      stack[#stack + 1] = w
      out[#out + 1] = w
    else
      while #stack > 0 and stack[#stack].indent >= indent do table.remove(stack) end
      local w = stack[#stack]
      local key, value = line:match('^([%w%.%-]+):%s*(.-)$')
      if w and key then
        if key == 'id' then w.id = value
        elseif key == 'width' then w.width = tonumber(value)
        elseif key == 'size' then w.width = tonumber(value:match('^(%-?%d+)'))
        elseif key == 'anchors.left' then w.left = true
        elseif key == 'anchors.right' then w.right = true
        elseif key == 'anchors.fill' then w.fill = true
        end
      end
    end
  end
  return out
end

-- the widgets of a window's .otui that are wider than the column (limit, default C.COLUMN) in the dock: a fixed width
-- over the limit, not anchored on both sides there (by the .otui or by the layout), not narrowed or hidden by the layout.
-- The window itself (a widget of no style at the top) is the dock's to size. Each: 'id (line N): width W'.
function C.wideParts(text, layout, limit)
  limit = limit or C.COLUMN
  local byId = {}
  for _, rule in ipairs((layout and layout.rules) or {}) do byId[rule.id] = rule.col or {} end
  local out = {}
  for _, w in ipairs(C.otuiWidgets(text)) do
    local window = w.depth == 0 and not w.style
    local col = (w.id and byId[w.id]) or {}
    local left, right = w.left, w.right
    if col.left ~= nil then left = col.left ~= false end
    if col.right ~= nil then right = col.right ~= false end
    local width = col.width or w.width
    if not window and width and width > limit and not (left and right) and not w.fill and col.visible ~= false then
      out[#out + 1] = tostring(w.id or '?') .. ' (line ' .. w.line .. '): width ' .. width
    end
  end
  return out
end

return C
