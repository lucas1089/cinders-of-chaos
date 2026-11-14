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
// the page's language (plugins/chaos/i18n_lib.php, website/README.md "Languages"); English when the plugin is missing
if (!function_exists('chaos_t') && is_file(dirname(__DIR__, 3) . '/plugins/chaos/i18n_lib.php')) {
	require_once dirname(__DIR__, 3) . '/plugins/chaos/i18n_lib.php';
}
if (!function_exists('chaos_t')) {
	function chaos_t(string $en, ...$args): string { return $args ? vsprintf($en, $args) : $en; }
}
if (!function_exists('chaos_media_trailer_html') && is_file(dirname(__DIR__, 3) . '/plugins/chaos/media_lib.php')) {
	require_once dirname(__DIR__, 3) . '/plugins/chaos/media_lib.php';
}
// trailer, shorts and screenshots (plugins/chaos/media_lib.php): '' without the plugin or its media files
$mediaTrailer = function_exists('chaos_media_trailer_html') ? chaos_media_trailer_html() : '';
$mediaShorts = function_exists('chaos_media_shorts_html') ? chaos_media_shorts_html() : '';
$mediaGallery = function_exists('chaos_media_gallery_html') ? chaos_media_gallery_html() : '';
$plugin = function_exists('chaos_class_lines');
$lines = $plugin ? chaos_class_lines() : array();
$icon = static function (string $name): string {
	return function_exists('znote_plugin_asset') ? znote_plugin_asset('chaos', 'img/class-' . $name . '.png') : '';
};
$features = array(
	chaos_t('Passive tree and Paragon') => array(chaos_t('Over 600 nodes, and never enough points for all of them'), chaos_t('Class keystones: Cleaving Arc, Ricochet, Arcane Echo, party auras'), chaos_t('Build codes to share; respec priced by your level'), chaos_t('Paragon points for every level after 1000')),
	chaos_t('Items and loot') => array(chaos_t('7 rarities from Common to Divine, and the uniques'), chaos_t('Item levels and random modifiers; about 50 uniques'), chaos_t('Monsters roll Magic, Rare or Legendary affixes'), chaos_t('Loot filter, loot rays and treasure goblins')),
	chaos_t('Crafting orbs') => array(chaos_t('Awakening and Gilding make magic items'), chaos_t('Grafting adds a modifier, Unmaking removes one'), chaos_t('Upheaval and Fate reroll; Erasure starts over'), chaos_t('All at the Crafting Bench (Alt+C)')),
	chaos_t('Endgame') => array(chaos_t('Five colossal world bosses with phases'), chaos_t('Rifts: keys with tiers 1-15 and modifiers'), chaos_t('Infinity Tower, dungeons and the bounty board'), chaos_t('17 level-scaled monsters in the deepest grounds')),
	chaos_t('Seasons and PvP') => array(chaos_t('Fresh season characters with their own ladder'), chaos_t('Season uniques and an account-wide reward track'), chaos_t('Ranked arena 1v1 and 2v2 with Elo ratings'), chaos_t('Weekly Guild Siege for the Chaos Obelisk')),
	chaos_t('Quality of life') => array(chaos_t('One-click Auto setup and a starter kit per class'), chaos_t('Hunt tracker: experience and profit per hour'), chaos_t('Daily rewards with login streaks and titles'), chaos_t('Patch notes right in the client')),
);
$latest = $plugin && function_exists('chaos_patchnotes') ? (chaos_patchnotes()[0] ?? null) : null;
?>
<div class="chaos-page">
	<section class="chaos-box chaos-hero">
		<div class="chaos-hero__copy">
			<h1 class="chaos-hero__title"><?= $h(chaos_t('Top-down hunt and loot with the depth of an action RPG')) ?></h1>
			<p class="chaos-hero__text"><?= $h(chaos_t('Cinders of Chaos is a dark fantasy online RPG with its own client: classes with ascensions, a huge passive tree, items with rarities and modifiers, crafting orbs, and an endgame built for weeks of play.')) ?></p>
			<div class="chaos-cta">
				<a class="chaos-btn" href="downloads"><?= $h(chaos_t('Download the client')) ?></a>
				<?php if ($mediaTrailer !== ''): ?>
					<a class="chaos-btn chaos-btn--ghost" href="#trailer"><?= $h(chaos_t('Watch the trailer')) ?></a>
				<?php endif; ?>
				<?php if (function_exists('user_logged_in') && user_logged_in()): ?>
					<a class="chaos-btn chaos-btn--ghost" href="createcharacter"><?= $h(chaos_t('Create a character')) ?></a>
				<?php else: ?>
					<a class="chaos-btn chaos-btn--ghost" href="register"><?= $h(chaos_t('Create an account')) ?></a>
				<?php endif; ?>
				<a class="chaos-btn chaos-btn--ghost" href="page?plugin=chaos&amp;p=guide"><?= $h(chaos_t('New player? Start here')) ?></a>
			</div>
		</div>
		<dl class="chaos-hero__facts">
			<div><dt><?= $h(chaos_t('Classes')) ?></dt><dd>7</dd></div>
			<div><dt><?= $h(chaos_t('Passive nodes')) ?></dt><dd>600+</dd></div>
			<div><dt><?= $h(chaos_t('Item rarities')) ?></dt><dd>7</dd></div>
			<div><dt><?= $h(chaos_t('World bosses')) ?></dt><dd>5</dd></div>
		</dl>
	</section>

	<?= $mediaTrailer ?>
	<?= $mediaShorts ?>

	<?php if ($lines): ?>
	<section class="chaos-box">
		<h2 class="chaos-heading"><?= $h(chaos_t('Choose your path')) ?></h2>
		<p class="chaos-lead"><?= $h(chaos_t('Start as one of seven classes (four free, three unlocked by reaching level 200). At level 100 you ascend into one of two specialisations with the Ascendant Oracle in the market of the teleport room.')) ?></p>
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
		<p class="chaos-note"><?= $h(chaos_t('The Monk, the Necromancer and the Templar unlock for your whole account once any of your characters reaches level 200.')) ?></p>
	</section>
	<?php endif; ?>

	<section class="chaos-box">
		<h2 class="chaos-heading"><?= $h(chaos_t('What waits for you')) ?></h2>
		<div class="chaos-features">
			<?php foreach ($features as $title => $items): ?>
				<div class="chaos-feature">
					<h3><?= $h($title) ?></h3>
					<ul><?php foreach ($items as $it): ?><li><?= $h($it) ?></li><?php endforeach; ?></ul>
				</div>
			<?php endforeach; ?>
		</div>
		<a class="chaos-btn chaos-btn--ghost chaos-features__more" href="page?plugin=chaos&amp;p=wiki"><?= $h(chaos_t('Read the guide')) ?></a>
	</section>

	<?= $mediaGallery ?>
	<?= function_exists('chaos_media_script_html') ? chaos_media_script_html($mediaTrailer . $mediaGallery) : '' ?>

	<?php $community = function_exists('chaos_community_state') ? chaos_community_block_html(chaos_community_state(time())) : ''; ?>
	<?php if ($community !== ''): // the community goal and the week's world modifiers (plugins/chaos/community_lib.php) ?>
	<section class="chaos-box">
		<h2 class="chaos-heading"><?= $h(chaos_t('The Great Brazier')) ?></h2>
		<?= $community ?>
		<a class="chaos-btn chaos-btn--ghost" href="page?plugin=chaos&amp;p=community"><?= $h(chaos_t('Community goal and contributors')) ?></a>
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
		<h2 class="chaos-heading"><?= $h(chaos_t('Latest patch notes')) ?> <small><?= $h($latest['date'] ?? '') ?></small></h2>
		<h3 class="chaos-subheading"><?= $h($latest['title']) ?></h3>
		<?php foreach (array_slice($latest['intro'], 0, 2) as $l): ?><p class="chaos-lead"><?= $h($l) ?></p><?php endforeach; ?>
		<a class="chaos-btn chaos-btn--ghost" href="page?plugin=chaos&amp;p=patchnotes&amp;id=<?= rawurlencode((string)$latest['id']) ?>"><?= $h(chaos_t('Read the full notes')) ?></a>
	</section>
	<?php endif; ?>

	<section class="chaos-box chaos-news">
		<h2 class="chaos-heading"><?= $h(chaos_t('News')) ?></h2>
		<?php if (empty($news)): ?>
			<p class="chaos-empty"><?= $h(chaos_t('No news yet.')) ?></p>
		<?php else: foreach (array_slice($news, 0, (int)($config['news_per_page'] ?? 4)) as $n): ?>
			<article class="chaos-news__item">
				<h3><a href="?view=<?= (int)$n['id'] ?>"><?= znote_bbcode_raw((string)$n['title']) ?></a></h3>
				<div class="chaos-news__meta"><?= $h(getClock($n['date'], true)) ?> &middot; <?= $h($n['name']) ?></div>
				<div><?= znote_bbcode_raw((string)$n['text']) ?></div>
			</article>
		<?php endforeach; endif; ?>
	</section>
</div>
