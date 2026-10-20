<?php
/**
 * Delete one of your characters: page?plugin=chaos&p=deletecharacter (delete_lib.php has the rules; plugin.php sends
 * ZnoteX's own deletion addresses here). Needs the form's CSRF token, the account password and the name typed again.
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once dirname(__DIR__) . '/delete_lib.php';

$GLOBALS['page_title'] = 'Delete Character';
$accountId = function_exists('getSession') ? (int)getSession('user_id') : 0;

if (session_status() === PHP_SESSION_ACTIVE && empty($_SESSION['chaos_delete_csrf'])) {
	$_SESSION['chaos_delete_csrf'] = bin2hex(random_bytes(16));
}
$csrf = (string)($_SESSION['chaos_delete_csrf'] ?? '');

$message = '';
$deleted = false;
if ($accountId > 0 && ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
	$session = session_status() === PHP_SESSION_ACTIVE ? $_SESSION : array();
	[$deleted, $message, $fails] = chaos_delete_character($accountId, $_POST, $csrf, $session, time());
	if (session_status() === PHP_SESSION_ACTIVE) {
		$_SESSION['chaos_delete_fails'] = $fails;
		if ($deleted) {
			$_SESSION['chaos_delete_csrf'] = bin2hex(random_bytes(16)); // one deletion per token
			$csrf = $_SESSION['chaos_delete_csrf'];
		}
	}
}
$characters = $accountId > 0 ? chaos_delete_characters($accountId) : array();
?>
<div class="chaos-page">
	<div class="chaos-box" id="chaos-delete-character">
		<h1 class="chaos-heading">Delete Character</h1>
		<?php if ($accountId <= 0): ?>
			<p>Please <a href="login">log in</a> first.</p>
		<?php else: ?>
			<p class="chaos-lead">Deleting a character removes it for good: its items, depot, progress and bank are gone, and the
				name becomes free. This cannot be undone. Staff cannot restore it.</p>
			<?php if ($message !== ''): ?>
				<p id="chaos-delete-message" class="<?= $deleted ? 'chaos-ok' : 'chaos-error' ?>"<?= $deleted ? '' : ' style="color:#e07060;"' ?>><?= chaos_h($message) ?></p>
			<?php endif; ?>
			<?php if (!$characters): ?>
				<p>This account has no characters.</p>
			<?php endif; ?>
			<?php foreach ($characters as $c): $why = chaos_delete_blockers($c); ?>
				<form method="post" action="page?plugin=chaos&amp;p=deletecharacter" class="chaos-delete-row" style="margin:12px 0;">
					<input type="hidden" name="csrf" value="<?= chaos_h($csrf) ?>">
					<input type="hidden" name="player" value="<?= (int)$c['id'] ?>">
					<strong><?= chaos_h($c['name']) ?></strong> (level <?= (int)$c['level'] ?>)
					<?php if ($why): ?>
						<span class="chaos-muted"> - cannot be deleted now: <?= chaos_h($why[0]) ?></span>
					<?php else: ?>
						<br>
						<input type="text" name="name" placeholder="Type the name to confirm" autocomplete="off" maxlength="40">
						<input type="password" name="password" placeholder="Account password" autocomplete="current-password" maxlength="200">
						<input type="submit" class="chaos-btn" value="Delete">
					<?php endif; ?>
				</form>
			<?php endforeach; ?>
			<p><a class="chaos-tab" href="myaccount">Back to the account</a></p>
		<?php endif; ?>
	</div>
</div>
