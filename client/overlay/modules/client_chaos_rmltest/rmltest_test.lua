-- Self test of rmltest.lua with a fake g_rml (no client needed). Run from the repository root (CI runs it with luajit
-- and lua5.3):  luajit client/overlay/modules/client_chaos_rmltest/rmltest_test.lua
local here = (arg and arg[0] or ''):match('^(.*[/\\])') or './'

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format('FAIL %s: got %q, want %q', what, tostring(got), tostring(want)))
  end
end

-- 1. no g_rml: nothing happens, nothing errors
function tr(s) return s end
g_rml = nil
dofile(here .. 'rmltest.lua')
init()
eq(ChaosRmlTest.available(), false, 'no g_rml: not available')
eq(ChaosRmlTest.open(), false, 'no g_rml: open is false')
ChaosRmlTest.close()
terminate()

-- 2. a fake g_rml records the calls
local calls, texts, rml, callback = {}, {}, {}, nil
local function escape(s) return (s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')) end
g_rml = {
  init = function() return true end,
  escape = escape,
  loadFont = function(p) calls[#calls + 1] = 'font ' .. p return true end,
  loadDocument = function(p) calls[#calls + 1] = 'doc ' .. p return 7 end,
  setEventCallback = function(f) callback = f end,
  setText = function(d, id, t) texts[id] = t return true end,
  setInnerRml = function(d, id, r) rml[id] = r return true end,
  show = function(d) calls[#calls + 1] = 'show ' .. d return true end,
  close = function(d) calls[#calls + 1] = 'close ' .. d return true end,
  isVisible = function() return true end,
}
dofile(here .. 'rmltest.lua')
eq(ChaosRmlTest.available(), true, 'fake g_rml: available')
eq(ChaosRmlTest.open(), true, 'open')
eq(calls[#calls], 'show 7', 'shown')
eq(calls[3], 'doc /modules/client_chaos_rmltest/rmltest.rml', 'document path')
eq(texts.title, 'RmlUi test window', 'title through tr')
eq(select(2, rml.list:gsub('class="row', '')), 30, 'thirty rows')
eq(texts.subtitle, '30 rows, refreshed 0 times', 'subtitle')

callback(7, 'refresh', 'click')
eq(texts.subtitle, '30 rows, refreshed 1 times', 'refresh button')
callback(8, 'refresh', 'click')
eq(texts.subtitle, '30 rows, refreshed 1 times', 'other document ignored')
callback(7, 'done', 'click')
eq(calls[#calls], 'close 7', 'done closes')

-- 3. row text is escaped
local out = ChaosRmlTest.rowsRml(1, escape, 'a<%d>', function() return '&' end)
eq(out, '<div class="row"><span class="name">a&lt;1&gt;</span><span class="value">&amp;</span></div>', 'row escaped')

print(string.format('rmltest: %d checks, %d failures', checks, failures))
os.exit(failures == 0 and 0 or 1)
