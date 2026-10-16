<?php
/**
 * Web sessions end when the account's password changes (website/README.md "Passwords"). Loaded by plugin.php.
 *
 * ZnoteX ends other sessions only through its 2FA v2 "log out all devices", which this site does not use. So each
 * logged-in session keeps a mark of the account's stored password hash (salted, so every change gives a new one):
 * the first request of a session records it, every later request compares it. After a change (recovery link,
 * changepassword.php, or the game) every other session no longer matches and is logged out. changepassword.php ends
 * its own session itself.
 */

if (!function_exists('chaos_session_password_mark')) {

/** The mark of an account's stored password hash (never the hash itself in the session). */
function chaos_session_password_mark(int $accountId, string $passwordHash): string {
	return $accountId . ':' . hash('sha256', 'chaos-session-password|' . $accountId . '|' . $passwordHash);
}

/**
 * True when the session may stay logged in. A session without a mark for this account takes the current one (the
 * first request after login, or a session older than this check).
 */
function chaos_session_password_ok(array &$session, int $accountId, string $passwordHash): bool {
	$mark = chaos_session_password_mark($accountId, $passwordHash);
	$have = $session['chaos_pw'] ?? null;
	if (!is_string($have) || strpos($have, $accountId . ':') !== 0) {
		$session['chaos_pw'] = $mark;
		return true;
	}
	return hash_equals($have, $mark);
}

/** The stored password hash of an account, or null when the account is gone. */
function chaos_session_password_hash(int $accountId): ?string {
	$row = db()->fetchOne('SELECT `password` FROM `accounts` WHERE `id` = ? LIMIT 1;', [$accountId]);
	return is_array($row) ? (string)$row['password'] : null;
}

}

// ---------------------------------------------------------------- the check, on every request of a logged-in account
$chaosPwAccount = function_exists('getSession') ? (int)getSession('user_id') : 0;
if ($chaosPwAccount > 0 && PHP_SAPI !== 'cli' && session_status() === PHP_SESSION_ACTIVE) {
	$chaosPwHash = chaos_session_password_hash($chaosPwAccount);
	if ($chaosPwHash === null || !chaos_session_password_ok($_SESSION, $chaosPwAccount, $chaosPwHash)) {
		if (function_exists('znote_session_destroy')) {
			znote_session_destroy();
		} else {
			$_SESSION = array();
			session_destroy();
		}
		header('Location: login', true, 303);
		exit;
	}
	unset($chaosPwHash);
}
unset($chaosPwAccount);
