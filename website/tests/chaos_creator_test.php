<?php
// php website/tests/chaos_creator_test.php : creator codes on the website (plugins/chaos/creator_lib.php,
// pages/creator.php) over an in-memory SQLite database: the settings read from the server's creator_codes_config.lua,
// the code format, a donor's pick (unknown, switched-off and own codes refused; clear; the window), a creator's totals,
// the administrator check (admin panel account AND a group 5+ character), creating / switching / re-pricing a code,
// the log, the referral link. No ZnoteX, no network. Exit status 0 when every check passes.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'), 'page_admin_access' => array('owner', 'helper'));
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/creator_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$TABLES = array('chaos_creator_codes' => true, 'chaos_creator_support' => true, 'chaos_creator_uses' => true, 'chaos_creator_log' => true,
	'chaos_referral_codes' => true);
final class FakeZnoteDb {
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
		if (strpos($sql, 'information_schema') !== false) { return array('n' => !empty($GLOBALS['TABLES'][$p[0]]) ? 1 : 0); }
		$r = $this->run($sql, $p)->fetch(PDO::FETCH_ASSOC);
		return $r === false ? false : $r;
	}
	public function fetchAll(string $sql, array $p = array()) { return $this->run($sql, $p)->fetchAll(PDO::FETCH_ASSOC); }
	public function execute(string $sql, array $p = array()) { $this->run($sql, $p); return true; }
}
$DB = new FakeZnoteDb($pdo);
function db() { return $GLOBALS['DB']; }

