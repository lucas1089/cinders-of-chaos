<?php
/**
 * Cinders of Chaos front page: the pitch, the classes, the features, the latest
 * patch notes and the news. Data comes from index.php ($news, $page, $view)
 * and from the chaos plugin when it is active. A news permalink or a news page
 * other than the first falls back to the stock front page view.
 */
if (($view ?? '') !== '' || (int)($page ?? 0) > 0) {
	include dirname(__DIR__, 2) . '/default/views/index.php';
	return;
}
$h = static function ($v): string { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); };
$plugin = function_exists('chaos_class_lines');
$lines = $plugin ? chaos_class_lines() : array();
$icon = static function (string $name): string {
	return function_exists('znote_plugin_asset') ? znote_plugin_asset('chaos', 'img/class-' . $name . '.png') : '';
};
$features = array(
	'Passive tree and Paragon' => array('Over 600 nodes, and never enough points for all of them', 'Class keystones: Cleaving Arc, Ricochet, Arcane Echo, party auras', 'Build codes to share; respec priced by your level', 'Paragon points for every level after 1000'),
	'Items and loot' => array('7 rarities from Common to Divine, and the uniques', 'Item levels and random modifiers; about 50 uniques', 'Monsters roll Magic, Rare or Legendary affixes', 'Loot filter, loot rays and treasure goblins'),
	'Crafting orbs' => array('Awakening and Gilding make magic items', 'Grafting adds a modifier, Unmaking removes one', 'Upheaval and Fate reroll; Erasure starts over', 'All at the Crafting Bench (!craft)'),
	'Endgame' => array('Five colossal world bosses with phases', 'Rifts: keys with tiers 1-15 and modifiers', 'Infinity Tower, dungeons and the bounty board', '17 level-scaled monsters in the deepest grounds'),
	'Seasons and PvP' => array('Fresh season characters with their own ladder', 'Season uniques and an account-wide reward track', 'Ranked arena 1v1 and 2v2 with Elo ratings', 'Weekly Guild Siege for the Chaos Obelisk'),
	'Quality of life' => array('Tutorial island and a starter kit per class', 'Hunt tracker: experience and profit per hour', 'Daily rewards with login streaks and titles', 'Patch notes right in the client'),
);
$latest = $plugin && function_exists('chaos_patchnotes') ? (chaos_patchnotes()[0] ?? null) : null;
?>
<div class="chaos-page">
	<section class="chaos-box chaos-hero">
		<h1 class="chaos-hero__title">Enter the broken world</h1>
		<p class="chaos-hero__quote">The world was not ended. It was broken, and the pieces still bleed.</p>
		<div class="chaos-divider"></div>
		<p class="chaos-hero__text">Cinders of Chaos is a dark fantasy online RPG with its own client. It keeps the classic top-down hunt-and-loot game and adds the depth of an action RPG: classes with ascensions, a huge passive tree, items with rarities and modifiers, crafting orbs, monsters that roll affixes, and endgame systems built for weeks of play rather than days.</p>
		<div class="chaos-cta">
			<?php if (function_exists('user_logged_in') && user_logged_in()): ?>
				<a class="chaos-btn" href="createcharacter">Create a character</a>
			<?php else: ?>
				<a class="chaos-btn" href="register">Create an account</a>
			<?php endif; ?>
			<a class="chaos-btn chaos-btn--ghost" href="downloads">Download the client</a>
			<a class="chaos-btn chaos-btn--ghost" href="page?plugin=chaos&amp;p=wiki">Read the guide</a>
		</div>
	</section>

	<?php if ($lines): ?>
	<section class="chaos-box">
		<h2 class="chaos-heading">Choose your path</h2>
		<p class="chaos-lead">Start as one of seven classes (four free, three unlocked by reaching level 200). At level 100 you ascend into one of two specialisations with the Ascendant Oracle in the market of the teleport room.</p>
		<div class="chaos-classes">
			<?php foreach ($lines as $base => $line): ?>
				<div class="chaos-class<?= $line['lock'] !== '' ? ' is-locked' : '' ?>">
					<img src="<?= $h($icon($line['icon'])) ?>" alt="">
					<div class="chaos-class__name"><?= $h($line['name']) ?></div>
					<div class="chaos-class__plays"><?= $h($line['plays']) ?></div>
					<ul class="chaos-class__asc">
						<?php foreach ($line['asc'] as $asc): ?>
							<li><strong><?= $h($asc[0]) ?></strong><?= $h($asc[1]) ?></li>
						<?php endforeach; ?>
					</ul>
				</div>
			<?php endforeach; ?>
		</div>
		<p class="chaos-note">The Monk, the Necromancer and the Templar unlock for your whole account once any of your characters reaches level 200.</p>
	</section>
	<?php endif; ?>

	<section class="chaos-box">
		<h2 class="chaos-heading">What waits for you</h2>
		<div class="chaos-features">
			<?php foreach ($features as $title => $items): ?>
				<div class="chaos-feature">
					<h3><?= $h($title) ?></h3>
					<ul><?php foreach ($items as $it): ?><li><?= $h($it) ?></li><?php endforeach; ?></ul>
				</div>
			<?php endforeach; ?>
		</div>
	</section>

	<?php $community = function_exists('chaos_community_state') ? chaos_community_block_html(chaos_community_state(time())) : ''; ?>
	<?php if ($community !== ''): // the community goal and the week's world modifiers (plugins/chaos/community_lib.php) ?>
	<section class="chaos-box">
		<h2 class="chaos-heading">The Great Brazier</h2>
		<?= $community ?>
		<a class="chaos-btn chaos-btn--ghost" href="page?plugin=chaos&amp;p=community">Community goal and contributors</a>
	</section>
	<?php endif; ?>

	<section class="chaos-box" id="chaos-seasons-optional">
		<h2 class="chaos-heading">Temporadas opcionais <small>Optional seasons</small></h2>
		<p class="chaos-lead" lang="pt-BR">Seu personagem é permanente, as temporadas são opcionais, o legado é cosmético. Nenhum personagem normal é apagado por uma temporada. Quem entra joga com um personagem novo e, no fim, ele vira um personagem normal; para a conta vão outfits, montarias e títulos.</p>
		<p class="chaos-lead">Your character is permanent, seasons are optional, the legacy is cosmetic. A season never wipes a standard character. Whoever joins plays a new character that becomes a standard one at the end; the account keeps outfits, mounts and titles.</p>
		<a class="chaos-btn chaos-btn--ghost" href="page?plugin=chaos&amp;p=calendar">Calendário / Calendar</a>
	</section>

	<?php if ($latest !== null): ?>
	<section class="chaos-box">
		<h2 class="chaos-heading">Latest patch notes <small><?= $h($latest['date'] ?? '') ?></small></h2>
		<h3 class="chaos-subheading"><?= $h($latest['title']) ?></h3>
		<?php foreach (array_slice($latest['intro'], 0, 2) as $l): ?><p class="chaos-lead"><?= $h($l) ?></p><?php endforeach; ?>
		<a class="chaos-btn chaos-btn--ghost" href="page?plugin=chaos&amp;p=patchnotes&amp;id=<?= rawurlencode((string)$latest['id']) ?>">Read the full notes</a>
	</section>
	<?php endif; ?>

	<section class="chaos-box chaos-news">
		<h2 class="chaos-heading">News</h2>
		<?php if (empty($news)): ?>
			<p class="chaos-empty">No news yet.</p>
		<?php else: foreach (array_slice($news, 0, (int)($config['news_per_page'] ?? 4)) as $n): ?>
			<article class="chaos-news__item">
				<h3><a href="?view=<?= (int)$n['id'] ?>"><?= znote_bbcode_raw((string)$n['title']) ?></a></h3>
				<div class="chaos-news__meta"><?= $h(getClock($n['date'], true)) ?> &middot; <?= $h($n['name']) ?></div>
				<div><?= znote_bbcode_raw((string)$n['text']) ?></div>
			</article>
		<?php endforeach; endif; ?>
	</section>
</div>
