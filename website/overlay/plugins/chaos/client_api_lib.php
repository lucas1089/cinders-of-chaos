<?php
/**
 * The client's account API (website/README.md "Client API"): the game client's character select reads the account's
 * character looks and creates characters through it. Entry point: chaos_client_api.php (site root, POST, JSON).
 *
 * Actions (JSON body {"action": ..., ...}; every answer is JSON {"ok": true|false, ...}):
 *   login   {account, password, nonce}  -> a session token (30 minutes) and the state below. The password is checked
 *           exactly as the website login does it (ZnoteX's login guard: 5 failures per address, 10 per account name in
 *           15 minutes lock that address / name, shared with the website login; the unknown-account answer and time
 *           equal a wrong password's).
 *   state   {token}                      -> the state: the account's character looks (outfit, colours, addons, wings,
 *           aura, shader, last login, season tag), the classes it may create (class lock), slots, towns, name rules,
 *           the running season and its modes, whether the current Terms were accepted.
 *   create  {token, nonce, name, vocation, sex, town, season, mode, hardcore}
 *           -> creates the character with engine/function/chaos_character.php: the website form's own checks (name
 *           rules, taken name, class lock, character slots, town, sex, IP), plus the Terms (accepted on the site),
 *           a creation limit per account and per address, and the season join (a request the game server carries
 *           out at the character's first login, season.lua).
 *   logout  {token}                      -> ends the token.
 *
 * Security: HTTPS only in production (the web server; the client refuses a non-HTTPS URL except 127.0.0.1). The
 * password is sent once, in the login body, and never stored; the token is random (32 bytes), only its SHA-256 is
 * kept, it ends after `token_seconds`, at logout, and when the account's password changes (the session guard's mark).
 * Replays: every login and create carries a fresh nonce, kept for two hours (longer than a token lives); a nonce seen
 * twice is refused. Floods: at most `per_ip_minute` requests per address per minute (IPv6 by its /64, as the register
 * guard), `create_per_account_hour` and `create_per_ip_hour` new characters. CSRF does not apply: no cookie is used.
 * Every query is a prepared statement; nothing from the request is printed back except the character name.
 */

if (!defined('CHAOS_CLIENT_API_VERSION')) {
	define('CHAOS_CLIENT_API_VERSION', 1);
}