// the website's install.sql tables, turned into SQLite (the same columns)
$install = file_get_contents(__DIR__ . '/../overlay/plugins/chaos/install.sql');
preg_match_all('/CREATE TABLE IF NOT EXISTS `(chaos_creator_[a-z]+|chaos_pay_payers)` \((.*?)\) ENGINE/s', $install, $mm, PREG_SET_ORDER);
check(count($mm) === 5, 'install.sql has the five creator code tables');
foreach ($mm as $m) {
	$cols = array();
	foreach (preg_split('/,\n/', trim($m[2])) as $line) {
		$line = trim($line);
		if (preg_match('/^`(\w+)` (\w+)/', $line, $c)) {
			$auto = strpos($line, 'AUTO_INCREMENT') !== false;
			$cols[] = $c[1] . ($auto ? ' INTEGER PRIMARY KEY AUTOINCREMENT' : (preg_match('/int/', $c[2]) ? ' INTEGER' : ' TEXT') . " NOT NULL DEFAULT " . (preg_match('/int/', $c[2]) ? '0' : "''"));
		}
	}
	$pdo->exec('CREATE TABLE ' . $m[1] . ' (' . implode(', ', $cols) . ')');
}
$pdo->exec("CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT)");
$pdo->exec("CREATE TABLE players (id INTEGER PRIMARY KEY, name TEXT, account_id INT, level INT, group_id INT DEFAULT 1)");
$pdo->exec("CREATE TABLE chaos_referral_codes (account_id INT PRIMARY KEY, code TEXT)");
// invented accounts only
$pdo->exec("INSERT INTO accounts VALUES (1, 'owner'), (2, 'streamer'), (3, 'donor'), (4, 'helper')");
$pdo->exec("INSERT INTO players (id, name, account_id, level, group_id) VALUES (1, 'Owner God', 1, 8, 6), (2, 'Ember Streams', 2, 300, 1),
	(3, 'Donor Dee', 3, 90, 1), (4, 'Helper Gm', 4, 8, 3)");
$pdo->exec("INSERT INTO chaos_referral_codes VALUES (3, 'ABCD2345')");

// ---------------------------------------------------------------- settings from creator_codes_config.lua
$cfg = chaos_creator_config();
$lua = file_get_contents(__DIR__ . '/../../server/data/scripts/chaos/creator_codes_config.lua');
foreach (array('sharePct', 'supportDays', 'holdDays', 'orderCap', 'monthlyCap', 'adminGroup') as $k) {
	check(preg_match('/\b' . $k . ' = (\d+)/', $lua, $m) && (int)$m[1] === $cfg[$k], "$k read from the Lua file");
}
check($cfg['enabled'] === true, 'enabled read');
check($cfg['adminGroup'] === 5, 'administrators: group 5');

// ---------------------------------------------------------------- codes
check(chaos_creator_normalize('ember-streams') === 'EMBERSTREAMS', 'normalized');
check(chaos_creator_normalize('ab') === '', 'too short');
check(chaos_creator_normalize("x'; --") === '', 'quotes refused');

// ---------------------------------------------------------------- administrators
check(chaos_creator_is_admin($config, 1) === true, 'admin panel account with a god character');
check(chaos_creator_is_admin($config, 4) === false, 'admin panel account with only a gamemaster (group 3): no');
check(chaos_creator_is_admin($config, 2) === false, 'a player: no');
check(chaos_creator_is_admin($config, 0) === false, 'logged out: no');

[$ok, $msg] = chaos_creator_admin_create('ember', 'Ember Streams', 'Ember Streams', 0, 'twitch', 'web:owner');
check($ok, 'code created: ' . $msg);
[$ok, $msg] = chaos_creator_admin_create('EMBER', 'Donor Dee', '', 0, '', 'web:owner');
check(!$ok && strpos($msg, 'taken') !== false, 'a code is unique');
[$ok, $msg] = chaos_creator_admin_create('NEWONE', 'Nobody Here', '', 0, '', 'web:owner');
check(!$ok, 'unknown character refused');
[$ok, $msg] = chaos_creator_admin_create('X', 'Donor Dee', '', 0, '', 'web:owner');
check(!$ok, 'bad code refused');
[$ok, $msg] = chaos_creator_admin_create('PCTBAD', 'Donor Dee', '', 90, '', 'web:owner');
check(!$ok, 'own % over 50 refused');
$code = chaos_creator_find('ember');
check($code && (int)$code['account_id'] === 2 && (int)$code['active'] === 1, 'the code belongs to the streamer\'s account');

// ---------------------------------------------------------------- a donor's pick
$now = 1800000000;
[$ok, $msg] = chaos_creator_set_support(3, 'NOPE', '9.9.9.9', $now);
check(!$ok && strpos($msg, 'not an active') !== false, 'unknown code refused');
[$ok, $msg] = chaos_creator_set_support(2, 'EMBER', '8.8.8.8', $now);
check(!$ok && strpos($msg, 'own creator code') !== false, 'self-use refused');
check((int)$pdo->query("SELECT COUNT(*) FROM chaos_creator_log WHERE action = 'refused'")->fetchColumn() === 1, 'self-use logged');
[$ok, $msg] = chaos_creator_set_support(3, 'ember', '9.9.9.9', $now);
check($ok && strpos($msg, (string)$cfg['sharePct'] . '%') !== false && strpos($msg, 'no cost to you') !== false, 'picked: ' . $msg);
$pick = chaos_creator_support_of(3, $now + 10);
check($pick && $pick['code'] === 'EMBER' && (int)$pick['expires_at'] === $now + $cfg['supportDays'] * 86400, 'the pick and its window');
check(chaos_creator_support_of(3, $now + $cfg['supportDays'] * 86400 + 1) === null, 'the pick runs out');
check((string)$pdo->query('SELECT ip FROM chaos_creator_support WHERE account_id = 3')->fetchColumn() === '9.9.9.9', 'the address is kept for the same-connection check');
[$ok] = chaos_creator_set_support(3, 'EMBER', '9.9.9.9', $now + 100);
check($ok && (int)$pdo->query('SELECT COUNT(*) FROM chaos_creator_support WHERE account_id = 3')->fetchColumn() === 1, 'a new pick replaces the old');
[$ok, $msg] = chaos_creator_set_support(3, '', '', $now);
check($ok && chaos_creator_support_of(3, $now) === null, 'cleared');
check(chaos_creator_set_support(0, 'EMBER')[0] === false, 'logged out: refused');

// ---------------------------------------------------------------- switch off, own %
[$ok, $msg] = chaos_creator_admin_update((int)$code['id'], 'off', 0, 'web:owner');
check($ok, 'switched off');
[$ok, $msg] = chaos_creator_set_support(3, 'EMBER', '', $now);
check(!$ok, 'a switched-off code cannot be picked');
chaos_creator_admin_update((int)$code['id'], 'on', 0, 'web:owner');
chaos_creator_admin_update((int)$code['id'], 'pct', 8, 'web:owner');
[$ok, $msg] = chaos_creator_set_support(3, 'EMBER', '', $now);
check($ok && strpos($msg, '8%') !== false, 'the code\'s own % is shown');
check(chaos_creator_admin_update(999, 'off', 0, 'x')[0] === false, 'unknown code');

// ---------------------------------------------------------------- a creator's totals (rows the game server writes)
$cid = (int)$code['id'];
$pdo->exec("INSERT INTO chaos_creator_uses (order_id, code_id, creator_account_id, buyer_account_id, coins_base, share, state, reason, created_at) VALUES
	(1, $cid, 2, 3, 1000, 50, 'paid', '', 1), (2, $cid, 2, 3, 2000, 100, 'wait', 'hold', 2), (3, $cid, 2, 3, 500, 25, 'void', 'sameIp', 3)");
$mine = chaos_creator_codes_of(2);
check(count($mine) === 1 && $mine[0]['earned'] === 50 && $mine[0]['waiting'] === 100 && $mine[0]['paid'] === 1, 'earned 50, 100 waiting');
check($mine[0]['supporters'] === 1 && count($mine[0]['uses']) === 3, 'one supporter, three donations listed');
check(chaos_creator_codes_of(3) === array(), 'a donor owns no code');
$list = chaos_creator_admin_list();
check(count($list) === 1 && $list[0]['owner'] === 'Ember Streams' && (int)$list[0]['earned'] === 50 && (int)$list[0]['voided'] === 1, 'admin list');
check(count(chaos_creator_admin_log()) >= 5, 'the log');

// ---------------------------------------------------------------- referral link
check(chaos_referral_link(3, 'https://example.invalid/') === 'https://example.invalid/register?ref=ABCD2345', 'referral link');
check(chaos_referral_link(2, 'https://example.invalid') === '', 'no code yet: no link');

// ---------------------------------------------------------------- the page
$page = file_get_contents(__DIR__ . '/../overlay/plugins/chaos/pages/creator.php');
check(strpos($page, 'hash_equals($csrf') !== false, 'the page checks its CSRF token');
check(strpos($page, 'chaos_creator_is_admin') !== false && strpos($page, '$isAdmin && $_POST') !== false, 'admin actions only for administrators');
check(strpos($page, 'costs you nothing') !== false && strpos($page, 'voluntary') !== false, 'the page says it costs the donor nothing and donations are voluntary');
exec('php -l ' . escapeshellarg(__DIR__ . '/../overlay/plugins/chaos/pages/creator.php') . ' 2>&1', $out, $rc);
check($rc === 0, 'php -l pages/creator.php');

echo $failed === 0 ? "chaos_creator_test: $checks checks OK\n" : "chaos_creator_test: $failed of $checks checks FAILED\n";
exit($failed === 0 ? 0 : 1);
