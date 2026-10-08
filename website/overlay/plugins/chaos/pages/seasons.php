<?php
/**
 * Seasons: the current (or next) season from the server's season_config.lua,
 * its reward track, and the season ladder (characters in chaos_season_players).
 * page.php?plugin=chaos&p=seasons
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
$fmt = static function (int $t): string {
	return $t > 0 ? date('j M Y, H:i', $t) : '-';
};
?>
<div class="chaos-page">
	<div class="chaos-box">
		<h1 class="chaos-heading">Seasons</h1>
		<p class="chaos-lead">Start fresh with a season character: create a new character, then type <code>!season join</code> in the game before level 8. Season characters trade, mail, party and loot only with their own season, race on the season ladder, and join the normal world with everything they earned when the season ends.</p>

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
		<?php if (!$hasTables): ?>
			<p class="chaos-empty">The season ladder opens with the season.</p>
		<?php else: ?>
			<div class="chaos-ladder">
				<?php foreach (chaos_class_lines() as $base => $line): $ladder = chaos_class_ladder($base, 10, (int)$current['id']); ?>
					<div class="chaos-ladder__col">
						<h3 class="chaos-ladder__name"><img src="<?= chaos_h(znote_plugin_asset('chaos', 'img/class-' . $line['icon'] . '.png')) ?>" alt="" width="28" height="28"> <?= chaos_h($line['name']) ?></h3>
						<ol class="chaos-ladder__list">
							<?php if (!$ladder): ?><li class="chaos-empty">Nobody yet.</li><?php endif; ?>
							<?php foreach ($ladder as $r): ?>
								<li><a href="characterprofile.php?name=<?= rawurlencode((string)$r['name']) ?>"><?= chaos_h($r['name']) ?></a>
									<span class="chaos-muted"><?= chaos_h(chaos_class_name((int)$r['vocation'])) ?></span>
									<span class="chaos-ladder__lvl"><?= (int)$r['level'] ?></span></li>
							<?php endforeach; ?>
						</ol>
					</div>
				<?php endforeach; ?>
			</div>
		<?php endif; ?>
	</div>
	<?php endif; ?>
</div>
