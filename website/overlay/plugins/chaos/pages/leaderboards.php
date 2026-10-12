<?php
/**
 * Leaderboards: the weekly boards (chaos_leaderboard), the title holders of
 * the last scored week (chaos_leaderboard_titles) and the all-time Class
 * Ladder (players, grouped by class line). Read-only.
 * page.php?plugin=chaos&p=leaderboards[&board=<key>][&class=<base class id>|all]
 * A board with byClass (leaderboard_config.lua) has class tabs, "All classes" first, as in the client.
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
$GLOBALS['page_title'] = 'Leaderboards';

$boards = chaos_leaderboard_boards();
$board = (string)($_GET['board'] ?? '');
if (!isset($boards[$board])) {
	$board = (string)array_key_first($boards);
}
$def = $boards[$board];
// class tabs (byClass): the class group asked for, anything else = every class (LB.sendBoard)
$classGroups = !empty($def['byClass']) ? chaos_leaderboard_class_groups() : array();
$classKey = (string)($_GET['class'] ?? 'all');
if (!ctype_digit($classKey) || !isset($classGroups[(int)$classKey])) {
	$classKey = 'all';
}
$classIds = $classKey === 'all' ? array() : $classGroups[(int)$classKey]['ids'];
$week = chaos_week_key(time(), 6);
$rows = chaos_leaderboard_rows($board, $week, 20, ($def['mode'] ?? '') === 'min', $classIds);
list($titleWeek, $titleRows) = chaos_leaderboard_titles();
$fallenMarks = chaos_fallen_marks(); // season modes: the skull of a fallen Hardcore character on the Class Ladder
// the class tab stays picked when moving to another board with class tabs, as in the client
$url = static function (string $key, ?string $class = null) use ($boards, $classKey): string {
	$class = $class ?? $classKey;
	$u = 'page.php?plugin=chaos&p=leaderboards&board=' . rawurlencode($key);
	return (!empty($boards[$key]['byClass']) && $class !== 'all') ? $u . '&class=' . rawurlencode($class) : $u;
};
?>
<div class="chaos-page">
	<div class="chaos-box">
		<h1 class="chaos-heading">Leaderboards</h1>
		<p class="chaos-lead">Weekly boards reset every Monday at 06:00 server time. The top 3 of each board earn a title for the next week and orbs in their inbox. Staff characters are left out of every board.</p>

		<nav class="chaos-tabs" aria-label="Boards">
			<?php foreach ($boards as $key => $b): ?>
				<a class="chaos-tab<?= $key === $board ? ' is-active' : '' ?>" href="<?= chaos_h($url($key)) ?>"><?= chaos_h($b['name']) ?></a>
			<?php endforeach; ?>
		</nav>

		<?php if ($classGroups): ?>
			<nav class="chaos-tabs chaos-tabs--classes" aria-label="Classes">
				<a class="chaos-tab<?= $classKey === 'all' ? ' is-active' : '' ?>" href="<?= chaos_h($url($board, 'all')) ?>">All classes</a>
				<?php foreach ($classGroups as $base => $g): ?>
					<a class="chaos-tab<?= $classKey === (string)$base ? ' is-active' : '' ?>" href="<?= chaos_h($url($board, (string)$base)) ?>" title="<?= chaos_h(implode(', ', array_map('chaos_class_name', chaos_line_ids($base)))) ?>"><img src="<?= chaos_h(znote_plugin_asset('chaos', 'img/class-' . $g['icon'] . '.png')) ?>" alt="" width="18" height="18"> <?= chaos_h($g['name']) ?></a>
				<?php endforeach; ?>
			</nav>
		<?php endif; ?>

		<h2 class="chaos-subheading"><?= chaos_h($def['name']) ?><?php if ($classKey !== 'all'): ?> &middot; <?= chaos_h($classGroups[(int)$classKey]['name']) ?><?php endif; ?> <small>week of <?= chaos_h(chaos_week_label($week)) ?></small></h2>
		<?php if ($def['info'] !== ''): ?><p class="chaos-muted"><?= chaos_h($def['info']) ?><?php if ($def['title'] !== ''): ?> Title: <span class="chaos-gold"><?= chaos_h($def['title']) ?></span>.<?php endif; ?></p><?php endif; ?>
		<table class="chaos-table">
			<thead><tr><th>#</th><th>Name</th><th>Class</th><th class="num"><?= chaos_h($def['value']) ?></th><?php if ($def['count'] !== ''): ?><th class="num"><?= chaos_h($def['count']) ?></th><?php endif; ?></tr></thead>
			<tbody>
			<?php if (!$rows): ?>
				<tr><td colspan="5" class="chaos-empty"><?= $classKey === 'all' ? 'No scores yet this week. Be the first.' : chaos_h('No ' . $classGroups[(int)$classKey]['name'] . ' on this board yet this week. Be the first.') ?></td></tr>
			<?php else: foreach ($rows as $i => $r): ?>
				<tr class="<?= $i < 3 ? 'chaos-top chaos-top-' . ($i + 1) : '' ?>">
					<td><?= $i + 1 ?></td>
					<td><a href="characterprofile.php?name=<?= rawurlencode((string)$r['name']) ?>"><?= chaos_h($r['name']) ?></a></td>
					<td><?= chaos_h(chaos_class_name((int)$r['vocation'])) ?></td>
					<td class="num"><?= chaos_h(chaos_leaderboard_value($def, $r['value'])) ?></td>
					<?php if ($def['count'] !== ''): ?><td class="num"><?= (int)$r['count'] ?></td><?php endif; ?>
				</tr>
			<?php endforeach; endif; ?>
			</tbody>
		</table>
	</div>

	<div class="chaos-box">
		<h2 class="chaos-heading">Title holders</h2>
		<?php if (!$titleRows): ?>
			<p class="chaos-muted">No week has been scored yet. Titles are awarded at the Monday reset.</p>
		<?php else: ?>
			<p class="chaos-muted">Winners of the week of <?= chaos_h(chaos_week_label($titleWeek)) ?>; they hold their titles until the next reset.</p>
			<table class="chaos-table">
				<thead><tr><th>Board</th><th>Rank</th><th>Name</th><th>Class</th><th>Title</th></tr></thead>
				<tbody>
				<?php foreach ($titleRows as $r): ?>
					<tr>
						<td><?= chaos_h($boards[(string)$r['board']]['name'] ?? (string)$r['board']) ?></td>
						<td><?= chaos_h(array('1st', '2nd', '3rd')[(int)$r['rank'] - 1] ?? ('#' . (int)$r['rank'])) ?></td>
						<td><a href="characterprofile.php?name=<?= rawurlencode((string)$r['name']) ?>"><?= chaos_h($r['name']) ?></a></td>
						<td><?= chaos_h(chaos_class_name((int)$r['vocation'])) ?></td>
						<td class="chaos-gold"><?= chaos_h($r['title']) ?></td>
					</tr>
				<?php endforeach; ?>
				</tbody>
			</table>
		<?php endif; ?>
	</div>

	<div class="chaos-box">
		<h2 class="chaos-heading">Class Ladder</h2>
		<p class="chaos-muted">All time: the highest characters of every class line, ascensions included.</p>
		<div class="chaos-ladder">
			<?php foreach (chaos_class_lines() as $base => $line): $ladder = chaos_class_ladder($base, 10); ?>
				<div class="chaos-ladder__col">
					<h3 class="chaos-ladder__name"><img src="<?= chaos_h(znote_plugin_asset('chaos', 'img/class-' . $line['icon'] . '.png')) ?>" alt="" width="28" height="28"> <?= chaos_h($line['name']) ?></h3>
					<ol class="chaos-ladder__list">
						<?php if (!$ladder): ?><li class="chaos-empty">Nobody yet.</li><?php endif; ?>
						<?php foreach ($ladder as $r): ?>
							<li><a href="characterprofile.php?name=<?= rawurlencode((string)$r['name']) ?>"><?= chaos_h($r['name']) ?></a><?= chaos_fallen_html($fallenMarks, (string)$r['name']) ?>
								<span class="chaos-muted"><?= chaos_h(chaos_class_name((int)$r['vocation'])) ?></span>
								<span class="chaos-ladder__lvl"><?= (int)$r['level'] ?></span></li>
						<?php endforeach; ?>
					</ol>
				</div>
			<?php endforeach; ?>
		</div>
	</div>
</div>
