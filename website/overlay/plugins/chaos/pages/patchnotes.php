<?php
/**
 * Patch notes: the Markdown files of the game server's data/patchnotes/
 * folder, read with the rules of patchnotes_core.lua (the in-game window).
 * page.php?plugin=chaos&p=patchnotes[&id=<file id>]
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
$GLOBALS['page_title'] = 'Patch Notes';

$notes = chaos_patchnotes();
$want = (string)($_GET['id'] ?? '');
$current = $notes[0] ?? null;
if ($want !== '' && chaos_pn_valid_id($want)) {
	foreach ($notes as $n) {
		if ($n['id'] === $want) {
			$current = $n;
			break;
		}
	}
}
?>
<div class="chaos-page">
	<div class="chaos-box">
		<h1 class="chaos-heading">Patch Notes</h1>
		<p class="chaos-lead">Every week's changes, the same notes as the Patch Notes window in the game (top menu, or <code>!patchnotes</code>).</p>
		<?php if (!$notes): ?>
			<p class="chaos-empty">No patch notes yet.</p>
		<?php else: ?>
			<div class="chaos-pn-layout">
				<ul class="chaos-pn-list">
					<?php foreach ($notes as $n): ?>
						<li class="<?= $current !== null && $n['id'] === $current['id'] ? 'is-active' : '' ?>">
							<a href="page.php?plugin=chaos&amp;p=patchnotes&amp;id=<?= rawurlencode($n['id']) ?>">
								<span class="chaos-pn-list__date"><?= chaos_h($n['date'] ?? '') ?></span>
								<span class="chaos-pn-list__title"><?= chaos_h($n['title']) ?></span>
							</a>
						</li>
					<?php endforeach; ?>
				</ul>
				<div class="chaos-pn-body"><?= $current !== null ? chaos_pn_render($current) : '' ?></div>
			</div>
		<?php endif; ?>
	</div>
</div>
