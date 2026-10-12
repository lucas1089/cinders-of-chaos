<?php
/**
 * recovery.php of the site (website/README.md "Mail"): ZnoteX's recovery.php includes this file right after
 * engine/init.php (patches/znotex-chaos-recovery-mail.patch), so none of the stock recovery modes runs.
 * The logic is chaos_recovery_handle() in recovery_lib.php; this file only glues it to ZnoteX.
 */
if (!function_exists('chaos_recovery_handle') || !function_exists('theme_open')) {
	http_response_code(404);
	exit;
}

header('Cache-Control: no-store');
header('Referrer-Policy: no-referrer'); // the link's token never leaves in a Referer header
znote_csrf_protect_public_post();
logged_in_redirect();

$chaosRecovery = chaos_recovery_handle(
	(string)($_SERVER['REQUEST_METHOD'] ?? 'GET'),
	$_GET,
	$_POST,
	(string)($_SERVER['REMOTE_ADDR'] ?? ''),
	time(),
	static function (string $response): bool {
		return function_exists('verifyGoogleReCaptcha') && verifyGoogleReCaptcha($response);
	},
	static function (int $accountId, string $password): void {
		user_change_password($accountId, $password); // salted PBKDF2, hashed as typed (patches/znotex-chaos-passwords.patch)
	}
);

theme_open();
echo '<div class="chaos-recovery">' . $chaosRecovery['html'] . '</div>';
theme_close();

// The answer goes out first, then the mails: a request that matches an account takes no longer to answer than one
// that does not (PHP-FPM). Without PHP-FPM the mail is sent before the connection closes.
if ($chaosRecovery['mails']) {
	while (ob_get_level() > 0) {
		ob_end_flush();
	}
	if (function_exists('fastcgi_finish_request')) {
		fastcgi_finish_request();
	} else {
		flush();
	}
	ignore_user_abort(true);
	chaos_recovery_send($chaosRecovery['mails']);
}
exit;
