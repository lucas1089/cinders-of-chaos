-- Server texts in other languages than English (i18n_core.lua, server/README.md "Server texts in pt-BR (Chaos.t)").
-- A key is the English text, a string.format pattern; its translation keeps the % conversions in the same order.
-- {spell} in a boss warning is the spell's name. UTF-8: the client turns it into cp1252 (client base patch 0028).
-- Game terms follow the wiki's pt-BR guides: proper names of classes, spells, items, bosses, orbs and the menus stay
-- in English. tests/i18n_test.lua checks that every key used by the converted sites has a pt-BR entry.

return {
	["pt-BR"] = {
		-- Auto Seller (autosell.lua, autosell_core.lua)
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
	},
}
