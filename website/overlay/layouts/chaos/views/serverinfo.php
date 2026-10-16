<?php
/**
 * Server info: the game, written for players (from the repository's README.md). Static text; edit it here.
 */
$h = static function ($v): string { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); };
$sections = array(
	'start' => array('Your first steps', array(
		'<strong>Tutorial island.</strong> New characters start on a small island with five stations: fight, cast your first spell, spend a passive point, use an Orb of Upheaval, and learn about keystones, bounties and the store. Each station opens the next gate. You can skip it any time (Character > Services > Leave Tutorial), and nobody can die there.',
		'<strong>Starter kit per class:</strong> weapon, armour, potions, food, tools, a temple teleport scroll and some gold, chosen for your class: arrows for Rangers, a second dagger for Ninjas, and so on.',
		'<strong>Milestone gifts</strong> at levels 20, 50, 100 and 200: potions for your role and Orbs of Upheaval.',
	)),
	'tree' => array('Passive tree and Paragon', array(
		'<strong>Passive tree:</strong> over 600 nodes, with points from levels and not enough to take everything, so every build is a choice. Class keystones change how you play: <em>Cleaving Arc</em> (two-handed hits strike everything around you), <em>Ricochet</em> (arrows bounce to another target), <em>Arcane Echo</em> (spells can cast a second time) and the Illusionist party auras.',
		'<strong>Build codes:</strong> export your tree as a short code (the passive tree\'s Build Code panel) and import someone else\'s. The tree previews it first.',
		'<strong>Respec:</strong> right-click a node to refund just that node, or reset the whole tree; both are priced by your level. Resets are free below level 50 and once after a class change.',
		'<strong>Paragon:</strong> after level 1000 every level gives a Paragon point for small, capped bonuses in four categories.',
	)),
	'items' => array('Items and loot', array(
		'<strong>15 rarities:</strong> Common, Uncommon, Rare, Epic, Legendary, Exotic, Mythic, Chaos, Eternal, Divine, Phantasmal, Celestial, Cosmic, Abyssal and Transcendent.',
		'<strong>Item levels and modifiers:</strong> elemental damage, absorbs, skills, critical hits, life and mana leech. About 50 uniques with fixed, build-defining stats; some only drop from bosses.',
		'<strong>Monster tiers:</strong> every spawn can roll Magic, Rare or Legendary, with modifiers such as <em>Blazing, Chilling, Venomous, Vampiric</em> or <em>Berserker</em>. Killing one can trigger an ambush.',
		'<strong>Treasure goblins:</strong> a very rare, cowardly goblin that flees, blinks away and escapes 18 seconds after the first hit. Catch it in time for a hoard.',
		'<strong>Loot filter</strong> (Hunt > Loot Filter), a loot channel with clickable item icons, loot rays for the best drops, Rarity Autoloot, autoloot, auto seller, bank and stash.',
	)),
	'crafting' => array('Crafting', array(
		'Orbs reshape your gear at the <strong>Crafting Bench</strong> (Economy > Crafting Bench): Awakening and Gilding turn normal items magic, Grafting adds a modifier, Unmaking removes one, Erasure makes an item normal again, Upheaval rerolls it with the same rarity and Fate with a new one. Tempering, Binding, Excision, Reforging, Ruin and Whetstones let you aim: new values, bind or cut a modifier of your choice, a risky gamble, and item quality.',
		'Orbs drop from monsters (more from tiered ones and bosses), from bounties and the weekly chest, and can be made from rune shards. The store sells only Whetstones, the Orb of Excision and the Orb of Binding, a few each week. Uniques cannot be crafted.',
	)),
	'endgame' => array('Endgame', array(
		'<strong>World bosses:</strong> a portal opens at every temple and one of five colossal bosses appears: Kaelgor the Infernal Warlord, Skaldra the Rime Queen, The Rotmother, Nyxareth the Void Archon or Vharok the Blood Colossus. Everyone who does real damage gets a reward.',
		'<strong>Bounty board</strong> (Adventure > Bounty Board): daily "kill X in Y" contracts per level band that pay orbs; seven in a week earn the weekly bounty chest.',
		'<strong>Rifts</strong> (Adventure > Rifts): a Rift Key opens a 10-minute instance for you and up to 3 party members. Keys have a tier (1-15) and 1-3 modifiers; harder modifiers raise the rewards. Kill the Guardian to seal the rift. A crash refunds your key.',
		'<strong>Infinity Tower</strong> (Adventure > Infinity Tower) alone or with a party, <strong>dungeons</strong>, and 17 level-scaled Chaos monsters (levels 650-1000) in the deepest hunting grounds.',
		'<strong>Events:</strong> Blood Moon weekends (+50% experience), Chaos Rift Wednesdays (double tiered spawns), Loot Frenzy Fridays, and a daily boosted creature and boss.',
	)),
	'seasons' => array('Seasons', array(
		'Start fresh with a <strong>season character</strong> (Adventure > Season, Join, on a new character) and race on the season ladder. Season characters trade, mail, party and loot only with their own season.',
		'Season uniques, and a reward track of outfits, addons, mounts and titles, unlocked for your whole account and kept forever. When the season ends, season characters join the normal world with everything they earned. See <a href="page?plugin=chaos&amp;p=seasons">Seasons</a>.',
	)),
	'pvp' => array('PvP', array(
		'<strong>Ranked arena</strong> (Adventure > Arena): 1v1 and 2v2 with an Elo rating per mode, matched by rating and level. Nobody really dies; each win pays an Orb of Upheaval.',
		'<strong>Guild Siege</strong> (Adventure > Guild Siege): every Saturday at 20:00, up to four guilds per arena fight over the Chaos Obelisk. The winners are Siege Champions for a week: a title and +5% experience.',
	)),
	'boards' => array('Leaderboards and titles', array(
		'Weekly boards (Social > Leaderboards) reset every Monday: World Boss damage, Bounty Hunter, Rifts, Goblin Slayer, Guild Siege, Arena 1v1 and 2v2. The top 3 of each board earn a title for the next week and orbs. The all-time Class Ladder ranks the highest characters of every class. See <a href="page?plugin=chaos&amp;p=leaderboards">Leaderboards</a>.',
	)),
	'qol' => array('Quality of life', array(
		'<strong>Combat visuals:</strong> crits, dodges and reflects get their own sprites; elemental weapon damage shows as its own coloured number.',
		'<strong>Patch notes in the client</strong>, a server-counted <strong>hunt tracker</strong> (Hunt > Hunt Tracker), <strong>daily rewards and login streaks</strong> with titles, <strong>waystones</strong> with account upgrades, and toast notifications.',
		'<strong>Store</strong> (Chaos Coins): outfits, mounts, wings, auras, outfit shaders and name plate frames, starter packs and bundles, store pouches, auto seller, training weapons, world buffs, name / vocation / sex change, blessings, passive tree reset. No random crafting orbs; achievement, season and class looks are never sold.',
	)),
);
?>
<div class="chaos-page">
<div class="chaos-box" id="about">
	<h1 class="chaos-heading">The world of Cinders of Chaos</h1>
	<p class="chaos-hero__quote">The world was not ended. It was broken, and the pieces still bleed.</p>
	<p class="chaos-lead">A dark fantasy online RPG with its own client. It keeps the classic top-down hunt-and-loot game and adds the depth of an action RPG: classes with ascensions, a huge passive tree, items with rarities and modifiers, crafting orbs, monsters that roll affixes, and endgame systems built for weeks of play rather than days.</p>
	<table class="chaos-table">
		<tbody>
			<tr><th>Client</th><td>Our own client (protocol 10.98) with a custom skin, a top menu and a window for every system</td></tr>
			<tr><th>Classes</th><td>7 class lines, each with 2 ascensions (14 ascended classes); the Necromancer, Monk and Templar unlock per account in the store</td></tr>
			<tr><th>Level cap</th><td>1000, then Paragon levels. Reaching 1000 takes roughly 100 hours of hunting</td></tr>
			<tr><th>Items</th><td>15 rarities, item levels, random modifiers, about 50 uniques</td></tr>
			<tr><th>Endgame</th><td>World bosses, bounties, rifts, the Infinity Tower, dungeons, arena, guild siege, weekly leaderboards</td></tr>
			<tr><th>Fair play</th><td>Multi-client rules; staff characters are left out of every leaderboard. Read the <a href="page?p=rules">rules</a>.</td></tr>
		</tbody>
	</table>
	<nav class="chaos-tabs" aria-label="Sections">
		<a class="chaos-tab" href="#classes">Classes</a>
		<?php foreach ($sections as $id => $s): ?><a class="chaos-tab" href="#<?= $h($id) ?>"><?= $h($s[0]) ?></a><?php endforeach; ?>
	</nav>
