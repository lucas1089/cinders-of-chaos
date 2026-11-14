-- mainquest_boss_config.lua: Vael Ashmourn's own attacks (O554; mainquest_boss_attacks_core.lua, mainquest_boss.lua,
-- tools/mainquest_boss_model.py, server/README.md "Vael's attacks (O554)"). Plain table, no engine calls: the Lua tests and the
-- boss model read it. The model is the source of the numbers: `--check` holds every share, windup and cadence below.
--
-- An attack is one or two floor shapes (`parts`), drawn on the floor by the floor telegraph (O549, ChaosTelegraph) `windMs` before the
-- hit. Only a character standing on a marked tile at the hit takes that part's `share` of the maximum health, before the resistance
-- of the phase's element (mainquest_config.lua boss.phases; the same hitAmount rule as Vael's melee hit) and the tier's hit scale
-- (trials_config.lua mq). A dodged attack does nothing. The shapes are boss_mechanics_core.lua's (G.shape): the same tile rules
-- as the world bosses, so the floor marks look the same.
--   cone    length, spread       from Vael towards the character, wider with the distance
--   line    halfWidth, length    a beam from Vael towards the character
--   ring    inner, outer         every tile from `inner` to `outer` tiles from Vael: the middle (and what lies past `outer`) is safe
--   cross   halfWidth            the row and the column through Vael, 2 x halfWidth + 1 wide
--   puddles count, radius, onPlayers   `count` circles of `radius`, `onPlayers` of them under the character, the rest anywhere
-- Lua 5.1 / LuaJIT and 5.3.

local function T(en, pt)
	return {en = en, pt = pt}
end

return {
	enabled = true,

	-- ms between two checks of the loop (the windup and the hit are timed by their own events)
	tickMs = 250,
	-- the first attack comes this long after Vael wakes (the character walks in, reads the room)
	firstDelayMs = 6000,

	-- never an unavoidable hit. The windup is at least `minWindMs`; the fairness check (G.makeFair) walks the reference character
	-- (refLevel, the step rules of chaos_speed.lua) for windup - reactionMs and cuts a pocket out of the shape when no safe tile
	-- is in reach, and an attack that still cannot be made fair is not cast. reactionMs is the time to see the mark and start to
	-- move: the client sees the mark after about half the ping, the move reaches the server after the other half, so 500 ms
	-- covers 300 ms of ping. lagMs: the hit is read this long after the mark's end, so a step taken in time is never lost to lag.
	minWindMs = 1800,
	reactionMs = 500,
	lagMs = 150,
	fair = {refLevel = 500},
	-- the quiet time between the hit of one attack and the windup of the next
	gapMs = 2000,

	-- ms between the starts of two attacks, by phase (mainquest_config.lua boss.phases: fire, cold, lightning, chaos); never less than
	-- the attack's windup + gapMs. Below the Trials' enrageBelow (trials_config.lua) the attacks come `cadenceMult` as far apart and
	-- hit `damageMult` as hard (the windup does not shrink).
	every = {9000, 8500, 8000, 8000},
	enrage = {cadenceMult = 0.85, damageMult = 1.2},

	-- the dodge share the model assumes (the share of attacks a character steps out of): a typical player and a poor one
	dodge = {typical = 0.75, poor = 0.50},

	-- the floor mark's colour (telegraph_config.lua colors) and the hit's stock effect, by the element of the phase
	color = {fire = "orange", ice = "blue", energy = "violet", earth = "green"},
	hitEffect = {fire = "CONST_ME_FIREAREA", ice = "CONST_ME_ICEAREA", energy = "CONST_ME_ENERGYAREA", earth = "CONST_ME_POISONAREA"},

	-- phases: indexes into mainquest_config.lua boss.phases (1 fire, 2 cold, 3 lightning, 4 chaos)
	attacks = {
		{key = "cinder_breath", phases = {1, 3}, windMs = 2400,
			name = T("Cinder Breath", "Sopro de Brasa"), say = T("Cinder Breath!", "Sopro de Brasa!"),
			tip = T("A cone ahead of Vael: step out to the side or behind him.", "Um cone à frente de Vael: saia para o lado ou para trás dele."),
			parts = {{kind = "cone", length = 7, spread = 3, share = 0.15}}},
		{key = "ember_rain", phases = {1, 2}, windMs = 2600,
			name = T("Ember Rain", "Chuva de Brasas"), say = T("Ember Rain!", "Chuva de Brasas!"),
			tip = T("Circles land on the floor, one under you: leave every circle.", "Círculos caem no chão, um sob você: saia de todos os círculos."),
			parts = {{kind = "puddles", count = 5, radius = 2, onPlayers = 1, share = 0.13}}},
		{key = "ashen_ring", phases = {2, 3}, windMs = 2800,
			name = T("Ashen Ring", "Anel de Cinzas"), say = T("Ashen Ring!", "Anel de Cinzas!"),
			tip = T("A ring round Vael: stand next to him, or outside it.", "Um anel em volta de Vael: fique junto dele, ou fora do anel."),
			parts = {{kind = "ring", inner = 2, outer = 6, share = 0.17}}},
		{key = "oath_lance", phases = {2, 3, 4}, windMs = 2200,
			name = T("Oath Lance", "Lança do Juramento"), say = T("Oath Lance!", "Lança do Juramento!"),
			tip = T("A beam from Vael towards you: step off the line.", "Um raio de Vael na sua direção: saia da linha."),
			parts = {{kind = "line", halfWidth = 1, length = 14, share = 0.19}}},
		{key = "warden_cross", phases = {3}, windMs = 2800,
			name = T("Warden's Cross", "Cruz do Guardião"), say = T("Warden's Cross!", "Cruz do Guardião!"),
			tip = T("A cross through Vael: stand in a corner between its arms.", "Uma cruz por Vael: fique num canto entre os braços."),
			parts = {{kind = "cross", halfWidth = 1, share = 0.17}}},
		-- the last phase mixes two shapes: the cross and the rain land together (two marks, one windup)
		{key = "final_oath", phases = {4}, windMs = 3000,
			name = T("Final Oath", "Juramento Final"), say = T("Final Oath!", "Juramento Final!"),
			tip = T("The cross and the rain together: stand in a corner of the cross, away from the circles.", "A cruz e a chuva juntas: fique num canto da cruz, longe dos círculos."),
			parts = {{kind = "cross", halfWidth = 1, share = 0.10}, {kind = "puddles", count = 4, radius = 2, onPlayers = 1, share = 0.09}}}
	}
}
