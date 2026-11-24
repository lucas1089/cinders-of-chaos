-- Search keywords of the hub cards (O718): the words a player may type that are not in the card's name, English and pt-BR
-- together, lower case, accents optional (topbarfindlogic.lua folds them). One card per line, the key is the entry text of
-- topbar_cards.lua; topbarfindlogic_test.lua fails when a card of the tree has no line here.
ChaosTopBarKeywords = {}
local K = ChaosTopBarKeywords

K.WORDS = {
  -- Hero > Character
  ['Inventory'] = 'backpack bag equipment gear items mochila equipamento itens',
  ['Skills'] = 'stats level fist sword axe club distance shielding magic habilidades nivel',
  ['Spellbook'] = 'spells magic cast learn livro magias feiticos',
  ['Passive Tree'] = 'talents points nodes class arvore passiva talentos pontos',
  ['Character Info'] = 'resist resistance kills deaths sets stats resistencias mortes',
  ['Achievements'] = 'goals trophies points conquistas',
  -- Hero > Build
  ['Spell Supports'] = 'support gems link apoios suportes',
  ['Loadouts'] = 'build save preset switch conjuntos',
  ['Charms'] = 'charm bonus place amuletos',
  ['Chaos Pact'] = 'pact marks builds pacto',
  ['Deck of Cards'] = 'cards loot collection baralho cartas colecao',
  -- Hero > Style
  ['Outfit'] = 'look appearance mount wings roupa visual montaria asas',
  ['Transmog'] = 'transmogrify appearance gear look transmutar visual',
  ['Cosmetics'] = 'aura trail frame effects cosmeticos',
  ['Pets'] = 'companion pet follow mascote animal',
  -- Hero > Home
  ['Hideout'] = 'room home base esconderijo',
  ['Town Portal'] = 'teleport town return portal cidade voltar',
  ['Portal Style'] = 'portal look color estilo',
  ['House'] = 'buy sell rent home casa comprar vender',
  -- Hunt > Hunting
  ['Hunt Tracker'] = 'exp experience profit loot per hour analyser analyzer xp ganho hora',
  ['Battle List'] = 'monsters creatures enemies targets lista batalha monstros',
  ['Minimap'] = 'map radar navigation mapa',
  ['Bestiary'] = 'monsters creatures kills charms bestiario',
  ['Helper'] = 'auto heal attack healing bot ajudante cura',
  ['Party Finder'] = 'group lfg find party applications grupo procurar',
  -- Hunt > Loot
  ['Auto Loot'] = 'pickup corpse loot coleta automatica saque',
  ['Loot Filter'] = 'glow hide dim drops rarity filtro',
  ['Loot Splitter'] = 'split share party divide dividir',
  ['Auto Seller'] = 'sell vendor timer trash vender automatico',
  -- Hunt > Records
  ['DPS Meter'] = 'damage dps meter dano',
  ['Death Recap'] = 'died killed death cause morte resumo',
  ['Nemesis'] = 'rival killer revenge inimigo',
  ['Collection Log'] = 'collection log uniques sets cards pity colecao registro unicos sorte',
  -- Hunt > Map
  ['Map Overlay'] = 'monsters map draw sobreposicao mapa',
  ['Map Overlay Settings'] = 'overlay options configuracao',
  ['Map Markers'] = 'points interest party marks flags marcadores',
  -- Hunt > Group
  ['Party'] = 'group members invite grupo membros',
  ['Party Frames'] = 'health bars group quadros',
  ['Group Queue'] = 'queue matchmaking group fila',
  -- Adventure > Journey
  ['Dungeons'] = 'boss chests instance masmorras',
  ['Bounty Board'] = 'contracts daily bounty contratos recompensas',
  ['Quest Log'] = 'quests missions diario missoes',
  ['Daily Reward'] = 'claim today streak login recompensa diaria',
  ['Next Goals'] = 'guide next what to do tips objetivos',
  ['Main Quest'] = 'story vael quest historia missao principal',
  -- Adventure > Rifts
  ['Rifts'] = 'keys tier rift fendas chaves',
  ['Rift Atlas'] = 'points atlas rift atlas fendas',
  ['Waystone Atlas'] = 'waystone maps points atlas',
  -- Adventure > Trials
  ['Infinity Tower'] = 'floors climb tower torre infinita andares',
  ['Ember Descent'] = 'rooms depth descent descida',
  ['Raid: Ashen Sepulchre'] = 'raid weekly boss group incursao',
  ['Boss Spawns'] = 'boss timer respawn where when chefes',
  -- Adventure > Season
  ['Season'] = 'ladder modifier temporada',
  ['Season Pass'] = 'tiers rewards pass passe',
  ['Weekly Chest'] = 'chest week reward bau semanal',
  ['Ember Cache'] = 'weekly orbs points cache',
  ['Events'] = 'invasion calendar eventos invasao',
  -- Adventure > Tasks
  ['Kill Tasks'] = 'kill count slayer tarefas matar',
  ['Task Tracker'] = 'tasks tracker rastreador tarefas',
  ['Quest Tracker'] = 'quest tracker rastreador missoes',
  ['Goal Tracker'] = 'goal achievement tracker rastreador metas',
  -- Adventure > War
  ['Arena'] = 'pvp duel ranked duelo',
  ['Battleground'] = 'pvp team match campo de batalha',
  ['Scorched Marches'] = 'pvp open world zone marchas',
  ['Guild Siege'] = 'guild arena pvp cerco',
  ['Guild Wars'] = 'guild war declare guerra',
  -- Trade > Shop
  ['Store'] = 'coins premium boost buy shop loja moedas comprar',
  ['Market'] = 'sell buy players trade auction mercado comprar vender leilao',
  ['Bank'] = 'gold deposit withdraw banco ouro deposito',
  ['Supply Stash'] = 'storage depot stash items deposito armazem',
  ['Crafting Bench'] = 'craft orbs upgrade improve forja bancada',
  -- Trade > Craft
  ['Salvage'] = 'shards break gear desmontar fragmentos',
  ['Professions'] = 'gather mining herbs materials profissoes',
  ['Orb Exchange'] = 'orbs trade exchange troca',
  -- Trade > Finder
  ['Item Finder'] = 'drop where sells locate find item procurar item',
  ['Ancestral Store'] = 'ancestral points shop loja ancestral',
  ['Character Bazaar'] = 'characters sale buy bazar personagens',
  -- Social > People
  ['Guild'] = 'clan bank hall members guilda',
  ['VIP List'] = 'friends online buddy amigos',
  ['Inspect Player'] = 'look view player equipment inspecionar',
  ['Mentors'] = 'mentor teach learn guide mentores',
  -- Social > Community
  ['Community'] = 'brazier goals server comunidade',
  ['Referral'] = 'invite friends rewards indicacao convidar',
  ['Leaderboards'] = 'ranking top highscores classificacao',
  ['Notifications'] = 'messages alerts inbox notificacoes mensagens',
  -- System > Basics
  ['Options'] = 'settings graphics audio controls configuracoes opcoes',
  ['Hotkeys'] = 'keys keybind shortcuts teclas atalhos',
  ['Codex'] = 'encyclopedia items wiki codice enciclopedia',
  ['Help Search'] = 'help guide how to ajuda guia',
  ['Logout'] = 'exit character list switch sair personagem',
  ['Exit'] = 'quit close client sair fechar',
  -- System > Settings
  ['Sound'] = 'music volume effects audio som musica volume',
  ['Drop Feed'] = 'loot messages screen feed mensagens saque',
  ['Buff Bar'] = 'buffs conditions icons status bar barra efeitos',
  ['New Window Look'] = 'style skin theme window aparencia tema janela',
  -- System > Library
  ['Chronicle'] = 'story fallen history lore cronica historia',
  ['Patch Notes'] = 'changes update news changelog novidades atualizacao',
  ['Server Info'] = 'rates rules links info regras servidor',
  -- System > Support
  ['Services'] = 'name change vocation frames servicos nome',
  ['Report a Bug'] = 'bug problem error feedback relatar erro problema',
  ['Report a Player'] = 'report cheat abuse denunciar jogador',
  ['Join Discord'] = 'chat community link discord comunidade',
  ['Credits'] = 'authors art music thanks creditos autores',
  -- System > Developer
  ['Console'] = 'terminal log commands console log',
  ['DAT Offset Studio'] = 'sprite offset editor dat editor',
  ['Performance'] = 'fps frame time memory lag desempenho',
  -- System > Staff
  ['Admin Panel'] = 'staff gm admin tools administracao',
}

return K
