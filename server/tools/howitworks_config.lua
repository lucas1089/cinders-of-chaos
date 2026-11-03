-- The hand-written part of the "How it works" cards (tools/gen_howitworks_data.lua -> client game_howitworks/howitworks_data.lua).
-- Everything that is NOT in a server config lives here: the plain sentences (English and Brazilian Portuguese), which window
-- and which unlock entry a card belongs to, and which goals of game_goals point to it. A number is never typed here:
-- a sentence has {name} places, and `values(C, H)` of the feature gives each name from the server config files (C = the
-- loaded configs by name, H = helpers). The generator stops when a {name} has no value or a value is never used by a
-- sentence of its feature (tests/howitworks_gen_test.lua). Lua 5.1 / LuaJIT and Lua 5.3 compatible, no engine calls.
--
-- Wording rules: very plain, short sentences, no jargon. Proper names (items, orbs, bosses, systems) stay in English in
-- pt-BR as everywhere in the game (client_chaos_locale/pt_br.lua). No other game, server or client is named.
--
-- A feature:
--   key      id of the card (the client asks for it)
--   title    {en, pt}
--   window   the client module whose window shows the "?" button (nil: only a popup or goal opens it)
--   unlocks  keys of unlocks_config.lua entries whose "New" window opens this card
--   goals    keys of goals_config.lua goals that open it from the Next Goals window
--   values   function(C, H) -> {name = value}; a value is a number, a string or {en = ..., pt = ...}
--   who / levels / drops / death / often / what   {en, pt} sentences with {name} places (any may be missing)
-- An entry of unlocks_config.lua that no card names goes to the card of the same key here, else to the card whose window
-- the entry opens (go.open); the others get a card made from the unlock entry itself (generator).

local P = {}

-- the row headings, in the order of the card (the client has tr() texts for them)
P.rows = {"what", "who", "levels", "drops", "death", "often"}

-- the death every real death follows (gentledeath_config.lua); {gentle} in a sentence
P.gentle = {
	en = "A real death: you never lose items. Experience loss is none up to level {free}, half at level {half}, full from level {full}; the first death of the day costs half.",
	pt = "Morte de verdade: você nunca perde itens. A perda de experiência é zero até o nível {free}, metade no nível {half} e total a partir do nível {full}; a primeira morte do dia custa metade."
}

