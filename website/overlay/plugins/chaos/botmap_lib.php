<?php
/**
 * The staff's live map of our tester bots (page?plugin=chaos&p=botmap, /chaos_botmap.php; server/README.md "Bot live map (O727)").
 * Reads two things the game server's machine writes into its data folder, and nothing else:
 *   - data/chaos_botlive/<bot>.json: one JSON line a bot (server/tools/bot_live.py, unity/Client/Assets/Chaos/Core/BotLive.cs): name, class,
 *     level, position, goal, why, spot, now, plan, the last 50 log lines. Only our test bots write there ("Tester Xxx").
 *   - data/chaos_botmap.json: where the map tiles are (server/tools/gen_bot_map_tiles.py --pointer): the folder under the site (named with a
 *     secret token, so the world map is not a public file), the geometry of the pyramid, the towns.
 * Access: an admin panel account (chaos_reports_is_admin) with a character of group 4 or higher, as the bot review page; everyone else gets
 * "not found", on the page and on the endpoint. Read only. The answer carries bots only: no account, no password, no address, no player; every
 * value is cut to its limits here again (a bad file shows nothing wrong), and the page script puts it on the screen with textContent.
 * Staleness (the twin of server/tools/bot_live.py): no update for 120 s is "stale" (shown greyed), for 600 s the bot is dropped.
 */

