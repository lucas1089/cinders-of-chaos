<?php
/**
 * Account creation limit per IP address (website/README.md "Account creation"). Loaded by plugin.php.
 *
 *  - A register.php POST from an address that created `per_ip` accounts in the last `window_seconds` (config.local.php
 *    $config['chaos_register_limit'], default 3 per hour) is refused: the message goes into register.php's $errors
 *    through the register_header view (layouts/chaos/views/register_header.php), so nothing is created.
 *  - Every account created is logged in `chaos_web_registrations` (address, time; install.sql) on the
 *    account.registered hook. Rows older than a day are deleted on the way.
 *  - The address is REMOTE_ADDR (as ZnoteX's login guard): behind a reverse proxy pass the client address to PHP.
 *    An IPv6 address counts by its /64 network, which one household normally owns as a whole.
 */

if (!function_exists('chaos_register_ip_key')) {

/** The key an address is counted under: IPv4 as is, IPv6 by its /64 network ("2001:db8:1:2::/64"). */
function chaos_register_ip_key(string $ip): string {
	$bin = @inet_pton($ip);
	if ($bin === false) {
		return substr($ip, 0, 45);
	}
	if (strlen($bin) === 16) {
		return inet_ntop(substr($bin, 0, 8) . str_repeat("\0", 8)) . '/64';
	}
	return inet_ntop($bin);
}

function chaos_register_limit(): array {
	$cfg = (array)($GLOBALS['config']['chaos_register_limit'] ?? array());
	return array('per_ip' => max(0, (int)($cfg['per_ip'] ?? 3)), 'window_seconds' => max(60, (int)($cfg['window_seconds'] ?? 3600)));
}

/** True when this address may create one more account now. $count: callable(string key, int since): int. */
function chaos_register_allowed(string $ip, int $now, callable $count): bool {
	$limit = chaos_register_limit();
	if ($limit['per_ip'] <= 0) {
		return true; // 0 = no limit
	}
	return $count(chaos_register_ip_key($ip), $now - $limit['window_seconds']) < $limit['per_ip'];
}

function chaos_register_count(string $key, int $since): int {
	if (!function_exists('chaos_table_exists') || !chaos_table_exists('chaos_web_registrations')) {
		return 0;
	}
	$row = db()->fetchOne('SELECT COUNT(*) AS `n` FROM `chaos_web_registrations` WHERE `ip` = ? AND `created` >= ?;', [$key, $since]);
	return is_array($row) ? (int)$row['n'] : 0;
}

function chaos_register_log(string $ip, int $now): void {
	if (!function_exists('chaos_table_exists') || !chaos_table_exists('chaos_web_registrations')) {
		return;
	}
	db()->execute('DELETE FROM `chaos_web_registrations` WHERE `created` < ?;', [$now - 86400]);
	db()->execute('INSERT INTO `chaos_web_registrations` (`ip`, `created`) VALUES (?, ?);', [chaos_register_ip_key($ip), $now]);
}

function chaos_register_is_post(): bool {
	return ($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && basename((string)($_SERVER['SCRIPT_NAME'] ?? '')) === 'register.php';
}

/** Called by the register_header view: puts the refusal into register.php's errors. */
function chaos_register_add_error(): void {
	$error = (string)($GLOBALS['chaos_register_error'] ?? '');
	if ($error !== '') {
		$GLOBALS['errors'][] = $error;
		$GLOBALS['chaos_register_error'] = '';
	}
}

}

// ---------------------------------------------------------------- hooks
if (chaos_register_is_post() && PHP_SAPI !== 'cli') {
	$chaosRegIp = (string)($_SERVER['REMOTE_ADDR'] ?? '');
	if (!chaos_register_allowed($chaosRegIp, time(), 'chaos_register_count')) {
		$GLOBALS['chaos_register_error'] = 'Too many accounts were created from your address. Please try again later.';
	} elseif (function_exists('znote_hook_register')) {
		znote_hook_register('account.registered', static function (array $data) use ($chaosRegIp): void {
			chaos_register_log($chaosRegIp, time());
		});
	}
	unset($chaosRegIp);
}
