<?php
/**
 * Seasons: the current (or next) season from the server's season_config.lua,
 * its reward track, and the season ladder (characters in chaos_season_players) with a tab per
 * season mode (Self-Found, Hardcore, ...; chaos_season_modes) and the fallen Hardcore characters.
 * page?plugin=chaos&p=seasons[&mode=<all|standard|ssf|hc|hcssf|fallen>]
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
$GLOBALS['page_title'] = 'Seasons';

$seasons = chaos_seasons();
$now = time();
$current = null;
$next = null;
foreach ($seasons as $s) {
	if ($s['start'] <= $now && $now < $s['finish']) {
		$current = $s;
	} elseif ($s['start'] > $now && ($next === null || $s['start'] < $next['start'])) {
		$next = $s;
	}
}
$shown = $current ?? $next;
$track = chaos_season_track();
$hasTables = chaos_table_exists('chaos_season_players');
$modeTabs = chaos_season_mode_tabs();
$mode = (string)($_GET['mode'] ?? 'all');
if (!isset($modeTabs[$mode])) {
	$mode = 'all';
}
$fallenMarks = $mode === 'fallen' ? array() : chaos_fallen_marks();
$modeUrl = static function (string $key): string {
	return 'page?plugin=chaos&p=seasons&mode=' . rawurlencode($key);
};
$fmt = static function (int $t): string {
	return $t > 0 ? date('j M Y, H:i', $t) : '-';
};
?>
<div class="chaos-page">
	<div class="chaos-box">
		<h1 class="chaos-heading">Seasons</h1>
		<p class="chaos-lead">Start fresh with a season character: create a new character, then open Adventure &gt; Season in the game before level 8 and join. Season characters trade, mail, party and loot only with their own season, race on the season ladder, and join the normal world with everything they earned when the season ends.</p>
		<p class="chaos-muted">Pick a mode when you join: <span class="chaos-gold">Self-Found</span> (no trading of any kind, parties only with other Self-Found characters, a loot bonus), <span class="chaos-gold">Hardcore</span> (one life: a character that dies falls, leaves the Hardcore ladder and becomes a standard character) or both. Each has its own ladder.</p>

		<?php if ($shown === null): ?>
			<p class="chaos-empty">No season is running or announced right now.</p>
		<?php else: ?>
			<div class="chaos-season">
				<div class="chaos-season__state"><?= $current !== null ? 'Running now' : 'Coming soon' ?></div>
				<h2 class="chaos-season__name"><?= chaos_h($shown['name']) ?> <span class="chaos-muted"><?= chaos_h($shown['tag']) ?></span></h2>
				<dl class="chaos-facts">
					<dt>Starts</dt><dd><?= chaos_h($fmt($shown['start'])) ?></dd>
					<dt>Ends</dt><dd><?= chaos_h($fmt($shown['finish'])) ?></dd>
					<?php if ($shown['modifier'] !== ''): ?>
						<dt>Modifier</dt><dd><span class="chaos-gold"><?= chaos_h($shown['modifier']) ?></span>: <?= chaos_h($shown['modifier_text']) ?></dd>
					<?php endif; ?>
				</dl>
			</div>
		<?php endif; ?>

		<?php if ($track): ?>
			<h2 class="chaos-subheading">Reward track</h2>
			<p class="chaos-muted">Rewards unlock for your whole account and are kept forever.</p>
			<table class="chaos-table">
				<thead><tr><th>Milestone</th><th>Reward</th></tr></thead>
				<tbody>
				<?php foreach ($track as $m): ?>
					<tr><td><?= chaos_h($m['name']) ?></td><td class="chaos-gold"><?= chaos_h($m['reward']) ?></td></tr>
				<?php endforeach; ?>
				</tbody>
			</table>
		<?php endif; ?>
	</div>

	<?php if ($current !== null): ?>
	<div class="chaos-box">
		<h2 class="chaos-heading">Season ladder <small><?= chaos_h($current['tag']) ?></small></h2>
		<nav class="chaos-tabs" aria-label="Modes">
			<?php foreach ($modeTabs as $key => $label): ?>
				<a class="chaos-tab<?= $key === $mode ? ' is-active' : '' ?>" href="<?= chaos_h($modeUrl($key)) ?>"><?= $key === 'fallen' ? '&#9760; ' : '' ?><?= chaos_h($label) ?></a>
			<?php endforeach; ?>
		</nav>
		<?php if ($mode === 'fallen'): ?><p class="chaos-muted">Hardcore characters that died this season, by the level they fell at.</p><?php endif; ?>
		<?php if (!$hasTables): ?>
			<p class="chaos-empty">The season ladder opens with the season.</p>
		<?php else: ?>
			<div class="chaos-ladder">
				<?php foreach (chaos_class_lines() as $base => $line): $ladder = chaos_class_ladder($base, 10, (int)$current['id'], $mode); ?>
					<div class="chaos-ladder__col">
						<h3 class="chaos-ladder__name"><img src="<?= chaos_h(znote_plugin_asset('chaos', 'img/class-' . $line['icon'] . '.png')) ?>" alt="" width="28" height="28"> <?= chaos_h($line['name']) ?></h3>
						<ol class="chaos-ladder__list">
							<?php if (!$ladder): ?><li class="chaos-empty">Nobody yet.</li><?php endif; ?>
							<?php foreach ($ladder as $r): ?>
								<?php $fell = $mode === 'fallen' ? array((string)$r['name'] => array('level' => (int)($r['fallen_level'] ?? 0), 'cause' => (string)($r['fallen_cause'] ?? ''))) : $fallenMarks; ?>
								<li><a href="characterprofile?name=<?= rawurlencode((string)$r['name']) ?>"><?= chaos_h($r['name']) ?></a><?= chaos_fallen_html($fell, (string)$r['name']) ?>
									<span class="chaos-muted"><?= chaos_h(chaos_class_name((int)$r['vocation'])) ?></span>
									<span class="chaos-ladder__lvl"><?= $mode === 'fallen' ? (int)($r['fallen_level'] ?? 0) : (int)$r['level'] ?></span></li>
							<?php endforeach; ?>
						</ol>
					</div>
				<?php endforeach; ?>
			</div>
		<?php endif; ?>
	</div>
	<?php endif; ?>
</div>
