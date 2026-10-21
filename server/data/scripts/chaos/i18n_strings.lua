-- Server texts in other languages than English (i18n_core.lua, server/README.md "Server texts in pt-BR (Chaos.t)").
-- A key is the English text, a string.format pattern; its translation keeps the % conversions in the same order.
-- {spell} in a boss warning is the spell's name. UTF-8: the client turns it into cp1252 (client base patch 0028).
-- Game terms follow the wiki's pt-BR guides: proper names of classes, spells, items, bosses, orbs and the menus stay
-- in English. tests/i18n_test.lua checks that every key used by the converted sites has a pt-BR entry.

return {
	["pt-BR"] = {
		-- Gold payments from carried coins and the bank (data/lib/chaos_pay.lua)
		["Paid %d gold: %d carried and %d from your bank. Bank balance: %d gold."] =
			"Pago %d de ouro: %d da mochila e %d do seu banco. Saldo no banco: %d de ouro.",
		["Paid %d gold from your bank. Bank balance: %d gold."] =
			"Pago %d de ouro do seu banco. Saldo no banco: %d de ouro.",
		["You do not have enough gold (carried and in the bank)."] =
			"Você não tem ouro suficiente (na mochila e no banco).",
		-- Idle Hall (idlehall.lua, idlehall_core.lua)
		["You are idle in town: you will be moved to the Idle Hall in 1 minute. Take a step to stay."] =
			"Você está parado na cidade: em 1 minuto será levado ao Idle Hall. Dê um passo para ficar.",
		["You are idle in town: you will be moved to the Idle Hall in %d seconds. Take a step to stay."] =
			"Você está parado na cidade: em %d segundos será levado ao Idle Hall. Dê um passo para ficar.",
		["You stood idle in town for %d minutes and were moved to the Idle Hall. Its portal leads back to your temple."] =
			"Você ficou parado na cidade por %d minutos e foi levado ao Idle Hall. O portal dele leva de volta ao seu templo.",
		-- Time-friendly progression (catchup.lua)
		["Rested Vial: +%d minutes of rested hunting (%d in all)."] =
			"Frasco de Descanso: +%d minutos de caça descansada (%d no total).",
		["Bounty rerolls: %d. Use one on an accepted contract in the Bounty Board."] =
			"Novos sorteios de bounty: %d. Use um em um contrato aceito no Bounty Board.",
		["You have no bounty reroll."] = "Você não tem novo sorteio de bounty.",
		["No other monster fits this contract."] = "Nenhum outro monstro serve para este contrato.",
		["Bounty rerolled: now %d x %s."] = "Bounty sorteado de novo: agora %d x %s.",
		["Kill task rerolls: %d. Use one on the task board of the Bestiary."] =
			"Novos sorteios de kill task: %d. Use um no quadro de tarefas do Bestiary.",
		["You have no kill task reroll."] = "Você não tem novo sorteio de kill task.",
		["The task board was drawn again."] = "O quadro de tarefas foi sorteado de novo.",
		["Not sure where to start? Open Next Goals in the top menu."] =
			"Não sabe por onde começar? Abra Next Goals no menu superior.",
		["You are rested: +%d%% experience from monsters for about %d minutes of hunting."] =
			"Você está descansado: +%d%% de experiência de monstros por cerca de %d minutos de caça.",
		["Welcome back! For %d days: +%d%% experience, +%d%% loot and +%d%% token drops."] =
			"Bem-vindo de volta! Por %d dias: +%d%% de experiência, +%d%% de loot e +%d%% de drops de tokens.",
		["Catch-up: +%d%% experience from monsters until you near level %d, your account's best."] =
			"Recuperação: +%d%% de experiência de monstros até chegar perto do level %d, o melhor da sua conta.",
		["Your stamina is below %d hours: monsters give %d%% experience and %d%% loot. Stamina comes back faster while you are offline."] =
			"Sua stamina está abaixo de %d horas: monstros dão %d%% de experiência e %d%% de loot. A stamina volta mais rápido enquanto você está offline.",
		-- Ember Cache, Daily Spark and the day book (embercache.lua)
		["%d gold to your bank and %s."] = "%d de ouro no seu banco e %s.",
		["%d gold to your bank."] = "%d de ouro no seu banco.",
		["Your backpack was full: see your inbox."] = "Sua mochila estava cheia: veja sua caixa de entrada.",
		["Daily Spark lit: %s"] = "Daily Spark aceso: %s",
		["Ember Cache milestone %d of %d: %s"] = "Marco %d de %d do Ember Cache: %s",
		["Your last day of play (%s): %s experience, %d kills, %s gold of loot, %d Ember points."] =
			"Seu último dia de jogo (%s): %s de experiência, %d abates, %s de ouro em loot, %d pontos Ember.",
		["You have offered all the junk orbs the Ember Cache takes today. More tomorrow."] =
			"Você já ofereceu todos os orbes comuns que o Ember Cache aceita hoje. Mais amanhã.",
		["You need at least %d junk orbs in your backpack (locked orbs do not count)."] =
			"Você precisa de pelo menos %d orbes comuns na mochila (orbes travados não contam).",
		["You offered %d junk orbs to the Ember Cache: %d Ember points (%d more points today)."] =
			"Você ofereceu %d orbes comuns ao Ember Cache: %d pontos Ember (mais %d pontos hoje).",
		["Daily Spark"] = "Daily Spark",
		["Ember Cache"] = "Ember Cache",
		["Day book"] = "Diário",
		-- Restock (restock.lua)
		["Restock: stand in a protection zone in town."] = "Reabastecer: fique em uma zona de proteção na cidade.",
		["Restock: not inside an instance."] = "Reabastecer: não dentro de uma instância.",
		["Restock: nothing used in this hunt session yet."] =
			"Reabastecer: nada foi usado nesta sessão de caçada ainda.",
		["Restock: you need %d gold (carried or in the bank)."] =
			"Reabastecer: você precisa de %d de ouro (com você ou no banco).",
		["Restocked %s for %d gold."] = "Reabastecido: %s por %d de ouro.",
		[" Some went to your inbox (no room or capacity)."] =
			" Parte foi para sua caixa de entrada (sem espaço ou capacidade).",
		-- Gentle deaths (gentledeath.lua)
		["Gentle death: you lost no experience."] = "Morte suave: você não perdeu experiência.",
		["Gentle death: first death of the day, you lost %d%% of the usual experience."] =
			"Morte suave: primeira morte do dia, você perdeu %d%% da experiência normal.",
		["Gentle death: you lost %d%% of the usual experience."] = "Morte suave: você perdeu %d%% da experiência normal.",
		["Gentle death: you keep all your items (only a red or black skull drops them)."] =
			"Morte suave: você mantém todos os seus itens (só uma red ou black skull os derruba).",
		["Blessings: leave combat first (no battle sign or protection zone lock)."] =
			"Bênçãos: saia do combate primeiro (sem sinal de batalha nem bloqueio de zona de proteção).",
		["Blessings: you need %d gold (carried or in the bank) for %d blessing(s)."] =
			"Bênçãos: você precisa de %d de ouro (com você ou no banco) para %d bênção(ões).",
		["The gods bless you: %d blessing(s) for %d gold. You have all blessings."] =
			"Os deuses te abençoam: %d bênção(ões) por %d de ouro. Você tem todas as bênçãos.",
		["You already have the Eternal Blessing."] = "Você já tem a Eternal Blessing.",
		["The Eternal Blessing is yours: this character keeps all blessings for good."] =
			"A Eternal Blessing é sua: este personagem mantém todas as bênçãos para sempre.",
		["Eternal Blessing: your blessings are back."] = "Eternal Blessing: suas bênçãos voltaram.",
		-- Pack combat (pace.lua)
		["Multikill x%d: +%d%% experience on the chain."] = "Multikill x%d: +%d%% de experiência na sequência.",
		-- Auto Seller (autosell.lua, autosell_core.lua)
		["Auto loot: %d gold to your bank."] = "Auto Loot: %d de ouro no seu banco.",
		["Auto seller: sold %s for %d gold (to your bank)."] = "Auto Seller: vendeu %s por %d de ouro (no seu banco).",
		["Auto seller: kept an item of a rarity you keep, a unique or a named item (Economy > Auto Seller)."] =
			"Auto Seller: guardou um item de uma raridade que você guarda, um único ou um item com nome (Economy > Auto Seller).",
		["Auto seller: kept a locked item."] = "Auto Seller: guardou um item travado.",
		["List cleared."] = "Lista limpa.",
		["Unknown list change."] = "Mudança de lista desconhecida.",
		["There is no item called %s."] = "Não existe item chamado %s.",
		["%s is already on your list."] = "%s já está na sua lista.",
		["%s is never auto-sold (orbs, gems and keys are kept)."] =
			"%s nunca é vendido automaticamente (orbes, gemas e chaves ficam).",
		["No NPC buys %s, so it cannot be auto-sold."] = "Nenhum NPC compra %s, então não pode ser vendido automaticamente.",
		["Your list is full (%d items)."] = "Sua lista está cheia (%d itens).",
		["%s will be sold for %d gold each."] = "%s será vendido por %d de ouro cada.",
		["%s is not on your list."] = "%s não está na sua lista.",
		["Removed %s."] = "%s removido.",
		["Rarities: %s."] = "Raridades: %s.",
		["Bad request."] = "Pedido inválido.",
		["%s no longer drops: bows and crossbows need no ammunition, so it cannot be on the auto loot list."] =
			"%s não cai mais: arcos e bestas não precisam de munição, então não pode estar na lista de auto loot.",
		-- Party shared experience (party_xp.lua)
		["Shared experience is off. The party leader can turn it on from the party shield menu."] =
			"A experiência compartilhada está desligada. O líder do grupo pode ligá-la no menu do escudo do grupo.",
		["Shared experience is not working: every member must pass these at once."] =
			"A experiência compartilhada não está funcionando: todos os membros precisam cumprir estas regras ao mesmo tempo.",
		["%s is below level %d (the party shares only within two thirds of its highest level)"] =
			"%s está abaixo do nível %d (o grupo só compartilha dentro de dois terços do maior nível)",
		["%s is too far from the leader (30 tiles, 1 floor)"] = "%s está longe demais do líder (30 sqm, 1 andar)",
		["%s has not attacked a monster or healed a member lately (buffs do not count)"] =
			"%s não atacou um monstro nem curou um membro há pouco (buffs não contam)",
		["Auto Seller: your Loot Bag is sold every %d minutes."] = "Auto Seller: sua Loot Bag é vendida a cada %d minutos.",
		["Auto Seller: timed selling is off."] = "Auto Seller: a venda automática por tempo está desligada.",
		["bad request"] = "pedido inválido",
		["unknown rarity"] = "raridade desconhecida",
		["on must be true or false"] = "on precisa ser true ou false",
		["You need the Auto Seller from the store (Convenience) or an active Chaos Pact."] =
			"Você precisa do Auto Seller da loja (Convenience) ou de um Chaos Pact ativo.",
		["Auto Seller: carry your Loot Bag to sell what is in it."] =
			"Auto Seller: carregue sua Loot Bag para vender o que tem nela.",
		["Needs the Auto Seller (Store > Convenience) or an active Chaos Pact."] =
			"Precisa do Auto Seller (Store > Convenience) ou de um Chaos Pact ativo.",
		["Auto Seller: sold %d item%s from your Loot Bag for %d gold (to your bank).%s"] =
			"Auto Seller: vendeu %d item%s da sua Loot Bag por %d de ouro (no seu banco).%s",
		[" Kept %d: %s."] = " Guardados %d: %s.",
		["%s %d"] = "%s %d",
		["locked"] = "travados",
		["unique"] = "únicos",
		["rarity"] = "raridade",
		["named"] = "com nome",
		["no NPC buys"] = "nenhum NPC compra",
		["orbs / gems / keys"] = "orbes / gemas / chaves",

		-- boss mechanics: the orange warning lines (boss_mechanics.lua, boss_mechanics_config.lua)
		["%s's {spell} is interrupted!"] = "{spell} de %s foi interrompido!",
		["%s: %d stacks (+%d%% damage taken from %s)."] = "%s: %d acúmulos (+%d%% de dano recebido de %s).",
		["%s anchors itself: kill the 2 Rift Anchors!"] = "%s se ancora: mate as 2 Rift Anchors!",
		["%s begins the Chorus! Stand in the circle together!"] = "%s começa o Chorus! Fiquem juntos no círculo!",
		["%s burns hotter with every minute!"] = "%s queima mais forte a cada minuto!",
		["%s calls down the sky! Hide behind a pillar!"] = "%s faz o céu desabar! Escondam-se atrás de um pilar!",
		["%s calls the Deep Freeze! Hide behind a pillar!"] = "%s invoca o Deep Freeze! Escondam-se atrás de um pilar!",
		["%s channels Oblivion! Destroy the Void Anchor!"] = "%s canaliza Oblivion! Destruam a Void Anchor!",
		["%s channels the Eclipse! Destroy the Gloom Totem!"] = "%s canaliza o Eclipse! Destruam o Gloom Totem!",
		["%s chants the Bone Requiem! Destroy the Bone Totem!"] = "%s entoa o Bone Requiem! Destruam o Bone Totem!",
		["%s charges a Conduit! Stand in the circle!"] = "%s carrega um Conduit! Fiquem no círculo!",
		["%s demands a Shared Oath! Stand in the circle together!"] = "%s exige um Shared Oath! Fiquem juntos no círculo!",
		["%s draws 3 Cinder Wardstones about it!"] = "%s ergue 3 Cinder Wardstones à sua volta!",
		["%s draws the cold into her! Hide behind a pillar!"] = "%s puxa o frio para si! Escondam-se atrás de um pilar!",
		["%s hides behind 2 Bloodmoon Wardstones!"] = "%s se esconde atrás de 2 Bloodmoon Wardstones!",
		["%s is gathering flame! Destroy the Ember Totem!"] = "%s está juntando chamas! Destruam o Ember Totem!",
		["%s is sealed: break the 3 Infernal Seals!"] = "%s está selado: quebrem os 3 Infernal Seals!",
		["%s is shielded by 3 Infernal Wardstones! Break them!"] = "%s está protegido por 3 Infernal Wardstones! Quebrem!",
		["%s is warded by 2 Sanguine Wardstones!"] = "%s está protegido por 2 Sanguine Wardstones!",
		["%s opens an Event Horizon! Stand in the circle together!"] =
			"%s abre um Event Horizon! Fiquem juntos no círculo!",
		["%s raises the Crown of Night! Hide behind a pillar!"] = "%s ergue a Crown of Night! Escondam-se atrás de um pilar!",
		["%s seals the vault: break the 2 Vault Wardens!"] = "%s sela o cofre: quebrem os 2 Vault Wardens!",
		["%s sings the Dirge! Destroy the Hollow Totem!"] = "%s canta o Dirge! Destruam o Hollow Totem!",
		["%s starts to devour the standard! Destroy it!"] = "%s começa a devorar o estandarte! Destruam!",
		["Blood Idols rise: %s grows stronger while they stand!"] =
			"Os Blood Idols se erguem: %s fica mais forte enquanto eles estiverem de pé!",
		["Plague Hearts pulse: they feed %s while they beat!"] =
			"Os Plague Hearts pulsam: eles alimentam %s enquanto batem!",
		["The Blood Idols crumble."] = "Os Blood Idols desmoronam.",
		["The Cinder Wardstones shatter!"] = "As Cinder Wardstones se estilhaçam!",
		["The Plague Hearts are still."] = "Os Plague Hearts param.",
		["The anchors break!"] = "As âncoras se partem!",
		["The seal breaks!"] = "O selo se quebra!",
		["The seals break!"] = "Os selos se quebram!",
		["The wards are broken: %s can be hurt again!"] = "As proteções caíram: %s pode ser ferido de novo!",
		["The wards fall!"] = "As proteções caem!",
		["The wardstones crack: %s bleeds again!"] = "As wardstones racham: %s sangra de novo!",
		-- the generated dungeons 6-9
		["%s hides in its ribs: break the 2 Marrow Reliquaries!"] =
			"%s se esconde nas costelas: quebrem os 2 Marrow Reliquaries!",
		["The reliquaries crack: %s can be hurt again!"] = "Os relicários racham: %s pode ser ferido de novo!",
		["%s stokes the Furnace Heart! Destroy the Bellows Totem!"] =
			"%s atiça o Furnace Heart! Destruam o Bellows Totem!",
		["%s raises 2 Gilded Wards!"] = "%s ergue 2 Gilded Wards!",
		["%s sings the Last Hymn! Stand in the circle!"] = "%s canta o Last Hymn! Fiquem no círculo!",
		["%s pulls on her chains: break the 3 Pyre Chains!"] = "%s puxa suas correntes: quebrem as 3 Pyre Chains!",
		["The chains snap: %s can be hurt again!"] = "As correntes se partem: %s pode ser ferida de novo!",
		["%s fills the hall with fire! Hide behind a pillar!"] =
			"%s enche o salão de fogo! Escondam-se atrás de um pilar!",
		-- the queue dungeons (dungeons.lua unlockBoss)
		["Boss unlocked! %d%% of the monsters are dead: %s awaits you."] =
			"Boss liberado! %d%% dos monstros estão mortos: %s espera por você.",
		-- the boss chest of a generated dungeon (areagen.lua AG.giveChest)
		["Boss chest of %s: %d gold to your bank%s%s.%s"] = "Baú do chefe de %s: %d de ouro no seu banco%s%s.%s",
		[" Your backpack was full: the rest is in your inbox."] = " Sua mochila estava cheia: o resto está na sua caixa de entrada.",

		-- the Ashen Sepulchre raid (raid.lua, raid_core.lua K.ANNOUNCE)
		["TANK SWAP: %s is at %d stacks!"] = "TROCA DE TANK: %s está com %d acúmulos!",
		["CRUSHING VERDICT on %s!"] = "CRUSHING VERDICT em %s!",
		["Frontal Cleave: get out of the front!"] = "Frontal Cleave: saiam da frente!",
		["Rear Sweep: get out from behind!"] = "Rear Sweep: saiam de trás!",
		["Ember Brand: SOAK the circles (%d each)!"] = "Ember Brand: ABSORVAM os círculos (%d em cada)!",
		["%s arrive: kill them first!"] = "%s chegam: matem primeiro!",
		["Bone Bloom: step out of your circle!"] = "Bone Bloom: saia do seu círculo!",
		["%s rises: KILL IT!"] = "%s se ergue: MATEM!",
		["Withering Hex on %s: cleanse it!"] = "Withering Hex em %s: purifiquem!",
		["The hex on %s bursts!"] = "O hex em %s explode!",
		["%s turns to %s."] = "%s se volta para %s.",
		["%s: phase %d of %d, %s."] = "%s: fase %d de %d, %s.",
		["%s awakens! The doors seal. Enrage in %s."] = "%s desperta! As portas se fecham. Enrage em %s.",
		["The raid falls before %s. The doors open again."] = "A raid cai diante de %s. As portas se abrem de novo.",
		["%s is slain! %d looted, %d helped.%s"] = "%s foi morto! %d com loot, %d ajudaram.%s",
		["%s is ENRAGED!"] = "%s está ENFURECIDO!",
		["A %s detonates!"] = "Um %s detona!",
		["The corridor is clear: the door to %s opens."] = "O corredor está limpo: a porta para %s se abre.",
		["%s has fallen."] = "%s caiu.",
		["%s, raid #%d: %d of %d bosses slain this week. %s"] = "%s, raid #%d: %d de %d chefes mortos nesta semana. %s",
		["Next: %s."] = "Próximo: %s.",
		["%s joins the raid."] = "%s entra na raid.",
		["A gamemaster closed the raid. Your progress is saved for the week."] =
			"Um gamemaster fechou a raid. Seu progresso fica salvo durante a semana.",
		["Time is up: %s closes. Your progress is saved for the week; continue it from the raid window."] =
			"O tempo acabou: %s fecha. Seu progresso fica salvo durante a semana; continue pela janela da raid.",
		["%s found %s in %s!"] = "%s achou %s em %s!",
		["a raid"] = "uma raid",
		["%s fell to %s in %s!"] = "%s caiu diante de %s em %s!",
		["%s fell to %s!"] = "%s caiu diante de %s!",

		-- rifts and omens (rift.lua)
		["You fell in the rift."] = "Você caiu no rift.",
		["You left the rift."] = "Você saiu do rift.",
		["Everyone left the rift."] = "Todos saíram do rift.",
		["You fell: %d life left. You return at the rift's entrance when you log in again."] =
			"Você caiu: resta %d vida. Você volta na entrada do rift quando entrar de novo.",
		["You fell: %d lives left. You return at the rift's entrance when you log in again."] =
			"Você caiu: restam %d vidas. Você volta na entrada do rift quando entrar de novo.",
		["%s The arena collapses and the key is lost."] = "%s A arena desaba e a chave se perde.",
		["%s The rift collapses and the key is lost."] = "%s O rift desaba e a chave se perde.",
		["The guardian did not answer."] = "O guardião não respondeu.",
		["Time is up!"] = "O tempo acabou!",
		["Nobody came back in time."] = "Ninguém voltou a tempo.",
		["A gamemaster closed the rift."] = "Um gamemaster fechou o rift.",
		["No lives are left!"] = "Não restam vidas!",
		["The guardian falls! Open its chest within %d seconds."] = "O guardião cai! Abra o baú dele em até %d segundos.",
		["The rift is sealed! Open the chest within %d seconds."] = "O rift foi selado! Abra o baú em até %d segundos.",
		["%s found a %s!"] = "%s achou uma %s!",
		["The %s guardian falls in %d:%02d. %s"] = "O guardião %s cai em %d:%02d. %s",
		["Rift tier %d sealed in %d:%02d. %s"] = "Rift tier %d selado em %d:%02d. %s",
		["%s answers the omen!"] = "%s responde ao omen!",
		["Twin guardians %s tear through the veil!"] = "Os guardiões gêmeos %s rasgam o véu!",
		["The rift guardian %s tears through the veil!"] = "O guardião do rift %s rasga o véu!",
		["The coffer's seal breaks: %d gold, %d Orb%s of Upheaval, %d Orb%s of Fate and %d more item%s inside."] =
			"O selo do cofre se quebra: %d de ouro, %d Orb%s of Upheaval, %d Orb%s of Fate e mais %d item%s dentro.",
		["%s breaks the coffer's seal: %d guards answer!"] = "%s quebra o selo do cofre: %d guardas respondem!",
		["Rift tier %d (%s, %s of %d x %d%s): %d monsters, the guardian waits in the %s after %d kills. %d minutes, %d shared lives. Modifiers: %s."] =
			"Rift tier %d (%s, %s de %d x %d%s): %d monstros, o guardião espera no %s depois de %d abates. %d minutos, %d vidas compartilhadas. Modificadores: %s.",
		["%d more packs gather ahead of you as you advance."] = "Mais %d packs se juntam à sua frente conforme você avança.",
		["The %s omen: %s comes in %d seconds. %d minutes, %d shared lives."] =
			"O omen %s: %s chega em %d segundos. %d minutos, %d vidas compartilhadas.",
		["The %s monster dropped a %s!"] = "O monstro %s dropou uma %s!",
		["%s has fallen: %d shared life left."] = "%s caiu: resta %d vida compartilhada.",
		["%s has fallen: %d shared lives left."] = "%s caiu: restam %d vidas compartilhadas.",
		["%s has fallen, and with them the rift's last life."] = "%s caiu, e com ele a última vida do rift.",
		["%s has fallen in the rift."] = "%s caiu no rift.",
		["%s returns to the rift (%d shared life left)."] = "%s volta ao rift (resta %d vida compartilhada).",
		["%s returns to the rift (%d shared lives left)."] = "%s volta ao rift (restam %d vidas compartilhadas).",
		["%s left the rift."] = "%s saiu do rift.",
		["A Treasure Goblin slips out of the rift with its hoard. Catch it before it escapes!"] =
			"Um Treasure Goblin escapa do rift com seu tesouro. Pegue-o antes que fuja!",
		["One guardian falls. Its twin still stands!"] = "Um guardião cai. O gêmeo dele continua de pé!",

		-- records and leaderboards (records.lua, records_core.lua, leaderboard_core.lua)
		["New record! %s: %s by %s%s."] = "Novo recorde! %s: %s por %s%s.",
		[" (was %s)"] = " (era %s)",
		["the season"] = "a temporada",
		["Realm first of %s! %s is the first to defeat %s."] = "Primeiro do reino em %s! %s é o primeiro a derrotar %s.",
		["Realm first of %s! %s are the first to defeat %s."] = "Primeiro do reino em %s! %s são os primeiros a derrotar %s.",
		["Records: %d weekly top 3 placings of last week hold their titles and the %s badge this week."] =
			"Recordes: %d colocações no top 3 semanal da semana passada mantêm os títulos e o selo %s nesta semana.",
		["A new leaderboard week begins! Nobody placed on last week's boards."] =
			"Começa uma nova semana nos leaderboards! Ninguém se classificou nos quadros da semana passada.",
		["A new leaderboard week begins! Last week's champions - %s."] =
			"Começa uma nova semana nos leaderboards! Campeões da semana passada - %s.",

		-- world boss (worldboss.lua)
		["%s received the unique %s from the world boss!"] = "%s recebeu o único %s do chefe de mundo!",
		["%s has appeared in the world boss arena! You have %d minutes to bring it down."] =
			"%s apareceu na arena do chefe de mundo! Vocês têm %d minutos para derrubá-lo.",
		["%s has been slain by %d champion(s) in %dm %02ds! %s Everyone inside returns home in %d seconds."] =
			"%s foi morto por %d campeão(ões) em %dm %02ds! %s Todos lá dentro voltam para casa em %d segundos.",
		["The world boss could not appear. The event is cancelled."] =
			"O chefe de mundo não pôde aparecer. O evento foi cancelado.",
		["The world boss event was stopped by the staff."] = "O evento do chefe de mundo foi interrompido pela equipe.",
		["%s was not defeated in time and withdraws. The world boss event is over."] =
			"%s não foi derrotado a tempo e se retira. O evento do chefe de mundo acabou.",
		["WORLD BOSS: %s Portals are open next to the temples for %d minutes (level %d+). The boss appears in %d seconds."] =
			"CHEFE DE MUNDO: %s Os portais estão abertos ao lado dos templos por %d minutos (nível %d+). O chefe aparece em %d segundos.",
		["The world boss portals have closed."] = "Os portais do chefe de mundo se fecharam.",
		["A world boss awakens in %d minute(s)%s! Portals will open next to the temples."] =
			"Um chefe de mundo desperta em %d minuto(s)%s! Portais vão abrir ao lado dos templos.",

		-- invasions and world events (invasion.lua, worldevents.lua)
		["Wave %d of %d: %s leads the last assault on %s!"] = "Onda %d de %d: %s lidera o último ataque a %s!",
		["Wave %d of %d: %d %s reach %s!"] = "Onda %d de %d: %d %s chegam a %s!",
		["The defences of %s are crumbling: the breach is at 50%%!"] = "As defesas de %s estão desmoronando: a brecha está em 50%%!",
		["%s is about to fall: the breach is at 80%%!"] = "%s está prestes a cair: a brecha está em 80%%!",
		["The horde of %s breaks: the last %d invaders flee in %d seconds."] =
			"A horda de %s se desfaz: os últimos %d invasores fogem em %d segundos.",
		["The last %d invaders flee from %s."] = "Os últimos %d invasores fogem de %s.",
		["INVASION! The %s attacks %s! Defend %s: %d waves in %d minutes, the last one led by their warlord."] =
			"INVASÃO! %s ataca %s! Defenda %s: %d ondas em %d minutos, a última liderada pelo senhor da guerra deles.",
		["VICTORY! %s held: the %s is broken in %s. Top defenders: %s."] =
			"VITÓRIA! %s resistiu: %s foi quebrado em %s. Melhores defensores: %s.",
		["DEFEAT! %s %s. The %s occupies it for %d minutes: slay the occupiers to free it."] =
			"DERROTA! %s %s. %s ocupa o lugar por %d minutos: mate os ocupantes para libertá-lo.",
		["%s is liberated! The last occupier is slain (%d defender%s rewarded)."] =
			"%s foi libertado! O último ocupante foi morto (%d recompensa%s para os defensores).",
		["The %s withdraws from %s."] = "%s se retira de %s.",
		["The invasion of %s was called off."] = "A invasão de %s foi cancelada.",
		["%s received the unique %s for defending %s!"] = "%s recebeu o único %s por defender %s!",
		["Victory buff: +%d%% experience %s for %d minutes!"] = "Bônus de vitória: +%d%% de experiência %s por %d minutos!",
		["%s is slain by %s!"] = "%s foi morto por %s!",
		["%s is slain!"] = "%s foi morto!",
		["The %s gathers: %s will be invaded in %d minute%s!"] = "%s se reúne: %s será invadido em %d minuto%s!",
		["A Chaos Storm rages over %s until %s: magic, rare and legendary monsters appear %s times as often there."] =
			"Uma Chaos Storm cai sobre %s até %s: monstros mágicos, raros e lendários aparecem %s vezes mais lá.",
		["Golden Hour in %s until %s: +%d%% loot from every monster there."] =
			"Golden Hour em %s até %s: +%d%% de loot de todo monstro lá.",
		["A Wandering Merchant has set up shop somewhere in %s until %s: orbs and rare goods at a good price. Find him!"] =
			"Um Wandering Merchant montou a loja em algum lugar de %s até %s: orbes e itens raros a bom preço. Ache-o!",
		["The %s in %s is over."] = "%s em %s acabou.",

		-- other broadcasts
		["PvP Season %d has ended. Season %d begins: ratings were softly reset; the season rewards are handed out."] =
			"A Temporada PvP %d acabou. A Temporada %d começa: os ratings foram levemente zerados; as recompensas da temporada foram entregues.",
		["%s has ascended to %s."] = "%s ascendeu a %s.",
		["%s has passed the Trial of Ascension and walks the path of the %s."] =
			"%s passou no Trial of Ascension e segue o caminho de %s.",
		["%s reached a login streak of %d days and earned the title %s!"] =
			"%s chegou a uma sequência de %d dias de login e ganhou o título %s!",
		["%s carried %s out of the Ember Descent!"] = "%s levou %s para fora da Ember Descent!",
		["%s and %s are now at war (%s)."] = "%s e %s agora estão em guerra (%s).",
		["%s found %s (%s)!"] = "%s achou %s (%s)!",
		["%s has extinguished the Cinderheart in %s!"] = "%s apagou o Cinderheart em %s!",
		["%s have extinguished the Cinderheart in %s!"] = "%s apagaram o Cinderheart em %s!",
		["%s %s has begun! New characters can join in Adventure > Season."] =
			"%s %s começou! Personagens novos podem entrar em Adventure > Season.",
		["%s has ended. Its characters are now standard characters."] =
			"%s acabou. Os personagens dela agora são personagens padrão.",
		["%s has fallen in Hardcore at level %d (%s)."] = "%s caiu no Hardcore no nível %d (%s).",
		["%s has ended."] = "%s acabou.",
		-- store-bound items kept through a death (death_keep.lua)
		["Kept through your death: your %s (%s)."] = "Guardado na sua morte: seu %s (%s).",
		["backpack"] = "mochila",
		["inbox"] = "caixa de entrada",
		["backpack and inbox"] = "mochila e caixa de entrada",
		-- Character Bazaar: a listed character's login is refused (bazaar.lua, bazaar_config.lua messages.locked)
		["This character is listed on the Character Bazaar until %s (server time). It cannot log in until the auction ends or the seller cancels it on the website."] =
			"Este personagem está anunciado no Character Bazaar até %s (horário do servidor). Ele não pode entrar até o leilão terminar ou o vendedor cancelar o anúncio no site.",
		-- The store: messages, refusals, gifts (shop.lua, shop_core.lua)
		["Error"] = "Erro",
		["Not possible"] = "Não é possível",
		["Not enough coins"] = "Coins insuficientes",
		["Gift sent"] = "Presente enviado",
		["Purchase complete"] = "Compra concluída",
		["This offer does not exist any more."] = "Esta oferta não existe mais.",
		["The store changed. Please choose the offer again."] = "A loja mudou. Escolha a oferta de novo.",
		["Please wait a moment before the next gift."] = "Espere um momento antes do próximo presente.",
		["You sent as many gifts as you may today."] = "Você já enviou todos os presentes permitidos hoje.",
		["Could not take the coins. Try again."] = "Não foi possível tirar as coins. Tente de novo.",
		["There is no character with that name."] = "Não existe personagem com esse nome.",
		["You cannot gift coins to your own account."] = "Você não pode presentear coins para a sua própria conta.",
		["Buy it for yourself with the Buy button."] = "Compre para você mesmo com o botão Buy.",
		["Gifts cannot go to staff characters."] = "Presentes não podem ir para personagens da staff.",
		["That account cannot receive gifts."] = "Essa conta não pode receber presentes.",
		["This offer cannot be gifted."] = "Esta oferta não pode ser presenteada.",
		["This offer is not available."] = "Esta oferta não está disponível.",
		["This offer cannot be bought."] = "Esta oferta não pode ser comprada.",
		["The outfit could not be added."] = "Não foi possível adicionar o outfit.",
		["The mount could not be added."] = "Não foi possível adicionar a montaria.",
		["It is no longer sold."] = "Não é mais vendido.",
		["Season characters cannot buy %s."] = "Personagens de temporada não podem comprar %s.",
		["%s already owns %s."] = "%s já tem %s.",
		["You already own %s."] = "Você já tem %s.",
		["%s needs a Premium account to wear. Get Premium Time first."] =
			"%s precisa de uma conta Premium para usar. Pegue Premium Time primeiro.",
		["%s is for characters up to level %s."] = "%s é para personagens até o nível %s.",
		["Your account already bought %s."] = "Sua conta já comprou %s.",
		["You bought %s %s times this week; the limit resets on Monday."] =
			"Você comprou %s %s vezes nesta semana; o limite reinicia na segunda-feira.",
		-- store delivery to the purse (store_delivery.lua, store_delivery_core.lua)
		["Delivered to your purse (the button under your equipment)."] =
			"Entregue na sua bolsa (o botão abaixo do seu equipamento).",
		["Delivered to your %s (%s)."] = "Entregue na sua %s (%s).",
		["Delivered: %d to your purse, %d to your depot inbox, %d to your backpack (%s)."] =
			"Entregue: %d na sua bolsa, %d na sua caixa de entrada do depot, %d na sua mochila (%s).",
		["purse"] = "bolsa",
		["depot inbox"] = "caixa de entrada do depot",
		["you have no purse"] = "você não tem bolsa",
		["not enough capacity for the purse"] = "sem capacidade para a bolsa",
		["your purse could not take it"] = "sua bolsa não pôde receber",
		["%s has no room in the purse, the depot inbox or the backpack."] =
			"%s não tem espaço na bolsa, na caixa de entrada do depot nem na mochila.",
		["%s does not have enough room or capacity."] = "%s não tem espaço ou capacidade suficiente.",
		["%s gave you %s from the Chaos store."] = "%s te deu %s da loja Chaos.",
		["%s sent you %s, but %s; the coins went back to them."] =
			"%s te enviou %s, mas %s; as coins voltaram para quem enviou.",
		["You need %s Chaos Coins for %s."] = "Você precisa de %s Chaos Coins para %s.",
		["You gave %s to %s for %s Chaos Coins."] = "Você deu %s para %s por %s Chaos Coins.",
		["You gave %s to %s for %s Chaos Coins. It is delivered at their next login."] =
			"Você deu %s para %s por %s Chaos Coins. A entrega acontece no próximo login.",
		["You bought %s for %s Chaos Coins."] = "Você comprou %s por %s Chaos Coins.",
		["Bought on %s for %s Chaos Coins."] = "Comprado em %s por %s Chaos Coins.",
		["You can gift at least %s Chaos Coins."] = "Você pode presentear no mínimo %s Chaos Coins.",
		["You do not have %s Chaos Coins."] = "Você não tem %s Chaos Coins.",
		["You gifted %s Chaos Coins to %s."] = "Você presenteou %s Chaos Coins para %s.",
		["Chaos Coins can be gifted %d days after your last donation (in %d day)."] =
			"Chaos Coins podem ser presenteadas %d dias depois da sua última doação (em %d dia).",
		["Chaos Coins can be gifted %d days after your last donation (in %d days)."] =
			"Chaos Coins podem ser presenteadas %d dias depois da sua última doação (em %d dias).",
		["You can gift at most %d Chaos Coins a day (%d left today)."] =
			"Você pode presentear no máximo %d Chaos Coins por dia (restam %d hoje).",
		["Your name plate frames: %s."] = "Suas molduras de nome: %s.",
		["none (Store > Name Plates)"] = "nenhuma (Store > Name Plates)",
		["Name plate frame: %s."] = "Moldura de nome: %s.",
		["your title's own"] = "a do seu título",
		["Thank you for your voluntary donation! You received %d Chaos Coins as a thank-you (%s%s).%s"] =
			"Obrigado pela sua doação voluntária! Você recebeu %d Chaos Coins como agradecimento (%s%s).%s",
		[", first donation bonus included"] = ", bônus de primeira doação incluído",

		-- Store services: tokens, world buffs, the Temple Teleport Scroll, name and vocation change (shop_services.lua)
		["A name must have %d to %d characters."] = "Um nome precisa ter de %d a %d caracteres.",
		["A name may only contain letters and spaces."] = "Um nome só pode ter letras e espaços.",
		["Use single spaces between the words."] = "Use um único espaço entre as palavras.",
		["A name may have at most %d words."] = "Um nome pode ter no máximo %d palavras.",
		["Every word needs at least %d letters."] = "Cada palavra precisa de pelo menos %d letras.",
		["Names may not look like a staff member's."] = "Nomes não podem parecer o de um membro da staff.",
		["A name may not repeat a letter three times in a row."] =
			"Um nome não pode repetir uma letra três vezes seguidas.",
		["That name is not allowed."] = "Esse nome não é permitido.",
		["Choose one of: %s."] = "Escolha um destes: %s.",
		["You have ascended: name the ascended class you want (%s)."] =
			"Você ascendeu: diga a classe ascendida que você quer (%s).",
		[" or "] = " ou ",
		["You already are of that vocation."] = "Você já é dessa vocação.",
		["%s (%s): %s left"] = "%s (%s): faltam %s",
		["+25% experience from monsters for every standard character"] =
			"+25% experiência de monstros para todo personagem padrão",
		["+25% Chaos loot (extra loot rolls and currency drops) for every standard character"] =
			"+25% Chaos loot (rolagens extras de loot e drops de moeda) para todo personagem padrão",
		["+25% skill and magic level training for every standard character"] =
			"+25% sobre o treino de skills e magic level para todo personagem padrão",
		["You cannot use this while you are in combat."] = "Você não pode usar isto em combate.",
		["You cannot use this inside a dungeon."] = "Você não pode usar isto dentro de uma dungeon.",
		["You cannot use this inside the Infinity Tower."] = "Você não pode usar isto dentro da Infinity Tower.",
		["You cannot use this inside the world boss arena."] = "Você não pode usar isto dentro da arena do world boss.",
		["You cannot use this inside a rift."] = "Você não pode usar isto dentro de um rift.",
		["You cannot use this inside %s."] = "Você não pode usar isto dentro de %s.",
		["name change"] = "troca de nome",
		["vocation change"] = "troca de vocação",
		["You already have an unused %s. Use it first (%s)."] = "Você já tem uma %s sem usar. Use primeiro (%s).",
		["You received a %s. Use it in %s."] = "Você recebeu uma %s. Use em %s.",
		["Your stamina is already full."] = "Sua stamina já está cheia.",
		["Your stamina is full again."] = "Sua stamina está cheia de novo.",
		["You do not have enough room or capacity."] = "Você não tem espaço ou capacidade suficiente.",
		["%s is already active for %s; it can run at most %d minutes. Try again later."] =
			"%s já está ativo por %s; pode durar no máximo %d minutos. Tente de novo mais tarde.",
		["The world buff is at its limit."] = "O world buff está no limite.",
		["%s extended the %s by %d minutes! (%s) %s left. Thank you!"] =
			"%s estendeu o %s por %d minutos! (%s) Faltam %s. Obrigado!",
		["%s activated the %s for everyone: %s for %d minutes! Thank you!"] =
			"%s ativou o %s para todos: %s por %d minutos! Obrigado!",
		["You already have all blessings."] = "Você já tem todas as bênçãos.",
		["The gods bless you: you have all blessings."] = "Os deuses te abençoam: você tem todas as bênçãos.",
		["Leave combat first (no battle sign or protection zone lock)."] =
			"Saia do combate primeiro (sem o sinal de batalha nem o bloqueio de zona de proteção).",
		["You have no unjustified kills or red/black skull to remove."] =
			"Você não tem mortes injustificadas nem skull vermelha/preta para remover.",
		["Your unjustified kills are forgiven and your skull is gone."] =
			"Suas mortes injustificadas foram perdoadas e sua skull sumiu.",
		["Leave combat first."] = "Saia do combate primeiro.",
		["Your character is now female. Your outfits came with you."] =
			"Sua personagem agora é feminina. Seus outfits vieram com você.",
		["Your character is now male. Your outfits came with you."] =
			"Seu personagem agora é masculino. Seus outfits vieram com você.",
		["The passive tree is not available."] = "A árvore passiva não está disponível.",
		["Your passive tree and Paragon track have no allocated points."] =
			"Sua árvore passiva e sua trilha Paragon não têm pontos distribuídos.",
		["Your passive tree and Paragon points were reset. All points are free to spend again."] =
			"Sua árvore passiva e seus pontos Paragon foram zerados. Todos os pontos estão livres de novo.",
		["Something went wrong. Your coins were refunded."] = "Algo deu errado. Suas coins foram devolvidas.",
		["You unlocked %s. %s"] = "Você desbloqueou %s. %s",
		["Mark the items to sell in Economy > Auto Seller."] = "Marque os itens para vender em Economy > Auto Seller.",
		["Set it in the Loot Filter (Hunt > Loot Filter)."] = "Configure no Loot Filter (Hunt > Loot Filter).",
		["World buff active - %s"] = "World buff ativo - %s",
		["You have an unused name change: Character > Services."] =
			"Você tem uma troca de nome sem usar: Character > Services.",
		["You have an unused vocation change: Character > Services."] =
			"Você tem uma troca de vocação sem usar: Character > Services.",
		["No world buff is active. Anyone can start one in the store (World Buffs)."] =
			"Nenhum world buff está ativo. Qualquer um pode começar um na loja (World Buffs).",
		["Active world buffs:\n%s"] = "World buffs ativos:\n%s",
		["You are exhausted."] = "Você está exausto.",
		["The scroll crumbles to dust."] = "O pergaminho vira pó.",
		["Your scroll has %d use left."] = "Seu pergaminho tem %d uso restante.",
		["Your scroll has %d uses left."] = "Seu pergaminho tem %d usos restantes.",
		["You need a Name Change from the store first."] = "Você precisa de um Name Change da loja primeiro.",
		["Type the new name (3-20 letters, single spaces, in a protection zone, out of combat). You will be logged out and log in with the new name."] =
			"Digite o novo nome (3-20 letras, espaços simples, em zona de proteção, fora de combate). Você será desconectado e entra com o novo nome.",
		["That is already your name."] = "Esse já é o seu nome.",
		["That name is already taken."] = "Esse nome já está em uso.",
		["You cannot change your name in combat."] = "Você não pode trocar de nome em combate.",
		["Go to a protection zone (a temple or a depot) first."] =
			"Vá para uma zona de proteção (um templo ou um depot) primeiro.",
		["Your name is now %s. You will be logged out: log in as %s."] =
			"Seu nome agora é %s. Você será desconectado: entre como %s.",
		["Your name is now %s.\nYou will be logged out now. Log in again with the new name."] =
			"Seu nome agora é %s.\nVocê será desconectado agora. Entre de novo com o novo nome.",
		["You need a Vocation Change from the store first."] = "Você precisa de um Vocation Change da loja primeiro.",
		["Choose one of: %s. %s"] = "Escolha um destes: %s. %s",
		["That vocation does not exist on this server."] = "Essa vocação não existe neste servidor.",
		["That class is locked. Unlock it in the store."] = "Essa classe está bloqueada. Desbloqueie na loja.",
		["%s Your Vocation Change is kept."] = "%s Seu Vocation Change foi mantido.",
		["You cannot change your vocation in combat."] = "Você não pode trocar de vocação em combate.",
		["You are now %s. Health, mana and capacity follow the new vocation; skills and magic level are kept; your passive tree was reset for free. Relog if anything looks stale."] =
			"Agora você é %s. Vida, mana e capacidade seguem a nova vocação; skills e magic level ficam; sua árvore passiva foi zerada de graça. Relogue se algo parecer desatualizado.",
		["Your spellbook now lists the spells of your new class. Spells of the old class no longer work: replace them on your action bar, or press Auto setup in the Helper."] =
			"Seu Spellbook agora lista as magias da sua nova classe. As magias da classe antiga não funcionam mais: troque-as na sua barra de ação ou use o Auto setup no Helper.",

		-- New players: the welcome, the kit, the level gifts and the tutorial island (newplayer.lua, newplayer_core.lua, newplayer_tutorial.lua, newplayer_config.lua)
		["Welcome to Cinders of Chaos"] = "Bem-vindo a Cinders of Chaos",
		["Welcome, %s the %s.\n\nYour starter kit is in your backpack. Next steps:\n- Character > Spellbook (Alt+S): every spell of your class and what it does.\n- The passive tree (top menu, Character): a point every 4 levels past level 8.\n- Adventure > Bounty Board: daily contracts that pay gold and Orbs of Upheaval.\n- The store (top menu, Economy): temple scrolls, stamina and services.\n- Cinderhold is the main city: the two great teleports north of its temple lead to the teleport room, a portal to a hunt of every level.\n- The top menu holds every game window: dungeons, the tower, dailies, bank and stash.\n\n%s"] =
			"Bem-vindo, %s, o %s.\n\nSeu kit inicial está na sua mochila. Próximos passos:\n- Character > Spellbook (Alt+S): todas as magias da sua classe e o que cada uma faz.\n- A árvore passiva (menu do topo, Character): um ponto a cada 4 níveis acima do nível 8.\n- Adventure > Bounty Board: contratos diários que pagam ouro e Orbs of Upheaval.\n- A loja (menu do topo, Economy): pergaminhos do templo, stamina e serviços.\n- Cinderhold é a cidade principal: os dois grandes teleportes ao norte do templo levam à sala de teleportes, um portal para uma caçada de cada nível.\n- O menu do topo tem todas as janelas do jogo: dungeons, a torre, as diárias, o banco e o stash.\n\n%s",
		["Welcome to Cinders of Chaos! Your kit is in your backpack. Everything else is in the menu at the top."] =
			"Bem-vindo a Cinders of Chaos! Seu kit está na sua mochila. Todo o resto está no menu do topo.",
		["A gift waits for you at level %s."] = "Um presente espera por você no nível %s.",
		["Gifts wait for you at levels %s and %s."] = "Presentes esperam por você nos níveis %s e %s.",
		["You received the %s starter kit.%s"] = "Você recebeu o kit inicial de %s.%s",
		[" Some of it did not fit: it is in your inbox."] = " Parte dele não coube: está na sua caixa de entrada.",
		["Level %d gift: %s.%s"] = "Presente do nível %d: %s.%s",
		["Ok"] = "Ok",
		["Skip tutorial"] = "Pular tutorial",
		["Skip"] = "Pular",
		["Stay"] = "Ficar",
		["Skip the tutorial?"] = "Pular o tutorial?",
		["You leave the island at once and get the rest of your starter kit at the temple of Cinderhold. You cannot come back."] =
			"Você sai da ilha na hora e recebe o resto do seu kit inicial no templo de Cinderhold. Não dá para voltar.",
		["Start tutorial"] = "Começar tutorial",
		["The tutorial island is closed: you start in Cinderhold at level 8 with your full kit."] =
			"A ilha do tutorial está fechada: você começa em Cinderhold no nível 8 com seu kit completo.",
		["Welcome to Cinders of Chaos! You start in Cinderhold at level 8, wearing your kit. Set up your helper in one click."] =
			"Bem-vindo a Cinders of Chaos! Você começa em Cinderhold no nível 8, usando seu kit. Configure seu helper com um clique.",
		["Set up your helper in one click: press Auto setup."] = "Configure seu helper com um clique: aperte Configuração automática.",
		["Skip to Cinderhold"] = "Pular para Cinderhold",
		["Welcome to the Isle of First Blood"] = "Bem-vindo à Isle of First Blood",
		["You are wearing your class's starter gear, with your Everfull health and mana potions in your backpack.\n\nFive short stations (5 to 10 minutes, at most %d) teach fighting, spells, the passive tree and orbs. At the end you arrive at the temple of Cinderhold, the main city, with the rest of your kit and gold.\n\nPlayed before? Skip to Cinderhold now: you get the same kit. You can also skip later with the goblin statue beside you or Character > Services > Leave Tutorial."] =
			"Você está usando o equipamento inicial da sua classe, com suas poções Everfull de vida e de mana na mochila.\n\nCinco estações curtas (5 a 10 minutos, no máximo %d) ensinam a lutar, as magias, a árvore passiva e os orbs. No fim você chega ao templo de Cinderhold, a cidade principal, com o resto do seu kit e ouro.\n\nJá jogou antes? Pule para Cinderhold agora: você recebe o mesmo kit. Também dá para pular depois com a estátua do goblin ao seu lado ou em Character > Services > Leave Tutorial.",
		["Tutorial or not? Press Skip to Cinderhold in the window, or use the goblin statue beside you."] =
			"Tutorial ou não? Aperte Pular para Cinderhold na janela, ou use a estátua do goblin ao seu lado.",
		["You are wearing the %s starter gear. Your Everfull potions are in your backpack."] =
			"Você está usando o equipamento inicial de %s. Suas poções Everfull estão na mochila.",
		["Station 1: Moving and fighting"] = "Estação 1: Andar e lutar",
		["Welcome to the Isle of First Blood.\n\nWalk with the arrow keys or by clicking the ground. Attack a creature by clicking it in the battle list or with ctrl + click / right click on it. Keep an eye on your health bar.\n\nTask: kill %d of the rats in this pen. The gate to the east opens when you are done.\n\nExperienced? Use the goblin statue (or Character > Services) to take your kit and leave at once."] =
			"Bem-vindo à Isle of First Blood.\n\nAnde com as setas ou clicando no chão. Ataque uma criatura clicando nela na battle list ou com ctrl + clique / clique direito nela. Fique de olho na sua barra de vida.\n\nTarefa: mate %d dos ratos deste cercado. O portão a leste abre quando você terminar.\n\nJá tem experiência? Use a estátua do goblin (ou Character > Services) para pegar seu kit e sair na hora.",
		["Station 1: kill %d rats in the first pen."] = "Estação 1: mate %d ratos no primeiro cercado.",
		["Station 2: Spells"] = "Estação 2: Magias",
		["Every class has its own spells. Character > Spellbook in the top menu (Alt+S) lists them with their words, mana, level and what they do.\n\nTask: open your spellbook (Character > Spellbook)%s"] =
			"Cada classe tem as próprias magias. Character > Spellbook no menu do topo (Alt+S) lista todas com as palavras, a mana, o nível e o que fazem.\n\nTarefa: abra seu spellbook (Character > Spellbook)%s",
		["Station 2: open your spellbook%s"] = "Estação 2: abra seu spellbook%s",
		[", then cast %s: say \"%s\" (it heals you)."] = ", depois use %s: diga \"%s\" (ela te cura).",
		[". Your class learns its first spell at level 20 (Shuriken Toss)."] =
			". Sua classe aprende a primeira magia no nível 20 (Shuriken Toss).",
		[" and say \"%s\""] = " e diga \"%s\"",
		["Station 3: The passive tree"] = "Estação 3: A árvore passiva",
		["Every 4 levels past level 8 you get a passive point. Spend them in the passive tree (top menu, Character > Passive Tree): start next to the centre and walk outwards. Big nodes are notables; the keystones at the far ends change how your class plays.\n\nTask: you get one free point now. Open the tree, click a node next to the centre and press Apply Plan."] =
			"A cada 4 níveis acima do nível 8 você ganha um ponto passivo. Gaste na árvore passiva (menu do topo, Character > Passive Tree): comece perto do centro e vá para fora. Nós grandes são notáveis; as keystones nas pontas mudam como sua classe joga.\n\nTarefa: você ganha um ponto grátis agora. Abra a árvore, clique num nó perto do centro e aperte Apply Plan.",
		["Station 3: spend your free passive point (Apply Plan)."] =
			"Estação 3: gaste seu ponto passivo grátis (Apply Plan).",
		["Station 4: Orbs and crafting"] = "Estação 4: Orbes e crafting",
		["Monsters drop orbs. An Orb of Upheaval rerolls the modifiers of an item with a rarity, an Orb of Fate rolls a new rarity, and the other orbs add or remove modifiers.%s\n\nTask: you got an Orb of Upheaval and a Common leather armor. Use the orb on the armor (right click the orb, Use with, then click the armor in your backpack)."] =
			"Monstros soltam orbes. Um Orb of Upheaval rerrola os modificadores de um item com raridade, um Orb of Fate rola uma raridade nova, e os outros orbes adicionam ou removem modificadores.%s\n\nTarefa: você ganhou um Orb of Upheaval e uma leather armor Common. Use o orbe na armadura (clique direito no orbe, Use with, depois clique na armadura na sua mochila).",
		["Station 4: use the Orb of Upheaval on the leather armor."] =
			"Estação 4: use o Orb of Upheaval na leather armor.",
		[" The crafting bench (Economy > Crafting Bench) shows every orb and what it does."] =
			" A Crafting Bench (Economy > Crafting Bench) mostra todos os orbes e o que cada um faz.",
		["Station 5: Keystones, bounties and the store"] = "Estação 5: Keystones, bounties e a loja",
		["Keystones are the big nodes at the edge of the passive tree: they change your class (Cleaving Arc, Ricochet, Arcane Echo...). Plan your path towards one.\n\nThe bounty board (Adventure > Bounty Board) gives daily contracts per level band that pay gold and orbs. The store (top menu, Economy) sells cosmetics, stamina and services. Dungeons, the Infinity Tower and the dailies are under Adventure in the top menu.\n\nStep into the forcefield to the east: you get your starter kit and arrive at the temple."] =
			"Keystones são os nós grandes na borda da árvore passiva: elas mudam sua classe (Cleaving Arc, Ricochet, Arcane Echo...). Planeje seu caminho até uma.\n\nO Bounty Board (Adventure > Bounty Board) dá contratos diários por faixa de nível que pagam ouro e orbes. A loja (menu do topo, Economy) vende cosméticos, stamina e serviços. Dungeons, a Infinity Tower e as diárias ficam em Adventure no menu do topo.\n\nEntre no campo de força a leste: você recebe seu kit inicial e chega ao templo.",
		["Station 5: step into the forcefield to leave the island."] =
			"Estação 5: entre no campo de força para sair da ilha.",
		["Station %d done! The gate to the east is open."] = "Estação %d concluída! O portão a leste está aberto.",
		["Step into the forcefield to leave the island."] = "Entre no campo de força para sair da ilha.",
		["Well cast! Now open your spellbook: Character > Spellbook (Alt+S)."] =
			"Boa magia! Agora abra seu spellbook: Character > Spellbook (Alt+S).",
		["You received a free passive point."] = "Você recebeu um ponto passivo grátis.",
		["Your time on the tutorial island is up: here is your kit. Everything the island shows is also in the menu at the top."] =
			"Seu tempo na ilha do tutorial acabou: aqui está seu kit. Tudo o que a ilha mostra também está no menu do topo.",
		["You skipped the tutorial."] = "Você pulou o tutorial.",
		["You finished the tutorial. Good hunting!"] = "Você terminou o tutorial. Boa caçada!",
		["Tutorial: %s Use the angel statue to read the lesson again."] =
			"Tutorial: %s Use a estátua do anjo para ler a lição de novo.",
		["Rats killed: %d / %d"] = "Ratos mortos: %d / %d",
		["The island will not let you die: you are healed. Use your potions and spells in the real world!"] =
			"A ilha não deixa você morrer: você foi curado. Use suas poções e magias no mundo real!",
		["Now cast %s: say \"%s\"."] = "Agora use %s: diga \"%s\".",
		["Finish this station first. Use the angel statue to read the lesson again."] =
			"Termine esta estação primeiro. Use a estátua do anjo para ler a lição de novo.",
		["Finish the stations first."] = "Termine as estações primeiro.",
		["You are not in the tutorial."] = "Você não está no tutorial.",

		-- Instance limits: time warnings, busy instances, the waiting line, boss rooms (instance_limits.lua, instance_limits_core.lua)
		["under a minute"] = "menos de um minuto",
		["%s minutes left"] = "faltam %s minutos",
		["1 minute left"] = "falta 1 minuto",
		["1 second left"] = "falta 1 segundo",
		["%s seconds left"] = "faltam %s segundos",
		["All %s are busy."] = "Sem vaga livre em %s.",
		[" One frees up in under a minute."] = " Uma vaga fica livre em menos de um minuto.",
		[" Try again in %s."] = " Tente de novo em %s.",
		[" Try again in a moment."] = " Tente de novo daqui a pouco.",
		[" You are %s in line: you will be told when one is free."] =
			" Você é o %s da fila: vai ser avisado quando uma vaga ficar livre.",
		["instances"] = "instâncias",
		["rifts"] = "rifts",
		["trial chambers"] = "câmaras de trial",
		["halls of the Descent"] = "salões da Descent",
		["guild boss arenas"] = "arenas de guild boss",
		["tower arenas"] = "arenas da torre",
		["wings of the Sepulchre"] = "alas do Sepulchre",
		["Ascended arenas"] = "arenas Ascended",
		["%s: %s. Everyone inside is sent out when the time runs out."] =
			"%s: %s. Todos lá dentro saem quando o tempo acabar.",
		["Instance"] = "Instância",
		["Arena"] = "Arena",
		["Battleground"] = "Battleground",
		["Infinity Tower"] = "Infinity Tower",
		["Guild siege"] = "Guild siege",
		["Tutorial"] = "Tutorial",
		["A place in %s is free now. Go ahead before someone else takes it."] =
			"Abriu uma vaga: %s. Vá antes que outra pessoa pegue.",
		["the instance"] = "a instância",
		["the ascension trial rooms"] = "as salas do trial de ascensão",
		["the Ember Descent"] = "a Ember Descent",
		["the guild boss arenas"] = "as arenas de guild boss",
		["the Infinity Tower"] = "a Infinity Tower",
		["the rifts"] = "os rifts",
		["the trial chambers"] = "as câmaras de trial",
		["the Ascended arenas"] = "as arenas Ascended",
		["Your turn"] = "Sua vez",
		["Your run is still going: %s left."] = "Sua run continua: faltam %s.",
		["A group is fighting in there. The room frees up in %s at the latest."] =
			"Um grupo está lutando lá dentro. A sala fica livre em no máximo %s.",
		["%s: you have %s. Then everyone in the room is sent out."] =
			"%s: vocês têm %s. Depois todos na sala são mandados para fora.",
		["Time is up: you were sent out of the boss room."] =
			"O tempo acabou: você foi mandado para fora da sala do boss.",
		["A gamemaster closed the boss room."] = "Um gamemaster fechou a sala do boss.",
		["The boss room closes."] = "A sala do boss se fecha.",
		["The boss room closes for a restart."] = "A sala do boss se fecha para um reinício.",
		["The boss room you were in has closed: you are at its exit."] =
			"A sala do boss em que você estava fechou: você está na saída dela.",

		-- The ascension quest and the Ascendant Oracle (ascension_quest.lua, ascension_quest_core.lua, ascension_quest_config.lua, npc/scripts/ascendant_oracle.lua)
		["The veil parts for you, |PLAYERNAME|. I keep the road of {ascension}. Few walk it to the end."] =
			"O véu se abre para você, |PLAYERNAME|. Eu guardo a estrada da {ascension}. Poucos a percorrem até o fim.",
		["Walk carefully, |PLAYERNAME|. The road remembers."] = "Ande com cuidado, |PLAYERNAME|. A estrada se lembra.",
		["The veil closes."] = "O véu se fecha.",
		["The old rites of promotion are broken; no king or guild can grant what must be earned. At level %d, walk the road of {ascension} with me."] =
			"Os velhos ritos de promoção estão quebrados; nenhum rei ou guilda pode conceder o que precisa ser conquistado. No nível %d, percorra comigo a estrada da {ascension}.",
		["The veil is closed for now. Come back later."] = "O véu está fechado por enquanto. Volte mais tarde.",
		["You hear it too, then: the Calling. %s"] = "Então você também ouve: o Chamado. %s",
		["Before you choose, prove that you are worth a road at all. %s"] =
			"Antes de escolher, prove que você merece alguma estrada. %s",
		["When your strength is proven, I will open the {trial} for you. Ask me about your {ascension} at any time."] =
			"Quando sua força estiver provada, eu abro o {trial} para você. Pergunte sobre sua {ascension} quando quiser.",
		[" Only beasts of level %d and above are worthy of you."] = " Só feras de nível %d ou mais são dignas de você.",
		["You are still bleeding from your last attempt. Return in %s."] =
			"Você ainda sangra da última tentativa. Volte em %s.",
		["Your strength is proven. Beyond the veil waits the %s. %s Step through when you are ready."] =
			"Sua força está provada. Além do véu espera o %s. %s Atravesse quando estiver pronto.",
		["So you have chosen. Confirm it, and it is done."] = "Então você escolheu. Confirme, e está feito.",
		["The Trial is behind you. Now choose. %s"] = "O Trial ficou para trás. Agora escolha. %s",
		["Your path holds no ascension, wanderer."] = "Seu caminho não tem ascensão, andarilho.",
		["You have ascended already. Your path is chosen; only the store's Vocation Change can alter it."] =
			"Você já ascendeu. Seu caminho está escolhido; só o Vocation Change da loja pode mudá-lo.",
		["You are not ready. Return when you have reached level %d."] =
			"Você não está pronto. Volte quando chegar ao nível %d.",
		["You have not passed the Trial yet."] = "Você ainda não passou no Trial.",
		["Choose: %s."] = "Escolha: %s.",
		["the %s"] = "o %s",
		["%s ({%s})."] = "%s ({%s}).",
		["The other is %s ({%s})."] = "O outro é %s ({%s}).",
		["Two roads rise from the %s. One is %s"] = "Duas estradas partem do %s. Uma é %s",
		["Prove your strength: slay rare and legendary beasts that are worthy of your level. A rare one counts %d, a legendary one %d. You have %d of %d."] =
			"Prove sua força: mate feras raras e lendárias dignas do seu nível. Uma rara vale %d, uma lendária %d. Você tem %d de %d.",
		["The Trial is closed to you until your strength is proven."] =
			"O Trial está fechado para você até sua força ser provada.",
		["You have passed the Trial already."] = "Você já passou no Trial.",
		["You are in a trial already."] = "Você já está em um trial.",
		["The Trial rejects you for now. Return in %s."] = "O Trial te rejeita por enquanto. Volte em %s.",
		["1 minute"] = "1 minuto",
		["%d minutes"] = "%d minutos",
		["1 second"] = "1 segundo",
		["%d seconds"] = "%d segundos",
		["Ascension is earned, not claimed. Speak with the %s in the Hall of Services."] =
			"A ascensão é conquistada, não reivindicada. Fale com o %s no Salão de Serviços.",
		["The %s waits beyond the veil. You go alone; you have %d seconds to break it.\n\n%s\n\nIf you fall, the Oracle pulls you back unharmed: no experience, no items lost. You may try again after %s."] =
			"O %s espera além do véu. Você vai sozinho; tem %d segundos para derrotá-lo.\n\n%s\n\nSe você cair, o Oracle te puxa de volta ileso: sem perder experiência nem itens. Você pode tentar de novo depois de %s.",
		["The Trial of Ascension"] = "O Trial of Ascension",
		["Enter"] = "Entrar",
		["Not yet"] = "Ainda não",
		["Choose the path you will walk. The choice is final; only the store's Vocation Change can alter it.\n\n%s"] =
			"Escolha o caminho que você vai seguir. A escolha é definitiva; só o Vocation Change da loja pode mudá-la.\n\n%s",
		["The Choice"] = "A Escolha",
		["Choose"] = "Escolher",
		["You will walk the path of %s.\n\nThis is final. Ascend?"] =
			"Você vai seguir o caminho de %s.\n\nIsto é definitivo. Ascender?",
		["Ascend as %s?"] = "Ascender como %s?",
		["Ascend"] = "Ascender",
		["Cancel"] = "Cancelar",
		["the Juggernaut, an unbreakable wall: taunts, damage reduction, a shield that blocks and reflects"] =
			"o Juggernaut, uma muralha inquebrável: provocações, redução de dano, um escudo que bloqueia e reflete",
		["the Berserker, two-handed fury: cleaving blows and a rage that grows as your blood runs out"] =
			"o Berserker, fúria de duas mãos: golpes que cortam em área e uma raiva que cresce conforme seu sangue se esvai",
		["the Deadeye, the single perfect shot: crossbows, marks and critical strikes"] =
			"o Deadeye, o tiro único e perfeito: bestas, marcas e acertos críticos",
		["the Beastmaster, never alone: beasts that fight beside you and arrows that splash"] =
			"o Beastmaster, nunca sozinho: feras que lutam ao seu lado e flechas que atingem em área",
		["the Elementalist, master of ruin: fire, ice and energy woven into great storms"] =
			"o Elementalist, mestre da ruína: fogo, gelo e energia tecidos em grandes tempestades",
		["the Illusionist, the hidden hand: strength for your allies, weakness for your foes, some healing"] =
			"o Illusionist, a mão oculta: força para os aliados, fraqueza para os inimigos, um pouco de cura",
		["the Ninja, two blades in the dark: very fast strikes and the shadow step"] =
			"o Ninja, duas lâminas no escuro: golpes muito rápidos e o passo das sombras",
		["the Samurai, one blade, one breath: slow heavy strikes, parries and counters"] =
			"o Samurai, uma lâmina, um fôlego: golpes lentos e pesados, aparadas e contra-ataques",
		["the Shadowfist, the killing touch: pressure points, flurries and chi spent in one burst"] =
			"o Shadowfist, o toque mortal: pontos de pressão, rajadas e chi gasto de uma vez",
		["the Iron Sage, the mountain that guards: chi wards on allies, stuns, the Mantra of Stone"] =
			"o Iron Sage, a montanha que protege: proteções de chi nos aliados, atordoamentos, o Mantra of Stone",
		["the Lich, the slow death: curses, life drain and corpses that burst"] =
			"o Lich, a morte lenta: maldições, dreno de vida e cadáveres que explodem",
		["the Bone Lord, master of the army: more skeletons, the Bone Golem, sacrifices"] =
			"o Bone Lord, mestre do exército: mais esqueletos, o Bone Golem, sacrifícios",
		["the Inquisitor, the burning judgement: holy fire on every foe around you"] =
			"o Inquisitor, o julgamento em chamas: fogo sagrado em todo inimigo ao seu redor",
		["the Sentinel, the shield of the faithful: a stronger aura, taunts and Lay on Hands"] =
			"o Sentinel, o escudo dos fiéis: uma aura mais forte, provocações e Lay on Hands",
		["It crushes those who stand their ground too long. Keep moving."] =
			"Ele esmaga quem fica parado tempo demais. Continue se movendo.",
		["Its hounds come in packs; a hunter who stands still becomes prey."] =
			"Seus cães vêm em matilha; um caçador parado vira presa.",
		["The ground under you will burn with runes. Read the marks and step aside."] =
			"O chão sob você vai arder com runas. Leia as marcas e saia de lado.",
		["Shadows do not stay still, and neither may you."] =
			"Sombras não ficam paradas, e você também não pode ficar.",
		["Stillness is the lesson it teaches the hard way: keep your feet moving."] =
			"Ficar parado é a lição que ele ensina do jeito difícil: mantenha os pés em movimento.",
		["It raises the dead around it. Break them before they bury you."] =
			"Ele ergue os mortos ao redor. Quebre-os antes que eles te enterrem.",
		["Its light burns where it falls, and it grows fierce as it fades."] =
			"Sua luz queima onde cai, e ele fica mais feroz conforme enfraquece.",
		["Keep moving and break what it calls."] = "Continue se movendo e quebre o que ele invoca.",
		["That is no ascended class."] = "Essa não é uma classe ascendida.",
		["You cannot ascend in combat."] = "Você não pode ascender em combate.",
		["Ascend before the %s."] = "Ascenda diante do %s.",
		["You have ascended: you are now %s. The choice is final; only the store's Vocation Change can undo it."] =
			"Você ascendeu: agora você é %s. A escolha é definitiva; só o Vocation Change da loja pode desfazê-la.",
		["You have ascended: %s."] = "Você ascendeu: %s.",
		["Proof of Strength: complete. Return to the %s and ask for the trial."] =
			"Proof of Strength: completa. Volte ao %s e peça o trial.",
		["Proof of Strength complete: the Trial awaits."] = "Proof of Strength completa: o Trial espera.",
		["Proof of Strength: %d / %d."] = "Proof of Strength: %d / %d.",
		["The %s falls. You have passed the Trial. The Oracle calls you back in %d seconds: make your choice."] =
			"O %s cai. Você passou no Trial. O Oracle te chama de volta em %d segundos: faça sua escolha.",
		["Trial passed: return to the Oracle and make your choice."] =
			"Trial vencido: volte ao Oracle e faça sua escolha.",
		["%s Nothing is lost. You may try again in %s."] = "%s Nada foi perdido. Você pode tentar de novo em %s.",
		["You have failed the Trial."] = "Você falhou no Trial.",
		["Trial failed: try again in %s."] = "Trial perdido: tente de novo em %s.",
		["The Trial could not begin. Nothing is lost."] = "O Trial não pôde começar. Nada foi perdido.",
		["A gamemaster closed the Trial. Nothing is lost."] = "Um gamemaster fechou o Trial. Nada foi perdido.",
		["The guardian did not answer the call. Nothing is lost; please tell the staff."] =
			"O guardião não atendeu ao chamado. Nada foi perdido; avise a staff.",
		["You left the Trial."] = "Você saiu do Trial.",
		["Time is up: the %s still stands."] = "O tempo acabou: o %s continua de pé.",
		["You have fallen in the Trial. The Oracle pulls you back."] = "Você caiu no Trial. O Oracle te puxa de volta.",
		["The %s awakens. %s"] = "O %s desperta. %s",
		["The %s calls for aid!"] = "O %s chama reforços!",
		["Trial: %d seconds left."] = "Trial: faltam %d segundos.",
		["The ground trembles under you. Move!"] = "O chão treme sob você. Mexa-se!",
		["You cannot enter the Trial in combat."] = "Você não pode entrar no Trial em combate.",
		["The Trial is entered at the %s."] = "Entra-se no Trial pelo %s.",
		["Every trial chamber is in use. Try again in a moment."] =
			"Todas as câmaras de trial estão em uso. Tente de novo daqui a pouco.",
		["The trial chambers cannot be opened. Please tell the staff."] =
			"As câmaras de trial não podem ser abertas. Avise a staff.",
		["The Trial of Ascension: the %s comes in %d seconds. You have %d seconds to defeat it."] =
			"Trial of Ascension: o %s chega em %d segundos. Você tem %d segundos para derrotá-lo.",
		["The Oracle waits. Say 'choice' when you are ready."] =
			"O Oracle espera. Diga 'choice' quando estiver pronto.",
		["That path is not yours to walk."] = "Esse caminho não é seu.",
		["Ascension: %s"] = "Ascensão: %s",
		["not begun. Speak with the %s in the Hall of Services."] = "não começou. Fale com o %s no Salão de Serviços.",
		["Proof of Strength, %d / %d (rare and legendary monsters of level %d+)."] =
			"Proof of Strength, %d / %d (monstros raros e lendários de nível %d+).",
		["the Trial. Ask the %s for the trial."] = "o Trial. Peça o trial ao %s.",
		["the Choice. Tell the %s your choice."] = "a Escolha. Diga sua escolha ao %s.",
		["complete."] = "completa.",
		[" You may try again in %s."] = " Você pode tentar de novo em %s.",

		-- NPCs: XML greet / farewell / walk away / trade lines and dialogue (data/npc/*.xml, data/npc/scripts/*.lua; {keywords} stay English)
		["Back from the hunt, |PLAYERNAME|? I buy what you carry: ask for a {trade}. Gear with a rarity or a high item level pays more. I can {appraise} your bags. Uniques I leave to you."] =
			"De volta da caçada, |PLAYERNAME|? Eu compro o que você carrega: peça um {trade}. Equipamento com raridade ou item level alto vale mais. Posso fazer um {appraise} das suas bolsas. Únicos eu deixo com você.",
		["Bring me more, |PLAYERNAME|."] = "Traga mais, |PLAYERNAME|.",
		["Your loss."] = "Azar o seu.",
		["Only what you carry is listed. A rare copy pays its own price, whatever the list says."] =
			"Só aparece o que você carrega. Uma cópia rara paga o próprio preço, diga a lista o que disser.",
		["You carry nothing I buy. Coins, orbs, keys, quest items and store items stay with you; ores, herbs, hides and fish go to the Material Broker."] =
			"Você não carrega nada que eu compre. Moedas, orbes, chaves, itens de quest e itens da loja ficam com você; minérios, ervas, couros e peixes vão para o Material Broker.",
		["Sold %dx %s for %s gold."] = "Vendeu %dx %s por %s de ouro.",
		["Kept %d copy: locked, a unique (salvage it or sell it on the market) or a container that is not empty."] =
			"Guardou %d cópia: travada, um único (faça salvage ou venda no market) ou um recipiente que não está vazio.",
		["Kept %d copies: locked, a unique (salvage it or sell it on the market) or a container that is not empty."] =
			"Guardou %d cópias: travadas, únicos (faça salvage ou venda no market) ou recipientes que não estão vazios.",
		["You do not have this item."] = "Você não tem este item.",
		["Nothing in your bags that I buy."] = "Nada nas suas bolsas que eu compre.",
		["Loot Buyer: %s. Everything I buy in your bags: %s gold (locked items and uniques left out)."] =
			"Loot Buyer: %s. Tudo o que eu compro nas suas bolsas: %s de ouro (itens travados e únicos ficam de fora).",
		["All of it together: %s gold. The list is in your server log."] =
			"Tudo junto: %s de ouro. A lista está no seu server log.",
		["A unique? Keep it, salvage it or sell it on the market. I will not put a price on a thing like that."] =
			"Um único? Guarde, faça salvage ou venda no market. Eu não ponho preço numa coisa dessas.",
		["Orbs, coins, keys, tokens and shards are worth more to you than to me: trade orbs at the Orb Exchange."] =
			"Orbes, moedas, chaves, tokens e fragmentos valem mais para você do que para mim: troque orbes no Orb Exchange.",
		["The Material Broker pays better for what you gather; I leave those to him."] =
			"O Material Broker paga melhor pelo que você coleta; deixo isso com ele.",
		["A plain piece pays the listed price. Uncommon pays half again, magic three times, rare six, legendary twelve, divine twenty-four; each item level adds half a percent."] =
			"Uma peça comum paga o preço da lista. Incomum paga uma vez e meia, mágica três vezes, rara seis, lendária doze, divina vinte e quatro; cada item level soma meio por cento.",
		["Ore, herbs, hides and fish, |PLAYERNAME|: I pay for all of it. Ask me to {sell}, about this week's {demand}, or {trade} for tools."] =
			"Minério, ervas, couros e peixes, |PLAYERNAME|: eu pago por tudo. Peça para {sell}, pergunte a {demand} desta semana, ou faça {trade} por ferramentas.",
		["Come back with full bags, |PLAYERNAME|."] = "Volte com as bolsas cheias, |PLAYERNAME|.",
		["Hm. Another time."] = "Hm. Outra hora.",
		["Picks, sickles, knives and rods. Sell me what you gather with them: ask to {sell}."] =
			"Picaretas, foices, facas e varas. Venda para mim o que você coleta com elas: peça para {sell}.",
		["Show me what you have. My prices change every week, and I only take so much of one thing a day: see the ledger (Economy > Professions)."] =
			"Mostre o que você tem. Meus preços mudam toda semana, e eu só aceito certa quantidade de cada coisa por dia: veja o registro (Economy > Professions).",
		["A pick for the veins, a sickle for the herbs, an obsidian knife for hides and a rod for the water. Ask me to {trade}."] =
			"Uma picareta para os veios, uma foice para as ervas, uma faca de obsidiana para os couros e uma vara para a água. Peça um {trade}.",
		["Sealed crates, |PLAYERNAME|. Made for your hands, opened by your gold. Care to {gamble}? Ask about the {odds}, or when the {crates} change."] =
			"Caixas lacradas, |PLAYERNAME|. Feitas para as suas mãos, abertas pelo seu ouro. Quer {gamble}? Pergunte sobre as {odds}, ou quando as {crates} mudam.",
		["Luck is a fickle ember, |PLAYERNAME|."] = "A sorte é uma brasa inconstante, |PLAYERNAME|.",
		["The crates will wait. They always do."] = "As caixas vão esperar. Sempre esperam.",
		["Pick a crate. You see the make and the craft, never the luck inside. That you pay to learn."] =
			"Escolha uma caixa. Você vê o modelo e o trabalho, nunca a sorte lá dentro. Isso você paga para descobrir.",
		["Every crate holds something touched by Chaos, never plain iron. Most are modest. One in twenty-five is Legendary or better, no more than the beasts give. The window lists the odds; I hide nothing but the crate."] =
			"Toda caixa guarda algo tocado pelo Chaos, nunca ferro comum. A maioria é modesta. Uma em vinte e cinco é Lendária ou melhor, não mais do que as feras dão. A janela mostra as chances; eu só escondo a caixa.",
		["New crates every %d hours, on the mark: midnight, four, eight and so on, by the temple bell. For a price I fetch fresh ones sooner."] =
			"Caixas novas a cada %d horas, na hora cheia: meia-noite, quatro, oito e assim por diante, pelo sino do templo. Por um preço eu trago novas antes.",
		["Mordecai Ashwager. I sell what the Chaos left sealed. Ask me to {gamble}."] =
			"Mordecai Ashwager. Eu vendo o que o Chaos deixou lacrado. Peça para {gamble}.",
		["Hush, |PLAYERNAME|. Listen: the rifts are singing. The Veiled Choir hears all who come. Ask about {contracts}, the {quartermaster} or the {lore}."] =
			"Silêncio, |PLAYERNAME|. Escute: os rifts estão cantando. The Veiled Choir ouve todos que chegam. Pergunte sobre {contracts}, o {quartermaster} ou a {lore}.",
		["The song goes with you, |PLAYERNAME|."] = "A canção vai com você, |PLAYERNAME|.",
		["The veil falls."] = "O véu cai.",
		["Root and thorn, |PLAYERNAME|. The Thornbound Circle needs hands that do not flinch. Ask about {contracts}, the {quartermaster} or the {lore}."] =
			"Raiz e espinho, |PLAYERNAME|. The Thornbound Circle precisa de mãos que não tremem. Pergunte sobre {contracts}, o {quartermaster} ou a {lore}.",
		["Walk lightly, |PLAYERNAME|."] = "Pise leve, |PLAYERNAME|.",
		["The leaves close."] = "As folhas se fecham.",
		["Mind the sparks, |PLAYERNAME|. The Cinderforge Compact pays for good work. Ask about {contracts}, the {quartermaster} or the {lore}."] =
			"Cuidado com as faíscas, |PLAYERNAME|. The Cinderforge Compact paga por trabalho bem feito. Pergunte sobre {contracts}, o {quartermaster} ou a {lore}.",
		["Steel holds, |PLAYERNAME|."] = "O aço aguenta, |PLAYERNAME|.",
		["Back to the anvil, then."] = "De volta à bigorna, então.",
		["Ashes to ashes, |PLAYERNAME|. The Ashen Vigil keeps the pyres. Ask me about our {contracts}, the {quartermaster} or the {lore} of the Vigil."] =
			"Cinzas às cinzas, |PLAYERNAME|. The Ashen Vigil guarda as piras. Pergunte sobre nossos {contracts}, o {quartermaster} ou a {lore} da Vigil.",
		["Keep your torch lit, |PLAYERNAME|."] = "Mantenha sua tocha acesa, |PLAYERNAME|.",
		["The bell tolls on."] = "O sino continua a tocar.",
		["Here is what %s asks, and what it gives. Your contracts, your standing and my stores are in the ledger (Adventure > Factions). Bring %s and deliveries to me."] =
			"Eis o que %s pede, e o que dá. Seus contratos, sua reputação e meu estoque estão no registro (Adventure > Factions). Traga %s e as entregas para mim.",
		["Every favour you do %s is a favour we remember, and the same is true the other way. Choose, or work twice as hard."] =
			"Todo favor que você faz para %s é um favor que lembramos, e o contrário também vale. Escolha, ou trabalhe em dobro.",
		["Pyre-wardens who burn what will not stay dead. Since the Cinders fell, their bells ring at every grave that stirs, and they ring for the rifts too."] =
			"Guardiões das piras que queimam o que não fica morto. Desde que as Cinders caíram, seus sinos tocam a cada túmulo que se mexe, e tocam pelos rifts também.",
		["Smiths and sellswords sworn to the obsidian forges. They pay in steel for whatever others fear to dig up, and they fear nothing that burns."] =
			"Ferreiros e mercenários jurados às forjas de obsidiana. Pagam em aço por tudo o que os outros temem desenterrar, e não temem nada que queima.",
		["Seers who listen at the rifts and sing back. What answers, they bargain with. The Vigil calls it heresy; the Choir calls it knowledge."] =
			"Videntes que escutam os rifts e cantam de volta. Com o que responde, eles negociam. A Vigil chama isso de heresia; o Choir chama de conhecimento.",
		["Wardens of root and rot. They cut the blight out of the Forsaken Sanctum before it reaches the fields, and they hate the furnaces that eat their forests."] =
			"Guardiões da raiz e da podridão. Cortam a praga do Forsaken Sanctum antes que ela chegue aos campos, e odeiam as fornalhas que devoram suas florestas.",
		["Welcome, |PLAYERNAME|. Every road of power asks a price. I keep the doors of the {trials}."] =
			"Bem-vindo, |PLAYERNAME|. Toda estrada de poder cobra um preço. Eu guardo as portas dos {trials}.",
		["May the trials find you ready, |PLAYERNAME|."] = "Que os trials te encontrem pronto, |PLAYERNAME|.",
		["The doors close."] = "As portas se fecham.",
		["The doors are closed to you for now."] = "As portas estão fechadas para você por enquanto.",
		["Choose your difficulty. Each cleared difficulty opens a pair of special nodes for your vocation."] =
			"Escolha sua dificuldade. Cada dificuldade vencida abre um par de nós especiais para a sua vocação.",
		[" (cleared)"] = " (vencido)",
		["%s: level %d, %d minutes, %d lives%s"] = "%s: nível %d, %d minutos, %d vidas%s",
		["%s\n\n%s\n\nYou go alone. A fall costs a life, not your experience or items; nothing is lost if you fail. The first clear of each difficulty opens a pair of special nodes for your vocation (choose them in the passive tree window, Trials).\n\n%s"] =
			"%s\n\n%s\n\nVocê vai sozinho. Uma queda custa uma vida, não sua experiência nem seus itens; nada é perdido se você falhar. A primeira vitória em cada dificuldade abre um par de nós especiais para a sua vocação (escolha na janela da árvore passiva, Trials).\n\n%s",
		["Trial of the %s"] = "Trial do %s",
		["Ah, |PLAYERNAME|! Fresh from the broken roads. Ask for a {trade}, I do not stay long."] =
			"Ah, |PLAYERNAME|! Recém-chegado das estradas quebradas. Peça um {trade}, eu não fico muito tempo.",
		["May the shards spare you, |PLAYERNAME|."] = "Que os fragmentos te poupem, |PLAYERNAME|.",
		["Your loss, wanderer."] = "Azar o seu, andarilho.",
		["Orbs and oddities, found where the world bleeds. Look, but be quick."] =
			"Orbes e curiosidades, achados onde o mundo sangra. Olhe, mas seja rápido.",
		["Season characters gain nothing from a %s, so I will not sell you one."] =
			"Personagens de temporada não ganham nada com um %s, então não vou te vender um.",
		["Season characters cannot buy a %s."] = "Personagens de temporada não podem comprar um %s.",
		["Write what you saw, |PLAYERNAME|. Ink outlasts us."] =
			"Escreva o que você viu, |PLAYERNAME|. A tinta dura mais que nós.",
		["Another page left blank."] = "Mais uma página deixada em branco.",

		-- The Vocation Trials (trials.lua, trials_core.lua, trials_config.lua stories)
		["That is not a choice of your trial nodes."] = "Essa não é uma escolha dos seus nós de trial.",
		["Locked: clear your trial on %s first."] = "Bloqueado: vença seu trial no %s primeiro.",
		["a higher difficulty"] = "uma dificuldade maior",
		["Nothing is chosen there."] = "Nada está escolhido aí.",
		["You already hold that node."] = "Você já tem esse nó.",
		["Changing a held node costs a Trial Token. Clear a trial you have already cleared to earn one."] =
			"Trocar um nó escolhido custa um Trial Token. Vença de novo um trial que você já venceu para ganhar um.",
		["That difficulty does not exist."] = "Essa dificuldade não existe.",
		["Clear the trial on %s first."] = "Vença o trial no %s primeiro.",
		["%s needs level %d."] = "%s precisa do nível %d.",
		["The trial is still closed to you for %d seconds."] = "O trial ainda está fechado para você por %d segundos.",
		["Vocation Trials"] = "Vocation Trials",
		["The Vocation Trials are closed."] = "Os Vocation Trials estão fechados.",
		["Your vocation has no trial."] = "Sua vocação não tem trial.",
		["You cannot change your nodes during a trial."] = "Você não pode trocar seus nós durante um trial.",
		["You cannot change a held node in combat."] = "Você não pode trocar um nó escolhido em combate.",
		["You need a Trial Token."] = "Você precisa de um Trial Token.",
		["Changing a node costs %d gold coins and a Trial Token."] =
			"Trocar um nó custa %d gold coins e um Trial Token.",
		["The choice was given up."] = "A escolha foi desfeita.",
		["The choice was given up (1 Trial Token and %d gold coins)."] =
			"A escolha foi desfeita (1 Trial Token e %d gold coins).",
		["%s is yours."] = "%s é seu.",
		["%s is yours (1 Trial Token and %d gold coins)."] = "%s é seu (1 Trial Token e %d gold coins).",
		["Wave %d of %d."] = "Onda %d de %d.",
		["The seals burn. Break them in the order the Keeper names, standing on each until it gives."] =
			"Os selos ardem. Quebre-os na ordem que o Keeper disser, ficando sobre cada um até ele ceder.",
		["Marked targets come one after another. Kill each before it slips away."] =
			"Alvos marcados vêm um depois do outro. Mate cada um antes que escape.",
		["%s awakens. %s"] = "%s desperta. %s",
		["%s calls for aid!"] = "%s chama reforços!",
		["The fire gathers! Stand next to a sanctuary light."] =
			"O fogo se junta! Fique ao lado de uma luz do santuário.",
		["The %s seal breaks."] = "O selo de %s se quebra.",
		["fire"] = "fogo",
		["ice"] = "gelo",
		["energy"] = "energia",
		["earth"] = "terra",
		["The wrong seal rebukes you!"] = "O selo errado te castiga!",
		["The mark got away! %d seconds are lost."] = "A marca escapou! %d segundos foram perdidos.",
		["First clear on %s: the %s pair of nodes opens (%s or %s)."] =
			"Primeira vitória no %s: o %s par de nós se abre (%s ou %s).",
		["first"] = "primeiro",
		["second"] = "segundo",
		["third"] = "terceiro",
		["Cleared again: +%s Trial Token."] = "Vencido de novo: +%s Trial Token.",
		["Cleared again: +%s Trial Tokens."] = "Vencido de novo: +%s Trial Tokens.",
		["%d gold coins to your bank, %d Orb(s) of Upheaval, %d Orb(s) of Fate%s."] =
			"%d gold coins no seu banco, %d Orb(s) of Upheaval, %d Orb(s) of Fate%s.",
		[" (some in your inbox)"] = " (parte na sua caixa de entrada)",
		["The weekly repeat rewards are used up; the token is yours."] =
			"As recompensas semanais de repetição acabaram; o token é seu.",
		["The trial could not begin. Nothing is lost."] = "O trial não pôde começar. Nada foi perdido.",
		["%s Nothing is lost."] = "%s Nada foi perdido.",
		["You have failed the trial."] = "Você falhou no trial.",
		["A gamemaster closed the trial."] = "Um gamemaster fechou o trial.",
		["You left the trial."] = "Você saiu do trial.",
		["Time is up: the trial is lost."] = "O tempo acabou: o trial está perdido.",
		["You have fallen with no lives left."] = "Você caiu sem vidas restantes.",
		["You fall! %d life left. The monsters cannot touch you for %d seconds."] =
			"Você caiu! Resta %d vida. Os monstros não podem te tocar por %d segundos.",
		["You fall! %d lives left. The monsters cannot touch you for %d seconds."] =
			"Você caiu! Restam %d vidas. Os monstros não podem te tocar por %d segundos.",
		["You are busy in %s."] = "Você está ocupado em %s.",
		["You cannot enter a trial in combat."] = "Você não pode entrar em um trial em combate.",
		["Enter the trial from a protection zone."] = "Entre no trial a partir de uma zona de proteção.",
		["Characters that share a connection with another character cannot enter a trial."] =
			"Personagens que dividem a conexão com outro personagem não podem entrar em um trial.",
		["The trial is entered at the %s."] = "Entra-se no trial pelo %s.",
		["%s (%s): %d minutes, %d life. %s"] = "%s (%s): %d minutos, %d vida. %s",
		["%s (%s): %d minutes, %d lives. %s"] = "%s (%s): %d minutos, %d vidas. %s",
		["Your last trial was cut short by a server restart. It does not count against you; no waiting is needed."] =
			"Seu último trial foi interrompido por um reinício do servidor. Ele não conta contra você; não é preciso esperar.",
		["Waves of iron-bound thralls, then the Champion. Do not stand still against it: it crushes whoever plants their feet."] =
			"Ondas de servos acorrentados em ferro, depois o Champion. Não fique parado contra ele: ele esmaga quem finca os pés.",
		["A fast pack, then the Stalker, whose volleys mark the ground before they land. Read the marks."] =
			"Uma matilha rápida, depois o Stalker, cujas rajadas marcam o chão antes de cair. Leia as marcas.",
		["Four seals burn in four colours. Break them in the order the Keeper speaks, or the wrong one will punish you."] =
			"Quatro selos ardem em quatro cores. Quebre-os na ordem que o Keeper disser, ou o errado vai te punir.",
		["Marked cutthroats come one after another, fast. Each that slips away costs you time. Then the Master."] =
			"Assassinos marcados vêm um depois do outro, rápido. Cada um que escapa te custa tempo. Depois, o Master.",
		["Two waves of acolytes, then the Warden. Stillness is the lesson: keep your feet moving against it."] =
			"Duas ondas de acólitos, depois o Warden. Ficar parado é a lição: mantenha os pés em movimento contra ele.",
		["The dead here stand up a second time. Break them again, and the Collector who calls for more."] =
			"Aqui os mortos se levantam uma segunda vez. Quebre-os de novo, e o Collector que chama mais.",
		["The fire sweeps the whole room. Stand beside a sanctuary light when it breaks, and keep fighting between the waves."] =
			"O fogo varre a sala inteira. Fique ao lado de uma luz do santuário quando ele explodir, e continue lutando entre as ondas.",

		-- Achievements: categories, descriptions (achievements_data.lua; names and titles stay English), window and toasts (achievements_core.lua)
		["Combat & Leveling"] = "Combate e Níveis",
		["Monsters"] = "Monstros",
		["World Bosses"] = "World Bosses",
		["Rifts"] = "Rifts",
		["Raids"] = "Raids",
		["Bounties"] = "Bounties",
		["Items & Crafting"] = "Itens e Crafting",
		["PvP"] = "PvP",
		["Exploration & Social"] = "Exploração e Social",
		["Secrets"] = "Segredos",
		["A hidden achievement. Keep playing to find it."] = "Uma conquista oculta. Continue jogando para descobri-la.",
		["%s gold"] = "%s de ouro",
		["outfit %s"] = "outfit %s",
		["outfit %s with addons"] = "outfit %s com addons",
		["mount %s"] = "montaria %s",
		["portal style %s"] = "estilo de portal %s",
		["+%d point."] = "+%d ponto.",
		["+%d points."] = "+%d pontos.",
		["Title: %s."] = "Título: %s.",
		["Reward: %s."] = "Recompensa: %s.",
		["+%d points: %s%s."] = "+%d pontos: %s%s.",
		[" and %s more"] = " e mais %s",
		[" Rewards: %s%s."] = " Recompensas: %s%s.",
		["%s achievements unlocked"] = "%s conquistas desbloqueadas",
		["Achievement unlocked: %s (+%d points)."] = "Conquista desbloqueada: %s (+%d pontos).",
		["Title: %s (pick it in the Achievements window)."] = "Título: %s (escolha na janela de Achievements).",
		["The reward could not be given; tell the staff."] = "A recompensa não pôde ser entregue; avise a staff.",
		["Class unlocked for your account: %s."] = "Classe desbloqueada para a sua conta: %s.",
		["Class unlocked"] = "Classe desbloqueada",
		["%s is open to every character of your account."] = "%s está liberada para todos os personagens da sua conta.",
		[" (your backpack was full: see your inbox)"] = " (sua mochila estava cheia: veja sua caixa de entrada)",
		["Reach level 50."] = "Alcance o nível 50.",
		["Reach level 100."] = "Alcance o nível 100.",
		["Reach level 200."] = "Alcance o nível 200.",
		["Reach level 300."] = "Alcance o nível 300.",
		["Reach level 500."] = "Alcance o nível 500.",
		["Reach level 700."] = "Alcance o nível 700.",
		["Reach level 1000."] = "Alcance o nível 1000.",
		["Ascend into one of your class's two paths."] = "Ascenda para um dos dois caminhos da sua classe.",
		["Clear your vocation's trial on Normal."] = "Vença o trial da sua vocação no Normal.",
		["Clear your vocation's trial on Cruel."] = "Vença o trial da sua vocação no Cruel.",
		["Clear your vocation's trial on Merciless."] = "Vença o trial da sua vocação no Merciless.",
		["Hold a special node from every pair of your vocation."] = "Tenha um nó especial de cada par da sua vocação.",
		["Clear a trial 10 times."] = "Vença um trial 10 vezes.",
		["Change a held trial node for another."] = "Troque um nó de trial escolhido por outro.",
		["Earn your first Paragon level."] = "Ganhe seu primeiro nível Paragon.",
		["Reach Paragon level 50."] = "Alcance o nível Paragon 50.",
		["Reach Paragon level 100."] = "Alcance o nível Paragon 100.",
		["Reach Paragon level 282: every Paragon stat maxed."] =
			"Alcance o nível Paragon 282: todos os atributos Paragon no máximo.",
		["Kill a magic monster."] = "Mate um monstro mágico.",
		["Kill 250 magic monsters."] = "Mate 250 monstros mágicos.",
		["Kill a rare monster."] = "Mate um monstro raro.",
		["Kill 100 rare monsters."] = "Mate 100 monstros raros.",
		["Kill a legendary monster."] = "Mate um monstro lendário.",
		["Kill 25 legendary monsters."] = "Mate 25 monstros lendários.",
		["Kill 250 legendary monsters."] = "Mate 250 monstros lendários.",
		["Kill 1,000 magic, rare or legendary monsters."] = "Mate 1.000 monstros mágicos, raros ou lendários.",
		["Kill 10,000 magic, rare or legendary monsters."] = "Mate 10.000 monstros mágicos, raros ou lendários.",
		["Survive an ambush: kill the monster that ambushed you."] =
			"Sobreviva a uma emboscada: mate o monstro que te emboscou.",
		["Kill 50 ambushing monsters."] = "Mate 50 monstros de emboscada.",
		["Kill 250 ambushing monsters."] = "Mate 250 monstros de emboscada.",
		["Slay a Treasure Goblin before it escapes."] = "Mate um Treasure Goblin antes que ele fuja.",
		["Slay 10 Treasure Goblins."] = "Mate 10 Treasure Goblins.",
		["Slay 50 Treasure Goblins."] = "Mate 50 Treasure Goblins.",
		["Hit a Treasure Goblin and watch it escape anyway."] =
			"Acerte um Treasure Goblin e veja ele fugir mesmo assim.",
		["Discover 25 bestiary entries."] = "Descubra 25 entradas do bestiário.",
		["Complete a bestiary entry."] = "Complete uma entrada do bestiário.",
		["Complete 50 bestiary entries."] = "Complete 50 entradas do bestiário.",
		["Complete 50 kill tasks."] = "Complete 50 kill tasks.",
		["Help slay Kaelgor the Infernal Warlord."] = "Ajude a matar Kaelgor the Infernal Warlord.",
		["Help slay Skaldra the Rime Queen."] = "Ajude a matar Skaldra the Rime Queen.",
		["Help slay The Rotmother."] = "Ajude a matar The Rotmother.",
		["Help slay Nyxareth the Void Archon."] = "Ajude a matar Nyxareth the Void Archon.",
		["Help slay Vharok the Blood Colossus."] = "Ajude a matar Vharok the Blood Colossus.",
		["Help slay each of the five world bosses."] = "Ajude a matar cada um dos cinco world bosses.",
		["Deal the most damage of everyone to a world boss."] = "Cause mais dano do que todos a um world boss.",
		["Deal the most damage to a world boss 5 times."] = "Cause o maior dano a um world boss 5 vezes.",
		["Be rewarded at 10 world boss kills."] = "Seja recompensado em 10 mortes de world boss.",
		["Be rewarded at 50 world boss kills."] = "Seja recompensado em 50 mortes de world boss.",
		["Heal the most of everyone at a world boss kill."] = "Cure mais do que todos na morte de um world boss.",
		["Take the most boss damage and live, at a world boss kill."] =
			"Receba o maior dano do boss e sobreviva, na morte de um world boss.",
		["Place in the top 3 for healing or tanking at 5 world boss kills."] =
			"Fique no top 3 de cura ou tank em 5 mortes de world boss.",
		["Seal a rift."] = "Sele um rift.",
		["Seal a tier 5 rift."] = "Sele um rift tier 5.",
		["Seal a tier 10 rift."] = "Sele um rift tier 10.",
		["Seal a tier 15 rift."] = "Sele um rift tier 15.",
		["Seal 25 rifts."] = "Sele 25 rifts.",
		["Seal 100 rifts."] = "Sele 100 rifts.",
		["Seal a rift with everyone who entered still standing."] = "Sele um rift com todos que entraram ainda de pé.",
		["Seal 10 rifts without losing anyone."] = "Sele 10 rifts sem perder ninguém.",
		["Seal a rift with three modifiers."] = "Sele um rift com três modificadores.",
		["Seal a rift with the Reflection modifier."] = "Sele um rift com o modificador Reflection.",
		["Seal a rift with the Withering modifier."] = "Sele um rift com o modificador Withering.",
		["Seal a rift with the Brutality modifier."] = "Sele um rift com o modificador Brutality.",
		["Seal a rift with the Swarm modifier."] = "Sele um rift com o modificador Swarm.",
		["Slay an omen guardian."] = "Mate um guardião de omen.",
		["Slay Sangrith the Bloodmoon Herald."] = "Mate Sangrith the Bloodmoon Herald.",
		["Slay Morvane the Hollow Crown."] = "Mate Morvane the Hollow Crown.",
		["Slay Thalcyra the Stormbound Seer."] = "Mate Thalcyra the Stormbound Seer.",
		["Slay 10 omen guardians."] = "Mate 10 guardiões de omen.",
		["Slay an Ascended Omen."] = "Mate um Ascended Omen.",
		["Slay Ascended Sangrith."] = "Mate Ascended Sangrith.",
		["Slay Ascended Morvane."] = "Mate Ascended Morvane.",
		["Slay Ascended Thalcyra."] = "Mate Ascended Thalcyra.",
		["Slay all three Ascended Omens."] = "Mate os três Ascended Omens.",
		["Slay Ysgrath the Cinderheart."] = "Mate Ysgrath the Cinderheart.",
		["Slay the Cinderheart alone."] = "Mate o Cinderheart sozinho.",
		["Slay the Cinderheart without losing a life."] = "Mate o Cinderheart sem perder uma vida.",
		["Slay the Cinderheart 10 times."] = "Mate o Cinderheart 10 vezes.",
		["Slay a boss of the Ashen Sepulchre."] = "Mate um boss do Ashen Sepulchre.",
		["Slay Gravewarden Ulthar."] = "Mate Gravewarden Ulthar.",
		["Slay Morwen the Ash-Sister."] = "Mate Morwen the Ash-Sister.",
		["Slay the Marrow Colossus."] = "Mate o Marrow Colossus.",
		["Slay Vhoss the Hexmaw."] = "Mate Vhoss the Hexmaw.",
		["Slay Varkhul the Ashen Sovereign."] = "Mate Varkhul the Ashen Sovereign.",
		["Slay Varkhul with nobody falling in the fight."] = "Mate Varkhul sem ninguém cair na luta.",
		["Clear the Sepulchre in one sitting in under 30 minutes."] =
			"Limpe o Sepulchre de uma vez em menos de 30 minutos.",
		["Slay Varkhul 10 times."] = "Mate Varkhul 10 vezes.",
		["Clear The Marrow Crypts."] = "Limpe The Marrow Crypts.",
		["Clear The Iron Crucible."] = "Limpe The Iron Crucible.",
		["Clear The Fallen Sanctum."] = "Limpe The Fallen Sanctum.",
		["Clear The Pyre Throne."] = "Limpe The Pyre Throne.",
		["Clear the four deep dungeons (Marrow Crypts, Iron Crucible, Fallen Sanctum, Pyre Throne) on difficulty 6."] =
			"Limpe as quatro dungeons profundas (Marrow Crypts, Iron Crucible, Fallen Sanctum, Pyre Throne) na dificuldade 6.",
		["Complete a bounty contract."] = "Complete um contrato de bounty.",
		["Complete 25 bounty contracts."] = "Complete 25 contratos de bounty.",
		["Complete 100 bounty contracts."] = "Complete 100 contratos de bounty.",
		["Complete 500 bounty contracts."] = "Complete 500 contratos de bounty.",
		["Earn the weekly bounty chest."] = "Ganhe o baú semanal de bounty.",
		["Earn the weekly bounty chest 10 times."] = "Ganhe o baú semanal de bounty 10 vezes.",
		["Find a unique item."] = "Encontre um item único.",
		["Find 10 unique items."] = "Encontre 10 itens únicos.",
		["Find 50 unique items."] = "Encontre 50 itens únicos.",
		["Find a Legendary item."] = "Encontre um item Lendário.",
		["Find a Divine item."] = "Encontre um item Divino.",
		["Use an orb at the Crafting Bench."] = "Use um orbe na Crafting Bench.",
		["Use 100 orbs at the Crafting Bench."] = "Use 100 orbes na Crafting Bench.",
		["Use 1,000 orbs at the Crafting Bench."] = "Use 1.000 orbes na Crafting Bench.",
		["Use 25 Orbs of Grafting."] = "Use 25 Orbs of Grafting.",
		["Bind a modifier with an Orb of Binding."] = "Prenda um modificador com um Orb of Binding.",
		["Improve an item with an Orb of Ruin."] = "Melhore um item com um Orb of Ruin.",
		["Ruin an item with an Orb of Ruin."] = "Arruíne um item com um Orb of Ruin.",
		["Bring an item to 20% quality with Whetstones."] = "Leve a qualidade de um item a 20% queimando Whetstones.",
		["Own an item with a legendary power."] = "Tenha um item com um poder lendário.",
		["Own an item with 6 modifiers (three prefixes, three suffixes)."] =
			"Tenha um item com 6 modificadores (três prefixos, três sufixos).",
		["Win a ranked 1v1 arena match."] = "Vença uma partida ranqueada 1v1 na arena.",
		["Win 50 ranked 1v1 matches."] = "Vença 50 partidas ranqueadas 1v1.",
		["Reach a 1v1 rating of 1200."] = "Alcance rating 1200 no 1v1.",
		["Reach a 1v1 rating of 1500."] = "Alcance rating 1500 no 1v1.",
		["Reach a 1v1 rating of 1800."] = "Alcance rating 1800 no 1v1.",
		["Win a ranked 2v2 arena match."] = "Vença uma partida ranqueada 2v2 na arena.",
		["Win 50 ranked 2v2 matches."] = "Vença 50 partidas ranqueadas 2v2.",
		["Reach a 2v2 rating of 1200."] = "Alcance rating 1200 no 2v2.",
		["Reach a 2v2 rating of 1500."] = "Alcance rating 1500 no 2v2.",
		["Reach a 2v2 rating of 1800."] = "Alcance rating 1800 no 2v2.",
		["Win an Ember Wells battleground."] = "Vença um battleground Ember Wells.",
		["Win 50 Ember Wells battlegrounds."] = "Vença 50 battlegrounds Ember Wells.",
		["Fight 100 Ember Wells battlegrounds."] = "Lute 100 battlegrounds Ember Wells.",
		["Finish a PvP season Blazing or higher."] = "Termine uma temporada PvP em Blazing ou acima.",
		["Finish a PvP season as a Cinder Sovereign."] = "Termine uma temporada PvP como Cinder Sovereign.",
		["Bank embers at a safe exit of the Scorched Marches."] =
			"Guarde embers numa saída segura das Scorched Marches.",
		["Bank 10,000 embers from the Scorched Marches."] = "Guarde 10.000 embers das Scorched Marches.",
		["Bank 1,000 embers at one exit of the Scorched Marches."] =
			"Guarde 1.000 embers numa única saída das Scorched Marches.",
		["Defeat a player in the Scorched Marches (a defeat that counts)."] =
			"Derrote um jogador nas Scorched Marches (uma derrota que conta).",
		["Defeat 100 players in the Scorched Marches."] = "Derrote 100 jogadores nas Scorched Marches.",
		["Stand in the circle when your faction takes the Cinder Shrine."] =
			"Esteja no círculo quando sua facção tomar o Cinder Shrine.",
		["Score in a guild siege."] = "Pontue em um guild siege.",
		["Win a guild siege with your guild."] = "Vença um guild siege com sua guilda.",
		["Win 5 guild sieges."] = "Vença 5 guild sieges.",
		["Finish the tutorial island."] = "Termine a ilha do tutorial.",
		["Join a guild."] = "Entre em uma guilda.",
		["Kill 100 monsters in a party."] = "Mate 100 monstros em party.",
		["Kill 1,000 monsters in a party."] = "Mate 1.000 monstros em party.",
		["Earn 250 achievement points with this character."] = "Ganhe 250 pontos de conquista com este personagem.",
		["Earn 750 achievement points with this character."] = "Ganhe 750 pontos de conquista com este personagem.",
		["Become Exalted with the Ashen Vigil."] = "Fique Exalted com The Ashen Vigil.",
		["Become Exalted with the Cinderforge Compact."] = "Fique Exalted com The Cinderforge Compact.",
		["Become Exalted with the Veiled Choir."] = "Fique Exalted com The Veiled Choir.",
		["Become Exalted with the Thornbound Circle."] = "Fique Exalted com The Thornbound Circle.",
		["Become Exalted with all four factions."] = "Fique Exalted com as quatro facções.",
		["Reach Delving level 50."] = "Alcance o nível 50 em Delving.",
		["Reach Delving level 100."] = "Alcance o nível 100 em Delving.",
		["Reach Wortcunning level 50."] = "Alcance o nível 50 em Wortcunning.",
		["Reach Wortcunning level 100."] = "Alcance o nível 100 em Wortcunning.",
		["Reach Flaying level 50."] = "Alcance o nível 50 em Flaying.",
		["Reach Flaying level 100."] = "Alcance o nível 100 em Flaying.",
		["Reach Angling level 50."] = "Alcance o nível 50 em Angling.",
		["Reach Angling level 100."] = "Alcance o nível 100 em Angling.",
		["Reach 200 profession levels in total."] = "Alcance 200 níveis de profissão no total.",
		["Reach level 100 in all four professions."] = "Alcance o nível 100 nas quatro profissões.",
		["Mentor an apprentice to graduation."] = "Seja mentor de um aprendiz até a formatura.",
		["Mentor 5 apprentices to graduation."] = "Seja mentor de 5 aprendizes até a formatura.",
		["Mentor 15 apprentices to graduation."] = "Seja mentor de 15 aprendizes até a formatura.",
		["Graduate from your mentor."] = "Forme-se com o seu mentor.",
		["Reach level 50 in a Hardcore season."] = "Alcance o nível 50 numa temporada Hardcore.",
		["Reach level 100 in a Hardcore season."] = "Alcance o nível 100 numa temporada Hardcore.",
		["Reach level 250 in a Hardcore season."] = "Alcance o nível 250 numa temporada Hardcore.",
		["Be alive in Hardcore when your season ends."] = "Esteja vivo no Hardcore quando sua temporada acabar.",
		["Reach level 100 in a Self-Found season."] = "Alcance o nível 100 numa temporada Self-Found.",
		["Still be Self-Found when your season ends."] = "Continue Self-Found quando sua temporada acabar.",
		["Find 25 unique items. Opens a stash tab for your account."] =
			"Encontre 25 itens únicos. Abre uma aba do stash para a sua conta.",
		["Complete 100 bestiary entries. Opens a stash tab for your account."] =
			"Complete 100 entradas do bestiário. Abre uma aba do stash para a sua conta.",
		["Seal 50 rifts. Opens a stash tab for your account."] =
			"Sele 50 rifts. Abre uma aba do stash para a sua conta.",
		["Kill a rat at level 500 or higher."] = "Mate um rato no nível 500 ou mais.",
		["Die 50 times."] = "Morra 50 vezes.",
		["Kill a legendary monster between midnight and 1 am."] =
			"Mate um monstro lendário entre meia-noite e 1 da manhã.",
		["Kill a legendary monster that ambushed you."] = "Mate um monstro lendário que te emboscou.",

		-- Daily reward (daily.lua, daily_core.lua)
		["Your account already collected today's daily reward."] = "Sua conta já pegou a recompensa diária de hoje.",
		["You do not have enough room or capacity for the reward."] =
			"Você não tem espaço ou capacidade para a recompensa.",
		["Daily reward (day %d, streak %d): %dx %s."] = "Recompensa diária (dia %d, sequência %d): %dx %s.",
		["Week completed! Bonus reward collected."] = "Semana completa! Recompensa bônus recebida.",
		["A grace charge kept your streak alive (%d left)."] =
			"Uma carga de tolerância manteve sua sequência viva (restam %d).",
		["You earned a grace charge (%d of %d): a missed day will not break your streak."] =
			"Você ganhou uma carga de tolerância (%d de %d): um dia perdido não vai quebrar sua sequência.",
		["Login streak of %d days! Milestone reward: %s."] = "Sequência de login de %d dias! Recompensa de marco: %s.",
		[" and "] = " e ",
		["the title \"%s\""] = "o título \"%s\"",

		-- The bounty board (bounty.lua through ptbr2/bounty.patch while that file is held; bounty_core.lua refusals)
		["Weekly bounty bonus: a %s with %d Orbs of Upheaval and %d Orbs of Fate%s.%s"] =
			"Bônus semanal de bounty: um %s com %d Orbs of Upheaval e %d Orbs of Fate%s.%s",
		["chest"] = "baú",
		["Bounty completed: %s. Another character from your connection was online during the hunt: no reward."] =
			"Bounty concluída: %s. Outro personagem da sua conexão estava online durante a caçada: sem recompensa.",
		["%s gold (bank)"] = "%s de ouro (banco)",
		["%s experience"] = "%s de experiência",
		["Bounty completed: %s. Reward: %s.%s"] = "Bounty concluída: %s. Recompensa: %s.%s",
		[" Your backpack was full: the orbs are in your inbox."] =
			" Sua mochila estava cheia: os orbes estão na sua caixa de entrada.",
		["Bounty accepted: %s. It expires at the next roll."] = "Bounty aceita: %s. Ela expira na próxima rolagem.",
		["Another character from your connection is online: you may hunt, but this contract will pay no reward."] =
			"Outro personagem da sua conexão está online: você pode caçar, mas este contrato não vai pagar recompensa.",
		["Bounty abandoned: %s."] = "Bounty abandonada: %s.",
		["Bounty: %s %d/%d."] = "Bounty: %s %d/%d.",
		["Bounty %s: %d%% done (%d/%d)."] = "Bounty %s: %d%% feito (%d/%d).",
		["The bounty board has new contracts (Adventure > Bounty Board)."] =
			"O Bounty Board tem contratos novos (Adventure > Bounty Board).",
		["That contract is not on today's board."] = "Esse contrato não está no quadro de hoje.",
		["That contract is not for your level."] = "Esse contrato não é para o seu nível.",
		["You already completed that contract today."] = "Você já completou esse contrato hoje.",
		["You already accepted that contract."] = "Você já aceitou esse contrato.",

		-- Systems: stash, bank, town portal, pouches, Everfull Ration, Chaos Pact, hideout, autoloot, party invites, class unlocks, professions, charms, pets, guild hall, tower, arena, battleground, seasons
		["You cannot put that item into the stash."] = "Você não pode colocar esse item no stash.",
		["That item is on your never-stash list."] = "Esse item está na sua lista de nunca guardar.",
		["Your stash cannot hold that many of this item."] = "Seu stash não comporta tantos desse item.",
		["Your stash is full (%d entries). Withdraw something, or get another tab."] =
			"Seu stash está cheio (%d entradas). Retire algo, ou pegue outra aba.",
		["Your stash is full: the tabs beyond your %d general tabs and the tabs you no longer own are withdraw-only."] =
			"Seu stash está cheio: as abas além das suas %d abas gerais e as abas que você não tem mais só permitem retirar.",
		["Could not take the item."] = "Não foi possível pegar o item.",
		["The stash is busy. Try again in a moment."] = "O stash está ocupado. Tente de novo daqui a pouco.",
		["That item moved before it reached the stash. Drag it again."] = "Esse item mudou de lugar antes de chegar ao stash. Arraste de novo.",
		["Empty the container first."] = "Esvazie o recipiente primeiro.",
		["Stashed %dx %s."] = "Guardou %dx %s no stash.",
		["Stashed %dx %s (%s tab)."] = "Guardou %dx %s no stash (aba %s).",
		["You do not have that item in the stash."] = "Você não tem esse item no stash.",
		["You do not have enough capacity."] = "Você não tem capacidade suficiente.",
		["You do not have enough room."] = "Você não tem espaço suficiente.",
		["Retrieved %dx %s from your stash."] = "Retirou %dx %s do seu stash.",
		["You can take items out of the stash only in a protection zone."] =
			"Você só pode retirar itens do stash numa zona de proteção.",
		["You can put items into the stash only in a protection zone. Remote deposit from anywhere: Store > Storage & Slots, or an active Chaos Pact."] =
			"Você só pode guardar itens no stash numa zona de proteção. Guardar de qualquer lugar: Store > Storage & Slots, ou um Chaos Pact ativo.",
		["That item could not be restored. It stays in the stash; tell the staff."] =
			"Não foi possível restaurar esse item. Ele fica no stash; avise a equipe.",
		["Nothing to stow."] = "Nada para guardar.",
		["Stowed %d item(s) into your stash."] = "Guardou %d item(ns) no seu stash.",
		["Kept %d item(s): %s."] = "Ficaram %d item(ns): %s.",
		["Your depot moved into your stash: %d item(s); %d did not fit and wait in the Old depot tab (withdraw-only). %d stay in the depot."] =
			"Seu depot foi para o seu stash: %d item(ns); %d não couberam e esperam na aba Old depot (só retirar). %d ficam no depot.",
		["More depot items move at your next login."] = "Mais itens do depot vão para o stash no seu próximo login.",
		["The depot boxes are withdraw-only now: everything goes into the stash (Economy > Supply Stash). You can still take items out."] =
			"As caixas do depot agora só permitem retirar: tudo vai para o stash (Economy > Supply Stash). Você ainda pode retirar itens.",
		["Your stash moved into your depot: %d entr(ies). %d stay in the stash because the open depot tabs are full (take them out in a protection zone and put them into your depot)."] =
			"Seu stash foi para o seu depot: %d entrada(s). %d ficam no stash porque as abas abertas do depot estão cheias (retire-as numa zona de proteção e coloque-as no depot).",
		["More of your stash moves into your depot when you open a depot locker again."] =
			"Mais itens do seu stash vão para o depot quando você abrir um depot locker de novo.",
		["The stash is closed to new items: put them into your depot. It only gives items back."] =
			"O stash está fechado para novos itens: coloque-os no seu depot. Ele só devolve itens.",
		["containers"] = "recipientes",
		["cannot be moved"] = "não podem ser movidos",
		["store-bound"] = "presos à conta (loja)",
		["quest items"] = "itens de quest",
		["never-stash list"] = "lista de nunca guardar",
		["no room"] = "sem espaço",
		["too many"] = "demais",
		["busy"] = "ocupado",
		["You deposited %d gold. Bank balance: %d gold."] = "Você depositou %d de ouro. Saldo no banco: %d de ouro.",
		["You deposited %d stars."] = "Você depositou %d estrelas.",
		["You withdrew %d gold. Bank balance: %d gold."] = "Você sacou %d de ouro. Saldo no banco: %d de ouro.",
		["You withdrew %d stars."] = "Você sacou %d estrelas.",
		["%s transferred %d gold to your bank account."] = "%s transferiu %d de ouro para a sua conta do banco.",
		["You transferred %d gold to %s."] = "Você transferiu %d de ouro para %s.",
		["%s transferred %d stars to your bank account."] = "%s transferiu %d estrelas para a sua conta do banco.",
		["You transferred %d stars to %s."] = "Você transferiu %d estrelas para %s.",
		["You withdrew %d gold; %d gold did not fit (capacity or free slots) and stays in the bank. Bank balance: %d gold."] =
			"Você sacou %d de ouro; %d de ouro não coube (capacidade ou espaço livre) e fica no banco. Saldo no banco: %d de ouro.",
		["Your bank balance is too low."] = "Seu saldo no banco é baixo demais.",
		["Your bank balance is empty."] = "Seu saldo no banco está vazio.",
		["You do not have room or capacity for any coins."] = "Você não tem espaço nem capacidade para nenhuma moeda.",
		["You do not carry that much gold."] = "Você não carrega tanto ouro.",
		["You do not carry any gold."] = "Você não carrega ouro.",
		["Could not take the gold from you."] = "Não foi possível tirar o ouro de você.",
		["Only gold can be deposited all at once."] = "Só ouro pode ser depositado de uma vez.",
		["Only gold can be withdrawn all at once."] = "Só ouro pode ser sacado de uma vez.",
		["You need level %d to transfer."] = "Você precisa de nível %d para transferir.",
		["That is not a valid character name."] = "Esse não é um nome de personagem válido.",
		["A player with that name does not exist."] = "Não existe jogador com esse nome.",
		["You cannot transfer to yourself."] = "Você não pode transferir para si mesmo.",
		["The bank is busy. Try again in a moment."] = "O banco está ocupado. Tente de novo em um instante.",
		["Stars are not available."] = "Estrelas não estão disponíveis.",
		["You do not carry that many stars."] = "Você não carrega tantas estrelas.",
		["Could not take the stars from you."] = "Não foi possível tirar as estrelas de você.",
		["You can withdraw at most %d stars at once."] = "Você pode sacar no máximo %d estrelas de uma vez.",
		["You do not have that many stars in the bank."] = "Você não tem tantas estrelas no banco.",
		["You do not have room or capacity for the stars."] = "Você não tem espaço nem capacidade para as estrelas.",
		["A portal to your temple opened beside you. Its return portal waits beside the temple for %d minutes."] =
			"Um portal para o seu templo abriu ao seu lado. O portal de volta espera ao lado do templo por %d minutos.",
		["Opening a town portal... stand still."] = "Abrindo um town portal... fique parado.",
		["The return portal beside the temple takes you back."] =
			"O portal de volta ao lado do templo te leva de volta.",
		["You do not own that portal style."] = "Você não tem esse estilo de portal.",
		["Store items cannot be traded."] = "Itens da loja não podem ser negociados.",
		["The Loot Bag stays in your purse: it cannot be moved out, dropped, traded or mailed."] =
			"A Loot Bag fica na sua purse: ela não pode ser movida para fora, jogada fora, negociada ou enviada.",
		["%s: your %s is in your %s. It collects %s while you carry it."] =
			"%s: seu %s está na sua %s. Ele coleta %s enquanto você o carrega.",
		["%s: your %s is in your %s. It collects %s from now on, there or in your backpack."] =
			"%s: seu %s está na sua %s. Ele coleta %s a partir de agora, ali ou na sua mochila.",
		["%s: your %s is in your %s. Move it to your backpack: it collects %s while you carry it."] =
			"%s: seu %s está na sua %s. Coloque-o na mochila: ele coleta %s enquanto você o carrega.",
		["Store"] = "Loja",
		["The Bottomless Loot Pouch is retired, a free Loot Bag replaces it"] =
			"O Bottomless Loot Pouch foi aposentado, uma Loot Bag grátis o substitui",
		["all the loot of your kills, as its rules pick (Loot Filter > Loot Bag)"] =
			"todo o loot das suas mortes, como as regras dela escolhem (Loot Filter > Loot Bag)",
		["orbs, whetstones, rune shards and gems"] = "orbes, whetstones, fragmentos de runa e gemas",
		["Rift Keys, Omen Keys and omen fragments"] = "Rift Keys, Omen Keys e fragmentos de omen",
		["Back after your death, empty: your %s (%s)."] = "De volta depois da sua morte, vazios: %s (%s).",
		["The Everfull Ration is in your %s. Use it like food: it never runs out."] =
			"A Everfull Ration está na sua %s. Use como comida: ela nunca acaba.",
		["Back after your death: your Everfull Ration."] = "De volta depois da sua morte: sua Everfull Ration.",
		-- Everfull potions (potions.lua, data/lib/chaos_potions.lua)
		["You received an Everfull Health Potion and an Everfull Mana Potion. They never run out."] =
			"Você recebeu uma Everfull Health Potion e uma Everfull Mana Potion. Elas nunca acabam.",
		["You already have one. It never runs out."] = "Você já tem uma. Ela nunca acaba.",
		["You do not have enough money."] = "Você não tem dinheiro suficiente.",
		["You have no room for it."] = "Você não tem espaço para ela.",
		["It never runs out: drink it as often as the potion exhaust allows."] =
			"Ela nunca acaba: beba sempre que o intervalo das poções permitir.",
		["%d days of the Chaos Pact added: it runs until %s."] = "%d dias de Chaos Pact adicionados: ele vale até %s.",
		["Your Chaos Pact runs until %s. Claim your %d Chaos Coins every day in Character > Chaos Pact."] =
			"Seu Chaos Pact vale até %s. Pegue suas %d Chaos Coins todo dia em Character > Chaos Pact.",
		["%s added to your account (%d of %d)."] = "%s adicionado à sua conta (%d de %d).",
		["Chaos Pact: a cosmetic for you, see Character > Cosmetics."] =
			"Chaos Pact: um cosmético para você, veja Character > Cosmetics.",
		["Welcome home. Character > Hideout to decorate. The portal south of you, or Leave in that window, takes you back."] =
			"Bem-vindo de volta. Character > Hideout para decorar. O portal ao sul de você, ou Leave nessa janela, leva você de volta.",
		["You visit the hideout of %s."] = "Você visita o hideout de %s.",
		["Your Town Portal takes you out of the hideout."] = "Seu Town Portal leva você para fora do hideout.",
		-- City portals: the look text (cityportals_config.lua, cityportals_fx.lua)
		["Hideout Portal"] = "Portal do Hideout",
		["Step in to enter your own hideout. Its exit portal brings you back to this spot."] =
			"Entre para ir ao seu hideout. O portal de saída dele traz você de volta a este lugar.",
		["Guild Hall Portal"] = "Portal do Guild Hall",
		["Members of a guild that owns a guild hall step in to enter it. Its exit portal leads to your temple."] =
			"Membros de uma guild que tem um guild hall entram por aqui. O portal de saída dele leva ao seu templo.",
		["Hall of Services Portal"] = "Portal do Salão de Serviços",
		["Guild Siege Portal"] = "Portal do Guild Siege",
		["Memorial Portal"] = "Portal do Memorial",
		["World Boss Portal"] = "Portal do World Boss",
		["Chronicle Gate"] = "Portão da Chronicle",
		["Hunting Area Portal"] = "Portal da Área de Caça",
		["Idle Hall Exit"] = "Saída do Idle Hall",
		["Hall of Services Exit"] = "Saída do Salão de Serviços",
		["Step in to go back to the temple of this town."] = "Entre para voltar ao templo desta cidade.",
		-- one loot line per kill (lootline_core.lua, pouches_core.lua summary)
		["Loot of %s: %s"] = "Loot de %s: %s",
		["nothing"] = "nada",
		["nothing (due to low stamina)"] = "nada (stamina baixa)",
		["a creature"] = "uma criatura",
		["Looted: %s"] = "Coletado: %s",
		["%s is full"] = "%s está cheio",
		["%d to your %s"] = "%d para seu %s",
		["%d to your backpack"] = "%d para sua mochila",
		["%d left in the corpse, no room"] = "%d ficou no corpo, sem espaço",
		[" and %d more"] = " e mais %d",
		["Step in to go back to your temple. Characters who stand idle in town are moved to this hall."] =
			"Entre para voltar ao seu templo. Personagens parados na cidade são levados a este salão.",
		["Step in to enter this hunting area; the portal refuses characters below its level. Its exit portal leads back here."] =
			"Entre para ir a esta área de caça; o portal recusa personagens abaixo do level dela. O portal de saída dela traz você de volta aqui.",
		["Ember Descent Portal"] = "Portal da Ember Descent",
		["Step in to open the Ember Descent: a roguelike trial for level 100+, alone or with up to three party members."] =
			"Entre para abrir a Ember Descent: um desafio roguelike para level 100+, sozinho ou com até três membros da party.",
		["Raid Portal"] = "Portal da Raid",
		["Step in to open the raid window: the Ashen Sepulchre for a party of 5 to 15, level 800+."] =
			"Entre para abrir a janela da raid: o Ashen Sepulchre para uma party de 5 a 15, level 800+.",
		["Step in to reach a chapter area of the Ashen Chronicle that the story has opened. Its exit portal leads to your temple."] =
			"Entre para chegar a uma área de capítulo da Ashen Chronicle que a história abriu. O portal de saída dela leva ao seu templo.",
		["Open while a world boss is awake: step in to join the fight in its arena. The arena's exit portal leads to your temple."] =
			"Aberto enquanto um world boss está desperto: entre para lutar na arena dele. O portal de saída da arena leva ao seu templo.",
		["Step in to visit the Ember Memorial: the season's realm firsts, its records and its fallen. Its exit portal leads to your temple."] =
			"Entre para visitar o Ember Memorial: as primeiras conquistas do reino na temporada, os recordes e os caídos. O portal de saída dele leva ao seu templo.",
		["Open while a guild siege runs: members of a signed-up guild step in to reach their base. The base's exit portal leads to your temple."] =
			"Aberto enquanto um guild siege acontece: membros de uma guild inscrita entram para chegar à base dela. O portal de saída da base leva ao seu templo.",
		["Step in to enter the Hall of Services: the town's Chaos NPCs behind their counters, the Ember Descent and the raid portals. Its exit portal leads back to this temple."] =
			"Entre para ir ao Salão de Serviços: os NPCs Chaos da cidade atrás dos balcões, os portais da Ember Descent e da raid. O portal de saída dele traz você de volta a este templo.",
		["Only the owner of this hideout may open its depot."] = "Só o dono deste hideout pode abrir o depot dele.",
		["This depot cannot open here. Use a town depot."] = "Este depot não abre aqui. Use um depot da cidade.",
		["Nothing can be left on a hideout's floor."] = "Nada pode ser deixado no chão de um hideout.",
		["No such character."] = "Esse personagem não existe.",
		["Autoloot list cleaned."] = "Lista do autoloot limpa.",
		["The item %s does not exist!"] = "O item %s não existe!",
		["The item %s already exists!"] = "O item %s já está na lista!",
		["Your auto loot only allows you to add %d items."] = "Seu autoloot só permite adicionar %d itens.",
		["Perfect you have added to the list: %s"] = "Pronto, você adicionou à lista: %s",
		["Perfect, you have removed from the list: %s"] = "Pronto, você removeu da lista: %s",
		["The item %s does not exist in the list."] = "O item %s não está na lista.",
		["Unknown auto loot action."] = "Ação de autoloot desconhecida.",
		["Rarity autoloot: no room or capacity, left in the corpse."] =
			"Rarity Autoloot: sem espaço ou capacidade, ficou no corpo.",
		["Catacombs are not available on this server."] = "As Catacombs não estão disponíveis neste servidor.",
		["The inviting player is no longer online."] = "O jogador que convidou não está mais online.",
		["That party no longer exists."] = "Essa party não existe mais.",
		["You are already in a party."] = "Você já está em uma party.",
		["You could not join the party."] = "Você não conseguiu entrar na party.",
		["The %s is unlocked: you can play this character fully now."] =
			"O %s está desbloqueado: agora você pode jogar com este personagem por completo.",
		["Every class is open to every account."] = "Todas as classes estão abertas para todas as contas.",
		["You switched for free: you are now %s. This was your only free switch; from now on only the store's Vocation Change changes it."] =
			"Você trocou de graça: agora você é %s. Essa foi sua única troca grátis; daqui em diante só o Vocation Change da loja muda isso.",
		["The vein is gone."] = "O veio sumiu.",
		["The corpse is gone."] = "O corpo sumiu.",
		["With %s %d you only get %s materials here (%s %d for more)."] =
			"Com %s %d você só consegue materiais %s aqui (%s %d para mais).",
		["You found a charm: %s%s."] = "Você achou um charm: %s%s.",
		[" (in your inbox)"] = " (na sua caixa de entrada)",
		["Last Ember: the Gravewarden's Seal kept you alive."] = "Last Ember: o Gravewarden's Seal te manteve vivo.",
		["Another %s! Yours gains %d pet experience."] = "Outro %s! O seu ganha %d de experiência de pet.",
		["New pet: %s! Open Character > Pets to call it."] = "Pet novo: %s! Abra Character > Pets para chamá-lo.",
		["Your pet mends you (+%.0f)."] = "Seu pet te cura (+%.0f).",
		["Your minions rest until you leave the protection zone."] =
			"Seus lacaios descansam até você sair da zona de proteção.",
		["You are full."] = "Você está cheio.",
		["Your title is hidden."] = "Seu título está oculto.",
		["Your guild's aura is yours to wear while you are in the guild (outfit window)."] =
			"A aura da sua guilda é sua para usar enquanto você estiver na guilda (janela de outfit).",
		["The guild hall cannot be built right now. Tell a gamemaster."] =
			"O guild hall não pode ser construído agora. Avise um gamemaster.",
		["Welcome to the hall of %s.%s"] = "Bem-vindo ao hall de %s.%s",
		[" The rent is unpaid: the upgrades are locked."] = " O aluguel não foi pago: as melhorias estão bloqueadas.",
		[" The rent is due: pay it before the upgrades lock."] =
			" O aluguel venceu: pague antes que as melhorias sejam bloqueadas.",
		["You are not a member of this hall's guild."] = "Você não é membro da guilda deste hall.",
		["The crafting bench is locked."] = "A crafting bench está bloqueada.",
		["Journey objective done: %s (%s)."] = "Objetivo da jornada concluído: %s (%s).",
		["%s: chapter %d, %s, complete! Rewards: %s."] = "%s: capítulo %d, %s, completo! Recompensas: %s.",
		["none"] = "nada",
		["%s milestone: %s. Unlocked for your whole account: %s."] =
			"Marco de %s: %s. Desbloqueado para toda a sua conta: %s.",
		["%s has ended. This character is now a standard character: it keeps its level, skills, items and passive tree and can trade with everyone."] =
			"%s acabou. Este personagem agora é um personagem padrão: ele mantém nível, skills, itens e árvore passiva e pode negociar com todos.",
		["The season"] = "A temporada",
		["Welcome to %s! %s is now a season character %s. The season ends in %s. Adventure > Season shows your milestones."] =
			"Bem-vindo a %s! %s agora é um personagem de temporada %s. A temporada acaba em %s. Adventure > Season mostra seus marcos.",
		["%s %s: %s left. Adventure > Season shows your milestones."] =
			"%s %s: faltam %s. Adventure > Season mostra seus marcos.",
		["%s is running. This character can still join it: Adventure > Season in the menu."] =
			"%s está rolando. Este personagem ainda pode entrar: Adventure > Season no menu.",
		["Mode: %s. It holds until %s ends."] = "Modo: %s. Ele vale até %s acabar.",
		["You have fallen. %s is no longer a Hardcore character: it stays on the %s ladder as fallen and plays on as a standard character, with everything it has."] =
			"Você caiu. %s não é mais um personagem Hardcore: ele fica no ranking de %s como caído e continua como personagem padrão, com tudo o que tem.",
		["Hardcore: you cannot be hurt for %d seconds after logging in."] =
			"Hardcore: você não pode ser ferido por %d segundos depois de entrar.",
		["You already claimed this reward."] = "Você já pegou essa recompensa.",
		["You do not have enough Tower Points yet."] = "Você ainda não tem Tower Points suficientes.",
		["You claimed the %d point Infinity Tower reward."] = "Você pegou a recompensa de %d pontos da Infinity Tower.",
		["Tower Season %d ends %s. Last season paid out: %s."] =
			"A Tower Season %d acaba em %s. Última temporada paga: %s.",
		["You are already inside the tower."] = "Você já está dentro da torre.",
		["You need level %d to enter the Infinity Tower."] = "Você precisa do nível %d para entrar na Infinity Tower.",
		["Only the party leader can start the tower."] = "Só o líder da party pode começar a torre.",
		["All tower arenas are busy. Try again in a moment."] =
			"Todas as arenas da torre estão ocupadas. Tente de novo daqui a pouco.",
		["Welcome to the Infinity Tower. Floor 1 starts in %d seconds. Leave Tower (Adventure > Infinity Tower) takes you out."] =
			"Bem-vindo à Infinity Tower. O andar 1 começa em %d segundos. Leave Tower (Adventure > Infinity Tower) te tira de lá.",
		["You are not inside the tower."] = "Você não está dentro da torre.",
		["You are not in the arena queue."] = "Você não está na fila da arena.",
		["Arena: FIGHT!"] = "Arena: LUTEM!",
		["The fight starts in %d seconds."] = "A luta começa em %d segundos.",
		["Choose 1v1, 2v2 or 3v3."] = "Escolha 1v1, 2v2 ou 3v3.",
		["PvP Season %d has ended: you finished %s (%s, rating %d).%s"] =
			"A Temporada PvP %d acabou: você terminou em %s (%s, rating %d).%s",
		[" Title: %s."] = " Título: %s.",
		["You are not in the battleground queue."] = "Você não está na fila do battleground.",
		["Battleground: you seem inactive. Move or fight, or you are removed as a deserter in %d seconds."] =
			"Battleground: você parece inativo. Mexa-se ou lute, ou você será removido como desertor em %d segundos.",
		["Battleground: turn secure mode off to fight back."] = "Battleground: desligue o secure mode para revidar.",
		["The wells open in %d seconds."] = "Os poços abrem em %d segundos.",
		["That player is protected for a moment."] = "Esse jogador está protegido por um momento.",
		["Only %d characters from the same connection can be online at once."] =
			"Só %d personagens da mesma conexão podem estar online ao mesmo tempo.",
		["Another character from your connection is online: dungeons, the Infinity Tower and PvP are blocked for both (max %d characters)."] =
			"Outro personagem da sua conexão está online: dungeons, a Infinity Tower e o PvP estão bloqueados para os dois (máximo %d personagens).",
		["Presence check failed. You were taken to the temple."] =
			"A verificação de presença falhou. Você foi levado ao templo.",
		["Presence check failed."] = "A verificação de presença falhou.",
		["No event is active today. Check the calendar on the login screen."] =
			"Nenhum evento está ativo hoje. Veja o calendário na tela de login.",
		["Your position: %d, %d, %d."] = "Sua posição: %d, %d, %d.",
		["The spellbook is already opening."] = "O spellbook já está abrindo.",
		["%s - %s. Fits %s spells. Socket it in the spell supports window (Character > Spell Supports)."] =
			"%s - %s. Serve em magias de %s. Encaixe na janela de spell supports (Character > Spell Supports).",
		["Switching loadout... stand still."] = "Trocando de loadout... fique parado.",
		["Your last loadout switch was interrupted by a server restart and was undone."] =
			"Sua última troca de loadout foi interrompida por um reinício do servidor e foi desfeita.",
		["You found %s, a piece of %s.%s"] = "Você achou %s, uma peça de %s.%s",
		[" Your backpack was full: it is in your inbox."] = " Sua mochila estava cheia: está na sua caixa de entrada.",
		["%sUse the %s on an item: choose \"Use with\" on the orb, then click an item or a Rift Key in your backpack. The crafting bench (Economy > Crafting Bench) shows a preview first."] =
			"%sUse o %s num item: escolha \"Use with\" no orbe, depois clique num item ou numa Rift Key na sua mochila. A Crafting Bench (Economy > Crafting Bench) mostra uma prévia antes.",
		["That cannot carry modifiers. "] = "Isso não pode ter modificadores. ",
		["Rift Atlas: %s completed, +%d point%s."] = "Rift Atlas: %s completado, +%d ponto%s.",
		["The way is sealed."] = "O caminho está selado.",
		["%s is for level %d and above."] = "%s é para o nível %d ou mais.",
		["%s. The portal beside you leads back to the temple."] = "%s. O portal ao seu lado leva de volta ao templo.",
		["The Hall of Services: progression to the west, trade to the east, the Descent and the raid to the south. The portal beside you leads back to the temple."] =
			"O Salão de Serviços: progressão a oeste, comércio a leste, a Descida e a raid ao sul. O portal ao seu lado leva de volta ao templo.",
		["%s declared war on your guild (%s). Answer it in Social > Guild Wars before it expires in %s."] =
			"%s declarou guerra à sua guilda (%s). Responda em Social > Guild Wars antes que expire em %s.",
		["Leaderboard: %s place on the %s board last week. You hold the title %s this week.%s"] =
			"Leaderboard: %s lugar no ranking de %s na semana passada. Você tem o título %s nesta semana.%s",
		[" Reward in your inbox: %s."] = " Recompensa na sua caixa de entrada: %s.",

		-- Rifts, Omens, Ascended arenas, the Descent, the raid, guild sieges, world and guild bosses (rift.lua, uber.lua, descent.lua, raid.lua, siege.lua, worldboss.lua, guildboss.lua)
		["Omen Keys are not installed on this server (tools/install_omens.py)."] =
			"As Omen Keys não estão instaladas neste servidor (tools/install_omens.py).",
		["You left your rift: its key is spent."] = "Você saiu do seu rift: a chave dele foi gasta.",
		["%s: %d gold to your bank, %d Orb%s of Upheaval, %d Orb%s of Fate%s%s.%s"] =
			"%s: %d de ouro no seu banco, %d Orb%s of Upheaval, %d Orb%s of Fate%s%s.%s",
		["Guardian's reward (the chest was not opened, it was sent to you)"] =
			"Recompensa do guardião (o baú não foi aberto, foi enviada para você)",
		["Rift reward (the chest was not opened, it was sent to you)"] =
			"Recompensa do rift (o baú não foi aberto, foi enviada para você)",
		["Guardian's chest"] = "Baú do guardião",
		["Rift chest"] = "Baú do rift",
		["The coffer does not answer you."] = "O cofre não te responde.",
		["The coffer's seal has gone cold."] = "O selo do cofre esfriou.",
		["The coffer is still sealed: %d guard%s left."] = "O cofre continua selado: resta(m) %d guarda%s.",
		["You are already inside a rift."] = "Você já está dentro de um rift.",
		["You cannot open a rift while you are in a fight."] = "Você não pode abrir um rift enquanto está em luta.",
		["You cannot open a rift from here."] = "Você não pode abrir um rift daqui.",
		["This rift key is broken."] = "Esta rift key está quebrada.",
		["No monsters answer this rift. Tell a gamemaster."] =
			"Nenhum monstro responde a este rift. Avise um gamemaster.",
		["The key could not be used."] = "A chave não pôde ser usada.",
		["This omen key is silent."] = "Esta omen key está em silêncio.",
		["The guardian does not answer. Tell a gamemaster."] = "O guardião não responde. Avise um gamemaster.",
		["You need %d omen fragments to bind an Omen Key (you carry %d)."] =
			"Você precisa de %d fragmentos de omen para formar uma Omen Key (você carrega %d).",
		["Omen Keys are not installed on this server."] = "As Omen Keys não estão instaladas neste servidor.",
		["The fragments could not be bound."] = "Os fragmentos não puderam ser unidos.",
		["The chest is empty."] = "O baú está vazio.",
		["This chest is not yours."] = "Este baú não é seu.",
		["You already took your share."] = "Você já pegou a sua parte.",
		["The rift's experience is spent for now: kills give less until more time passes."] =
			"A experiência do rift se esgotou por enquanto: as mortes dão menos até passar mais tempo.",
		["A %s drops from %s!"] = "Um %s cai de %s!",
		["%s: an %s.%s"] = "%s: um %s.%s",
		["You found"] = "Você achou",
		[" It is in your inbox."] = " Está na sua caixa de entrada.",
		["%s: %s.%s"] = "%s: %s.%s",
		["You received a sigil"] = "Você recebeu um sigilo",
		["The guardian's death leaves something behind"] = "A morte do guardião deixa algo para trás",
		["The sealed rift leaves something behind"] = "O rift selado deixa algo para trás",
		["Your last arena was interrupted by a server restart, so its sigil is returned"] =
			"Sua última arena foi interrompida por um reinício do servidor, então o sigilo foi devolvido",
		["The arena did not answer, so your sigil is returned"] =
			"A arena não respondeu, então seu sigilo foi devolvido",
		["%d shards bind together"] = "%d fragmentos se unem",
		["Three relics burn into one"] = "Três relíquias se fundem em uma",
		["Staff"] = "Staff",
		["Spoils of %s: %d gold to your bank, %d Orbs of Upheaval, %d Orbs of Fate%s%s%s.%s"] =
			"Espólios de %s: %d de ouro no seu banco, %d Orbs of Upheaval, %d Orbs of Fate%s%s%s.%s",
		["The Ascended arenas are closed."] = "As arenas Ascended estão fechadas.",
		["You are already inside an Ascended arena."] = "Você já está dentro de uma arena Ascended.",
		["You must stand in a protection zone to use a sigil."] =
			"Você precisa estar numa zona de proteção para usar um sigilo.",
		["You cannot use a sigil while you are in a fight."] = "Você não pode usar um sigilo enquanto está em luta.",
		["You cannot use a sigil from here."] = "Você não pode usar um sigilo daqui.",
		["You need level %d to face %s."] = "Você precisa do nível %d para enfrentar %s.",
		["Wait a moment."] = "Espere um momento.",
		["This sigil is silent."] = "Este sigilo está em silêncio.",
		["The sigil cannot be used now."] = "O sigilo não pode ser usado agora.",
		["The Ember Gate opens for you in %d seconds."] = "O Ember Gate abre para você em %d segundos.",
		["You need %d of these shards to bind an Ascended Sigil (you carry %d)."] =
			"Você precisa de %d destes fragmentos para formar um Ascended Sigil (você carrega %d).",
		["Ascended Sigils are not installed on this server."] =
			"Os Ascended Sigils não estão instalados neste servidor.",
		["The chest spills %d embers and %d gold (to your bank)."] =
			"O baú solta %d embers e %d de ouro (no seu banco).",
		["You do not have enough embers."] = "Você não tem embers suficientes.",
		["You carry no curse."] = "Você não carrega nenhuma maldição.",
		["Choose your boon first."] = "Escolha sua bênção primeiro.",
		["%s is lifted."] = "%s foi removida.",
		["The altar has taken its due from you."] = "O altar já cobrou o que era devido de você.",
		["You earned the title \"%s\"."] = "Você ganhou o título \"%s\".",
		["%s Depth %d of %d. Rewards: %s."] = "%s Profundidade %d de %d. Recompensas: %s.",
		["The Descent is conquered!"] = "A Descent foi conquistada!",
		["You fell in the Descent."] = "Você caiu na Descent.",
		["The embers burned out."] = "As brasas se apagaram.",
		["You left the Descent."] = "Você saiu da Descent.",
		["The Descent closes for a restart."] = "A Descent se fecha para um reinício.",
		["The Phoenix Ember flares: you rise again."] = "A Phoenix Ember se acende: você se levanta de novo.",
		["The altar is cold."] = "O altar está frio.",
		["The chest is empty: its embers and gold are yours already."] =
			"O baú está vazio: as embers e o ouro dele já são seus.",
		["Your last descent was interrupted by a server restart."] =
			"Sua última descida foi interrompida por um reinício do servidor.",
		["You cannot leave the Descent while you are in a fight."] =
			"Você não pode sair da Descent enquanto está em luta.",
		["Spoils of %s: %s.%s"] = "Espólios de %s: %s.%s",
		["You helped slay %s. You looted it already this week: no spoils until the reset."] =
			"Você ajudou a matar %s. Você já saqueou nesta semana: sem espólios até o reset.",
		["You fell. The fight goes on without you; the doors open when it ends."] =
			"Você caiu. A luta continua sem você; as portas abrem quando ela acabar.",
		["Stand next to the Font of Ash."] = "Fique ao lado da Font of Ash.",
		["The Font of Ash washes the hex away."] = "A Font of Ash lava a maldição.",
		["You carry no hex."] = "Você não carrega nenhuma maldição.",
		["Your raid was interrupted. Its progress is saved: continue it from the raid window."] =
			"Sua raid foi interrompida. O progresso está salvo: continue pela janela da raid.",
		["You cannot leave in the middle of a boss fight."] = "Você não pode sair no meio de uma luta contra boss.",
		["You wake up in your guild's base. The gate leads back into the fight."] =
			"Você acorda na base da sua guilda. O portão leva de volta para a luta.",
		["You struck down %s: +%d points for %s."] = "Você derrubou %s: +%d pontos para %s.",
		["%s struck you down. You wake up in your base in %d seconds."] =
			"%s te derrubou. Você acorda na sua base em %d segundos.",
		["%s (%s) struck down %s."] = "%s (%s) derrubou %s.",
		["You were struck down. You wake up in your base in %d seconds."] =
			"Você foi derrubado. Você acorda na sua base em %d segundos.",
		["Guild siege reward (%s): %d gold to your bank%s%s.%s"] =
			"Recompensa do guild siege (%s): %d de ouro no seu banco%s%s.%s",
		["winner"] = "vencedor",
		["participant"] = "participante",
		["No guild siege reward: you need %d seconds in the siege while the match runs (you had %d)."] =
			"Sem recompensa do guild siege: você precisa de %d segundos no siege durante a partida (você teve %d).",
		["You cannot join the guild siege while another character from your connection is online (multi-client). Log the other character out first."] =
			"Você não pode entrar no guild siege enquanto outro personagem da sua conexão está online (multi-client). Deslogue o outro personagem primeiro.",
		["Guild siege: this is the %s base of %s. %s Turn your secure mode off to attack. The forcefield at the back of the room leads home."] =
			"Guild siege: esta é a base %s de %s. %s Desligue o secure mode para atacar. O campo de força no fundo da sala leva para casa.",
		["north"] = "norte",
		["east"] = "leste",
		["south"] = "sul",
		["west"] = "oeste",
		["The gate opens in %d seconds."] = "O portão abre em %d segundos.",
		["The gate leads into the arena."] = "O portão leva para a arena.",
		["World boss reward (%.1f%% of the contribution: %s damage, %s healing, %s tanking%s): %d gold to your bank, %s.%s"] =
			"Recompensa do world boss (%.1f%% da contribuição: %s de dano, %s de cura, %s de tank%s): %d de ouro no seu banco, %s.%s",
		["You earned the title %s (%s %s) for %d days."] = "Você ganhou o título %s (%s %s) por %d dias.",
		["You did too little of the damage for a share of the spoils."] =
			"Você causou pouco dano para receber parte dos espólios.",

		-- Mentors and referrals (mentor.lua, mentor_core.lua, mentor_config.lua messages; referral.lua, referral_config.lua messages)
		["now"] = "agora",
		["%d day"] = "%d dia",
		["%d days"] = "%d dias",
		["%d hour"] = "%d hora",
		["%d hours"] = "%d horas",
		["%d minute"] = "%d minuto",
		["Only accounts up to %d days old can pick a mentor."] = "Só contas com até %d dias podem escolher um mentor.",
		["Only characters up to level %d can pick a mentor."] =
			"Só personagens até o nível %d podem escolher um mentor.",
		["Your referrer's character %s is now your mentor. You can dismiss them in Social > Mentors."] =
			"%s, personagem de quem te indicou, agora é seu mentor. Você pode dispensá-lo em Social > Mentors.",
		["This account cannot take part right now."] = "Esta conta não pode participar agora.",
		["Bought: %s."] = "Comprado: %s.",
		["You can pick another mentor in %s."] = "Você pode escolher outro mentor em %s.",
		["Cosmetics are not available right now."] = "Os cosméticos não estão disponíveis agora.",
		["The mentor system is off."] = "O sistema de mentores está desligado.",
		["You dismissed your mentor %s."] = "Você dispensou seu mentor %s.",
		["Your apprentice %s dismissed you."] = "Seu aprendiz %s te dispensou.",
		["This mentor has no free place."] = "Este mentor não tem vaga livre.",
		["This character has graduated already."] = "Este personagem já se formou.",
		["You graduated from your mentor %s: %s."] = "Você se formou com seu mentor %s: %s.",
		["Your apprentice %s graduated! +%d Mentor Marks."] = "Seu aprendiz %s se formou! +%d Mentor Marks.",
		["%s reached level %d and leaves the mentorship (not enough time hunting together for a reward)."] =
			"%s chegou ao nível %d e sai da mentoria (pouco tempo caçando juntos para uma recompensa).",
		["Release your apprentices first."] = "Libere seus aprendizes primeiro.",
		["You already have a mentor."] = "Você já tem um mentor.",
		["+1 Mentor Mark for hunting with your apprentice (%d / %d today)."] =
			"+1 Mentor Mark por caçar com seu aprendiz (%d / %d hoje).",
		["Invitation sent to %s."] = "Convite enviado para %s.",
		["%s invites you to be their apprentice: Social > Mentors."] =
			"%s te convida para ser aprendiz: Social > Mentors.",
		["A character with a mentor cannot mentor."] = "Um personagem com mentor não pode ser mentor.",
		["A mentor cannot pick a mentor."] = "Um mentor não pode escolher um mentor.",
		["%s is now your mentor. Hunt together for the bonus: +%d%% experience and %d%% less damage taken."] =
			"%s agora é seu mentor. Cacem juntos pelo bônus: +%d%% de experiência e %d%% menos dano recebido.",
		["%s is now your apprentice."] = "%s agora é seu aprendiz.",
		["This character has had %d mentors already."] = "Este personagem já teve %d mentores.",
		["To mentor, your account must be at least %d days old."] =
			"Para ser mentor, sua conta precisa ter pelo menos %d dias.",
		["This mentor cannot take apprentices right now."] = "Este mentor não pode aceitar aprendizes agora.",
		["This character must be level %d to mentor."] = "Este personagem precisa ter nível %d para ser mentor.",
		["To mentor, your account needs %d hours of play."] = "Para ser mentor, sua conta precisa de %d horas de jogo.",
		["To mentor, a character of your account must have reached level %d."] =
			"Para ser mentor, um personagem da sua conta precisa ter chegado ao nível %d.",
		["Staff characters cannot mentor."] = "Personagens da staff não podem ser mentores.",
		["Your apprentice %s: %s. +%d Mentor Marks."] = "Seu aprendiz %s: %s. +%d Mentor Marks.",
		["Your apprentice %s: %s. Monthly marks limit reached."] =
			"Seu aprendiz %s: %s. Limite mensal de marks atingido.",
		["Your apprentice %s: %s. No marks: hunt together first."] =
			"Seu aprendiz %s: %s. Sem marks: cacem juntos primeiro.",
		["This mentor has taken enough new apprentices this month."] =
			"Este mentor já aceitou aprendizes novos suficientes neste mês.",
		["That apprentice is not yours."] = "Esse aprendiz não é seu.",
		["That invitation is gone."] = "Esse convite não existe mais.",
		["That mentor is gone."] = "Esse mentor não existe mais.",
		["No room for it: free some space first."] = "Sem espaço para isso: libere espaço primeiro.",
		["This mentor takes no new apprentices right now."] = "Este mentor não aceita aprendizes novos agora.",
		["Not enough Mentor Marks."] = "Mentor Marks insuficientes.",
		["This character is not a mentor."] = "Este personagem não é mentor.",
		["That player is not online."] = "Esse jogador não está online.",
		["You own this already."] = "Você já tem isso.",
		["You were linked to this mentor before."] = "Você já foi ligado a este mentor antes.",
		["This character is already a mentor."] = "Este personagem já é mentor.",
		["You are a mentor now. New players can find you in Social > Mentors."] =
			"Agora você é mentor. Jogadores novos podem te achar em Social > Mentors.",
		["You released %s."] = "Você liberou %s.",
		["Your mentor %s released you."] = "Seu mentor %s te liberou.",
		["You are no longer a mentor."] = "Você não é mais mentor.",
		["You cannot mentor your own account."] = "Você não pode ser mentor da sua própria conta.",
		["A mentor and an apprentice cannot share an e-mail domain."] =
			"Um mentor e um aprendiz não podem dividir um domínio de e-mail.",
		["A mentor and an apprentice cannot share a connection."] =
			"Um mentor e um aprendiz não podem dividir uma conexão.",
		["Mentor card saved."] = "Cartão de mentor salvo.",
		["Staff accounts take no part in the mentor system."] =
			"Contas da staff não participam do sistema de mentores.",
		["Unknown offer."] = "Oferta desconhecida.",
		["Weekly limit reached for this offer."] = "Limite semanal atingido para esta oferta.",
		["This account already has a referrer."] = "Esta conta já tem quem a indicou.",
		["That is not a referral code."] = "Isso não é um código de indicação.",
		["You cannot use the code of an account you referred."] =
			"Você não pode usar o código de uma conta que você indicou.",
		["The referral program is off."] = "O programa de indicação está desligado.",
		["Welcome gift for joining with a referral code: %s and the title %s."] =
			"Presente de boas-vindas por entrar com um código de indicação: %s e o título %s.",
		["Part of your welcome gift did not fit: it waits in your depot inbox."] =
			"Parte do seu presente de boas-vindas não coube: ela espera na caixa de entrada do seu depot.",
		["Your welcome gift could not be given: log in again."] =
			"Seu presente de boas-vindas não pôde ser entregue: entre de novo.",
		["Referral code accepted: you were referred by %s."] = "Código de indicação aceito: você foi indicado por %s.",
		["This referral code has reached its limit of new friends for this month."] =
			"Este código de indicação atingiu o limite de novos amigos deste mês.",
		["Reach level %d with any character of this account to get your referral code."] =
			"Chegue ao nível %d com qualquer personagem desta conta para ganhar seu código de indicação.",
		["This account has no creation date, so it cannot enter a referral code."] =
			"Esta conta não tem data de criação, então não pode usar um código de indicação.",
		["You cannot use your own referral code."] = "Você não pode usar seu próprio código de indicação.",
		["Your friend %s reached level %d: you received %s."] = "Seu amigo %s chegou ao nível %d: você recebeu %s.",
		["This referral code cannot be used right now."] = "Este código de indicação não pode ser usado agora.",
		["Staff accounts cannot refer players."] = "Contas da staff não podem indicar jogadores.",
		["The referral code entered at account creation was not accepted: %s"] =
			"O código de indicação usado na criação da conta não foi aceito: %s",
		["This referral code cannot be used by an account with the same e-mail domain as its owner."] =
			"Este código de indicação não pode ser usado por uma conta com o mesmo domínio de e-mail do dono.",
		["This referral code cannot be used from the same connection as its owner."] =
			"Este código de indicação não pode ser usado da mesma conexão do dono.",
		["Staff accounts cannot take part in the referral program."] =
			"Contas da staff não podem participar do programa de indicação.",
		["%d of your friends reached level %d: you received %s."] =
			"%d dos seus amigos chegaram ao nível %d: você recebeu %s.",
		["Referral codes can only be entered in the first %d days of a new account."] =
			"Códigos de indicação só podem ser usados nos primeiros %d dias de uma conta nova.",
		["No account has this referral code."] = "Nenhuma conta tem este código de indicação.",
		["Your friend %s reached level %d, but the referral rules refused the reward (a banned account, a shared connection or a shared payer)."] =
			"Seu amigo %s chegou ao nível %d, mas as regras de indicação recusaram a recompensa (uma conta banida, uma conexão ou um pagador em comum).",
		["Your friend %s reached level %d. Monthly reward limit reached: the reward waits for next month."] =
			"Seu amigo %s chegou ao nível %d. Limite mensal de recompensas atingido: a recompensa espera o próximo mês.",

		-- More chat lines: professions, battleground and arena queues, builds and the Chaos Pact, world boss and siege gates, rifts, multi-client (professions.lua, battleground.lua, arena.lua, pact.lua, pact_config.lua, worldboss.lua, siege.lua, rift.lua, chaos_constants.lua multiClient)
		["Your backpack is full: %s went to your inbox."] =
			"Sua mochila está cheia: %s foi para a sua caixa de entrada.",
		["You gathered %d %s (+%d %s experience)."] = "Você coletou %d %s (+%d de experiência de %s).",
		["Nothing worth keeping (+%d %s experience)."] = "Nada que valha guardar (+%d de experiência de %s).",
		["You advanced to %s level %d. Profession experience bonus: +%s%%."] =
			"Você avançou para %s nível %d. Bônus de experiência da profissão: +%s%%.",
		["Battleground: you left the queue."] = "Battleground: você saiu da fila.",
		["Battleground: the wards of the enemy base throw you back."] =
			"Battleground: as proteções da base inimiga te jogam para trás.",
		["Battleground: you left the queue (time out, or a party member logged out)."] =
			"Battleground: você saiu da fila (tempo esgotado, ou alguém da party deslogou).",
		["Battleground: %s"] = "Battleground: %s",
		["Battleground: you joined the queue as %s (%s). Stay in a protection zone."] =
			"Battleground: você entrou na fila como %s (%s). Fique numa zona de proteção.",
		["Battleground: %s left the queue, so did your party."] = "Battleground: %s saiu da fila, e sua party também.",
		["Battleground: you left the match early (%s). Deserter: no queue for %d minute(s)."] =
			"Battleground: você saiu da partida antes da hora (%s). Desertor: sem fila por %d minuto(s).",
		["Battleground: a match was found but could not start, you were removed from the queue: %s"] =
			"Battleground: uma partida foi encontrada mas não pôde começar, você saiu da fila: %s",
		["Battleground: Ember Wells %dv%d. You fight for the %s. The wells open in %d seconds; secure mode must be off (the client turns it off for you)."] =
			"Battleground: Ember Wells %dv%d. Você luta pelos %s. Os poços abrem em %d segundos; o secure mode precisa estar desligado (o cliente desliga para você).",
		["Arena: you left the queue."] = "Arena: você saiu da fila.",
		["Arena: you left the match (a loss)."] = "Arena: você saiu da partida (uma derrota).",
		["Arena: %s"] = "Arena: %s",
		["Arena: you joined the %s queue (rating %d). Stay in a protection zone; the Arena window leaves the queue."] =
			"Arena: você entrou na fila %s (rating %d). Fique numa zona de proteção; a janela da Arena sai da fila.",
		["Arena: %s left the queue, so did your party."] = "Arena: %s saiu da fila, e sua party também.",
		["Arena: a match was found but could not start, you were removed from the queue: %s"] =
			"Arena: uma partida foi encontrada mas não pôde começar, você saiu da fila: %s",
		["Arena %s against %s. The fight starts in %d seconds; secure mode must be off (the client turns it off for you)."] =
			"Arena %s contra %s. A luta começa em %d segundos; o secure mode precisa estar desligado (o cliente desliga para você).",
		["Build sharing is not available."] = "O compartilhamento de builds não está disponível.",
		["Your passive tree has no allocated nodes to save."] =
			"Sua árvore passiva não tem nós distribuídos para salvar.",
		["That build slot is empty."] = "Esse slot de build está vazio.",
		["Build saved in slot %d: %s (%d nodes)."] = "Build salva no slot %d: %s (%d nós).",
		["Build slot %d is empty now."] = "O slot de build %d está vazio agora.",
		["You have no active Chaos Pact."] = "Você não tem um Chaos Pact ativo.",
		["Your Chaos Pact already runs for more than %d days. Buy more later."] =
			"Seu Chaos Pact já vale por mais de %d dias. Compre mais depois.",
		["Your account already has the most of %s it can have (%d)."] =
			"Sua conta já tem o máximo de %s permitido (%d).",
		["Your account has %d of at most %d %s; this offer adds %d. Buy fewer at once."] =
			"Sua conta tem %d de no máximo %d %s; esta oferta adiciona %d. Compre menos de uma vez.",
		["This account has %d character slots and this is character number %d. Buy a Character Slot in the store with another character, or ask the staff."] =
			"Esta conta tem %d slots de personagem e este é o personagem número %d. Compre um Character Slot na loja com outro personagem, ou fale com a staff.",
		["You claimed today's %d Chaos Coins of your Chaos Pact."] =
			"Você pegou as %d Chaos Coins de hoje do seu Chaos Pact.",
		["That build slot is read-only now (your account has %d build slots). Load or delete it."] =
			"Esse slot de build agora é só leitura (sua conta tem %d slots de build). Carregue ou apague.",
		["You already claimed today's Chaos Coins. Come back tomorrow."] =
			"Você já pegou as Chaos Coins de hoje. Volte amanhã.",
		["All your build slots are used (%d). Delete one, or get another slot."] =
			"Todos os seus slots de build estão usados (%d). Apague um, ou pegue outro slot.",
		["No world boss reward: another character from your connection was online during the fight."] =
			"Sem recompensa do world boss: outro personagem da sua conexão estava online durante a luta.",
		["No world boss reward: you need a contribution (damage, healing and tanking) of at least %.2f%% of the boss health."] =
			"Sem recompensa do world boss: você precisa de uma contribuição (dano, cura e tank) de pelo menos %.2f%% da vida do boss.",
		["Another character from your connection is online: you may fight, but you will get no world boss reward."] =
			"Outro personagem da sua conexão está online: você pode lutar, mas não vai ganhar recompensa do world boss.",
		["World boss lobby: the forcefield to the north leads to the arena, the ones on the sides take you home. %s"] =
			"Lobby do world boss: o campo de força ao norte leva à arena, os dos lados te levam para casa. %s",
		["The world boss portal is closed."] = "O portal do world boss está fechado.",
		["You need level %d to face the world boss."] = "Você precisa do nível %d para enfrentar o world boss.",
		["The world boss arena is full."] = "A arena do world boss está cheia.",
		["There is no fight in the arena right now."] = "Não há luta na arena agora.",
		["The siege portal is closed."] = "O portal do siege está fechado.",
		["%s is not signed up for this siege."] = "%s não está inscrita neste siege.",
		["Only members of a signed-up guild can enter the siege."] =
			"Só membros de uma guilda inscrita podem entrar no siege.",
		["You need level %d to join the siege."] = "Você precisa do nível %d para entrar no siege.",
		["Multi-client: another character from your connection is online. Log it out to join the siege."] =
			"Multi-client: outro personagem da sua conexão está online. Deslogue-o para entrar no siege.",
		["%s already has %d members inside."] = "%s já tem %d membros lá dentro.",
		["You fought for another guild in this siege."] = "Você lutou por outra guilda neste siege.",
		["You must stand in a protection zone to open an omen arena."] =
			"Você precisa estar numa zona de proteção para abrir uma arena de omen.",
		["You must stand in a protection zone to open a rift."] =
			"Você precisa estar numa zona de proteção para abrir um rift.",
		["You need level %d to open an omen arena."] = "Você precisa do nível %d para abrir uma arena de omen.",
		["You need level %d to open a tier %d rift."] = "Você precisa do nível %d para abrir um rift tier %d.",
		["The rifts are still forming. Try again in a few seconds."] =
			"Os rifts ainda estão se formando. Tente de novo em alguns segundos.",
		["Every rift is open right now. Try again in a moment."] =
			"Todos os rifts estão abertos agora. Tente de novo daqui a pouco.",
		["You cannot enter while another character from your connection is online."] =
			"Você não pode entrar enquanto outro personagem da sua conexão está online.",
		["You cannot attack players while another character from your connection is online."] =
			"Você não pode atacar jogadores enquanto outro personagem da sua conexão está online.",
		["Not with a second character online."] = "Não com um segundo personagem online.",
		["You cannot attack players now."] = "Você não pode atacar jogadores agora.",

		-- Titles, cosmetics, appearances, pets, the Gambler, hideout likes (nameplate.lua, cosmetics.lua, transmog.lua, pets.lua, gamble.lua, hideout.lua, trials_effects.lua)
		["%s likes your hideout."] = "%s curtiu seu hideout.",
		["Your pet wards you: %s%% less damage from monsters."] = "Seu pet te protege: %s%% menos dano de monstros.",
		["Your pet fetched %d gold to your bank."] = "Seu pet buscou %d de ouro para o seu banco.",
		["%s opened a [%s] %s at the Gambler!"] = "%s abriu um [%s] %s no Gambler!",
		["You hold no titles yet. Titles come from the weekly leaderboards, the guild siege, seasons and more; they show above your name."] =
			"Você ainda não tem títulos. Títulos vêm dos rankings semanais, do guild siege, das temporadas e mais; eles aparecem acima do seu nome.",
		["Your titles: %s%s. Pick one in the Achievements window."] =
			"Seus títulos: %s%s. Escolha um na janela de Achievements.",
		[" (hidden)"] = " (oculto)",
		["Your title follows the newest you earn: %s."] = "Seu título acompanha o mais recente que você ganhar: %s.",
		["Your title follows the newest you earn."] = "Seu título acompanha o mais recente que você ganhar.",
		["You do not hold the title \"%s\"."] = "Você não tem o título \"%s\".",
		["Your title is now %s."] = "Seu título agora é %s.",
		["Your last stand holds: the lethal blow leaves you standing."] =
			"Sua última resistência aguenta: o golpe letal te deixa de pé.",
		["Cosmetic unlocked: %s. Choose it in Character > Cosmetics."] =
			"Cosmético desbloqueado: %s. Escolha em Character > Cosmetics.",
		["New appearance unlocked: %s."] = "Nova aparência desbloqueada: %s.",
		["New appearances unlocked: %s."] = "Novas aparências desbloqueadas: %s.",
		["Appearance set unlocked: %s."] = "Conjunto de aparência desbloqueado: %s.",

		-- Progression: Paragon, the passive tree, boss points, gems, salvage, archery, Ember Blessings (paragon.lua, passivetree.lua, bosspoints.lua, gems.lua, salvage.lua, archery.lua, blessings.lua)
		["Your Paragon points were refunded for free: you had spent more than your %d points."] =
			"Seus pontos Paragon foram devolvidos de graça: você tinha gastado mais do que seus %d pontos.",
		["You have %d unspent Paragon point%s. Open the passive tree and press Paragon."] =
			"Você tem %d ponto%s Paragon sem gastar. Abra a árvore passiva e aperte Paragon.",
		["Your passive tree was refunded for free: it held more nodes than your %d passive points. Please allocate them again."] =
			"Sua árvore passiva foi devolvida de graça: ela tinha mais nós do que seus %d pontos passivos. Distribua os pontos de novo.",
		["Your passive tree: %d node your class cannot hold (or that left the tree) was refunded for free."] =
			"Sua árvore passiva: %d nó que sua classe não pode ter (ou que saiu da árvore) foi devolvido de graça.",
		["Your passive tree: %d nodes your class cannot hold (or that left the tree) were refunded for free."] =
			"Sua árvore passiva: %d nós que sua classe não pode ter (ou que saíram da árvore) foram devolvidos de graça.",
		["Your passive tree: %d node whose effect changed or that left the tree was refunded for free%s."] =
			"Sua árvore passiva: %d nó cujo efeito mudou (ou que saiu da árvore) foi devolvido de graça%s.",
		["Your passive tree: %d nodes whose effect changed or that left the tree were refunded for free%s."] =
			"Sua árvore passiva: %d nós cujo efeito mudou (ou que saíram da árvore) foram devolvidos de graça%s.",
		["; your saved loadouts lost %d"] = "; seus loadouts salvos perderam %d",
		["First kill of %s: +1 passive point! %s."] = "Primeira morte de %s: +1 ponto passivo! %s.",
		["Boss passive points: +%d for bosses you had already slain (%s). %s."] =
			"Pontos passivos de boss: +%d por bosses que você já tinha matado (%s). %s.",
		["%s%s - %s. Use it with a piece of gear that has a free socket to socket it, or with %s of the same kind to combine three into one of the next quality."] =
			"%s%s - %s. Use num equipamento com um encaixe livre para encaixar, ou com %s do mesmo tipo para juntar três em uma da qualidade seguinte.",
		["a gem"] = "uma gema",
		["nothing (Perfect is the best quality)"] = "nada (Perfect é a melhor qualidade)",
		["That cannot hold gems. "] = "Isso não pode ter gemas. ",
		["Salvaged %s: %s.%s"] = "Salvage de %s: %s.%s",
		[" Your backpack is full: some went to your inbox."] =
			" Sua mochila está cheia: parte foi para a sua caixa de entrada.",
		["Salvaged %d items: %d %s%s.%s"] = "Salvage de %d itens: %d %s%s.%s",
		[" Your backpack is full: it went to your inbox."] =
			" Sua mochila está cheia: foi para a sua caixa de entrada.",
		["The ammunition slot is a second ring slot now and quivers are worn in the off-hand next to a bow or crossbow. Moved: %s."] =
			"O slot de munição agora é um segundo slot de anel e as aljavas vão na mão secundária junto de um arco ou besta. Movidos: %s.",
		["You can only wear one might ring at a time. Moved: %s."] =
			"Você só pode usar um might ring por vez. Movidos: %s.",
		["Your Ember Blessings fade: no blessings in the %s."] = "Suas Ember Blessings somem: sem bênçãos em %s.",
		-- Factions: reputation, contracts, the quartermasters (factions.lua, factions_core.lua contracts and offer states)
		["+%d reputation with %s%s."] = "+%d de reputação com %s%s.",
		["You have reached this week's reputation cap with %s."] = "Você atingiu o limite semanal de reputação com %s.",
		["%s now counts you as %s."] = "%s agora te considera %s.",
		["%s contract done: %s."] = "Contrato de %s concluído: %s.",
		["You received %d %s."] = "Você recebeu %d %s.",
		["Speak with %s (%s) for that."] = "Fale com %s (%s) para isso.",
		["%s cannot reward you more this week. Keep your tokens."] =
			"%s não pode te recompensar mais nesta semana. Guarde seus tokens.",
		["You carry no %s."] = "Você não carrega %s.",
		["The tokens could not be taken."] = "Não foi possível tirar os tokens.",
		["%s takes %d %s: +%d reputation%s."] = "%s recebe %d %s: +%d de reputação%s.",
		[" (weekly cap reached)"] = " (limite semanal atingido)",
		["That delivery is not open."] = "Essa entrega não está aberta.",
		["You need %d %s."] = "Você precisa de %d %s.",
		["You need %s gold (carried or in the bank)."] = "Você precisa de %s de ouro (carregado ou no banco).",
		["The materials could not be taken."] = "Não foi possível tirar os materiais.",
		["The gold could not be taken."] = "Não foi possível tirar o ouro.",
		["Delivered: %s."] = "Entregue: %s.",
		["Not available."] = "Indisponível.",
		["Bought: %s.%s"] = "Comprado: %s.%s",
		["You do not know that recipe."] = "Você não conhece essa receita.",
		["You need %s gold."] = "Você precisa de %s de ouro.",
		["%s: made %dx."] = "%s: feito %dx.",
		["The quartermaster's forge is cold (crafting is not loaded)."] =
			"A forja do intendente está fria (o crafting não está carregado).",
		["That item does not exist on this server."] = "Esse item não existe neste servidor.",
		["That offer is broken. Tell a gamemaster."] = "Essa oferta está quebrada. Avise um gamemaster.",
		["You have it."] = "Você já tem.",
		["Needs %s with %s."] = "Precisa de %s com %s.",
		["Bought %d of %d this week."] = "Comprado %d de %d nesta semana.",
		["Slay %d %s of level %d+"] = "Mate %d %s de level %d+",
		["Seal a tier %d+ rift of the %s"] = "Sele uma rift de tier %d+ de %s",
		["Seal %d tier %d+ rifts of the %s"] = "Sele %d rifts de tier %d+ de %s",
		["Deliver %s"] = "Entregue %s",
		["Take part in the fall of a world boss"] = "Participe da queda de um world boss",
		["Stand against an invasion"] = "Enfrente uma invasão",
		-- Bestiary: kill tasks, stages, refusals (bestiary.lua, bestiary_core.lua, bestiary_config.lua stage names)
		["%d %s of level %d-%d"] = "%d %s de level %d-%d",
		["Kill task accepted: %s."] = "Kill task aceita: %s.",
		["Another character from your connection is online: you may hunt, but this task will pay no reward."] =
			"Outro personagem da sua conexão está online: você pode caçar, mas esta task não dará recompensa.",
		["Kill task abandoned: %s."] = "Kill task abandonada: %s.",
		["Kill task completed: %s. Another character from your connection was online during the hunt: no reward."] =
			"Kill task concluída: %s. Outro personagem da sua conexão estava online durante a caçada: sem recompensa.",
		["%s bestiary points"] = "%s pontos de bestiário",
		["Kill task completed: %s. Reward: %s.%s"] = "Kill task concluída: %s. Recompensa: %s.%s",
		["Kill task completed: %d %s."] = "Kill task concluída: %d %s.",
		["Bestiary: %s discovered (+%d points)."] = "Bestiário: %s descoberto (+%d pontos).",
		["Bestiary: %s completed (+%d points). You deal %d%% more damage to it and gain %d%% more experience from it."] =
			"Bestiário: %s completo (+%d pontos). Você causa %d%% a mais de dano a ele e ganha %d%% a mais de experiência com ele.",
		["Bestiary: %s %s (+%d points)."] = "Bestiário: %s %s (+%d pontos).",
		["studied"] = "estudado",
		["mastered"] = "dominado",
		["Kill task %s: %d%% done (%d/%d)."] = "Kill task %s: %d%% feita (%d/%d).",
		["That monster is not in the bestiary."] = "Esse monstro não está no bestiário.",
		["Bosses cannot be taken as kill tasks."] = "Bosses não podem ser pegos como kill tasks.",
		["That monster does not live anywhere you can hunt it."] =
			"Esse monstro não vive em nenhum lugar onde você possa caçá-lo.",
		["Kill one first: its bestiary entry must be discovered."] =
			"Mate um primeiro: a entrada dele no bestiário precisa estar descoberta.",
		["That monster is not for your level (hunting level %d, yours: %d-%d)."] =
			"Esse monstro não é para o seu level (level de caça %d, o seu: %d-%d).",
		["That task is not on your board."] = "Essa task não está no seu quadro.",
		["You already hold that task."] = "Você já tem essa task.",
		["You already completed that task today."] = "Você já concluiu essa task hoje.",
		["You can hold at most %d kill tasks at once."] = "Você pode ter no máximo %d kill tasks ao mesmo tempo.",
		["You can complete at most %d kill tasks a day."] = "Você pode concluir no máximo %d kill tasks por dia.",
		["You can complete at most %d kill tasks a week."] = "Você pode concluir no máximo %d kill tasks por semana.",
		-- Season pass: tiers, claims, challenges, premium and packs (seasonpass.lua, seasonpass_core.lua, seasonpass_config.lua challenges)
		["a shader"] = "um shader",
		["Season pass cosmetics of your account: %s."] = "Cosméticos do season pass da sua conta: %s.",
		["Season pass tier %d (%s): %s."] = "Season pass tier %d (%s): %s.",
		["premium"] = "premium",
		["free"] = "grátis",
		["Season pass: claimed %d reward%s: %s."] = "Season pass: resgatou %d recompensa%s: %s.",
		["%s The other items wait for you."] = "%s Os outros itens esperam por você.",
		["%s: %d reward%s to claim in Adventure > Season Pass."] =
			"%s: %d recompensa%s para resgatar em Adventure > Season Pass.",
		["No season pass is running."] = "Nenhum season pass está ativo.",
		["%s: tier %d reached! Claim your rewards in Adventure > Season Pass."] =
			"%s: tier %d alcançado! Resgate suas recompensas em Adventure > Season Pass.",
		["%s: tiers %d to %d reached! Claim your rewards in Adventure > Season Pass."] =
			"%s: tiers %d a %d alcançados! Resgate suas recompensas em Adventure > Season Pass.",
		["Tier %d reached! New rewards to claim."] = "Tier %d alcançado! Novas recompensas para resgatar.",
		["Daily challenge done: %s (+%d pass XP)."] = "Desafio diário concluído: %s (+%d de XP do pass).",
		["Weekly challenge done: %s (+%d pass XP)."] = "Desafio semanal concluído: %s (+%d de XP do pass).",
		["Challenge done: +%d pass XP."] = "Desafio concluído: +%d de XP do pass.",
		["Premium %s: the %d reward of the tiers you already reached is yours: %s."] =
			"Premium %s: a %d recompensa dos tiers que você já alcançou é sua: %s.",
		["Premium %s: the %d rewards of the tiers you already reached are yours: %s."] =
			"Premium %s: as %d recompensas dos tiers que você já alcançou são suas: %s.",
		["%d premium reward%s unlocked"] = "%d recompensa%s premium para você",
		["That account already has the premium %s."] = "Essa conta já tem o %s premium.",
		["The premium %s is unlocked for your whole account. Its rewards wait in Adventure > Season Pass."] =
			"O %s premium está liberado para toda a sua conta. As recompensas esperam em Adventure > Season Pass.",
		["Premium track unlocked!"] = "Trilha premium liberada!",
		["That account already owns %s."] = "Essa conta já possui %s.",
		["%s is yours: its cosmetics are on every character of your account."] =
			"%s é seu: os cosméticos estão em todos os personagens da sua conta.",
		["%s unlocked!"] = "%s liberado!",
		["%s already has it."] = "%s já tem.",
		["The price is %d Chaos Coins for %s. Please confirm again."] =
			"O preço é %d Chaos Coins para %s. Confirme de novo.",
		["The price is %d Chaos Coins. Please confirm again."] = "O preço é %d Chaos Coins. Confirme de novo.",
		["You need %d Chaos Coins (you have %d)."] = "Você precisa de %d Chaos Coins (você tem %d).",
		["%s gave your account %s."] = "%s deu à sua conta %s.",
		["Your account gets this for %d Chaos Coins (the difference to what it already owns): buy it in Adventure > Season Pass, Packs."] =
			"Sua conta recebe isto por %d Chaos Coins (a diferença para o que ela já possui): compre em Adventure > Season Pass, Packs.",
		["Title: %s"] = "Título: %s",
		["%s Chaos Coins"] = "%s Chaos Coins",
		["%s tier skips"] = "%s tier skips",
		["Premium pass"] = "Pass premium",
		["Nothing to claim."] = "Nada para resgatar.",
		["Gift sent."] = "Presente enviado.",
		["Purchase complete."] = "Compra concluída.",
		["Already claimed."] = "Já resgatado.",
		["This pack does not exist."] = "Este pack não existe.",
		["That tier does not exist."] = "Esse tier não existe.",
		["Unknown track."] = "Trilha desconhecida.",
		["The season pass is closed: its season is over."] = "O season pass está fechado: a season acabou.",
		["This reward is on the premium track."] = "Esta recompensa está na trilha premium.",
		["The store is not available: try again later."] = "A loja não está disponível: tente mais tarde.",
		["The season pass can only be bought while its season runs."] =
			"O season pass só pode ser comprado enquanto a season está ativa.",
		["That account already has the premium pass."] = "Essa conta já tem o pass premium.",
		["Season packs can only be bought while their season runs."] =
			"Os packs de season só podem ser comprados enquanto a season está ativa.",
		["Only while the season runs."] = "Só enquanto a season está ativa.",
		["Owned."] = "Já possui.",
		["That is a character of your own account: use Buy."] = "Esse é um personagem da sua própria conta: use Buy.",
		["This season's pass and packs can only be bought while the season runs."] =
			"O pass e os packs desta season só podem ser comprados enquanto a season está ativa.",
		["Slay 3000 monsters"] = "Mate 3000 monstros",
		["Gain two levels' worth of experience"] = "Ganhe o equivalente a dois levels de experiência",
		["Complete 10 bounty contracts"] = "Conclua 10 contratos de bounty",
		["Clear 5 rifts"] = "Limpe 5 rifts",
		["Clear 2 rifts of tier 8 or higher"] = "Limpe 2 rifts de tier 8 ou maior",
		["Defeat 3 bosses"] = "Derrote 3 bosses",
		["Defend against an invasion"] = "Defenda contra uma invasão",
		["Slay a treasure goblin"] = "Mate um treasure goblin",
		["Slay 300 monsters"] = "Mate 300 monstros",
		["Slay 500 monsters"] = "Mate 500 monstros",
		["Gain 30% of a level"] = "Ganhe 30% ou mais de um level",
		["Complete 2 bounty contracts"] = "Conclua 2 contratos de bounty",
		["Clear a rift"] = "Limpe uma rift",
		["Complete 3 bounty contracts"] = "Conclua 3 contratos de bounty",
		["Slay 200 monsters"] = "Mate 200 monstros",
		["Gain 20% of a level"] = "Ganhe 20% ou mais de um level",
		["Clear 2 rifts"] = "Limpe 2 rifts",
		-- Community goal: the Great Brazier, stages, the week's modifiers (community.lua, community_core.lua, community_config.lua texts)
		["Forgefire: the orb was not used up."] = "Forgefire: o orbe não foi gasto.",
		["the title %s for %d days (place %d)"] = "o título %s por %d dias (lugar %d)",
		["Community goal reward (%d points): %s."] = "Recompensa da meta comunitária (%d pontos): %s.",
		["The Brazier is cold."] = "O Brazier está frio.",
		["Staff donations do not count."] = "Doações da staff não contam.",
		["Stand next to the Great Brazier in the temple to give gold."] =
			"Fique ao lado do Great Brazier no templo para dar ouro.",
		["You do not have that much gold (backpack and bank)."] = "Você não tem todo esse ouro (mochila e banco).",
		["The Brazier flares: %d gold given, +%d points."] = "O Brazier se inflama: %d de ouro dado, +%d pontos.",
		["Standard realm"] = "Reino padrão",
		["Season %d"] = "Season %d",
		["The community goal ended at %d%%.%s"] = "A meta comunitária terminou em %d%%.%s",
		[" Top contributors: %s."] = " Maiores contribuidores: %s.",
		["%s A new community goal begins: %s."] = "%s Uma nova meta comunitária começa: %s.",
		["Community goal %d%% reached%s! %s: %s for %d hours."] =
			"Meta comunitária de %d%% alcançada%s! %s: %s por %d horas.",
		["The Great Brazier burns at %d%%: keep feeding it!"] = "O Great Brazier queima a %d%%: continue alimentando!",
		["A new week: the world changes. %s (Adventure > Community)."] =
			"Uma nova semana: o mundo muda. %s (Adventure > Community).",
		["Give at least %d gold."] = "Dê pelo menos %d de ouro.",
		["The Brazier has taken all it will from you today."] =
			"O Brazier já aceitou tudo o que aceitaria de você hoje.",
		["%s (%s left)"] = "%s (faltam %s)",
		["Community goal \"%s\": %d%% (%s left this period)%s."] =
			"Meta comunitária \"%s\": %d%% (faltam %s neste período)%s.",
		["; active: %s"] = "; ativos: %s",
		["World modifiers this week - %s"] = "Modificadores do mundo nesta semana - %s",
		["2 Orbs of Upheaval and an Orb of Fate"] = "2 Orbs of Upheaval e um Orb of Fate",
		["+10% experience from monsters"] = "+10% experiência dos monstros",
		["+10% Chaos loot quantity (extra loot rolls and currency)"] =
			"+10% Chaos loot em quantidade (rolagens extras de loot e moedas)",
		["+5% chance of a new Rift Key when a rift is sealed"] =
			"+5% chance de uma nova Rift Key quando uma rift é selada",
		["+20% faction reputation and +5% experience"] = "+20% fama com as facções e +5% experiência",
		["Rifts open with one more modifier, and their rewards are 15% richer."] =
			"Rifts abrem com um modificador a mais, e as recompensas ficam 15% mais ricas.",
		["Magic, rare and legendary monsters appear 50% more often."] =
			"Monstros magic, rare e legendary aparecem 50% mais vezes.",
		["Undead give 30% more experience and 30% more Chaos loot."] =
			"Undead dão 30% mais experiência e 30% mais Chaos loot.",
		["Treasure goblins appear twice as often."] = "Treasure goblins aparecem duas vezes mais.",
		["Crafting orbs cost 20% less: each orb used has a 20% chance to be kept."] =
			"Orbes de crafting custam 20% menos: cada orbe usado tem 20% chance de ser mantido.",
		["Dragons give 25% more experience and 25% more Chaos loot."] =
			"Dragons dão 25% mais experiência e 25% mais Chaos loot.",
		["Ambushes after a kill are 50% more likely."] = "Emboscadas após uma morte ficam 50% mais prováveis.",
		["Faction reputation gains are 20% higher."] = "Ganhos de reputação com facções ficam 20% maiores.",
		["The Infinity Tower gives 50% more points."] = "A Infinity Tower dá 50% mais pontos.",
		-- Dungeons, treasure goblins and Chaos loot (dungeons.lua, treasure_goblin.lua and its config, loot.lua and loot_config.lua)
		["You are already inside a dungeon."] = "Você já está dentro de uma dungeon.",
		["You cannot queue from inside the dungeon."] = "Você não pode entrar na fila de dentro da dungeon.",
		["You cannot enter a dungeon while you are in a fight."] =
			"Você não pode entrar em uma dungeon enquanto está em luta.",
		["You need level %s."] = "Você precisa de level %s.",
		["You are in cooldown for dungeons. Wait %d minute(s)."] =
			"Você está em cooldown de dungeons. Espere %d minuto(s).",
		["That difficulty is still locked."] = "Essa dificuldade ainda está bloqueada.",
		["You were unable to complete the dungeon in time."] = "Você não conseguiu completar a dungeon a tempo.",
		["You were unable to complete the dungeon in the respective time.\n\nNext time you will do it better!"] =
			"Você não conseguiu completar a dungeon no tempo previsto.\n\nDa próxima vez você vai se sair melhor!",
		["A gamemaster closed the dungeon."] = "Um gamemaster fechou a dungeon.",
		["Your dungeon run was cut short by a server restart."] =
			"Sua run de dungeon foi interrompida por um restart do servidor.",
		["You logged out inside the dungeon: your run is over."] =
			"Você saiu do jogo dentro da dungeon: sua run acabou.",
		["%s hoard: %s"] = "Tesouro de %s: %s",
		["A %s appears!"] = "Um %s aparece!",
		["The %s escaped through a portal with its loot!"] = "O %s escapou por um portal com o loot!",
		["%s slew a %s!"] = "%s matou um %s!",
		["Chaos bonus loot of %s: %s"] = "Chaos loot bônus de %s: %s",
		["A unique item drops from %s: %s!"] = "Um item único cai de %s: %s!",
		["%s found %s!"] = "%s encontrou %s!",
		-- Who stays behind (rift.lua, uber.lua, descent.lua, raid.lua: the reasons in the third person and, through ChaosI18n.you, the second), the rift HUD notes, the Descent and raid entry
		["%s stays behind: %s."] = "%s fica para trás: %s.",
		["You stay behind from %s's rift: you %s."] = "Você fica fora da rift de %s: você %s.",
		["You stay behind from %s's arena: you %s."] = "Você fica fora da arena de %s: você %s.",
		["You stay behind from %s's descent: you %s."] = "Você fica fora da descent de %s: você %s.",
		["You %s."] = "Você %s.",
		["is already inside a rift"] = "já está dentro de uma rift",
		["are already inside a rift"] = "já está dentro de uma rift",
		["needs level %d for an omen arena"] = "precisa de level %d para uma omen arena",
		["need level %d for an omen arena"] = "precisa de level %d para uma omen arena",
		["needs level %d for a tier %d rift"] = "precisa de level %d para uma rift de tier %d",
		["need level %d for a tier %d rift"] = "precisa de level %d para uma rift de tier %d",
		["has another character from the same connection online"] = "tem outro personagem da mesma conexão online",
		["have another character from the same connection online"] = "tem outro personagem da mesma conexão online",
		["is in a fight"] = "está em luta",
		["are in a fight"] = "está em luta",
		["is inside a dungeon, the tower or the world boss arena"] =
			"está dentro de uma dungeon, da tower ou da arena do world boss",
		["are inside a dungeon, the tower or the world boss arena"] =
			"está dentro de uma dungeon, da tower ou da arena do world boss",
		["is already in the Descent"] = "já está na Descent",
		["are already in the Descent"] = "já está na Descent",
		["needs level %d"] = "precisa de level %d",
		["need level %d"] = "precisa de level %d",
		["is inside another instance"] = "está dentro de outra instância",
		["are inside another instance"] = "está dentro de outra instância",
		["has used the free weekly descent and carries no Ember Sigil"] =
			"já usou a descent semanal grátis e não carrega Ember Sigil",
		["have used the free weekly descent and carry no Ember Sigil"] =
			"já usou a descent semanal grátis e não carrega Ember Sigil",
		["has used today's free descent and carries no Ember Sigil"] =
			"já usou a descent grátis de hoje e não carrega Ember Sigil",
		["have used today's free descent and carry no Ember Sigil"] =
			"já usou a descent grátis de hoje e não carrega Ember Sigil",
		["is already in the raid"] = "já está no raid",
		["are already in the raid"] = "já está no raid",
		["is already inside an Ascended arena"] = "já está dentro de uma Ascended arena",
		["are already inside an Ascended arena"] = "já está dentro de uma Ascended arena",
		["is inside a rift, a dungeon, the tower or the world boss arena"] =
			"está dentro de uma rift, uma dungeon, da tower ou da arena do world boss",
		["are inside a rift, a dungeon, the tower or the world boss arena"] =
			"está dentro de uma rift, uma dungeon, da tower ou da arena do world boss",
		["%s is in a fight."] = "%s está em luta.",
		["A sealed coffer waits to the %s."] = "Um cofre selado espera (direção: %s).",
		["far side"] = "lado oposto",
		["north-east"] = "nordeste",
		["north-west"] = "noroeste",
		["south-east"] = "sudeste",
		["south-west"] = "sudoeste",
		["centre"] = "centro",
		["Coffer guards: %d left."] = "Guardas do cofre: faltam %d.",
		["The coffer is open."] = "O cofre está aberto.",
		["A Treasure Goblin is loose!"] = "Um Treasure Goblin está à solta!",
		["Guardians left: %d."] = "Guardiões restantes: %d.",
		["%d fallen player may still return."] = "%d jogador caído ainda pode voltar.",
		["%d fallen players may still return."] = "%d jogadores caídos ainda podem voltar.",
		["%d more pack gather."] = "Mais %d pack se reúne.",
		["%d more packs gather."] = "Mais %d packs se reúnem.",
		["+%s%% packs"] = "+%s%% packs",
		["+%s%% time"] = "+%s%% tempo",
		["+%s life"] = "+%s vida",
		["+%s lives"] = "+%s vidas",
		["Atlas: %s"] = "Atlas: %s",
		["You cannot enter now."] = "Você não pode entrar agora.",
		["The Ember Descent is closed."] = "A Ember Descent está fechada.",
		["You are already in the Descent."] = "Você já está na Descent.",
		["You must stand in a protection zone to enter the Descent."] =
			"Você precisa estar em uma zona de proteção para entrar na Descent.",
		["Every hall of the Descent is taken right now. Try again in a moment."] =
			"Todos os salões da Descent estão ocupados agora. Tente de novo em instantes.",
		["%s's sigil could not be used."] = "O sigil de %s não pôde ser usado.",
		["Your free weekly descent is used and you carry no Ember Sigil."] =
			"Sua descent semanal grátis já foi usada e você não carrega Ember Sigil.",
		["Your free descent of today is used and you carry no Ember Sigil."] =
			"Sua descent grátis de hoje já foi usada e você não carrega Ember Sigil.",
		["The Sepulchre is sealed."] = "O Sepulchre está selado.",
		["You are already in the raid."] = "Você já está no raid.",
		["You must stand in a protection zone to open the raid."] =
			"Você precisa estar em uma zona de proteção para abrir o raid.",
		["That raid does not exist."] = "Esse raid não existe.",
		["That raid belongs to an earlier week."] = "Esse raid é de uma semana anterior.",
		["That raid is cleared."] = "Esse raid já foi concluído.",
		["You were not in that raid."] = "Você não estava nesse raid.",
		["You cannot continue that raid."] = "Você não pode continuar esse raid.",
		["That raid is open right now: join it from the window."] =
			"Esse raid está aberto agora: entre nele pela janela.",
		["Every wing of the Sepulchre is taken right now. Try again in a moment."] =
			"Todas as alas do Sepulchre estão ocupadas agora. Tente de novo em instantes.",
		["The raid could not be saved (database)."] = "Não foi possível salvar o raid (banco de dados).",
		["That raid is not open."] = "Esse raid não está aberto.",
		["Only its members (or the party of one inside) may join this raid."] =
			"Só os membros (ou a party de alguém lá dentro) podem entrar neste raid.",
		["The raid is full."] = "O raid está cheio.",
		["You must stand in a protection zone to join the raid."] =
			"Você precisa estar em uma zona de proteção para entrar no raid.",
		-- Pocket bosses (pocketboss.lua, pocketboss_core.lua)
		["Pocket reward of %s: %s.%s"] = "Recompensa do pocket de %s: %s.%s",
		["Every pocket arena is in use. Try again in a moment."] = "Todas as arenas de pocket estão em uso. Tente de novo em instantes.",
		["Personal loot of %s (%.1f%% of its health in damage and healing): %s.%s"] =
			"Loot pessoal de %s (%.1f%% da vida dele em dano e cura): %s.%s",
		["nothing this time"] = "nada desta vez",
		["%s falls in %s. The pocket closes in %d seconds: loot the corpse, or leave now through the forcefield by the arrival."] =
			"%s cai em %s. O pocket fecha em %d segundos: pegue o loot do corpo, ou saia agora pelo campo de força junto à chegada.",
		["Pocket loot of %s: %s.%s"] = "Loot do pocket de %s: %s.%s",
		["%s appears. You have %d minutes."] = "%s aparece. Você tem %d minutos.",
		["Pocket of %s: it comes in %d seconds. %d%% experience and loot; the way out is in the room to the south."] =
			"Pocket de %s: ele chega em %d segundos. %d%% de experiência e loot; a saída fica na sala ao sul.",
		["%s falls and is carried out of the pocket."] = "%s cai e é levado para fora do pocket.",
		["The boss did not answer; your charge is given back."] = "O boss não respondeu; sua carga foi devolvida.",
		["Time is up: %s still stands."] = "O tempo acabou: %s continua de pé.",
		["A gamemaster closed the pocket."] = "Um gamemaster fechou o pocket.",
		["Ended by the staff."] = "Encerrado pela equipe.",
		["the pocket is full"] = "o pocket está cheio",
		["You stay behind from the pocket of %s: %s."] = "Você fica de fora do pocket de %s: %s.",
		["The server is restarting: the pocket closes and your charge is given back."] =
			"O servidor está reiniciando: o pocket fecha e sua carga é devolvida.",
		["No pocket charges left for this boss today. They come back in %s."] =
			"Sem cargas de pocket para este boss hoje. Elas voltam em %s.",
		["You hold the most bonus charges for this boss (%d)."] = "Você já tem o máximo de cargas bônus para este boss (%d).",
		["No more bonus charges for this boss today (%d a day)."] = "Sem mais cargas bônus para este boss hoje (%d por dia).",
		["Pocket bosses are switched off."] = "Os pocket bosses estão desligados.",
		["There is no pocket of that boss."] = "Não existe pocket desse boss.",
		["You need level %d for the pocket of %s."] = "Você precisa de level %d para o pocket de %s.",
		["Leave %s first."] = "Saia de %s primeiro.",
		["Open a pocket from a protection zone."] = "Abra um pocket a partir de uma zona de proteção.",
		["You are in combat."] = "Você está em combate.",
		["Wait %d seconds before opening another pocket."] = "Espere %d segundos antes de abrir outro pocket.",
		["You were rewarded by the %s fight less than an hour ago: its pocket opens for you in %s."] =
			"Você foi recompensado pela luta de %s há menos de uma hora: o pocket dele abre para você em %s.",
		["level %d needed"] = "level %d necessário",
		["inside %s"] = "dentro de %s",
		["too far away"] = "longe demais",
		["in combat"] = "em combate",
		["rewarded by this boss's event within the hour"] = "recompensado pelo evento deste boss nesta hora",
		["no charges left"] = "sem cargas",
		-- Conquest Tokens, the Conquest vendor and bad-luck protection (conquest.lua, conquest_core.lua K.reasons, the vendor NPC)
		["The Conquest vendor is closed."] = "O vendedor de Conquest está fechado.",
		["There is no such offer."] = "Essa oferta não existe.",
		["You do not have enough Conquest Tokens."] = "Você não tem Conquest Tokens suficientes.",
		["You have not seen this item yet: find it once, slay a monster that drops it, or reach its level band."] =
			"Você ainda não viu este item: encontre-o uma vez, mate um monstro que o derruba ou chegue à faixa de nível dele.",
		["This season item is not for sale to your character."] = "Este item de temporada não está à venda para o seu personagem.",
		["Visit the Conquest vendor from a protection zone."] = "Visite o vendedor de Conquest em uma zona de proteção.",
		["Wear an item with a rarity in that slot first."] = "Primeiro equipe um item com raridade nesse slot.",
		["Uniques keep their stats: they cannot be refined."] = "Únicos mantêm seus atributos: não podem ser refinados.",
		["A ruined item cannot be refined."] = "Um item arruinado não pode ser refinado.",
		["A corrupted item cannot be refined."] = "Um item corrompido não pode ser refinado.",
		["This item is already at the highest rarity a refinement reaches."] =
			"Este item já está na maior raridade que um refinamento alcança.",
		["Choose two different kinds."] = "Escolha dois tipos diferentes.",
		["There is no such kind."] = "Esse tipo não existe.",
		["You do not carry enough of that kind to convert."] = "Você não carrega o suficiente desse tipo para converter.",
		["Carry an Omen Key to attune it."] = "Carregue uma Omen Key para sintonizá-la.",
		["Your level is too low for that."] = "Seu nível é baixo demais para isso.",
		["%s is now %s (%d Conquest Tokens)."] = "%s agora é %s (%d Conquest Tokens).",
		["+%d Conquest Tokens (%s). Balance: %d."] = "+%d Conquest Tokens (%s). Saldo: %d.",
		["Ascended Shards are not installed on this server. Your tokens are back."] =
			"Ascended Shards não estão instalados neste servidor. Seus tokens voltaram.",
		["Bought with Conquest Tokens"] = "Comprado com Conquest Tokens",
		["Conquest Tokens: today's limit for %s is reached (%d)."] = "Conquest Tokens: o limite de hoje para %s foi atingido (%d).",
		["Converted"] = "Convertido",
		["Converted %d %s into one of %s."] = "Convertidos %d %s em um de %s.",
		["New modifier: %s."] = "Novo modificador: %s.",
		["The key could not be made. Your tokens are back."] = "A chave não pôde ser feita. Seus tokens voltaram.",
		["The relics could not be taken."] = "As relíquias não puderam ser retiradas.",
		["The shards could not be taken."] = "Os fragmentos não puderam ser retirados.",
		["The vendor shakes her head. Try again."] = "A vendedora balança a cabeça. Tente de novo.",
		["The vendor's stock is empty for that item. Your tokens are untouched."] =
			"O estoque da vendedora está vazio para esse item. Seus tokens não foram tocados.",
		["You bought %s for %d Conquest Tokens.%s"] = "Você comprou %s por %d Conquest Tokens.%s",
		["You bought an Ascended Shard (%s) for %d Conquest Tokens."] = "Você comprou um Ascended Shard (%s) por %d Conquest Tokens.",
		["You bought an Omen Key (%s) for %d Conquest Tokens."] = "Você comprou uma Omen Key (%s) por %d Conquest Tokens.",
		["Your Omen Key now opens the %s guardian's arena (%d Conquest Tokens)."] =
			"Sua Omen Key agora abre a arena do guardião %s (%d Conquest Tokens).",
		["Every trophy has a price, |PLAYERNAME|, and you have been paying it in blood. Want to see my {wares}? Ask about {tokens} or {luck}."] =
			"Todo troféu tem um preço, |PLAYERNAME|, e você vem pagando em sangue. Quer ver minhas {wares}? Pergunte sobre {tokens} ou {luck}.",
		["Come back with more conquests, |PLAYERNAME|."] = "Volte com mais conquistas, |PLAYERNAME|.",
		["The ledger stays open for you."] = "O livro de registros fica aberto para você.",
		["Pick what you need. Anything you have seen fall, or anything of your level, is on my ledger."] =
			"Escolha o que precisa. Tudo o que você viu cair, ou tudo do seu nível, está no meu registro.",
		["Conquest Tokens come from every boss you help slay, every sealed rift, dungeon, Descent run and defended town. The harder the fight, the more you earn."] =
			"Conquest Tokens vêm de cada chefe que você ajuda a matar, cada rift selado, dungeon, corrida da Descent e cidade defendida. Quanto mais difícil a luta, mais você ganha.",
		["Every time a boss, a raid or a chest keeps its treasure from you, the next try gets kinder. Once it drops, the count starts over. The window shows how far along you are."] =
			"Cada vez que um chefe, uma raid ou um baú guarda o tesouro de você, a próxima tentativa fica mais generosa. Quando ele cai, a contagem recomeça. A janela mostra quanto falta.",
		["Iselde Varrow. I keep the ledger of conquests. Ask about my {wares}."] =
			"Iselde Varrow. Eu guardo o registro das conquistas. Pergunte sobre minhas {wares}.",
		-- Candlemarks (candlemarks.lua, candlemarks_config.lua messages and offers, NPC Osric the Chandler)
		["Candlemarks are switched off."] = "As Candlemarks estão desligadas.",
		["That offer is not in the shop."] = "Essa oferta não está na loja.",
		["You need level %d for that."] = "Você precisa do nível %d para isso.",
		["You need %d Candlemarks for that."] = "Você precisa de %d Candlemarks para isso.",
		["Weekly limit reached for that offer."] = "Limite semanal dessa oferta atingido.",
		["Your account already has that."] = "Sua conta já tem isso.",
		["That offer is not available right now."] = "Essa oferta não está disponível agora.",
		["One purchase at a time."] = "Uma compra de cada vez.",
		["Visit Osric the Chandler to buy (at the temple)."] = "Visite Osric the Chandler para comprar (no templo).",
		["The purchase could not be written down. Nothing was taken; try again."] =
			"Não foi possível registrar a compra. Nada foi cobrado; tente de novo.",
		["Bought %s for %d Candlemarks."] = "Comprou %s por %d Candlemarks.",
		["Your backpack is full: the rest went to your inbox."] = "Sua mochila está cheia: o resto foi para o seu inbox.",
		["You earned a Candlemark. Your account has %d."] = "Você ganhou uma Candlemark. Sua conta tem %d.",
		["Your account reached today's Candlemark limit."] = "Sua conta atingiu o limite de Candlemarks de hoje.",
		["Pocket Boss Charge"] = "Carga de Pocket Boss",
		["One extra charge for the pocket boss you choose."] = "Uma carga extra para o pocket boss que você escolher.",
		["Common crafting orbs."] = "Orbes de criação comuns.",
		["Raises a modifier you choose by one tier."] = "Sobe em um tier um modificador que você escolher.",
		["Lifts an item one rarity, up to Legendary."] = "Sobe um item em uma raridade, até Lendário.",
		["Rolls the values of an item's modifiers again."] = "Rola de novo os valores dos modificadores de um item.",
		["A crafting orb for the patient."] = "Um orbe de criação para os pacientes.",
		["A rare crafting orb, once a week."] = "Um orbe de criação raro, uma vez por semana.",
		["Raise the quality of an item."] = "Aumentam a qualidade de um item.",
		["Chipped Gem"] = "Gema Chipped",
		["A random gem of the lowest quality."] = "Uma gema aleatória da menor qualidade.",
		["Flawed Gem"] = "Gema Flawed",
		["A random gem of the second quality."] = "Uma gema aleatória da segunda qualidade.",
		["Salvage material."] = "Material de salvage.",
		["Hunting Supplies I"] = "Suprimentos de Caça I",
		["Hunting Supplies II"] = "Suprimentos de Caça II",
		["Hunting Supplies III"] = "Suprimentos de Caça III",
		["50 health and 50 mana potions."] = "50 poções de vida e 50 de mana.",
		["25 great health and 25 great mana potions."] = "25 grandes poções de vida e 25 grandes de mana.",
		["25 ultimate health and 25 great spirit potions."] = "25 poções de vida supremas e 25 grandes poções de espírito.",
		["Rested Vial"] = "Frasco de Descanso",
		["Stored rested experience for your next hunt."] = "Experiência de descanso guardada para a sua próxima caçada.",
		["Bounty Reroll"] = "Novo sorteio de Bounty",
		["Draw one bounty contract again."] = "Sorteia de novo um contrato de bounty.",
		["Kill Task Reroll"] = "Novo sorteio de Kill Task",
		["Draw one kill task again."] = "Sorteia de novo uma kill task.",
		["Candle Seal"] = "Selo de Vela",
		["A kill effect: a seal of candlelight. For the account."] = "Um efeito de abate: um selo de luz de vela. Para a conta.",
		["Candlelight Name"] = "Nome à Luz de Vela",
		["Your name in chat in candlelight. For the account."] = "Seu nome no chat à luz de vela. Para a conta.",
		["Tallow Labels"] = "Rótulos de Sebo",
		["Loot labels on warm tallow. For the account."] = "Rótulos de loot sobre sebo morno. Para a conta.",
		["Welcome, |PLAYERNAME|. Every half hour you spend among us burns a mark into my candles. Care to see my {wares}?"] =
			"Bem-vindo, |PLAYERNAME|. Cada meia hora que você passa entre nós queima uma marca nas minhas velas. Quer ver minhas {wares}?",
		["Keep your wick dry, |PLAYERNAME|."] = "Mantenha seu pavio seco, |PLAYERNAME|.",
		["The candles burn on without you."] = "As velas continuam queimando sem você.",
		["Here is what your marks can buy. Some of it only once a week, mind you."] =
			"Eis o que suas marcas compram. Algumas coisas só uma vez por semana, veja bem.",
		["Every %d minutes a soul spends in this world, a mark is burnt in for its account. Two souls per hearth at most."] =
			"A cada %d minutos que uma alma passa neste mundo, uma marca é queimada para a conta dela. No máximo duas almas por lar.",
		["Osric, chandler. I count the hours you keep the dark at bay. Ask about my {wares}."] =
			"Osric, fabricante de velas. Conto as horas em que você mantém a escuridão longe. Pergunte sobre minhas {wares}.",
		-- Beta starter coins (beta.lua)
		["Beta: your account received %d Chaos Coins to try the store. They are beta test coins: they and everything bought with them are wiped at launch."] =
			"Beta: sua conta recebeu %d Chaos Coins para testar a loja. São moedas de teste do beta: elas e tudo o que for comprado com elas serão apagados no lançamento.",
		-- Info & Services: Ancestral Store, Character Info (commands_ui.lua, class_unlocks.lua, ascension_quest.lua)
		["Wait a moment between purchases."] = "Espere um momento entre as compras.",
		["The purchase failed. Try again."] = "A compra falhou. Tente de novo.",
		["You need %d Ancestral Points; you have %d."] = "Você precisa de %d Ancestral Points; você tem %d.",
		["No room in your backpack: your %d Ancestral Points were returned."] =
			"Sem espaço na mochila: seus %d Ancestral Points foram devolvidos.",
		["Bought %dx %s; no room for the rest: %d Ancestral Points returned."] =
			"Comprou %dx %s; sem espaço para o resto: %d Ancestral Points devolvidos.",
		["Bought %dx %s for %d Ancestral Points."] = "Comprou %dx %s por %d Ancestral Points.",
		["Choose between 1 and %d."] = "Escolha entre 1 e %d.",
		["That item is not in the store."] = "Esse item não está na loja.",
		["No Double EXP active."] = "Nenhum Double EXP ativo.",
		["Unlocked classes: %s."] = "Classes desbloqueadas: %s.",
		["Locked classes: %s. Reach level %d with any character to unlock."] =
			"Classes bloqueadas: %s. Chegue ao nível %d com qualquer personagem para desbloquear.",
		["Locked classes: %s. To unlock: %s."] = "Classes bloqueadas: %s. Para desbloquear: %s.",
		["Ascension unlocks at level %d (you are level %d)."] = "A ascensão abre no nível %d (você está no nível %d).",
		-- Passive tree stat help (passivetree_stats_config.lua)
		["Elemental damage"] =
			"Dano elemental",
		["Resists"] =
			"Resistências",
		["Melee skills"] =
			"Skills corpo a corpo",
		["Life leech"] =
			"Roubo de vida",
		["Mana leech"] =
			"Roubo de mana",
		["Critical hits"] =
			"Golpes críticos",
		["Shielding"] =
			"Escudo",
		["Crafting skills"] =
			"Skills de criação",
		["Strength"] =
			"Força",
		["Intelligence"] =
			"Inteligência",
		["Dexterity"] =
			"Destreza",
		["Vitality"] =
			"Vitalidade",
		["Spirit"] =
			"Espírito",
		["Wisdom"] =
			"Sabedoria",
		["Speed"] =
			"Velocidade",
		["Experience"] =
			"Experiência",
		["Item find"] =
			"Item find",
		["Item rarity"] =
			"Raridade de item",
		["Sword skill"] =
			"Skill de espada",
		["Axe skill"] =
			"Skill de machado",
		["Club skill"] =
			"Skill de clava",
		["Distance skill"] =
			"Skill de distância",
		["Magic level"] =
			"Magic level",
		["Crit chance"] =
			"Chance de crítico",
		["Crit amount"] =
			"Dano crítico",
		["Life leech chance"] =
			"Chance de roubo de vida",
		["Life leech amount"] =
			"Quantidade de roubo de vida",
		["Mana leech chance"] =
			"Chance de roubo de mana",
		["Mana leech amount"] =
			"Quantidade de roubo de mana",
		["All elements"] =
			"Todos os elementos",
		["Physical damage"] =
			"Dano físico",
		["Fire damage"] =
			"Dano de fogo",
		["Ice damage"] =
			"Dano de gelo",
		["Energy damage"] =
			"Dano de energia",
		["Earth damage"] =
			"Dano de terra",
		["Death damage"] =
			"Dano de morte",
		["Holy damage"] =
			"Dano sagrado",
		["Arcane damage"] =
			"Dano arcano",
		["Water damage"] =
			"Dano de água",
		["Healing"] =
			"Cura",
		["Life drain damage"] =
			"Dano de life drain",
		["Mana drain damage"] =
			"Dano de mana drain",
		["Physical resist"] =
			"Resistência física",
		["Fire resist"] =
			"Resistência a fogo",
		["Ice resist"] =
			"Resistência a gelo",
		["Energy resist"] =
			"Resistência a energia",
		["Earth resist"] =
			"Resistência a terra",
		["Death resist"] =
			"Resistência a morte",
		["Holy resist"] =
			"Resistência sagrada",
		["Arcane resist"] =
			"Resistência arcana",
		["Water resist"] =
			"Resistência a água",
		["Life drain resist"] =
			"Resistência a life drain",
		["Mana drain resist"] =
			"Resistência a mana drain",
		["All resists"] =
			"Todas as resistências",
		["Crafting skill"] =
			"Skill de criação",
		["Armorsmith skill"] =
			"Skill de armorsmith",
		["Weaponsmith skill"] =
			"Skill de weaponsmith",
		["Jewelsmith skill"] =
			"Skill de jewelsmith",
		["Mining skill"] =
			"Skill de mineração",
		["Woodcutting skill"] =
			"Skill de lenhador",
		["Herbalist skill"] =
			"Skill de herbalista",
		["Physical damage x (1 + value / 230). Value: 0.8 per point up to 60 points (+21%), then 0.2 per point up to 120 points (+26%)."] =
			"Dano físico x (1 + valor / 230). Valor: 0,8 por ponto até 60 pontos (+21%), depois 0,2 por ponto até 120 pontos (+26%).",
		["Damage of every type but physical, and healing, x (1 + value / 230). Value: 0.8 per point up to 60 points (+21%), then 0.2 per point up to 120 points (+26%)."] =
			"Dano de todo tipo menos físico, e cura, x (1 + valor / 230). Valor: 0,8 por ponto até 60 pontos (+21%), depois 0,2 por ponto até 120 pontos (+26%).",
		["Weapon hits (melee, distance, wand) deal 1 / (1 - value%) times the damage, like attacking faster. Value: 0.8 per point up to 20 points (+19%), then 1 per 15 points up to 80 points (+25%)."] =
			"Golpes de arma (corpo a corpo, distância, varinha) causam 1 / (1 - valor%) vezes o dano, como atacar mais rápido. Valor: 0,8 por ponto até 20 pontos (+19%), depois 1 a cada 15 pontos até 80 pontos (+25%).",
		["+0.8 percent maximum health per point up to 50 points (+40%), then +0.2 per point up to 100 points (+50%)."] =
			"+0,8 percent de vida máxima por ponto até 50 pontos (+40%), depois +0,2 por ponto até 100 pontos (+50%).",
		["+0.8 percent maximum mana per point up to 50 points (+40%), then +0.2 per point up to 100 points (+50%)."] =
			"+0,8 percent de mana máxima por ponto até 50 pontos (+40%), depois +0,2 por ponto até 100 pontos (+50%).",
		["No effect yet: the game gives wisdom no use."] =
			"Sem efeito por enquanto: o jogo ainda não dá uso à sabedoria.",
		["Walking speed. The tooltip shows the speed you gain; at most +80."] =
			"Velocidade de caminhada. A dica mostra a velocidade que você ganha; no máximo +80.",
		["Experience from monsters, in the percent shown."] =
			"Experiência de monstros, na porcentagem mostrada.",
		["Item find +0.2 per point (shown as the percent): scales the chance of better item rarities, +300 percent at most with everything else."] =
			"Item find +0,2 por ponto (mostrado como a porcentagem): aumenta a chance de raridades melhores de item, no máximo +300 percent com todo o resto.",
		["Item find +1 per point (shown as the percent): scales the chance of better item rarities, +300 percent at most with everything else."] =
			"Item find +1 por ponto (mostrado como a porcentagem): aumenta a chance de raridades melhores de item, no máximo +300 percent com todo o resto.",
		["+1 sword skill level per point: sword hit damage and accuracy."] =
			"+1 nível de skill de espada por ponto: dano e precisão dos golpes de espada.",
		["+1 axe skill level per point: axe hit damage and accuracy."] =
			"+1 nível de skill de machado por ponto: dano e precisão dos golpes de machado.",
		["+1 club skill level per point: club hit damage and accuracy."] =
			"+1 nível de skill de clava por ponto: dano e precisão dos golpes de clava.",
		["+1 distance skill level per point: bow, crossbow and throwing damage and accuracy."] =
			"+1 nível de skill de distância por ponto: dano e precisão de arco, besta e arremesso.",
		["+1 magic level per point: stronger spells, healing and runes."] =
			"+1 magic level por ponto: magias, curas e runas mais fortes.",
		["+1 shielding skill level per point: you block more of the hits you take with a shield."] =
			"+1 nível de escudo por ponto: você bloqueia mais dos golpes que recebe com um escudo.",
		["Percent chance that a hit is critical, rolled once against the sum of tree, gear and gems."] =
			"Chance em porcentagem de um golpe ser crítico, sorteada uma vez contra a soma da árvore, equipamento e gemas.",
		["A critical hit deals this many percent more damage."] =
			"Um golpe crítico causa essa porcentagem a mais de dano.",
		["Percent chance on each hit that it also heals you."] =
			"Chance em porcentagem de cada golpe também curar você.",
		["A leeching hit heals you for this percent of the damage it dealt."] =
			"Um golpe com roubo de vida cura você nessa porcentagem do dano causado.",
		["Percent chance on each hit that it also refills your mana."] =
			"Chance em porcentagem de cada golpe também recuperar sua mana.",
		["A leeching hit gives you this percent of the damage it dealt as mana."] =
			"Um golpe com roubo de mana dá a você essa porcentagem do dano causado como mana.",
		["+percent damage to every element at once (fire, ice, energy, earth, death, holy, water, arcane; not physical)."] =
			"+porcentagem de dano em todos os elementos de uma vez (fogo, gelo, energia, terra, morte, sagrado, água, arcano; não físico).",
		["+percent physical damage, up to +150 percent together with every other source of the type."] =
			"+porcentagem de dano físico, até +150 percent junto com toda outra fonte do tipo.",
		["+percent fire damage, up to +150 percent together with all elements."] =
			"+porcentagem de dano de fogo, até +150 percent junto com todos os elementos.",
		["+percent ice damage, up to +150 percent together with all elements."] =
			"+porcentagem de dano de gelo, até +150 percent junto com todos os elementos.",
		["+percent energy damage, up to +150 percent together with all elements."] =
			"+porcentagem de dano de energia, até +150 percent junto com todos os elementos.",
		["+percent earth damage, up to +150 percent together with all elements."] =
			"+porcentagem de dano de terra, até +150 percent junto com todos os elementos.",
		["+percent death damage, up to +150 percent together with all elements."] =
			"+porcentagem de dano de morte, até +150 percent junto com todos os elementos.",
		["+percent holy damage, up to +150 percent together with all elements."] =
			"+porcentagem de dano sagrado, até +150 percent junto com todos os elementos.",
		["+percent arcane damage, up to +150 percent together with all elements."] =
			"+porcentagem de dano arcano, até +150 percent junto com todos os elementos.",
		["+percent water damage, up to +150 percent together with all elements."] =
			"+porcentagem de dano de água, até +150 percent junto com todos os elementos.",
		["+percent healing done by your heal spells."] =
			"+porcentagem de cura feita pelas suas magias de cura.",
		["+percent life drain damage."] =
			"+porcentagem de dano de life drain.",
		["+percent mana drain damage."] =
			"+porcentagem de dano de mana drain.",
		["Takes this percent less physical damage, at most 75 percent (gear adds on top)."] =
			"Recebe essa porcentagem a menos de dano físico, no máximo 75 por cento (o equipamento soma por cima).",
		["Takes this percent less fire damage, at most 75 percent (gear adds on top)."] =
			"Recebe essa porcentagem a menos de dano de fogo, no máximo 75 por cento (o equipamento soma por cima).",
		["Takes this percent less ice damage, at most 75 percent (gear adds on top)."] =
			"Recebe essa porcentagem a menos de dano de gelo, no máximo 75 por cento (o equipamento soma por cima).",
		["Takes this percent less energy damage, at most 75 percent (gear adds on top)."] =
			"Recebe essa porcentagem a menos de dano de energia, no máximo 75 por cento (o equipamento soma por cima).",
		["Takes this percent less earth damage, at most 75 percent (gear adds on top)."] =
			"Recebe essa porcentagem a menos de dano de terra, no máximo 75 por cento (o equipamento soma por cima).",
		["Takes this percent less death damage, at most 75 percent (gear adds on top)."] =
			"Recebe essa porcentagem a menos de dano de morte, no máximo 75 por cento (o equipamento soma por cima).",
		["Takes this percent less holy damage, at most 75 percent (gear adds on top)."] =
			"Recebe essa porcentagem a menos de dano sagrado, no máximo 75 por cento (o equipamento soma por cima).",
		["Takes this percent less arcane damage, at most 75 percent (gear adds on top)."] =
			"Recebe essa porcentagem a menos de dano arcano, no máximo 75 por cento (o equipamento soma por cima).",
		["Takes this percent less water damage, at most 75 percent (gear adds on top)."] =
			"Recebe essa porcentagem a menos de dano de água, no máximo 75 por cento (o equipamento soma por cima).",
		["Takes this percent less life drain damage, at most 75%."] =
			"Recebe essa porcentagem a menos de dano de life drain, no máximo 75%.",
		["Takes this percent less mana drain damage, at most 75%."] =
			"Recebe essa porcentagem a menos de dano de mana drain, no máximo 75%.",
		["Adds this percent to the resist of every element (fire, ice, energy, earth, death, holy, water, arcane), at most 75 percent each."] =
			"Soma essa porcentagem à resistência de todos os elementos (fogo, gelo, energia, terra, morte, sagrado, água, arcano), no máximo 75 por cento cada.",
		["Raises your crafting skill; no combat effect."] =
			"Aumenta seu skill de criação; sem efeito em combate.",
		["Raises your armorsmith skill; no combat effect."] =
			"Aumenta seu skill de armorsmith; sem efeito em combate.",
		["Raises your weaponsmith skill; no combat effect."] =
			"Aumenta seu skill de weaponsmith; sem efeito em combate.",
		["Raises your jewelsmith skill; no combat effect."] =
			"Aumenta seu skill de jewelsmith; sem efeito em combate.",
		["Raises your mining skill; no combat effect."] =
			"Aumenta seu skill de mineração; sem efeito em combate.",
		["Raises your woodcutting skill; no combat effect."] =
			"Aumenta seu skill de lenhador; sem efeito em combate.",
		["Raises your herbalist skill; no combat effect."] =
			"Aumenta seu skill de herbalista; sem efeito em combate.",
		-- Auto build (passive_builds_config.lua, passive_builds.lua)
		["Damage"] =
			"Dano",
		["Raw damage: the damage nodes, your weapon or spell skill and the damage multipliers."] =
			"Dano bruto: os nós de dano, o skill da sua arma ou magia e os multiplicadores de dano.",
		["Critical strikes"] =
			"Golpes críticos",
		["Critical hit chance and amount, with the skill and attributes that feed your hits."] =
			"Chance e dano de crítico, com o skill e os atributos que alimentam seus golpes.",
		["Life and mana leech"] =
			"Roubo de vida e mana",
		["Life and mana leech chance and amount, and healing spells, to sustain yourself from your own hits."] =
			"Chance e quantidade de roubo de vida e mana, e magias de cura, para se manter com os próprios golpes.",
		["Mana"] =
			"Mana",
		["A deeper mana pool and leech for it, mana drain damage and absorb, and magic level."] =
			"Uma mana maior e roubo de mana, dano e resistência a mana drain, e magic level.",
		["Defense"] =
			"Defesa",
		["Health, resistances to every damage type and the shielding skill."] =
			"Vida, resistência a todo tipo de dano e o skill de escudo.",
		["Movement speed first; attack speed (dexterity) and evasion nodes on the way."] =
			"Velocidade de movimento primeiro; velocidade de ataque (destreza) e nós de esquiva pelo caminho.",
		["Loot"] =
			"Loot",
		["Item find and item rarity: more drops, better drops."] =
			"Item find e raridade de item: mais drops, drops melhores.",
		["Experience gained from monsters."] =
			"Experiência ganha de monstros.",
		["Physical"] =
			"Físico",
		["Physical damage, physical absorb and the melee or distance skills."] =
			"Dano físico, resistência física e os skills corpo a corpo ou de distância.",
		["Fire"] =
			"Fogo",
		["Fire damage and fire resistance."] =
			"Dano e resistência a fogo.",
		["Ice"] =
			"Gelo",
		["Ice damage and ice resistance."] =
			"Dano e resistência a gelo.",
		["Energy"] =
			"Energia",
		["Energy damage and energy resistance."] =
			"Dano e resistência a energia.",
		["Earth"] =
			"Terra",
		["Earth damage and earth resistance."] =
			"Dano e resistência a terra.",
		["Holy"] =
			"Sagrado",
		["Holy damage and holy resistance."] =
			"Dano e resistência sagrada.",
		["Death"] =
			"Morte",
		["Death damage and death resistance."] =
			"Dano e resistência a morte.",
		["Summons"] =
			"Invocações",
		["The army and companion nodes of the class, with health and mana for the owner."] =
			"Os nós de exército e companheiro da classe, com vida e mana para o dono.",
		["Hybrid"] =
			"Híbrido",
		["A balance of damage, health and resistances."] =
			"Um equilíbrio de dano, vida e resistências.",
		["Damage first: the damage nodes of your class, then crit and skill."] =
			"Dano primeiro: os nós de dano da sua classe, depois crítico e skill.",
		["Survivability first: health, resistances and the shielding skill."] =
			"Sobrevivência primeiro: vida, resistências e o skill de escudo.",
		["Staying power: leech and health on the way to the class keystones."] =
			"Resistência: roubo de vida e vida no caminho dos keystones da classe.",
		["Support: mana and the support keystones of the class."] =
			"Suporte: mana e os keystones de suporte da classe.",
		["Summons: the army or companion nodes, with health for the owner."] =
			"Invocações: os nós de exército ou companheiro, com vida para o dono.",
		["Speed and evasion with enough damage to hunt."] =
			"Velocidade e esquiva com dano suficiente para caçar.",
		["Critical strikes: chance and amount on the class path."] =
			"Golpes críticos: chance e dano no caminho da classe.",
		["One element: its damage nodes and resistance."] =
			"Um elemento: seus nós de dano e de resistência.",
		["All damage"] =
			"Todo dano",
		["Experience %"] =
			"Experiência %",
		["Item find %"] =
			"Item find %",
		["Item rarity %"] =
			"Raridade de item %",
		["Healing spells"] =
			"Magias de cura",
		["Slayer"] =
			"Carniceiro",
		["Bulwark"] =
			"Baluarte",
		["Bloodied"] =
			"Sanguinário",
		["Unbreakable"] =
			"Inquebrável",
		["Retaliator"] =
			"Retaliador",
		["Heavy Hitter"] =
			"Golpe Pesado",
		["Rage Engine"] =
			"Motor da Fúria",
		["Bloodrunner"] =
			"Corredor de Sangue",
		["Crusher"] =
			"Esmagador",
		["Sharpshooter"] =
			"Atirador",
		["Skirmisher"] =
			"Escaramuçador",
		["Steady Aim"] =
			"Mira Firme",
		["Marked Target"] =
			"Alvo Marcado",
		["Hunter's Focus"] =
			"Foco do Caçador",
		["Evasive Hunter"] =
			"Caçador Evasivo",
		["Pack Leader"] =
			"Líder da Matilha",
		["Wild Volley"] =
			"Saraivada Selvagem",
		["Hardy Warden"] =
			"Guardião Robusto",
		["Arcanist"] =
			"Arcanista",
		["Mana Weaver"] =
			"Tecelão de Mana",
		["Warded Mage"] =
			"Mago Protegido",
		["Overloaded"] =
			"Sobrecarregado",
		["Pyromancer"] =
			"Piromante",
		["Channeler"] =
			"Canalizador",
		["Support Weaver"] =
			"Tecelão de Apoio",
		["Lifeline"] =
			"Linha de Vida",
		["Illusory Striker"] =
			"Golpeador Ilusório",
		["Venomblade"] =
			"Lâmina Venenosa",
		["Shadow Dancer"] =
			"Dançarino das Sombras",
		["Cutthroat"] =
			"Degolador",
		["Twin Fangs"] =
			"Presas Gêmeas",
		["Phantom"] =
			"Fantasma",
		["Plaguebearer"] =
			"Portador da Praga",
		["Duelist"] =
			"Duelista",
		["Iaido Striker"] =
			"Golpeador Iaido",
		["Bloodblade"] =
			"Lâmina de Sangue",
		["Grave Caller"] =
			"Invocador de Tumbas",
		["Soul Siphon"] =
			"Sifão de Almas",
		["Death Mage"] =
			"Mago da Morte",
		["Rot Curser"] =
			"Amaldiçoador da Podridão",
		["Soul Hoarder"] =
			"Acumulador de Almas",
		["Lifedrinker"] =
			"Bebedor de Vida",
		["Bone Army"] =
			"Exército de Ossos",
		["Bone Warden"] =
			"Guardião de Ossos",
		["Ossuary Fury"] =
			"Fúria do Ossuário",
		["Iron Body"] =
			"Corpo de Ferro",
		["Fist Flurry"] =
			"Rajada de Punhos",
		["Chi Surge"] =
			"Surto de Chi",
		["Hundred Fists"] =
			"Cem Punhos",
		["Pressure Points"] =
			"Pontos de Pressão",
		["Shadow Step"] =
			"Passo Sombrio",
		["Chi Healer"] =
			"Curandeiro de Chi",
		["Stone Sage"] =
			"Sábio de Pedra",
		["Healing Fist"] =
			"Punho Curador",
		["Zealot"] =
			"Zeloso",
		["Shield Wall"] =
			"Muralha de Escudos",
		["Penitent"] =
			"Penitente",
		["Judge"] =
			"Juiz",
		["Burning Zeal"] =
			"Zelo Ardente",
		["Purifier"] =
			"Purificador",
		["Bastion"] =
			"Bastião",
		["Beacon"] =
			"Farol",
		["Retributor"] =
			"Retribuidor",
		-- Auto build messages (passive_builds.lua)
		["Unknown build."] =
			"Build desconhecida.",
		["That build is not for your class."] =
			"Essa build não é para a sua classe.",
		["Malformed request."] =
			"Pedido inválido.",
		["Nothing would change: you already have this build, or you have no free points."] =
			"Nada mudaria: você já tem essa build, ou não tem pontos livres.",
		["The price changed since the preview. Open the build again."] =
			"O preço mudou desde a prévia. Abra a build de novo.",
		["You need %s gold coins (carried or in the bank) to reset your tree first."] =
			"Você precisa de %s gold coins (na bolsa ou no banco) para resetar sua árvore primeiro.",
		["Auto build: %d nodes now allocated, %d taken back%s."] =
			"Auto build: %d nós alocados agora, %d devolvidos%s.",
		["for %s gold coins"] =
			"por %s gold coins",
		["(free)"] =
			"(grátis)",
		["Auto build: %d nodes added, %d in all."] =
			"Auto build: %d nós adicionados, %d no total.",
		["%d more nodes of the build need more points."] =
			"Mais %d nós da build precisam de mais pontos.",
		["Too fast: wait a moment and apply again."] =
			"Rápido demais: espere um momento e aplique de novo.",
		["Too fast: wait a moment and pick the build again."] =
			"Rápido demais: espere um momento e escolha a build de novo.",
		["The preview could not be made. Try another build or try again later."] =
			"Não foi possível montar a prévia. Tente outra build ou tente mais tarde.",
		-- Service NPCs (service_npcs*.lua, data/npc/scripts/chaos_service_npc.lua and the five NPC XMLs)
		["%s has %d free houses, the cheapest: %s. Say {buy} and a name."] =
			"%s tem %d casas livres, as mais baratas: %s. Diga {buy} e um nome.",
		["%s in %s costs %s gold coins, paid from your backpack and then the bank. Do you want it? Say {yes}."] =
			"%s em %s custa %s gold coins, pagos da sua mochila e depois do banco. Quer? Diga {yes}.",
		["%s is yours. Keep the rent in your bank, or the house returns to me."] =
			"%s é sua. Deixe o aluguel no banco, ou a casa volta para mim.",
		["A class change takes a token from the store, and you have %d. The window shows the free switch of an old character as well."] =
			"Uma troca de classe usa um token da loja, e você tem %d. A janela mostra também a troca grátis de um personagem antigo.",
		["A house needs a premium account."] =
			"Uma casa exige conta premium.",
		["A name change takes a token from the store, and you have %d. Choose the new name in the window."] =
			"Uma troca de nome usa um token da loja, e você tem %d. Escolha o novo nome na janela.",
		["A roof keeps the rain off, |PLAYERNAME|."] =
			"Um teto afasta a chuva, |PLAYERNAME|.",
		["As you wish."] =
			"Como quiser.",
		["Cassian Auric. I keep the gold that you cannot carry. Ask to {open} your account."] =
			"Cassian Auric. Guardo o ouro que você não consegue carregar. Peça para {open} sua conta.",
		["Come again, |PLAYERNAME|."] =
			"Volte sempre, |PLAYERNAME|.",
		["Come back for it any time, |PLAYERNAME|."] =
			"Volte para buscar quando quiser, |PLAYERNAME|.",
		["Every boss gives you %d free pocket charges a day, renewed at midnight. A charge buys a private fight. The ledger shows what you hold."] =
			"Cada chefe dá %d cargas de bolso grátis por dia, renovadas à meia-noite. Uma carga compra uma luta privada. O registro mostra quantas você tem.",
		["Familiars are not on this server."] =
			"Não há familiares neste servidor.",
		["Free houses by town: %s. Ask for the {list} of a town."] =
			"Casas livres por cidade: %s. Peça a {list} de uma cidade.",
		["Good day, |PLAYERNAME|. A roof of your own? Ask for the {list} of free houses, or say {buy} and a name."] =
			"Bom dia, |PLAYERNAME|. Um teto só seu? Peça a {list} das casas livres, ou diga {buy} e um nome.",
		["Good hunting, |PLAYERNAME|."] =
			"Boa caçada, |PLAYERNAME|.",
		["Halvard Deedkeeper. I sell the free houses of the land and take back the ones you leave. Ask for the {list}, or say {buy} and a house name."] =
			"Halvard Deedkeeper. Vendo as casas livres da terra e recebo de volta as que você deixa. Peça a {list}, ou diga {buy} e o nome da casa.",
		["Here is the ledger. A boss that is out of reach can be fought in a pocket of its own: the Pocket button spends a charge."] =
			"Aqui está o registro. Um chefe fora de alcance pode ser enfrentado num bolso só dele: o botão Pocket gasta uma carga.",
		["Houses are not for sale on this server."] =
			"Casas não estão à venda neste servidor.",
		["Hunter, |PLAYERNAME|. I keep the ledger of every boss and the hour it returns. Ask for the {bosses}, or about your daily {charges}."] =
			"Caçador, |PLAYERNAME|. Guardo o registro de cada chefe e da hora em que volta. Peça os {bosses}, ou pergunte das suas {charges} diárias.",
		["I know no house of that name."] =
			"Não conheço casa com esse nome.",
		["More than one house fits that name. Say it fully."] =
			"Mais de uma casa combina com esse nome. Diga o nome completo.",
		["No house is free at the moment."] =
			"Nenhuma casa está livre no momento.",
		["Pell Ashmere. I see to your name, your class, your familiar, your plate frame and your web shop orders. Ask what you need."] =
			"Pell Ashmere. Cuido do seu nome, da sua classe, do seu familiar, da moldura da placa e dos pedidos da loja web. Diga o que precisa.",
		["Say {sell} and the name of the one who buys it. Both of you must be here."] =
			"Diga {sell} e o nome de quem compra. Vocês dois precisam estar aqui.",
		["Tavish Coldhand. I keep the supply stash of every adventurer. Ask me to open your {stash}."] =
			"Tavish Coldhand. Guardo o estoque de suprimentos de todo aventureiro. Peça para abrir seu {stash}.",
		["That cannot be done now."] =
			"Isso não pode ser feito agora.",
		["That house already has an owner."] =
			"Essa casa já tem dono.",
		["The deeds wait."] =
			"As escrituras esperam.",
		["The ink dries."] =
			"A tinta seca.",
		["The ledger stays open."] =
			"O registro continua aberto.",
		["The services are open. Name, class and frame changes are done in that window."] =
			"Os serviços estão abertos. Trocas de nome, classe e moldura são feitas nessa janela.",
		["The shelves wait."] =
			"As prateleiras esperam.",
		["The vault door closes."] =
			"A porta do cofre se fecha.",
		["The web shop is not on this server."] =
			"A loja web não existe neste servidor.",
		["Vessa Hollowmark. I keep the ledger of every boss: where it lives and when it returns. Ask for the {bosses}."] =
			"Vessa Hollowmark. Guardo o registro de cada chefe: onde vive e quando volta. Peça os {bosses}.",
		["Welcome, |PLAYERNAME|. A new name, a new class, a familiar or a plate frame? Ask, or say {services}."] =
			"Bem-vindo, |PLAYERNAME|. Um novo nome, uma nova classe, um familiar ou uma moldura de placa? Pergunte, ou diga {services}.",
		["Welcome, |PLAYERNAME|. What you cannot carry, I keep. Shall I open your {stash}?"] =
			"Bem-vindo, |PLAYERNAME|. O que você não consegue carregar, eu guardo. Abro seu {stash}?",
		["Welcome, |PLAYERNAME|. Your gold is safe with me. Shall I {open} your account?"] =
			"Bem-vindo, |PLAYERNAME|. Seu ouro está seguro comigo. Devo {open} sua conta?",
		["Which house? Say {buy} and its name; ask for the {list} to hear the free ones."] =
			"Qual casa? Diga {buy} e o nome dela; peça a {list} para ouvir as livres.",
		["You already own a house. Leave it first."] =
			"Você já tem uma casa. Deixe-a primeiro.",
		["You need %d gold coins (carried or in the bank) for that house."] =
			"Você precisa de %d gold coins (na bolsa ou no banco) para essa casa.",
		["Your account holds %s gold coins."] =
			"Sua conta guarda %s gold coins.",
		["Your account is open. You can deposit, withdraw or transfer gold. Your balance is %s gold coins."] =
			"Sua conta está aberta. Você pode depositar, sacar ou transferir ouro. Seu saldo é %s gold coins.",
		["Your gold sleeps safe, |PLAYERNAME|."] =
			"Seu ouro dorme seguro, |PLAYERNAME|.",
		["Your plate frames are in the window. Pick one, or switch it off."] =
			"Suas molduras de placa estão na janela. Escolha uma, ou desligue.",
		["Your stash is open. Drag items onto it, or take them out. Taking out works in town only, mind you."] =
			"Seu estoque está aberto. Arraste itens para ele, ou retire-os. Retirar só funciona na cidade, atenção.",
		-- the Haunted Harvest (harvest_event.lua, harvest_event_config.lua messages, Widow Hessa, the Harvest Portal)
		["Harvest Portal"] = "Portal da Colheita",
		["Open while the Haunted Harvest lasts: step in to reach the cursed village (levels 450-650). Its exit portal leads to your temple."] =
			"Aberto enquanto durar a Haunted Harvest: entre para chegar à vila amaldiçoada (níveis 450-650). O portal de saída leva ao seu templo.",
		["Haunted Harvest"] = "Haunted Harvest",
		["A cursed harvest village opens its gates: Harvest Portals next to the temples."] =
			"Uma vila de colheita amaldiçoada abre seus portões: Portais da Colheita ao lado dos templos.",
		["The Haunted Harvest has begun! Harvest Portals stand next to the temples."] =
			"A Haunted Harvest começou! Os Portais da Colheita estão ao lado dos templos.",
		["The Haunted Harvest is over. The village sleeps until next year."] =
			"A Haunted Harvest acabou. A vila dorme até o ano que vem.",
		["The Haunted Harvest is not open now."] = "A Haunted Harvest não está aberta agora.",
		["The pumpkin is not ripe yet."] = "A abóbora ainda não está madura.",
		["You harvest the pumpkin: %d hollow candy."] = "Você colhe a abóbora: %d hollow candy.",
		["You harvested enough pumpkins today; the field gives you nothing more."] =
			"Você já colheu abóboras demais hoje; o campo não lhe dá mais nada.",
		["The pumpkin wakes up!"] = "A abóbora acorda!",
		["You dig into the fresh grave..."] = "Você cava a cova recente...",
		["The coffin is empty but for some candy (%d)."] = "O caixão está vazio, exceto por alguns doces (%d).",
		["Among the bones lies a sexton's key."] = "Entre os ossos está uma sexton's key.",
		["The dead climb out!"] = "Os mortos saem da terra!",
		["Treat! The cauldron gives you %d hollow candy."] = "Gostosura! O caldeirão lhe dá %d hollow candy.",
		["Trick!"] = "Travessura!",
		["The cauldron is empty. It fills again soon."] = "O caldeirão está vazio. Logo ele se enche de novo.",
		["The cursed bell tolls... wings beat in the dark."] = "O sino amaldiçoado dobra... asas batem no escuro.",
		["The bell is still ringing in the dark."] = "O sino ainda ressoa no escuro.",
		["The crypt seal is shut. A sexton's key would break it."] =
			"O selo da cripta está fechado. Uma sexton's key o quebraria.",
		["The seal cracks open. The crypt stair lies below."] = "O selo se parte. A escada da cripta está abaixo.",
		["You set a ritual candle on the circle (%d of %d)."] = "Você põe uma ritual candle no círculo (%d de %d).",
		["The circle flares: the ritual portal is open!"] = "O círculo se acende: o portal do ritual está aberto!",
		["The circle is already burning."] = "O círculo já está queimando.",
		["The ritual portal is not open."] = "O portal do ritual não está aberto.",
		["The hollow charm crumbles: %s is yours (for the account)."] =
			"O hollow charm se desfaz: %s é seu (para a conta).",
		["Your account owns every haunted cosmetic: the charm turns into %d hollow candy."] =
			"Sua conta já tem todos os cosméticos assombrados: o charm vira %d hollow candy.",
		["%s calls his court from the graves!"] = "%s chama sua corte das covas!",
		["%s has fallen! The harvest is safe... for now."] = "%s caiu! A colheita está a salvo... por enquanto.",
		["First Hollow King of the day: %d hollow candy."] = "Primeiro Hollow King do dia: %d hollow candy.",
		["Shh, |PLAYERNAME|. The dead are listening. Bring me hollow candy and I will {trade}; ask me about the {harvest} if you dare."] =
			"Psiu, |PLAYERNAME|. Os mortos estão ouvindo. Traga hollow candy e eu faço {trade}; pergunte sobre a {harvest} se tiver coragem.",
		["Keep a lantern lit, |PLAYERNAME|."] = "Mantenha uma lanterna acesa, |PLAYERNAME|.",
		["The corn whispers your name..."] = "O milharal sussurra seu nome...",
		["Hollow candy buys: %s. Say {buy} and the number."] = "Hollow candy compra: %s. Diga {buy} e o número.",
		["That costs %d hollow candy; you carry %d."] = "Isso custa %d hollow candy; você carrega %d.",
		["I have no such thing. Ask me to {trade}."] = "Não tenho isso. Peça para eu fazer {trade}.",
		["A fair trade: %s for %d hollow candy."] = "Uma troca justa: %s por %d hollow candy.",
		["The harvest moon woke the dead of this village. Pick the pumpkins, dig the graves, and find the sexton's key: the crypt under the chapel leads to the Hollow King."] =
			"A lua da colheita acordou os mortos desta vila. Colha as abóboras, cave as covas e encontre a sexton's key: a cripta sob a capela leva ao Hollow King.",
		["Hessa. I buried my husband in that graveyard. Twice. Bring me hollow candy and I will {trade}."] =
			"Hessa. Enterrei meu marido naquele cemitério. Duas vezes. Traga hollow candy e eu faço {trade}.",
	},
}
