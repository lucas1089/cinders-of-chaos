<?php
/**
 * Trending builds (O409; pt-BR "Builds em alta"): page?plugin=chaos&p=trends. The game server's daily snapshot
 * (server/data/scripts/chaos/build_trends.lua, table chaos_build_trends): per class the most played builds, grouped by
 * the keystones taken, with their share of the class, the number of characters and their average level. Each build
 * links to the build page (pages/build.php draws its full build code) and has a copy button (assets/js/chaos-copy.js;
 * without JavaScript the code is a read-only field to select). No character name is in the table or on the page.
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../i18n_lib.php';
require_once dirname(__DIR__) . '/buildcode_lib.php';
$GLOBALS['page_title'] = chaos_t('Trending builds');
$GLOBALS['page_description'] = chaos_t('The most played builds of every class this week: keystones, share of the class and the full build code.');

list($trendAt, $trends) = chaos_build_trends();
$lines = chaos_class_lines();
ksort($lines);
?>
<div class="chaos-page">
	<div class="chaos-box">
		<h1 class="chaos-heading"><?= chaos_h(chaos_t('Trending builds')) ?></h1>
		<p class="chaos-muted chaos-lang-row"><?= chaos_lang_link('page?plugin=chaos&p=trends') ?></p>
		<p class="chaos-lead"><?= chaos_h(chaos_t('What every class plays: the passive trees of the characters active in the last 7 days (level 100 and up), grouped by the keystones they took. A build appears once at least 3 characters play it. No names are shown.')) ?></p>
		<?php if ($trendAt <= 0): ?>
			<p class="chaos-muted"><?= chaos_h(chaos_t('No snapshot yet. The server counts the builds once a day.')) ?></p>
		<?php else: ?>
			<p class="chaos-muted"><?= chaos_h(chaos_t('Snapshot of %s.', date('Y-m-d', $trendAt))) ?>
				<?= chaos_h(chaos_t('In the game: Passive Tree > Build Code > Trending Builds imports one.')) ?></p>
		<?php endif; ?>
		<p><a href="page?plugin=chaos&amp;p=build"><?= chaos_h(chaos_t('Open a build code')) ?></a>
			&middot; <a href="page?plugin=chaos&amp;p=leaderboards"><?= chaos_h(chaos_t('Leaderboards')) ?></a></p>
	</div>

	<?php if ($trendAt > 0): ?>
	<div class="chaos-box">
		<div class="chaos-ladder chaos-trends">
			<?php foreach ($lines as $base => $line): $list = array_slice($trends[$base] ?? array(), 0, 5); ?>
				<div class="chaos-ladder__col">
					<h2 class="chaos-ladder__name"><img src="<?= chaos_h(znote_plugin_asset('chaos', 'img/class-' . $line['icon'] . '.png')) ?>" alt="" width="28" height="28"> <?= chaos_h($line['name']) ?></h2>
					<?php if (!$list): ?>
						<p class="chaos-empty"><?= chaos_h(chaos_t('No build is played by enough characters yet.')) ?></p>
					<?php else: ?>
						<p class="chaos-muted"><?= chaos_h(chaos_t('%d active characters', (int)$list[0]['total'])) ?></p>
						<ol class="chaos-trends__list">
							<?php foreach ($list as $r):
								$code = (string)$r['code'];
								$copy = $code !== '' ? $code : (string)$r['tree_code'];
								$keys = trim((string)$r['keystones']);
							?>
								<li class="chaos-trends__item">
									<strong class="chaos-gold"><?= chaos_h(chaos_share_text((int)$r['share'])) ?></strong>
									<?= chaos_h($keys !== '' ? $keys : chaos_t('No keystone')) ?>
									<br><span class="chaos-muted"><?= chaos_h(chaos_t('%1$d characters, average level %2$d', (int)$r['count'], (int)$r['avg_level'])) ?></span>
									<br><?php if ($code !== ''): ?><a href="<?= chaos_h(chaos_build_url($code)) ?>"><?= chaos_h(chaos_t('View build')) ?></a> &middot; <?php endif; ?>
									<button type="button" class="chaos-copy" data-chaos-copy="<?= chaos_h($copy) ?>" data-chaos-copied="<?= chaos_h(chaos_t('Copied')) ?>" hidden><?= chaos_h(chaos_t('Copy code')) ?></button>
									<input class="chaos-build__share chaos-copy__field" type="text" readonly value="<?= chaos_h($copy) ?>" aria-label="<?= chaos_h(chaos_t('Build code')) ?>">
								</li>
							<?php endforeach; ?>
						</ol>
					<?php endif; ?>
				</div>
			<?php endforeach; ?>
		</div>
	</div>
	<script src="<?= chaos_h(znote_plugin_asset('chaos', 'js/chaos-copy.js')) ?>" defer></script>
	<?php endif; ?>
</div>
