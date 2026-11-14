-- The pt-BR script of the main quest (O551): docs/ROTEIRO_QUEST_PRINCIPAL.md, generated from mainquest_config.lua, so the
-- script the owner reads is the text the game says. usage (from server/): luajit tools/gen_mainquest_script.lua [--check]
-- Lua 5.1 / LuaJIT and 5.3.
local cfg = dofile("data/scripts/chaos/mainquest_config.lua")
local OUT = "../docs/ROTEIRO_QUEST_PRINCIPAL.md"

local o = {}
local function w(s)
	o[#o + 1] = s or ""
end

local hasBring = {}
for _, st in ipairs(cfg.steps) do
	for _, c in ipairs(st.conds) do
		if c.c == "talk" and c.bring then
			hasBring[c.bring] = true
		end
	end
end

local function objective(step)
	local parts = {}
	for _, c in ipairs(step.conds) do
		if c.c == "count" and c.item then
			local list = table.concat(c.mons, ", ")
			local takes = hasBring[step.key] and "A Guardiã Ysolde recolhe os itens no passo seguinte." or "A Vigília recolhe os itens quando a etapa termina."
			parts[#parts + 1] = string.format("%s (monstros: %s). Item de quest: %s, o stock item %d com nome, descrição e marca próprios. %s",
				step.title.pt, list, c.item.pt, c.itemId, takes)
		elseif c.c == "count" then
			local list = table.concat(c.mons, ", ")
			parts[#parts + 1] = string.format("%s (monstros: %s).", step.title.pt, list)
		elseif c.c == "visit" then
			parts[#parts + 1] = string.format("%s (a marca está no mapa).", step.title.pt)
		elseif c.c == "talk" and c.bring then
			parts[#parts + 1] = "Leve os itens de quest à Guardiã Ysolde e diga \"juramento\": ela recolhe a quantia exata. Se faltar algum (perdido, ou o saco de saque sumiu antes de você pegar o item), ela avisa e eles caem de novo dos mesmos monstros enquanto a etapa estiver aberta."
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
w("## Itens de quest e grupo")
w()
w("Os itens das etapas de coleta são de verdade, não um contador. Cada um é um item do jogo (um stock item, como uma presa ou uma engrenagem) com nome, descrição e marca próprios, feito para o personagem que o recebeu. Ele cai no saco de saque do monstro morto quando o personagem é o dono do saque, senão vai direto para a mochila (e, com a mochila cheia, para a caixa de correio). Não pode ser vendido, jogado fora, colocado no mercado nem empilhado com uma cópia comum do mesmo item, e o item de outro personagem não conta. A etapa de coleta conta os itens que o personagem carrega. Quem perdeu algum é avisado pela Guardiã Ysolde na etapa de entrega, e o item volta a cair dos mesmos monstros (a regra da garantia ainda vale: depois de muitas mortes sem queda, a próxima derruba).")
w()
w("Quem estava no meio de uma etapa de coleta antes dessa mudança recebe, uma vez, os itens que o contador já tinha contado. Uma etapa de entrega aberta na regra antiga é aceita sem itens.")
w()
w(string.format("Uma morte conta para quem deu o golpe final, para quem causou mais dano e para os membros do grupo deles que estão no mesmo andar, a até %d casas: quem causou dano conta sempre, quem não causou conta quando a experiência compartilhada do grupo está funcionando. Cada membro na etapa certa (nível da etapa atingido) conta a morte, ou rola a queda do item para si, e o item vai para quem rolou.", cfg.party.range))
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
