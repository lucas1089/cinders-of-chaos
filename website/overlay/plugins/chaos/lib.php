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

/**
 * The clean address of a link to a top-level page (README "Web server"): "highscores.php?x=1" -> "highscores?x=1",
 * "/page?p=rules" -> "/page?p=rules", "index.php" -> "./". Anything else is returned as it is: other sites,
 * folders, and the machine endpoints the game client and the payment providers call by their .php address.
 */
function chaos_clean_url(string $url): string {
	if (!preg_match('~^(/?)([A-Za-z0-9_-]+)\.php([?#].*)?$~s', $url, $m)
			|| in_array($m[2], array('chaos_client_api', 'chaos_pay_webhook', 'chaos_outfit'), true)) {
		return $url;
	}
	$rest = $m[3] ?? '';
	if ($m[2] === 'index') {
		return ($m[1] === '/' ? '/' : './') . $rest;
	}
	return $m[1] . $m[2] . $rest;
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
		'depot_boxes'      => false,              // the base server's new-player depot boxes (off: they block joining a season)
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

/**
 * Stock ZnoteX pages this server does not use (website/README.md "Not used on this server"): root script => what
 * pages/notused.php explains. plugin.php sends a request for one of them there. The store is in the game and
 * donations are the Donate page; creatures and spells are in the client; there is no forum.
 * The stock payment callbacks (PayGol, PayPal IPN, PagSeguro, the stock webhook) are off too: our donations have
 * their own webhook (chaos_pay_webhook.php). pagseguro_retorno.php and payment_webhook.php do not load plugins, so
 * patches/znotex-chaos-unused-callbacks.patch stops those two itself.
 */
function chaos_unused_pages(): array {
	return array(
		'shop.php' => 'store', 'buypoints.php' => 'store', 'payment.php' => 'store',
		'paygol_ipn.php' => 'store', 'ipn.php' => 'store', 'pagseguro_ipn.php' => 'store',
		'pagseguro_retorno.php' => 'store', 'payment_webhook.php' => 'store',
		'creatures.php' => 'creatures', 'spells.php' => 'spells',
		'forum.php' => 'forum', 'forum_search.php' => 'forum',
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

/**
 * The class look a character of this class and sex wears (class_looks_core.lua: L.looks with the pair switches
 * L.PAIR19_LOOKS / L.PAIR20_LOOKS and their lists), or null (no server data, unknown class). Sex 0 = female.
 * New characters get it at creation (plugin.php), so the character list shows the class's look before the first
 * login; the game server puts the same look on at that login (class_looks.lua).
 */
function chaos_class_look(int $vocation, int $sex): ?int {
	$text = chaos_read_server_file('scripts/chaos/class_looks_core.lua');
	if ($text === '') {
		return null;
	}
	$table = static function (string $name) use ($text): array {
		$out = array();
		if (preg_match_all('/\[(\d+)\]\s*=\s*\{([^{}]*)\}/', chaos_lua_block($text, $name), $m, PREG_SET_ORDER)) {
			foreach ($m as $e) {
				$out[(int)$e[1]] = array('male' => (int)(chaos_lua_field($e[2], 'male') ?? 0), 'female' => (int)(chaos_lua_field($e[2], 'female') ?? 0));
			}
		}
		return $out;
	};
	$pick = $table('looks')[$vocation] ?? null;
	foreach (array(19, 20) as $pair) {
		$swap = $table('pair' . $pair . 'Looks')[$vocation] ?? null;
		if ($swap !== null && preg_match('/^L\.PAIR' . $pair . '_LOOKS\s*=\s*true\b/m', $text)) {
			$pick = $swap;
			break;
		}
	}
	if ($pick === null) {
		return null;
	}
	$look = $sex === 0 ? $pick['female'] : $pick['male'];
	return $look > 0 ? $look : null;
}

/**
 * The start colours of a class (class_looks_core.lua L.startColors: head, body, legs, feet), or null. A new character
 * wears them with its class look: the website's old starter colours (head 78, body 68: yellow and blue) made the
 * Ranger's hooded archer look like a blue-robed mage (owner report 2026-10-16).
 */
function chaos_class_colors(int $vocation): ?array {
	$text = chaos_read_server_file('scripts/chaos/class_looks_core.lua');
	if ($text === '' || !preg_match('/^\s*\[' . $vocation . '\]\s*=\s*\{head = (\d+), body = (\d+), legs = (\d+), feet = (\d+)\}/m',
			chaos_lua_block($text, 'startColors'), $m)) {
		return null;
	}
	return array('head' => (int)$m[1], 'body' => (int)$m[2], 'legs' => (int)$m[3], 'feet' => (int)$m[4]);
}

/** Puts the class look on a new character (by name): look type of its class and sex, both addons (ChaosClassLooks.ADDONS), the class's start colours. */
function chaos_apply_class_look(string $name): bool {
	$row = $name === '' ? false : db()->fetchOne('SELECT `id`, `vocation`, `sex` FROM `players` WHERE `name` = ? LIMIT 1;', [$name]);
	if (!is_array($row)) {
		return false;
	}
	$look = chaos_class_look((int)$row['vocation'], (int)$row['sex']);
	if ($look === null) {
		return false;
	}
	db()->execute('UPDATE `players` SET `looktype` = ?, `lookaddons` = 3 WHERE `id` = ?;', [$look, (int)$row['id']]);
	$colors = chaos_class_colors((int)$row['vocation']);
	if ($colors !== null) {
		db()->execute('UPDATE `players` SET `lookhead` = ?, `lookbody` = ?, `looklegs` = ?, `lookfeet` = ? WHERE `id` = ?;',
			[$colors['head'], $colors['body'], $colors['legs'], $colors['feet'], (int)$row['id']]);
	}
	return true;
}

/**
 * What a new character of a class starts with (server data/scripts/chaos/start_stats.lua, the one source of truth of
 * every creation path: this site, the client's API, the Linux add-account.sh and the game server's one-time login
 * correction): level and experience (startLevel / startExperience, level 8 since the owner's design of 2026-10-16) and
 * the class's health, mana, capacity (oz) and soul at that level (its level 1 row plus a level's gains per level above
 * 1). Null without the server data or for an unknown class. The file keeps one row per line.
 */
function chaos_start_stats(int $vocation): ?array {
	$text = chaos_read_server_file('scripts/chaos/start_stats.lua');
	if ($text === '' || !preg_match('/^\s*\[' . $vocation . '\]\s*=\s*\{health = (\d+), mana = (\d+), cap = (\d+), soul = (\d+), gainhp = (\d+), gainmana = (\d+), gaincap = (\d+)\}/m', $text, $m)) {
		return null;
	}
	$level = preg_match('/^\s*startLevel\s*=\s*(\d+)/m', $text, $l) ? max(1, (int)$l[1]) : 1;
	$up = $level - 1;
	$experience = preg_match('/^\s*startExperience\s*=\s*(\d+)/m', $text, $e) ? (int)$e[1]
		: intdiv(50 * $up * $up * $up - 150 * $up * $up + 400 * $up, 3);
	return array('level' => $level, 'experience' => $experience,
		'health' => (int)$m[1] + $up * (int)$m[5], 'mana' => (int)$m[2] + $up * (int)$m[6],
		'cap' => (int)$m[3] + $up * (int)$m[7], 'soul' => (int)$m[4]);
}

/**
 * Puts its class's start on a new character (by name): the start level and its experience, health, mana, capacity and
 * soul of start_stats.lua instead of ZnoteX's flat $config['player']['base'] (level 1, 150 health, 0 mana, 400 cap for
 * every class). Only a character below the start level (one just created). The game server gives the full starter kit
 * at its first login, in the login event (items with the server's own attributes, which this site does not write).
 */
function chaos_apply_start_stats(string $name): bool {
	$row = $name === '' ? false : db()->fetchOne('SELECT `id`, `vocation`, `level` FROM `players` WHERE `name` = ? LIMIT 1;', [$name]);
	if (!is_array($row)) {
		return false;
	}
	$stats = chaos_start_stats((int)$row['vocation']);
	if ($stats === null || (int)$row['level'] >= $stats['level'] && $stats['level'] > 1) {
		return false;
	}
	db()->execute('UPDATE `players` SET `level` = ?, `experience` = ?, `health` = ?, `healthmax` = ?, `mana` = ?, `manamax` = ?, `cap` = ?, `soul` = ? WHERE `id` = ?;',
		[$stats['level'], $stats['experience'], $stats['health'], $stats['health'], $stats['mana'], $stats['mana'], $stats['cap'], $stats['soul'], (int)$row['id']]);
	return true;
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

/**
 * Accounts held off the boards pending an anti-bot review (chaos_antibot_holds, written by the game server's
 * antibot.lua only with log.holdLeaderboards = true): SQL that leaves them out, for the players table alias `p`.
 */
function chaos_antibot_hold_sql(): string {
	if (!chaos_table_exists('chaos_antibot_holds')) {
		return '';
	}
	return ' AND NOT EXISTS (SELECT 1 FROM `chaos_antibot_holds` `h` WHERE `h`.`account_id` = `p`.`account_id` AND `h`.`cleared_at` = 0)';
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
// Character slots (pact_config.lua `characters`, table chaos_account_extras)
// ---------------------------------------------------------------------------

/** {free, maxExtra} from the server's pact_config.lua, with these defaults when it is not readable. */
function chaos_character_slot_config(): array {
	$out = array('free' => 5, 'maxExtra' => 10);
	$body = chaos_lua_block(chaos_read_server_file('scripts/chaos/pact_config.lua'), 'characters');
	if ($body !== '') {
		foreach (array('free', 'maxExtra') as $key) {
			$v = chaos_lua_field($body, $key);
			if (is_int($v) || (is_float($v) && $v == (int)$v)) {
				$out[$key] = max(0, (int)$v);
			}
		}
	}
	return $out;
}

/** Pure: free + bought slots (at most maxExtra) + slots granted to older accounts (charSlotsLegacy). */
function chaos_character_limit_of(array $slotConfig, int $bought, int $legacy): int {
	return (int)$slotConfig['free'] + min(max(0, $bought), (int)$slotConfig['maxExtra']) + max(0, $legacy);
}

/**
 * Characters the account may have: the same number the game server allows at login (pact.lua). Bought in the store
 * ("Character Slot"); createcharacter.php compares it with the account's character count.
 */
function chaos_character_limit(int $accountId): int {
	$slots = chaos_character_slot_config();
	$bought = 0;
	$legacy = 0;
	if ($accountId > 0 && chaos_table_exists('chaos_account_extras')) {
		foreach (chaos_rows("SELECT `extra_key`, `amount` FROM `chaos_account_extras` WHERE `account_id` = ? AND `extra_key` IN ('charSlots', 'charSlotsLegacy');", [$accountId]) as $row) {
			if ($row['extra_key'] === 'charSlots') {
				$bought = (int)$row['amount'];
			} else {
				$legacy = (int)$row['amount'];
			}
		}
	}
	return chaos_character_limit_of($slots, $bought, $legacy);
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

/** A `key = true|false` field of a Lua entry (missing or anything else: false). */
function chaos_lua_bool(string $entry, string $key): bool {
	return (bool)preg_match('/\b' . preg_quote($key, '/') . '\s*=\s*true\b/', $entry);
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
				// mode "min": the lowest value ranks first (fastest kills); format "time": seconds shown as m:ss
				'mode'   => (string)(chaos_lua_field($entry, 'mode') ?? 'add'),
				'format' => (string)(chaos_lua_field($entry, 'format') ?? ''),
				// byClass: class tabs, as in the client (the Cinderheart fastest kills)
				'byClass' => chaos_lua_bool($entry, 'byClass'),
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

/** A board value as shown: m:ss for the time boards (format "time", seconds; TabRows.valueText of the client), else a
 * grouped number. */
function chaos_leaderboard_value(array $def, $value): string {
	if (($def['format'] ?? '') === 'time') {
		$s = max(0, (int)$value);
		return sprintf('%d:%02d', intdiv($s, 60), $s % 60);
	}
	return number_format((float)$value);
}

/** Top rows of a weekly board (staff left out, ties: who got there first, then the lower id). $ascending: the lowest
 * value first (boards of mode "min", fastest times; LB.rank of leaderboard_core.lua). $vocations: only characters of
 * these class ids (a class tab, LB.filterClass), ranked again from 1; empty = every class. */
function chaos_leaderboard_rows(string $board, int $week, int $limit = 20, bool $ascending = false, array $vocations = array()): array {
	if (!chaos_table_exists('chaos_leaderboard')) {
		return array();
	}
	$vocations = array_values(array_map('intval', $vocations));
	$class = $vocations ? ' AND `p`.`vocation` IN (' . implode(',', array_fill(0, count($vocations), '?')) . ')' : '';
	return chaos_rows('
		SELECT `p`.`name`, `p`.`vocation`, `p`.`level`, `l`.`value`, `l`.`count`
		FROM `chaos_leaderboard` `l`
		JOIN `players` `p` ON `p`.`id` = `l`.`player_id`
		WHERE `l`.`board` = ? AND `l`.`week` = ? AND `l`.`value` > 0 AND `p`.`group_id` < ?' . $class . chaos_antibot_hold_sql() . '
		ORDER BY `l`.`value` ' . ($ascending ? 'ASC' : 'DESC') . ', `l`.`updated_at` ASC, `l`.`player_id` ASC
		LIMIT ?;', array_merge([$board, $week, (int)chaos_cfg('staff_group', 4)], $vocations, [$limit]));
}

/**
 * The class tabs of a board with byClass, grouped as the game does (LB.classGroups of leaderboard.lua, the client's
 * game_leaderboard): one tab per base class with its ascensions, ordered by the base class id, named after the base
 * class. key (the base id) => {name, icon, ids}. The retired ids of the class rework count with the class they move to.
 * The page puts "All classes" first.
 */
function chaos_leaderboard_class_groups(): array {
	$lines = chaos_class_lines();
	ksort($lines);
	$groups = array();
	foreach ($lines as $base => $line) {
		$groups[$base] = array('name' => $line['name'], 'icon' => $line['icon'], 'ids' => chaos_line_ids($base));
	}
	foreach (chaos_retired_vocations() as $old => $new) {
		$base = chaos_base_of($new);
		if ($base !== null && isset($groups[$base])) {
			$groups[$base]['ids'][] = $old;
		}
	}
	return $groups;
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

// ---------------------------------------------------------------------------
// Competitive records (records.lua, records_config.lua, tables chaos_records*)
// ---------------------------------------------------------------------------

/** The record categories of records_config.lua: key => {name, title, info}. */
function chaos_records_categories(): array {
	$cats = array();
	$body = chaos_lua_block(chaos_read_server_file('scripts/chaos/records_config.lua'), 'categories');
	foreach (chaos_lua_entries($body) as $entry) {
		$key = chaos_lua_field($entry, 'key');
		if (is_string($key) && preg_match('/^[a-z0-9_]{1,16}$/', $key)) {
			$cats[$key] = array('name' => (string)(chaos_lua_field($entry, 'name') ?? $key),
				'title' => (string)(chaos_lua_field($entry, 'title') ?? ''), 'info' => (string)(chaos_lua_field($entry, 'info') ?? ''));
		}
	}
	return $cats;
}

/** "k=name;k=name" (chaos_records_boards variants / sizes) -> key => name. */
function chaos_records_pairs(string $text): array {
	$out = array();
	foreach (explode(';', $text) as $part) {
		$kv = explode('=', $part, 2);
		if (count($kv) === 2 && preg_match('/^[a-z0-9_]{1,24}$/', $kv[0])) {
			$out[$kv[0]] = $kv[1];
		}
	}
	return $out;
}

/** The boards the server published at startup (chaos_records_boards), in its order: key => {cat, name, mode, format,
 * label, variants, sizes}. */
function chaos_records_boards(): array {
	if (!chaos_table_exists('chaos_records_boards')) {
		return array();
	}
	$boards = array();
	foreach (chaos_rows('SELECT `key`, `cat`, `name`, `mode`, `format`, `label`, `variants`, `sizes` FROM `chaos_records_boards` ORDER BY `ord`;') as $r) {
		$boards[(string)$r['key']] = array('cat' => (string)$r['cat'], 'name' => (string)$r['name'], 'mode' => (string)$r['mode'],
			'format' => (string)$r['format'], 'label' => (string)$r['label'], 'variants' => chaos_records_pairs((string)$r['variants']),
			'sizes' => chaos_records_pairs((string)$r['sizes']));
	}
	return $boards;
}

/** The season key of the records (ChaosRecordsCore.seasonKey): the running season "s<id>", else the quarter "q<YYYY><q>". */
function chaos_records_season_key(int $time): string {
	foreach (chaos_seasons() as $s) {
		if ($s['start'] > 0 && $time >= $s['start'] && ($s['finish'] <= 0 || $time < $s['finish'])) {
			return 's' . $s['id'];
		}
	}
	return 'q' . date('Y', $time) . (intdiv((int)date('n', $time) - 1, 3) + 1);
}

/** A record value as shown (ChaosRecordsCore.valueText): time m:ss (h:mm:ss), pct (1/100 %), else a number. */
function chaos_records_value(string $format, $value): string {
	$v = (int)$value;
	if ($format === 'time') {
		$v = max(0, $v);
		return $v >= 3600 ? sprintf('%d:%02d:%02d', intdiv($v, 3600), intdiv($v % 3600, 60), $v % 60) : sprintf('%d:%02d', intdiv($v, 60), $v % 60);
	}
	if ($format === 'pct') {
		return sprintf('%.2f%%', $v / 100);
	}
	return number_format((float)$v);
}

/** The rows of one record slot and period: the best first (mode "min": the lowest), a tie to the earlier time, staff and
 * held characters left out, $vocations = a class tab (empty = every class). */
function chaos_records_rows(string $slot, string $period, string $mode, int $limit = 20, array $vocations = array()): array {
	if (!chaos_table_exists('chaos_records')) {
		return array();
	}
	$vocations = array_values(array_map('intval', $vocations));
	$class = $vocations ? ' AND `r`.`voc` IN (' . implode(',', array_fill(0, count($vocations), '?')) . ')' : '';
	return chaos_rows('
		SELECT `p`.`name`, `p`.`vocation`, `r`.`value`, `r`.`at`, `r`.`party`, `r`.`members`
		FROM `chaos_records` `r`
		JOIN `players` `p` ON `p`.`id` = `r`.`player_id`
		WHERE `r`.`slot` = ? AND `r`.`period` = ? AND `r`.`value` > 0 AND `p`.`group_id` < ?' . $class . chaos_antibot_hold_sql() . '
		ORDER BY `r`.`value` ' . ($mode === 'min' ? 'ASC' : 'DESC') . ', `r`.`at` ASC, `r`.`player_id` ASC
		LIMIT ?;', array_merge([$slot, $period, (int)chaos_cfg('staff_group', 4)], $vocations, [$limit]));
}

/** The name a realm first is listed by (ChaosRecordsCore.firstDisplay in the server's records_core.lua): a first keeps
 * its target and the short title name ("Skaldra"); the list names the boss in full ("Skaldra the Rime Queen") from the
 * boards the server published (chaos_records_boards): the variant's name, else the board's, else the stored name. */
function chaos_records_first_name(array $first, array $boards): string {
	$short = (string)($first['name'] ?? '');
	$parts = explode(':', (string)($first['target'] ?? ''), 2);
	$board = $boards[$parts[0]] ?? null;
	if (!$board) {
		return $short;
	}
	if (count($parts) < 2 || $parts[1] === '') {
		return (string)$board['name'];
	}
	$variants = $board['variants'] ?? array();
	if (isset($variants[$parts[1]])) {
		return (string)$variants[$parts[1]];
	}
	// "<family>.<variant>" (the trials): the stored name and the variant
	$dot = strrpos($parts[1], '.');
	$v = $dot === false ? null : ($variants[substr($parts[1], $dot + 1)] ?? null);
	if ($v !== null && $short !== '') {
		return $short . ' (' . $v . ')';
	}
	return $short !== '' ? $short : (string)$board['name'];
}

/** The realm firsts of a season, oldest first. */
function chaos_records_firsts(string $season): array {
	if (!chaos_table_exists('chaos_records_firsts')) {
		return array();
	}
	return chaos_rows('SELECT `target`, `board`, `name`, `members`, `value`, `at` FROM `chaos_records_firsts` WHERE `season` = ? ORDER BY `at` ASC LIMIT 100;', [$season]);
}

/** Class Ladder: the highest characters of one class line. With a season: only its characters; $mode is a season
 * mode tab (chaos_season_mode_tabs, season_modes.lua): 'all' and the mode tabs list living (unmigrated) characters,
 * 'fallen' the fallen Hardcore ones by the level they fell at. Rows carry fallen_level / fallen_cause when known. */
function chaos_class_ladder(int $base, int $limit = 10, int $season = 0, string $mode = 'all'): array {
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
	$where = '';
	$cols = '';
	$order = '`p`.`experience` DESC, `p`.`id` ASC';
	if ($season > 0) {
		if (!chaos_table_exists('chaos_season_players')) {
			return array();
		}
		$join = 'JOIN `chaos_season_players` `s` ON `s`.`player_id` = `p`.`id` AND `s`.`season` = ?';
		array_unshift($params, $season);
		// season modes (season_modes.lua): the mode tab, the fallen marks
		$clause = chaos_season_mode_clause($mode);
		if ($clause === null) {
			return array();
		}
		if (chaos_table_exists('chaos_season_modes')) {
			$join .= ' LEFT JOIN `chaos_season_modes` `m` ON `m`.`player_id` = `p`.`id`';
			$cols = ', `m`.`fallen_level`, `m`.`fallen_cause`';
			$where = ' AND ' . $clause;
		} elseif ($mode !== 'all' && $mode !== 'standard') {
			return array();
		}
		if ($mode === 'fallen') {
			$order = '`m`.`fallen_level` DESC, `m`.`fallen_at` ASC';
		} else {
			$where .= ' AND `s`.`migrated_at` = 0';
		}
	}
	$params[] = $limit;
	return chaos_rows("
		SELECT `p`.`name`, `p`.`level`, `p`.`vocation`, `p`.`experience`$cols
		FROM `players` `p` $join
		WHERE `p`.`vocation` IN ($in) AND `p`.`group_id` < ? AND `p`.`deletion` = 0$where" . chaos_antibot_hold_sql() . "
		ORDER BY $order
		LIMIT ?;", $params);
}

// ---------------------------------------------------------------------------
// Season modes (season_modes.lua, season_config.lua `modes`, table chaos_season_modes)
// ---------------------------------------------------------------------------

/** The mode tabs of the season ladder, key => label (the game's leaderboard window has the same). */
function chaos_season_mode_tabs(): array {
	return array('all' => 'All', 'standard' => 'Standard', 'ssf' => 'Self-Found', 'hc' => 'Hardcore',
		'hcssf' => 'HC Self-Found', 'fallen' => 'Fallen');
}

/** SQL condition of a mode tab on `m` (chaos_season_modes, LEFT JOINed: NULL = no mode row); null = unknown tab.
 * The same rules as ChaosSeasonModes.ladderClause (season_modes_core.lua). */
function chaos_season_mode_clause(string $mode): ?string {
	$c = array(
		'all'      => '1 = 1',
		'standard' => '(`m`.`player_id` IS NULL OR (`m`.`ssf` = 0 AND `m`.`hc` = 0))',
		'ssf'      => '`m`.`ssf` = 1 AND `m`.`hc` = 0',
		'hc'       => '`m`.`hc` = 1 AND `m`.`ssf` = 0 AND `m`.`fallen_at` = 0',
		'hcssf'    => '`m`.`hc` = 1 AND `m`.`ssf` = 1 AND `m`.`fallen_at` = 0',
		'fallen'   => '`m`.`fallen_at` > 0',
	);
	return $c[$mode] ?? null;
}

/** Fallen Hardcore characters (every season): name => {level, cause}, for the skull on the ladders. */
function chaos_fallen_marks(): array {
	if (!chaos_table_exists('chaos_season_modes')) {
		return array();
	}
	$out = array();
	foreach (chaos_rows('SELECT `p`.`name`, `m`.`fallen_level`, `m`.`fallen_cause` FROM `chaos_season_modes` `m`
		JOIN `players` `p` ON `p`.`id` = `m`.`player_id` WHERE `m`.`fallen_at` > 0;') as $r) {
		$out[(string)$r['name']] = array('level' => (int)$r['fallen_level'], 'cause' => (string)$r['fallen_cause']);
	}
	return $out;
}

/** The skull of a fallen character (an inline mark with the fall as its tooltip), or '' */
function chaos_fallen_html(array $marks, string $name): string {
	if (!isset($marks[$name])) {
		return '';
	}
	$f = $marks[$name];
	return ' <span class="chaos-fallen" title="' . chaos_h(sprintf('Fallen in Hardcore at level %d (%s)', $f['level'], $f['cause']))
		. '">&#9760;</span>';
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

// ---------------------------------------------------------------------------
// Chaos Coins (server/data/scripts/chaos/shop_coins_config.lua, table chaos_coin_orders)
// The game server credits every paid order (shop.lua: pack coins, pack bonus, the one-time first-purchase bonus, the
// one-time starter pack); the site only shows the packs and records paid orders.
// ---------------------------------------------------------------------------

/** The coin packs: key, name, coins, bonus_pct, bonus_coins, usd_cents, once, starter, total (without the first-purchase bonus). */
function chaos_coin_packs(): array {
	$text = chaos_read_server_file('scripts/chaos/shop_coins_config.lua');
	$out = array();
	foreach (chaos_lua_entries(chaos_lua_block($text, 'packs')) as $entry) {
		$key = (string)(chaos_lua_field($entry, 'key') ?? '');
		if ($key === '') {
			continue;
		}
		$pack = array(
			'key'         => $key,
			'name'        => (string)(chaos_lua_field($entry, 'name') ?? $key),
			'coins'       => (int)(chaos_lua_field($entry, 'coins') ?? 0),
			'bonus_pct'   => (int)(chaos_lua_field($entry, 'bonusPct') ?? 0),
			'bonus_coins' => (int)(chaos_lua_field($entry, 'bonusCoins') ?? 0),
			'usd_cents'   => is_int(chaos_lua_field($entry, 'usdCents')) ? chaos_lua_field($entry, 'usdCents') : 0,
			'once'        => (bool)preg_match('/\bonce\s*=\s*true\b/', $entry),
			'starter'     => (bool)preg_match('/\bstarter\s*=\s*true\b/', $entry),
		);
		$pack['total'] = chaos_coin_pack_total($pack, false, 0);
		$out[] = $pack;
	}
	return $out;
}

/** The first-purchase bonus in % and the base currency of the prices (USD: usdCents). */
function chaos_coin_settings(): array {
	$text = chaos_read_server_file('scripts/chaos/shop_coins_config.lua');
	return array(
		'first_bonus_pct' => (int)(chaos_lua_field(chaos_lua_block($text, 'firstPurchase'), 'bonusPct') ?? 0),
		// the cap of the first-purchase bonus in coins (0 = none): "Limite a 1000"
		'first_bonus_max' => (int)(chaos_lua_field(chaos_lua_block($text, 'firstPurchase'), 'maxBonus') ?? 0),
		'currency'        => (string)(preg_match('/\bcurrency\s*=\s*"([^"]*)"/', $text, $m) ? $m[1] : ''),
	);
}

/**
 * The `payments` block of shop_coins_config.lua (donations: Pix and PayPal): brl_per_usd, expire_minutes, max_open,
 * max_per_hour, first_bonus_pct, methods => [pix|paypal => enabled, currency, label]. Prices are derived from the packs'
 * usdCents with ChaosPayService::priceCents (the game server: ChaosPayCore.priceCents), never stored twice.
 */
function chaos_pay_config(): array {
	$text = chaos_read_server_file('scripts/chaos/shop_coins_config.lua');
	$block = chaos_lua_block($text, 'payments');
	$int = static function (string $key, int $default) use ($block): int {
		$v = chaos_lua_field($block, $key);
		return is_int($v) ? $v : $default;
	};
	$methods = array();
	$list = chaos_lua_block($block, 'methods');
	foreach (array('pix', 'paypal') as $m) {
		$body = preg_match('/\b' . $m . '\s*=\s*\{([^}]*)\}/', $list, $mm) ? $mm[1] : '';
		$methods[$m] = array(
			'enabled'  => $body !== '' && !preg_match('/\benabled\s*=\s*false\b/', $body),
			'currency' => (string)(chaos_lua_field($body, 'currency') ?? ''),
			'label'    => (string)(chaos_lua_field($body, 'label') ?? $m),
		);
	}
	return array(
		'brl_per_usd'     => $int('brlPerUsd', 0),
		'expire_minutes'  => $int('expireMinutes', 30),
		'max_open'        => $int('maxOpenPerAccount', 1),
		'max_per_hour'    => $int('maxPerHour', 6),
		'first_bonus_pct' => chaos_coin_settings()['first_bonus_pct'],
		'first_bonus_max' => chaos_coin_settings()['first_bonus_max'],
		'methods'         => $methods,
	);
}

/** Coins a pack credits (same rule as ChaosShopCore.packCredit in shop_core.lua). */
function chaos_coin_pack_total(array $pack, bool $first, int $firstPct, int $firstMax = 0): int {
	$coins = (int)$pack['coins'];
	$total = $coins + intdiv($coins * (int)$pack['bonus_pct'], 100) + (int)$pack['bonus_coins'];
	if ($first && empty($pack['starter'])) {
		$total += chaos_coin_first_bonus($coins, $firstPct, $firstMax);
	}
	return $total;
}

/** The first-purchase bonus of a pack of $coins: $pct % of it, at most $max coins (0 = no cap; ChaosShopCore.packCredit). */
function chaos_coin_first_bonus(int $coins, int $pct, int $max = 0): int {
	$bonus = intdiv($coins * $pct, 100);
	return $max > 0 ? min($bonus, $max) : $bonus;
}

/** The first donation line of the Donate page and the guides: "double Chaos Coins (+100%, up to 1000 extra)". */
function chaos_coin_first_text(int $pct, int $max): string {
	$t = function_exists('chaos_t') ? 'chaos_t' : 'sprintf';   // the page's language (i18n_lib.php), else English
	$base = $pct === 100 ? $t('double Chaos Coins') : $t('+%d%% extra Chaos Coins', $pct);
	$notes = $pct === 100 ? array('+100%') : array();
	if ($max > 0) {
		$notes[] = $t('up to %d extra', $max);
	}
	return $notes ? $base . ' (' . implode(', ', $notes) . ')' : $base;
}

/** What an account can still get: ['first' => first-purchase bonus open, 'starter' => starter pack open]. */
function chaos_coin_account_state(int $accountId): array {
	$state = array('first' => true, 'starter' => true);
	if ($accountId <= 0 || !chaos_table_exists('chaos_coin_orders')) {
		return $state;
	}
	$starters = array();
	foreach (chaos_coin_packs() as $pack) {
		if ($pack['starter']) {
			$starters[] = $pack['key'];
		}
	}
	foreach (chaos_rows('SELECT `pack_key` FROM `chaos_coin_orders` WHERE `account_id` = ? AND `status` IN (\'paid\', \'credited\');', [$accountId]) as $row) {
		if (in_array($row['pack_key'], $starters, true)) {
			$state['starter'] = false;
		} else {
			$state['first'] = false;
		}
	}
	return $state;
}

/**
 * HOOK for a payment provider: call it from the provider's confirmed-payment callback (after verifying the provider's
 * signature there). It only records the order as paid; the game server credits it within a minute. The provider's
 * own reference makes it idempotent (a repeated callback writes nothing). No provider is connected in this repository.
 * Returns false for an unknown pack or account.
 */
function chaos_coin_order_paid(int $accountId, string $packKey, string $provider, string $providerRef): bool {
	$known = false;
	foreach (chaos_coin_packs() as $pack) {
		$known = $known || $pack['key'] === $packKey;
	}
	if (!$known || $accountId <= 0 || $provider === '' || $providerRef === '') {
		return false;
	}
	$account = db()->fetchOne('SELECT `id` FROM `accounts` WHERE `id` = ? LIMIT 1;', [$accountId]);
	if (!is_array($account)) {
		return false;
	}
	db()->execute('INSERT IGNORE INTO `chaos_coin_orders` (`account_id`, `pack_key`, `provider`, `provider_ref`, `status`, `created`) VALUES (?, ?, ?, ?, \'paid\', ?);',
		[$accountId, $packKey, substr($provider, 0, 32), substr($providerRef, 0, 128), time()]);
	return true;
}

// ---------------------------------------------------------------------------
// Dropdown filters (README "Dropdown filters"): a long row of filter buttons becomes a GET form with one <select> per
// filter and a "Show" button, so it works without JavaScript; assets/js/chaos-pick.js submits it on change and hides
// the button. Same query parameters as the old button links.
// ---------------------------------------------------------------------------

/** The sort form of a name: accents folded to their base letter, lower case (the client's BoardPick.fold). */
function chaos_sort_fold(string $s): string {
	static $map = null;
	if ($map === null) {
		$from = 'ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝàáâãäåçèéêëìíîïñòóôõöøùúûüýÿ';
		$to   = 'aaaaaaceeeeiiiinoooooouuuuyaaaaaaceeeeiiiinoooooouuuuyy';
		$map = array('Æ' => 'ae', 'æ' => 'ae', 'ß' => 'ss');
		$chars = preg_split('//u', $from, -1, PREG_SPLIT_NO_EMPTY);
		foreach ($chars as $i => $c) {
			$map[$c] = $to[$i];
		}
	}
	return strtolower(strtr($s, $map));
}

/** key => label sorted by the label as shown (accents folded, as the client's board dropdown), ties by the key. */
function chaos_sort_options(array $options): array {
	$keys = array_keys($options);
	usort($keys, static function ($a, $b) use ($options): int {
		$c = strcmp(chaos_sort_fold((string)$options[$a]), chaos_sort_fold((string)$options[$b]));
		if ($c === 0) {
			$c = strcmp((string)$options[$a], (string)$options[$b]);
		}
		return $c !== 0 ? $c : strcmp((string)$a, (string)$b);
	});
	$out = array();
	foreach ($keys as $k) {
		$out[$k] = $options[$k];
	}
	return $out;
}

/** One labelled <select> of a filter form. $options: value => label, in the order given. $reset: the other fields
 * dropped when this one changes (chaos-pick.js; without JavaScript the page falls back to their first value). */
function chaos_pick_select(string $name, string $label, array $options, string $selected, array $reset = array()): string {
	static $n = 0;
	$id = 'chaos-pick-' . preg_replace('/[^a-z0-9_-]/i', '', $name) . '-' . (++$n);
	$html = '<label class="chaos-pick__field" for="' . chaos_h($id) . '"><span class="chaos-pick__label">' . chaos_h($label) . '</span>'
		. '<select id="' . chaos_h($id) . '" name="' . chaos_h($name) . '" data-chaos-autosubmit'
		. ($reset ? ' data-chaos-reset="' . chaos_h(implode(' ', $reset)) . '"' : '') . '>';
	foreach ($options as $value => $text) {
		$html .= '<option value="' . chaos_h((string)$value) . '"' . ((string)$value === $selected ? ' selected' : '') . '>'
			. chaos_h($text) . '</option>';
	}
	return $html . '</select></label>';
}

/** A GET filter form to page.php: $hidden (name => value) first, then the fields (chaos_pick_select HTML), then the
 * submit button. $anchor: the part of the page to land on (kept by the browser on submit). Loads chaos-pick.js. */
function chaos_pick_form(array $hidden, string $fields, string $label, string $anchor = ''): string {
	$html = '<form class="chaos-pick" method="get" action="page' . ($anchor !== '' ? '#' . chaos_h($anchor) : '') . '"'
		. ' aria-label="' . chaos_h($label) . '">';
	foreach ($hidden as $name => $value) {
		if ($value === null || (string)$value === '') {
			continue;
		}
		$html .= '<input type="hidden" name="' . chaos_h((string)$name) . '" value="' . chaos_h((string)$value) . '">';
	}
	$html .= $fields . '<button type="submit" class="chaos-btn chaos-pick__go">' . chaos_h(function_exists('chaos_t') ? chaos_t('Show') : 'Show') . '</button></form>';
	if (function_exists('znote_plugin_asset')) {
		// every form names the script; the browser fetches it once and the script sets each form up once
		$html .= '<script src="' . chaos_h(znote_plugin_asset('chaos', 'js/chaos-pick.js')) . '" defer></script>';
	}
	return $html;
}

} // function_exists guard
