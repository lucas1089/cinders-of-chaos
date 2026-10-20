<?php
// php website/tests/chaos_delete_character_test.php : deleting a character on the website (plugins/chaos/delete_lib.php,
// pages/deletecharacter.php, plugin.php's redirect of ZnoteX's own deletion addresses; owner report 2026-10-17
// "Deletar personagem no site nao funciona"). The rules (own character, offline, not staff, no guild lead, no house, no
// open bazaar listing), the form (CSRF token, the typed name, the account password, the wrong-password limit), what is
// removed (the players row, foreign-key children, the loose rows) and what is left alone. php-cli with pdo_sqlite, no
// ZnoteX, an in-memory SQLite database with foreign keys on.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));
$GLOBALS['config'] = $config;

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->exec('PRAGMA foreign_keys = ON');
final class ChaosDeleteFakeDb {
	public PDO $pdo;
	public function __construct(PDO $pdo) { $this->pdo = $pdo; }
	private function run(string $sql, array $p): PDOStatement {
		$st = $this->pdo->prepare($sql);
		foreach (array_values($p) as $i => $v) {
			$st->bindValue($i + 1, $v, is_int($v) ? PDO::PARAM_INT : PDO::PARAM_STR);
		}
		$st->execute();
		return $st;
	}
	public function fetchOne(string $sql, array $p = array()) {
		if (strpos($sql, 'information_schema') !== false) {
			$r = $this->pdo->prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' AND name = ?");
			$r->execute(array($p[0]));
			return $r->fetch(PDO::FETCH_ASSOC);
		}
		$r = $this->run($sql, $p)->fetch(PDO::FETCH_ASSOC);
		return $r === false ? false : $r;
	}
	public function fetchAll(string $sql, array $p = array()) { return $this->run($sql, $p)->fetchAll(PDO::FETCH_ASSOC); }
	public function execute(string $sql, array $p = array()) { $this->run($sql, $p); return true; }
}
$DB = new ChaosDeleteFakeDb($pdo);
function db() { return $GLOBALS['DB']; }
function DATABASE() { return ''; }

$pdo->exec('CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT, password TEXT)');
$pdo->exec('CREATE TABLE players (id INTEGER PRIMARY KEY, name TEXT, account_id INT NOT NULL, level INT, group_id INT DEFAULT 1, vocation INT DEFAULT 0, deletion INT DEFAULT 0)');
$pdo->exec('CREATE TABLE player_items (player_id INT NOT NULL, itemtype INT, FOREIGN KEY (player_id) REFERENCES players (id) ON DELETE CASCADE)');
$pdo->exec('CREATE TABLE players_online (player_id INT NOT NULL)');
$pdo->exec('CREATE TABLE guilds (id INTEGER PRIMARY KEY, ownerid INT NOT NULL)');
$pdo->exec('CREATE TABLE guild_ranks (id INTEGER PRIMARY KEY, level INT)');
$pdo->exec('CREATE TABLE guild_membership (player_id INT, rank_id INT)');
$pdo->exec('CREATE TABLE guild_invites (player_id INT, guild_id INT)');
$pdo->exec('CREATE TABLE houses (id INTEGER PRIMARY KEY, owner INT)');
$pdo->exec('CREATE TABLE chaos_bazaar_listings (id INTEGER PRIMARY KEY, player_id INT, status TEXT)');
$pdo->exec('CREATE TABLE znote_players (player_id INT, created INT)');
$pdo->exec('CREATE TABLE account_viplist (account_id INT, player_id INT)');
$pdo->exec('CREATE TABLE player_namelocks (player_id INT)');
$pdo->exec('CREATE TABLE chaos_player_titles (player_id INT)');
$pdo->exec('CREATE TABLE chaos_pvpzone_players (player_id INT)');
$pdo->exec('CREATE TABLE chaos_pocketboss (player_id INT)');
$pdo->exec('CREATE TABLE chaos_mentors (player_id INT)');
$pdo->exec('CREATE TABLE chaos_shop_history (id INTEGER PRIMARY KEY, player_id INT)');

$SESSION_USER = 7;
function getSession(string $k) { global $SESSION_USER; return $k === 'user_id' ? $SESSION_USER : null; }

require __DIR__ . '/../overlay/engine/function/chaos_password.php';
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/delete_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) {
		$failed++;
		echo "FAIL: $what\n";
	}
}
function exists(string $table, string $where): bool {
	global $pdo;
	return (int)$pdo->query("SELECT COUNT(*) FROM $table WHERE $where")->fetchColumn() > 0;
}

