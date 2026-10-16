<?php
/**
 * Credits (credits_lib.php): page?plugin=chaos&p=credits[&l=en]. Every third-party source of the game from
 * docs/CREDITS.md (credits/credits_data.json). Portuguese headings by default, English with &l=en. Linked from the
 * footer and from the site's credits page.
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once dirname(__DIR__) . '/credits_lib.php';

$lang = chaos_credits_lang($_GET);
$other = $lang === 'en' ? 'pt-BR' : 'en';
$GLOBALS['page_title'] = chaos_credits_t('title', $lang);
?>
<div class="chaos-page">
	<div class="chaos-box chaos-credits" id="chaos-credits" lang="<?= chaos_h($lang) ?>">
		<p class="chaos-tabs">
			<a class="chaos-tab" href="<?= chaos_h(chaos_credits_url($other)) ?>" lang="<?= chaos_h($other) ?>"><?= chaos_h(chaos_credits_t('other', $lang)) ?></a>
		</p>
		<h1 class="chaos-heading"><?= chaos_h(chaos_credits_t('title', $lang)) ?></h1>
		<p><?= chaos_h(chaos_credits_t('intro', $lang)) ?></p>
		<?= chaos_credits_render(chaos_credits_data(), $lang) ?>
	</div>
</div>
