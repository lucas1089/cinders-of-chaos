-- luajit shaderfx_test.lua && lua5.3 shaderfx_test.lua
-- Pure helpers of game_shaderfx: orb fill and slosh, the frame shine rule, greyscale of locked items, and the shader
-- files the module registers.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'shaderfxlogic.lua')
local L = ShaderFxLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- fill
eq(L.fill(50, 100), 0.5, 'half') eq(L.fill(100, 100), 1, 'full') eq(L.fill(150, 100), 1, 'over max')
eq(L.fill(0, 100), 0, 'empty') eq(L.fill(10, 0), 0, 'no max') eq(L.fill(nil, nil), 0, 'nil') eq(L.fill(-5, 10), 0, 'negative')

-- slosh: a change raises it (bigger change, more), rest decays it to 0
eq(L.sloshAfter(0.5, 0.5, 0), 0, 'no change, no slosh')
local small, big = L.sloshAfter(0.5, 0.48, 0), L.sloshAfter(0.9, 0.2, 0)
eq(small > 0 and small < big, true, 'a big hit sloshes more') eq(big, 1, 'capped at 1')
eq(L.sloshAfter(0.5, 0.49, 0.9), 0.9, 'a change never calms it')
eq(L.decay(1, 0), 1, 'no time, no decay')
eq(L.decay(1, 1000) < 0.2, true, 'one second calms most of it')
eq(L.decay(0.02, 1000), 0, 'too small to see: 0')
local s, ticks = 1, 0
while s > 0 and ticks < 1000 do s = L.decay(s, 50) ticks = ticks + 1 end
eq(ticks < 60, true, 'calm within 3 s of 50 ms ticks')

-- orb params are clamped
local a, b, c, d = L.orbParams(1.5, -1, 0.3)
eq(a, 1, 'fill clamped') eq(b, 0, 'slosh clamped') eq(c, 0.3, 'phase') eq(d, 1, 'foam on')

-- phase: stable, in 0..1, differs between keys
eq(L.phaseOf('slot1'), L.phaseOf('slot1'), 'stable')
eq(L.phaseOf('slot1') ~= L.phaseOf('slot2'), true, 'different keys differ')
eq(L.phaseOf(nil) >= 0 and L.phaseOf(nil) < 1, true, 'in range')

-- shine: legendary (5) and up and uniques, only with the option on
eq(L.shineParams(4, false, true, 'k'), nil, 'rare: no shine')
eq(L.shineParams(5, false, true, 'k') ~= nil, true, 'legendary shines')
eq(L.shineParams(15, false, true, 'k') ~= nil, true, 'an old Transcendent (Divine) shines')
eq(L.shineParams(1, true, true, 'k') ~= nil, true, 'a unique shines whatever its rarity')
eq(L.shineParams(9, false, false, 'k'), nil, 'option off: no shine')
local p1, p2, p3, p4 = L.shineParams(5, false, true, 'k')
eq(p1 >= 0 and p1 < L.SHINE_PERIOD, true, 'phase within a period') eq(p2, L.SHINE_PERIOD, 'period')
eq(p3, L.SHINE_STRENGTH, 'strength') eq(p4, L.SHINE_WIDTH, 'width')
eq(select(3, L.shineParams(2, true, true, 'k')), L.UNIQUE_SHINE_STRENGTH, 'uniques shine brighter')

-- greyscale of locked items
local function item(attrs) return { getCustomAttribute = function(self, k) return attrs[k] or 0 end } end
eq(L.isLocked(item({ [3] = 1 })), true, 'locked') eq(L.isLocked(item({})), false, 'not locked')
eq(L.isLocked(item({ [3] = 2 })), false, 'bound (the Everfull potions): drawn in their colours, not grey')
eq(L.isLocked(nil), false, 'no item') eq(L.isLocked({}), false, 'an item without attributes')
eq(L.greyAction(true, false), 'grey', 'grey a locked item') eq(L.greyAction(true, true), nil, 'already grey')
eq(L.greyAction(false, true), 'clear', 'unlocked: take our grey back') eq(L.greyAction(false, false), nil, 'leave other shaders')

