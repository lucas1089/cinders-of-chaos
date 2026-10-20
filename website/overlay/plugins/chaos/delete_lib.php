<?php
/**
 * Character deletion by the owner (pages/deletecharacter.php; website/README.md "Deleting a character"). Owner report
 * 2026-10-17 "Deletar personagem no site nao funciona": ZnoteX's own deletion page is replaced by this one (plugin.php
 * sends deletecharacter.php / delete_character.php here), so the rules live in the repository and are tested.
 *
 * Rules (chaos_delete_blockers): the character is on the account, is offline, is not staff (group_id > 1), is not a
 * guild leader or vice-leader, owns no house and has no open Character Bazaar listing. The request needs the form's
 * CSRF token, the account password and the character's name typed again; wrong passwords are limited per session.
 *
 * What is removed: the `players` row (the foreign keys of the game schema, ON DELETE CASCADE, take items, depot,
 * storages and the per-character Chaos tables with it) and then the rows that have no foreign key (the website's
 * znote_players, the VIP list entries, guild invites, live state of a few Chaos systems). Logs and the purchase
 * history stay (they hold no gameplay state and the shop history is a financial record).
 *
 * All SQL is prepared (db() of ZnoteX; PDO / SQLite in website/tests/chaos_delete_character_test.php).
 */

