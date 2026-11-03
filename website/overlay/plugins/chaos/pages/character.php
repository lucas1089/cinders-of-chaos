<?php
/**
 * A character's page (O392): page?plugin=chaos&p=character&name=NAME. Gear, achievements and titles, level
 * milestones, best runs, season results and a build code, read only (character_lib.php; privacy rules there).
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once dirname(__DIR__) . '/character_lib.php';

$name = isset($_GET['name']) && is_string($_GET['name']) ? $_GET['name'] : '';
$char = chaos_character_find($name);
$siteUrl = (string)($GLOBALS['config']['site_url'] ?? '');
if ($char === null) {
	$GLOBALS['page_title'] = 'Character';
	if ($name !== '') {
		http_response_code(404);
	}
} else {
	$data = chaos_character_page($char);
	$GLOBALS['page_title'] = (string)$char['name'];
	$GLOBALS['page_description'] = (string)$char['name'] . ', level ' . (int)$char['level'] . ' ' . chaos_class_name((int)$char['vocation'])
		. ': ' . $data['achievements']['count'] . ' achievements, gear and best runs.';
}
?>
<div class="chaos-page">
	<div class="chaos-box">
		<?php if ($char === null): ?>
			<h1 class="chaos-heading">Character</h1>
			<?php if ($name !== ''): ?>
				<p class="chaos-error">No character with this name.</p>
			<?php endif; ?>
			<form class="chaos-pick" method="get" action="page" aria-label="Character">
				<input type="hidden" name="plugin" value="chaos">
				<input type="hidden" name="p" value="character">
				<label class="chaos-pick__field"><span class="chaos-pick__label">Name</span>
					<input type="text" name="name" maxlength="64" value="<?= chaos_h($name) ?>"></label>
				<button type="submit" class="chaos-pick__go">Show</button>
			</form>
		<?php else: ?>
			<h1 class="chaos-heading"><?= chaos_h($char['name']) ?></h1>
			<?= chaos_character_html($char, $data, $siteUrl) ?>
		<?php endif; ?>
	</div>
</div>
