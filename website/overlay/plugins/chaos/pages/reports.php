<?php
/**
 * Staff: player reports and the anti-bot log (page?plugin=chaos&p=reports). Only the admin accounts of ZnoteX's
 * admin panel ($config['page_admin_access']); everyone else gets "not found". Nothing here bans: staff read, decide
 * in the game, then close the report with a note.
 *
 *  - GET status / reason / name / page: the filtered list, newest first; each report with its note, position,
 *    suspicion score and the target's last lines in public channels (never private messages).
 *  - POST rid + do (close | note | reopen) + note + CSRF token: the staff action, then back to the list.
 *  - GET log=1 [&name=]: the anti-bot log (scores, presence checks).
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../reports_lib.php';

$accountId = function_exists('getSession') ? (int)getSession('user_id') : 0;
if (!chaos_reports_is_admin($config, $accountId)) {
	http_response_code(404);
	$GLOBALS['page_title'] = 'Not found';
	echo '<div class="chaos-page"><div class="chaos-box"><h1 class="chaos-heading">Not found</h1><p>This page does not exist.</p></div></div>';
	return;
}
$GLOBALS['page_title'] = 'Player Reports';
$self = 'page?plugin=chaos&p=reports';

if (session_status() === PHP_SESSION_ACTIVE && empty($_SESSION['chaos_reports_csrf'])) {
	$_SESSION['chaos_reports_csrf'] = bin2hex(random_bytes(16));
}
$csrf = (string)($_SESSION['chaos_reports_csrf'] ?? '');

$message = '';
$messageOk = true;
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && isset($_POST['rid'])) {
	if ($csrf === '' || !hash_equals($csrf, (string)($_POST['csrf'] ?? ''))) {
		$message = 'The form expired. Please try again.';
		$messageOk = false;
	} else {
		[$messageOk, $message] = chaos_report_action((string)($_POST['do'] ?? ''), (int)$_POST['rid'],
			(string)($_POST['note'] ?? ''), chaos_report_staff_name($accountId));
	}
}

$f = chaos_report_filters($_GET);
$showLog = !empty($_GET['log']);
$reasons = chaos_report_reasons();
$perPage = 25;
[$rows, $total] = $showLog ? array(array(), 0) : chaos_report_list($f, $perPage);
$logRows = $showLog ? chaos_antibot_log_rows($f['name'], 50) : array();
$link = static function (array $over) use ($self, $f): string {
	$q = array_merge(array('status' => $f['status'], 'reason' => $f['reason'], 'name' => $f['name']), $over);
	$q = array_filter($q, static function ($v) { return $v !== '' && $v !== null; });
	return $self . ($q ? '&' . http_build_query($q) : '');
};
$time = static function (int $t): string { return $t > 0 ? gmdate('Y-m-d H:i', $t) : '-'; };
?>
<div class="chaos-page" id="chaos-reports">
	<div class="chaos-box">
		<h1 class="chaos-heading">Player Reports</h1>
		<p class="chaos-lead">Reports from the game (Report Player) and the anti-bot log. Nothing here bans anyone: check in the game, decide, then close the report with a note. Times are UTC.</p>

		<nav class="chaos-tabs" aria-label="Views">
			<a class="chaos-tab<?= !$showLog && $f['status'] === 'open' ? ' is-active' : '' ?>" href="<?= chaos_h($link(array('status' => 'open', 'log' => null))) ?>">Open</a>
			<a class="chaos-tab<?= !$showLog && $f['status'] === 'closed' ? ' is-active' : '' ?>" href="<?= chaos_h($link(array('status' => 'closed'))) ?>">Closed</a>
			<a class="chaos-tab<?= !$showLog && $f['status'] === 'all' ? ' is-active' : '' ?>" href="<?= chaos_h($link(array('status' => 'all'))) ?>">All</a>
			<a class="chaos-tab<?= $showLog ? ' is-active' : '' ?>" href="<?= chaos_h($self . '&log=1') ?>">Anti-bot log</a>
		</nav>

		<?php if ($message !== ''): ?>
			<p class="<?= $messageOk ? 'chaos-gold' : 'chaos-error' ?>" id="chaos-reports-message"<?= $messageOk ? '' : ' style="color:#e07060;"' ?>><?= chaos_h($message) ?></p>
		<?php endif; ?>

		<form method="get" action="page" class="chaos-filter" style="margin:10px 0;">
			<input type="hidden" name="plugin" value="chaos">
			<input type="hidden" name="p" value="reports">
			<?php if ($showLog): ?><input type="hidden" name="log" value="1"><?php else: ?>
			<input type="hidden" name="status" value="<?= chaos_h($f['status']) ?>">
			<label>Reason
				<select name="reason">
					<option value="">any</option>
					<?php foreach ($reasons as $key => $label): ?>
						<option value="<?= chaos_h($key) ?>"<?= $f['reason'] === $key ? ' selected' : '' ?>><?= chaos_h($label) ?></option>
					<?php endforeach; ?>
				</select>
			</label>
			<?php endif; ?>
			<label>Name <input type="text" name="name" maxlength="29" value="<?= chaos_h($f['name']) ?>" placeholder="character"></label>
			<button type="submit" class="chaos-button">Filter</button>
		</form>

		<?php if ($showLog): ?>
			<table class="chaos-table" id="chaos-antibot-log">
				<thead><tr><th>Time</th><th>Character</th><th>Entry</th><th class="num">Score</th><th>Detail</th></tr></thead>
				<tbody>
				<?php if (!$logRows): ?>
					<tr><td colspan="5" class="chaos-muted">No entries.</td></tr>
				<?php endif; ?>
				<?php foreach ($logRows as $r): ?>
					<tr>
						<td><?= chaos_h($time((int)$r['created_at'])) ?></td>
						<td><a href="<?= chaos_h($self . '&log=1&name=' . rawurlencode((string)$r['player_name'])) ?>"><?= chaos_h($r['player_name']) ?></a></td>
						<td><?= chaos_h(str_replace('_', ' ', (string)$r['kind'])) ?></td>
						<td class="num"><?= (int)$r['score'] ?></td>
						<td class="chaos-muted" style="font-size:12px;"><?= chaos_h($r['detail']) ?></td>
					</tr>
				<?php endforeach; ?>
				</tbody>
			</table>
		<?php else: ?>
			<p class="chaos-muted"><?= (int)$total ?> report(s).</p>
			<table class="chaos-table" id="chaos-reports-list">
				<thead><tr><th>#</th><th>Time</th><th>Reported</th><th>By</th><th>Reason</th><th class="num">Suspicion</th><th>Status</th></tr></thead>
				<tbody>
				<?php if (!$rows): ?>
					<tr><td colspan="7" class="chaos-muted">No reports.</td></tr>
				<?php endif; ?>
				<?php foreach ($rows as $r): ?>
					<tr>
						<td><?= (int)$r['id'] ?></td>
						<td><?= chaos_h($time((int)$r['created_at'])) ?></td>
						<td><strong><?= chaos_h($r['target_name']) ?></strong></td>
						<td><?= chaos_h($r['reporter_name']) ?></td>
						<td><?= chaos_h($reasons[$r['reason']] ?? $r['reason']) ?></td>
						<td class="num<?= (int)$r['suspicion'] >= 60 ? ' chaos-gold' : '' ?>"><?= (int)$r['suspicion'] ?></td>
						<td><?= $r['status'] === 'closed' ? 'closed' : '<span class="chaos-gold">open</span>' ?></td>
					</tr>
					<tr class="chaos-report-detail">
						<td></td>
						<td colspan="6" style="font-size:13px;">
							<div><span class="chaos-muted">Note:</span> <?= $r['note'] !== '' ? chaos_h($r['note']) : '<span class="chaos-muted">-</span>' ?></div>
							<div class="chaos-muted">Position <?= (int)$r['pos_x'] ?>, <?= (int)$r['pos_y'] ?>, <?= (int)$r['pos_z'] ?> (<?= $r['reason'] === 'bug' ? 'bug report' : ((int)$r['target_online'] === 1 ? 'reported player' : 'reporter; the player was offline') ?>)</div>
							<?php if ((string)$r['chat'] !== ''): ?>
								<details><summary><?= $r['reason'] === 'bug' ? 'Details' : 'Public chat of ' . chaos_h($r['target_name']) ?></summary>
									<pre style="white-space:pre-wrap;margin:4px 0;"><?= chaos_h($r['chat']) ?></pre>
								</details>
							<?php endif; ?>
							<?php if ($r['status'] === 'closed'): ?>
								<div class="chaos-muted">Closed <?= chaos_h($time((int)$r['closed_at'])) ?> by <?= chaos_h($r['closed_by']) ?></div>
							<?php endif; ?>
							<form method="post" action="<?= chaos_h($link(array('page' => $f['page'] > 1 ? $f['page'] : null))) ?>" style="margin-top:6px;">
								<input type="hidden" name="csrf" value="<?= chaos_h($csrf) ?>">
								<input type="hidden" name="rid" value="<?= (int)$r['id'] ?>">
								<input type="text" name="note" maxlength="255" size="48" value="<?= chaos_h($r['staff_note']) ?>" placeholder="staff note">
								<?php if ($r['status'] === 'closed'): ?>
									<button type="submit" name="do" value="note" class="chaos-button">Save note</button>
									<button type="submit" name="do" value="reopen" class="chaos-button">Reopen</button>
								<?php else: ?>
									<button type="submit" name="do" value="close" class="chaos-button">Close</button>
									<button type="submit" name="do" value="note" class="chaos-button">Save note</button>
								<?php endif; ?>
								<a href="<?= chaos_h($self . '&log=1&name=' . rawurlencode((string)$r['target_name'])) ?>">anti-bot log</a>
							</form>
						</td>
					</tr>
				<?php endforeach; ?>
				</tbody>
			</table>
			<?php $pages = (int)ceil($total / $perPage); ?>
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
