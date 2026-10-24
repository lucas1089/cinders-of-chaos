-- luajit treetext_test.lua && lua5.3 treetext_test.lua (CI runs every client module test from the repo root)
-- TreeText.lines on the real keystone texts of treedata/nodes.lua: with no translation the lines are the data's own; with the
-- pt-BR table every description paragraph of the data has an entry (client_chaos_locale/pt_br.lua) and wraps within the
-- width of the English lines.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'treetext.lua')
dofile(dir .. 'treedata/nodes.lua')
local fails, count = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(cond, what) eq(cond and true or false, true, what) end

local T = TreeText
eq(T.join({'a b', 'c'}), 'a b c', 'join')
eq(table.concat(T.wrap('one two three four', 9), '|'), 'one two|three|four', 'wrap')
eq(table.concat(T.wrap('averyveryverylongword x', 5), '|'), 'averyveryverylongword|x', 'long word keeps its line')
local same = {'only', 'english'}
eq(T.lines(same), same, 'no translation: the same table')
eq(#T.lines({}), 0, 'empty')

-- the description paragraphs of the tree data (every `stats` list of a string table, at any depth)
local paragraphs, n = {}, 0
local seen = {}
local function collect(tbl)
  if seen[tbl] then return end
  seen[tbl] = true
  for k, v in pairs(tbl) do
    if type(v) == 'table' then
      if k == 'stats' and type(v[1]) == 'string' then
        n = n + 1
        paragraphs[T.join(v)] = v
      else
        collect(v)
      end
    end
  end
end
collect(getTreeNodes())
ok(n > 60, 'the data has description paragraphs: ' .. n)

local pt = dofile(dir .. '../client_chaos_locale/pt_br.lua')
local missing = 0
for text, lines in pairs(paragraphs) do
  if not pt[text] then
    missing = missing + 1
    print('no pt-BR: ' .. text)
  else
    local width = 0
    for _, l in ipairs(lines) do width = math.max(width, #l) end
    _G.tr = function(s) return pt[s] or s end
    local shown = T.lines(lines)
    _G.tr = nil
    ok(#shown >= 1, 'translated lines')
    for _, l in ipairs(shown) do
      ok(#l <= width or not l:find(' '), 'line within the English width: ' .. l)
    end
    eq(T.join(shown), pt[text], 'translation kept whole: ' .. text:sub(1, 30))
  end
end
eq(missing, 0, 'every description paragraph has a pt-BR entry')

if fails > 0 then print(fails .. ' of ' .. count .. ' FAILED'); os.exit(1) end
print('treetext_test: ' .. count .. ' checks passed')
