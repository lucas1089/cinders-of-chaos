<?php
/**
 * Creator codes on the website (pages/creator.php; website/README.md "Creator codes"; the game server's half is
 * server/data/scripts/chaos/creator_codes.lua, which matches credited donations to codes and pays the creator's share
 * in Chaos Coins after the hold).
 *
 *  - A donor picks a creator's code (chaos_creator_support): from then on, for supportDays, each of the account's
 *    donations credits the creator with sharePct % of its coins. The donor's pack is never reduced.
 *    Refused: an unknown or switched-off code, the creator's own code (self-use).
 *  - A creator (an account that owns a code) sees its code, its share, its supporters' donations (no names: date,
 *    coins, share, state) and what it earned.
 *  - Administrators (an admin panel account, $config['page_admin_access'], with a character of group adminGroup or
 *    higher: 5) create a code for a character's account, switch it off and on, set its own % and read the log.
 *  - The account's referral link (the game server's referral program) is shown on the same page.
 *
 * Settings: the game server's creator_codes_config.lua (CHAOS_SERVER_DATA); defaults without it. Every query is a
 * prepared statement through ZnoteX's db(); every value printed goes through chaos_h(). Writes are POSTs with the
 * page's CSRF token (checked in the page).
 */

if (!function_exists('chaos_creator_config')) {

/** The plain fields of a server Lua config file, comments stripped (missing: the defaults). */
function chaos_lua_config_fields(string $relative, array $defaults): array {
	$text = preg_replace('/--[^\n]*/', '', chaos_read_server_file($relative));
	$out = $defaults;
	if ($text === '') {
		return $out;
	}
	foreach ($defaults as $key => $default) {
		if (is_bool($default)) {
			if (preg_match('/\b' . preg_quote($key, '/') . '\s*=\s*(true|false)\b/', $text, $m)) {
				$out[$key] = $m[1] === 'true';
			}
			continue;
		}
		$v = chaos_lua_field($text, $key);
		if (is_int($default) && (is_int($v) || (is_float($v) && $v == (int)$v))) {
			$out[$key] = (int)$v;
		} elseif (is_string($default) && is_string($v)) {
			$out[$key] = $v;
		}
	}
	return $out;
}

/** creator_codes_config.lua: enabled, sharePct, supportDays, holdDays, orderCap, monthlyCap, adminGroup. */
function chaos_creator_config(): array {
	return chaos_lua_config_fields('scripts/chaos/creator_codes_config.lua', array(
		'enabled' => true, 'sharePct' => 5, 'supportDays' => 30, 'holdDays' => 14, 'orderCap' => 500,
		'monthlyCap' => 5000, 'adminGroup' => 5,
	));
}

/** "ashen-2" -> "ASHEN2", or '' when it is not a code (3-16 letters and digits). */
function chaos_creator_normalize(string $text): string {
	$code = strtoupper(preg_replace('/[\s\-]+/', '', $text));
	return preg_match('/^[A-Z0-9]{3,16}$/', $code) ? $code : '';
}

function chaos_creator_tables_ok(): bool {
	return chaos_table_exists('chaos_creator_codes') && chaos_table_exists('chaos_creator_support')
		&& chaos_table_exists('chaos_creator_uses') && chaos_table_exists('chaos_creator_log');
}

function chaos_creator_log(int $codeId, int $accountId, string $action, string $detail): void {
	db()->execute('INSERT INTO `chaos_creator_log` (`at`, `code_id`, `account_id`, `order_id`, `action`, `detail`) VALUES (?, ?, ?, 0, ?, ?);',
		[time(), $codeId, $accountId, substr($action, 0, 16), substr($detail, 0, 255)]);
}

/** A code row by its text, or null. */
function chaos_creator_find(string $code): ?array {
	$code = chaos_creator_normalize($code);
	if ($code === '' || !chaos_creator_tables_ok()) {
		return null;
	}
	$row = db()->fetchOne('SELECT `id`, `code`, `account_id`, `display_name`, `pct`, `active` FROM `chaos_creator_codes` WHERE `code` = ? LIMIT 1;', [$code]);
	return is_array($row) ? $row : null;
}

/** The donor's current pick: {code, display_name, expires_at} or null (none, or it ran out). */
function chaos_creator_support_of(int $accountId, ?int $now = null): ?array {
	if ($accountId <= 0 || !chaos_creator_tables_ok()) {
		return null;
	}
	$row = db()->fetchOne('SELECT `s`.`code_id`, `s`.`set_at`, `s`.`expires_at`, `c`.`code`, `c`.`display_name`, `c`.`active` FROM `chaos_creator_support` `s`
		JOIN `chaos_creator_codes` `c` ON `c`.`id` = `s`.`code_id` WHERE `s`.`account_id` = ? LIMIT 1;', [$accountId]);
	if (!is_array($row) || (int)$row['expires_at'] < ($now ?? time())) {
		return null;
	}
	return $row;
}

/**
 * The donor picks a code (or '' to clear it). Returns [ok, message]. HOOK for the donate page: call this with the
 * code field of the donation form before the order is created (website/README.md "Creator codes").
 */
function chaos_creator_set_support(int $accountId, string $text, string $ip = '', ?int $now = null): array {
	$cfg = chaos_creator_config();
	$now = $now ?? time();
	if ($accountId <= 0) {
		return array(false, 'Log in first.');
	}
	if (!$cfg['enabled'] || !chaos_creator_tables_ok()) {
		return array(false, 'Creator codes are not available right now.');
	}
	if (trim($text) === '') {
		db()->execute('DELETE FROM `chaos_creator_support` WHERE `account_id` = ?;', [$accountId]);
		chaos_creator_log(0, $accountId, 'unpick', '');
		return array(true, 'You no longer support a creator.');
	}
	$code = chaos_creator_find($text);
	if (!$code || (int)$code['active'] !== 1) {
		return array(false, 'That is not an active creator code.');
	}
	if ((int)$code['account_id'] === $accountId) {
		chaos_creator_log((int)$code['id'], $accountId, 'refused', 'self-use');
		return array(false, 'You cannot support your own creator code.');
	}
	$expires = $now + (int)$cfg['supportDays'] * 86400;
	db()->execute('DELETE FROM `chaos_creator_support` WHERE `account_id` = ?;', [$accountId]);
	db()->execute('INSERT INTO `chaos_creator_support` (`account_id`, `code_id`, `set_at`, `expires_at`, `ip`) VALUES (?, ?, ?, ?, ?);',
		[$accountId, (int)$code['id'], $now, $expires, substr($ip, 0, 64)]);
	chaos_creator_log((int)$code['id'], $accountId, 'pick', $code['code']);
	return array(true, sprintf('You now support %s (code %s) for %d days: %d%% of the coins of your donations go to them as a thank-you, at no cost to you.',
		$code['display_name'] !== '' ? $code['display_name'] : $code['code'], $code['code'], (int)$cfg['supportDays'],
		(int)$code['pct'] > 0 ? (int)$code['pct'] : (int)$cfg['sharePct']));
}

/** The codes an account owns, each with its totals: paid shares, coins earned, waiting coins. */
function chaos_creator_codes_of(int $accountId): array {
	if ($accountId <= 0 || !chaos_creator_tables_ok()) {
		return array();
	}
	$out = array();
	foreach (chaos_rows('SELECT `id`, `code`, `display_name`, `pct`, `active` FROM `chaos_creator_codes` WHERE `account_id` = ? ORDER BY `code`;', [$accountId]) as $c) {
		$t = db()->fetchOne("SELECT COALESCE(SUM(CASE WHEN `state` = 'paid' THEN `share` ELSE 0 END), 0) AS `earned`,
			COALESCE(SUM(CASE WHEN `state` IN ('pending', 'wait') THEN `share` ELSE 0 END), 0) AS `waiting`,
			COALESCE(SUM(CASE WHEN `state` = 'paid' THEN 1 ELSE 0 END), 0) AS `paid` FROM `chaos_creator_uses` WHERE `code_id` = ?;", [(int)$c['id']]);
		$c['earned'] = (int)($t['earned'] ?? 0);
		$c['waiting'] = (int)($t['waiting'] ?? 0);
		$c['paid'] = (int)($t['paid'] ?? 0);
		$c['supporters'] = (int)(db()->fetchOne('SELECT COUNT(*) AS `n` FROM `chaos_creator_support` WHERE `code_id` = ? AND `expires_at` >= ?;', [(int)$c['id'], time()])['n'] ?? 0);
		$c['uses'] = chaos_rows('SELECT `order_id`, `coins_base`, `share`, `state`, `reason`, `created_at`, `settled_at` FROM `chaos_creator_uses` WHERE `code_id` = ? ORDER BY `order_id` DESC LIMIT 50;', [(int)$c['id']]);
		$out[] = $c;
	}
	return $out;
}

// ---------------------------------------------------------------------------
// administrators
// ---------------------------------------------------------------------------

/** An admin panel account (as the reports page) with a character of group adminGroup (5) or higher. */
function chaos_creator_is_admin(array $config, int $accountId): bool {
	require_once __DIR__ . '/reports_lib.php';
	if (!chaos_reports_is_admin($config, $accountId)) {
		return false;
	}
	$row = db()->fetchOne('SELECT MAX(`group_id`) AS `g` FROM `players` WHERE `account_id` = ?;', [$accountId]);
	return is_array($row) && (int)($row['g'] ?? 0) >= (int)chaos_creator_config()['adminGroup'];
}

/** Creates a code for the account of `character`. Returns [ok, message]. */
function chaos_creator_admin_create(string $codeText, string $character, string $display, int $pct, string $note, string $staff): array {
	$code = chaos_creator_normalize($codeText);
	if ($code === '') {
		return array(false, 'A code is 3 to 16 letters and digits.');
	}
	if ($pct < 0 || $pct > 50) {
		return array(false, 'The own % is 0 (the default) to 50.');
	}
	$player = db()->fetchOne('SELECT `account_id`, `name` FROM `players` WHERE `name` = ? LIMIT 1;', [trim($character)]);
	if (!is_array($player)) {
		return array(false, 'No character of that name.');
	}
	if (chaos_creator_find($code)) {
		return array(false, 'That code is taken.');
	}
	db()->execute('INSERT INTO `chaos_creator_codes` (`code`, `account_id`, `display_name`, `pct`, `active`, `note`, `created_at`, `created_by`) VALUES (?, ?, ?, ?, 1, ?, ?, ?);',
		[$code, (int)$player['account_id'], substr(trim($display), 0, 64), $pct, substr(trim($note), 0, 255), time(), substr($staff, 0, 64)]);
	$row = chaos_creator_find($code);
	chaos_creator_log($row ? (int)$row['id'] : 0, (int)$player['account_id'], 'create', $code . ' for ' . $player['name'] . ' by ' . $staff);
	return array(true, 'Code ' . $code . ' created for the account of ' . $player['name'] . '.');
}

/** Switches a code off or on, or sets its own %. Returns [ok, message]. */
function chaos_creator_admin_update(int $codeId, string $what, int $pct, string $staff): array {
	$row = db()->fetchOne('SELECT `id`, `code`, `account_id`, `active` FROM `chaos_creator_codes` WHERE `id` = ? LIMIT 1;', [$codeId]);
	if (!is_array($row)) {
		return array(false, 'No such code.');
	}
	if ($what === 'off' || $what === 'on') {
		db()->execute('UPDATE `chaos_creator_codes` SET `active` = ? WHERE `id` = ?;', [$what === 'on' ? 1 : 0, $codeId]);
		chaos_creator_log($codeId, (int)$row['account_id'], $what, $row['code'] . ' by ' . $staff);
		return array(true, $row['code'] . ($what === 'on' ? ' is on.' : ' is off: new picks are refused and waiting shares void.'));
	}
	if ($what === 'pct' && $pct >= 0 && $pct <= 50) {
		db()->execute('UPDATE `chaos_creator_codes` SET `pct` = ? WHERE `id` = ?;', [$pct, $codeId]);
		chaos_creator_log($codeId, (int)$row['account_id'], 'pct', $row['code'] . ' ' . $pct . '% by ' . $staff);
		return array(true, $row['code'] . ': ' . ($pct > 0 ? $pct . '%' : 'the default %') . '.');
	}
	return array(false, 'Unknown action.');
}

/** Every code with its owner's character name and totals, for the admin view. */
function chaos_creator_admin_list(): array {
	if (!chaos_creator_tables_ok()) {
		return array();
	}
	return chaos_rows("SELECT `c`.`id`, `c`.`code`, `c`.`display_name`, `c`.`pct`, `c`.`active`, `c`.`created_at`, `c`.`created_by`, `c`.`note`,
		(SELECT `p`.`name` FROM `players` `p` WHERE `p`.`account_id` = `c`.`account_id` ORDER BY `p`.`level` DESC LIMIT 1) AS `owner`,
		(SELECT COALESCE(SUM(`u`.`share`), 0) FROM `chaos_creator_uses` `u` WHERE `u`.`code_id` = `c`.`id` AND `u`.`state` = 'paid') AS `earned`,
		(SELECT COUNT(*) FROM `chaos_creator_uses` `u` WHERE `u`.`code_id` = `c`.`id` AND `u`.`state` = 'void') AS `voided`
		FROM `chaos_creator_codes` `c` ORDER BY `c`.`code`;");
}

function chaos_creator_admin_log(int $limit = 50): array {
	if (!chaos_creator_tables_ok()) {
		return array();
	}
	return chaos_rows('SELECT `at`, `code_id`, `account_id`, `order_id`, `action`, `detail` FROM `chaos_creator_log` ORDER BY `id` DESC LIMIT ?;', [$limit]);
}

// ---------------------------------------------------------------------------
// the account's referral link (the game server's referral program, referral_config.lua)
// ---------------------------------------------------------------------------

/** register.php?ref=CODE on this site, or '' when the account has no code yet (it gets one in game at level 20). */
function chaos_referral_link(int $accountId, string $siteUrl): string {
	if ($accountId <= 0 || !chaos_table_exists('chaos_referral_codes')) {
		return '';
	}
	$row = db()->fetchOne('SELECT `code` FROM `chaos_referral_codes` WHERE `account_id` = ? LIMIT 1;', [$accountId]);
	if (!is_array($row) || (string)$row['code'] === '') {
		return '';
	}
	return rtrim($siteUrl, '/') . '/register?ref=' . rawurlencode((string)$row['code']);
}

} // function_exists guard