if (!function_exists('chaos_botmap_group')) {

require_once __DIR__ . '/reports_lib.php';

define('CHAOS_BOTMAP_GROUP', 4);          // gamemaster: view
define('CHAOS_BOTMAP_GREY', 120);         // seconds without an update: stale
define('CHAOS_BOTMAP_DROP', 600);         // seconds without an update: gone
define('CHAOS_BOTMAP_MAX_BOTS', 200);
define('CHAOS_BOTMAP_MAX_FILE', 65536);
define('CHAOS_BOTMAP_LOG_MAX', 50);
define('CHAOS_BOTMAP_PLAN_MAX', 8);
define('CHAOS_BOTMAP_POLL_MS', 3000);

/** The staff group of an admin panel account (its highest character group), 0 when it may not use the map. */
function chaos_botmap_group(array $config, int $accountId): int {
	if (!chaos_reports_is_admin($config, $accountId)) {
		return 0;
	}
	$row = db()->fetchOne('SELECT MAX(`group_id`) AS `g` FROM `players` WHERE `account_id` = ?;', [$accountId]);
	$g = is_array($row) ? (int)($row['g'] ?? 0) : 0;
	return $g >= CHAOS_BOTMAP_GROUP ? $g : 0;
}

/** The folder of the bots' files (the game server's data/chaos_botlive), '' without a server data folder. */
function chaos_botmap_dir(): string {
	return chaos_data_path('chaos_botlive');
}

/** 'live' | 'stale' | 'gone' of an entry last updated at $t, seen at $now. */
function chaos_botmap_age_state($t, int $now): string {
	if (!is_int($t) && !is_float($t)) {
		return 'gone';
	}
	$age = $now - $t;
	if ($age > CHAOS_BOTMAP_DROP) {
		return 'gone';
	}
	return $age > CHAOS_BOTMAP_GREY ? 'stale' : 'live';
}

/** One line of text: valid UTF-8, no control characters, runs of spaces folded, cut to $limit characters. */
function chaos_botmap_text($v, int $limit): string {
	if (!is_string($v) && !is_int($v) && !is_float($v)) {
		return '';
	}
	$s = (string)$v;
	if (function_exists('mb_convert_encoding')) {
		$s = (string)mb_convert_encoding($s, 'UTF-8', 'UTF-8');
	}
	$s = preg_replace('/[\x00-\x1f\x7f]+/u', ' ', $s) ?? '';
	$s = trim(preg_replace('/\s+/u', ' ', $s) ?? '');
	return function_exists('mb_substr') ? mb_substr($s, 0, $limit, 'UTF-8') : substr($s, 0, $limit);
}

/** A tester name: "Tester" and three letters (server/tools/tester_core.py NAME_RE). */
function chaos_botmap_is_tester(string $name): bool {
	return (bool)preg_match('/^Tester [A-Z][a-z][a-z]$/', $name);
}

/** The entry of one file as the page gets it, or null when it is not a bot's (or too old). */
function chaos_botmap_clean_entry($e, int $now): ?array {
	if (!is_array($e) || !isset($e['name']) || !is_string($e['name']) || !chaos_botmap_is_tester($e['name'])) {
		return null;
	}
	$t = $e['t'] ?? null;
	$state = chaos_botmap_age_state($t, $now);
	if ($state === 'gone') {
		return null;
	}
	$pos = null;
	if (isset($e['pos']) && is_array($e['pos']) && count($e['pos']) === 3) {
		$p = array_values($e['pos']);
		if (is_int($p[0]) && is_int($p[1]) && is_int($p[2]) && $p[0] >= 0 && $p[0] <= 65535 && $p[1] >= 0 && $p[1] <= 65535 && $p[2] >= 0 && $p[2] <= 15) {
			$pos = $p;
		}
	}
	$plan = array();
	foreach (is_array($e['plan'] ?? null) ? array_slice(array_values($e['plan']), 0, CHAOS_BOTMAP_PLAN_MAX) : array() as $step) {
		$plan[] = chaos_botmap_text($step, 240);
	}
	$log = array();
	$lines = is_array($e['log'] ?? null) ? array_values($e['log']) : array();
	foreach (array_slice($lines, -CHAOS_BOTMAP_LOG_MAX) as $line) {
		if (is_array($line) && count($line) === 2 && is_int($line[0] ?? null)) {
			$log[] = array($line[0], chaos_botmap_text($line[1] ?? '', 160));
		}
	}
	$level = $e['level'] ?? 0;
	$since = $e['goal_since'] ?? 0;
	return array(
		'name' => $e['name'],
		'class' => chaos_botmap_text($e['class'] ?? '', 40),
		'level' => is_int($level) && $level >= 0 && $level <= 99999 ? $level : 0,
		'pos' => $pos,
		'goal' => chaos_botmap_text($e['goal'] ?? '', 60),
		'goal_since' => is_int($since) && $since > 0 ? $since : 0,
		'why' => chaos_botmap_text($e['why'] ?? '', 240),
		'spot' => chaos_botmap_text($e['spot'] ?? '', 240),
		'now' => chaos_botmap_text($e['now'] ?? '', 240),
		'plan' => $plan,
		'log' => $log,
		't' => (int)$t,
		'age' => max(0, $now - (int)$t),
		'state' => $state,
		'src' => ($e['src'] ?? '') === 'cs' ? 'cs' : 'py',
	);
}

/** The bots of the folder: live and stale ones, ordered by name, at most CHAOS_BOTMAP_MAX_BOTS. A missing folder is no bots. */
function chaos_botmap_read(string $dir, int $now): array {
	$out = array();
	if ($dir === '' || !is_dir($dir)) {
		return $out;
	}
	$names = @scandir($dir);
	if (!is_array($names)) {
		return $out;
	}
	sort($names);
	foreach ($names as $f) {
		if ($f === '' || $f[0] === '.' || substr($f, -5) !== '.json' || !preg_match('/^[a-z0-9-]{1,40}\.json$/', $f)) {
			continue;
		}
		$path = $dir . '/' . $f;
		if (!is_file($path) || is_link($path) || !is_readable($path)) {
			continue;
		}
		$text = @file_get_contents($path, false, null, 0, CHAOS_BOTMAP_MAX_FILE + 1);
		if (!is_string($text) || strlen($text) > CHAOS_BOTMAP_MAX_FILE) {
			continue;
		}
		$e = chaos_botmap_clean_entry(json_decode($text, true), $now);
		if ($e !== null) {
			$out[$e['name']] = $e;
			if (count($out) >= CHAOS_BOTMAP_MAX_BOTS) {
				break;
			}
		}
	}
	ksort($out);
	return array_values($out);
}

/**
 * The map pointer of gen_bot_map_tiles.py (data/chaos_botmap.json), checked: the url is a plain relative path, the numbers are numbers. null
 * when there is no map built yet.
 */
function chaos_botmap_pointer(): ?array {
	$text = chaos_read_server_file('chaos_botmap.json');
	$d = $text === '' ? null : json_decode($text, true);
	if (!is_array($d) || ($d['v'] ?? 0) !== 1 || !isset($d['url']) || !is_string($d['url'])
		|| !preg_match('#^[A-Za-z0-9._/-]{1,200}$#', $d['url']) || strpos($d['url'], '..') !== false || $d['url'][0] === '/') {
		return null;
	}
	$origin = $d['origin'] ?? null;
	$bbox = $d['bbox'] ?? null;
	if (!is_array($origin) || count($origin) !== 2 || !is_int($origin[0]) || !is_int($origin[1])
		|| !is_array($bbox) || count($bbox) !== 4 || !isset($d['span0'], $d['maxZoom']) || !is_int($d['span0']) || !is_int($d['maxZoom'])
		|| $d['span0'] < 32 || $d['maxZoom'] < 0 || $d['maxZoom'] > 8) {
		return null;
	}
	$floors = array();
	foreach (is_array($d['floors'] ?? null) ? $d['floors'] : array() as $f) {
		if (is_array($f) && is_int($f['z'] ?? null) && $f['z'] >= 0 && $f['z'] <= 15) {
			$floors[] = array('z' => $f['z'], 'tiles' => (int)($f['tiles'] ?? 0));
		}
	}
	$towns = array();
	foreach (is_array($d['towns'] ?? null) ? $d['towns'] : array() as $t) {
		if (is_array($t) && is_int($t['x'] ?? null) && is_int($t['y'] ?? null) && is_int($t['z'] ?? null)) {
			$towns[] = array('name' => chaos_botmap_text($t['name'] ?? '', 60), 'x' => $t['x'], 'y' => $t['y'], 'z' => $t['z']);
		}
	}
	return array(
		'url' => $d['url'], 'tile' => 256, 'minZoom' => 0, 'maxZoom' => $d['maxZoom'], 'span0' => $d['span0'],
		'origin' => array((int)$origin[0], (int)$origin[1]), 'bbox' => array_map('intval', array_values($bbox)),
		'floors' => $floors, 'towns' => $towns, 'built' => (int)($d['built'] ?? 0),
	);
}

/**
 * The endpoint (chaos_botmap.php): [http code, body array].
 *   a=bots (default)  {ok, now, bots: [...], count, stale}
 *   a=meta            {ok, now, map: pointer or null}
 * Anyone but staff gets 404 {"ok":false,"error":"not_found"}: the same answer as a page that does not exist.
 */
function chaos_botmap_handle(array $config, int $accountId, array $query, int $now): array {
	if (chaos_botmap_group($config, $accountId) <= 0) {
		return array(404, array('ok' => false, 'error' => 'not_found'));
	}
	$a = (string)($query['a'] ?? 'bots');
	if ($a === 'meta') {
		return array(200, array('ok' => true, 'now' => $now, 'map' => chaos_botmap_pointer()));
	}
	if ($a !== 'bots') {
		return array(400, array('ok' => false, 'error' => 'bad_request'));
	}
	$bots = chaos_botmap_read(chaos_botmap_dir(), $now);
	$stale = 0;
	foreach ($bots as $b) {
		$stale += $b['state'] === 'stale' ? 1 : 0;
	}
	return array(200, array('ok' => true, 'now' => $now, 'bots' => $bots, 'count' => count($bots), 'stale' => $stale));
}

}
