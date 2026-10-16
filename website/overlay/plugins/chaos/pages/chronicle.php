<?php
/**
 * The Ashen Chronicle: the running season's chapters (goal bars, the top contributors, what each written chapter
 * changed) and the record of past seasons (who carried each chapter), read from the game server's chaos_chronicle_*
 * tables (chronicle_lib.php). The story itself: the wiki (Events tab) and the client (Adventure > Chronicle).
 * page?plugin=chaos&p=chronicle
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once dirname(__DIR__) . '/chronicle_lib.php';
$GLOBALS['page_title'] = 'The Ashen Chronicle';

$state = chaos_chronicle_state(5, 5);
?>
<div class="chaos-page">
	<div class="chaos-box">
		<h1 class="chaos-heading">The Ashen Chronicle <span class="chaos-muted" lang="pt-BR">A Crônica das Cinzas</span></h1>
		<p class="chaos-lead">Each season the whole realm writes one story together. World bosses slain, rifts sealed, Omens and the Ashen Sepulchre defeated and new heroes rising fill its chapters, and every written chapter changes the world: a new way opens, the capital is scarred or rebuilt, the Chronicler's words move on. At the season's end the Chronicler records who carried each chapter.</p>
		<?php if (empty($state['ok']) || ($state['current'] === null && !$state['past'])): ?>
			<p class="chaos-empty">The first page is still blank. The Chronicle begins with the season.</p>
		<?php else: ?>
			<?php if ($state['current'] !== null): ?>
				<h2 class="chaos-subheading"><?= chaos_h($state['current']['name']) ?>: <?= (int)$state['current']['done'] ?> of <?= count($state['current']['chapters']) ?> chapters written</h2>
				<?= chaos_chronicle_season_html($state['current'], true) ?>
			<?php endif; ?>
			<?php foreach ($state['past'] as $past): ?>
				<h2 class="chaos-subheading">The record of <?= chaos_h($past['name']) ?>: <?= (int)$past['done'] ?> of <?= count($past['chapters']) ?> chapters written</h2>
				<?= chaos_chronicle_season_html($past, false) ?>
			<?php endforeach; ?>
		<?php endif; ?>
		<p class="chaos-note">In the game: Adventure &gt; Chronicle. Names follow each character's Memorial choice (<a href="page?plugin=chaos&amp;p=memorial">the Memorial</a>).</p>
	</div>
</div>
