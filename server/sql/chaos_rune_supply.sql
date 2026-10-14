-- Rune supply (server/README.md "Rune supply"): the conjure spells are gone (tools/install_rune_supply.py comments
-- them out of spells.xml): the 36 rune conjures, the blank rune, Conjure Rations, Hallow Spear and Charge Staff. The stock
-- entries had needlearn="0", so normally no player learned one; a row left from an older setup would only keep a name
-- the server no longer knows (the engine keeps learned names as plain text and logs nothing), so this removes such rows.
-- The names are the stock and the Chaos names of spell_names.csv rows marked "conjure" (tests/rune_supply_test.lua
-- checks the list). The rune items share the rune names, but using a rune never needs a learned spell. Safe to run
-- more than once.

DELETE FROM `player_spells` WHERE `name` IN (
  'Food', 'Conjure Rations', 'Enchant Spear', 'Hallow Spear',
  'Enchant Staff', 'Charge Staff', 'Avalanche Rune', 'Frostfall Rune',
  'Energy Bomb Rune', 'Storm Seed Rune', 'Energy Field Rune', 'Sparkmire Rune',
  'Energy Wall Rune', 'Stormwall Rune', 'Explosion Rune', 'Concussion Rune',
  'Fire Bomb Rune', 'Ember Seed Rune', 'Fire Field Rune', 'Cinderpatch Rune',
  'Fire Wall Rune', 'Pyrewall Rune', 'Fireball Rune', 'Cinder Orb Rune',
  'Great Fireball Rune', 'Searing Orb Rune', 'Heavy Magic Missile Rune', 'Greater Hexdart Rune',
  'Holy Missile Rune', 'Dawnshard Rune', 'Icicle Rune', 'Rimespike Rune',
  'Light Magic Missile Rune', 'Hexdart Rune', 'Light Stone Shower Rune', 'Pebblestorm Rune',
  'Lightest Missile Rune', 'Faint Dart Rune', 'Magic Wall Rune', 'Bastion Rune',
  'Poison Bomb Rune', 'Blight Seed Rune', 'Poison Field Rune', 'Blightpatch Rune',
  'Poison Wall Rune', 'Blightwall Rune', 'Soulfire Rune', 'Soulpyre Rune',
  'Stalagmite Rune', 'Stonefang Rune', 'Stone Shower Rune', 'Rockfall Rune',
  'Sudden Death Rune', 'Reaper''s Rune', 'Thunderstorm Rune', 'Stormcall Rune',
  'Paralyze Rune', 'Shackle Rune', 'Wild Growth Rune', 'Thicket Rune',
  'Cure Poison Rune', 'Purge Rune', 'Intense Healing Rune', 'Mending Rune',
  'Ultimate Healing Rune', 'Grand Mending Rune', 'Animate Dead Rune', 'Gravecall Rune',
  'Convince Creature Rune', 'Beastbond Rune', 'Chameleon Rune', 'Mimic Rune',
  'Disintegrate Rune', 'Unmaking Rune', 'Destroy Field Rune', 'Dispel Rune',
  'Blank Rune', 'Unscribed Rune', 'Practice Magic Missile Rune', 'Novice''s Hexdart Rune'
);
