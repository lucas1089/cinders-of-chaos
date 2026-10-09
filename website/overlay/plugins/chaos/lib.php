<?php
/**
 * Cinders of Chaos helpers for the website (loaded by plugin.php on every request).
 *
 * Only functions here: no output, no queries at load time. Every query is a
 * prepared statement through ZnoteX's db() helper; nothing is built from
 * request input. Everything printed goes through chaos_h().
 *
 * Settings: $config['chaos'] (written by website/setup/write_config.php into
 * config.local.php). See website/README.md.
 */

if (!function_exists('chaos_h')) {

/** HTML-escape anything for output. */
function chaos_h($value): string {
	return htmlspecialchars((string)$value, ENT_QUOTES, 'UTF-8');
}

/** $config['chaos'] with defaults. */
function chaos_cfg(?string $key = null, $default = null) {
	$cfg = (array)($GLOBALS['config']['chaos'] ?? array());
	$cfg += array(
		'server_data'      => '',                 // the game server's data/ folder (patch notes, Lua settings)
		'game_host'        => '',                 // shown on the downloads page
		'game_port'        => 7171,
		'discord_url'      => '',
		'staff_group'      => 4,                  // leaderboard_config.lua staffGroup
		'staff_account_type' => 5,                // class_unlocks_core.lua bypass.minAccountType
		'base_classes'     => array(4, 3, 1, 11), // offered to every account
		'depot_boxes'      => false,              // the base server's new-player depot boxes (off: they block !season join)
	);
	if ($key === null) {
		return $cfg;
	}
	return array_key_exists($key, $cfg) ? $cfg[$key] : $default;
}

/** A path inside the game server's data folder, or '' when it is not configured. */
function chaos_data_path(string $relative): string {
	$root = rtrim((string)chaos_cfg('server_data', ''), '/\\');
	return $root === '' ? '' : $root . '/' . ltrim($relative, '/');
}

// ---------------------------------------------------------------------------
// Classes (server/data/scripts/chaos/chaos_constants.lua, Chaos.classes)
// ---------------------------------------------------------------------------

/**
 * The class lines: base class id => line. `lock` is the class key of
 * chaos_class_unlocks (class_unlocks_core.lua) or '' for the four open lines.
 */
function chaos_class_lines(): array {
	return array(
		4 => array('name' => 'Warrior', 'lock' => '', 'icon' => 'warrior', 'plays' => 'Melee, heavy armour, the most health.',
			'asc' => array(8 => array('Juggernaut', 'The tank: taunts, damage reduction, block and reflect.'),
				14 => array('Berserker', 'Two-handed area damage; Rage hits harder the lower your health.'))),
		3 => array('name' => 'Ranger', 'lock' => '', 'icon' => 'ranger', 'plays' => 'Bows and crossbows.',
			'asc' => array(7 => array('Deadeye', 'The best single-target damage: crossbows, marks and crits.'),
				15 => array('Beastmaster', 'Fights beside a War Wolf companion that grows with you.'))),
		1 => array('name' => 'Mystic', 'lock' => '', 'icon' => 'mystic', 'plays' => 'Spells, wands and rods.',
			'asc' => array(5 => array('Elementalist', 'The best area damage: fire, ice and energy combos.'),
				10 => array('Illusionist', 'The support: party attack buffs, debuffs and heals.'))),
		11 => array('name' => 'Thief', 'lock' => '', 'icon' => 'thief', 'plays' => 'Fast light weapons, shurikens and stealth.',
			'asc' => array(12 => array('Ninja', 'Dual daggers, Shadow Step and smoke.'),
				13 => array('Samurai', 'One sword, counter stance, Iaijutsu and Bushido.'))),
		17 => array('name' => 'Monk', 'lock' => 'monk', 'icon' => 'monk', 'plays' => 'Unarmed strikes, chi and evasion.',
			'asc' => array(18 => array('Shadowfist', 'Single-target burst from spent chi.'),
				19 => array('Iron Sage', 'Bruiser and support: Chi Ward, stuns and a party aura.'))),
		20 => array('name' => 'Necromancer', 'lock' => 'necromancer', 'icon' => 'necromancer', 'plays' => 'Summoner: skeletons, curses and corpses.',
			'asc' => array(21 => array('Lich', 'Curses, damage over time and life drain.'),
				22 => array('Bone Lord', 'The army: more skeletons, the Bone Golem and an aura.'))),
		23 => array('name' => 'Templar', 'lock' => 'templar', 'icon' => 'templar', 'plays' => 'Holy melee with a shield and a party defence aura.',
			'asc' => array(24 => array('Inquisitor', 'Holy area damage: Judgement and Purging Nova.'),
				25 => array('Sentinel', 'Tank-support: a stronger aura, Rebuke and Lay on Hands.'))),
	);
}

/** Vocation ids retired by the class rework (class_migration.lua): old id => new id. */
function chaos_retired_vocations(): array {
	return array(2 => 1, 6 => 10, 9 => 1);
}

/** Base class id of any class id (Chaos.classes.baseOf), or null. */
function chaos_base_of(int $vocation): ?int {
	$retired = chaos_retired_vocations();
	if (isset($retired[$vocation])) {
		$vocation = $retired[$vocation];
	}
	foreach (chaos_class_lines() as $base => $line) {
		if ($vocation === $base || isset($line['asc'][$vocation])) {
			return $base;
		}
	}
	return null;
}

/** Class name of a vocation id (retired ids show the class they move to). */
function chaos_class_name(int $vocation): string {
	$retired = chaos_retired_vocations();
	if (isset($retired[$vocation])) {
		$vocation = $retired[$vocation];
	}
	foreach (chaos_class_lines() as $base => $line) {
		if ($vocation === $base) {
			return $line['name'];
		}
		if (isset($line['asc'][$vocation])) {
			return $line['asc'][$vocation][0];
		}
	}
	return $vocation === 0 ? 'None' : 'Unknown';
}

/** Every class id of a line (base first). */
function chaos_line_ids(int $base): array {
	$lines = chaos_class_lines();
	if (!isset($lines[$base])) {
		return array();
	}
	return array_merge(array($base), array_keys($lines[$base]['asc']));
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

/** True when the table exists in the game database (cached per request). */
function chaos_table_exists(string $table): bool {
	static $known = array();
	if (!isset($known[$table])) {
		$row = db()->fetchOne('SELECT COUNT(*) AS `n` FROM `information_schema`.`tables` WHERE `table_schema` = DATABASE() AND `table_name` = ?;', [$table]);
		$known[$table] = is_array($row) && (int)($row['n'] ?? 0) > 0;
	}
	return $known[$table];
}

/** Rows of a prepared SELECT, always an array. */
function chaos_rows(string $sql, array $params = array()): array {
	$rows = db()->fetchAll($sql, $params);
	return is_array($rows) ? $rows : array();
}

// ---------------------------------------------------------------------------
// Class lock (class_unlocks_core.lua, table chaos_class_unlocks)
// ---------------------------------------------------------------------------

/** Class keys the account has unlocked ("necromancer", "monk", "templar"). */
function chaos_unlocked_class_keys(int $accountId): array {
	if ($accountId <= 0 || !chaos_table_exists('chaos_class_unlocks')) {
		return array();
	}
	$keys = array();
	foreach (chaos_rows('SELECT `class_key` FROM `chaos_class_unlocks` WHERE `account_id` = ?;', [$accountId]) as $row) {
		$keys[] = (string)$row['class_key'];
	}
	return $keys;
}

/** Staff accounts never meet the lock (class_unlocks_core.lua bypass.minAccountType). */
function chaos_account_is_staff(int $accountId): bool {
	if ($accountId <= 0) {
		return false;
	}
	$row = db()->fetchOne('SELECT `type` FROM `accounts` WHERE `id` = ? LIMIT 1;', [$accountId]);
	return is_array($row) && (int)($row['type'] ?? 0) >= (int)chaos_cfg('staff_account_type', 5);
}

/**
 * The base classes an account may create: the four open ones, plus each
 * locked line the account has unlocked. This is what createcharacter.php
 * validates against (through $config['available_vocations']).
 */
function chaos_creatable_classes(int $accountId): array {
	$open = array_map('intval', (array)chaos_cfg('base_classes', array(4, 3, 1, 11)));
	$unlocked = chaos_unlocked_class_keys($accountId);
	$staff = chaos_account_is_staff($accountId);
	foreach (chaos_class_lines() as $base => $line) {
		if ($line['lock'] !== '' && ($staff || in_array($line['lock'], $unlocked, true))) {
			$open[] = $base;
		}
	}
	return array_values(array_unique($open));
}

// ---------------------------------------------------------------------------
// Lua settings files of the server (read-only, for names and dates)
// ---------------------------------------------------------------------------

/** Text of a file under server_data, or '' (missing, unreadable, unconfigured). */
function chaos_read_server_file(string $relative): string {
	$path = chaos_data_path($relative);
	if ($path === '' || !is_file($path) || !is_readable($path)) {
		return '';
	}
	return (string)file_get_contents($path);
}

/** The body of `name = { ... }` in a Lua table text (balanced braces), or ''. */
function chaos_lua_block(string $text, string $name): string {
	if (!preg_match('/\b' . preg_quote($name, '/') . '\s*=\s*\{/', $text, $m, PREG_OFFSET_CAPTURE)) {
		return '';
	}
	$start = $m[0][1] + strlen($m[0][0]);
	$depth = 1;
	$len = strlen($text);
	for ($i = $start; $i < $len; $i++) {
		$c = $text[$i];
		if ($c === '"') {
			$end = strpos($text, '"', $i + 1);
			$i = ($end === false) ? $len : $end;
		} elseif ($c === '-' && substr($text, $i, 2) === '--') {
			$end = strpos($text, "\n", $i);
			$i = ($end === false) ? $len : $end;
		} elseif ($c === '{') {
			$depth++;
		} elseif ($c === '}') {
			$depth--;
			if ($depth === 0) {
				return substr($text, $start, $i - $start);
			}
		}
	}
	return '';
}

/** The top-level `{ ... }` entries of a Lua list body. */
function chaos_lua_entries(string $body): array {
	$out = array();
	$depth = 0;
	$from = 0;
	$len = strlen($body);
	for ($i = 0; $i < $len; $i++) {
		$c = $body[$i];
		if ($c === '"') {
			$end = strpos($body, '"', $i + 1);
			$i = ($end === false) ? $len : $end;
		} elseif ($c === '-' && substr($body, $i, 2) === '--') {
			$end = strpos($body, "\n", $i);
			$i = ($end === false) ? $len : $end;
		} elseif ($c === '{') {
			if ($depth === 0) {
				$from = $i + 1;
			}
			$depth++;
		} elseif ($c === '}') {
			$depth--;
			if ($depth === 0) {
				$out[] = substr($body, $from, $i - $from);
			}
		}
	}
	return $out;
}

/** A `key = "string"` or `key = number` field of a Lua entry. */
function chaos_lua_field(string $entry, string $key) {
	if (preg_match('/\b' . preg_quote($key, '/') . '\s*=\s*"((?:[^"\\\\]|\\\\.)*)"/', $entry, $m)) {
		return stripcslashes($m[1]);
	}
	if (preg_match('/\b' . preg_quote($key, '/') . '\s*=\s*(-?[0-9.]+)/', $entry, $m)) {
		return $m[1] + 0;
	}
	return null;
}

// ---------------------------------------------------------------------------
// Leaderboards (leaderboard_config.lua, tables chaos_leaderboard*)
// ---------------------------------------------------------------------------

/** The weekly boards: key => {name, value, count, title, info}. */
function chaos_leaderboard_boards(): array {
	$boards = array(
		'worldboss' => array('name' => 'World Boss', 'value' => 'Damage', 'count' => 'Kills', 'title' => 'Bossbane', 'info' => 'Damage dealt to world bosses this week.'),
		'bounty'    => array('name' => 'Bounty Hunter', 'value' => 'Contracts', 'count' => '', 'title' => 'Warden of the Hunt', 'info' => 'Bounty contracts completed this week.'),
		'rift'      => array('name' => 'Rifts', 'value' => 'Highest Tier', 'count' => 'Runs', 'title' => 'Riftwalker', 'info' => 'Highest rift tier completed this week.'),
		'goblin'    => array('name' => 'Goblin Slayer', 'value' => 'Goblins', 'count' => '', 'title' => 'Goblin Slayer', 'info' => 'Treasure goblins slain this week.'),
		'siege'     => array('name' => 'Guild Siege', 'value' => 'Points', 'count' => '', 'title' => 'Siegebreaker', 'info' => 'Guild siege points this week.'),
		'arena1v1'  => array('name' => 'Arena 1v1', 'value' => 'Rating', 'count' => '', 'title' => 'Duelist', 'info' => 'Best 1v1 arena rating reached this week.'),
		'arena2v2'  => array('name' => 'Arena 2v2', 'value' => 'Rating', 'count' => '', 'title' => 'Gladiator', 'info' => 'Best 2v2 arena rating reached this week.'),
	);
	// The server's own list wins when its settings file is readable (new boards, renamed titles).
	$body = chaos_lua_block(chaos_read_server_file('scripts/chaos/leaderboard_config.lua'), 'boards');
	if ($body !== '') {
		$read = array();
		foreach (chaos_lua_entries($body) as $entry) {
			$key = chaos_lua_field($entry, 'key');
			if (!is_string($key) || !preg_match('/^[a-z0-9_]{1,16}$/', $key)) {
				continue;
			}
			$read[$key] = array(
				'name'  => (string)(chaos_lua_field($entry, 'name') ?? $key),
				'value' => (string)(chaos_lua_field($entry, 'value') ?? 'Score'),
				'count' => (string)(chaos_lua_field($entry, 'count') ?? ''),
				'title' => (string)(chaos_lua_field($entry, 'title') ?? ''),
				'info'  => (string)(chaos_lua_field($entry, 'info') ?? ''),
			);
		}
		if ($read) {
			$boards = $read;
		}
	}
	return $boards;
}

/**
 * Week key (YYYYMMDD of the Monday) of a time: the weekly boards reset on
 * Monday at `hour` server time (ChaosBounty.week with the leaderboard's resetHour).
 */
function chaos_week_key(int $time, int $hour = 6): int {
	$t = $time - $hour * 3600;
	$back = ((int)date('N', $t)) - 1; // Monday = 0 ... Sunday = 6
	return (int)date('Ymd', mktime(12, 0, 0, (int)date('n', $t), (int)date('j', $t) - $back, (int)date('Y', $t)));
}

/** Human date of a week key. */
function chaos_week_label(int $week): string {
	$y = intdiv($week, 10000);
	$m = intdiv($week, 100) % 100;
	$d = $week % 100;
	return checkdate($m, $d, $y) ? date('j M Y', mktime(12, 0, 0, $m, $d, $y)) : (string)$week;
}

/** Top rows of a weekly board (staff left out, ties: who got there first, then the lower id). */
function chaos_leaderboard_rows(string $board, int $week, int $limit = 20): array {
	if (!chaos_table_exists('chaos_leaderboard')) {
		return array();
	}
	return chaos_rows('
		SELECT `p`.`name`, `p`.`vocation`, `p`.`level`, `l`.`value`, `l`.`count`
		FROM `chaos_leaderboard` `l`
		JOIN `players` `p` ON `p`.`id` = `l`.`player_id`
		WHERE `l`.`board` = ? AND `l`.`week` = ? AND `l`.`value` > 0 AND `p`.`group_id` < ?
		ORDER BY `l`.`value` DESC, `l`.`updated_at` ASC, `l`.`player_id` ASC
		LIMIT ?;', [$board, $week, (int)chaos_cfg('staff_group', 4), $limit]);
}

/** The title holders of the most recent scored week: [week, rows]. */
function chaos_leaderboard_titles(): array {
	if (!chaos_table_exists('chaos_leaderboard_titles')) {
		return array(0, array());
	}
	$row = db()->fetchOne('SELECT MAX(`week`) AS `w` FROM `chaos_leaderboard_titles`;');
	$week = is_array($row) ? (int)($row['w'] ?? 0) : 0;
	if ($week <= 0) {
		return array(0, array());
	}
	return array($week, chaos_rows('
		SELECT `t`.`board`, `t`.`rank`, `t`.`title`, `t`.`value`, `p`.`name`, `p`.`vocation`
		FROM `chaos_leaderboard_titles` `t`
		JOIN `players` `p` ON `p`.`id` = `t`.`player_id`
		WHERE `t`.`week` = ?
		ORDER BY `t`.`board`, `t`.`rank`;', [$week]));
}

/** Class Ladder: the highest characters of one class line. */
function chaos_class_ladder(int $base, int $limit = 10, int $season = 0): array {
	$ids = chaos_line_ids($base);
	if (!$ids) {
		return array();
	}
	if ($base === 1 || $base === 10) {
		$ids = array_merge($ids, array(2, 6, 9)); // not yet migrated (class_migration.lua runs at the next server start)
	}
	$in = implode(',', array_fill(0, count($ids), '?'));
	$params = array_merge($ids, array((int)chaos_cfg('staff_group', 4)));
	$join = '';
	if ($season > 0) {
		if (!chaos_table_exists('chaos_season_players')) {
			return array();
		}
		$join = 'JOIN `chaos_season_players` `s` ON `s`.`player_id` = `p`.`id` AND `s`.`season` = ?';
		array_unshift($params, $season);
	}
	$params[] = $limit;
	return chaos_rows("
		SELECT `p`.`name`, `p`.`level`, `p`.`vocation`, `p`.`experience`
		FROM `players` `p` $join
		WHERE `p`.`vocation` IN ($in) AND `p`.`group_id` < ? AND `p`.`deletion` = 0
		ORDER BY `p`.`experience` DESC, `p`.`id` ASC
		LIMIT ?;", $params);
}

// ---------------------------------------------------------------------------
// Seasons (season_config.lua, tables chaos_season_*)
// ---------------------------------------------------------------------------

/** Unix time of a season date: YYYYMMDD at `hour`, or a unix time. */
function chaos_season_time($value, int $hour): int {
	$v = (int)$value;
	if ($v >= 19000101 && $v <= 29991231) {
		return (int)mktime($hour, 0, 0, intdiv($v, 100) % 100, $v % 100, intdiv($v, 10000));
	}
	return $v;
}

/** The seasons of season_config.lua, with the /season start|end overrides of server_config. */
function chaos_seasons(): array {
	$text = chaos_read_server_file('scripts/chaos/season_config.lua');
	$seasons = array();
	foreach (chaos_lua_entries(chaos_lua_block($text, 'seasons')) as $entry) {
		$id = (int)(chaos_lua_field($entry, 'id') ?? 0);
		if ($id <= 0) {
			continue;
		}
		$hour = (int)(chaos_lua_field($entry, 'hour') ?? 0);
		$mod = chaos_lua_block($entry, 'modifier');
		$seasons[$id] = array(
			'id'       => $id,
			'name'     => (string)(chaos_lua_field($entry, 'name') ?? ('Season ' . $id)),
			'tag'      => (string)(chaos_lua_field($entry, 'tag') ?? ('[S' . $id . ']')),
			'start'    => chaos_season_time(chaos_lua_field($entry, 'start') ?? 0, $hour),
			'finish'   => chaos_season_time(chaos_lua_field($entry, 'finish') ?? 0, $hour),
			'modifier' => $mod !== '' ? (string)(chaos_lua_field($mod, 'name') ?? '') : '',
			'modifier_text' => $mod !== '' ? (string)(chaos_lua_field($mod, 'description') ?? '') : '',
		);
	}
	if ($seasons && chaos_table_exists('server_config')) {
		foreach (chaos_rows("SELECT `config`, `value` FROM `server_config` WHERE `config` LIKE 'chaos\\_season\\_%';") as $row) {
			if (preg_match('/^chaos_season_(\d+)_(start|end)$/', (string)$row['config'], $m) && isset($seasons[(int)$m[1]])) {
				$seasons[(int)$m[1]][$m[2] === 'start' ? 'start' : 'finish'] = (int)$row['value'];
			}
		}
	}
	ksort($seasons);
	return $seasons;
}

/** The reward track of season_config.lua: list of {name, reward}. */
function chaos_season_track(): array {
	$out = array();
	$text = chaos_read_server_file('scripts/chaos/season_config.lua');
	foreach (chaos_lua_entries(chaos_lua_block($text, 'track')) as $entry) {
		$name = chaos_lua_field($entry, 'name');
		$reward = chaos_lua_block($entry, 'reward');
		if (!is_string($name)) {
			continue;
		}
		$kind = (string)(chaos_lua_field($reward, 'kind') ?? '');
		$what = $kind === 'title' ? 'Title: ' . (string)chaos_lua_field($reward, 'title') : (string)(chaos_lua_field($reward, 'name') ?? $kind);
		$out[] = array('name' => $name, 'reward' => $what);
	}
	return $out;
}

// ---------------------------------------------------------------------------
// Patch notes (server/data/patchnotes/*.md, rules of patchnotes_core.lua)
// ---------------------------------------------------------------------------

function chaos_pn_limits(): array {
	return array('title' => 80, 'text' => 700, 'items' => 60, 'sections' => 12, 'intro' => 6, 'list' => 52);
}

function chaos_pn_kind(string $name): string {
	$kinds = array(
		'new' => 'new', 'added' => 'new', 'new features' => 'new',
		'changes' => 'changes', 'changed' => 'changes', 'change' => 'changes',
		'fixes' => 'fixes', 'fixed' => 'fixes', 'fix' => 'fixes', 'bug fixes' => 'fixes',
		'balance' => 'balance', 'balancing' => 'balance',
	);
	return $kinds[strtolower($name)] ?? 'other';
}

function chaos_pn_cut(string $s, int $n): string {
	return strlen($s) <= $n ? $s : substr($s, 0, $n - 3) . '...';
}

/** Inline markers out (**, __, backticks, [text](link)), spaces squeezed. */
function chaos_pn_clean(string $s): string {
	$s = preg_replace('/\*\*(.*?)\*\*/s', '$1', $s);
	$s = preg_replace('/__(.*?)__/s', '$1', $s);
	$s = preg_replace('/`(.*?)`/s', '$1', $s);
	$s = preg_replace('/\[(.*?)\]\((.*?)\)/s', '$1', $s);
	$s = preg_replace('/\s+/', ' ', $s);
	return trim($s);
}

/** A bullet; a bold start ("**Lead.** text") becomes its highlighted lead. */
function chaos_pn_item(string $bullet, int $level): array {
	if (preg_match('/^\*\*(.*?)\*\*\s*(.*)$/s', $bullet, $m) && chaos_pn_clean($m[1]) !== '') {
		return array('lead' => chaos_pn_clean($m[1]), 'text' => chaos_pn_clean($m[2]), 'level' => $level);
	}
	return array('lead' => '', 'text' => chaos_pn_clean($bullet), 'level' => $level);
}

/** One notes file -> {id, title, date, intro: [lines], sections: [{name, kind, items: [{text, lead, level}]}]}. */
function chaos_pn_parse(string $text, string $id): array {
	$lim = chaos_pn_limits();
	$note = array('id' => $id, 'title' => null, 'date' => null, 'intro' => array(), 'sections' => array());
	$sec = null;     // index into sections
	$item = null;    // reference path: array('intro', i) or array('sec', s, i)
	$inComment = false;
	$text = str_replace(array("\r\n", "\r"), "\n", $text);
	if (substr($text, 0, 3) === "\xEF\xBB\xBF") {
		$text = substr($text, 3);
	}
	foreach (explode("\n", $text) as $raw) {
		$line = str_replace("\t", '    ', $raw);
		if ($inComment) {
			$e = strpos($line, '-->');
			if ($e !== false) {
				$inComment = false;
				$line = substr($line, $e + 3);
			} else {
				$line = '';
			}
		}
		$line = preg_replace('/<!--.*?-->/', '', $line);
		$s = strpos($line, '<!--');
		if ($s !== false) {
			$inComment = true;
			$line = substr($line, 0, $s);
		}
		$body = trim($line);
		preg_match('/^( *)/', $line, $im);
		$indent = strlen($im[1]);
		if ($body === '') {
			$item = null;
		} elseif (preg_match('/^#[^#]/', $body) && $note['title'] === null) {
			$note['title'] = chaos_pn_cut(chaos_pn_clean(substr($body, 1)), $lim['title']);
			$item = null;
		} elseif (preg_match('/^##+/', $body)) {
			$name = chaos_pn_clean(preg_replace('/^#+/', '', $body));
			if (count($note['sections']) < $lim['sections'] && $name !== '') {
				$note['sections'][] = array('name' => chaos_pn_cut($name, $lim['title']), 'kind' => chaos_pn_kind($name), 'items' => array());
				$sec = count($note['sections']) - 1;
			} else {
				$sec = null;
			}
			$item = null;
		} elseif ($sec === null && $note['date'] === null && preg_match('/^date\s*:/i', $body)) {
			$d = trim(substr($body, strpos($body, ':') + 1));
			if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $d)) {
				$note['date'] = $d;
			}
		} elseif (preg_match('/^[-*+]\s+(.*)$/', $body, $bm)) {
			if ($sec !== null) {
				if (count($note['sections'][$sec]['items']) < $lim['items']) {
					$note['sections'][$sec]['items'][] = chaos_pn_item($bm[1], $indent >= 2 ? 2 : 1);
					$item = array('sec', $sec, count($note['sections'][$sec]['items']) - 1);
				} else {
					$item = null;
				}
			} elseif (count($note['intro']) < $lim['intro']) {
				$note['intro'][] = chaos_pn_clean($bm[1]);
				$item = array('intro', count($note['intro']) - 1);
			} else {
				$item = null;
			}
		} elseif ($item !== null) {
			if ($item[0] === 'intro') {
				$note['intro'][$item[1]] = chaos_pn_clean($note['intro'][$item[1]] . ' ' . $body);
			} else {
				$cur = &$note['sections'][$item[1]]['items'][$item[2]];
				$cur['text'] = chaos_pn_clean($cur['text'] . ' ' . $body);
				unset($cur);
			}
		} elseif ($sec !== null) {
			if (count($note['sections'][$sec]['items']) < $lim['items']) {
				$note['sections'][$sec]['items'][] = array('lead' => '', 'text' => chaos_pn_clean($body), 'level' => 0);
				$item = array('sec', $sec, count($note['sections'][$sec]['items']) - 1);
			}
		} elseif (count($note['intro']) < $lim['intro']) {
			$note['intro'][] = chaos_pn_clean($body);
			$item = array('intro', count($note['intro']) - 1);
		}
	}
	foreach ($note['sections'] as &$section) {
		foreach ($section['items'] as &$it) {
			$it['text'] = chaos_pn_cut($it['text'], $lim['text']);
		}
		unset($it);
	}
	unset($section);
	foreach ($note['intro'] as $i => $l) {
		$note['intro'][$i] = chaos_pn_cut($l, $lim['text']);
	}
	if ($note['date'] === null && preg_match('/^(\d{4}-\d{2}-\d{2})/', $id, $dm)) {
		$note['date'] = $dm[1];
	}
	if ($note['title'] === null) {
		$note['title'] = $note['date'] !== null ? 'Patch notes ' . $note['date'] : $id;
	}
	$note['sections'] = array_values(array_filter($note['sections'], static function ($s) {
		return is_array($s) && count($s['items']) > 0;
	}));
	return $note;
}

/** A file id is safe to look up (patchnotes_core.lua validId). */
function chaos_pn_valid_id(string $id): bool {
	return strlen($id) >= 1 && strlen($id) <= 48 && preg_match('/^[A-Za-z0-9][A-Za-z0-9\-._]*$/', $id) === 1;
}

/** Every note of the patch notes folder, parsed, newest first (date, then id). */
function chaos_patchnotes(): array {
	$dir = chaos_data_path('patchnotes');
	if ($dir === '' || !is_dir($dir)) {
		return array();
	}
	$notes = array();
	foreach ((array)scandir($dir) as $name) {
		$name = (string)$name;
		if (strtolower(substr($name, -3)) !== '.md' || strtolower($name) === 'readme.md' || $name[0] === '_') {
			continue;
		}
		$id = substr($name, 0, -3);
		if (!chaos_pn_valid_id($id) || !is_file($dir . '/' . $name)) {
			continue;
		}
		$notes[] = chaos_pn_parse((string)file_get_contents($dir . '/' . $name), $id);
	}
	usort($notes, static function (array $a, array $b): int {
		return strcmp(($b['date'] ?? '0000-00-00') . '|' . $b['id'], ($a['date'] ?? '0000-00-00') . '|' . $a['id']);
	});
	return array_slice($notes, 0, chaos_pn_limits()['list']);
}

/** Render one parsed note as HTML (escaped). */
function chaos_pn_render(array $note): string {
	$html = '<article class="chaos-pn">';
	$html .= '<h2 class="chaos-pn__title">' . chaos_h($note['title']) . '</h2>';
	if (!empty($note['date'])) {
		$html .= '<div class="chaos-pn__date">' . chaos_h($note['date']) . '</div>';
	}
	foreach ($note['intro'] as $line) {
		$html .= '<p class="chaos-pn__intro">' . chaos_h($line) . '</p>';
	}
	foreach ($note['sections'] as $section) {
		$html .= '<section class="chaos-pn__section chaos-pn--' . chaos_h($section['kind']) . '">';
		$html .= '<h3>' . chaos_h($section['name']) . '</h3><ul>';
		foreach ($section['items'] as $it) {
			$cls = $it['level'] === 2 ? 'sub' : ($it['level'] === 0 ? 'para' : 'bullet');
			$html .= '<li class="chaos-pn__' . $cls . '">';
			if ($it['lead'] !== '') {
				$html .= '<strong class="chaos-pn__lead">' . chaos_h($it['lead']) . '</strong> ';
			}
			$html .= chaos_h($it['text']) . '</li>';
		}
		$html .= '</ul></section>';
	}
	return $html . '</article>';
}

} // function_exists guard
