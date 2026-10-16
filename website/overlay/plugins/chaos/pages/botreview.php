<?php
/**
 * Staff: bot review (page?plugin=chaos&p=botreview). The days the game server flagged (botreview.lua), with the
 * score, each signal, the explanations and a timeline. Nothing here punishes: staff look, then mark the day reviewed,
 * false positive or escalated; every mark is logged (chaos_bot_actions). Penalties follow the GM handbook ladder.
 *
 *  - GET status / days / name / page: the list of flagged days, highest score first.
 *  - GET id: one day: signals (automation and unattended), explanations, hourly timeline, the character's last 30
 *    days, its presence checks (anti-bot log) and the staff actions.
 *  - POST rid + do (reviewed | false_positive | escalate | note | check) + note + CSRF token: the action, then the day.
 * Access: admin panel accounts with a group 4+ character; an escalated day changes only with group 5+.
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../botreview_lib.php';

$accountId = function_exists('getSession') ? (int)getSession('user_id') : 0;
$group = chaos_botreview_group($config, $accountId);
if ($group <= 0) {
	http_response_code(404);
	$GLOBALS['page_title'] = 'Not found';
	echo '<div class="chaos-page"><div class="chaos-box"><h1 class="chaos-heading">Not found</h1><p>This page does not exist.</p></div></div>';
	return;
}
$GLOBALS['page_title'] = 'Bot Review';
$self = 'page?plugin=chaos&p=botreview';
$now = time();

if (session_status() === PHP_SESSION_ACTIVE && empty($_SESSION['chaos_botreview_csrf'])) {
	$_SESSION['chaos_botreview_csrf'] = bin2hex(random_bytes(16));
}
$csrf = (string)($_SESSION['chaos_botreview_csrf'] ?? '');

$message = '';
$messageOk = true;
$detailId = (int)($_GET['id'] ?? 0);
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && isset($_POST['rid'])) {
	if ($csrf === '' || !hash_equals($csrf, (string)($_POST['csrf'] ?? ''))) {
		$message = 'The form expired. Please try again.';
		$messageOk = false;
	} else {
		[$messageOk, $message] = chaos_botreview_action((string)($_POST['do'] ?? ''), (int)$_POST['rid'],
			(string)($_POST['note'] ?? ''), chaos_report_staff_name($accountId), $group, $now);
	}
	$detailId = (int)$_POST['rid'];
}

$f = chaos_botreview_filters($_GET);
$statuses = chaos_botreview_statuses();
$signalNames = chaos_botreview_signal_names();
$time = static function (int $t): string { return $t > 0 ? gmdate('Y-m-d H:i', $t) : '-'; };
$dayText = static function ($d): string {
	$d = (string)$d;
	return strlen($d) === 8 ? substr($d, 0, 4) . '-' . substr($d, 4, 2) . '-' . substr($d, 6, 2) : $d;
};
$link = static function (array $over) use ($self, $f): string {
	$q = array_merge(array('status' => $f['status'], 'days' => $f['days'], 'name' => $f['name']), $over);
	$q = array_filter($q, static function ($v) { return $v !== '' && $v !== null; });
	return $self . ($q ? '&' . http_build_query($q) : '');
};
$bar = static function (float $v, string $color): string {
	$w = max(0, min(100, (int)round($v * 100)));
	return '<span style="display:inline-block;width:120px;height:9px;background:rgba(255,255,255,0.08);vertical-align:middle;">'
		. '<span style="display:block;height:9px;width:' . $w . '%;background:' . $color . ';"></span></span>';
};
$row = $detailId > 0 ? chaos_botreview_row($detailId) : null;
?>
<div class="chaos-page" id="chaos-botreview">
	<div class="chaos-box">
		<h1 class="chaos-heading">Bot Review</h1>
		<p class="chaos-lead">Days the game server flagged for a look (score 50+ of 100). Nothing here punishes anyone: watch the character, send a presence check, talk to it, then mark the day. A helper user still moves, chats and takes breaks; the score needs signs that nobody is at the keyboard. Times are UTC.</p>

		<nav class="chaos-tabs" aria-label="Status">
			<?php foreach ($statuses + array('all' => 'All') as $key => $label): ?>
				<a class="chaos-tab<?= !$row && $f['status'] === $key ? ' is-active' : '' ?>" href="<?= chaos_h($link(array('status' => $key, 'page' => null))) ?>"><?= chaos_h($label) ?></a>
			<?php endforeach; ?>
		</nav>

		<?php if ($message !== ''): ?>
			<p class="<?= $messageOk ? 'chaos-gold' : 'chaos-error' ?>" id="chaos-botreview-message"<?= $messageOk ? '' : ' style="color:#e07060;"' ?>><?= chaos_h($message) ?></p>
		<?php endif; ?>

		<?php if ($row): ?>
			<?php
			$signals = chaos_botreview_parse_signals((string)$row['signals']);
			$timeline = chaos_botreview_parse_timeline((string)$row['timeline']);
			$reasons = array_filter(array_map('trim', explode('|', (string)$row['reasons'])), 'strlen');
			$history = chaos_botreview_history((int)$row['player_id']);
			$actions = chaos_botreview_actions((int)$row['player_id']);
			$abLog = chaos_botreview_antibot_log((int)$row['player_id']);
			$locked = $row['status'] === 'escalated' && $group < CHAOS_BOTREVIEW_ADMIN_GROUP;
			?>
			<p><a href="<?= chaos_h($link(array())) ?>">&larr; back to the list</a></p>
			<h2 class="chaos-heading" id="chaos-botreview-day"><?= chaos_h($row['player_name']) ?>, <?= chaos_h($dayText($row['day'])) ?></h2>
			<p>Day score <strong class="<?= (int)$row['score'] >= 50 ? 'chaos-gold' : '' ?>"><?= (int)$row['score'] ?></strong> (highest moment <?= (int)$row['peak'] ?>).
				Status: <strong><?= chaos_h($statuses[$row['status']] ?? (string)$row['status']) ?></strong><?php if ((string)$row['reviewed_by'] !== ''): ?>, by <?= chaos_h($row['reviewed_by']) ?> at <?= chaos_h($time((int)$row['reviewed_at'])) ?><?php endif; ?>.
				<?php if ((string)$row['note'] !== ''): ?><br><span class="chaos-muted">Note:</span> <?= chaos_h($row['note']) ?><?php endif; ?></p>

			<h3>Signals</h3>
			<p class="chaos-muted" style="font-size:12px;">Automation alone (the allowed client helper) never makes a high score; the score needs at least two unattended signs. 0 = like a person, 1 = like a program.</p>
			<table class="chaos-table" id="chaos-botreview-signals">
				<thead><tr><th>Family</th><th>Signal</th><th class="num">Value</th><th></th></tr></thead>
				<tbody>
				<?php foreach ($signalNames as $key => $info): ?>
					<?php $v = $signals[$key] ?? 0.0; ?>
					<tr>
						<td class="chaos-muted"><?= chaos_h($info[0]) ?></td>
						<td><?= chaos_h($info[1]) ?></td>
						<td class="num"><?= number_format($v, 2) ?></td>
						<td><?= $bar($v, $info[0] === 'automation' ? '#8aa0c8' : '#e0a050') ?></td>
					</tr>
				<?php endforeach; ?>
				</tbody>
			</table>
			<?php if ($reasons): ?>
				<ul id="chaos-botreview-reasons">
					<?php foreach ($reasons as $r): ?><li><?= chaos_h($r) ?></li><?php endforeach; ?>
				</ul>
			<?php endif; ?>

			<h3>Timeline</h3>
			<div id="chaos-botreview-timeline" style="display:flex;align-items:flex-end;gap:2px;height:80px;border-bottom:1px solid rgba(255,255,255,0.2);" aria-label="Score by hour">
				<?php for ($hour = 0; $hour < 24; $hour++): ?>
					<?php $s = $timeline[$hour] ?? null; ?>
					<div title="<?= sprintf('%02d:00', $hour) ?>: <?= $s === null ? 'offline' : (int)$s ?>" style="flex:1;height:<?= $s === null ? 1 : max(2, (int)$s * 0.8) ?>px;background:<?= $s === null ? 'rgba(255,255,255,0.1)' : ($s >= 50 ? '#e0a050' : '#8aa0c8') ?>;"></div>
				<?php endfor; ?>
			</div>
			<div class="chaos-muted" style="display:flex;justify-content:space-between;font-size:11px;"><span>00</span><span>06</span><span>12</span><span>18</span><span>23</span></div>

			<h3>Last 30 days</h3>
			<table class="chaos-table" id="chaos-botreview-history">
				<thead><tr><th>Day</th><th class="num">Score</th><th>Status</th></tr></thead>
				<tbody>
				<?php foreach ($history as $h): ?>
					<tr>
						<td><a href="<?= chaos_h($self . '&id=' . (int)$h['id']) ?>"><?= chaos_h($dayText($h['day'])) ?></a></td>
						<td class="num"><?= (int)$h['score'] ?> <?= $bar((int)$h['score'] / 100, (int)$h['flagged'] === 1 ? '#e0a050' : '#8aa0c8') ?></td>
						<td><?= chaos_h($statuses[$h['status']] ?? ((int)$h['flagged'] === 1 ? (string)$h['status'] : 'not flagged')) ?></td>
					</tr>
				<?php endforeach; ?>
				</tbody>
			</table>

			<?php if ($abLog): ?>
				<h3>Presence checks and anti-bot log</h3>
				<table class="chaos-table" id="chaos-botreview-antibot">
					<thead><tr><th>Time</th><th>Entry</th><th class="num">Score</th><th>Detail</th></tr></thead>
					<tbody>
					<?php foreach ($abLog as $l): ?>
						<tr><td><?= chaos_h($time((int)$l['created_at'])) ?></td><td><?= chaos_h(str_replace('_', ' ', (string)$l['kind'])) ?></td>
							<td class="num"><?= (int)$l['score'] ?></td><td class="chaos-muted" style="font-size:12px;"><?= chaos_h($l['detail']) ?></td></tr>
					<?php endforeach; ?>
					</tbody>
				</table>
			<?php endif; ?>

			<h3>Review</h3>
			<?php if ($locked): ?>
				<p class="chaos-muted" id="chaos-botreview-locked">Escalated: an administrator (group 5) decides. You can still add a note or request a presence check.</p>
			<?php endif; ?>
			<form method="post" action="<?= chaos_h($self . '&id=' . (int)$row['id']) ?>" id="chaos-botreview-form">
				<input type="hidden" name="csrf" value="<?= chaos_h($csrf) ?>">
				<input type="hidden" name="rid" value="<?= (int)$row['id'] ?>">
				<input type="text" name="note" maxlength="255" size="60" value="<?= chaos_h($row['note']) ?>" placeholder="what you found">
				<?php if (!$locked): ?>
					<button type="submit" name="do" value="reviewed" class="chaos-button">Mark reviewed</button>
					<button type="submit" name="do" value="false_positive" class="chaos-button">False positive</button>
					<button type="submit" name="do" value="escalate" class="chaos-button">Escalate</button>
				<?php endif; ?>
				<button type="submit" name="do" value="note" class="chaos-button">Save note</button>
				<button type="submit" name="do" value="check" class="chaos-button">Request presence check</button>
			</form>
			<?php if ($actions): ?>
				<table class="chaos-table" id="chaos-botreview-actions" style="margin-top:8px;">
					<thead><tr><th>Time</th><th>Day</th><th>Action</th><th>By</th><th>Note</th></tr></thead>
					<tbody>
					<?php foreach ($actions as $a): ?>
						<tr><td><?= chaos_h($time((int)$a['created_at'])) ?></td><td><?= chaos_h($dayText($a['day'])) ?></td>
							<td><?= chaos_h(str_replace('_', ' ', (string)$a['action'])) ?><?php if ($a['action'] === 'check'): ?> <span class="chaos-muted">(<?= (int)$a['done_at'] > 0 ? chaos_h($a['result']) : 'waiting' ?>)</span><?php endif; ?></td>
							<td><?= chaos_h($a['staff']) ?></td><td class="chaos-muted"><?= chaos_h($a['note']) ?></td></tr>
					<?php endforeach; ?>
					</tbody>
				</table>
			<?php endif; ?>
		<?php else: ?>
			<?php [$rows, $total] = chaos_botreview_list($f, $now); ?>
			<form method="get" action="page" class="chaos-filter" style="margin:10px 0;">
				<input type="hidden" name="plugin" value="chaos">
				<input type="hidden" name="p" value="botreview">
				<input type="hidden" name="status" value="<?= chaos_h($f['status']) ?>">
				<label>Days
					<select name="days">
						<?php foreach (array(1 => 'today', 7 => 'last 7 days', 30 => 'last 30 days') as $d => $label): ?>
							<option value="<?= $d ?>"<?= $f['days'] === $d ? ' selected' : '' ?>><?= chaos_h($label) ?></option>
						<?php endforeach; ?>
					</select>
				</label>
				<label>Name <input type="text" name="name" maxlength="29" value="<?= chaos_h($f['name']) ?>" placeholder="character"></label>
				<button type="submit" class="chaos-button">Filter</button>
			</form>
			<p class="chaos-muted"><?= (int)$total ?> day(s).</p>
			<table class="chaos-table" id="chaos-botreview-list">
				<thead><tr><th>Day</th><th>Character</th><th class="num">Score</th><th>Strongest signals</th><th>Status</th></tr></thead>
				<tbody>
				<?php if (!$rows): ?>
					<tr><td colspan="5" class="chaos-muted">Nothing here.</td></tr>
				<?php endif; ?>
				<?php foreach ($rows as $r): ?>
					<?php
					$sig = chaos_botreview_parse_signals((string)$r['signals']);
					arsort($sig);
					$top = array();
					foreach (array_slice($sig, 0, 3, true) as $k => $v) {
						if ($v >= 0.3) { $top[] = $signalNames[$k][1] . ' ' . number_format($v, 2); }
					}
					?>
					<tr>
						<td><?= chaos_h($dayText($r['day'])) ?></td>
						<td><a href="<?= chaos_h($self . '&id=' . (int)$r['id']) ?>"><strong><?= chaos_h($r['player_name']) ?></strong></a></td>
						<td class="num chaos-gold"><?= (int)$r['score'] ?></td>
						<td class="chaos-muted" style="font-size:12px;"><?= chaos_h(implode(', ', $top)) ?></td>
						<td><?= chaos_h($statuses[$r['status']] ?? (string)$r['status']) ?><?php if ((string)$r['reviewed_by'] !== ''): ?> <span class="chaos-muted">(<?= chaos_h($r['reviewed_by']) ?>)</span><?php endif; ?></td>
					</tr>
				<?php endforeach; ?>
				</tbody>
			</table>
			<?php $pages = (int)ceil($total / 25); ?>
			<?php if ($pages > 1): ?>
				<p>
					<?php for ($i = 1; $i <= min($pages, 20); $i++): ?>
						<?php if ($i === $f['page']): ?><strong><?= $i ?></strong><?php else: ?><a href="<?= chaos_h($link(array('page' => $i))) ?>"><?= $i ?></a><?php endif; ?>
					<?php endfor; ?>
				</p>
			<?php endif; ?>
		<?php endif; ?>
	</div>
</div>
