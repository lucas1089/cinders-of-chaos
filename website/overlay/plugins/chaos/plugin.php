<?php
/**
 * Cinders of Chaos plugin: loaded by ZnoteX on every request (engine/init.php,
 * after the database and settings, before the page). Registers hooks only.
 *
 *  - Class lock: the base classes an account may create are the four open
 *    ones plus every locked line (Monk, Necromancer, Templar) the account has
 *    unlocked in `chaos_class_unlocks`. createcharacter.php validates the
 *    posted vocation against $config['available_vocations'], so narrowing it
 *    here is a server-side check, not only hidden options.
 *  - Character slots: $config['max_characters'] is the account's limit (free
 *    slots of pact_config.lua plus Character Slots bought in the store), so
 *    createcharacter.php refuses one more character server-side.
 *  - Optional starter depot boxes for new characters (the base server's
 *    ADD_DEPOT_BOXES_NEW_PLAYERS snippet), on the character.created hook. Off by
 *    default ($config['chaos']['depot_boxes']): !season join needs an empty depot.
 */

if (!isset($config)) {
	global $config;
}
if (!is_array($config)) {
	return;
}

require_once __DIR__ . '/lib.php';
// referral code on the account creation form (referral.php registers its own hooks)
require_once __DIR__ . '/referral.php';

// ---------------------------------------------------------------- class lock
// Session user, not $user_data: init.php loads the plugins before it reads the account.
$chaosAccountId = function_exists('getSession') ? (int)getSession('user_id') : 0;
$config['available_vocations'] = chaos_creatable_classes($chaosAccountId);
// ---------------------------------------------------------------- character slots
// free + Character Slots bought in the store (pact_config.lua, chaos_account_extras). createcharacter.php and the
// ZnoteX API refuse past $config['max_characters'] (staff: is_admin); the game server checks it again at login.
if ($chaosAccountId > 0) {
	$config['max_characters'] = chaos_character_limit($chaosAccountId);
}
unset($chaosAccountId);

// ---------------------------------------------------------------- new characters
znote_hook_register('character.created', static function (array $data): void {
	if (!chaos_cfg('depot_boxes', false) || !chaos_table_exists('player_depotitems') || !chaos_table_exists('towns')) {
		return;
	}
	$row = db()->fetchOne('SELECT `id` FROM `players` WHERE `name` = ? LIMIT 1;', [(string)($data['name'] ?? '')]);
	if (!is_array($row)) {
		return;
	}
	$playerId = (int)$row['id'];
	// one depot box of each kind (item ids 25453-25469, 29841-29844) in the depot of every town
	$boxes = array_merge(range(25453, 25469), range(29841, 29844));
	foreach (chaos_rows('SELECT `id` FROM `towns` ORDER BY `id`;') as $town) {
		$townId = (int)$town['id'];
		foreach ($boxes as $i => $itemType) {
			db()->execute('INSERT IGNORE INTO `player_depotitems` (`player_id`, `pid`, `sid`, `itemtype`, `count`, `attributes`) VALUES (?, ?, ?, ?, 1, \'\');',
				[$playerId, $townId, $townId * 100 + $i, $itemType]);
		}
	}
});
