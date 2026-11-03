<?php
/**
 * A shared build (O391): page?plugin=chaos&p=build&c=CODE draws a full build code made in the client (Passive Tree >
 * Build Code > Copy Full Build) or on a character page: class, passive tree, spell rotation and gear, with a link to
 * share. buildcode_lib.php decodes; nothing is read from the database. Without a code (or with a bad one) the page
 * shows a form to paste one.
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once dirname(__DIR__) . '/buildcode_lib.php';

$raw = isset($_GET['c']) && is_string($_GET['c']) ? substr($_GET['c'], 0, CHAOS_BUILDCODE_MAX + 64) : '';
$code = chaos_buildcode_extract($raw) ?? trim($raw);
$result = $code !== '' ? chaos_buildcode_decode($code) : array('error' => 'empty');
$card = $result['card'] ?? null;
$GLOBALS['page_title'] = $card !== null ? chaos_build_title($card) . ' - Build' : 'Build';
if ($card !== null) {
	$parts = array();
	if (!empty($card['tree_info']['nodes'])) {
		$parts[] = count(array_diff($card['tree_info']['nodes'], array(1))) . ' passive points';
	}
	if (!empty($card['spells'])) {
		$parts[] = count($card['spells']) . ' spells';
	}
	if (!empty($card['gear'])) {
		$parts[] = count($card['gear']) . ' items';
	}
	$GLOBALS['page_description'] = 'A ' . chaos_build_title($card) . ' build' . ($parts ? ': ' . implode(', ', $parts) : '') . '.';
} elseif ($code !== '') {
	http_response_code(404);
}
$siteUrl = (string)($GLOBALS['config']['site_url'] ?? '');
?>
<div class="chaos-page">
	<div class="chaos-box">
		<h1 class="chaos-heading"><?= chaos_h($card !== null ? chaos_build_title($card) : 'Build') ?></h1>
		<?php if ($card !== null): ?>
			<?= chaos_build_html($card, $code, $siteUrl) ?>
		<?php else: ?>
			<?php if ($code !== ''): ?>
				<p class="chaos-error"><?= chaos_h(chaos_buildcode_error_text((string)$result['error'])) ?></p>
			<?php endif; ?>
			<p class="chaos-lead">A full build code holds a class, the passive tree, the spell rotation and the gear. Make one in the game: Passive Tree &gt; Build Code &gt; Copy Full Build. Every character page has one too.</p>
		<?php endif; ?>
		<form class="chaos-pick" method="get" action="page" aria-label="Build code">
			<input type="hidden" name="plugin" value="chaos">
			<input type="hidden" name="p" value="build">
			<label class="chaos-pick__field"><span class="chaos-pick__label">Build code</span>
				<input type="text" name="c" maxlength="<?= CHAOS_BUILDCODE_MAX ?>" value="<?= chaos_h($card !== null ? '' : $code) ?>" placeholder="CC1-..."></label>
			<button type="submit" class="chaos-pick__go">Show</button>
		</form>
	</div>
</div>
