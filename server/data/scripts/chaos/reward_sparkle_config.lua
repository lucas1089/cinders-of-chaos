-- Reward chest sparkle: numbers (reward_sparkle.lua, rules in reward_sparkle_core.lua; server/README.md "Reward chests").
-- One shared timer glints every unopened reward chest that a system registered (the rift chest, the sealed coffer).
return {
	enabled = true,
	intervalMs = 2500, -- one timer for every chest; each chest glints at most once per interval
	effect = "CONST_ME_YELLOW_RINGS", -- a soft gold ring over the chest (a CONST_ME_* name; unknown: no effect)
	maxAge = 30 * 60, -- seconds: an entry older than this is dropped even when its system forgot to remove it
	maxEntries = 200 -- at most this many chests glint at once (the oldest go first)
}
