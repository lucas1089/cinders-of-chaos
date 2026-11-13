-- The pt-BR script of the main quest (O551): docs/ROTEIRO_QUEST_PRINCIPAL.md, generated from mainquest_config.lua, so the
-- script the owner reads is the text the game says. usage (from server/): luajit tools/gen_mainquest_script.lua [--check]
-- Lua 5.1 / LuaJIT and 5.3.
local cfg = dofile("data/scripts/chaos/mainquest_config.lua")
local OUT = "../docs/ROTEIRO_QUEST_PRINCIPAL.md"

local o = {}
local function w(s)
	o[#o + 1] = s or ""
end

local function objective(step)
	local parts = {}
	for _, c in ipairs(step.conds) do
		if c.c == "count" then
			local list = table.concat(c.mons, ", ")
			if c.item then
				parts[#parts + 1] = string.format("Colete %d %s dos monstros (%s).", c.target, c.item.pt, list)
			else
				parts[#parts + 1] = string.format("Mate %d (%s).", c.target, list)
			end
		elseif c.c == "visit" then
			parts[#parts + 1] = string.format("Chegue a %s (marca no mapa).", c.label)
		elseif c.c == "talk" then
			parts[#parts + 1] = "Fale com a Guardiã Ysolde e diga \"juramento\"."
		elseif c.c == "boss" then
			parts[#parts + 1] = "Vença Vael Ashmourn sozinho, na Câmara do Juramento."
		elseif c.c == "resist" then
			parts[#parts + 1] = c.mode == "prepare" and "Suba as quatro resistências até a meta." or "Mantenha as quatro resistências sem valor negativo."
		end
	end
	return #parts > 0 and table.concat(parts, " ") or step.title.pt
end

w("# Roteiro da Quest Principal: O Juramento da Brasa")
w()
w("Gerado de `server/data/scripts/chaos/mainquest_config.lua` por `server/tools/gen_mainquest_script.lua`. Não edite aqui: o texto do jogo é o deste arquivo.")
w("Trechos entre chaves, como {m1} ou {p1}, são preenchidos em tempo de execução com os números das configurações do servidor.")
w()
w("## Premissa")
w()
w("As Brasas levaram os Guardiões da Vigília Cinzenta um a um. Quem sai vivo do templo de Cinderhold é chamado de nascido das brasas, e a Guardiã Ysolde, no mercado da sala de teleportes, oferece a esses sobreviventes o Juramento: uma caminhada pelo reino, um voto de cada vez. A última página do Juramento é uma porta, e atrás dela espera Vael Ashmourn, o primeiro Guardião, que se recusou a jurar.")
w()
w(string.format("São %d etapas em %d capítulos, do nível %d ao 500, mais um epílogo. Metade ou mais das etapas é caçar, coletar, explorar ou entregar.", #cfg.steps, #cfg.chapters - 1, cfg.startLevel))
w()
for _, ch in ipairs(cfg.chapters) do
	w(string.format("## Capítulo %d: %s (níveis %d a %d)", ch.n, ch.name.pt, ch.from, ch.to))
	w()
	w("*Abertura:* " .. ch.intro.pt)
	w()
	if ch.n < 8 then
		local n = 0
		for _, s in ipairs(cfg.steps) do
			if s.ch == ch.n then
				n = n + 1
				w(string.format("### %d.%d %s (nível %d)", ch.n, n, s.title.pt, s.level))
				w()
				w("- Objetivo: " .. objective(s))
				w("- Dica: " .. s.hint.pt)
				w("- Conclusão (Ysolde): " .. s.done.pt)
				w()
			end
		end
	else
		for _, e in ipairs(cfg.epilogue) do
			w(string.format("### %s (a partir do nível %d)", e.title.pt, e.level))
			w()
			w(e.text.pt)
			w()
		end
	end
end
w("## Falas da Guardiã Ysolde")
w()
local keys = {}
for k in pairs(cfg.ysolde) do
	keys[#keys + 1] = k
end
table.sort(keys)
for _, k in ipairs(keys) do
	w("- **" .. k .. "**: " .. cfg.ysolde[k].pt)
end
w()
w("## Falas de Vael Ashmourn")
w()
keys = {}
for k in pairs(cfg.vael) do
	keys[#keys + 1] = k
end
table.sort(keys)
for _, k in ipairs(keys) do
	w("- **" .. k .. "**: " .. cfg.vael[k].pt)
end
w()
w("## Fim do Juramento")
w()
w(cfg.texts.finished.pt)
local text = table.concat(o, "\n") .. "\n"

if arg and arg[1] == "--check" then
	local f = io.open(OUT, "rb")
	local have = f and f:read("*a")
	if f then f:close() end
	if have ~= text then
		io.stderr:write("docs/ROTEIRO_QUEST_PRINCIPAL.md is out of date: run luajit tools/gen_mainquest_script.lua\n")
		os.exit(1)
	end
	print("roteiro ok")
else
	local f = assert(io.open(OUT, "wb"))
	f:write(text)
	f:close()
	print("wrote " .. OUT)
end