P.features = {
	{key = "tower", title = {"Infinity Tower", "Infinity Tower"}, window = "game_infinitytower", unlocks = {"tower"},
		goals = {"tower10", "tower25"},
		values = function(C, H)
			local B, R = C.tower, C.towerRun
			return {min = H.unlock("tower"), party = R.maxPartySize, l1 = H.curve(B.level, 1), l10 = H.curve(B.level, 10),
				l20 = H.curve(B.level, 20), l40 = H.curve(B.level, 40), bossEvery = B.bossEvery, mile = B.milestoneEvery,
				orbEvery = H.rewardEvery(B, 29856), floorSec = R.floorTimeLimit,
				bossSec = R.floorTimeLimit * R.bossFloorTimeMult, runMin = R.runTimeLimit / 60}
		end,
		who = {"Level {min}+. Go alone or with a party of up to {party}.",
			"Nível {min}+. Vá sozinho ou com um grupo de até {party}."},
		levels = {"Floor 1: level {l1}. Floor 10: level {l10}. Floor 20: level {l20}. Floor 40: level {l40}. It never stops growing. A boss waits every {bossEvery} floors.",
			"Andar 1: nível {l1}. Andar 10: nível {l10}. Andar 20: nível {l20}. Andar 40: nível {l40}. Nunca para de crescer. Um chefe aparece a cada {bossEvery} andares."},
		drops = {"Gold on every floor. Every {mile} floors: crystal coins. Every {orbEvery} floors: Orbs of Upheaval and Fate. Monsters can drop orbs too.",
			"Ouro em todo andar. A cada {mile} andares: crystal coins. A cada {orbEvery} andares: Orbs of Upheaval e Fate. Os monstros também podem soltar orbes."},
		death = {"{gentle}", "{gentle}"},
		often = {"No daily limit. {floorSec} seconds for a floor, {bossSec} for a boss floor, {runMin} minutes for a whole run. The big prize of a floor is paid once per tower season.",
			"Sem limite por dia. {floorSec} segundos por andar, {bossSec} num andar de chefe, {runMin} minutos na corrida toda. O prêmio grande de cada andar sai uma vez por temporada da torre."}},

	{key = "rift", title = {"Rifts", "Fendas"}, window = "game_riftatlas", unlocks = {"rifts"},
		goals = {"rift1", "rift4", "rift6", "rift8", "rift10"},
		values = function(C, H)
			local R = C.rift
			local n = #R.tiers
			local sz = R.layout.sizes
			return {min = R.tiers[1].minLevel, minTop = R.tiers[n].minLevel, top = n, a1 = R.tiers[1].pick[1], b1 = R.tiers[1].pick[2],
				a5 = R.tiers[5].pick[1], b5 = R.tiers[5].pick[2], aTop = R.tiers[n].pick[1], bTop = R.tiers[n].pick[2],
				lives = R.lives.base, extra = R.lives.perExtraPlayer, t1 = H.round(sz[1][3] / 60), t3 = H.round(sz[#sz][3] / 60),
				partyPct = R.party.rewardPerExtraPlayer, partyCap = R.party.rewardCap}
		end,
		who = {"Level {min}+ for tier 1. Higher tiers need more level: tier {top} needs {minTop}. Alone or in a party: a bigger party faces harder monsters and gets +{partyPct}% reward for each extra player (up to +{partyCap}%).",
			"Nível {min}+ para o nível 1. Níveis mais altos pedem mais nível: o nível {top} pede {minTop}. Sozinho ou em grupo: um grupo maior enfrenta monstros mais fortes e ganha +{partyPct}% de recompensa por jogador extra (até +{partyCap}%)."},
		levels = {"Tier 1: monsters of level {a1}-{b1}. Tier 5: {a5}-{b5}. Tier {top} and above: {aTop}-{bTop}.",
			"Nível 1: monstros de nível {a1}-{b1}. Nível 5: {a5}-{b5}. Nível {top} em diante: {aTop}-{bTop}."},
		drops = {"A chest after the boss: gold, orbs and gear. Harder key modifiers give a bigger prize. Seal a tier to get a key for the next one.",
			"Um baú depois do chefe: ouro, orbes e equipamento. Modificadores mais difíceis dão prêmio maior. Sele um nível para ganhar a chave do próximo."},
		death = {"Each death costs one shared life: {lives} alone, +{extra} for each extra player. {gentle} With no lives left the rift ends and the key is lost.",
			"Cada morte gasta uma vida do grupo: {lives} sozinho, +{extra} por jogador extra. {gentle} Sem vidas, a fenda acaba e a chave se perde."},
		often = {"Each run needs one Rift Key; monsters drop them. Time limit: {t1} to {t3} minutes, by map size. When time runs out the rift fails and the key is spent.",
			"Cada corrida pede uma Rift Key; os monstros as soltam. Limite de tempo: {t1} a {t3} minutos, pelo tamanho do mapa. Se o tempo acabar, a fenda falha e a chave é gasta."}},

	{key = "arena", title = {"Arena", "Arena"}, window = "game_arena", unlocks = {"arena"}, goals = {"arena1"},
		values = function(C, H)
			local A = C.arena
			return {min = A.minLevel, ratio = H.round(A.level.ratio * 100), slack = A.level.slack,
				win = A.reward.win[1].count, ff = A.reward.firstWin[1].count, fu = A.reward.firstWin[2].count,
				maxWins = A.reward.maxRewardedWinsPerDay, fightMin = A.fightSeconds / 60, cd = A.countdownSeconds}
		end,
		who = {"Level {min}+. Queue alone for 1v1, or in a party for 2v2 and 3v3. You meet players of a close level: at least {ratio}% of the highest one, or within {slack} levels.",
			"Nível {min}+. Entre na fila sozinho para 1v1, ou em grupo para 2v2 e 3v3. Você enfrenta jogadores de nível próximo: pelo menos {ratio}% do maior, ou até {slack} níveis de diferença."},
		levels = {"No monsters. You fight other players.", "Sem monstros. Você luta contra outros jogadores."},
		drops = {"Each win: {win} Orb of Upheaval. The first win of the day also gives {ff} Orb of Fate and {fu} more Orbs of Upheaval.",
			"Cada vitória: {win} Orb of Upheaval. A primeira vitória do dia dá também {ff} Orb of Fate e mais {fu} Orbs of Upheaval."},
		death = {"No real death. The loser just leaves the match. You lose no experience and no items.",
			"Sem morte de verdade. Quem perde só sai da partida. Você não perde experiência nem itens."},
		often = {"{maxWins} rewarded wins per day. A match is a {cd} second countdown and then {fightMin} minutes at most.",
			"{maxWins} vitórias com prêmio por dia. Uma partida tem {cd} segundos de contagem e depois no máximo {fightMin} minutos."}},

	{key = "battleground", title = {"Battleground", "Campo de Batalha"}, window = "game_battleground",
		values = function(C, H)
			local B = C.bg
			local names = {}
			for _, b in ipairs(B.brackets) do
				names[#names + 1] = b.max and (b.min .. "-" .. b.max) or (b.min .. "+")
			end
			return {min = B.minLevel, tmin = B.teamMin, tmax = B.teamMax, pmax = B.partyMax, brackets = table.concat(names, ", "),
				prep = B.prepSeconds, mins = B.matchSeconds / 60, win = B.honor.win, loss = B.honor.loss, draw = B.honor.draw,
				wfw = B.honor.weeklyFirstWin, cap = B.honor.weeklyCap, presence = H.round(B.minPresenceShare * 100)}
		end,
		who = {"Level {min}+. Teams of {tmin} to {tmax} players per side. Queue alone or in a party of up to {pmax}. You meet players of your level bracket: {brackets}.",
			"Nível {min}+. Times de {tmin} a {tmax} jogadores por lado. Entre na fila sozinho ou em grupo de até {pmax}. Você enfrenta jogadores da sua faixa de nível: {brackets}."},
		levels = {"No monsters. Hits are scaled to your bracket, so a higher level gives only a small edge.",
			"Sem monstros. Os golpes são ajustados à sua faixa, então um nível maior dá só uma pequena vantagem."},
		drops = {"Honor, the PvP vendor's money: {win} for a win, {draw} for a draw, {loss} for a loss. The first win of the week adds {wfw} honor and orbs. At most {cap} honor a week from matches. Be in at least {presence}% of the match.",
			"Honra, o dinheiro do vendedor de PvP: {win} por vitória, {draw} por empate, {loss} por derrota. A primeira vitória da semana soma {wfw} de honra e orbes. No máximo {cap} de honra por semana em partidas. Fique em pelo menos {presence}% da partida."},
		death = {"No real death. You go down and wake in your base. You lose no experience and no items.",
			"Sem morte de verdade. Você cai e acorda na sua base. Você não perde experiência nem itens."},
		often = {"Queue any time. {prep} seconds to get ready, then {mins} minutes. The higher score wins.",
			"Entre na fila quando quiser. {prep} segundos de preparo, depois {mins} minutos. Vence a maior pontuação."}},

	{key = "dungeons", title = {"Dungeons", "Masmorras"}, window = "game_dungeons", unlocks = {"dungeons"}, goals = {"dungeon1"},
		values = function(C, H)
			local list = {}
			for i = 1, #C.bossspawns.dungeons.defaults do
				local d = C.bossspawns.dungeons.defaults[i]
				list[#list + 1] = d.name .. " " .. d.level
			end
			return {min = H.unlock("dungeons"), list = table.concat(list, ", ")}
		end,
		who = {"Level {min}+, by dungeon: {list}. Enter alone or queue with a group.",
			"Nível {min}+, conforme a masmorra: {list}. Entre sozinho ou na fila com um grupo."},
		levels = {"The monsters match the dungeon. In a group they get tougher with each extra player.",
			"Os monstros seguem a masmorra. Em grupo, ficam mais fortes a cada jogador extra."},
		drops = {"Boss chests. The item level of the loot rises with the difficulty.",
			"Baús de chefe. O nível dos itens sobe com a dificuldade."},
		death = {"{gentle}", "{gentle}"},
		often = {"Each dungeon has its own wait before you can enter again; the window shows it.",
			"Cada masmorra tem a sua espera antes de entrar de novo; a janela mostra."}},

	{key = "bosses", title = {"Boss Spawns", "Chefes"}, window = "game_bossspawns", goals = {"wb1", "wb5", "pocket1", "pocket10", "pocket50"},
		values = function(C, H)
			local W, K = C.worldBoss, C.pocket
			local hours = {}
			for h = W.offsetHours % W.intervalHours, 23, W.intervalHours do
				hours[#hours + 1] = H.hhmm(h, 0)
			end
			return {min = W.minLevel, maxP = W.maxPlayers, every = W.intervalHours, hours = table.concat(hours, ", "),
				portal = W.portalMinutes, fight = W.fightMinutes, pmax = K.party.max, daily = K.charges.daily,
				bonusMax = K.charges.bonusMax}
		end,
		who = {"World boss: level {min}+, up to {maxP} players together. Pocket boss: your own copy of a boss, alone or in a party of up to {pmax}.",
			"Chefe mundial: nível {min}+, até {maxP} jogadores juntos. Chefe de bolso: sua própria cópia de um chefe, sozinho ou em grupo de até {pmax}."},
		levels = {"World boss: one big boss, shown at level {min}.",
			"Chefe mundial: um chefe grande, mostrado no nível {min}."},
		drops = {"World boss: its loot, and a reward by how much damage you did. Pocket boss: a smaller reward than the real fight.",
			"Chefe mundial: o saque dele e uma recompensa pelo dano que você causou. Chefe de bolso: recompensa menor que a da luta de verdade."},
		death = {"World boss: {gentle} Pocket boss: a deadly hit sends you back safe. You lose nothing, but the try is spent.",
			"Chefe mundial: {gentle} Chefe de bolso: um golpe mortal manda você de volta em segurança. Você não perde nada, mas a tentativa é gasta."},
		often = {"World boss every {every} hours: {hours}. The portals stay open {portal} minutes. The boss leaves after {fight} minutes. Pocket boss: {daily} free tries per boss each day; more from the online-time shop (up to {bonusMax} saved).",
			"Chefe mundial a cada {every} horas: {hours}. Os portais ficam abertos {portal} minutos. O chefe vai embora após {fight} minutos. Chefe de bolso: {daily} tentativas grátis por chefe por dia; mais na loja de tempo online (até {bonusMax} guardadas)."}},

	{key = "descent", title = {"Ember Descent", "Ember Descent"}, window = "game_descent", goals = {"descent1", "descentclear"},
		values = function(C, H)
			local D = C.descent
			return {min = D.minLevel, max = D.maxPlayers, free = D.freePerDay, bank = D.freeBankDays, weekly = D.freeWeeklyPerWeek,
				shards = D.sigil.craft.shards, gold = H.big(D.sigil.craft.gold), mins = D.timeLimit / 60}
		end,
		who = {"Level {min}+. Alone or in a party of up to {max}.", "Nível {min}+. Sozinho ou em grupo de até {max}."},
		levels = {"8 to 12 rooms, each harder than the last. Taking curses gives more reward.",
			"8 a 12 salas, cada uma mais difícil que a anterior. Aceitar maldições dá mais recompensa."},
		drops = {"Rewards at the end of the run, by the depth you reached.",
			"Recompensas no fim da corrida, conforme a profundidade que você alcançou."},
		death = {"No real death. A deadly hit ends your run, and you keep the rewards of the depth you reached. You lose no experience and no items.",
			"Sem morte de verdade. Um golpe mortal termina a sua corrida, e você fica com as recompensas da profundidade alcançada. Você não perde experiência nem itens."},
		often = {"{free} free run a day (up to {bank} saved if you skip days) and {weekly} free weekly run. More runs cost 1 Ember Sigil: {shards} rune shards and {gold} gold, made in the Descent window. A run lasts {mins} minutes at most.",
			"{free} corrida grátis por dia (até {bank} guardadas se você pular dias) e {weekly} corrida grátis por semana. Mais corridas custam 1 Ember Sigil: {shards} rune shards e {gold} de ouro, feito na janela do Descent. Uma corrida dura no máximo {mins} minutos."}},

	{key = "raid", title = {"Ashen Sepulchre", "Ashen Sepulchre"}, window = "game_raid", goals = {"raid1", "raidclear", "raid3", "raidflawless"},
		values = function(C, H)
			local R = C.raid
			return {min = R.minLevel, max = R.maxPlayers, base = R.basePlayers, day = H.weekday(R.resetDay),
				hour = H.hhmm(R.resetHour, 0)}
		end,
		who = {"Level {min}+. Alone or in a party of up to {max}. The bosses are made for {base} players and scale to your group.",
			"Nível {min}+. Sozinho ou em grupo de até {max}. Os chefes são feitos para {base} jogadores e se ajustam ao seu grupo."},
		levels = {"Several bosses in a row. Each one waits behind a door with its own monsters.",
			"Vários chefes em sequência. Cada um espera atrás de uma porta, com os seus monstros."},
		drops = {"Boss rewards: orbs and the raid's own unique gear.",
			"Recompensas dos chefes: orbes e os itens únicos da própria raide."},
		death = {"No real death. You go down, and if everyone falls it is a wipe. You lose no experience and no items.",
			"Sem morte de verdade. Você cai, e se todos caírem é um desastre. Você não perde experiência nem itens."},
		often = {"Once a week: it resets every {day} at {hour}. Your progress of the week is saved.",
			"Uma vez por semana: reinicia toda {day} às {hour}. O seu progresso da semana fica salvo."}},

	{key = "siege", title = {"Guild Siege", "Guild Siege"}, window = "game_siege", unlocks = {"siege"},
		values = function(C, H)
			local S = C.siege
			return {min = S.minLevel, day = H.weekday(S.weekday), time = H.hhmm(S.hour, S.minute), minM = S.minMembers,
				minG = S.minGuilds, mins = S.matchMinutes, close = S.signupCloseMinutes, down = S.downedSeconds,
				wg = H.big(S.reward.winner.bankGold), wu = S.reward.winner.items[1].count, wf = S.reward.winner.items[2].count,
				og = H.big(S.reward.others.bankGold), ou = S.reward.others.items[1].count,
				pres = S.minPresenceSeconds / 60}
		end,
		who = {"Level {min}+. For guilds: the leader or vice-leader signs the guild up. The guild needs {minM} members, and at least {minG} guilds must sign up.",
			"Nível {min}+. Para guildas: o líder ou vice-líder inscreve a guilda. A guilda precisa de {minM} membros, e pelo menos {minG} guildas precisam se inscrever."},
		levels = {"No monsters. Guilds fight each other for the Chaos Obelisk.",
			"Sem monstros. As guildas lutam entre si pelo Chaos Obelisk."},
		drops = {"Gold in the bank and orbs. The winning guild: {wg} gold, {wu} Orbs of Upheaval and {wf} of Fate. The others: {og} gold and {ou} Orbs of Upheaval. Be there at least {pres} minutes.",
			"Ouro no banco e orbes. A guilda vencedora: {wg} de ouro, {wu} Orbs of Upheaval e {wf} de Fate. As outras: {og} de ouro e {ou} Orbs of Upheaval. Fique pelo menos {pres} minutos."},
		death = {"No real death. You lie down for {down} seconds and wake in your guild base. You lose no experience and no items.",
			"Sem morte de verdade. Você fica caído por {down} segundos e acorda na base da guilda. Você não perde experiência nem itens."},
		often = {"Once a week: {day} at {time}. Sign-ups close {close} minutes before. The match lasts {mins} minutes.",
			"Uma vez por semana: {day} às {time}. As inscrições fecham {close} minutos antes. A partida dura {mins} minutos."}},

	{key = "invasion", title = {"Invasions", "Invasões"}, window = "game_chaosinfo", unlocks = {"events"}, goals = {"invasion1"},
		values = function(C, H)
			local I = C.invasion
			local at = {}
			for _, s in ipairs(I.schedule) do
				at[#at + 1] = {en = H.weekday(s.weekdays[1]).en .. " " .. H.hhmm(s.hour, s.minute),
					pt = H.weekday(s.weekdays[1]).pt .. " " .. H.hhmm(s.hour, s.minute)}
			end
			return {min = I.minLevel, at = H.join(at), chance = I.random.chance, mins = I.timeLimitMinutes, waves = I.waves.count}
		end,
		who = {"Level {min}+, near the invaded area. The more defenders, the bigger the waves.",
			"Nível {min}+, perto da área invadida. Quanto mais defensores, maiores as ondas."},
		levels = {"The invaders are scaled to the level of the area.", "Os invasores seguem o nível da área."},
		drops = {"A reward by how much you helped. Players below level {min} get none.",
			"Uma recompensa conforme a sua ajuda. Quem está abaixo do nível {min} não ganha nada."},
		death = {"{gentle}", "{gentle}"},
		often = {"Every week: {at}. Some days bring a surprise invasion ({chance}% of days). Each one lasts {mins} minutes at most, with {waves} waves; the last has a boss.",
			"Toda semana: {at}. Alguns dias trazem uma invasão surpresa ({chance}% dos dias). Cada uma dura no máximo {mins} minutos, com {waves} ondas; a última tem um chefe."}},

	{key = "bounty", title = {"Bounty Board", "Bounty Board"}, window = "game_bounty", unlocks = {"bounty"},
		goals = {"bounty1", "bounty10", "bounty25"},
		values = function(C, H)
			local B = C.bounty
			return {min = B.bands[1].min, hold = B.maxActive, hour = H.hhmm(B.rollHour, 0), mult = B.typeMult.elite}
		end,
		who = {"Level {min}+. Alone or in a party: party members near you get the kills too.",
			"Nível {min}+. Sozinho ou em grupo: os colegas por perto também contam as mortes."},
		levels = {"Contracts name monsters close to your level. You also see the bands next to yours.",
			"Os contratos pedem monstros perto do seu nível. Você também vê as faixas vizinhas à sua."},
		drops = {"Gold in the bank, orbs and experience when you finish. Elite and boss contracts pay x{mult}.",
			"Ouro no banco, orbes e experiência quando você termina. Contratos de elite e de chefe pagam x{mult}."},
		death = {"{gentle}", "{gentle}"},
		often = {"New contracts every day at {hour}. You can hold {hold} at once. There is a weekly prize too.",
			"Contratos novos todo dia às {hour}. Você pode ter {hold} ao mesmo tempo. Também há um prêmio semanal."}},

	{key = "daily", title = {"Daily Reward", "Recompensa Diária"}, window = "game_daily",
		values = function(C, H)
			local days = {}
			for _, m in ipairs(C.daily.milestones) do
				days[#days + 1] = m.days
			end
			return {days = table.concat(days, ", "), ge = C.daily.graceEvery, gm = C.daily.graceMax}
		end,
		who = {"Every player. One reward a day for the whole account: all your characters share it.",
			"Todo jogador. Uma recompensa por dia para a conta inteira: todos os seus personagens dividem."},
		drops = {"Seven daily rewards in a loop. Streak prizes (orbs) at {days} days in a row.",
			"Sete recompensas diárias em ciclo. Prêmios de sequência (orbes) com {days} dias seguidos."},
		often = {"Once a day. Miss a day and the streak breaks, unless you have a grace charge: you earn one every {ge} days (up to {gm}).",
			"Uma vez por dia. Se faltar um dia, a sequência quebra, a menos que você tenha uma carga de graça: você ganha uma a cada {ge} dias (até {gm})."}},

	{key = "weeklychest", title = {"Weekly Chest", "Baú Semanal"}, window = "game_weeklychest",
		values = function(C, H)
			local W = C.weeklychest
			return {need = W.need, total = #W.activities, minNeed = W.minNeed, hour = H.hhmm(W.resetHour, 0)}
		end,
		who = {"Every player. Six activities count: a dungeon, a rift, a waystone run, an Infinity Tower floor, a world boss or invasion, and a bounty contract. Ones you have not unlocked are skipped.",
			"Todo jogador. Seis atividades contam: uma masmorra, uma fenda, uma corrida de waystone, um andar da Infinity Tower, um chefe mundial ou invasão, e um contrato de bounty. As que você ainda não liberou são ignoradas."},
		drops = {"Gold (about an hour of hunting) and orbs. Do every activity you have unlocked for a bonus roll.",
			"Ouro (cerca de uma hora de caça) e orbes. Faça todas as atividades liberadas para ganhar um sorteio extra."},
		often = {"Once a week, new every Monday at {hour}. Do {need} of the {total} activities to open it (fewer if some are locked, never under {minNeed}).",
			"Uma vez por semana, novo toda segunda às {hour}. Faça {need} das {total} atividades para abrir (menos se algumas estiverem bloqueadas, nunca abaixo de {minNeed})."}},

	{key = "embercache", title = {"Ember Cache", "Ember Cache"}, window = "game_embercache",
		values = function(C, H)
			local E = C.embercache
			return {goal = E.daily.goal, bonus = E.daily.bonusPoints, t1 = E.tiers[1].points, t2 = E.tiers[2].points,
				t3 = E.tiers[3].points, hour = H.hhmm(E.resetHour, 0)}
		end,
		who = {"Every player. Any activity gives Ember points: hunting, dungeons, rifts, bounties, bosses, crafting and more.",
			"Todo jogador. Qualquer atividade dá pontos de Ember: caça, masmorras, fendas, bounties, chefes, criação e mais."},
		drops = {"Daily Spark: a small reward when you earn {goal} points in a day (the first {bonus} count double). Weekly cache: gold and orbs at {t1}, {t2} and {t3} points.",
			"Daily Spark: uma recompensa pequena ao ganhar {goal} pontos no dia (os primeiros {bonus} valem em dobro). Cache semanal: ouro e orbes com {t1}, {t2} e {t3} pontos."},
		often = {"The day and the week turn at {hour} (the week on Monday).",
			"O dia e a semana viram às {hour} (a semana na segunda)."}},

	{key = "season", title = {"Seasons", "Temporadas"}, window = "game_season",
		values = function(C, H)
			local S = C.season.seasons[1]
			return {maxLvl = C.season.join.maxLevel, name = S.name, start = H.date(S.start), finish = H.date(S.finish),
				xp = H.round((S.modifier.expMult - 1) * 100)}
		end,
		who = {"Only a new character of level {maxLvl} or less can join, with the Join button. It starts from nothing: items and bank are wiped. Season characters play apart from the normal ones.",
			"Só um personagem novo de nível {maxLvl} ou menos pode entrar, com o botão Entrar. Ele começa do zero: itens e banco são apagados. Personagens de temporada jogam separados dos normais."},
		drops = {"A reward track, rankings and season titles. {name}: +{xp}% experience from monsters.",
			"Uma trilha de recompensas, rankings e títulos da temporada. {name}: +{xp}% de experiência dos monstros."},
		death = {"Normal season characters follow the normal death rules. In Hardcore mode you have one life.",
			"Personagens de temporada normais seguem as regras normais de morte. No modo Hardcore você tem uma vida."},
		often = {"{name} runs from {start} to {finish}. Only one season runs at a time.",
			"{name} vai de {start} a {finish}. Só uma temporada roda por vez."}},

	{key = "factions", title = {"Factions", "Facções"}, window = "game_factions", goals = {"trusted", "honored", "revered", "exalted"},
		values = function(C, H)
			local F = C.factions
			return {band1 = F.daily.bands[1].upTo, cap = F.weeklyCap, dc = F.contracts.daily, wc = F.contracts.weekly,
				hour = H.hhmm(F.dayHour, 0)}
		end,
		who = {"Every player. Nothing is locked: even a Hostile faction still talks and trades.",
			"Todo jogador. Nada fica trancado: até uma facção Hostil ainda fala e negocia."},
		drops = {"Ranks unlock gear, orb bundles and titles at the faction's quartermaster.",
			"Os postos liberam equipamento, pacotes de orbes e títulos com o intendente da facção."},
		often = {"Kills, rifts, bosses and more give reputation, less after {band1} a day, and at most {cap} per faction per week. Each faction has {dc} daily and {wc} weekly contracts. The day turns at {hour}.",
			"Mortes, fendas, chefes e mais dão reputação, menos depois de {band1} por dia, e no máximo {cap} por facção por semana. Cada facção tem {dc} contratos diários e {wc} semanal. O dia vira às {hour}."}},

	{key = "gamble", title = {"The Gambler", "O Apostador"}, window = "game_gamble",
		values = function(C, H)
			return {hours = C.gamble.refresh.hours, size = C.gamble.stock.size}
		end,
		who = {"Every player. The Gambler sells sealed gear for gold. You see how rare it is only after you buy it.",
			"Todo jogador. O Apostador vende equipamento lacrado por ouro. Você só vê a raridade depois de comprar."},
		drops = {"One piece of gear for your level and class.", "Uma peça de equipamento para o seu nível e a sua classe."},
		often = {"The stock is new every {hours} hours, {size} pieces each time. You can buy an early refresh.",
			"O estoque renova a cada {hours} horas, com {size} peças. Você pode comprar uma renovação antecipada."}},

	{key = "goals", title = {"Next Goals", "Próximas Metas"}, window = "game_goals",
		who = {"Every player. It shows the goals of your level, the gear to look for, where to hunt and what unlocks next.",
			"Todo jogador. Mostra as metas do seu nível, o equipamento para procurar, onde caçar e o que libera em seguida."},
		drops = {"Most goals give a reward when you finish them.", "A maioria das metas dá uma recompensa quando você termina."},
		often = {"New goals come as you level up. The tracker keeps the next ones on your screen.",
			"Metas novas chegam conforme você sobe de nível. O marcador deixa as próximas na tela."}},

	-- ---------------------------------------------------------------- the windows a new player opens (O331 follow-up)
	{key = "passive", title = {"Passive Tree", "Árvore Passiva"}, window = "game_passivetree", unlocks = {"passive"},
		goals = {"passive1"},
		values = function(C, H)
			local P = C.passive
			return {first = P.startLevel + P.levelsPerPoint, per = P.levelsPerPoint, free = C.respec.freeBelowLevel}
		end,
		what = {"A big tree of small bonuses. Start next to the centre and take nodes that touch the ones you have. Plan first, then press Apply Plan.",
			"Uma grande árvore de pequenos bônus. Comece perto do centro e pegue nós vizinhos aos que já tem. Planeje antes e depois clique em Aplicar plano."},
		who = {"Every player. Your first point comes at level {first}, then one more every {per} levels.",
			"Todo jogador. Seu primeiro ponto chega no nível {first}, depois mais um a cada {per} níveis."},
		often = {"Adding a node is free. Taking nodes back is free below level {free}; after that a single node or a full reset costs gold.",
			"Adicionar um nó é grátis. Tirar nós é grátis abaixo do nível {free}; depois disso um nó ou uma redistribuição total custa ouro."}},

	{key = "spellbook", title = {"Spellbook", "Livro de Magias"}, window = "game_spellbook", goals = {"spells25"},
		what = {"Every spell of the game: its words, level, mana, cooldown and the area it hits. Search by name or words, or show only your class.",
			"Todas as magias do jogo: palavras, nível, mana, recarga e a área que atinge. Busque pelo nome ou pelas palavras, ou mostre só a sua classe."},
		who = {"Every player. No spell needs premium.", "Todo jogador. Nenhuma magia pede premium."},
		often = {"New spells open as you level up; Available soon lists the next ones. A few line spells need a quest first: the spell names the teacher and the level.",
			"Magias novas abrem conforme você sobe de nível; Em breve mostra as próximas. Algumas magias de linha pedem uma quest antes: a magia mostra o mestre e o nível."}},

	{key = "bestiary", title = {"Bestiary", "Bestiário"}, window = "game_bestiary", goals = {"task1", "known25", "completed10"},
		values = function(C, H)
			local B = C.bestiary
			local lo, hi = math.huge, 0
			for _, d in ipairs(B.difficulties) do
				lo, hi = math.min(lo, d.bonus.damage), math.max(hi, d.bonus.damage)
			end
			return {stages = #B.stageNames, range = B.partyRange, bmin = lo, bmax = hi, rank = B.ranks[#B.ranks].exp,
				active = B.maxActive, daily = B.dailyLimit, weekly = B.weeklyLimit, hour = H.hhmm(B.rollHour, 0)}
		end,
		what = {"A book of every monster. Your kills fill its page in {stages} stages, and each stage shows more: health, weaknesses, where it lives, then the whole loot list.",
			"Um livro de todos os monstros. Suas mortes preenchem a página em {stages} etapas, e cada etapa mostra mais: vida, fraquezas, onde vive e depois todo o saque."},
		who = {"Every player. Party members within {range} squares of you count the kills too.",
			"Todo jogador. Colegas de grupo a até {range} quadrados de você também contam as mortes."},
		drops = {"A completed page gives +{bmin}% to +{bmax}% damage and experience against that monster. Bestiary points raise your rank, up to +{rank}% experience from every monster.",
			"Uma página completa dá +{bmin}% a +{bmax}% de dano e experiência contra aquele monstro. Pontos de bestiário sobem o seu posto, até +{rank}% de experiência de todos os monstros."},
		often = {"Kill Tasks (same window): hold {active} at once, finish up to {daily} a day and {weekly} a week. They pay gold, orbs, experience and bestiary points. The day turns at {hour}.",
			"Tarefas de Abate (mesma janela): tenha {active} ao mesmo tempo, conclua até {daily} por dia e {weekly} por semana. Pagam ouro, orbes, experiência e pontos de bestiário. O dia vira às {hour}."}},

	{key = "professions", title = {"Professions", "Profissões"}, window = "game_professions",
		values = function(C, H)
			local R = C.professions
			local names, en, pt = {}, {}, {}
			for i, p in ipairs(R.professions) do
				names[i] = p.name
			end
			for i, t in ipairs(R.tiers) do
				en[i] = t.name .. " (profession " .. t.profLevel .. ", level " .. t.charLevel .. ")"
				pt[i] = t.name .. " (profissão " .. t.profLevel .. ", nível " .. t.charLevel .. ")"
			end
			return {count = #R.professions, names = H.join(names), max = R.maxLevel, first = R.tiers[1].charLevel,
				tiers = {en = table.concat(en, ", "), pt = table.concat(pt, ", ")}, cap = R.bonus.cap,
				respawn = R.respawnMin, full = R.broker.fullPerDay, late = H.round(R.broker.lateMult * 100),
				top = R.broker.capPerDay}
		end,
		what = {"{count} gathering trades: {names}. Each has its own level, up to {max}. Ore veins and herb patches stand in the hunting grounds; flay beasts and reptiles you kill; fish in any water.",
			"{count} profissões de coleta: {names}. Cada uma tem o seu nível, até {max}. Veios de minério e moitas de ervas ficam nas áreas de caça; esfole feras e répteis que matar; pesque em qualquer água."},
		who = {"Every player from level {first}. You need the tool: a pick, a sickle, an obsidian knife or a fishing rod. The Material Broker next to the temple sells them.",
			"Todo jogador a partir do nível {first}. Você precisa da ferramenta: uma picareta, uma foice, uma faca de obsidiana ou uma vara de pesca. O Material Broker perto do templo vende."},
		levels = {"Better materials need a profession level and a character level: {tiers}.",
			"Materiais melhores pedem um nível de profissão e um nível de personagem: {tiers}."},
		drops = {"Materials to sell to the Material Broker or on the Market; they make no gear. Each profession level also adds a little monster experience, up to +{cap}% with all of them high.",
			"Materiais para vender ao Material Broker ou no Market; eles não fazem equipamento. Cada nível de profissão também soma um pouco de experiência dos monstros, até +{cap}% com todas altas."},
		often = {"A node is ready for you again {respawn} minutes after you use it, and nobody can take it from you. The broker pays full price for {full} of each material a day, then {late}% up to {top}.",
			"Um ponto de coleta fica pronto de novo para você {respawn} minutos depois de usar, e ninguém pode tirá-lo de você. O broker paga o preço cheio por {full} de cada material por dia, depois {late}% até {top}."}},

	{key = "charms", title = {"Charms", "Amuletos"}, window = "game_charms",
		values = function(C, H)
			local K = C.charms
			return {min = K.minLevel, cells = #K.unlocks[1].cells, next = K.unlocks[2].level, bounty = K.drops.bounty.chance,
				rift = K.drops.rift.minTier}
		end,
		what = {"A grid next to your gear. A charm is a small item with one or two bonuses: damage to a monster family, a resistance, gold or orb find, and more. Bigger charms take more cells.",
			"Uma grade ao lado do seu equipamento. Um amuleto é um item pequeno com um ou dois bônus: dano contra uma família de monstros, uma resistência, achar ouro ou orbes, e mais. Amuletos maiores ocupam mais casas."},
		who = {"Level {min}+. {cells} cells are open from the start; more open from level {next} and with an achievement.",
			"Nível {min}+. {cells} casas abrem desde o início; mais abrem a partir do nível {next} e com uma conquista."},
		drops = {"Bounty contracts ({bounty}% chance), invasions, dungeons, the Ember Descent and rifts of tier {rift} and up. A few are uniques with a special power. Salvage a charm into shards; shards reforge the values of another.",
			"Contratos de bounty ({bounty}% de chance), invasões, masmorras, o Ember Descent e fendas de nível {rift} para cima. Alguns são únicos com um poder especial. Recicle um amuleto em fragmentos; os fragmentos refazem os valores de outro."},
		often = {"A charm works only while it sits in an open cell. Place and move charms out of combat, as often as you like.",
			"Um amuleto só funciona numa casa aberta. Coloque e mova amuletos fora de combate, quantas vezes quiser."}},

	{key = "achievements", title = {"Achievements", "Conquistas"}, window = "game_achievements",
		values = function(C, H)
			local A = C.achievements
			local hidden = 0
			for _, a in ipairs(A.list) do
				if a.hidden then
					hidden = hidden + 1
				end
			end
			return {count = #A.list, groups = #A.categories, hidden = hidden}
		end,
		what = {"{count} achievements in {groups} groups, from leveling and monsters to bosses, rifts, crafting and PvP. {hidden} stay secret until you earn them.",
			"{count} conquistas em {groups} grupos, de subir de nível e monstros a chefes, fendas, criação e PvP. {hidden} ficam secretas até você conseguir."},
		who = {"Every player. Most unlock by themselves while you play.",
			"Todo jogador. A maioria libera sozinha enquanto você joga."},
		drops = {"Achievement points; many also give a title, gold, items, an outfit, a mount or a portal style. Finish every achievement of a group for its own title.",
			"Pontos de conquista; muitas também dão um título, ouro, itens, um traje, uma montaria ou um estilo de portal. Complete todas as conquistas de um grupo para ganhar o título dele."},
		often = {"Once each. Progress never goes back. Pick a title you earned in this window.",
			"Uma vez cada. O progresso nunca volta. Escolha um título que você ganhou nesta janela."}},

	{key = "loadouts", title = {"Loadouts", "Loadouts"}, window = "game_loadouts",
		values = function(C, H)
			local L = C.loadouts
			return {min = L.minLevel, base = L.baseSlots, l1 = L.earned[1].level, l2 = L.earned[2].level, pact = L.pactSlots,
				cast = L.castMs / 1000, cd = L.cooldownSeconds}
		end,
		what = {"Save your build and switch to another one: passive tree, Paragon points, the support runes of your spells and a set of gear.",
			"Salve a sua build e troque para outra: árvore passiva, pontos de Paragon, as runas de suporte das magias e um conjunto de equipamento."},
		who = {"Level {min}+. {base} slots, one more at level {l1} and at level {l2}, and {pact} more while the Chaos Pact runs.",
			"Nível {min}+. {base} espaços, mais um no nível {l1} e no nível {l2}, e mais {pact} enquanto o Chaos Pact estiver ativo."},
		often = {"A switch is free. Out of combat and never inside an instance: at once in a safe zone, elsewhere after {cast} seconds standing still. Then wait {cd} seconds for the next one.",
			"Trocar é grátis. Fora de combate e nunca dentro de uma instância: na hora numa zona segura, fora dela após {cast} segundos parado. Depois espere {cd} segundos para a próxima."}},

	{key = "townportal", title = {"Town Portal", "Portal da Cidade"}, window = "game_townportal",
		values = function(C, H)
			local T = C.townportal
			assert(T.partyCanUse, "the Town Portal card says the party may use the portals: townportal_config.lua partyCanUse is off")
			return {cast = T.castMs / 1000, cd = T.cooldownSeconds, mins = T.portalMinutes}
		end,
		what = {"Open a portal from the field to your temple. A return portal at the temple takes you back to the same spot.",
			"Abra um portal do campo até o seu templo. Um portal de volta no templo leva você ao mesmo lugar."},
		who = {"Every player. Your party may use your portals too.", "Todo jogador. O seu grupo também pode usar os seus portais."},
		drops = {"The styles of this window change only the look of the portal. They come from the store, achievements and the season pass.",
			"Os estilos desta janela mudam só a aparência do portal. Vêm da loja, de conquistas e do passe da temporada."},
		often = {"Casting takes {cast} seconds; moving or taking damage stops it. Then {cd} seconds of cooldown. The portals close after {mins} minutes, or when you walk back.",
			"Conjurar leva {cast} segundos; andar ou levar dano interrompe. Depois {cd} segundos de recarga. Os portais fecham após {mins} minutos, ou quando você volta por ele."}},

	{key = "stash", title = {"Supply Stash", "Supply Stash"}, window = "game_stash",
		values = function(C, H)
			local S, L = C.stash, C.pact.limits.stashSlots
			return {free = S.slots.free, per = S.slots.perPack, packs = L.maxExtra, pact = L.pact}
		end,
		what = {"Your item storage. All of one plain item fills one slot: a big stack of gold coins is a single entry.",
			"O seu depósito de itens. Tudo de um mesmo item simples ocupa um espaço: uma pilha enorme de moedas de ouro é uma entrada só."},
		who = {"Every player. Each character has its own stash; every character of the account gets the same room.",
			"Todo jogador. Cada personagem tem o seu stash; todos os personagens da conta têm o mesmo espaço."},
		often = {"{free} slots free. The store sells expansions of {per} slots (up to {packs}) and tabs that each hold one kind of item. The Chaos Pact lends {pact} expansion while it runs.",
			"{free} espaços grátis. A loja vende expansões de {per} espaços (até {packs}) e abas para um tipo de item cada. O Chaos Pact empresta {pact} expansão enquanto estiver ativo."}},

	{key = "autoloot", title = {"Auto Loot", "Auto Loot"}, window = "game_autoloot",
		values = function(C, H)
			return {free = C.autoloot.freeLimit, more = C.autoloot.premiumLimit}
		end,
		what = {"Items on your list go from the corpse into your backpack by themselves when you kill.",
			"Os itens da sua lista vão do corpo para a sua mochila sozinhos quando você mata."},
		who = {"Every player. Add an item by its name here, or right-click it and choose Add to Loot List.",
			"Todo jogador. Adicione um item pelo nome aqui, ou clique com o botão direito nele e escolha Add to Loot List."},
		often = {"{free} items on the list; premium time or the Chaos Pact raise it to {more}.",
			"{free} itens na lista; tempo premium ou o Chaos Pact sobem para {more}."}},

	{key = "lootfilter", title = {"Loot Filter", "Filtro de Saque"}, window = "game_lootfilter",
		values = function(C, H)
			return {hist = C.lootfilter.historySize}
		end,
		what = {"Choose which drops stand out: rarity, uniques, orbs and more. A matching drop gets a light beam over the corpse, a sound and a line in the loot feed.",
			"Escolha quais itens se destacam: raridade, únicos, orbes e mais. Um item escolhido ganha uma luz sobre o corpo, um som e uma linha no registro de saque."},
		who = {"Every player. Start from a preset, then change any rule.", "Todo jogador. Comece de um modelo e depois mude qualquer regra."},
		often = {"The loot feed keeps your last {hist} kills. Click an item there to loot it while the corpse is on your screen.",
			"O registro de saque guarda as suas últimas {hist} mortes. Clique num item ali para pegar enquanto o corpo está na sua tela."}},

	{key = "itemfinder", title = {"Item Finder", "Item Finder"}, window = "game_itemfinder",
		values = function(C, H)
			return {min = C.itemfinder.minQuery}
		end,
		what = {"Search any item and see where it comes from: monsters, chests and rewards, recipes, NPC shops, the store, the Gambler and gathering. It also shows who buys it and what uses it.",
			"Busque qualquer item e veja de onde ele vem: monstros, baús e recompensas, receitas, lojas de NPC, a loja, o Apostador e a coleta. Também mostra quem compra e onde ele é usado."},
		who = {"Every player. Type at least {min} letters of the name.", "Todo jogador. Digite pelo menos {min} letras do nome."}},

	{key = "codex", title = {"Codex", "Códex"}, window = "game_codex",
		what = {"The book of the item system: modifiers, powers, orbs, gems, uniques, sets, rifts, supports, materials, the basics and the lore.",
			"O livro do sistema de itens: modificadores, poderes, orbes, gemas, únicos, conjuntos, fendas, suportes, materiais, o básico e a história."},
		who = {"Every player. Search with any word, then use the filters of the tab. Where to find opens the Item Finder.",
			"Todo jogador. Busque com qualquer palavra e depois use os filtros da aba. Onde achar abre o Item Finder."}},

	{key = "partyfinder", title = {"Party Finder", "Procurar Grupo"}, window = "game_partyfinder",
		values = function(C, H)
			local F = C.partyfinder
			local names = {}
			for _, a in ipairs(F.activities) do
				if not a.title then
					names[#names + 1] = a.name
				end
			end
			return {acts = H.join(names), emin = F.expiryMinutes[1], emax = F.expiryMinutes[#F.expiryMinutes],
				apps = F.maxApplications}
		end,
		what = {"Find a group, or players for yours: post what you want to do and the roles you need (tank, healer, damage), or apply to a listing.",
			"Ache um grupo, ou jogadores para o seu: anuncie o que quer fazer e as funções que precisa (tank, healer, dano), ou candidate-se a um anúncio."},
		who = {"Every player. Activities: {acts}, or anything else.",
			"Todo jogador. Atividades: {acts}, ou qualquer outra coisa."},
		often = {"A listing closes by itself after {emin} to {emax} minutes, as you choose. You can have {apps} applications open at once.",
			"Um anúncio fecha sozinho após {emin} a {emax} minutos, como você escolher. Você pode ter {apps} candidaturas abertas ao mesmo tempo."}},

	{key = "mentor", title = {"Mentors", "Mentores"}, window = "game_mentor",
		values = function(C, H)
			local M = C.mentor
			return {exp = H.round(M.bonus.exp * 100), dmg = H.round(M.bonus.damageTaken * 100), amax = M.apprentice.maxLevel,
				adays = M.apprentice.maxAccountDays, mlvl = M.mentor.minAccountLevel, hours = M.mentor.minOnlineHours,
				mdays = M.mentor.minAccountDays, maxA = M.mentor.maxApprentices, grad = M.graduationLevel,
				hp = M.graduation.items[1].count, mp = M.graduation.items[2].count}
		end,
		what = {"A veteran helps a new player. While they hunt together, the apprentice gets +{exp}% experience and {dmg}% less damage from monsters.",
			"Um veterano ajuda um jogador novo. Enquanto caçam juntos, o aprendiz ganha +{exp}% de experiência e {dmg}% menos dano dos monstros."},
		who = {"Apprentice: a character of level {amax} or less, on an account up to {adays} days old. Mentor: an account with a level {mlvl} character, {hours} hours played and {mdays} days of age.",
			"Aprendiz: um personagem de nível {amax} ou menos, numa conta de até {adays} dias. Mentor: uma conta com um personagem nível {mlvl}, {hours} horas jogadas e {mdays} dias de idade."},
		drops = {"Milestones (levels, a first rift, dungeon, bounty contract and world boss) give the mentor Mentor Marks for titles, looks and supplies. At level {grad} the apprentice graduates and gets {hp} health and {mp} mana potions.",
			"Marcos (níveis, a primeira fenda, masmorra, contrato de bounty e chefe mundial) dão ao mentor Mentor Marks para títulos, visuais e suprimentos. No nível {grad} o aprendiz se forma e ganha {hp} poções de vida e {mp} de mana."},
		often = {"A mentor has up to {maxA} apprentices at once. The bonus works only near each other, with the mentor's character close to the apprentice's level.",
			"Um mentor tem até {maxA} aprendizes ao mesmo tempo. O bônus só funciona perto um do outro, com o personagem do mentor perto do nível do aprendiz."}},

	{key = "guild", title = {"Guild", "Guilda"}, window = "game_guild",
		values = function(C, H)
			local G = C.guild
			local hall
			for _, p in ipairs(G.perks) do
				if p.hall then
					hall = hall or p.level
				end
			end
			return {max = G.maxLevel, xp = G.caps.xp, loot = G.caps.loot, hall = assert(hall, "no guild hall perk"),
				cap = G.sources.dailyCapAll}
		end,
		what = {"Your guild gains guild levels (up to {max}) from what its members do: experience, bounty contracts, rifts, world bosses, invasions and sieges.",
			"A sua guilda ganha níveis de guilda (até {max}) com o que os membros fazem: experiência, contratos de bounty, fendas, chefes mundiais, invasões e cercos."},
		who = {"Every member of a guild.", "Todo membro de uma guilda."},
		drops = {"Guild levels give every member perks: up to +{xp}% experience and +{loot}% loot, cheaper respecs and more depot room. At guild level {hall} the guild gets its own guild hall.",
			"Os níveis da guilda dão vantagens a todos os membros: até +{xp}% de experiência e +{loot}% de saque, redistribuição mais barata e mais espaço no depósito. No nível {hall} a guilda ganha o seu salão."},
		often = {"Each member adds at most {cap} guild XP a day.", "Cada membro soma no máximo {cap} de XP de guilda por dia."}},

	{key = "seasonpass", title = {"Season Pass", "Passe da Temporada"}, window = "game_battlepass",
		values = function(C, H)
			local S = C.seasonpass
			return {tiers = S.maxTier, bank = S.bankDays, grace = S.claimGraceDays}
		end,
		what = {"A reward track of {tiers} tiers. Pass XP from play fills it.",
			"Uma trilha de recompensas com {tiers} níveis. A XP do passe, ganha jogando, enche a trilha."},
		who = {"Every player. The pass counts for the whole account, season and normal characters alike, and starts from zero each season.",
			"Todo jogador. O passe vale para a conta inteira, personagens de temporada e normais, e começa do zero a cada temporada."},
		drops = {"A free track of gold and potions, and a premium track (sold in the store) with Chaos Coins, titles, outfits and other looks. Looks are yours forever.",
			"Uma trilha grátis de ouro e poções, e uma trilha premium (vendida na loja) com Chaos Coins, títulos, trajes e outros visuais. Os visuais ficam com você para sempre."},
		often = {"Pass XP comes from experience, bosses, bounty contracts, rifts, treasure goblins and invasions, each with a daily cap; the caps of {bank} days add up, so a missed day can be caught up. Daily and weekly challenges give more. Claim rewards up to {grace} days after the season ends.",
			"A XP do passe vem de experiência, chefes, contratos de bounty, fendas, treasure goblins e invasões, cada um com limite diário; os limites de {bank} dias se somam, então um dia perdido pode ser recuperado. Desafios diários e semanais dão mais. Pegue as recompensas até {grace} dias depois do fim da temporada."}},

	{key = "hideout", title = {"Hideout", "Esconderijo"}, window = "game_hideout",
		values = function(C, H)
			return {likes = C.hideout.likes.perDay}
		end,
		what = {"Your own room, with your depot, the supply stash, exercise dummies and a waystone device. Decorations change only its look.",
			"A sua própria sala, com o seu depósito, o supply stash, bonecos de treino e um dispositivo de waystone. As decorações mudam só a aparência."},
		who = {"Every character has one. Enter through the Hideout Portal of any town.",
			"Todo personagem tem um. Entre pelo Hideout Portal de qualquer cidade."},
		drops = {"Decorations come from achievements, boss kills, factions, the Ember Descent and the store.",
			"As decorações vêm de conquistas, chefes mortos, facções, do Ember Descent e da loja."},
		often = {"Go any time. Choose who may visit: only you, friends, your guild or everyone. You can like {likes} hideouts of others a day.",
			"Vá quando quiser. Escolha quem pode visitar: só você, amigos, a sua guilda ou todos. Você pode curtir {likes} esconderijos de outros por dia."}},

	{key = "transmog", title = {"Transmog", "Transmog"}, window = "game_transmog",
		values = function(C, H)
			local F = C.transmog.fee
			assert(F.remove == 0, "the Transmog card says taking a look off is free: transmog_config.lua fee.remove is not 0")
			return {fee = H.big(F.apply), per = F.perItemLevel, max = H.big(F.maxApply)}
		end,
		what = {"Make a worn item look like another item of the same kind. Only the look changes; the stats stay the item's own.",
			"Faça um item equipado parecer outro item do mesmo tipo. Só a aparência muda; os atributos continuam os do item."},
		who = {"Every player. Looks are saved for the whole account: carry or wear an item once to learn its look.",
			"Todo jogador. As aparências ficam salvas para a conta inteira: carregue ou use um item uma vez para aprender a aparência."},
		often = {"A look costs {fee} gold plus {per} per item level, {max} at most. Taking it off is free.",
			"Uma aparência custa {fee} de ouro mais {per} por nível do item, no máximo {max}. Tirar é grátis."}},

	{key = "nemesis", title = {"Nemesis", "Nêmesis"}, window = "game_nemesis",
		values = function(C, H)
			local N = C.nemesis
			return {min = N.birth.minLevel, chance = N.birth.chance, max = N.birth.maxPerPlayer, xp = N.stats.xpMult,
				appear = N.appear.chance, cd = N.appear.cooldownSeconds / 60, life = N.appear.lifetimeSeconds / 60,
				days = N.expireDays}
		end,
		what = {"A monster that kills you may become your Nemesis: stronger, with special traits, and it comes back to hunt you.",
			"Um monstro que mata você pode virar o seu Nêmesis: mais forte, com traços especiais, e ele volta para caçar você."},
		who = {"Level {min}+. Each death to a normal monster outside instances has a {chance}% chance. You have at most {max} at a time.",
			"Nível {min}+. Cada morte para um monstro comum fora de instâncias tem {chance}% de chance. Você tem no máximo {max} por vez."},
		drops = {"It gives x{xp} experience. Slay your own Nemesis for gold and a trophy; slaying another player's pays a bounty.",
			"Ele dá x{xp} de experiência. Mate o seu Nêmesis por ouro e um troféu; matar o de outro jogador paga uma recompensa."},
		death = {"{gentle}", "{gentle}"},
		often = {"While you hunt, each kill of its kind or of a monster near its level has a {appear}% chance to call it, at most once in {cd} minutes. It leaves after {life} minutes. Unseen for {days} days, it is gone.",
			"Enquanto você caça, cada morte do mesmo tipo ou de um monstro perto do nível dele tem {appear}% de chance de chamá-lo, no máximo uma vez a cada {cd} minutos. Ele vai embora após {life} minutos. Sem aparecer por {days} dias, some."}},

	{key = "pact", title = {"Chaos Pact", "Chaos Pact"}, window = "game_pact",
		values = function(C, H)
			local P, K = C.pact.pact, C.pact.perks
			return {days = P.days, xp = H.round(K.expBonus * 100), stam = K.staminaRegen, marks = P.dailyMarks}
		end,
		what = {"The server's monthly membership, bought with Chaos Coins: comfort and looks.",
			"A assinatura mensal do servidor, comprada com Chaos Coins: conforto e visuais."},
		who = {"Every account. One purchase gives {days} days; more purchases add time. The experience bonus does not reach season characters.",
			"Toda conta. Uma compra dá {days} dias; mais compras somam tempo. O bônus de experiência não vale para personagens de temporada."},
		drops = {"While it runs: +{xp}% experience from monsters, stamina comes back x{stam} faster, more storage and room, and {marks} Pact Marks a day for looks.",
			"Enquanto estiver ativo: +{xp}% de experiência dos monstros, a stamina volta x{stam} mais rápido, mais espaço e depósito, e {marks} Pact Marks por dia para visuais."},
		often = {"Claim the Marks in this window once a day while the Pact runs; a missed day is not paid later.",
			"Pegue as Marks nesta janela uma vez por dia enquanto o Pact estiver ativo; um dia perdido não é pago depois."}},

	{key = "shop", title = {"Store", "Loja"}, window = "game_shop",
		what = {"The Chaos store. Prices are in Chaos Coins, kept for the whole account.",
			"A loja do Chaos. Os preços são em Chaos Coins, guardadas para a conta inteira."},
		who = {"Every player. Buy coins with the coin packs. Many offers can be sent to a friend as a gift.",
			"Todo jogador. Compre moedas com os pacotes de moedas. Muitas ofertas podem ser enviadas de presente a um amigo."},
		drops = {"Looks (outfits, mounts, wings, auras, portal styles), more storage room, services such as a name change, and comfort items.",
			"Visuais (trajes, montarias, asas, auras, estilos de portal), mais espaço de depósito, serviços como troca de nome, e itens de conforto."}}
}

-- windows of the unlock entries that have no card of their own above (the generator makes a card from the unlock entry)
-- key of the unlock entry -> client module whose window gets the "?" button
P.unlockWindows = {crafting = "game_crafting", salvage = "game_crafting", pets = "game_pets", market = "game_market"}

return P
