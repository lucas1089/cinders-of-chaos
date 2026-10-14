<?php
/**
 * Bot review for the staff page (pages/botreview.php). Tables of the game server: chaos_bot_daily, chaos_bot_actions
 * (server/sql/chaos_bot.sql; data/scripts/chaos/botreview.lua), chaos_antibot_log (antibot.lua).
 *
 * Nothing here punishes. Staff read a flagged day, then mark it reviewed, false positive or escalated (GM handbook
 * section 3). Every mark and every presence check request is a row in chaos_bot_actions.
 *
 * Access: an admin panel account (the reports page's check, chaos_reports_is_admin) with a character of group 4
 * (gamemaster) or higher views and marks; only group 5 (administrator) may change a day that is already escalated
 * (GM handbook section 7, level 2). Every write is a POST with the page's CSRF token. Every query is a prepared
 * statement through ZnoteX's db(); every value printed goes through chaos_h().
 */

if (!function_exists('chaos_botreview_group')) {

require_once __DIR__ . '/reports_lib.php';

define('CHAOS_BOTREVIEW_VIEW_GROUP', 4); // gamemaster: view and mark (GM handbook section 3)
define('CHAOS_BOTREVIEW_ADMIN_GROUP', 5); // administrator: changes an escalated day (GM handbook section 7)

/** The staff group of an admin panel account (its highest character group), 0 when it may not use the page. */
function chaos_botreview_group(array $config, int $accountId): int {
	if (!chaos_reports_is_admin($config, $accountId)) {
		return 0;
	}
	$row = db()->fetchOne('SELECT MAX(`group_id`) AS `g` FROM `players` WHERE `account_id` = ?;', [$accountId]);
	$g = is_array($row) ? (int)($row['g'] ?? 0) : 0;
	return $g >= CHAOS_BOTREVIEW_VIEW_GROUP ? $g : 0;
}

/** Status keys and labels of chaos_bot_daily (botreview_core.lua BR.STATUSES). */
function chaos_botreview_statuses(): array {
	return array('new' => 'To review', 'escalated' => 'Escalated', 'reviewed' => 'Reviewed', 'false_positive' => 'False positive');
}

/** The signal names in the order of botreview_core.lua, with their family and a short label. */
function chaos_botreview_signal_names(): array {
	return array(
		'timing' => array('automation', 'Action rhythm'), 'reaction' => array('automation', 'Instant heals after hits'),
		'loot' => array('automation', 'Looting pace'), 'heal' => array('automation', 'Heals at one HP threshold'),
		'retarget' => array('automation', 'Next target after a kill'),
		'nonstop' => array('unattended', 'Hours without a break'), 'silence' => array('unattended', 'No chat, looks, turns or pauses'),
		'route' => array('unattended', 'Same route hour after hour'), 'loop' => array('unattended', 'Walking one loop'),
		'presence' => array('unattended', 'Missed presence check'), 'cluster' => array('unattended', 'In step with another character'),
	);
}

/** "timing=0.82;heal=1.00" -> ['timing' => 0.82, ...], only known names, clamped to 0..1. */
function chaos_botreview_parse_signals(string $text): array {
	$known = chaos_botreview_signal_names();
	$out = array();
	foreach (explode(';', $text) as $part) {
		$kv = explode('=', $part, 2);
		if (count($kv) === 2 && isset($known[$kv[0]]) && is_numeric($kv[1])) {
			$out[$kv[0]] = max(0.0, min(1.0, (float)$kv[1]));
		}
	}
	return $out;
}

/** "3=40,4=62" -> [3 => 40, 4 => 62] (hours 0..23, scores 0..100). */
function chaos_botreview_parse_timeline(string $text): array {
	$out = array();
	foreach (explode(',', $text) as $part) {
		if (preg_match('/^(\d{1,2})=(\d{1,3})$/', $part, $m) && (int)$m[1] < 24) {
			$out[(int)$m[1]] = min(100, (int)$m[2]);
		}
	}
	ksort($out);
	return $out;
}

/** The list filters from the query string, validated (never used raw in SQL). */
function chaos_botreview_filters(array $get): array {
	$status = (string)($get['status'] ?? 'new');
	if ($status !== 'all' && !isset(chaos_botreview_statuses()[$status])) {
		$status = 'new';
	}
	$days = (int)($get['days'] ?? 7);
	if (!in_array($days, array(1, 7, 30), true)) {
		$days = 7;
	}
	$name = trim((string)($get['name'] ?? ''));
	if (!preg_match("/^[A-Za-z][A-Za-z '\\-]{0,28}$/", $name)) {
		$name = '';
	}
	$page = max(1, min(1000, (int)($get['page'] ?? 1)));
	return array('status' => $status, 'days' => $days, 'name' => $name, 'page' => $page);
}

/** The YYYYMMDD day key of a time (server time, as Chaos.dayKey). */
function chaos_botreview_day(int $t): int {
	return (int)date('Ymd', $t);
}

/** [rows, total] of the flagged days matching the filters, highest score first. */
function chaos_botreview_list(array $f, int $now, int $perPage = 25): array {
	$where = array('`flagged` = 1', '`day` >= ?');
	$params = array(chaos_botreview_day($now - ($f['days'] - 1) * 86400));
	if ($f['status'] !== 'all') {
		$where[] = '`status` = ?';
		$params[] = $f['status'];
	}
	if ($f['name'] !== '') {
		$where[] = '`player_name` LIKE ?';
		$params[] = '%' . str_replace(array('%', '_'), array('\\%', '\\_'), $f['name']) . '%';
	}
	$sql = implode(' AND ', $where);
	$count = db()->fetchOne("SELECT COUNT(*) AS `n` FROM `chaos_bot_daily` WHERE $sql;", $params);
	$total = is_array($count) ? (int)$count['n'] : 0;
	$rows = chaos_rows("SELECT `id`, `player_id`, `player_name`, `day`, `score`, `peak`, `signals`, `status`, `reviewed_by`
		FROM `chaos_bot_daily` WHERE $sql ORDER BY `score` DESC, `id` DESC LIMIT ? OFFSET ?;",
		array_merge($params, array($perPage, ($f['page'] - 1) * $perPage)));
	return array($rows, $total);
}

/** One day row, or null. */
function chaos_botreview_row(int $id): ?array {
	$row = db()->fetchOne('SELECT * FROM `chaos_bot_daily` WHERE `id` = ? LIMIT 1;', [$id]);
	return is_array($row) ? $row : null;
}

/** The stored days of a character (newest first), for the 30-day timeline. */
function chaos_botreview_history(int $playerId, int $limit = 30): array {
	return chaos_rows('SELECT `id`, `day`, `score`, `flagged`, `status` FROM `chaos_bot_daily` WHERE `player_id` = ?
		ORDER BY `day` DESC LIMIT ?;', [$playerId, $limit]);
}

/** Staff actions on a character, newest first. */
function chaos_botreview_actions(int $playerId, int $limit = 30): array {
	return chaos_rows('SELECT `created_at`, `day`, `action`, `staff`, `note`, `done_at`, `result` FROM `chaos_bot_actions`
		WHERE `player_id` = ? ORDER BY `id` DESC LIMIT ?;', [$playerId, $limit]);
}

/** The anti-bot log of a character (presence checks, scores), newest first. */
function chaos_botreview_antibot_log(int $playerId, int $limit = 20): array {
	if (function_exists('chaos_table_exists') && !chaos_table_exists('chaos_antibot_log')) {
		return array();
	}
	return chaos_rows('SELECT `created_at`, `kind`, `score`, `detail` FROM `chaos_antibot_log` WHERE `player_id` = ?
		ORDER BY `id` DESC LIMIT ?;', [$playerId, $limit]);
}

function chaos_botreview_clean_note(string $note): string {
	$note = preg_replace('/[\x00-\x1F\x7F]+/', ' ', $note);
	$note = trim(preg_replace('/\s+/', ' ', (string)$note));
	return mb_substr($note, 0, 255);
}

/**
 * A staff action on a day: reviewed | false_positive | escalate | note | check (a presence check for the character,
 * sent by the game server within a minute when it is online, outside PvP, boss fights and rifts). Returns [ok, message].
 */
function chaos_botreview_action(string $action, int $id, string $note, string $staff, int $group, int $now): array {
	if (!in_array($action, array('reviewed', 'false_positive', 'escalate', 'note', 'check'), true)) {
		return array(false, 'Unknown action.');
	}
	if ($group < CHAOS_BOTREVIEW_VIEW_GROUP) {
		return array(false, 'Not allowed.');
	}
	$row = chaos_botreview_row($id);
	if (!$row) {
		return array(false, 'No such day.');
	}
	$note = chaos_botreview_clean_note($note);
	$name = (string)$row['player_name'];
	$status = array('reviewed' => 'reviewed', 'false_positive' => 'false_positive', 'escalate' => 'escalated')[$action] ?? null;
	if ($status !== null && $row['status'] === 'escalated' && $group < CHAOS_BOTREVIEW_ADMIN_GROUP) {
		return array(false, 'This case is escalated: only an administrator (group 5) may change it.');
	}
	if ($action === 'check') {
		$pending = db()->fetchOne('SELECT `id` FROM `chaos_bot_actions` WHERE `player_id` = ? AND `action` = \'check\' AND `done_at` = 0 LIMIT 1;',
			[(int)$row['player_id']]);
		if (is_array($pending)) {
			return array(false, 'A presence check for ' . $name . ' is already waiting.');
		}
		db()->execute('INSERT INTO `chaos_bot_actions` (`created_at`, `player_id`, `player_name`, `day`, `action`, `staff`, `staff_group`, `note`, `done_at`)
			VALUES (?, ?, ?, ?, \'check\', ?, ?, ?, 0);', [$now, (int)$row['player_id'], $name, (int)$row['day'], $staff, $group, $note]);
		return array(true, 'Presence check requested for ' . $name . ' (sent when online, outside PvP and boss fights).');
	}
	if ($status !== null) {
		db()->execute('UPDATE `chaos_bot_daily` SET `status` = ?, `reviewed_by` = ?, `reviewed_at` = ?, `note` = ? WHERE `id` = ?;',
			[$status, $staff, $now, $note, $id]);
	} else {
		db()->execute('UPDATE `chaos_bot_daily` SET `note` = ? WHERE `id` = ?;', [$note, $id]);
	}
	db()->execute('INSERT INTO `chaos_bot_actions` (`created_at`, `player_id`, `player_name`, `day`, `action`, `staff`, `staff_group`, `note`, `done_at`)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);', [$now, (int)$row['player_id'], $name, (int)$row['day'], $action, $staff, $group, $note, $now]);
	$labels = array('reviewed' => 'marked reviewed', 'false_positive' => 'marked false positive', 'escalate' => 'escalated to an administrator', 'note' => 'note saved');
	return array(true, $name . ' (' . (int)$row['day'] . '): ' . $labels[$action] . '.');
}

}