if (!function_exists('chaos_client_api_settings')) {

/** $config['chaos_client_api'] (config.local.php) with its defaults. */
function chaos_client_api_settings(): array {
	$cfg = (array)($GLOBALS['config']['chaos_client_api'] ?? array());
	return array(
		'enabled'                 => !array_key_exists('enabled', $cfg) || !empty($cfg['enabled']),
		'token_seconds'           => max(60, (int)($cfg['token_seconds'] ?? 1800)),
		'per_ip_minute'           => max(1, (int)($cfg['per_ip_minute'] ?? 30)),
		'create_per_account_hour' => max(1, (int)($cfg['create_per_account_hour'] ?? 3)),
		'create_per_ip_hour'      => max(1, (int)($cfg['create_per_ip_hour'] ?? 5)),
		'nonce_seconds'           => 7200,
	);
}

/** The key an address is counted under (the register guard's: IPv4 as is, IPv6 by its /64). */
function chaos_client_api_ip_key(string $ip): string {
	if (function_exists('chaos_register_ip_key')) {
		return chaos_register_ip_key($ip);
	}
	return substr($ip, 0, 45);
}

function chaos_client_api_fail(int $status, string $error, string $message, array $extra = array()): array {
	return array($status, array('ok' => false, 'error' => $error, 'message' => $message) + $extra);
}

/** Requests of an address (all actions) in the last minute, then this one logged. */
function chaos_client_api_flooded(string $ipKey, string $action, int $now): bool {
	$row = db()->fetchOne('SELECT COUNT(*) AS `n` FROM `chaos_client_api_log` WHERE `ip` = ? AND `created` >= ?;', [$ipKey, $now - 60]);
	return is_array($row) && (int)$row['n'] >= chaos_client_api_settings()['per_ip_minute'];
}

function chaos_client_api_log(string $ipKey, int $accountId, string $action, bool $ok, int $now): void {
	db()->execute('INSERT INTO `chaos_client_api_log` (`ip`, `account_id`, `action`, `ok`, `created`) VALUES (?, ?, ?, ?, ?);',
		[$ipKey, $accountId, substr($action, 0, 16), $ok ? 1 : 0, $now]);
	if (random_int(1, 50) === 1) {
		db()->execute('DELETE FROM `chaos_client_api_log` WHERE `created` < ?;', [$now - 86400]);
		db()->execute('DELETE FROM `chaos_client_tokens` WHERE `expires` < ?;', [$now]);
	}
}

/** True the first time a nonce is seen (it is then kept); false for a replay or a malformed nonce. */
function chaos_client_api_nonce_fresh($nonce, int $now): bool {
	if (!is_string($nonce) || !preg_match('/^[0-9a-f]{16,64}$/', $nonce)) {
		return false;
	}
	db()->execute('DELETE FROM `chaos_client_nonces` WHERE `created` < ?;', [$now - chaos_client_api_settings()['nonce_seconds']]);
	if (is_array(db()->fetchOne('SELECT `nonce` FROM `chaos_client_nonces` WHERE `nonce` = ? LIMIT 1;', [$nonce]))) {
		return false;
	}
	db()->execute('INSERT INTO `chaos_client_nonces` (`nonce`, `created`) VALUES (?, ?);', [$nonce, $now]);
	return true;
}

/** The account's stored password hash mark (session_guard.php): a token ends when the password changes. */
function chaos_client_api_pass_mark(int $accountId): ?string {
	$row = db()->fetchOne('SELECT `password` FROM `accounts` WHERE `id` = ? LIMIT 1;', [$accountId]);
	if (!is_array($row)) {
		return null;
	}
	$hash = (string)$row['password'];
	return function_exists('chaos_session_password_mark') ? chaos_session_password_mark($accountId, $hash)
		: hash('sha256', 'chaos-session-password|' . $accountId . '|' . $hash);
}

function chaos_client_api_issue_token(int $accountId, string $ipKey, int $now): array {
	$token = bin2hex(random_bytes(32));
	$expires = $now + chaos_client_api_settings()['token_seconds'];
	db()->execute('INSERT INTO `chaos_client_tokens` (`token_hash`, `account_id`, `pass_mark`, `ip`, `created`, `expires`) VALUES (?, ?, ?, ?, ?, ?);',
		[hash('sha256', $token), $accountId, (string)chaos_client_api_pass_mark($accountId), $ipKey, $now, $expires]);
	return array($token, $expires);
}

/** The account id of a valid token, or 0 (unknown, expired, or the password changed since). */
function chaos_client_api_token_account($token, int $now): int {
	if (!is_string($token) || !preg_match('/^[0-9a-f]{64}$/', $token)) {
		return 0;
	}
	$row = db()->fetchOne('SELECT `account_id`, `pass_mark`, `expires` FROM `chaos_client_tokens` WHERE `token_hash` = ? LIMIT 1;', [hash('sha256', $token)]);
	if (!is_array($row) || (int)$row['expires'] < $now) {
		return 0;
	}
	$accountId = (int)$row['account_id'];
	$mark = chaos_client_api_pass_mark($accountId);
	if ($mark === null || !hash_equals((string)$row['pass_mark'], $mark)) {
		db()->execute('DELETE FROM `chaos_client_tokens` WHERE `token_hash` = ?;', [hash('sha256', $token)]);
		return 0;
	}
	return $accountId;
}

// ---------------------------------------------------------------- the account's state

/** True when the players table has this column (the base server adds wings_id, aura_id, shader_id). */
function chaos_client_api_has_column(string $table, string $column): bool {
	static $known = array();
	$key = $table . '.' . $column;
	if (!isset($known[$key])) {
		$row = db()->fetchOne('SELECT COUNT(*) AS `n` FROM `information_schema`.`columns` WHERE `table_schema` = DATABASE() AND `table_name` = ? AND `column_name` = ?;', [$table, $column]);
		$known[$key] = is_array($row) && (int)($row['n'] ?? 0) > 0;
	}
	return $known[$key];
}

/** Shader names of the server's data/XML/shaders.xml: id => name ('' when not readable). */
function chaos_client_api_shaders(): array {
	$text = chaos_read_server_file('XML/shaders.xml');
	$out = array();
	if (preg_match_all('/<shader\s+id="(\d+)"\s+name="([A-Za-z0-9_ ]{1,40})"/', $text, $m, PREG_SET_ORDER)) {
		foreach ($m as $s) {
			$out[(int)$s[1]] = $s[2];
		}
	}
	return $out;
}

/** The account's characters as the character select draws them: name => look and card facts. */
function chaos_client_api_looks(int $accountId): array {
	$extra = '';
	foreach (array('wings_id', 'aura_id', 'shader_id') as $col) {
		$extra .= chaos_client_api_has_column('players', $col) ? ", `p`.`$col`" : ", 0 AS `$col`";
	}
	$season = chaos_table_exists('chaos_season_players');
	$rows = chaos_rows('SELECT `p`.`id`, `p`.`name`, `p`.`level`, `p`.`vocation`, `p`.`sex`, `p`.`looktype`, `p`.`lookhead`, `p`.`lookbody`, `p`.`looklegs`, `p`.`lookfeet`, `p`.`lookaddons`, `p`.`lastlogin`' . $extra
		. ($season ? ', `s`.`season` AS `season_id`, `s`.`migrated_at`' : '')
		. ' FROM `players` `p`' . ($season ? ' LEFT JOIN `chaos_season_players` `s` ON `s`.`player_id` = `p`.`id`' : '')
		. ' WHERE `p`.`account_id` = ? AND `p`.`deletion` = 0 ORDER BY `p`.`name` LIMIT 50;', [$accountId]);
	$shaders = chaos_client_api_shaders();
	$seasons = $season ? chaos_seasons() : array();
	$requests = array();
	if (chaos_table_exists('chaos_season_requests')) {
		foreach (chaos_rows('SELECT `r`.`player_id`, `r`.`season` FROM `chaos_season_requests` `r` JOIN `players` `p` ON `p`.`id` = `r`.`player_id` WHERE `p`.`account_id` = ?;', [$accountId]) as $r) {
			$requests[(int)$r['player_id']] = (int)$r['season'];
		}
	}
	$out = array();
	foreach ($rows as $r) {
		$tag = '';
		$sid = (int)($r['season_id'] ?? 0);
		if ($sid > 0 && (int)($r['migrated_at'] ?? 0) === 0 && isset($seasons[$sid])) {
			$tag = $seasons[$sid]['tag'];
		} elseif (isset($requests[(int)$r['id']], $seasons[$requests[(int)$r['id']]])) {
			$tag = $seasons[$requests[(int)$r['id']]]['tag'];
		}
		$out[(string)$r['name']] = array(
			'type' => (int)$r['looktype'], 'head' => (int)$r['lookhead'], 'body' => (int)$r['lookbody'],
			'legs' => (int)$r['looklegs'], 'feet' => (int)$r['lookfeet'], 'addons' => (int)$r['lookaddons'],
			'wings' => (int)$r['wings_id'], 'aura' => (int)$r['aura_id'], 'shader' => $shaders[(int)$r['shader_id']] ?? '',
			'level' => (int)$r['level'], 'vocation' => (int)$r['vocation'], 'sex' => (int)$r['sex'],
			'lastLogin' => (int)$r['lastlogin'], 'season' => $tag,
		);
	}
	return $out;
}

/** The season a new character may join now (the running one) with its modes, or null. */
function chaos_client_api_season(int $now): ?array {
	foreach (chaos_seasons() as $s) {
		if ($s['start'] > 0 && $s['start'] <= $now && ($s['finish'] <= 0 || $now < $s['finish'])) {
			return array('id' => $s['id'], 'name' => $s['name'], 'tag' => $s['tag'], 'endsAt' => $s['finish'],
				'modifier' => $s['modifier'], 'modes' => chaos_season_modes_list());
		}
	}
	return null;
}

/** A `key = "a" .. "b"` text field of a Lua entry, its pieces joined ('' when missing). */
function chaos_client_api_lua_text(string $entry, string $key): string {
	if (!preg_match('/\b' . preg_quote($key, '/') . '\s*=\s*((?:"(?:[^"\\\\]|\\\\.)*"\s*(?:\.\.\s*)?)+)/', $entry, $m)) {
		return '';
	}
	preg_match_all('/"((?:[^"\\\\]|\\\\.)*)"/', $m[1], $parts);
	return stripcslashes(implode('', $parts[1]));
}

/** The modes of season_config.lua `modes.list`: {key, name, warning, ssf, hc}, Standard first. */
function chaos_season_modes_list(): array {
	$text = chaos_read_server_file('scripts/chaos/season_config.lua');
	$out = array();
	foreach (chaos_lua_entries(chaos_lua_block(chaos_lua_block($text, 'modes'), 'list')) as $entry) {
		$key = chaos_lua_field($entry, 'key');
		if (!is_string($key) || !preg_match('/^[a-z]{1,16}$/', $key)) {
			continue;
		}
		$out[] = array('key' => $key, 'name' => (string)(chaos_lua_field($entry, 'name') ?? $key),
			'warning' => chaos_client_api_lua_text($entry, 'warning'), 'ssf' => chaos_lua_bool($entry, 'ssf'),
			'hc' => chaos_lua_bool($entry, 'hc'));
	}
	if (!$out) {
		$out[] = array('key' => 'standard', 'name' => 'Standard', 'warning' => '', 'ssf' => false, 'hc' => false);
	}
	return $out;
}

function chaos_client_api_state(int $accountId, int $now): array {
	global $config;
	$creatable = chaos_creatable_classes($accountId);
	$classes = array();
	foreach (chaos_class_lines() as $base => $line) {
		$classes[] = array('id' => $base, 'name' => $line['name'], 'plays' => $line['plays'], 'icon' => $line['icon'],
			'locked' => !in_array($base, $creatable, true), 'lock' => $line['lock'],
			'male' => (int)chaos_class_look($base, 1), 'female' => (int)chaos_class_look($base, 0));
	}
	$towns = array();
	foreach ((array)($config['available_towns'] ?? array()) as $tid) {
		$towns[] = array('id' => (int)$tid, 'name' => function_exists('town_id_to_name') ? (string)town_id_to_name($tid) : (string)$tid);
	}
	$used = function_exists('user_character_list_count') ? (int)user_character_list_count($accountId) : 0;
	$site = rtrim((string)($config['site_url'] ?? ''), '/');
	return array(
		'account' => array(
			'terms' => !function_exists('chaos_legal_has_accepted') || chaos_legal_has_accepted($accountId),
			'termsUrl' => $site . '/page.php?plugin=chaos&p=accept',
			'slots' => array('used' => $used, 'limit' => chaos_character_limit($accountId)),
			'classes' => $classes,
			'towns' => $towns,
			'rules' => array('minL' => (int)($config['minL'] ?? 3), 'maxL' => (int)($config['maxL'] ?? 20), 'maxW' => (int)($config['maxW'] ?? 3)),
			'season' => chaos_client_api_season($now),
		),
		'looks' => chaos_client_api_looks($accountId),
	);
}

// ---------------------------------------------------------------- actions

function chaos_client_api_login(array $req, string $ip, string $ipKey, int $now): array {
	global $config;
	$username = $req['account'] ?? null;
	$password = $req['password'] ?? null;
	if (!is_string($username) || !is_string($password) || $username === '' || $password === '') {
		return chaos_client_api_fail(400, 'fields', 'Enter your account name and password.');
	}
	if (strlen($username) > 32 || strlen($password) > 64) {
		return chaos_client_api_fail(400, 'fields', 'Account name or password is too long.');
	}
	$guardIp = function_exists('znote_login_guard_ip') ? znote_login_guard_ip() : $ip;
	$ipLock = function_exists('znote_login_guard_lockout_remaining') ? znote_login_guard_lockout_remaining($guardIp) : 0;
	$nameLock = function_exists('znote_login_guard_account_lockout_remaining') ? znote_login_guard_account_lockout_remaining($username) : 0;
	if ($ipLock > 0 || $nameLock > 0) {
		$minutes = (int)ceil(max($ipLock, $nameLock) / 60);
		return chaos_client_api_fail(429, 'locked', 'Too many failed logins. Try again in ' . $minutes . ' minute(s).', array('retryAfter' => max($ipLock, $nameLock)));
	}
	if (!chaos_client_api_nonce_fresh($req['nonce'] ?? null, $now)) {
		return chaos_client_api_fail(409, 'replay', 'This request was already used. Please try again.');
	}
	$login = false;
	if (user_exist($username) === false) {
		chaos_password_dummy($password); // the same answer and about the same time as a wrong password
	} else {
		$login = znote_server_adapter()->login($username, $password);
	}
	if (function_exists('znote_login_guard_record')) {
		znote_login_guard_record($guardIp, $username, $login !== false);
	}
	if ($login === false) {
		return chaos_client_api_fail(401, 'auth', 'Account name or password is not correct.');
	}
	$accountId = (int)$login;
	if (!empty($config['mailserver']['register'])) {
		$active = db()->fetchOne('SELECT `id` FROM `znote_accounts` WHERE `account_id` = ? AND `active` = 1 LIMIT 1;', [$accountId]);
		if ($active === false) {
			return chaos_client_api_fail(403, 'inactive', 'Activate your account first (the e-mail of the website).');
		}
	}
	[$token, $expires] = chaos_client_api_issue_token($accountId, $ipKey, $now);
	return array(200, array('ok' => true, 'version' => CHAOS_CLIENT_API_VERSION, 'token' => $token, 'expires' => $expires,
		'expiresIn' => $expires - $now)
		+ chaos_client_api_state($accountId, $now));
}

/** A clearer refusal than the form's "wrong vocation" for a locked class line. */
function chaos_client_api_class_problem(int $vocation, int $accountId): ?string {
	$lines = chaos_class_lines();
	if (!isset($lines[$vocation])) {
		return null;
	}
	if ($lines[$vocation]['lock'] !== '' && !in_array($vocation, chaos_creatable_classes($accountId), true)) {
		return 'The ' . $lines[$vocation]['name'] . ' is locked for your account. Unlock it in the game store (Classes).';
	}
	return null;
}

function chaos_client_api_create(array $req, int $accountId, string $ipKey, int $now): array {
	global $config;
	$state = chaos_client_api_settings();
	if (function_exists('chaos_legal_has_accepted') && !chaos_legal_has_accepted($accountId)) {
		$site = rtrim((string)($config['site_url'] ?? ''), '/');
		return chaos_client_api_fail(403, 'terms', 'Accept the current Terms of Use on the website first (log in there once).',
			array('url' => $site . '/page.php?plugin=chaos&p=accept'));
	}
	if (!chaos_client_api_nonce_fresh($req['nonce'] ?? null, $now)) {
		return chaos_client_api_fail(409, 'replay', 'This request was already used. Please try again.');
	}
	$byAccount = db()->fetchOne("SELECT COUNT(*) AS `n` FROM `chaos_client_api_log` WHERE `account_id` = ? AND `action` = 'create' AND `ok` = 1 AND `created` >= ?;", [$accountId, $now - 3600]);
	$byIp = db()->fetchOne("SELECT COUNT(*) AS `n` FROM `chaos_client_api_log` WHERE `ip` = ? AND `action` = 'create' AND `ok` = 1 AND `created` >= ?;", [$ipKey, $now - 3600]);
	if ((is_array($byAccount) && (int)$byAccount['n'] >= $state['create_per_account_hour'])
		|| (is_array($byIp) && (int)$byIp['n'] >= $state['create_per_ip_hour'])) {
		return chaos_client_api_fail(429, 'limit', 'Too many new characters in the last hour. Please try again later.', array('retryAfter' => 3600));
	}
	// the website form's checks, for this account (plugin.php does the same for the logged-in session)
	$config['available_vocations'] = chaos_creatable_classes($accountId);
	$config['max_characters'] = chaos_character_limit($accountId);
	$userData = function_exists('user_data') ? (array)user_data($accountId, 'id', 'name', 'password', 'email', 'premium_ends_at') : array('id' => $accountId);
	$towns = array_map('intval', (array)($config['available_towns'] ?? array()));
	$town = (int)($req['town'] ?? 0);
	$post = array(
		'name' => is_string($req['name'] ?? null) ? substr($req['name'], 0, 64) : '',
		'selected_vocation' => (int)($req['vocation'] ?? 0),
		'selected_town' => $town > 0 ? $town : (int)($towns[count($towns) - 1] ?? 0),
		'selected_gender' => (int)($req['sex'] ?? -1),
	);
	$errors = chaos_character_form_errors($post, $accountId, $userData, false);
	$classProblem = chaos_client_api_class_problem($post['selected_vocation'], $accountId);
	if ($classProblem !== null) {
		$generic = function_exists('t') ? t('createchar.bad_vocation') : '';
		$errors = array_values(array_filter($errors, static function ($e) use ($generic) { return $e !== $generic; }));
		$errors[] = $classProblem;
	}

	// optional season: the running one, a known mode, Hardcore confirmed
	$seasonId = (int)($req['season'] ?? 0);
	$mode = null;
	if ($seasonId > 0) {
		$season = chaos_client_api_season($now);
		if ($season === null || $season['id'] !== $seasonId) {
			$errors[] = 'That season is not running now. Create the character without a season.';
		} else {
			foreach ($season['modes'] as $m) {
				if ($m['key'] === ($req['mode'] ?? 'standard')) {
					$mode = $m;
				}
			}
			if ($mode === null) {
				$errors[] = 'Unknown season mode.';
			} elseif ($mode['hc'] && empty($req['hardcore'])) {
				$errors[] = 'Hardcore has one life: tick "I understand" to choose it.';
			}
		}
	}
	if ($errors) {
		chaos_client_api_log($ipKey, $accountId, 'create', false, $now);
		return array(400, array('ok' => false, 'error' => 'invalid', 'message' => (string)$errors[0], 'errors' => array_values(array_unique($errors))));
	}

	$created = chaos_character_create($post, $accountId);
	$name = (string)$created['name'];
	if ($mode !== null) {
		$row = db()->fetchOne('SELECT `id` FROM `players` WHERE `name` = ? AND `account_id` = ? LIMIT 1;', [$name, $accountId]);
		if (is_array($row)) {
			db()->execute('INSERT INTO `chaos_season_requests` (`player_id`, `season`, `mode`, `requested_at`) VALUES (?, ?, ?, ?);',
				[(int)$row['id'], $seasonId, $mode['key'], $now]);
		}
	}
	chaos_client_api_log($ipKey, $accountId, 'create', true, $now);
	$looks = chaos_client_api_looks($accountId);
	return array(200, array('ok' => true, 'name' => $name, 'look' => $looks[$name] ?? null,
		'message' => $name . ' was created.' . ($mode !== null ? ' It joins the season at its first login.' : '')));
}

/**
 * One request: [HTTP status, answer]. $req is the decoded JSON body, $ip the client address (REMOTE_ADDR).
 */
function chaos_client_api_handle(array $req, string $ip, int $now): array {
	$settings = chaos_client_api_settings();
	if (!$settings['enabled']) {
		return chaos_client_api_fail(503, 'off', 'Character creation in the client is switched off. Use the website.');
	}
	$action = is_string($req['action'] ?? null) ? $req['action'] : '';
	$ipKey = chaos_client_api_ip_key($ip);
	if (chaos_client_api_flooded($ipKey, $action, $now)) {
		return chaos_client_api_fail(429, 'busy', 'Too many requests. Please wait a minute.', array('retryAfter' => 60));
	}
	if ($action === 'login') {
		$out = chaos_client_api_login($req, $ip, $ipKey, $now);
		chaos_client_api_log($ipKey, 0, 'login', $out[0] === 200, $now);
		return $out;
	}
	if (!in_array($action, array('state', 'create', 'logout'), true)) {
		chaos_client_api_log($ipKey, 0, 'unknown', false, $now);
		return chaos_client_api_fail(400, 'action', 'Unknown action.');
	}
	$accountId = chaos_client_api_token_account($req['token'] ?? null, $now);
	if ($accountId <= 0) {
		chaos_client_api_log($ipKey, 0, $action, false, $now);
		return chaos_client_api_fail(401, 'token', 'Your session ended. Log in again.');
	}
	if ($action === 'logout') {
		db()->execute('DELETE FROM `chaos_client_tokens` WHERE `token_hash` = ?;', [hash('sha256', (string)$req['token'])]);
		chaos_client_api_log($ipKey, $accountId, 'logout', true, $now);
		return array(200, array('ok' => true));
	}
	if ($action === 'state') {
		chaos_client_api_log($ipKey, $accountId, 'state', true, $now);
		return array(200, array('ok' => true) + chaos_client_api_state($accountId, $now));
	}
	return chaos_client_api_create($req, $accountId, $ipKey, $now);
}

}
