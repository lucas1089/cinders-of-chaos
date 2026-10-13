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
 *  - New characters wear their class's look (class_looks_core.lua, both addons) from the start, not ZnoteX's starter
 *    outfit, on the character.created hook (website form and client, chaos_client_api.php).
 *  - Optional starter depot boxes for new characters (the base server's
 *    ADD_DEPOT_BOXES_NEW_PLAYERS snippet), on the character.created hook. Off by
 *    default ($config['chaos']['depot_boxes']): !season join needs an empty depot.
 *  - Mail and account recovery: mail_lib.php (one sender, off without SMTP settings) and recovery_lib.php (a
 *    one-time reset link; recovery.php hands over to recovery_page.php).
 *  - Legal texts (legal_lib.php, pages/legal.php): Terms of Use, Privacy Policy, Donation Terms; account creation
 *    needs the Terms checkbox, and the acceptance is recorded. A logged-in account without the acceptance of the
 *    current texts is sent to pages/accept.php first.
 *  - The stock pages this server does not use (shop, points, creatures, spells,
 *    forum, the stock payment callbacks) send the visitor to pages/notused.php.
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
// account creation: per-IP limit (register_guard.php registers its own hook)
require_once __DIR__ . '/register_guard.php';
// the legal texts (pages/legal.php), the Terms checkbox of account creation and the donation notices (legal_lib.php)
require_once __DIR__ . '/legal_lib.php';
// site mail (SMTP from config.local.php, off without it) and recovery by a one-time link (recovery.php, README "Mail")
require_once __DIR__ . '/mail_lib.php';
require_once __DIR__ . '/recovery_lib.php';
// a logged-in session ends when the account's password changes (recovery link, another device, the game)
require_once __DIR__ . '/session_guard.php';
// the community goal and the week's world modifiers (read only: the front page block and pages/community.php)
require_once __DIR__ . '/community_lib.php';
// item and outfit images drawn from our client pair (chaos-sprites/, chaos_outfit.php; README "Sprite images")
require_once __DIR__ . '/sprite_lib.php';

// ---------------------------------------------------------------- pages not used on this server
// The stock shop, points, creature / spell library and forum pages (chaos_unused_pages) lead to the short note of
// pages/notused.php instead: the store is in the game, the forum is off. Only the site's own root scripts; the admin
// panel is untouched. setup/chaos_setup.php hides their menu entries, setup/write_config.php switches them off.
$chaosScript = (string)($_SERVER['SCRIPT_FILENAME'] ?? '');
$chaosWhat = chaos_unused_pages()[strtolower(basename($chaosScript))] ?? null;
if ($chaosWhat !== null && PHP_SAPI !== 'cli' && realpath(dirname($chaosScript)) === realpath(__DIR__ . '/../..')) {
	header('Location: page.php?plugin=chaos&p=notused&what=' . $chaosWhat, true, 302);
	exit;
}
unset($chaosScript, $chaosWhat);

// ---------------------------------------------------------------- Terms for existing accounts
// A logged-in account without the acceptance of the current texts (the beta accounts made before the sign-up
// checkbox; everyone after the texts change) goes to page.php?plugin=chaos&p=accept first, then back. The accept page,
// the legal texts, login, logout, register, recovery and the donation webhook pass (legal_lib.php).
$chaosAccountId = function_exists('getSession') ? (int)getSession('user_id') : 0;
if ($chaosAccountId > 0 && PHP_SAPI !== 'cli') {
	$chaosGate = chaos_legal_gate_target($chaosAccountId, (string)($_SERVER['SCRIPT_NAME'] ?? ''), $_GET, $_SERVER);
	if ($chaosGate !== null) {
		header('Location: ' . $chaosGate, true, 303);
		exit;
	}
	unset($chaosGate);
}

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
// The class's look (class_looks_core.lua, both addons) instead of ZnoteX's starter outfit, so the character lists of
// the client and the site show the class from the start; the game server puts the same look on at the first login.
znote_hook_register('character.created', static function (array $data): void {
	chaos_apply_class_look((string)($data['name'] ?? ''));
});
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
