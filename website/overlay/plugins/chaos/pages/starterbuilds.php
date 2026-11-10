<?php
/**
 * Starter builds: three Recommended builds for every class (starter_builds_lib.php, guide/starter_builds_data.json, O448).
 * What each does, how it plays, its price, the keystones, spells, gear, a card set and an import code per point cut. The
 * texts have no damage figure. The same builds are in the game, in the Auto build list of the passive tree.
 * page?plugin=chaos&p=starterbuilds[&l=en|pt-BR]
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../starter_builds_lib.php';
require_once __DIR__ . '/../i18n_lib.php';
$GLOBALS['page_title'] = chaos_t('Starter builds');

$self = 'page?plugin=chaos&p=starterbuilds';
$data = chaos_starter_data();
$lang = chaos_lang();
$wikiLang = $lang === 'en' ? '&amp;l=en' : '';
?>
<div class="chaos-page" id="chaos-starterbuilds">
	<div class="chaos-box">
		<h1 class="chaos-heading"><?= chaos_h(chaos_t('Starter builds')) ?> <small><?= chaos_h(chaos_t('Three Recommended builds for every class')) ?></small></h1>
		<p class="chaos-muted chaos-lang-row"><?= chaos_lang_link($self) ?></p>

		<?php if (empty($data['classes'])): ?>
			<p class="chaos-empty"><?= chaos_h(chaos_t('The builds are not available right now.')) ?></p>
		<?php else: ?>
		<p class="chaos-lead"><?= chaos_h(chaos_bi($data['intro'])) ?></p>
		<ol id="chaos-sb-howto">
			<?php foreach ($data['howTo'] as $step): ?><li><?= chaos_h(chaos_bi($step)) ?></li><?php endforeach; ?>
		</ol>
		<p class="chaos-muted"><?= chaos_h(chaos_starter_label($data, 'keystoneNote')) ?> <?= chaos_h(chaos_starter_label($data, 'cardRule')) ?></p>

		<nav class="chaos-guide-toc" aria-label="<?= chaos_h(chaos_t('On this page')) ?>">
			<?php foreach ($data['classes'] as $c): ?>
				<a href="#class-<?= chaos_h($c['key']) ?>"><?= chaos_h($c['name']) ?></a>
			<?php endforeach; ?>
		</nav>

		<?php foreach ($data['classes'] as $c): ?>
			<section class="chaos-guide-section" id="class-<?= chaos_h($c['key']) ?>">
				<h2 class="chaos-subheading"><?= chaos_h($c['name']) ?></h2>
				<p class="chaos-muted"><?= chaos_h(chaos_bi($c['line'] ?? '')) ?></p>
				<div class="chaos-guide-cards">
					<?php foreach ((array)$c['builds'] as $b): ?><?= chaos_starter_build_html($b, $data, $lang) ?><?php endforeach; ?>
				</div>
			</section>
		<?php endforeach; ?>
		<?php endif; ?>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Read more')) ?></h2>
		<ul id="chaos-sb-more">
			<li><a href="page?plugin=chaos&amp;p=wiki&amp;t=guide%3Atree<?= $wikiLang ?>"><?= chaos_h(chaos_t('The passive tree and example builds')) ?></a></li>
			<li><a href="page?plugin=chaos&amp;p=guide"><?= chaos_h(chaos_t('Start here: the beginner guide')) ?></a></li>
		</ul>
	</div>
</div>
