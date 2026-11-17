-- Run from the repo root: luajit client/overlay/modules/game_statusfx/statusfx_test.lua (and lua5.3)
-- Covers the pure rules (statusfx_logic.lua): the opcode and the option, the bit order against the server's ids file,
-- the server's messages, the pick of 2 statuses by priority, the start / loop / stop timing, a status that comes back
-- while it stops, the screen cap, the box of the canvas on creatures 1 to 3 tiles wide and the sprite places.
local dir = arg[0]:match('^(.*)/[^/]*$') or '.'
dofile(dir .. '/statusfx_logic.lua')
local L = StatusFxLogic

local fails, checks = 0, 0
local function eq(a, b, msg)
  checks = checks + 1
  if a ~= b then
    fails = fails + 1
    print('FAIL ' .. msg .. ': got ' .. tostring(a) .. ', want ' .. tostring(b))
  end
end

-- ---------------------------------------------------------------- opcode, option, order
eq(L.OPCODE, 165, 'opcode 165 (server ChaosOpcodes.statusVfx)')
eq(L.optionOn(nil), true, 'option default on'); eq(L.optionOn(false), false, 'option off'); eq(L.optionOn(true), true, 'option on')
eq(L.hello(true).data.on, 1, 'hello on'); eq(L.hello(false).data.on, 0, 'hello off'); eq(L.hello(true).action, 'hello', 'hello action')
local ids = dofile(dir .. '/../../../../server/data/lib/chaos_status_vfx_ids.lua')
eq(#L.ORDER, #ids.order, 'as many statuses as the server')
for i, name in ipairs(ids.order) do eq(L.ORDER[i], name, 'bit ' .. (i - 1)) end
eq(#L.PRIORITY, #L.ORDER, 'every status has a priority')
for _, name in ipairs(L.ORDER) do eq(type(L.RANK[name]), 'number', 'rank of ' .. name) end
eq(L.BITS.burn, 1, 'burn bit'); eq(L.BITS.rage, 8192, 'rage bit')

-- ---------------------------------------------------------------- messages
local e, ms = {}, {}
for _, name in ipairs(ids.order) do
  local s = ids.status[name]
  e[#e + 1] = s.start; e[#e + 1] = s.loop; e[#e + 1] = s.stop
  ms[#ms + 1] = s.startMs; ms[#ms + 1] = s.loopMs; ms[#ms + 1] = s.stopMs
end
local cfg = L.parseCfg({ action = 'cfg', data = { on = 1, e = e, ms = ms } })
eq(cfg.on, true, 'cfg on')
eq(cfg.fx.burn.start.id, ids.status.burn.start, 'burn start id')
eq(cfg.fx.burn.loop.n, 16, 'burn loop phases'); eq(cfg.fx.burn.start.n, 11, 'burn start phases')
eq(cfg.fx.rage.stop.id, ids.status.rage.stop, 'rage stop id')
eq(L.parseCfg({ action = 'cfg', data = { on = 0 } }).on, false, 'cfg off')
eq(L.parseCfg({ action = 'cfg', data = { on = 1, e = { 1, 2 }, ms = { 1, 2 } } }).on, false, 'a short list is off')
local bad = {}
for i, v in ipairs(e) do bad[i] = v end
bad[5] = 'x'
eq(L.parseCfg({ action = 'cfg', data = { on = 1, e = bad, ms = ms } }).on, false, 'a bad id is off')
eq(L.parseCfg({ action = 's' }), nil, 'not a cfg'); eq(L.parseCfg(nil), nil, 'nil')
local list = L.parseList({ action = 's', data = { l = { 10, 1, 11, 0, -3, 4, 12, 99999999, 13, 'x', 14 } } })
eq(#list, 2, 'only good pairs'); eq(list[1].id, 10, 'id'); eq(list[1].mask, 1, 'mask'); eq(list[2].mask, 0, 'a zero mask clears')
eq(L.parseList({ action = 'cfg', data = {} }), nil, 'not a list')

-- ---------------------------------------------------------------- pick
eq(table.concat(L.pick(0), ','), '', 'nothing')
eq(table.concat(L.pick(L.BITS.burn + L.BITS.haste + L.BITS.stun), ','), 'stun,burn', 'two, the strongest first')
eq(table.concat(L.pick(L.BITS.regen + L.BITS.bless + L.BITS.haste, 3), ','), 'bless,regen,haste', 'three when asked')
eq(#L.pick(16383), 2, 'every bit: still two')
eq(#L.pick('junk'), 0, 'junk')

-- ---------------------------------------------------------------- timing
local m = L.newModel()
L.setMask(m, 7, L.BITS.burn)
eq(L.sync(m, 7, 1000, true), 1, 'one show')
local s = m.shows[7].burn
eq(s.part, 'start', 'starts')
local id, ph = L.frame(s, cfg.fx.burn, 1000)
eq(id, cfg.fx.burn.start.id, 'start effect'); eq(ph, 0, 'phase 0')
id, ph = L.frame(s, cfg.fx.burn, 1000 + 66 * 10)
eq(id, cfg.fx.burn.start.id, 'last start phase'); eq(ph, 10, 'phase 10')
id, ph = L.frame(s, cfg.fx.burn, 1000 + 66 * 11)
eq(id, cfg.fx.burn.loop.id, 'the loop follows'); eq(ph, 0, 'loop phase 0'); eq(s.part, 'loop', 'part loop')
id, ph = L.frame(s, cfg.fx.burn, 1000 + 66 * (11 + 16 * 3 + 5))
eq(ph, 5, 'the loop wraps')
eq(L.sync(m, 7, 5000, true), 1, 'held: no change'); eq(m.shows[7].burn.part, 'loop', 'still loop')
L.setMask(m, 7, 0)
L.sync(m, 7, 6000, true)
eq(m.shows[7].burn.part, 'stop', 'the stop begins')
id, ph = L.frame(m.shows[7].burn, cfg.fx.burn, 6000 + 66 * 8)
eq(id, cfg.fx.burn.stop.id, 'stop effect'); eq(ph, 8, 'stop phase')
eq(L.frame(m.shows[7].burn, cfg.fx.burn, 6000 + 66 * 9), nil, 'over')
eq(L.reap(m, 7, cfg, 6000 + 66 * 9), 0, 'reaped'); eq(m.shows[7], nil, 'no shows left')
-- a status that comes back while its stop plays starts again
L.setMask(m, 7, L.BITS.burn); L.sync(m, 7, 0, true); L.setMask(m, 7, 0); L.sync(m, 7, 100, true)
L.setMask(m, 7, L.BITS.burn); L.sync(m, 7, 200, true)
eq(m.shows[7].burn.part, 'start', 'back: start again'); eq(m.shows[7].burn.t0, 200, 'from now')
-- the cap of a creature: a stronger status enters, the weakest running one stops
L.setMask(m, 7, L.BITS.burn + L.BITS.poison); L.sync(m, 7, 300, true)
L.setMask(m, 7, L.BITS.burn + L.BITS.poison + L.BITS.stun); L.sync(m, 7, 400, true)
eq(m.shows[7].stun ~= nil, true, 'stun enters'); eq(m.shows[7].poison.part, 'stop', 'the weakest stops')
eq(m.shows[7].burn.part ~= 'stop', true, 'burn stays')
-- not allowed (the screen cap): nothing new starts
local m2 = L.newModel()
L.setMask(m2, 1, L.BITS.burn)
eq(L.sync(m2, 1, 0, false), 0, 'not allowed: no show')

-- ---------------------------------------------------------------- screen cap
local m3 = L.newModel()
for i = 1, 20 do L.setMask(m3, i, L.BITS.burn + L.BITS.poison) end
local order = {}
for i = 1, 20 do order[i] = i end
local allowed = L.budget(m3, order, L.CAP_SCREEN)
local n = 0
for _ in pairs(allowed) do n = n + 1 end
eq(n, 12, '24 statuses: 12 creatures of two'); eq(allowed[1], true, 'the nearest'); eq(allowed[13], nil, 'the 13th waits')
n = 0
for _ in pairs(L.budget(m3, order, L.CAP_SCREEN_MOBILE)) do n = n + 1 end
eq(n, 6, 'a phone: 6 creatures of two')

-- ---------------------------------------------------------------- box and sprites
local size, ml, mt, tile = L.box(32, 1)
eq(size, 64, 'one tile: 64 px'); eq(ml, 0, 'centred'); eq(mt, -12, 'feet point on the feet'); eq(tile, 32, 'tile 32')
size, ml, mt, tile = L.box(32, 2)
eq(size, 96, 'two tiles: 96 px'); eq(ml, -16, 'pulled left'); eq(mt, -40, 'pulled up'); eq(tile, 48, 'tile 48')
size = L.box(32, 9)
eq(size, 128, 'capped at three tiles')
size, ml, mt, tile = L.box(64, 1)
eq(size, 128, 'a 64 px engine tile doubles it'); eq(mt, -24, 'and the shift')
eq(L.tilesOf(32, 32), 1, '32 px: 1'); eq(L.tilesOf(64, 32), 2, '64 px: 2'); eq(L.tilesOf(48, 32), 1, '48 px: still 1'); eq(L.tilesOf(49, 32), 2, '49 px: 2'); eq(L.tilesOf(nil, 32), 1, 'unknown: 1'); eq(L.tilesOf(500, 32), 3, 'cap')
eq(L.spriteIndex(0, 0, 0), 1, 'bottom right tile first'); eq(L.spriteIndex(1, 1, 0), 4, 'top left last'); eq(L.spriteIndex(0, 0, 3), 13, 'phase 3')
local x, y = L.tileCorner(0, 0, 32)
eq(x, 32, 'bottom right x'); eq(y, 32, 'bottom right y')
x, y = L.tileCorner(1, 1, 32)
eq(x, 0, 'top left x'); eq(y, 0, 'top left y')

print(string.format('statusfx_test: %d checks, %d failed', checks, fails))
os.exit(fails == 0 and 0 or 1)