$pass = 'correct horse';
$hash = chaos_password_hash($pass, 1000);
$pdo->exec("INSERT INTO accounts VALUES (7, 'hunter', '$hash'), (8, 'other', '$hash')");
// 1 plain, 2 online, 3 guild leader, 4 vice-leader, 5 house owner, 6 listed in the bazaar, 7 staff, 9 someone else's
$pdo->exec("INSERT INTO players (id, name, account_id, level, group_id) VALUES (1, 'Plain Pete', 7, 120, 1), (2, 'Online Olga', 7, 80, 1),
	(3, 'Leader Lars', 7, 200, 1), (4, 'Vice Vera', 7, 150, 1), (5, 'House Hans', 7, 90, 1), (6, 'Listed Lena', 7, 300, 1),
	(7, 'Gamemaster Gus', 7, 1, 3), (9, 'Stranger', 8, 50, 1)");
$pdo->exec('INSERT INTO players_online VALUES (2)');
$pdo->exec('INSERT INTO guilds VALUES (1, 3)');
$pdo->exec('INSERT INTO guild_ranks VALUES (10, 2), (11, 1)');
$pdo->exec('INSERT INTO guild_membership VALUES (4, 10), (1, 11)');
$pdo->exec('INSERT INTO houses VALUES (1, 5)');
$pdo->exec("INSERT INTO chaos_bazaar_listings (player_id, status) VALUES (6, 'active')");
$pdo->exec('INSERT INTO player_items VALUES (1, 2160), (1, 2400), (9, 2160)');
$pdo->exec('INSERT INTO znote_players VALUES (1, 1), (9, 1)');
$pdo->exec('INSERT INTO account_viplist VALUES (8, 1), (8, 9)');
$pdo->exec('INSERT INTO guild_invites VALUES (1, 1)');
$pdo->exec('INSERT INTO chaos_player_titles VALUES (1), (9)');
$pdo->exec('INSERT INTO chaos_shop_history (player_id) VALUES (1)');

$now = 1790000000;
$csrf = 'tok123';
$form = static function (int $player, string $name, string $password, string $token = 'tok123'): array {
	return array('csrf' => $token, 'player' => (string)$player, 'name' => $name, 'password' => $password);
};

// ---------------------------------------------------------------- the list and the blockers
$list = chaos_delete_characters(7);
check(count($list) === 7, 'the account lists its seven characters, not the stranger: ' . count($list));
$byName = array();
foreach ($list as $c) { $byName[$c['name']] = $c; }
check(chaos_delete_blockers($byName['Plain Pete']) === array(), 'a plain character has no blocker');
check(count(chaos_delete_blockers($byName['Online Olga'])) === 1 && strpos(chaos_delete_blockers($byName['Online Olga'])[0], 'online') !== false, 'online blocks');
check(strpos(implode(' ', chaos_delete_blockers($byName['Leader Lars'])), 'leads a guild') !== false, 'a guild leader blocks');
check(strpos(implode(' ', chaos_delete_blockers($byName['Vice Vera'])), 'vice-leader') !== false, 'a vice-leader blocks');
check(strpos(implode(' ', chaos_delete_blockers($byName['House Hans'])), 'house') !== false, 'a house owner blocks');
check(strpos(implode(' ', chaos_delete_blockers($byName['Listed Lena'])), 'Bazaar') !== false, 'an open bazaar listing blocks');
check(strpos(implode(' ', chaos_delete_blockers($byName['Gamemaster Gus'])), 'Staff') !== false, 'staff blocks');
$pdo->exec("UPDATE chaos_bazaar_listings SET status = 'sold'");
check(chaos_delete_blockers($byName['Listed Lena']) === array(), 'a finished listing does not block');
$pdo->exec("UPDATE chaos_bazaar_listings SET status = 'active'");

// ---------------------------------------------------------------- refusals leave everything alone
[$ok, $msg] = chaos_delete_character(0, $form(1, 'Plain Pete', $pass), $csrf, array(), $now);
check(!$ok && strpos($msg, 'log in') !== false, 'logged out');
[$ok, $msg] = chaos_delete_character(7, $form(1, 'Plain Pete', $pass, 'forged'), $csrf, array(), $now);
check(!$ok && strpos($msg, 'expired') !== false, 'a wrong CSRF token is refused');
[$ok, $msg] = chaos_delete_character(7, $form(1, 'Plain Pete', $pass), '', array(), $now);
check(!$ok, 'no session token: refused');
[$ok, $msg] = chaos_delete_character(7, $form(9, 'Stranger', $pass), $csrf, array(), $now);
check(!$ok && strpos($msg, 'not on your account') !== false && exists('players', 'id = 9'), "someone else's character is refused");
[$ok, $msg] = chaos_delete_character(7, $form(1, 'Wrong Name', $pass), $csrf, array(), $now);
check(!$ok && strpos($msg, 'name') !== false && exists('players', 'id = 1'), 'the typed name must match');
[$ok, $msg] = chaos_delete_character(7, $form(1, '', $pass), $csrf, array(), $now);
check(!$ok && exists('players', 'id = 1'), 'an empty name is refused');
[$ok, $msg, $fails] = chaos_delete_character(7, $form(1, 'Plain Pete', 'nope'), $csrf, array(), $now);
check(!$ok && strpos($msg, 'password') !== false && exists('players', 'id = 1') && $fails === array($now), 'a wrong password is refused and counted');
foreach (array('Online Olga' => 2, 'Leader Lars' => 3, 'Vice Vera' => 4, 'House Hans' => 5, 'Listed Lena' => 6, 'Gamemaster Gus' => 7) as $n => $id) {
	[$ok, $msg] = chaos_delete_character(7, $form($id, $n, $pass), $csrf, array(), $now);
	check(!$ok && exists('players', "id = $id"), "$n: blocked, still there ($msg)");
}
[$ok, $msg] = chaos_delete_character(7, $form(999, 'Nobody', $pass), $csrf, array(), $now);
check(!$ok, 'a character that does not exist');

// ---------------------------------------------------------------- the wrong-password limit
$session = array('chaos_delete_fails' => array($now - 10, $now - 20, $now - 30, $now - 40, $now - 50));
check(chaos_delete_throttled($session, $now), 'five wrong passwords in 15 minutes: throttled');
[$ok, $msg] = chaos_delete_character(7, $form(1, 'Plain Pete', $pass), $csrf, $session, $now);
check(!$ok && strpos($msg, 'Too many') !== false && exists('players', 'id = 1'), 'throttled even with the right password');
check(!chaos_delete_throttled($session, $now + 1000), 'the failures age out');
check(chaos_delete_record_fail(array('chaos_delete_fails' => array($now - 5000)), $now) === array($now), 'old failures are dropped when one is added');

// ---------------------------------------------------------------- a real deletion
[$ok, $msg, $fails] = chaos_delete_character(7, $form(1, 'plain pete', $pass), $csrf, array(), $now);
check($ok && $msg === 'Plain Pete was deleted.', "deleted (name matched without case): $msg");
check(!exists('players', 'id = 1'), 'the players row is gone');
check(!exists('player_items', 'player_id = 1') && exists('player_items', 'player_id = 9'), 'items went by the foreign key, the stranger keeps its own');
check(!exists('znote_players', 'player_id = 1') && exists('znote_players', 'player_id = 9'), 'the website row went');
check(!exists('account_viplist', 'player_id = 1') && exists('account_viplist', 'player_id = 9'), "other accounts' VIP entry for it went");
check(!exists('guild_invites', 'player_id = 1'), 'guild invites went');
check(!exists('chaos_player_titles', 'player_id = 1') && exists('chaos_player_titles', 'player_id = 9'), 'live Chaos rows went');
check(exists('chaos_shop_history', 'player_id = 1'), 'the purchase history stays');
check(count(chaos_delete_characters(7)) === 6, 'the list has one less');
[$ok, $msg] = chaos_delete_character(7, $form(1, 'Plain Pete', $pass), $csrf, array(), $now);
check(!$ok, 'deleting it again is refused');

// ---------------------------------------------------------------- the stock addresses and the page
check(chaos_delete_stock_pages() === array('deletecharacter.php', 'delete_character.php'), 'the stock addresses');
$plugin = file_get_contents(__DIR__ . '/../overlay/plugins/chaos/plugin.php');
check(strpos($plugin, 'chaos_delete_stock_pages()') !== false && strpos($plugin, 'p=deletecharacter') !== false, 'plugin.php sends them to our page');
check(strpos(file_get_contents(__DIR__ . '/../overlay/plugins/chaos/seo_lib.php'), 'page_chaos_deletecharacter') !== false, 'the page is not indexed');

$pdo->exec("INSERT INTO players (id, name, account_id, level, group_id) VALUES (10, 'Spare Sam', 7, 20, 1)");
$_SERVER['REQUEST_METHOD'] = 'GET';
ob_start();
include __DIR__ . '/../overlay/plugins/chaos/pages/deletecharacter.php';
$html = ob_get_clean();
check(strpos($html, 'Spare Sam') !== false && strpos($html, 'Type the name to confirm') !== false, 'the page lists the characters with a form');
check(strpos($html, 'name="password"') !== false && strpos($html, 'name="csrf"') !== false, 'the form has the password and the token');
check(strpos($html, 'Plain Pete') === false, 'a deleted character is not listed');
check(substr_count($html, 'cannot be deleted now') === 6, 'six characters show their reason instead of a form: ' . substr_count($html, 'cannot be deleted now'));
$SESSION_USER = 0;
ob_start();
include __DIR__ . '/../overlay/plugins/chaos/pages/deletecharacter.php';
$html = ob_get_clean();
check(strpos($html, 'log in') !== false && strpos($html, 'Online Olga') === false, 'logged out: only the login note');

echo $failed ? "chaos_delete_character_test: $failed of $checks checks FAILED\n" : "chaos_delete_character_test: $checks checks OK\n";
exit($failed ? 1 : 0);
