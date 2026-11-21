-- The opcode 168 messages a live server sent to a tester bot (O686 phase 8d, closed_spell_wire of server/tools/tester_checks.py on the local test server with the spell upgrades
-- switched on): `state` (ranks with SP into the rank: a heal spell at rank 12, a damage spell at rank 14 with Form I picked, rank 5, and one at rank 20), `forms`, `awakened`
-- (one spell in slot 1), and the answers `awaken` and `pick`. Read by spellranks_wire_test.lua. Captured as JSON by CHAOS_WIRE_DUMP and written by hand into this table; no name,
-- account or address in it (spell ids and numbers only).
return {
  state = { on = true, s = { { 1, 12, 0.181, 1.811 }, { 13, 20, 0, 0 }, { 146, 14, 1.026, 2.565 }, { 163, 5, 0.486, 0.811 } }, v = 1 },
  forms = { f = { { 13, 1, 1 }, { 146, 2, 0 } }, v = 1 },
  awakened = { bonus = 0.1, costs = { { 40, 36, 16 }, { 70, 60, 28 }, { 100, 90, 40 } }, held = 1, on = true, seals = { 0, 0, 0 }, slots = { 13, 0, 0 }, v = 1 },
  awaken = { cost = { pinnacle = 16, rift = 36, waystone = 40 }, name = 'Tempest Sovereign', namePt = 'Tempestade Soberana', ok = true, slot = 1, spell = 13, why = 'ok' },
  pick = { f1 = 2, f2 = 0, free = true, ok = true, pick = 2, price = 0, spell = 146, tier = 1, why = 'first' },
}
