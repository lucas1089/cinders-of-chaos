-- skin.rcss rules that keep a drop-down list readable (O576). Run from the repository root.
local f = assert(io.open('client/overlay/modules/client_chaos_rmlform/skin.rcss', 'rb'))
local css = f:read('*a')
f:close()

local fails, checks = 0, 0
local function ok(cond, what)
  checks = checks + 1
  if not cond then
    print('FAIL ' .. what)
    fails = fails + 1
  end
end

local function rule(selector)
  local pat = '\n' .. selector:gsub('%p', '%%%0') .. '%s*{([^}]*)}'
  return css:match(pat)
end

local bodies = {}
for body in css:gmatch('\nselect:checked%s*{([^}]*)}') do bodies[#bodies + 1] = body end
local open = table.concat(bodies, ' ')
ok(#bodies >= 2, 'select:checked has its look and its lift')
local z = open:match('z%-index:%s*(%d+)')
ok(z and tonumber(z) > 100, 'an open select lies above the controls that follow it (z-index ' .. tostring(z) .. ')')
ok(open:find('position:%s*relative') ~= nil, 'z-index needs a positioned element')
local box = rule('select selectbox')
ok(box and box:find('background%-color') ~= nil, 'the list has an opaque background')
print(string.format('rmlform_skin: %d checks, %d failed', checks, fails))
os.exit(fails == 0 and 0 or 1)
