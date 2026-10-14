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
require_once __DIR__ . '/../i18n_lib.php';
$GLOBALS['page_title'] = chaos_t('Creator Codes');

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
		[$messageOk, $message] = array(false, chaos_t('The form expired. Please try again.'));
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
		<h1 class="chaos-heading"><?= chaos_h(chaos_t('Creator Codes')) ?></h1>
		<p class="chaos-muted chaos-lang-row"><?= chaos_lang_link($self) ?></p>
		<p class="chaos-lead"><?= chaos_h(chaos_t('Support a streamer or content creator of Cinders of Chaos: pick their code and, for %d days, %d%% of the Chaos Coins of each of your donations goes to them in game, as a thank-you from the server. It costs you nothing: your donation and your coins stay exactly the same. Donations are always voluntary.', (int)$cfg['supportDays'], (int)$cfg['sharePct'])) ?></p>
		<?php if ($message !== ''): ?>
			<p class="<?= $messageOk ? 'chaos-gold' : 'chaos-error' ?>" id="chaos-creator-message"><?= chaos_h(chaos_t($message)) ?></p>
		<?php endif; ?>
		<?php if (!$cfg['enabled']): ?>
			<p class="chaos-muted"><?= chaos_h(chaos_t('Creator codes are switched off.')) ?></p>
		<?php elseif ($accountId <= 0): ?>
			<p class="chaos-muted"><?= chaos_h(chaos_t('Log in to pick a creator.')) ?></p>
		<?php else: ?>
			<h2><?= chaos_h(chaos_t('Support a creator')) ?></h2>
			<?php if ($pick): ?>
				<p id="chaos-creator-pick"><?= chaos_h(chaos_t('You support')) ?> <strong><?= chaos_h($pick['display_name'] !== '' ? $pick['display_name'] : $pick['code']) ?></strong> <?= chaos_h(chaos_t('(code %s) until %s (UTC).', $pick['code'], $time((int)$pick['expires_at']))) ?></p>
			<?php else: ?>
				<p class="chaos-muted"><?= chaos_h(chaos_t('You support no creator right now.')) ?></p>
			<?php endif; ?>
			<form method="post" action="<?= chaos_h($self) ?>">
				<input type="hidden" name="csrf" value="<?= chaos_h($csrf) ?>">
				<label><?= chaos_h(chaos_t('Creator code')) ?> <input type="text" name="code" maxlength="20" placeholder="<?= chaos_h(chaos_t('CODE')) ?>"></label>
				<button type="submit" name="do" value="support" class="chaos-button"><?= chaos_h(chaos_t('Support')) ?></button>
				<?php if ($pick): ?><button type="submit" name="do" value="clear" class="chaos-button"><?= chaos_h(chaos_t('Stop supporting')) ?></button><?php endif; ?>
			</form>
			<p class="chaos-muted" style="font-size:12px;"><?= chaos_h(chaos_t('You cannot use your own code. A donation that is refunded or charged back gives the creator nothing.')) ?></p>

			<h2><?= chaos_h(chaos_t('Invite friends')) ?></h2>
			<?php if ($refLink !== ''): ?>
				<p><?= chaos_h(chaos_t('Your referral link:')) ?> <code id="chaos-referral-link"><?= chaos_h($refLink) ?></code></p>
			<?php else: ?>
				<p class="chaos-muted"><?= chaos_h(chaos_t('Reach level 20 with any character to get your referral link (Character > Referral in game).')) ?></p>
			<?php endif; ?>
			<p class="chaos-muted" style="font-size:12px;"><?= chaos_h(chaos_t('You earn titles when friends you invited reach level milestones, and more at 3, 5 and 10 friends. Accounts of the same person, connection or payment do not count.')) ?></p>
		<?php endif; ?>

		<?php foreach ($mine as $c): ?>
			<h2><?= chaos_h(chaos_t('Your code %s', $c['code'])) ?><?= (int)$c['active'] === 1 ? '' : chaos_h(chaos_t(' (off)')) ?></h2>
			<p><?= chaos_h(chaos_t("Share: %d%% of the coins of each supporter's donation, paid in game %d days after it (at most %d per donation and %d a month). Supporters now: %d.", (int)$c['pct'] > 0 ? (int)$c['pct'] : (int)$cfg['sharePct'], (int)$cfg['holdDays'], (int)$cfg['orderCap'], (int)$cfg['monthlyCap'], (int)$c['supporters'])) ?> <?= chaos_h(chaos_t('Earned:')) ?> <strong><?= (int)$c['earned'] ?></strong> <?= chaos_h(chaos_t('Chaos Coins; waiting: %d.', (int)$c['waiting'])) ?></p>
			<table class="chaos-table chaos-creator-uses">
				<thead><tr><th><?= chaos_h(chaos_t('Date')) ?></th><th class="num"><?= chaos_h(chaos_t('Coins')) ?></th><th class="num"><?= chaos_h(chaos_t('Share')) ?></th><th><?= chaos_h(chaos_t('State')) ?></th></tr></thead>
				<tbody>
				<?php if (!$c['uses']): ?><tr><td colspan="4" class="chaos-muted"><?= chaos_h(chaos_t('No donations with your code yet.')) ?></td></tr><?php endif; ?>
				<?php foreach ($c['uses'] as $u): ?>
					<tr><td><?= chaos_h($time((int)$u['created_at'])) ?></td><td class="num"><?= (int)$u['coins_base'] ?></td><td class="num"><?= (int)$u['share'] ?></td>
						<td><?= chaos_h(chaos_t($u['state']) . ($u['reason'] !== '' ? ' (' . chaos_t($u['reason']) . ')' : '')) ?></td></tr>
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
