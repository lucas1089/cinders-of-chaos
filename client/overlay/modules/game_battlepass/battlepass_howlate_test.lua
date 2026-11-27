-- V34 (seen in a client): game_battlepass is a load-later module of the base's game_interface, so its init() runs before
-- game_howitworks is loaded and the How it works attach found no module: the Season Pass had no "?" button and no
-- first-open card. battlepass.lua tries the attach again when the window shows. Run from the repo root (luajit, lua5.3).
local dir = 'client/overlay/modules/game_battlepass/'
local count, fails = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then
    fails = fails + 1
    print(string.format('FAIL %s: %s ~= %s', what, tostring(a), tostring(b)))
  end
end

-- a widget that answers every method and gives a child widget for every unknown field (a child is callable too, so
-- w:setText(...) is a no-op and w.rewardsPage a widget)
local function widget()
  local w = { visible = true }
  local methods = {
    isVisible = function(self) return self.visible end,
    show = function(self) self.visible = true end,
    hide = function(self) self.visible = false end,
  }
  return setmetatable(w, {
    __index = function(t, k)
      if methods[k] then return methods[k] end
      if type(k) == 'string' and k:match('^[a-z]') and not k:match('^how') then
        local c = widget()
        rawset(t, k, c)
        return c
      end
      if type(k) == 'string' and k:match('^how') then return nil end
      return function() end
    end,
    __call = function() end,
  })
end

g_ui = { displayUI = function() return widget() end, createWidget = function() return widget() end }
ProtocolGame = { registerExtendedOpcode = function() end, unregisterExtendedOpcode = function() end }
g_game = {}
function connect() end
function disconnect() end
function tr(s) return s end
function scheduleEvent() return nil end
function removeEvent() end
g_clock = { seconds = function() return 0 end }
modules = {}

dofile(dir .. 'battlepass.lua')

init()
local attached = {}
modules.game_howitworks = {
  attach = function(w, key)
    attached[#attached + 1] = key
    w.howKey = key
    return true
  end,
}
eq(#attached, 0, 'init before game_howitworks: nothing attached')
show()
eq(attached[1], 'seasonpass', 'the window shows: the card is attached then')
hide()
show()
eq(#attached, 1, 'once')

print(string.format('battlepass_howlate: %d checks, %d failed', count, fails))
if fails > 0 then os.exit(1) end
