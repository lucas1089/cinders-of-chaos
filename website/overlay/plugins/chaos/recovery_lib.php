<?php
/**
 * Account recovery by a one-time link (website/README.md "Mail"). Loaded by plugin.php; the page is
 * recovery_page.php, which ZnoteX's recovery.php hands over to (patches/znotex-chaos-recovery-mail.patch).
 *
 *  1. The player enters an account name or e-mail address. The answer is always the same, whether an account
 *     matches or not, so the form does not tell which names or addresses exist.
 *  2. A matching account with an e-mail address gets a link with a random token (32 bytes). Only its SHA-256 is
 *     stored (`chaos_password_resets`, one row per account: a new request replaces the older link).
 *  3. The link works once, for `reset_minutes` (30). Opening it shows a form; the token is used up only when a new
 *     password is posted (a mail scanner that opens the link changes nothing). The password is hashed as typed
 *     (user_change_password, salted PBKDF2), then a notice mail says the password was changed.
 *  Limits (`chaos_recovery_requests`): `per_ip_hour` requests per address (IPv6 by /64), `per_account_hour` mails
 *  per account; the second one is silent (same answer). reCAPTCHA when the site has it on. Links use the configured
 *  site address, never the request's Host header.
 */

if (!function_exists('chaos_recovery_settings')) {

function chaos_recovery_settings(): array {
	$own = (array)($GLOBALS['config']['chaos_mail'] ?? array());
	return array(
		'reset_minutes'    => max(5, min(240, (int)($own['reset_minutes'] ?? 30))),
		'per_ip_hour'      => max(1, (int)($own['per_ip_hour'] ?? 5)),
		'per_account_hour' => max(1, (int)($own['per_account_hour'] ?? 3)),
	);
}

/** The address an IP is counted under (IPv6 by /64, as the account creation limit). */
function chaos_recovery_ip_key(string $ip): string {
	if (function_exists('chaos_register_ip_key')) {
		return chaos_register_ip_key($ip);
	}
	return substr($ip, 0, 45);
}

function chaos_recovery_token_new(): string {
	return rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');
}

function chaos_recovery_token_valid_format(string $token): bool {
	return preg_match('/^[A-Za-z0-9_-]{43}$/', $token) === 1;
}

function chaos_recovery_hash(string $token): string {
	return hash('sha256', $token);
}

/** The link in the mail: the configured site address, never the request's Host header. */
function chaos_recovery_link(string $token): string {
	$base = rtrim((string)($GLOBALS['config']['site_url'] ?? ''), '/');
	return $base . '/recovery.php?reset=' . rawurlencode($token);
}

/** The accounts an entry names: an e-mail address (at most 3 accounts) or an account name. */
function chaos_recovery_find_accounts(string $who): array {
	if (strpos($who, '@') !== false) {
		$rows = db()->fetchAll('SELECT `id`, `name`, `email` FROM `accounts` WHERE `email` = ? ORDER BY `id` LIMIT 3;', [$who]);
	} else {
		$rows = db()->fetchAll('SELECT `id`, `name`, `email` FROM `accounts` WHERE `name` = ? LIMIT 1;', [$who]);
	}
	$out = array();
	foreach (is_array($rows) ? $rows : array() as $row) {
		if (filter_var((string)$row['email'], FILTER_VALIDATE_EMAIL) !== false) {
			$out[] = $row;
		}
	}
	return $out;
}

/** Requests from an address since then (rows with account 0: one per request). */
function chaos_recovery_count_ip(string $ipKey, int $since): int {
	$row = db()->fetchOne('SELECT COUNT(*) AS `n` FROM `chaos_recovery_requests` WHERE `ip` = ? AND `account_id` = 0 AND `created` >= ?;', [$ipKey, $since]);
	return is_array($row) ? (int)$row['n'] : 0;
}

/** Links mailed to an account since then. */
function chaos_recovery_count_account(int $accountId, int $since): int {
	$row = db()->fetchOne('SELECT COUNT(*) AS `n` FROM `chaos_recovery_requests` WHERE `account_id` = ? AND `created` >= ?;', [$accountId, $since]);
	return is_array($row) ? (int)$row['n'] : 0;
}

/** The mail with the link. */
function chaos_recovery_mail_link(array $account, string $link, int $minutes): array {
	$site = chaos_mail_site_name();
	$name = (string)$account['name'];
	$text = "Hello,\n\n"
		. "someone asked to reset the password of the account \"$name\" on $site.\n\n"
		. "To choose a new password, open this link within $minutes minutes. It works once:\n$link\n\n"
		. "If it was not you, ignore this e-mail. Your password stays as it is.\n\n"
		. "$site\n(This is an automatic e-mail. Replies are not read.)";
	$html = '<p>Hello,</p>'
		. '<p>someone asked to reset the password of the account <b>' . chaos_h($name) . '</b> on ' . chaos_h($site) . '.</p>'
		. '<p>To choose a new password, open this link within ' . $minutes . ' minutes. It works once:<br>'
		. '<a href="' . chaos_h($link) . '">' . chaos_h($link) . '</a></p>'
		. '<p>If it was not you, ignore this e-mail. Your password stays as it is.</p>'
		. '<p>' . chaos_h($site) . '<br><small>This is an automatic e-mail. Replies are not read.</small></p>';
	return array('to' => (string)$account['email'], 'to_name' => $name, 'subject' => $site . ': reset your password',
		'text' => $text, 'html' => $html);
}

/** The notice after a reset. */
function chaos_recovery_mail_changed(array $account): array {
	$site = chaos_mail_site_name();
	$name = (string)$account['name'];
	$text = "Hello,\n\nthe password of the account \"$name\" on $site was changed with a recovery link.\n\n"
		. "If it was not you, reset it again at once and tell the staff.\n\n"
		. "$site\n(This is an automatic e-mail. Replies are not read.)";
	$html = '<p>Hello,</p><p>the password of the account <b>' . chaos_h($name) . '</b> on ' . chaos_h($site)
		. ' was changed with a recovery link.</p><p>If it was not you, reset it again at once and tell the staff.</p>'
		. '<p>' . chaos_h($site) . '<br><small>This is an automatic e-mail. Replies are not read.</small></p>';
	return array('to' => (string)$account['email'], 'to_name' => $name, 'subject' => $site . ': your password was changed',
		'text' => $text, 'html' => $html);
}

/**
 * A recovery request. Returns array('answer' => 'sent' | 'limited' | 'empty', 'mails' => list of messages to send).
 * 'sent' is the answer for every entry, matching or not.
 */
function chaos_recovery_request(string $who, string $ip, int $now): array {
	$who = trim($who);
	if ($who === '' || strlen($who) > 255) {
		return array('answer' => 'empty', 'mails' => array());
	}
	$cfg = chaos_recovery_settings();
	$ipKey = chaos_recovery_ip_key($ip);
	db()->execute('DELETE FROM `chaos_recovery_requests` WHERE `created` < ?;', [$now - 86400]);
	db()->execute('DELETE FROM `chaos_password_resets` WHERE `expires` < ?;', [$now]);
	if (chaos_recovery_count_ip($ipKey, $now - 3600) >= $cfg['per_ip_hour']) {
		return array('answer' => 'limited', 'mails' => array());
	}
	db()->execute('INSERT INTO `chaos_recovery_requests` (`ip`, `account_id`, `created`) VALUES (?, 0, ?);', [$ipKey, $now]);
	$mails = array();
	foreach (chaos_recovery_find_accounts($who) as $account) {
		$id = (int)$account['id'];
		if (chaos_recovery_count_account($id, $now - 3600) >= $cfg['per_account_hour']) {
			continue; // silent: the same answer as any other entry
		}
		$token = chaos_recovery_token_new();
		db()->execute('DELETE FROM `chaos_password_resets` WHERE `account_id` = ?;', [$id]);
		db()->execute('INSERT INTO `chaos_password_resets` (`account_id`, `token_hash`, `created`, `expires`) VALUES (?, ?, ?, ?);',
			[$id, chaos_recovery_hash($token), $now, $now + $cfg['reset_minutes'] * 60]);
		db()->execute('INSERT INTO `chaos_recovery_requests` (`ip`, `account_id`, `created`) VALUES (?, ?, ?);', [$ipKey, $id, $now]);
		$mails[] = chaos_recovery_mail_link($account, chaos_recovery_link($token), $cfg['reset_minutes']);
	}
	return array('answer' => 'sent', 'mails' => $mails);
}

/** The account of a valid, unexpired token, or null. */
function chaos_recovery_check(string $token, int $now): ?array {
	if (!chaos_recovery_token_valid_format($token)) {
		return null;
	}
	$row = db()->fetchOne('SELECT `a`.`id`, `a`.`name`, `a`.`email` FROM `chaos_password_resets` `r`
		INNER JOIN `accounts` `a` ON `a`.`id` = `r`.`account_id` WHERE `r`.`token_hash` = ? AND `r`.`expires` >= ? LIMIT 1;',
		[chaos_recovery_hash($token), $now]);
	return is_array($row) ? $row : null;
}

/**
 * Uses the token up: one conditional UPDATE swaps its hash for a random marker, so of two posts at the same time only
 * one finds its marker afterwards. Returns the account, or null when the token is not (or no longer) valid.
 */
function chaos_recovery_consume(string $token, int $now): ?array {
	$account = chaos_recovery_check($token, $now);
	if ($account === null) {
		return null;
	}
	$marker = hash('sha256', 'used:' . random_bytes(32));
	db()->execute('UPDATE `chaos_password_resets` SET `token_hash` = ?, `expires` = 0 WHERE `account_id` = ? AND `token_hash` = ? AND `expires` >= ?;',
		[$marker, (int)$account['id'], chaos_recovery_hash($token), $now]);
	$won = db()->fetchOne('SELECT `account_id` FROM `chaos_password_resets` WHERE `token_hash` = ? LIMIT 1;', [$marker]);
	db()->execute('DELETE FROM `chaos_password_resets` WHERE `token_hash` = ?;', [$marker]);
	return is_array($won) ? $account : null;
}

/** '' when the new password is fine, else the message. Same length rules as account creation (6 to 29). */
function chaos_recovery_password_error(string $password, string $again): string {
	if ($password !== $again) {
		return 'The two passwords are not the same.';
	}
	if (strlen($password) < 6 || strlen($password) > 29) {
		return 'The password must have 6 to 29 characters.';
	}
	return '';
}

/** The page's texts. */
function chaos_recovery_texts(): array {
	$cfg = chaos_recovery_settings();
	return array(
		'off'     => 'Account recovery by e-mail is not available on this server yet. Please ask the staff for help.',
		'sent'    => 'If an account matches what you entered, we sent an e-mail to its address with a link to choose a new '
			. 'password. The link works once, for ' . $cfg['reset_minutes'] . ' minutes. Please check your spam folder too.',
		'limited' => 'Too many recovery requests came from your address. Please try again in an hour.',
		'empty'   => 'Please enter your account name or e-mail address.',
		'captcha' => 'The captcha was not solved. Please try again.',
		'bad'     => 'This link is not valid or has expired. You can ask for a new one below.',
		'done'    => 'Your password was changed. You can log in with it now, on the website and in the game.',
	);
}

/** reCAPTCHA widget and Google's script, when the site has reCAPTCHA on. */
function chaos_recovery_captcha_html(): string {
	if (empty($GLOBALS['config']['use_captcha'])) {
		return '';
	}
	return '<div class="g-recaptcha" data-sitekey="' . chaos_h((string)($GLOBALS['config']['captcha_site_key'] ?? '')) . '"></div>'
		. '<script src="https://www.google.com/recaptcha/api.js" async defer></script>';
}

function chaos_recovery_request_form(string $message = ''): string {
	return '<h1>Lost account</h1>'
		. ($message !== '' ? '<p class="chaos-note">' . chaos_h($message) . '</p>' : '')
		. '<p>Enter your account name or the e-mail address of your account. We will send a link to that address to '
		. 'choose a new password. The e-mail also tells you your account name.</p>'
		. '<form action="recovery.php" method="post" class="lostaccount-form">'
		. '<label for="chaos-who">Account name or e-mail address</label><br>'
		. '<input type="text" id="chaos-who" name="who" maxlength="255" autocomplete="username" required><br>'
		. chaos_recovery_captcha_html()
		. '<input type="submit" value="Send me a link">'
		. '</form>';
}

function chaos_recovery_reset_form(string $token, array $account, string $error = ''): string {
	return '<h1>Choose a new password</h1>'
		. ($error !== '' ? '<p class="chaos-error">' . chaos_h($error) . '</p>' : '')
		. '<p>Account: <b>' . chaos_h((string)$account['name']) . '</b></p>'
		. '<form action="recovery.php" method="post">'
		. '<input type="hidden" name="reset" value="' . chaos_h($token) . '">'
		. '<label for="chaos-pw1">New password</label><br>'
		. '<input type="password" id="chaos-pw1" name="password" maxlength="29" autocomplete="new-password" required><br>'
		. '<label for="chaos-pw2">New password again</label><br>'
		. '<input type="password" id="chaos-pw2" name="password_again" maxlength="29" autocomplete="new-password" required><br>'
		. '<input type="submit" value="Change the password">'
		. '</form>';
}

/**
 * The whole page for one request. Returns array('html' => page body, 'mails' => messages to send after the
 * answer went out). $captchaOk: callable(string response): bool (ZnoteX's verifyGoogleReCaptcha);
 * $setPassword: callable(int accountId, string password): void (ZnoteX's user_change_password).
 */
function chaos_recovery_handle(string $method, array $get, array $post, string $ip, int $now, callable $captchaOk, callable $setPassword): array {
	$t = chaos_recovery_texts();
	if (!chaos_mail_enabled()) {
		return array('html' => '<h1>Lost account</h1><p>' . chaos_h($t['off']) . '</p>', 'mails' => array());
	}
	$isPost = strtoupper($method) === 'POST';
	$raw = $isPost ? ($post['reset'] ?? '') : ($get['reset'] ?? '');
	$token = is_string($raw) ? $raw : '';

	// the link: the form, then the new password
	if ($token !== '') {
		if (!$isPost) {
			$account = chaos_recovery_check($token, $now);
			return array('html' => $account === null ? chaos_recovery_request_form($t['bad']) : chaos_recovery_reset_form($token, $account), 'mails' => array());
		}
		$password = is_string($post['password'] ?? null) ? $post['password'] : '';
		$again = is_string($post['password_again'] ?? null) ? $post['password_again'] : '';
		$account = chaos_recovery_check($token, $now);
		if ($account === null) {
			return array('html' => chaos_recovery_request_form($t['bad']), 'mails' => array());
		}
		$error = chaos_recovery_password_error($password, $again);
		if ($error !== '') {
			return array('html' => chaos_recovery_reset_form($token, $account, $error), 'mails' => array());
		}
		$account = chaos_recovery_consume($token, $now);
		if ($account === null) {
			return array('html' => chaos_recovery_request_form($t['bad']), 'mails' => array());
		}
		$setPassword((int)$account['id'], $password);
		return array('html' => '<h1>Password changed</h1><p>' . chaos_h($t['done']) . '</p><p><a href="login.php">Log in</a></p>',
			'mails' => array(chaos_recovery_mail_changed($account)));
	}

	// the request
	if ($isPost) {
		if (!empty($GLOBALS['config']['use_captcha'])) {
			$response = $post['g-recaptcha-response'] ?? '';
			if (!is_string($response) || $response === '' || !$captchaOk($response)) {
				return array('html' => chaos_recovery_request_form($t['captcha']), 'mails' => array());
			}
		}
		$who = is_string($post['who'] ?? null) ? $post['who'] : '';
		$result = chaos_recovery_request($who, $ip, $now);
		if ($result['answer'] === 'sent') {
			return array('html' => '<h1>Check your e-mail</h1><p>' . chaos_h($t['sent']) . '</p>', 'mails' => $result['mails']);
		}
		return array('html' => chaos_recovery_request_form($t[$result['answer']]), 'mails' => array());
	}
	return array('html' => chaos_recovery_request_form(), 'mails' => array());
}

/** Sends the queued mails; failures are logged by the sender and never shown (the answer is already out). */
function chaos_recovery_send(array $mails): int {
	$sent = 0;
	foreach ($mails as $m) {
		if (chaos_mail_send((string)$m['to'], (string)$m['to_name'], (string)$m['subject'], (string)$m['text'], (string)$m['html'])) {
			$sent++;
		}
	}
	return $sent;
}

}
