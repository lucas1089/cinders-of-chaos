-- Ember, the Help channel assistant (helpai.lua, helpai_core.lua; server/README.md "Help channel assistant").
-- Returned as a table, loaded as Chaos.helpAIConfig (and by tests/helpai_test.lua). Data only. The model, the budget
-- and the API limits are the sidecar's (server/tools/helpai_config.json); these are the game server's own checks.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,
	botName = "Ember", -- shown as "[Ember]": brackets are not allowed in character names, so nobody can pose as it
	channelId = 7, -- the Help channel of data/chatchannels/chatchannels.xml (also itemlink_core.lua CHANNEL_HELP)
	-- triggers: "?question", "Ember, question" / "Ember: question" / "@Ember question" always; with autoQuestions also
	-- a plain line that ends in "?" and has at least autoMinWords words, from players below tutor
	autoQuestions = true,
	autoMinWords = 3,
	minQuestionChars = 6,
	maxQuestionChars = 200,
	-- per character (memory only: a restart clears it) and for the whole server
	cooldownSeconds = 20,
	perDay = 30,
	globalPerMinute = 20,
	pendingSeconds = 90, -- a question without an answer by then is forgotten
	-- answers go to the whole channel; above publicPerMinute answers in the last minute only the asker sees them
	publicPerMinute = 6,
	maxLineChars = 240, -- one chat line (the client's input limit is 255)
	maxLines = 4,
	-- files in the server folder (bare names), shared with server/tools/helpai.py
	queueFile = "helpai.queue",
	answersFile = "helpai.answers",
	aliveFile = "helpai.alive",
	aliveSeconds = 30, -- the sidecar writes helpai.alive every 5 s; older than this: the sidecar is off
	intervalMs = 1000,
	-- fixed replies, shown only to the asker
	texts = {
		en = {
			cooldown = "Ember: one question every %d seconds, please. Try again in %d s.",
			day = "Ember: you have asked enough for today. A tutor or the wiki can help you further.",
			busy = "Ember is busy right now. Ask again in a minute, or ask a tutor here.",
			off = "Ember is resting. A tutor or a gamemaster in this channel can help, or check the wiki.",
			refused = "Ember cannot answer that one. A tutor or a gamemaster in this channel can help.",
			short = "Ember: write the whole question after the ?, for example: ?how do I ascend",
			pending = "Ember is still thinking about your last question."
		},
		["pt-BR"] = {
			cooldown = "Ember: uma pergunta a cada %d segundos, por favor. Tente de novo em %d s.",
			day = "Ember: você já perguntou bastante hoje. Um tutor ou a wiki podem ajudar.",
			busy = "Ember está ocupada agora. Pergunte de novo em um minuto, ou pergunte a um tutor aqui.",
			off = "Ember está descansando. Um tutor ou um gamemaster neste canal pode ajudar, ou veja a wiki.",
			refused = "Ember não pode responder essa. Um tutor ou um gamemaster neste canal pode ajudar.",
			short = "Ember: escreva a pergunta inteira depois do ?, por exemplo: ?como faço a ascensão",
			pending = "Ember ainda está pensando na sua última pergunta."
		}
	}
}
