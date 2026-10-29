<?php
/**
 * Creator program ("Programa de Criadores"): who qualifies, what a creator gets, how to apply and the media kit
 * (creators_lib.php, creators/creators_data.json, website/README.md "Creator program"). The creator code itself is
 * the existing creator code system (pages/creator.php). Undecided parts say "To be set" ("A definir").
 * page?plugin=chaos&p=creators[&l=en|pt-BR]
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../creators_lib.php';
require_once __DIR__ . '/../i18n_lib.php';
$GLOBALS['page_title'] = chaos_t('Creator Program');

$self = 'page?plugin=chaos&p=creators';
$data = chaos_creators_data();
$kit = chaos_creators_kit();
$state = static function (string $s): string {
	return $s === 'built' ? chaos_t('Available') : ($s === 'proposal' ? chaos_t('Proposed, to be confirmed') : chaos_t('To be set'));
};
?>
<div class="chaos-page" id="chaos-creators">
	<div class="chaos-box">
		<h1 class="chaos-heading"><?= chaos_h(chaos_t('Creator Program')) ?></h1>
		<p class="chaos-muted chaos-lang-row"><?= chaos_lang_link($self) ?></p>
		<p class="chaos-lead"><?= chaos_h(chaos_t('Streamers and video makers are how many players find Cinders of Chaos. This is what we offer them, what is ready and what is still to be set.')) ?></p>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Who qualifies')) ?></h2>
		<p class="chaos-muted"><?= chaos_h(chaos_bi($data['qualify']['intro'])) ?></p>
		<ul id="chaos-creators-qualify">
			<?php foreach ($data['qualify']['items'] as $line): ?><li><?= chaos_h(chaos_bi($line)) ?></li><?php endforeach; ?>
		</ul>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('What you get')) ?></h2>
		<table class="chaos-table" id="chaos-creators-benefits">
			<thead><tr><th><?= chaos_h(chaos_t('Benefit')) ?></th><th><?= chaos_h(chaos_t('How it works')) ?></th><th><?= chaos_h(chaos_t('State')) ?></th></tr></thead>
			<tbody>
			<?php foreach ($data['benefits'] as $b): ?>
				<tr id="benefit-<?= chaos_h($b['id']) ?>">
					<td><strong><?= chaos_h(chaos_bi($b['title'])) ?></strong></td>
					<td><?= chaos_h(chaos_bi($b['text'])) ?></td>
					<td><?= chaos_h($state((string)$b['status'])) ?></td>
				</tr>
			<?php endforeach; ?>
			</tbody>
		</table>
		<p class="chaos-muted"><?= chaos_h(chaos_t('Donations are always voluntary.')) ?> <a href="page?plugin=chaos&amp;p=creator"><?= chaos_h(chaos_t('Creator Codes')) ?></a> &middot; <a href="page?plugin=chaos&amp;p=fairplay"><?= chaos_h(chaos_t('What the store never sells')) ?></a></p>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('How to apply')) ?></h2>
		<p class="chaos-muted"><?= chaos_h(chaos_bi($data['apply']['intro'])) ?></p>
		<ol id="chaos-creators-apply">
			<?php foreach ($data['apply']['steps'] as $line): ?><li><?= chaos_h(chaos_bi($line)) ?></li><?php endforeach; ?>
		</ol>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Media kit')) ?></h2>
		<?php if ($kit['zip']): ?>
			<p id="chaos-creators-kit"><a class="chaos-button" href="<?= chaos_h((string)$kit['zip']['path']) ?>"><?= chaos_h(chaos_t('Download the media kit (%s)', chaos_creators_size((int)$kit['zip']['bytes']))) ?></a></p>
			<ul class="chaos-muted">
				<?php foreach ($kit['files'] as $f): ?><li><?= chaos_h((string)$f['name']) ?> <span>(<?= chaos_h(chaos_creators_size((int)$f['bytes'])) ?>)</span></li><?php endforeach; ?>
			</ul>
		<?php else: ?>
			<p class="chaos-muted"><?= chaos_h(chaos_t('The media kit is not available right now.')) ?></p>
		<?php endif; ?>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Still to be decided')) ?></h2>
		<ul id="chaos-creators-open">
			<?php foreach ($data['open'] as $q): ?><li id="open-<?= chaos_h($q['id']) ?>"><?= chaos_h(chaos_bi($q['text'])) ?></li><?php endforeach; ?>
		</ul>
		<?php if ($data['updated'] !== ''): ?><p class="chaos-muted" style="font-size:12px;"><?= chaos_h(chaos_t('Last reviewed: %s.', $data['updated'])) ?></p><?php endif; ?>
	</div>
</div>
