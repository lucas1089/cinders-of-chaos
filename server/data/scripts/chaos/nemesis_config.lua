-- nemesis_config.lua: every number and text of the Nemesis system (nemesis.lua, nemesis_core.lua; client game_nemesis).
-- Plain table, loaded as ChaosNemesisConfig = dofile("data/scripts/chaos/nemesis_config.lua").
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then /reload scripts (or restart). See server/README.md "Nemesis".
return {
	enabled = true,
	opcode = 163, -- ChaosOpcodes.nemesis (chaos_constants.lua; server/README.md "Opcode collision check")
	table = "chaos_nemesis", -- Chaos.tables.nemesis (server/sql/chaos_nemesis.sql; nemesis.lua creates it when missing)
	-- player storages 7102300 - 7102309 (Chaos.storage.nemesis): +0 nemeses avenged, +1 nemeses of others slain,
	-- +2 os.time of the last hunter bounty, +3 os.time of the last avenge loot bonus, +4 os.time this character's last
	-- nemesis ended (slain or expired: the birth cooldown), +5 trophies received
	storage = 7102300,
	rateLimitMs = 1000, -- client requests ("get") per character

	-- ------------------------------------------------------------------ birth
	-- A regular monster (no boss, summon, treasure goblin, renamed event / instance monster, nobody's nemesis) that
	-- kills a character of at least minLevel outside every instance may become that character's nemesis.
	birth = {
		chance = 25, -- percent per qualifying death
		minLevel = 50,
		maxPerPlayer = 1, -- active nemeses per character
		softCap = 200, -- active nemeses server-wide: above this the chance falls linearly ...
		serverCap = 300, -- ... to 0 here (hard cap)
		cooldownSeconds = 6 * 3600, -- no new nemesis this long after the character's last one ended (anti-farm)
		minMonsterHealth = 100, -- critters never
		skipNames = {} -- lowercase monster type names that never become a nemesis
	},

	-- ------------------------------------------------------------------ level and growth
	-- base level = the killer's level (ChaosLoot.monsterLevel; else its max health / healthPerLevel). The nemesis
	-- starts bumpMin..bumpMax percent above it; every further kill of its victim adds growthPct of the base, up to
	-- maxKills kills (the epithet changes with the kills, the second trait comes with the second kill).
	level = {bumpMin = 10, bumpMax = 20, growthPct = 10, maxKills = 4, min = 1, max = 1500, healthPerLevel = 20},
	stats = {
		-- owner 2026-10-18 ("Nemesis has too much health and hits too hard"): was health x3.0, damage x1.3, xp x4.0.
		-- Now about 1.7x the type's health at birth (x1.5 x the +10-20% level), a Magic tier hit, so a kill takes
		-- roughly half as long as before; xp follows the health so it is not a better farm than before.
		healthMult = 1.5, -- the type's max health x this x (level / base level)
		damageMult = 1.0, -- damage dealt (monster_tiers.lua hit handler, tier "nemesis")
		xpMult = 2.5, -- experience (monster_tiers.lua experience callback, tier "nemesis")
		speed = 20 -- speed added
	},

	-- ------------------------------------------------------------------ look (no new sprite)
	-- outfit shader 23 = chaos_blood_pulse "Heartblood" (cosmetics_config.lua outfitShaders, data/XML/shaders.xml), a
	-- black skull over the head and a death effect when it appears. The monster bar labels the tier "Nemesis".
	look = {shader = 23, skull = "SKULL_BLACK", appearEffect = "CONST_ME_MORTAREA", pulseEffect = "CONST_ME_MAGIC_RED"},

	-- ------------------------------------------------------------------ traits
	-- One at birth, a second at the second kill (maxTraits). `mod` = the monster_tiers.lua modifier whose hooks do the
	-- work (damage, reflect, regeneration); `speed` is added on top; stalker is nemesis.lua's own.
	maxTraits = 2,
	traits = {
		{key = "vengeful", name = "Vengeful", pt = "Vingativo", mod = "berserker", weight = 25,
			desc = "Hits 50% harder below half health.", descPt = "Bate 50% mais forte abaixo de metade da vida."},
		{key = "swift", name = "Swift", pt = "Veloz", mod = "swift", weight = 20,
			desc = "Much faster.", descPt = "Muito mais rápido."},
		{key = "thorned", name = "Thorned", pt = "Espinhoso", mod = "reflective", weight = 20,
			desc = "Reflects 15% of the damage it takes.", descPt = "Reflete 15% do dano que recebe."},
		{key = "regenerating", name = "Regenerating", pt = "Regenerante", mod = "regenerating", weight = 20,
			desc = "Heals 2% of its health every few seconds.", descPt = "Cura 2% da vida a cada poucos segundos."},
		{key = "stalker", name = "Stalker", pt = "Espreitador", speed = 20, weight = 15,
			desc = "Steps out of the shadows next to its victim.", descPt = "Surge das sombras ao lado da vítima."}
	},

	-- ------------------------------------------------------------------ appearing
	-- Only for its victim: a kill of the victim (the kill event is registered only on characters with a nemesis) of
	-- the same monster type, or of a monster within bandPct of the nemesis's base level, rolls `chance` percent. A
	-- warning first, the nemesis delayMs later, 3-6 tiles away. It vanishes after lifetimeSeconds, when its victim
	-- logs out or leaves the floor, and comes back another time. Never inside an instance or a protection zone.
	appear = {
		chance = 4,
		bandPct = 25,
		cooldownSeconds = 1800, -- per victim, between two appearances (was 900: in a pack farm it showed every time)
		delayMs = 3000,
		lifetimeSeconds = 300,
		minDistance = 3,
		maxDistance = 6,
		tickMs = 2000, -- regeneration, stalker and lifetime step
		stalkerRange = 7, -- the stalker steps next to its victim when farther than this (same floor, in view)
		stalkerEveryMs = 8000,
		leashRange = 30 -- farther than this from its victim (or another floor): it vanishes
	},

	-- ------------------------------------------------------------------ rewards
	-- The victim slays it: the trophy (once per nemesis; the nemesis is gone after), the title, the loot bonus
	-- (gold in the corpse, once per avengeCooldownSeconds). Someone else of the victim's party slays it: the bounty
	-- to the bank (once per bounty.cooldownSeconds, never for the victim's account or connection, never for a nemesis
	-- younger than minAgeSeconds) and a notice to the victim. A Hardcore character gets the trophy only.
	rewards = {
		trophy = {id = 7393, name = "nemesis trophy", article = "a", -- a stock hunting trophy (no new art)
			ownerAttr = "chaos_nemesis_owner", nameAttr = "chaos_nemesis_name", storebound = "chaos_storebound",
			lock = "chaos_locked"},
		avenge = {goldBase = 5000, goldPerLevel = 150, cooldownSeconds = 20 * 3600},
		bounty = {goldBase = 10000, goldPerLevel = 200, cooldownSeconds = 6 * 3600, minAgeSeconds = 600},
		hardcoreTrophyOnly = true,
		titles = {avenger = "Avenger of Self", hunter = "Nemesis Hunter", hunterMin = 3, color = "#c0392b"},
		-- achievements.lua stats fed (ChaosAchievements.progress): the achievements themselves are a hook (README)
		stats = {born = "nemesis_marked", avenged = "nemesis_avenged", hunted = "nemesis_hunted"},
		-- optional leaderboard (ChaosLeaderboard.record, only once Chaos.leaderboardConfig lists the board)
		leaderboard = {board = "nemesis", mode = "add"}
	},

	-- ------------------------------------------------------------------ expiry
	expireDays = 14, -- a nemesis not seen (born, grown, appeared) for this long is gone

	-- ------------------------------------------------------------------ names
	-- name = prefix .. middle .. suffix ("Varkh", "Morath"); the shown name adds the epithet of the kills. A shown
	-- name longer than maxShown characters drops the epithet's victim part.
	names = {
		prefixes = {"Var", "Mor", "Kra", "Zul", "Ash", "Gor", "Vex", "Thar", "Ul", "Drak", "Skor", "Nyx", "Bel", "Rhaz",
			"Ost", "Grim", "Vol", "Karn", "Sab", "Hex"},
		middles = {"", "", "a", "o", "u", "e", "i"},
		suffixes = {"kh", "rath", "gul", "mok", "zar", "th", "dren", "vas", "rok", "nash", "x", "gor", "mael", "dun"},
		maxShown = 40
	},
	-- epithet by kills (1, 2, 3, 4 and more); %s = the victim's name
	epithets = {
		en = {"Bane of %s", "Twice-Slayer of %s", "Thrice-Slayer of %s", "Doom of %s"},
		pt = {"Flagelo de %s", "Duas Vezes Algoz de %s", "Três Vezes Algoz de %s", "Ruína de %s"}
	},
	-- the shown monster name is one string for every viewer, so it is always in this language
	nameLang = "en",

	-- ------------------------------------------------------------------ texts (en and pt-BR, UTF-8)
	-- The localization helper (Chaos.t, i18n_core.lua) takes the English texts as its keys: its i18n_strings.lua
	-- "pt-BR" table can take these pairs as they are; until it has them, a pt-BR player (Chaos.lang) reads `pt` here.
	texts = {
		en = {
			born = "%s marked you. A Nemesis is born: %s.",
			grown = "%s grows stronger on your death: %s.",
			warning = "You feel a familiar hatred watching you...",
			appear = "%s has found you!",
			vanish = "%s fades back into the shadows. It will return.",
			avenged = "You slew %s. Your Nemesis is no more.",
			trophy = "You receive a trophy engraved with its name.",
			trophyLost = "Your backpack and inbox are full: no trophy.",
			lootBonus = "Its hoard spills into the corpse.",
			hunted = "%s slew %s and claims the Nemesis Hunter bounty of %d gold.",
			huntedVictim = "%s slew your Nemesis, %s.",
			noBounty = "No bounty for this Nemesis.",
			expired = "Your Nemesis, %s, lost your trail.",
			trophyDesc = "Engraved: %s, slain by %s."
		},
		pt = {
			born = "%s marcou você. Nasce um Nemesis: %s.",
			grown = "%s fica mais forte com a sua morte: %s.",
			warning = "Você sente um ódio familiar observando você...",
			appear = "%s encontrou você!",
			vanish = "%s volta para as sombras. Ele vai voltar.",
			avenged = "Você matou %s. Seu Nemesis não existe mais.",
			trophy = "Você recebe um troféu com o nome dele gravado.",
			trophyLost = "Sua mochila e sua caixa de entrada estão cheias: sem troféu.",
			lootBonus = "O tesouro dele cai no corpo.",
			hunted = "%s matou %s e recebe a recompensa de Caçador de Nemesis: %d de ouro.",
			huntedVictim = "%s matou o seu Nemesis, %s.",
			noBounty = "Sem recompensa por este Nemesis.",
			expired = "Seu Nemesis, %s, perdeu o seu rastro.",
			trophyDesc = "Gravado: %s, morto por %s."
		}
	}
}