</div>

<div class="chaos-box" id="classes">
	<h2 class="chaos-heading">Classes</h2>
	<p class="chaos-lead">You start as one of seven classes (four free, three unlocked per account in the store). At level 100 you <strong>ascend</strong> into one of two specialisations at the Ascendant Oracle. Every class has its own Chaos spells with custom names, icons and effects; the spellbook (Character > Spellbook) lists them all. Balance is measured on test dummies at levels 300 and 1000, so every class keeps a clear role in a group.</p>
	<?php if (function_exists('chaos_class_lines')): ?>
	<table class="chaos-table">
		<thead><tr><th>Base class</th><th>Plays as</th><th>Ascensions</th></tr></thead>
		<tbody>
		<?php foreach (chaos_class_lines() as $line): ?>
			<tr>
				<td class="chaos-gold"><?= $h($line['name']) ?><?= $line['lock'] !== '' ? ' <span class="chaos-muted">(unlockable)</span>' : '' ?></td>
				<td><?= $h($line['plays']) ?></td>
				<td><?php foreach ($line['asc'] as $asc): ?><div><strong><?= $h($asc[0]) ?></strong>: <?= $h($asc[1]) ?></div><?php endforeach; ?></td>
			</tr>
		<?php endforeach; ?>
		</tbody>
	</table>
	<?php endif; ?>
</div>

<?php foreach ($sections as $id => $s): ?>
<div class="chaos-box" id="<?= $h($id) ?>">
	<h2 class="chaos-heading"><?= $h($s[0]) ?></h2>
	<div class="chaos-feature" style="box-shadow:none;background:none;border:0;padding:0">
		<ul><?php foreach ($s[1] as $p): ?><li><?= $p /* static, trusted text written above */ ?></li><?php endforeach; ?></ul>
	</div>
</div>
<?php endforeach; ?>
</div>
