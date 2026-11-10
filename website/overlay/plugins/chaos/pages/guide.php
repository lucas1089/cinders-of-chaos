<?php
/**
 * Start here: the beginner guide (guide_lib.php, guide/guide_data.json, website/README.md "Beginner guide (O373)").
 * First steps, then every feature by the level where it opens, then the ones of any level. The texts are the game's
 * "How it works" cards. page?plugin=chaos&p=guide[&l=en|pt-BR]
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../guide_lib.php';
require_once __DIR__ . '/../i18n_lib.php';
$GLOBALS['page_title'] = chaos_t('Start here');

$self = 'page?plugin=chaos&p=guide';
$data = chaos_guide_data();
$sections = chaos_guide_view($data);
$lang = chaos_lang();
$headings = $data['headings'];
?>
<div class="chaos-page" id="chaos-guide">
	<div class="chaos-box">
		<h1 class="chaos-heading"><?= chaos_h(chaos_t('Start here')) ?> <small><?= chaos_h(chaos_t('Beginner guide')) ?></small></h1>
		<p class="chaos-muted chaos-lang-row"><?= chaos_lang_link($self) ?></p>
		<p class="chaos-lead"><?= chaos_h(chaos_bi($data['intro'])) ?></p>
		<p class="chaos-muted"><?= chaos_h(chaos_t('In the game, System > Help Search (Alt+F) finds any of these answers, and the ? button of a window opens its card.')) ?></p>

		<?php if (empty($data['cards'])): ?>
			<p class="chaos-empty"><?= chaos_h(chaos_t('The guide is not available right now.')) ?></p>
		<?php else: ?>
		<nav class="chaos-guide-toc" aria-label="<?= chaos_h(chaos_t('On this page')) ?>">
			<?php foreach ($sections as $s): ?>
				<a href="#<?= chaos_h($s['id']) ?>"><?= chaos_h(chaos_bi($s['title'])) ?></a>
			<?php endforeach; ?>
			<?php foreach ($sections[1]['groups'] as $g): ?>
				<a class="chaos-muted" href="#<?= chaos_h($g['id']) ?>"><?= chaos_h(chaos_t('Level %d+', (int)$g['level'])) ?></a>
			<?php endforeach; ?>
		</nav>

		<?php foreach ($sections as $s): ?>
			<section class="chaos-guide-section" id="<?= chaos_h($s['id']) ?>">
				<h2 class="chaos-subheading"><?= chaos_h(chaos_bi($s['title'])) ?></h2>
				<?php if ($s['id'] === 'steps'): ?>
					<ol class="chaos-guide-steps">
						<?php foreach ($s['groups'][0]['cards'] as $c): ?>
							<li><?= chaos_guide_card_html($c[0], $c[1], $c[2], $headings, $lang) ?></li>
						<?php endforeach; ?>
					</ol>
				<?php else: ?>
					<?php foreach ($s['groups'] as $g): ?>
						<?php if ($g['level'] !== null): ?>
							<h3 class="chaos-guide-level" id="<?= chaos_h($g['id']) ?>"><?= chaos_h(chaos_t('Opens at level %d', (int)$g['level'])) ?></h3>
						<?php endif; ?>
						<div class="chaos-guide-cards">
							<?php foreach ($g['cards'] as $c): ?><?= chaos_guide_card_html($c[0], $c[1], $c[2], $headings, $lang) ?><?php endforeach; ?>
						</div>
					<?php endforeach; ?>
				<?php endif; ?>
			</section>
		<?php endforeach; ?>
		<?php endif; ?>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Read more')) ?></h2>
		<ul id="chaos-guide-more">
			<?php $wikiLang = $lang === 'en' ? '&amp;l=en' : ''; ?>
			<li><a href="page?plugin=chaos&amp;p=wiki&amp;t=guide%3Astart<?= $wikiLang ?>"><?= chaos_h(chaos_t('Getting started: account, client and the first levels')) ?></a></li>
			<li><a href="page?plugin=chaos&amp;p=wiki&amp;t=guide%3Aleveling<?= $wikiLang ?>"><?= chaos_h(chaos_t('Leveling guide: where to hunt at each level')) ?></a></li>
			<li><a href="page?plugin=chaos&amp;p=starterbuilds<?= $wikiLang ?>"><?= chaos_h(chaos_t('Starter builds')) ?></a></li>
			<li><a href="downloads"><?= chaos_h(chaos_t('Download the client')) ?></a></li>
		</ul>
	</div>
</div>
