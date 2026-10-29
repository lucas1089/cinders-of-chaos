<?php
/**
 * What the store never sells: the fair-play pledge (fairplay_lib.php, fairplay/fairplay_data.json, website/README.md
 * "Fair play"). Three lists: never sold, sold, and the time savers with their limits (the gray areas, in the open).
 * page?plugin=chaos&p=fairplay[&l=en|pt-BR]
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../fairplay_lib.php';
require_once __DIR__ . '/../i18n_lib.php';
$GLOBALS['page_title'] = chaos_t('What the store never sells');

$self = 'page?plugin=chaos&p=fairplay';
$data = chaos_fairplay_data();
?>
<div class="chaos-page" id="chaos-fairplay">
	<div class="chaos-box">
		<h1 class="chaos-heading"><?= chaos_h(chaos_t('What the store never sells')) ?></h1>
		<p class="chaos-muted chaos-lang-row"><?= chaos_lang_link($self) ?></p>
		<p class="chaos-lead"><?= chaos_h(chaos_t('Cinders of Chaos is free to play. The store pays for the server and never sells power. This is our pledge, and this page is tested against the settings of the game server, so it cannot drift from what the store really does.')) ?></p>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Never sold')) ?></h2>
		<ul class="chaos-fairplay-list" id="chaos-fairplay-never">
			<?php foreach ($data['never'] as $e): ?>
				<li id="never-<?= chaos_h($e['id']) ?>"><strong><?= chaos_h(chaos_bi($e['title'])) ?></strong>. <?= chaos_h(chaos_bi($e['text'] ?? '')) ?></li>
			<?php endforeach; ?>
		</ul>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('What the store sells')) ?></h2>
		<ul class="chaos-fairplay-list" id="chaos-fairplay-sold">
			<?php foreach ($data['sold'] as $e): ?>
				<li id="sold-<?= chaos_h($e['id']) ?>"><strong><?= chaos_h(chaos_bi($e['title'])) ?></strong>. <?= chaos_h(chaos_bi($e['text'] ?? '')) ?></li>
			<?php endforeach; ?>
		</ul>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('What time savers exist and their limits')) ?></h2>
		<p class="chaos-muted"><?= chaos_h(chaos_bi($data['gray'])) ?></p>
		<table class="chaos-table" id="chaos-fairplay-timesavers">
			<thead><tr><th><?= chaos_h(chaos_t('Time saver')) ?></th><th><?= chaos_h(chaos_t('What it does')) ?></th><th><?= chaos_h(chaos_t('Its limit')) ?></th></tr></thead>
			<tbody>
			<?php foreach ($data['timesavers'] as $e): ?>
				<tr id="timesaver-<?= chaos_h($e['id']) ?>">
					<td><strong><?= chaos_h(chaos_bi($e['title'])) ?></strong></td>
					<td><?= chaos_h(chaos_bi($e['what'] ?? '')) ?></td>
					<td><?= chaos_h(chaos_bi($e['limit'] ?? '')) ?></td>
				</tr>
			<?php endforeach; ?>
			</tbody>
		</table>

		<p class="chaos-muted"><?= chaos_h(chaos_t('Prices are in the in-game Store (Economy > Store) and on the Donate page. Donations are always voluntary.')) ?></p>
		<p><a class="chaos-button" href="page?plugin=chaos&amp;p=coins"><?= chaos_h(chaos_t('Back to the Donate page')) ?></a></p>
		<?php if ($data['updated'] !== ''): ?>
			<p class="chaos-muted" style="font-size:12px;"><?= chaos_h(chaos_t('Last reviewed: %s.', $data['updated'])) ?></p>
		<?php endif; ?>
	</div>
</div>
