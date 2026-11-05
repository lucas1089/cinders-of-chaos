-- Run from the repo root: luajit client/overlay/modules/game_chaosshots/shots_core_test.lua (also lua5.3)
-- Automatic screenshot rules (shots_core.lua): which base option each Chaos event reads, phones off, one picture per
-- burst, file names (streamer mode leaves the name out), the toast, and the event tests (loot, record, level, boss).
local here = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
dofile(here .. '/shots_core.lua')
local C = ChaosShotsCore
local fails, n = 0, 0
local function eq(a, b, name)
  n = n + 1
  if a ~= b then fails = fails + 1; print('FAIL ' .. name .. ': got ' .. tostring(a) .. ', want ' .. tostring(b)) end
end

-- ------------------------------------------------------------------ options
local saved = {}
local function get(k) return saved[k] end
eq(C.wants('level', get, false), true, 'level up on by default (base default)')
eq(C.wants('loot', get, false), false, 'valuable loot off by default (base default)')
eq(C.wants('boss', get, false), false, 'boss off by default (base default)')
eq(C.wants('achievement', get, false), true, 'achievement on by default')
eq(C.wants('record', get, false), true, 'record on by default (patch 0186 option, or none)')
eq(C.wants('level', get, true), false, 'off on a phone')
eq(C.wants('nothing', get, false), false, 'unknown event')
saved = { autoScreenshot = false, screenshotLevelUp = true }
eq(C.wants('level', get, false), false, 'master switch off')
saved = { autoScreenshot = true, screenshotBossDefeated = true, screenshotLevelUp = false }
eq(C.wants('boss', get, false), true, 'boss ticked')
eq(C.wants('level', get, false), false, 'level unticked')
eq(C.EVENTS.loot.key, 'screenshotValuableLoot', 'loot reads the base Valuable Loot box')
eq(C.EVENTS.boss.key, 'screenshotBossDefeated', 'boss reads the base Boss Defeated box')
eq(C.EVENTS.achievement.key, 'screenshotAchievement', 'achievement box')
eq(C.EVENTS.level.key, 'screenshotLevelUp', 'level box')
eq(C.DELAY_MS, 300, 'delay so the effect shows')

-- ------------------------------------------------------------------ bursts
local st = C.newState()
eq(C.request(st, 'level', 1000), 'shoot', 'first event shoots')
eq(C.request(st, 'loot', 1100), 'merged', 'a second event in the delay is the same picture')
eq(C.taken(st), 'loot', 'named after the higher event')
eq(C.request(st, 'level', 1500), 'repeat', 'the same event right after: no second picture')
eq(C.request(st, 'level', 5000), 'shoot', 'later: a new picture')
eq(C.request(st, 'achievement', 5100), 'merged', 'lower event merged')
eq(C.taken(st), 'level', 'keeps the higher one')
eq(C.taken(st), nil, 'nothing pending')

-- ------------------------------------------------------------------ files and toast
eq(C.fileName('level', 'Ashkar Vel', 120, '2026-11-05_14-03-07', false, nil),
  'screenshots/Ashkar_Vel_120_levelup_2026-11-05_14-03-07.png', 'file name')
eq(C.fileName('boss', 'Ashkar', 120, '2026-11-05_14-03-07', true, nil),
  'screenshots/120_boss_2026-11-05_14-03-07.png', 'streamer mode: no name in the file')
local taken = { ['screenshots/120_boss_d.png'] = true, ['screenshots/120_boss_d_1.png'] = true }
eq(C.fileName('boss', 'X', 120, 'd', true, function(p) return taken[p] end), 'screenshots/120_boss_d_2.png', 'free name')
eq(C.fileName('record', '../evil', 5, 'd', false, nil), 'screenshots/___evil_5_record_d.png', 'no path in the name')
eq(C.toastText('/home/u/.local/share/CindersOfChaos/screenshots', false), 'Screenshot saved in /home/u/.local/share/CindersOfChaos/screenshots', 'toast with the folder')
eq(C.toastText('/home/u/.local/share/CindersOfChaos/screenshots', true), 'Screenshot saved in screenshots', 'streamer: no full path')
eq(C.toastText(nil, false, function(s, a) return '[' .. s:format(a) .. ']' end), '[Screenshot saved in screenshots]', 'translated')

-- ------------------------------------------------------------------ events
eq(C.valuableLoot({ { text = 'a', rank = 4 } }), false, 'rare is not valuable')
eq(C.valuableLoot({ { rank = 2 }, { rank = 5 } }), true, 'legendary')
eq(C.valuableLoot({ { rank = 10 } }), true, 'divine')
eq(C.valuableLoot({ { rank = 100 } }), true, 'unique')
eq(C.valuableLoot(nil), false, 'no drops')
eq(C.isRecordMessage('New record: Tower floor: 31 (was 28)'), true, 'record line')
eq(C.isRecordMessage('Novo recorde: Andar da Torre: 31 (era 28)'), true, 'record line pt-BR')
eq(C.isRecordMessage('New record! Tower floor: 31 by Ashkar.'), false, 'the broadcast of someone else is not yours')
eq(C.isRecordMessage(nil), false, 'nil')
eq(C.isLevelUp(51, 50), true, 'level up')
eq(C.isLevelUp(50, 0), false, 'login sets the level from 0')
eq(C.isLevelUp(49, 50), false, 'level down')
eq(C.isBossKill('boss', 0, 1000, 60000), true, 'boss you fought dies')
eq(C.isBossKill('boss', 0, nil, 60000), false, 'a boss you never attacked')
eq(C.isBossKill('boss', 0, 1000, 1000 + C.ENGAGED_MS + 1), false, 'attacked too long ago')
eq(C.isBossKill('legendary', 0, 1000, 2000), false, 'not a boss')
eq(C.isBossKill('boss', 12, 1000, 2000), false, 'still alive')

print(string.format('%d checks, %d failures', n, fails))
if fails > 0 then os.exit(1) end
