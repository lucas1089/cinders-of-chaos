-- Quiet first login and the introductions after it (O761, owner 2026-11-24: "tire tudo isso de janela abrindo quando um player
-- entra pela primeira vez. só mostre o daily reward e encaminhe pra quest principal, que deve mostrar primeiro como funciona o
-- helper. depois introduza as outras coisas."). intros.lua (engine), intros_core.lua (rules); server/README.md "Quiet first
-- login (O761)". Data only, no engine calls (tests/intros_test.lua reads it). Lua 5.1 / LuaJIT and 5.3.
--
-- A character's first login (lastLoginSaved 0) gets the Daily Reward window and nothing else: no welcome toast, no Helper, no
-- outfit window, no menu callout, no first-hour tip, no Next Goals rows, no patch notes. When the Daily Reward closes (or there is
-- none to claim) the main quest starts on its first step, the Helper (mainquest_config.lua `helper`). The other introductions come
-- one at a time, each when its quest step is done or at its level, whichever is first.

local function T(en, pt)
	return {en = en, pt = pt}
end

return {
	enabled = true,

	-- player storages: block 7103160-7103169 (server/README.md "Storage keys"): +0 the state (-1 never seen, 0 open: a character
	-- from before O761, a staff or a tester character, every introduction as before; 1 quiet: its first login came under O761),
	-- +1 the introductions given (bits, by index of `intros`); +2..+9 free
	storage = {base = 7103160, state = 0, shown = 1, last = 7103169},
	states = {open = 0, quiet = 1},
	staffGroup = 4,

	-- the windows of the login window queue (daily.lua ChaosLoginWindows) a first login opens by itself: only these
	firstLoginWindows = {daily = true},
	-- waiting for the login windows to be done (the player closed the Daily Reward): a look every pollMs, at most maxWaitMs
	wait = {pollMs = 1000, maxWaitMs = 180000},
	-- the main quest's first look on a first login: at most this long after the login (mainquest_config.lua firstLookMs otherwise),
	-- then it waits for the login windows
	questAfterMs = 4000,
	-- one introduction per run; the next after gapMs while more are due (the first hour's pace, firsthour_config.lua `pace`)
	pace = {gapMs = 60000},
	-- the first run after a login (a returning quiet character) waits for the login windows and then this long
	loginDelayMs = 8000,

	-- the introductions, in the order they come. An introduction is due when the main quest is past the step `after` (its key in
	-- mainquest_config.lua) or the character reached `level`, whichever is first; with the quest not running (skipped, done, off)
	-- it is due at once (still one per gapMs). `system`: what it lets go (that system keeps its own pace, bits and the player's
	-- own "don't show again" settings): "outfit" opens the Customise Character window once, "firsthour" the first-hour tips
	-- (NEW ADVENTURER toasts and the hunting marks, firsthour.lua), "unlocks" the "New" callouts of the top menu (unlocks.lua: the
	-- Bounty Board, the Market, ...), "goals" the Next Goals rows of the goal tracker (goals.lua). `text`: one line to the chat
	-- (and a toast) when it opens, or nil.
	-- NEVER reorder or insert: the bits are by index; add new introductions at the end (up to 30)
	intros = {
		{key = "outfit", after = "warden", level = 10, system = "outfit",
			text = T("Make the character yours: the Customise Character window (Character > Outfit) changes your look, colours and effects.",
				"Deixe o personagem com a sua cara: a janela Personalizar Personagem (Personagem > Outfit) muda a aparência, as cores e os efeitos.")},
		{key = "tips", after = "trolls", level = 10, system = "firsthour", text = nil},
		{key = "unlocks", after = "tusks_in", level = 11, system = "unlocks", text = nil},
		{key = "goals", after = "gear", level = 12, system = "goals",
			text = T("Next Goals is open: the tracker on the left now also lists what to do at your level (Adventure > Next Goals).",
				"Próximos objetivos liberado: o rastreador à esquerda agora também mostra o que fazer no seu nível (Adventure > Próximos objetivos).")}
	}
}
