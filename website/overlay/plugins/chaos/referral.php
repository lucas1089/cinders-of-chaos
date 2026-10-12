<?php
/**
 * Referral program on the website: the optional "Referral code" field of the account creation form
 * (layouts/chaos/views/register_form.php). Loaded by plugin.php on every request; the hooks are registered here.
 *
 * The site only checks the code's format and that an account owns it, and records a `pending` row in
 * `chaos_referrals` with the registration IP. Every other rule (one referrer, staff, same IP, same e-mail domain,
 * monthly caps, bans) is the game server's: referral.lua checks the row at the new account's first login and accepts
 * or rejects it (server/README.md "Referral program"). Settings: the server's referral_config.lua (`enabled`,
 * `code`), read through CHAOS_SERVER_DATA; without it the defaults below.
 *
 * An invalid code stops the registration with a message: the check runs when the plugin loads, and the layout's
 * register_header view (rendered by register.php after its own checks, before the account is created) adds the message
 * to register.php's $errors through chaos_referral_add_error(); with an error register.php creates nothing.
 */

if (!function_exists('chaos_referral_settings')) {

/** {enabled, length, alphabet, entryDays} from referral_config.lua, else the defaults. */
function chaos_referral_settings(): array {
	$out = array('enabled' => true, 'length' => 8, 'alphabet' => 'ABCDEFGHJKMNPQRSTUVWXYZ23456789', 'entryDays' => 7);
	$text = function_exists('chaos_read_server_file') ? chaos_read_server_file('scripts/chaos/referral_config.lua') : '';
	if ($text === '') {
		return $out;
	}
	if (preg_match('/^\s*enabled\s*=\s*(true|false)/m', $text, $m)) {
		$out['enabled'] = $m[1] === 'true';
	}
	if (preg_match('/^\s*entryDays\s*=\s*(\d+)/m', $text, $m)) {
		$out['entryDays'] = (int)$m[1];
	}
	$code = chaos_lua_block($text, 'code');
	if ($code !== '') {
		$len = chaos_lua_field($code, 'length');
		$abc = chaos_lua_field($code, 'alphabet');
		if (is_int($len) && $len >= 4 && $len <= 16) {
			$out['length'] = $len;
		}
		if (is_string($abc) && preg_match('/^[A-Z0-9]{10,}$/', $abc)) {
			$out['alphabet'] = $abc;
		}
	}
	return $out;
}

/** Pure: "abcd-2345" -> "ABCD2345", or null when it is not a code of this format (referral_core.lua normalize). */
function chaos_referral_normalize(string $text, array $settings): ?string {
	if (strlen($text) > 40) {
		return null;
	}
	$code = strtoupper(preg_replace('/[\s\-]+/', '', $text));
	if (strlen($code) !== (int)$settings['length']) {
		return null;
	}
	for ($i = 0; $i < strlen($code); $i++) {
		if (strpos($settings['alphabet'], $code[$i]) === false) {
			return null;
		}
	}
	return $code;
}

/** The account that owns this code, or 0. */
function chaos_referral_owner(string $code): int {
	if (!chaos_table_exists('chaos_referral_codes')) {
		return 0;
	}
	$row = db()->fetchOne('SELECT `account_id` FROM `chaos_referral_codes` WHERE `code` = ? LIMIT 1;', [$code]);
	return is_array($row) ? (int)$row['account_id'] : 0;
}

/**
 * Pure check of the posted field: array(error text or '', normalized code or null, referrer account id).
 * An empty field is fine (no referral). $owner is a callable code -> account id.
 */
function chaos_referral_check(string $posted, array $settings, callable $owner): array {
	$posted = trim($posted);
	if ($posted === '' || !$settings['enabled']) {
		return array('', null, 0);
	}
	$code = chaos_referral_normalize($posted, $settings);
	if ($code === null) {
		return array('That is not a referral code. Leave the field empty if you have none.', null, 0);
	}
	$referrer = (int)$owner($code);
	if ($referrer <= 0) {
		return array('No account has this referral code. Check it with your friend, or leave the field empty.', null, 0);
	}
	return array('', $code, $referrer);
}

/** The value for the form field: null when the program is off (no field), else the posted value or ?ref=. */
function chaos_referral_form_value(): ?string {
	$settings = chaos_referral_settings();
	if (!$settings['enabled']) {
		return null;
	}
	$value = (string)($_POST['referral_code'] ?? ($_GET['ref'] ?? ''));
	return substr(preg_replace('/[^A-Za-z0-9\- ]/', '', $value), 0, 12);
}

/** Writes the pending link of a new account (once; an existing row is kept). */
function chaos_referral_record(int $accountId, int $referrerId, string $code, string $ip): bool {
	if ($accountId <= 0 || $referrerId <= 0 || $accountId === $referrerId || !chaos_table_exists('chaos_referrals')) {
		return false;
	}
	db()->execute("INSERT IGNORE INTO `chaos_referrals` (`referred_account_id`, `referrer_account_id`, `code`, `source`, `status`, `reg_ip`, `created_at`) " .
		"VALUES (?, ?, ?, 'web', 'pending', ?, ?);", [$accountId, $referrerId, $code, substr($ip, 0, 45), time()]);
	return true;
}

/** Called by the register_header view: puts a refused code's message into register.php's errors. */
function chaos_referral_add_error(): void {
	$error = (string)($GLOBALS['chaos_referral_error'] ?? '');
	if ($error !== '') {
		$GLOBALS['errors'][] = $error;
		$GLOBALS['chaos_referral_error'] = '';
	}
}

function chaos_referral_is_register_post(): bool {
	return ($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && basename((string)($_SERVER['SCRIPT_NAME'] ?? '')) === 'register.php'
		&& trim((string)($_POST['referral_code'] ?? '')) !== '';
}

}

// ---------------------------------------------------------------- hooks
if (function_exists('chaos_referral_is_register_post') && chaos_referral_is_register_post()) {
	$chaosRef = chaos_referral_check((string)$_POST['referral_code'], chaos_referral_settings(), 'chaos_referral_owner');
	if ($chaosRef[0] !== '') {
		$GLOBALS['chaos_referral_error'] = $chaosRef[0];
	} elseif ($chaosRef[1] !== null && function_exists('znote_hook_register')) {
		$chaosRefCode = $chaosRef[1];
		$chaosRefReferrer = $chaosRef[2];
		znote_hook_register('account.registered', static function (array $data) use ($chaosRefCode, $chaosRefReferrer): void {
			$row = db()->fetchOne('SELECT `id` FROM `accounts` WHERE `name` = ? LIMIT 1;', [(string)($data['name'] ?? '')]);
			if (is_array($row)) {
				chaos_referral_record((int)$row['id'], $chaosRefReferrer, $chaosRefCode, (string)($_SERVER['REMOTE_ADDR'] ?? ''));
			}
		});
	}
	unset($chaosRef, $chaosRefCode, $chaosRefReferrer);
}
