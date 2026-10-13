<?php
/**
 * Creator codes and the referral link (page.php?plugin=chaos&p=creator; creator_lib.php, website/README.md
 * "Creator codes").
 *
 *  - Everyone logged in: pick a creator to support (or stop), see the current pick and until when; the account's
 *    referral link. A pick changes nothing for the donor: the donation and its coins stay the same.
 *  - A creator: its code, %, supporters, earned and waiting coins, the last donations that carried the code (no names).
 *  - Administrators (admin panel account with a group 5+ character): create a code for a character's account, switch
 *    a code off / on, set its own %, read the log.
 * Writes: POST with the page's CSRF token.
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../creator_lib.php';
$GLOBALS['page_title'] = 'Creator Codes';

$self = 'page.php?plugin=chaos&p=creator';
$cfg = chaos_creator_config();
$accountId = function_exists('getSession') ? (int)getSession('user_id') : 0;
$isAdmin = $accountId > 0 && chaos_creator_is_admin($config, $accountId);
if (session_status() === PHP_SESSION_ACTIVE && empty($_SESSION['chaos_creator_csrf'])) {
	$_SESSION['chaos_creator_csrf'] = bin2hex(random_bytes(16));
}
$csrf = (string)($_SESSION['chaos_creator_csrf'] ?? '');

$message = '';
$messageOk = true;
if ($accountId > 0 && ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && isset($_POST['do'])) {
	if ($csrf === '' || !hash_equals($csrf, (string)($_POST['csrf'] ?? ''))) {
		[$messageOk, $message] = array(false, 'The form expired. Please try again.');
	} elseif ($_POST['do'] === 'support') {
		[$messageOk, $message] = chaos_creator_set_support($accountId, (string)($_POST['code'] ?? ''), (string)($_SERVER['REMOTE_ADDR'] ?? ''));
	} elseif ($_POST['do'] === 'clear') {
		[$messageOk, $message] = chaos_creator_set_support($accountId, '');
	} elseif ($isAdmin && $_POST['do'] === 'create') {
		require_once __DIR__ . '/../reports_lib.php';
		[$messageOk, $message] = chaos_creator_admin_create((string)($_POST['code'] ?? ''), (string)($_POST['character'] ?? ''),
			(string)($_POST['display'] ?? ''), (int)($_POST['pct'] ?? 0), (string)($_POST['note'] ?? ''), chaos_report_staff_name($accountId));
	} elseif ($isAdmin && in_array($_POST['do'], array('on', 'off', 'pct'), true)) {
		require_once __DIR__ . '/../reports_lib.php';
		[$messageOk, $message] = chaos_creator_admin_update((int)($_POST['id'] ?? 0), (string)$_POST['do'], (int)($_POST['pct'] ?? 0),
			chaos_report_staff_name($accountId));
	}
}
$pick = chaos_creator_support_of($accountId);
$mine = chaos_creator_codes_of($accountId);
$refLink = chaos_referral_link($accountId, (string)($config['site_url'] ?? ''));
$time = static function (int $t): string { return $t > 0 ? gmdate('Y-m-d', $t) : '-'; };
?>
<div class="chaos-page" id="chaos-creator">
	<div class="chaos-box">
		<h1 class="chaos-heading">Creator Codes</h1>
		<p class="chaos-lead">Support a streamer or content creator of Cinders of Chaos: pick their code and, for <?= (int)$cfg['supportDays'] ?> days, <?= (int)$cfg['sharePct'] ?>% of the Chaos Coins of each of your donations goes to them in game, as a thank-you from the server. It costs you nothing: your donation and your coins stay exactly the same. Donations are always voluntary.</p>
		<?php if ($message !== ''): ?>
			<p class="<?= $messageOk ? 'chaos-gold' : 'chaos-error' ?>" id="chaos-creator-message"><?= chaos_h($message) ?></p>
		<?php endif; ?>
		<?php if (!$cfg['enabled']): ?>
			<p class="chaos-muted">Creator codes are switched off.</p>
		<?php elseif ($accountId <= 0): ?>
			<p class="chaos-muted">Log in to pick a creator.</p>
		<?php else: ?>
			<h2>Support a creator</h2>
			<?php if ($pick): ?>
				<p id="chaos-creator-pick">You support <strong><?= chaos_h($pick['display_name'] !== '' ? $pick['display_name'] : $pick['code']) ?></strong> (code <?= chaos_h($pick['code']) ?>) until <?= chaos_h($time((int)$pick['expires_at'])) ?> (UTC).</p>
			<?php else: ?>
				<p class="chaos-muted">You support no creator right now.</p>
			<?php endif; ?>
			<form method="post" action="<?= chaos_h($self) ?>">
				<input type="hidden" name="csrf" value="<?= chaos_h($csrf) ?>">
				<label>Creator code <input type="text" name="code" maxlength="20" placeholder="CODE"></label>
				<button type="submit" name="do" value="support" class="chaos-button">Support</button>
				<?php if ($pick): ?><button type="submit" name="do" value="clear" class="chaos-button">Stop supporting</button><?php endif; ?>
			</form>
			<p class="chaos-muted" style="font-size:12px;">You cannot use your own code. A donation that is refunded or charged back gives the creator nothing.</p>

			<h2>Invite friends</h2>
			<?php if ($refLink !== ''): ?>
				<p>Your referral link: <code id="chaos-referral-link"><?= chaos_h($refLink) ?></code></p>
			<?php else: ?>
				<p class="chaos-muted">Reach level 20 with any character to get your referral link (Character &gt; Referral in game).</p>
			<?php endif; ?>
			<p class="chaos-muted" style="font-size:12px;">You earn titles when friends you invited reach level milestones, and more at 3, 5 and 10 friends. Accounts of the same person, connection or payment do not count.</p>
		<?php endif; ?>

		<?php foreach ($mine as $c): ?>
			<h2>Your code <?= chaos_h($c['code']) ?><?= (int)$c['active'] === 1 ? '' : ' (off)' ?></h2>
			<p>Share: <?= (int)$c['pct'] > 0 ? (int)$c['pct'] : (int)$cfg['sharePct'] ?>% of the coins of each supporter's donation, paid in game <?= (int)$cfg['holdDays'] ?> days after it (at most <?= (int)$cfg['orderCap'] ?> per donation and <?= (int)$cfg['monthlyCap'] ?> a month). Supporters now: <?= (int)$c['supporters'] ?>. Earned: <strong><?= (int)$c['earned'] ?></strong> Chaos Coins; waiting: <?= (int)$c['waiting'] ?>.</p>
			<table class="chaos-table chaos-creator-uses">
				<thead><tr><th>Date</th><th class="num">Coins</th><th class="num">Share</th><th>State</th></tr></thead>
				<tbody>
				<?php if (!$c['uses']): ?><tr><td colspan="4" class="chaos-muted">No donations with your code yet.</td></tr><?php endif; ?>
				<?php foreach ($c['uses'] as $u): ?>
					<tr><td><?= chaos_h($time((int)$u['created_at'])) ?></td><td class="num"><?= (int)$u['coins_base'] ?></td><td class="num"><?= (int)$u['share'] ?></td>
						<td><?= chaos_h($u['state'] . ($u['reason'] !== '' ? ' (' . $u['reason'] . ')' : '')) ?></td></tr>
				<?php endforeach; ?>
				</tbody>
			</table>
		<?php endforeach; ?>

		<?php if ($isAdmin): ?>
			<h2>Administration</h2>
			<form method="post" action="<?= chaos_h($self) ?>" id="chaos-creator-create">
				<input type="hidden" name="csrf" value="<?= chaos_h($csrf) ?>">
				<label>Code <input type="text" name="code" maxlength="16" required></label>
				<label>Character <input type="text" name="character" maxlength="29" required></label>
				<label>Shown name <input type="text" name="display" maxlength="64"></label>
				<label>Own % <input type="number" name="pct" min="0" max="50" value="0"></label>
				<label>Note <input type="text" name="note" maxlength="255"></label>
				<button type="submit" name="do" value="create" class="chaos-button">Create code</button>
			</form>
			<table class="chaos-table" id="chaos-creator-admin">
				<thead><tr><th>Code</th><th>Owner</th><th class="num">%</th><th class="num">Earned</th><th class="num">Void</th><th>Created</th><th></th></tr></thead>
				<tbody>
				<?php foreach (chaos_creator_admin_list() as $c): ?>
					<tr>
						<td><?= chaos_h($c['code']) ?><?= (int)$c['active'] === 1 ? '' : ' <span class="chaos-muted">(off)</span>' ?></td>
						<td><?= chaos_h((string)$c['owner']) ?><?= $c['display_name'] !== '' ? ' (' . chaos_h($c['display_name']) . ')' : '' ?></td>
						<td class="num"><?= (int)$c['pct'] > 0 ? (int)$c['pct'] : (int)$cfg['sharePct'] . '*' ?></td>
						<td class="num"><?= (int)$c['earned'] ?></td><td class="num"><?= (int)$c['voided'] ?></td>
						<td><?= chaos_h($time((int)$c['created_at']) . ' ' . $c['created_by']) ?></td>
						<td><form method="post" action="<?= chaos_h($self) ?>">
							<input type="hidden" name="csrf" value="<?= chaos_h($csrf) ?>"><input type="hidden" name="id" value="<?= (int)$c['id'] ?>">
							<button type="submit" name="do" value="<?= (int)$c['active'] === 1 ? 'off' : 'on' ?>" class="chaos-button"><?= (int)$c['active'] === 1 ? 'Switch off' : 'Switch on' ?></button>
							<input type="number" name="pct" min="0" max="50" value="<?= (int)$c['pct'] ?>" style="width:4em;">
							<button type="submit" name="do" value="pct" class="chaos-button">Set %</button>
						</form></td>
					</tr>
				<?php endforeach; ?>
				</tbody>
			</table>
			<details><summary>Log</summary>
				<table class="chaos-table"><tbody>
				<?php foreach (chaos_creator_admin_log() as $l): ?>
					<tr><td><?= chaos_h(gmdate('Y-m-d H:i', (int)$l['at'])) ?></td><td><?= chaos_h($l['action']) ?></td><td><?= (int)$l['order_id'] ?: '' ?></td><td class="chaos-muted"><?= chaos_h($l['detail']) ?></td></tr>
				<?php endforeach; ?>
				</tbody></table>
			</details>
		<?php endif; ?>
	</div>
</div>
