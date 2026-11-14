-- The cards of the hubs (O550): entry text -> glyph slot (client/tools/topbar_glyphs.py draws it) and the one line under
-- the name (at most 34 characters; tr() key, pt-BR in client_chaos_locale/pt_br.lua). One card per line: the checker
-- reads this file as text. A glyph is never used twice on one tab.
ChaosTopBarCards = {}
local C = ChaosTopBarCards

C.CARDS = {
  -- Hero > Character
  ['Inventory'] = { 'pack', 'Backpack and equipment' },
  ['Skills'] = { 'bolt', 'Levels and combat stats' },
  ['Spellbook'] = { 'tome', 'Learn and cast your spells' },
  ['Passive Tree'] = { 'tree', 'Spend passive points' },
  ['Character Info'] = { 'info', 'Resists, kills, deaths, sets' },
  ['Achievements'] = { 'trophy', 'Goals done and points' },
  -- Hero > Build
  ['Spell Supports'] = { 'star', 'Support effects for spells' },
  ['Loadouts'] = { 'dividers', 'Save tree and gear as a build' },
  ['Charms'] = { 'gem', 'Place charms for small bonuses' },
  ['Chaos Pact'] = { 'swirl', 'Pact marks and saved builds' },
  ['Deck of Cards'] = { 'cards', 'Every card you loot, in one place' },
  -- Hero > Style
  ['Outfit'] = { 'shirt', 'Change your look' },
  ['Transmog'] = { 'dividers', 'Gear with another look' },
  ['Cosmetics'] = { 'laurel', 'Auras, trails and frames' },
  ['Pets'] = { 'claws', 'A companion that follows you' },
  -- Hero > Home
  ['Hideout'] = { 'house', 'Your own room' },
  ['Town Portal'] = { 'swirl', 'Cast a portal to town' },
  ['Portal Style'] = { 'sliders', 'Choose how the portal looks' },
  ['House'] = { 'columns', 'Buy, leave or sell a house' },
  -- Hunt > Hunting
  ['Hunt Tracker'] = { 'stopwatch', 'Exp, loot and profit per hour' },
  ['Battle List'] = { 'list', 'Creatures near you' },
  ['Minimap'] = { 'compass', 'The map of this area' },
  ['Bestiary'] = { 'horns', 'Monsters you have met' },
  ['Helper'] = { 'cross', 'Auto heal and attack helper' },
  ['Party Finder'] = { 'magnifier', 'Find or list a hunting group' },
  -- Hunt > Loot
  ['Auto Loot'] = { 'lootarrow', 'Pick up loot by itself' },
  ['Loot Filter'] = { 'funnel', 'Glow, dim or hide drops' },
  ['Loot Splitter'] = { 'split', 'Split loot with the party' },
  ['Auto Seller'] = { 'sellcoin', 'Sell the loot bag on a timer' },
  -- Hunt > Records
  ['DPS Meter'] = { 'bars', 'Damage per second, live' },
  ['Death Recap'] = { 'scroll', 'What killed you' },
  ['Nemesis'] = { 'swords', 'The monster that killed you' },
  -- Hunt > Map
  ['Map Overlay'] = { 'map', 'Monsters drawn on the map' },
  ['Map Overlay Settings'] = { 'sliders', 'What the overlay shows' },
  ['Map Markers'] = { 'compass', 'Points of interest and party marks' },
  -- Hunt > Group
  ['Party'] = { 'heads', 'Your party members' },
  ['Party Frames'] = { 'trio', 'Health bars of the party' },
  ['Group Queue'] = { 'list', 'Queue as a group' },
  -- Adventure > Journey
  ['Dungeons'] = { 'columns', 'Boss dungeons with chests' },
  ['Bounty Board'] = { 'scroll', 'Daily contracts for your level' },
  ['Quest Log'] = { 'book', 'Your quests' },
  ['Daily Reward'] = { 'chest', 'Claim today\'s reward' },
  ['Next Goals'] = { 'compass', 'What to do next' },
  ['Main Quest'] = { 'star', 'The story, step by step' },
  -- Adventure > Rifts
  ['Rifts'] = { 'rift', 'Tiered rifts and their keys' },
  ['Rift Atlas'] = { 'map', 'Points that make rifts richer' },
  ['Waystone Atlas'] = { 'gem', 'Points for waystone maps' },
  -- Adventure > Trials
  ['Infinity Tower'] = { 'tower', 'Climb floor after floor' },
  ['Ember Descent'] = { 'bolt', 'Room after room, ever harder' },
  ['Raid: Ashen Sepulchre'] = { 'horns', 'Weekly boss raid for a group' },
  ['Boss Spawns'] = { 'stopwatch', 'Where and when bosses appear' },
  -- Adventure > Season
  ['Season'] = { 'laurel', 'This season and its modifier' },
  ['Season Pass'] = { 'cards', 'Tiers and rewards' },
  ['Weekly Chest'] = { 'chest', 'Your chest of the week' },
  ['Ember Cache'] = { 'orbs', 'Weekly orbs for points' },
  ['Events'] = { 'star', 'Invasions and the calendar' },
  -- Adventure > Tasks
  ['Kill Tasks'] = { 'claws', 'Kill counts for rewards' },
  ['Task Tracker'] = { 'list', 'Task progress on screen' },
  ['Quest Tracker'] = { 'scroll', 'Quest progress on screen' },
  ['Goal Tracker'] = { 'trophy', 'Goal progress on screen' },
  -- Adventure > War
  ['Arena'] = { 'columns', 'Ranked player duels' },
  ['Battleground'] = { 'swords', 'Team against team' },
  ['Scorched Marches'] = { 'rift', 'Open zone, players hunt players' },
  ['Guild Siege'] = { 'tower', 'Guilds fight for an arena' },
  ['Guild Wars'] = { 'horns', 'Declare war on a guild' },
  -- Trade > Shop
  ['Store'] = { 'pouch', 'Chaos Coins and boosts' },
  ['Market'] = { 'scales', 'Sell and buy with players' },
  ['Bank'] = { 'columns', 'Keep and move your gold' },
  ['Supply Stash'] = { 'chest', 'One storage for any item' },
  ['Crafting Bench'] = { 'anvil', 'Improve gear with orbs' },
  -- Trade > Craft
  ['Salvage'] = { 'salvage', 'Break gear into shards' },
  ['Professions'] = { 'pick', 'Gather and sell materials' },
  ['Orb Exchange'] = { 'orbs', 'Trade orbs with players' },
  -- Trade > Finder
  ['Item Finder'] = { 'magnifier', 'Where an item drops or sells' },
  ['Ancestral Store'] = { 'stall', 'Spend ancestral points' },
  ['Character Bazaar'] = { 'heads', 'Characters for sale' },
  -- Social > People
  ['Guild'] = { 'tower', 'Your guild, bank and hall' },
  ['VIP List'] = { 'list', 'Friends and who is online' },
  ['Inspect Player'] = { 'magnifier', 'Look at another player' },
  ['Mentors'] = { 'tome', 'Learn from or guide a player' },
  -- Social > Community
  ['Community'] = { 'trio', 'The server brazier and goals' },
  ['Referral'] = { 'split', 'Invite friends for rewards' },
  ['Leaderboards'] = { 'trophy', 'Rankings of the server' },
  ['Notifications'] = { 'bolt', 'Messages you got' },
  -- System > Basics
  ['Options'] = { 'sliders', 'Game settings' },
  ['Hotkeys'] = { 'cards', 'Keys for your actions' },
  ['Codex'] = { 'book', 'The item encyclopedia' },
  ['Help Search'] = { 'magnifier', 'Search every help text' },
  ['Logout'] = { 'door', 'Back to the character list' },
  ['Exit'] = { 'power', 'Close the client' },
  -- System > Settings
  ['Sound'] = { 'note', 'Music and effects' },
  ['Drop Feed'] = { 'scroll', 'Loot messages on screen' },
  ['Buff Bar'] = { 'bars', 'Show or hide the buff bar' },
  ['New Window Look'] = { 'dividers', 'Switch the window style' },
  -- System > Library
  ['Chronicle'] = { 'book', 'The story and the fallen' },
  ['Patch Notes'] = { 'scroll', 'What changed each week' },
  ['Server Info'] = { 'info', 'Rates, rules and links' },
  -- System > Support
  ['Services'] = { 'shirt', 'Name, vocation, frames' },
  ['Report a Bug'] = { 'cross', 'Tell us what broke' },
  ['Report a Player'] = { 'cards', 'Report a rule breaker' },
  ['Join Discord'] = { 'trio', 'Open the community chat' },
  ['Credits'] = { 'laurel', 'Who made what' },
  -- System > Developer
  ['Console'] = { 'terminal', 'The client console' },
  ['DAT Offset Studio'] = { 'dividers', 'Sprite offset editor' },
  ['Performance'] = { 'stopwatch', 'Frame time and memory' },
  -- System > Staff
  ['Admin Panel'] = { 'hammer', 'Staff tools' },
}

-- an entry the tree does not know yet (a new module) gets the glyph of its old icon name (topbutton_<icon>), no line
C.ICON_GLYPH = {
  skills = 'bolt', spells = 'tome', passivetree = 'tree', inventory = 'pack', battlelist = 'list', vip = 'heads',
  minimap = 'compass', ranking = 'trophy', quests = 'scroll', autoloot = 'lootarrow', market = 'scales', bank = 'columns',
  stash = 'chest', proficiency = 'anvil', daily = 'chest', battlepass = 'cards', dungeons = 'columns', events = 'star',
  infinitytower = 'tower', options = 'sliders', notifications = 'bolt', help = 'info', logout = 'door', exit = 'power',
  admin = 'hammer', console = 'terminal', community = 'trio', pvp = 'swords', autoseller = 'sellcoin',
}
C.FALLBACK_GLYPH = 'star'

return C
