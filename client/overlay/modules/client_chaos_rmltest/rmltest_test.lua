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

-- 2b. hot reload: terminate() with an open window clears the caches, init() opens it again
local cleared = 0
g_rml.clearCaches = function() cleared = cleared + 1 end
g_keyboard = { bindKeyDown = function() end, unbindKeyDown = function() end }
ChaosRmlTest.open() -- the done button above closed it
local before = #calls
terminate()
eq(cleared, 1, 'terminate clears the caches')
eq(calls[#calls], 'close 7', 'terminate closes the window')
init()
eq(#calls > before + 1 and calls[#calls] == 'show 7', true, 'init opens it again after a reload')
terminate() -- opened again, so it reopens once more
eq(ChaosRmlTest.reopen, true, 'flag set while open')
init()
ChaosRmlTest.close()
terminate()
eq(ChaosRmlTest.reopen, false, 'no flag when the window was closed')

-- 2c. the touch sequence is the Android one: touch press first, left press after the slop, both releases last
local st = ChaosRmlTest.touchSteps(100, 200, -90, 6)
eq(st[1][1] .. st[1][4], 'moveleft', 'starts with a move')
eq(st[2][1] .. st[2][4], 'presstouch', 'touch press second')
local at
for i, s in ipairs(st) do if s[1] == 'press' and s[4] == 'left' then at = i end end
eq(st[at][3], 200, 'left press at the start point')
eq(st[at - 1][1] .. st[at - 1][3], 'move200', 'move back to the start point first')
eq(st[at - 2][3], 194, 'the slop (8 px) was crossed after the second 6 px step')
eq(st[#st - 1][1] .. st[#st - 1][4], 'releasetouch', 'touch release before the left release')
eq(st[#st][1] .. st[#st][4], 'releaseleft', 'left release last')
eq(st[#st][3], 200 - 90, 'ends 90 px up')
local presses = 0
for _, s in ipairs(st) do if s[1] == 'press' and s[4] == 'left' then presses = presses + 1 end end
eq(presses, 1, 'one left press')

-- 2d. the script of the environment variable
local sc = ChaosRmlTest.parseScript('open;wait3000; touch ;bogus;wait40;scale;close')
eq(#sc, 6, 'script steps (unknown words dropped)')
local sc2 = ChaosRmlTest.parseScript('scale2;scale1')
eq(sc2[1][1] .. sc2[1][2] .. sc2[2][2], 'scale21', 'scale<N> steps')
eq(sc[2][1] .. sc[2][2], 'wait3000', 'wait step')
eq(sc[3][1], 'touch', 'touch step')
eq(#ChaosRmlTest.parseScript(nil), 0, 'no script')

-- 3. row text is escaped
local out = ChaosRmlTest.rowsRml(1, escape, 'a<%d>', function() return '&' end)
eq(out, '<div class="row"><span class="name">a&lt;1&gt;</span><span class="value">&amp;</span></div>', 'row escaped')

print(string.format('rmltest: %d checks, %d failures', checks, failures))
os.exit(failures == 0 and 0 or 1)