-- a slot whose setItemShader re-enters (the engine's onItemChange -> game_itemrarity -> onSlotItem): one shader call
-- each way, no endless recursion (live test 2026-10-14: "stack overflow" opening a backpack with the Loot Bag)
do
  local calls, depth, maxDepth = 0, 0, 0
  local slot = {}
  local locked = true
  function slot:setItemShader(name)
    calls = calls + 1
    depth = depth + 1
    if depth > maxDepth then maxDepth = depth end
    if depth < 50 then L.applyItemGrey(self, locked) end
    depth = depth - 1
  end
  eq(L.applyItemGrey(slot, true), 'grey', 're-entrant slot: greyed')
  eq(calls, 1, 're-entrant slot: one shader call to grey')
  eq(maxDepth < 50, true, 're-entrant slot: no recursion')
  locked = false
  calls = 0
  eq(L.applyItemGrey(slot, false), 'clear', 're-entrant slot: cleared')
  eq(calls, 1, 're-entrant slot: one shader call to clear')
  eq(slot.sfxGrey, nil, 're-entrant slot: mark gone')
end

-- the registered shader files exist (client/overlay/data/shaders)
local shaders = dir .. '../../data/shaders/'
for _, s in ipairs(L.UI_SHADERS) do
  for _, f in ipairs({ s.vertex, s.fragment }) do
    local fh = io.open(shaders .. f:match('[^/]+$') .. '.frag', 'r')
    eq(fh ~= nil, true, s.name .. ': ' .. f .. '.frag exists')
    if fh then fh:close() end
  end
end

-- orb sizes and their place beside the chat panel
do
  local size, liquid, font = L.orbSize(nil)
  eq(size, 150, 'default orb size is medium')
  eq(liquid, 99, 'liquid keeps 50/76')
  eq(font ~= nil, true, 'a font for the number')
  eq(L.orbSize(1), 76, 'small')
  eq(L.orbSize(3), 190, 'large')
  eq(L.orbSize(9), 150, 'unknown size is the default')
  -- each size has its own ring and mask, made at twice the drawn size (tools/gen_orb_art.py): a 76 px ring and a
  -- 64 px mask stretched to the medium and large orbs looked blurred and stepped (owner screenshot 2026-10-21)
  local function pngSize(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local h = f:read(24)
    f:close()
    if not h or #h < 24 or h:sub(2, 4) ~= 'PNG' then return nil end
    local function u32(i) local a, b, c, d = h:byte(i, i + 3) return ((a * 256 + b) * 256 + c) * 256 + d end
    return u32(17), u32(21)
  end
  local here = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
  for opt = 1, 3 do
    local size, liquid = L.orbSize(opt)
    local ring, mask = L.orbArt(opt)
    eq(ring, '/modules/game_shaderfx/images/orb_ring_' .. size, 'ring image of size ' .. opt)
    eq(mask, '/modules/game_shaderfx/images/orb_mask_' .. liquid, 'mask image of size ' .. opt)
    local rw, rh = pngSize(here .. 'images/orb_ring_' .. size .. '.png')
    eq(rw, 2 * size, 'ring of size ' .. opt .. ' is 2x its drawn width') eq(rh, 2 * size, 'ring height')
    local mw, mh = pngSize(here .. 'images/orb_mask_' .. liquid .. '.png')
    eq(mw, 2 * liquid, 'mask of size ' .. opt .. ' is 2x its drawn width') eq(mh, 2 * liquid, 'mask height')
  end
  eq(select(1, L.orbArt(nil)), select(1, L.orbArt(L.ORB_DEFAULT_SIZE)), 'no option: the default size art')
  -- every orb size beside the chat (game_chatpanel's layout): inside the window, clear of the grips and the chat
  local C = rawget(_G, 'ChaosChatLogic')
  if not C then
    dofile(((arg and arg[0] or ''):match('^(.*[/\\])') or './') .. '../game_chatpanel/chatpanel_logic.lua')
    C = ChaosChatLogic
  end
  local m = C.orbMargins()
  for opt = 1, 3 do
    local size = L.orbSize(opt)
    for _, off in ipairs({ false, -4000, 4000 }) do
      local p = C.layout({ regionLeft = 0, regionRight = 1920, windowLeft = 0, windowWidth = 1920, width = 760,
        offset = off or nil, orbSize = size })
      eq(p.orbs, true, 'orb size ' .. opt .. ' fits a 1920 window')
      local lifeLeft, lifeRight = p.chatLeft - m.left - size, p.chatLeft - m.left
      local manaLeft = p.chatLeft + p.chatWidth + m.right
      eq(lifeLeft >= 0 and manaLeft + size <= 1920, true, 'orbs inside the window (size ' .. opt .. ')')
      eq(lifeRight <= p.chatLeft - C.MOVE_GRIP_GAP - C.GRIP, true, 'life orb clear of the move grip and the chat')
      eq(manaLeft >= p.chatLeft + p.chatWidth + C.WIDTH_GRIP_GAP + C.GRIP, true, 'mana orb clear of the width grip')
    end
  end
end

-- globes docked into the hotbar: any diameter, the nearest art
do
  local d, liquid, font, ring, mask = L.dockedSize(110)
  eq(d, 110, 'docked size is the asked diameter'); eq(liquid, 72, 'docked liquid keeps the ring proportion')
  eq(ring, L.ORB_IMAGES .. 'orb_ring_76', 'docked 110 is nearer the 76 art'); eq((select(4, L.dockedSize(138))), L.ORB_IMAGES .. 'orb_ring_150', 'docked 138 uses the 150 art'); eq(font, 'chaos-display-16px', 'docked font')
  d, liquid, font, ring, mask = L.dockedSize(80)
  eq(ring, L.ORB_IMAGES .. 'orb_ring_76', 'docked 80 uses the 76 art'); eq(font, 'chaos-outline-11px', 'small docked font')
  eq(mask, L.ORB_IMAGES .. 'orb_mask_50', 'docked 80 mask')
  -- the plain fill is cut in the mask image's texels (100 for orb_mask_50), not the drawn liquid's (53 * 2): a clip
  -- of 106 of 100 texels drew the fill up and left of the ring (owner screenshot 2026-11-05)
  eq((select(6, L.dockedSize(80))), 100, 'docked 80 mask texels'); eq((select(6, L.dockedSize(138))), 198, 'docked 138 mask texels')
  local clip = L.plainClip(1, select(6, L.dockedSize(80)), 53)
  eq(clip.width, 100, 'full docked fill spans the whole mask'); eq(clip.y, 0, 'full docked fill starts at the top')
  eq(L.dockedSize(5), 40, 'docked size floor'); eq((select(4, L.dockedSize(nil))), L.ORB_IMAGES .. 'orb_ring_76', 'no size')
  eq(L.ORB_SIZES[2].size, 150, 'the art sizes the docked globes pick from')
  local clip, h = L.plainClip(0.5, 100, 50)
  eq(clip.y, 50, 'plain globe half: cut from the top half'); eq(clip.height, 50, 'plain globe half height'); eq(h, 25, 'plain height')
  clip, h = L.plainClip(1, 100, 50)
  eq(clip.y, 0, 'plain globe full'); eq(h, 50, 'plain full height')
  clip, h = L.plainClip(0, 100, 50)
  eq(clip.height, 0, 'plain globe empty'); eq(h, 0, 'plain empty height')
  clip = L.plainClip(7, 100, 50)
  eq(clip.height, 100, 'plain fill capped at 1')
end

-- Orb size on docked globes: small / medium / large scale the hotbar diameter; a large one grows outward
do
  eq((L.dockedDiameter(110, 2)), 110, 'docked medium keeps the hotbar diameter')
  eq((L.dockedDiameter(110, 1)), 83, 'docked small'); eq((select(2, L.dockedDiameter(110, 1))), 0, 'small does not grow')
  eq((L.dockedDiameter(110, 3)), 126, 'docked large'); eq((select(2, L.dockedDiameter(110, 3))), 16, 'large grows 16 px')
  eq((L.dockedDiameter(110, nil)), 110, 'no option is medium'); eq((L.dockedDiameter(40, 1)), 40, 'never below 40')
end

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('shaderfx_test: ' .. checks .. ' checks OK')
