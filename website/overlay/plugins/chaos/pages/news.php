<?php
/**
 * News ("Novidades"): the changes of the game by week, newest first, the last weeks in full and the older ones in an
 * archive (news_lib.php, news/news_data.json, website/README.md "News and changelog (O687)").
 * page?plugin=chaos&p=news[&l=en|pt-BR]
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../news_lib.php';
require_once __DIR__ . '/../i18n_lib.php';
$GLOBALS['page_title'] = chaos_t('What is new');

$self = 'page?plugin=chaos&p=news';
$data = chaos_news_live_data(); // gated entries that are not live are left out (O688); the tests set the file in $GLOBALS['chaos_news_file']
$newIds = chaos_news_fresh_ids($data); // the NEW badge of the fresh featured entries (O688)
$split = chaos_news_split($data);
$lang = chaos_lang();
?>
<div class="chaos-page" id="chaos-news">
	<div class="chaos-box">
		<h1 class="chaos-heading"><?= chaos_h(chaos_t('What is new')) ?></h1>
		<p class="chaos-muted chaos-lang-row"><?= chaos_lang_link($self) ?></p>
		<p class="chaos-lead"><?= chaos_h(chaos_t('What changed in the game, week by week, newest first. The full weekly notes are on the Patch Notes page and in the game (Social > Patch Notes).')) ?></p>
		<?php if (!$split['recent']): ?>
			<p class="chaos-empty"><?= chaos_h(chaos_t('No news yet.')) ?></p>
		<?php else: ?>
			<?php foreach ($split['recent'] as $week): ?>
				<?= chaos_news_week_html($week, $lang, $newIds) ?>
			<?php endforeach; ?>
			<?php if ($split['archive']): ?>
				<details class="chaos-newsarchive" id="chaos-news-archive">
					<summary><?= chaos_h(chaos_t('Archive')) ?> <span class="chaos-muted">(<?= (int)count($split['archive']) ?>)</span></summary>
					<?php foreach ($split['archive'] as $week): ?>
						<?= chaos_news_week_html($week, $lang, $newIds) ?>
					<?php endforeach; ?>
				</details>
			<?php endif; ?>
		<?php endif; ?>
		<p><a class="chaos-btn chaos-btn--ghost" href="page?plugin=chaos&amp;p=patchnotes"><?= chaos_h(chaos_t('Patch Notes')) ?></a></p>
	</div>
</div>