if (!function_exists('chaos_delete_blockers')) {

/** Wrong passwords allowed per session in the window, and the window (seconds). */
define('CHAOS_DELETE_MAX_FAILS', 5);
define('CHAOS_DELETE_FAIL_WINDOW', 900);

/** Tables without a foreign key whose rows go with the character: table => column of the character id. */
function chaos_delete_loose_tables(): array {
	return array(
		'znote_players' => 'player_id', 'account_viplist' => 'player_id', 'guild_invites' => 'player_id',
		'player_namelocks' => 'player_id', 'chaos_player_titles' => 'player_id', 'chaos_pvpzone_players' => 'player_id',
		'chaos_pocketboss' => 'player_id', 'chaos_mentors' => 'player_id',
	);
}

/** The characters of an account that can be deleted or listed: id, name, level, group, vocation. */
function chaos_delete_characters(int $accountId): array {
	return chaos_rows('SELECT `id`, `name`, `level`, `group_id`, `vocation` FROM `players` WHERE `account_id` = ? AND `deletion` = 0 ORDER BY `name`;',
		array($accountId));
}

/** Reasons a character cannot be deleted now (empty list: it can). $player is a row of chaos_delete_characters. */
function chaos_delete_blockers(array $player): array {
	$id = (int)$player['id'];
	$why = array();
	if ((int)($player['group_id'] ?? 0) > 1) {
		$why[] = 'Staff characters cannot be deleted here. Ask another staff member.';
	}
	if (chaos_table_exists('players_online') && chaos_rows('SELECT `player_id` FROM `players_online` WHERE `player_id` = ?;', array($id))) {
		$why[] = 'The character is online. Log it out first.';
	}
	if (chaos_table_exists('guilds') && chaos_rows('SELECT `id` FROM `guilds` WHERE `ownerid` = ?;', array($id))) {
		$why[] = 'The character leads a guild. Pass the leadership on or disband the guild first.';
	} elseif (chaos_table_exists('guild_membership') && chaos_table_exists('guild_ranks')
		&& chaos_rows('SELECT `m`.`player_id` FROM `guild_membership` `m` JOIN `guild_ranks` `r` ON `r`.`id` = `m`.`rank_id` WHERE `m`.`player_id` = ? AND `r`.`level` >= 2;', array($id))) {
		$why[] = 'The character is a guild vice-leader. Pass the rank on or leave the guild first.';
	}
	if (chaos_table_exists('houses') && chaos_rows('SELECT `id` FROM `houses` WHERE `owner` = ?;', array($id))) {
		$why[] = 'The character owns a house. Leave the house first.';
	}
	if (chaos_table_exists('chaos_bazaar_listings')
		&& chaos_rows("SELECT `id` FROM `chaos_bazaar_listings` WHERE `player_id` = ? AND `status` IN ('active', 'settling');", array($id))) {
		$why[] = 'The character is listed in the Character Bazaar. Cancel the listing first.';
	}
	return $why;
}

/** True when the session has used up its wrong passwords in the window. */
function chaos_delete_throttled(array $session, int $now): bool {
	$fails = array();
	foreach ((array)($session['chaos_delete_fails'] ?? array()) as $t) {
		if ((int)$t > $now - CHAOS_DELETE_FAIL_WINDOW) {
			$fails[] = (int)$t;
		}
	}
	return count($fails) >= CHAOS_DELETE_MAX_FAILS;
}

/** The failures of a session kept after adding one at $now (the ones inside the window only). */
function chaos_delete_record_fail(array $session, int $now): array {
	$fails = array();
	foreach ((array)($session['chaos_delete_fails'] ?? array()) as $t) {
		if ((int)$t > $now - CHAOS_DELETE_FAIL_WINDOW) {
			$fails[] = (int)$t;
		}
	}
	$fails[] = $now;
	return $fails;
}

/**
 * Deletes a character. $post: csrf, player (id), name (typed), password. $csrf: the session's token. $session: the
 * session array (read for the throttle; the new failure list is returned as the third element). Returns
 * array(bool deleted, string message, array fails).
 */
function chaos_delete_character(int $accountId, array $post, string $csrf, array $session, int $now): array {
	$fails = (array)($session['chaos_delete_fails'] ?? array());
	if ($accountId <= 0) {
		return array(false, 'Please log in first.', $fails);
	}
	if ($csrf === '' || !hash_equals($csrf, (string)($post['csrf'] ?? ''))) {
		return array(false, 'The form expired. Please try again.', $fails);
	}
	if (chaos_delete_throttled($session, $now)) {
		return array(false, 'Too many wrong passwords. Wait a few minutes and try again.', $fails);
	}
	$playerId = (int)($post['player'] ?? 0);
	$player = $playerId > 0 ? db()->fetchOne('SELECT `id`, `name`, `level`, `group_id`, `vocation`, `account_id`, `deletion` FROM `players` WHERE `id` = ?;', array($playerId)) : false;
	if (!is_array($player) || (int)$player['deletion'] !== 0 || (int)$player['account_id'] !== $accountId) {
		return array(false, 'That character is not on your account.', $fails);
	}
	if (trim((string)($post['name'] ?? '')) === '' || strcasecmp(trim((string)$post['name']), (string)$player['name']) !== 0) {
		return array(false, 'Type the character\'s name exactly to confirm.', $fails);
	}
	$account = db()->fetchOne('SELECT `password` FROM `accounts` WHERE `id` = ?;', array($accountId));
	$stored = is_array($account) ? (string)$account['password'] : '';
	$salt = '';
	if (!function_exists('chaos_password_check_account') || $stored === ''
		|| !chaos_password_check_account($accountId, (string)($post['password'] ?? ''), $stored, $salt)) {
		$fails = chaos_delete_record_fail($session, $now);
		return array(false, 'The password is wrong.', $fails);
	}
	$why = chaos_delete_blockers($player);
	if ($why) {
		return array(false, $why[0], $fails);
	}
	// the players row first: if the database refuses (a foreign key of a table we do not know), nothing else was touched
	try {
		db()->execute('DELETE FROM `players` WHERE `id` = ? AND `account_id` = ?;', array($playerId, $accountId));
	} catch (Throwable $e) {
		error_log('[chaos delete character] ' . $e->getMessage());
		return array(false, 'The character could not be deleted. Tell the staff (it is logged).', $fails);
	}
	$left = db()->fetchOne('SELECT `id` FROM `players` WHERE `id` = ?;', array($playerId));
	if (is_array($left)) {
		return array(false, 'The character could not be deleted. Tell the staff (it is logged).', $fails);
	}
	foreach (chaos_delete_loose_tables() as $table => $column) {
		if (!chaos_table_exists($table)) {
			continue;
		}
		try {
			db()->execute('DELETE FROM `' . $table . '` WHERE `' . $column . '` = ?;', array($playerId));
		} catch (Throwable $e) {
			error_log('[chaos delete character] ' . $table . ': ' . $e->getMessage());
		}
	}
	return array(true, sprintf('%s was deleted.', (string)$player['name']), $fails);
}

/** The stock ZnoteX addresses of character deletion that lead to our page (lower case script names). */
function chaos_delete_stock_pages(): array {
	return array('deletecharacter.php', 'delete_character.php');
}

}
