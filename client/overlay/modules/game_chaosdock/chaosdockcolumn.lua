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
-- otui = the file the window is in (the test finds every id there); a window of a base module (the Quest Log of
-- mods/game_questlog) has none in this repository.
ChaosDockColumn = {}
local C = ChaosDockColumn

C.EDGES = { 'top', 'bottom', 'left', 'right' }
C.PROPS = { 'width', 'height', 'marginTop', 'marginLeft', 'marginRight', 'marginBottom', 'visible' }

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
    { id = 'missionsPanel', col = { top = 'questLines.bottom', left = 'parent.left', marginTop = 6, height = 400 },
      home = { top = 'parent.top', left = false } },
    { id = 'missionTitle', col = { right = 'parent.right' }, home = { right = false } },
    { id = 'missionContent', col = { right = 'parent.right', height = 200 }, home = { right = false } },
  } },
  -- the chapters over the steps of the chapter; the two buttons share the width (the intro and the step rows grow to their
  -- wrapped lines by game_goals mainquest.lua itself)
  ['Main Quest'] = { otui = 'game_goals/mainquest.otui', height = 720, rules = {
    { id = 'chapterFrame', col = { right = 'parent.right', bottom = false, height = 150 },
      home = { right = false, bottom = 'closeButton.top' } },
    { id = 'stepFrame', col = { top = 'chapterFrame.bottom', left = 'parent.left', marginLeft = 0 },
      home = { top = 'introLabel.bottom', left = 'chapterFrame.right' } },
    { id = 'skipChapterButton', col = { width = 88 } },
    { id = 'goButton', col = { width = 56, marginLeft = 4 } },
  } },
  -- the dock shows the Character Info page only: the list of the other Info pages hides, the page takes the width
  ['Character Info'] = { otui = 'game_chaosinfo/chaosinfo.otui', rules = {
    { id = 'pageList', col = { visible = false } },
    { id = 'pageTitle', col = { left = 'parent.left', marginLeft = 0 }, home = { left = 'pageList.right' } },
  } },
  -- the search and the spell list over the details; in the details the numbers over the area of effect
  ['Spellbook'] = { otui = 'game_spellbook/spellbook.otui', height = 860, rules = {
    { id = 'searchEdit', col = { right = 'parent.right' }, home = { right = false } },
    { id = 'filterCombo', col = { width = 72 } },
    { id = 'listFrame', col = { right = 'parent.right', bottom = false, height = 200 },
      home = { right = false, bottom = 'closeButton.top' } },
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
    { id = 'runesTitle', col = { right = 'parent.right' }, home = { right = false } },
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
      elseif known[k] == 'edge' then
        if v ~= false and not C.target(v) then out[#out + 1] = name .. ': bad target ' .. tostring(v) end
        if (rule.home or {})[k] == nil then out[#out + 1] = name .. ': ' .. k .. ' not put back' end
      end
    end
    for k, v in pairs(rule.home or {}) do
      if known[k] ~= 'edge' then out[#out + 1] = name .. ': home sets ' .. tostring(k) .. ' (only anchors)'
      elseif v ~= false and not C.target(v) then out[#out + 1] = name .. ': bad home target ' .. tostring(v) end
    end
  end
  return out
end

return C
