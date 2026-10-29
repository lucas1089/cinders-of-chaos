<?php
/**
 * The creator program page (pages/creators.php, website/README.md "Creator program"): who qualifies, what a creator
 * gets, how to apply, the media kit. Texts and states are creators/creators_data.json (pt-BR and en); the media kit
 * file list is creators/media_kit_manifest.json (website/tools/gen_media_kit.py). Each benefit may list `verify` rules
 * that website/tests/chaos_creators_page_test.php checks against the server configs.
 */

if (!function_exists('chaos_creators_data')) {

function chaos_creators_json(string $name): array {
	$file = __DIR__ . '/creators/' . $name;
	$text = is_file($file) ? file_get_contents($file) : false;
	$json = $text === false ? null : json_decode((string)$text, true);
	return is_array($json) ? $json : array();
}

/** {updated, qualify, benefits[], apply, open[]}; empty parts when the file is missing. */
function chaos_creators_data(): array {
	$j = chaos_creators_json('creators_data.json');
	return array(
		'updated' => is_string($j['updated'] ?? null) ? $j['updated'] : '',
		'qualify' => is_array($j['qualify'] ?? null) ? $j['qualify'] : array('status' => '', 'intro' => '', 'items' => array()),
		'benefits' => is_array($j['benefits'] ?? null) ? $j['benefits'] : array(),
		'apply' => is_array($j['apply'] ?? null) ? $j['apply'] : array('intro' => '', 'steps' => array()),
		'open' => is_array($j['open'] ?? null) ? $j['open'] : array(),
	);
}

/** {zip: {name, path, bytes, sha256}, files: [{name, bytes}]}; zip empty without the manifest. */
function chaos_creators_kit(): array {
	$j = chaos_creators_json('media_kit_manifest.json');
	return array('zip' => is_array($j['zip'] ?? null) ? $j['zip'] : array(), 'files' => is_array($j['files'] ?? null) ? $j['files'] : array());
}

function chaos_creators_size(int $bytes): string {
	return $bytes >= 1048576 ? number_format($bytes / 1048576, 1, '.', '') . ' MB' : number_format(max(1, (int)round($bytes / 1024))) . ' KB';
}


/** The numbers of the criteria (creators/creators_data.json "criteria"): hours a week, average live viewers, followers. */
function chaos_creators_criteria(): array {
	$c = (array)(chaos_creators_json('creators_data.json')['criteria'] ?? array());
	return array('hoursWeek' => max(1, (int)($c['hoursWeek'] ?? 4)), 'viewers' => max(1, (int)($c['viewers'] ?? 10)), 'followers' => max(1, (int)($c['followers'] ?? 500)));
}

/** The platforms of the form. */
function chaos_creators_platforms(): array {
	return array('twitch', 'youtube', 'kick', 'tiktok', 'other');
}

/**
 * Checks the form. Returns [errors (each an English message, or [message, sprintf arguments...]), clean values]. The criteria are the page's: at least hoursWeek hours
 * of streams or videos of the game a week, and at least `viewers` average live viewers or `followers` followers, and the
 * promise of no account trading or real-money trading.
 */
function chaos_creators_validate(array $in, array $crit): array {
	$errors = array();
	$clean = array(
		'platform' => strtolower(trim((string)($in['platform'] ?? ''))),
		'channel_url' => trim((string)($in['channel_url'] ?? '')),
		'character_name' => trim((string)($in['character_name'] ?? '')),
		'hours_week' => (int)($in['hours_week'] ?? 0),
		'viewers_avg' => (int)($in['viewers_avg'] ?? 0),
		'followers' => (int)($in['followers'] ?? 0),
		'message' => trim((string)($in['message'] ?? '')),
	);
	if (!in_array($clean['platform'], chaos_creators_platforms(), true)) {
		$errors[] = 'Pick a platform.';
	}
	if (strlen($clean['channel_url']) > 255 || !preg_match('#^https://[A-Za-z0-9.-]+\.[A-Za-z]{2,}(/[^\s<>"\']*)?$#', $clean['channel_url'])) {
		$errors[] = 'The channel link must be an https link.';
	}
	if ($clean['character_name'] === '' || strlen($clean['character_name']) > 29) {
		$errors[] = 'Write the name of your character.';
	}
	foreach (array('hours_week' => 168, 'viewers_avg' => 10000000, 'followers' => 100000000) as $k => $max) {
		if ($clean[$k] < 0 || $clean[$k] > $max) {
			$errors[] = 'Check the numbers of your channel.';
			break;
		}
	}
	if (function_exists('mb_strlen') ? mb_strlen($clean['message'], 'UTF-8') > 1000 : strlen($clean['message']) > 1000) {
		$errors[] = 'The message is too long (1000 characters at most).';
	}
	if (empty($in['agree'])) {
		$errors[] = 'You must promise not to trade accounts or items for real money.';
	}
	if (!$errors && $clean['hours_week'] < $crit['hoursWeek']) {
		$errors[] = array('The program asks for streams or videos of the game at least %d hours a week.', $crit['hoursWeek']);
	}
	if (!$errors && $clean['viewers_avg'] < $crit['viewers'] && $clean['followers'] < $crit['followers']) {
		$errors[] = array('The program asks for at least %d average live viewers or %d followers.', $crit['viewers'], $crit['followers']);
	}
	return array($errors, $clean);
}

/**
 * Limits of the form (the same idea as the password recovery's): one open application per account, 3 applications per
 * account a day, 5 per address an hour (IPv6 by /64). Returns '' when allowed, else the English message.
 */
function chaos_creators_limit(int $accountId, string $ipKey, int $now): string {
	$open = db()->fetchOne("SELECT COUNT(*) AS `n` FROM `chaos_creator_applications` WHERE `account_id` = ? AND `status` = 'new';", [$accountId]);
	if (is_array($open) && (int)$open['n'] > 0) {
		return 'You already have an application waiting for the staff.';
	}
	$day = db()->fetchOne('SELECT COUNT(*) AS `n` FROM `chaos_creator_applications` WHERE `account_id` = ? AND `created_at` >= ?;', [$accountId, $now - 86400]);
	if (is_array($day) && (int)$day['n'] >= 3) {
		return 'Too many applications from this account today. Please try again tomorrow.';
	}
	$ip = db()->fetchOne('SELECT COUNT(*) AS `n` FROM `chaos_creator_applications` WHERE `ip` = ? AND `created_at` >= ?;', [$ipKey, $now - 3600]);
	if (is_array($ip) && (int)$ip['n'] >= 5) {
		return 'Too many applications came from your address. Please try again in an hour.';
	}
	return '';
}

/** Stores an application. Returns [ok, English message, sprintf arguments]; the CSRF check is the page's. */
function chaos_creators_submit(int $accountId, array $in, string $ip, ?int $now = null): array {
	$now = $now ?? time();
	if ($accountId <= 0) {
		return array(false, 'Log in first.');
	}
	if (!chaos_table_exists('chaos_creator_applications')) {
		return array(false, 'Applications are not available right now.');
	}
	$crit = chaos_creators_criteria();
	[$errors, $v] = chaos_creators_validate($in, $crit);
	if ($errors) {
		$first = (array)$errors[0];
		return array(false, (string)$first[0], array_slice($first, 1));
	}
	$mine = db()->fetchOne('SELECT `name` FROM `players` WHERE `account_id` = ? AND `name` = ? LIMIT 1;', [$accountId, $v['character_name']]);
	if (!is_array($mine)) {
		return array(false, 'That character is not on your account.');
	}
	$ipKey = function_exists('chaos_register_ip_key') ? chaos_register_ip_key($ip) : substr($ip, 0, 45);
	$limited = chaos_creators_limit($accountId, $ipKey, $now);
	if ($limited !== '') {
		return array(false, $limited);
	}
	db()->execute("INSERT INTO `chaos_creator_applications` (`account_id`, `character_name`, `platform`, `channel_url`, `hours_week`, `viewers_avg`, `followers`, `message`, `ip`, `status`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'new', ?);",
		[$accountId, (string)$mine['name'], $v['platform'], $v['channel_url'], $v['hours_week'], $v['viewers_avg'], $v['followers'], $v['message'], $ipKey, $now]);
	if (function_exists('chaos_creator_log') && function_exists('chaos_creator_tables_ok') && chaos_creator_tables_ok()) {
		chaos_creator_log(0, $accountId, 'apply', $v['platform'] . ' ' . $v['channel_url']);
	}
	return array(true, 'Thank you. The staff reads your application and answers on the server Discord or by the character.');
}

/** The newest applications for the staff: new ones first. */
function chaos_creators_applications(int $limit = 50): array {
	if (!chaos_table_exists('chaos_creator_applications')) {
		return array();
	}
	return db()->fetchAll("SELECT `a`.`id`, `a`.`account_id`, `a`.`character_name`, `a`.`platform`, `a`.`channel_url`, `a`.`hours_week`, `a`.`viewers_avg`, `a`.`followers`, `a`.`message`, `a`.`status`, `a`.`created_at`, `a`.`reviewed_by`
		FROM `chaos_creator_applications` `a` ORDER BY (`a`.`status` = 'new') DESC, `a`.`id` DESC LIMIT ?;", [$limit]);
}

/** The staff marks an application 'approved' or 'rejected' (the code itself is made in the admin form). */
function chaos_creators_review(int $id, string $status, string $staff, ?int $now = null): array {
	if (!in_array($status, array('approved', 'rejected'), true)) {
		return array(false, 'Unknown action.');
	}
	$row = db()->fetchOne('SELECT `id`, `account_id` FROM `chaos_creator_applications` WHERE `id` = ? LIMIT 1;', [$id]);
	if (!is_array($row)) {
		return array(false, 'No such application.');
	}
	db()->execute('UPDATE `chaos_creator_applications` SET `status` = ?, `reviewed_by` = ?, `reviewed_at` = ? WHERE `id` = ?;',
		[$status, substr($staff, 0, 64), $now ?? time(), $id]);
	if (function_exists('chaos_creator_log') && function_exists('chaos_creator_tables_ok') && chaos_creator_tables_ok()) {
		chaos_creator_log(0, (int)$row['account_id'], 'app-' . substr($status, 0, 8), 'application ' . $id . ' by ' . $staff);
	}
	return array(true, $status === 'approved' ? 'Application approved. Now create the code below.' : 'Application rejected.');
}

/** The streamer kit files the page lists: [folder => [file names]] read from plugins/chaos/assets/streamer (committed, website/tools/gen_streamer_kit.py). */
function chaos_creators_streamer_files(): array {
	$base = __DIR__ . '/assets/streamer';
	$out = array();
	foreach (array('overlays', 'banners', 'discord') as $dir) {
		$names = is_dir($base . '/' . $dir) ? scandir($base . '/' . $dir) : array();
		$out[$dir] = array_values(array_filter((array)$names, static function ($n) { return preg_match('/^[a-z0-9][a-z0-9.-]*\.png$/i', $n) === 1; }));
	}
	return $out;
}

/** The URL of a streamer kit file ('' for a path that is not one of ours). */
function chaos_creators_streamer_url(string $path): string {
	if (!preg_match('#^(overlays|banners|discord)/[a-z0-9][a-z0-9.-]*\.png$#i', $path) && !preg_match('#^obs-overlay\.html$#', $path)) {
		return '';
	}
	return function_exists('znote_plugin_asset') ? (string)znote_plugin_asset('chaos', 'streamer/' . $path) : 'plugins/chaos/assets/streamer/' . $path;
}

/**
 * The numbers the partner guide quotes, from creator_codes_config.lua (chaos_creator_config) and the Discord link
 * (CHAOS_DISCORD_URL, only an https one). Mirrors website/tools/gen_streamer_kit.py code_numbers().
 */
function chaos_creators_guide_numbers(string $lang, string $discord = ''): array {
	$cfg = chaos_creator_config();
	$days = (int)$cfg['launchBonusDays'];
	$dt = DateTimeImmutable::createFromFormat('!Y-m-d H:i', (string)$cfg['launchBonusStart'], new DateTimeZone('America/Sao_Paulo'));
	$pt = $lang === 'pt-BR';
	$fmt = $pt ? 'd/m/Y H:i' : 'd M Y, H:i';
	$discordOk = preg_match('#^https://[^\s<>"\']+$#', $discord) === 1;
	return array(
		'share' => (int)$cfg['sharePct'], 'bonus' => (int)$cfg['launchBonusPct'], 'support' => (int)$cfg['supportDays'], 'hold' => (int)$cfg['holdDays'],
		'orderCap' => (int)$cfg['orderCap'], 'monthlyCap' => (int)$cfg['monthlyCap'], 'bonusDays' => $days,
		'launch' => $dt ? $dt->format($fmt) : '', 'end' => $dt ? $dt->modify('+' . $days . ' days')->format($fmt) : '',
		'discord' => $discordOk ? $discord : ($pt ? 'o link será publicado nesta página' : 'the link will be posted on this page'),
	);
}

/** partner_guide.json in one language with the {tokens} filled: {title, intro, sections: [{id, title, blocks: [[kind, text|[texts]]]}]}. */
function chaos_creators_guide(string $lang, string $discord = ''): array {
	$j = chaos_creators_json('partner_guide.json');
	$nums = chaos_creators_guide_numbers($lang, $discord);
	$fill = static function ($pair) use ($lang, $nums): string {
		return (string)preg_replace_callback('/\{([A-Za-z]+)\}/', static function ($m) use ($nums) {
			return (string)($nums[$m[1]] ?? $m[0]);
		}, chaos_bi($pair, $lang));
	};
	$secs = array();
	foreach ((array)($j['sections'] ?? array()) as $sec) {
		$blocks = array();
		foreach ((array)($sec['blocks'] ?? array()) as $blk) {
			$kind = (string)array_key_first((array)$blk);
			$val = $blk[$kind];
			$blocks[] = in_array($kind, array('ul', 'ol', 'check'), true) ? array($kind, array_map($fill, (array)$val)) : array($kind, $fill($val));
		}
		$secs[] = array('id' => (string)($sec['id'] ?? ''), 'title' => $fill($sec['title'] ?? ''), 'blocks' => $blocks);
	}
	return array('title' => $fill($j['title'] ?? ''), 'intro' => $fill($j['intro'] ?? ''), 'updated' => (string)($j['updated'] ?? ''), 'sections' => $secs);
}
}
