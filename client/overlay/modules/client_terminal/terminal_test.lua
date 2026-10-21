-- luajit terminal_test.lua && lua5.3 terminal_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
-- The stand-in console runs nothing: no toggle, no executeCommand, no loadstring / load / dofile anywhere in it.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, checks = 0, 0
local function check(cond, what)
  checks = checks + 1
  if not cond then print('FAIL ' .. what); fails = fails + 1 end
end
local f = assert(io.open(dir .. 'terminal.lua', 'r'))
local src = f:read('*a')
f:close()
local code = src:gsub('%-%-[^\n]*', '')
for _, word in ipairs({'loadstring', 'load%s*%(', 'dofile', 'pcall', 'require', 'g_keyboard', 'executeCommand', 'toggle'}) do
  check(not code:find(word), 'no ' .. word .. ' in the stand-in')
end
local env = setmetatable({}, {__index = _G})
local chunk = (loadstring and setfenv) and assert(loadstring(src)) or assert(load(src, 'terminal', 't', env))
if setfenv then setfenv(chunk, env) end
chunk()
for _, name in ipairs({'init', 'terminate', 'show', 'hide', 'bindHotkey', 'flushLines', 'addLine', 'clear'}) do
  check(type(env[name]) == 'function', name .. ' exists for its callers')
  check(select('#', env[name]('x')) == 0, name .. ' does nothing')
end
check(env.toggle == nil and env.executeCommand == nil, 'nothing to open or run')
if fails > 0 then
  print(string.format('terminal_test: %d of %d checks failed', fails, checks))
  os.exit(1)
end
print(string.format('terminal_test: %d checks ok', checks))
