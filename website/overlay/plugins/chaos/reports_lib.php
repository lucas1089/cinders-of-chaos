<?php
/**
 * Player reports and the anti-bot log for the staff page (pages/reports.php). Tables of the game server:
 * chaos_reports, chaos_antibot_log (server/sql/chaos_reports.sql; data/scripts/chaos/reports.lua, antibot.lua).
 *
 * Access: the accounts of ZnoteX's admin panel ($config['page_admin_access'], CHAOS_ADMIN_ACCOUNTS), the same check
 * as ZnoteX's is_admin(). Every write is a POST with the page's CSRF token. Every query is a prepared statement
 * through ZnoteX's db(); every value printed goes through chaos_h().
 */

if (!function_exists('chaos_reports_is_admin')) {

/** True when the logged-in account may use the staff pages. */
function chaos_reports_is_admin(array $config, int $accountId): bool {
	if ($accountId <= 0) {
		return false;
	}
	if (function_exists('is_admin') && isset($GLOBALS['user_data']) && is_array($GLOBALS['user_data'])) {
		return (bool)is_admin($GLOBALS['user_data']);
	}
	$admins = array_map('strval', (array)($config['page_admin_access'] ?? array()));
	if (!$admins) {
		return false;
	}
	$row = db()->fetchOne('SELECT `name` FROM `accounts` WHERE `id` = ? LIMIT 1;', [$accountId]);
	return is_array($row) && in_array((string)$row['name'], $admins, true);
}

/** The reasons of antibot_config.lua (keys and labels). */
function chaos_report_reasons(): array {
	return array(
		'botting' => 'Botting', 'cheating' => 'Cheating / exploiting', 'harassment' => 'Harassment',
		'scam' => 'Scam', 'name' => 'Offensive name', 'other' => 'Other',
	);
}

/** The list filters from the query string, validated (never used raw in SQL). */
function chaos_report_filters(array $get): array {
	$status = (string)($get['status'] ?? 'open');
	if (!in_array($status, array('open', 'closed', 'all'), true)) {
		$status = 'open';
	}
	$reason = (string)($get['reason'] ?? '');
	if (!isset(chaos_report_reasons()[$reason])) {
		$reason = '';
	}
	$name = trim((string)($get['name'] ?? ''));
	if (!preg_match("/^[A-Za-z][A-Za-z '\\-]{0,28}$/", $name)) {
		$name = '';
	}
	$page = max(1, min(1000, (int)($get['page'] ?? 1)));
	return array('status' => $status, 'reason' => $reason, 'name' => $name, 'page' => $page);
}

/** [rows, total] of the reports matching the filters, newest first. */
function chaos_report_list(array $f, int $perPage = 25): array {
	$where = array('1 = 1');
	$params = array();
	if ($f['status'] !== 'all') {
		$where[] = '`status` = ?';
		$params[] = $f['status'];
	}
	if ($f['reason'] !== '') {
		$where[] = '`reason` = ?';
		$params[] = $f['reason'];
	}
	if ($f['name'] !== '') {
		$where[] = '(`target_name` LIKE ? OR `reporter_name` LIKE ?)';
		$like = '%' . str_replace(array('%', '_'), array('\\%', '\\_'), $f['name']) . '%';
		$params[] = $like;
		$params[] = $like;
	}
	$sql = implode(' AND ', $where);
	$count = db()->fetchOne("SELECT COUNT(*) AS `n` FROM `chaos_reports` WHERE $sql;", $params);
	$total = is_array($count) ? (int)$count['n'] : 0;
	$rows = chaos_rows("SELECT `id`, `created_at`, `reporter_name`, `target_name`, `reason`, `note`, `pos_x`, `pos_y`, `pos_z`,
		`target_online`, `suspicion`, `chat`, `status`, `closed_at`, `closed_by`, `staff_note`
		FROM `chaos_reports` WHERE $sql ORDER BY `id` DESC LIMIT ? OFFSET ?;",
		array_merge($params, array($perPage, ($f['page'] - 1) * $perPage)));
	return array($rows, $total);
}

/** The staff name of an account (shown as "closed by"). */
function chaos_report_staff_name(int $accountId): string {
	$row = db()->fetchOne('SELECT `name` FROM `accounts` WHERE `id` = ? LIMIT 1;', [$accountId]);
	return is_array($row) ? 'web:' . (string)$row['name'] : 'web';
}

function chaos_report_clean_note(string $note): string {
	$note = preg_replace('/[\x00-\x1F\x7F]+/', ' ', $note);
	$note = trim(preg_replace('/\s+/', ' ', (string)$note));
	return mb_substr($note, 0, 255);
}

/**
 * A staff action from the page: close (with a note), note (only the note), reopen. Returns [ok, message].
 */
function chaos_report_action(string $action, int $id, string $note, string $staff): array {
	$row = db()->fetchOne('SELECT `id`, `status` FROM `chaos_reports` WHERE `id` = ? LIMIT 1;', [$id]);
	if (!is_array($row)) {
		return array(false, 'No report #' . $id . '.');
	}
	$note = chaos_report_clean_note($note);
	if ($action === 'close') {
		if ($row['status'] === 'closed') {
			return array(false, 'Report #' . $id . ' is already closed.');
		}
		db()->execute('UPDATE `chaos_reports` SET `status` = \'closed\', `closed_at` = ?, `closed_by` = ?, `staff_note` = ? WHERE `id` = ?;',
			[time(), $staff, $note, $id]);
		return array(true, 'Report #' . $id . ' closed.');
	}
	if ($action === 'note') {
		db()->execute('UPDATE `chaos_reports` SET `staff_note` = ? WHERE `id` = ?;', [$note, $id]);
		return array(true, 'Note of report #' . $id . ' saved.');
	}
	if ($action === 'reopen') {
		if ($row['status'] !== 'closed') {
			return array(false, 'Report #' . $id . ' is open.');
		}
		db()->execute('UPDATE `chaos_reports` SET `status` = \'open\', `closed_at` = 0, `closed_by` = \'\' WHERE `id` = ?;', [$id]);
		return array(true, 'Report #' . $id . ' opened again.');
	}
	return array(false, 'Unknown action.');
}

/** The newest anti-bot log entries (optionally of one character name). */
function chaos_antibot_log_rows(string $name = '', int $limit = 30): array {
	if ($name !== '') {
		return chaos_rows('SELECT `created_at`, `player_name`, `kind`, `score`, `detail` FROM `chaos_antibot_log`
			WHERE `player_name` = ? ORDER BY `id` DESC LIMIT ?;', [$name, $limit]);
	}
	return chaos_rows('SELECT `created_at`, `player_name`, `kind`, `score`, `detail` FROM `chaos_antibot_log`
		ORDER BY `id` DESC LIMIT ?;', [$limit]);
}

}
