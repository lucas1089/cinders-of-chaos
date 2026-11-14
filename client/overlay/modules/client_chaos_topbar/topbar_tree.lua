-- The top menu as hubs (O550): hub (a badge on the bar) -> tab -> card. One card per window, named by the entry text the
-- modules give ChaosTopBar.addEntry (that text is also the unlock key). Pure data: topbarhublogic.lua reads it,
-- topbar_cards.lua holds the glyph and the line of every card, tools/ci/check_topbar_tree.py checks it against the
-- entries the modules register (a new entry nobody placed fails the build). Names of hubs and tabs go through tr() with
-- the keys hub.<id> and tab.<hub>.<id> (pt-BR in client_chaos_locale/pt_br.lua); English falls back to `name`.
-- One tab per line and one card list per tab: the checker reads this file as text.
ChaosTopBarTree = {}
local T = ChaosTopBarTree

T.HUBS = {
  { id = 'hero', name = 'Hero', glyph = 'helm', tabs = {
    { id = 'character', name = 'Character', cards = { 'Inventory', 'Skills', 'Spellbook', 'Passive Tree', 'Character Info', 'Achievements' } },
    { id = 'build', name = 'Build', cards = { 'Spell Supports', 'Loadouts', 'Charms', 'Chaos Pact' } },
    { id = 'style', name = 'Style', cards = { 'Outfit', 'Transmog', 'Cosmetics', 'Pets' } },
    { id = 'home', name = 'Home', cards = { 'Hideout', 'Town Portal', 'Portal Style', 'House' } },
  } },
  { id = 'hunt', name = 'Hunt', glyph = 'claws', tabs = {
    { id = 'hunting', name = 'Hunting', cards = { 'Hunt Tracker', 'Battle List', 'Minimap', 'Bestiary', 'Helper', 'Party Finder' } },
    { id = 'loot', name = 'Loot', cards = { 'Auto Loot', 'Loot Filter', 'Loot Splitter', 'Auto Seller' } },
    { id = 'records', name = 'Records', cards = { 'DPS Meter', 'Death Recap', 'Nemesis' } },
    { id = 'map', name = 'Map', cards = { 'Map Overlay', 'Map Overlay Settings', 'Map Markers' } },
    { id = 'group', name = 'Group', cards = { 'Party', 'Party Frames', 'Group Queue' } },
  } },
  { id = 'adventure', name = 'Adventure', glyph = 'peaks', tabs = {
    { id = 'journey', name = 'Journey', cards = { 'Dungeons', 'Bounty Board', 'Quest Log', 'Daily Reward', 'Next Goals', 'Main Quest' } },
    { id = 'rifts', name = 'Rifts', cards = { 'Rifts', 'Rift Atlas', 'Waystone Atlas' } },
    { id = 'trials', name = 'Trials', cards = { 'Infinity Tower', 'Ember Descent', 'Raid: Ashen Sepulchre', 'Boss Spawns' } },
    { id = 'season', name = 'Season', cards = { 'Season', 'Season Pass', 'Weekly Chest', 'Ember Cache', 'Events' } },
    { id = 'tasks', name = 'Tasks', cards = { 'Kill Tasks', 'Task Tracker', 'Quest Tracker', 'Goal Tracker' } },
    { id = 'war', name = 'War', cards = { 'Arena', 'Battleground', 'Scorched Marches', 'Guild Siege', 'Guild Wars' } },
  } },
  { id = 'trade', name = 'Trade', glyph = 'coins', tabs = {
    { id = 'shop', name = 'Shop', cards = { 'Market', 'Bank', 'Supply Stash', 'Crafting Bench' } },
    { id = 'craft', name = 'Craft', cards = { 'Salvage', 'Professions', 'Orb Exchange' } },
    { id = 'finder', name = 'Finder', cards = { 'Item Finder', 'Ancestral Store', 'Character Bazaar' } },
  } },
  { id = 'social', name = 'Social', glyph = 'heads', tabs = {
    { id = 'people', name = 'People', cards = { 'Guild', 'VIP List', 'Inspect Player', 'Mentors' } },
    { id = 'community', name = 'Community', cards = { 'Community', 'Referral', 'Leaderboards', 'Notifications' } },
  } },
  { id = 'system', name = 'System', glyph = 'gear', tabs = {
    { id = 'basics', name = 'Basics', cards = { 'Options', 'Hotkeys', 'Codex', 'Help Search', 'Logout', 'Exit' } },
    { id = 'settings', name = 'Settings', cards = { 'Sound', 'Drop Feed', 'Buff Bar', 'New Window Look' } },
    { id = 'library', name = 'Library', cards = { 'Chronicle', 'Patch Notes', 'Server Info' } },
    { id = 'support', name = 'Support', cards = { 'Services', 'Report a Bug', 'Report a Player', 'Join Discord', 'Credits' } },
    { id = 'developer', name = 'Developer', cards = { 'Console', 'DAT Offset Studio', 'Performance' } },
    { id = 'staff', name = 'Staff', cards = { 'Admin Panel' } },
  } },
}

-- the old category ids (CATEGORIES in chaos_topbar.lua, the first argument of addEntry) -> the hub that holds them
T.CATEGORY_HUB = { character = 'hero', hunt = 'hunt', adventure = 'adventure', chaos = 'adventure', economy = 'trade',
  social = 'social', system = 'system', admin = 'system' }

-- entries the hubs leave out on purpose (owner decision of the hub design): still run by ChaosTopBar.run(text)
T.DROPPED = { ['Unjustified Points'] = true, ['Crafting Tables'] = true }

-- entries that sit in the slot of another one, shown only where the other window is missing (CATEGORIES `unless`)
T.SHARED = { ['Spell List'] = 'Spellbook', ['Hunt Analyser'] = 'Hunt Tracker' }

-- entries on no tab that still work as a pin on the bar (the Store has its own button there, owner 2026-11-14)
T.PIN_ONLY = { ['Store'] = true }

-- entries only the text menu shows (the way back from the text menu to the hubs)
T.TEXT_ONLY = { ['Menu Style'] = true }

return T
