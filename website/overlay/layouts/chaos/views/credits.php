<?php
/**
 * Credits: ZnoteX's own credits page, unchanged, plus the layout credit. The stock view asks GitHub for the
 * contributor list while it renders and fails when GitHub answers with an error (rate limit); then a short version
 * with the same credits and a link to the list is shown instead of a broken page.
 */
$level = ob_get_level();
ob_start();
try {
	include dirname(__DIR__, 2) . '/default/views/credits.php';
	$html = (string)ob_get_clean();
} catch (Throwable $e) {
	while (ob_get_level() > $level) {
		ob_end_clean();
	}
	$html = '<div class="znx-acct"><div class="znx-acct-head">ZnoteX</div><div class="znx-acct-info">' . t('credits.znotex_text') . '</div>'
		. '<div class="znx-acct-head">Znote AAC</div><div class="znx-acct-info"><p>' . t('credits.znote_text') . '</p><p>' . t('credits.opensource') . '</p>'
		. '<p><a href="https://github.com/Open-Games-Community/ZnoteX">ZnoteX</a> &middot; <a href="https://github.com/Znote/ZnoteAAC/graphs/contributors">' . t('credits.full_list') . '</a></p></div></div>';
}
?>
<div class="chaos-page">
	<div class="chaos-box">
		<?= $html ?>
		<div class="znx-acct-head">Cinders of Chaos layout</div>
		<div class="znx-acct-info">Based on the Void layout by Alex (opengamescommunity.com), re-coloured and framed for Cinders of Chaos.</div>
	</div>
</div>
