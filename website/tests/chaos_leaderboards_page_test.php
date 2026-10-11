<?php
// php website/tests/chaos_leaderboards_page_test.php : the Leaderboards page (plugins/chaos/lib.php, pages/leaderboards.php)
// over an in-memory SQLite database: the boards of the server's leaderboard_config.lua with their mode and format, the
// "min" boards (fastest kills) ranked lowest first and shown as m:ss like the client, the other boards highest first,
// staff left out. No ZnoteX, no network. Exit status 0 when every check passes.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';

$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
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
		if (strpos($sql, 'information_schema') !== false) {
			$n = $this->run("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?", $p)->fetchColumn();
			return array('n' => (int)$n);
		}
		$r = $this->run($sql, $p)->fetch(PDO::FETCH_ASSOC);
		return $r === false ? false : $r;
	}
	public function fetchAll(string $sql, array $p = array()) { return $this->run($sql, $p)->fetchAll(PDO::FETCH_ASSOC); }
	public function execute(string $sql, array $p = array()) { $this->run($sql, $p); return true; }
}
$DB = new FakeZnoteDb($pdo);
function db() { return $GLOBALS['DB']; }
function znote_plugin_asset(string $plugin, string $path): string { return 'plugins/' . $plugin . '/assets/' . $path; }

$pdo->exec("CREATE TABLE players (id INTEGER PRIMARY KEY, name TEXT NOT NULL, account_id INT NOT NULL DEFAULT 1, group_id INT NOT NULL DEFAULT 1,
	vocation INT NOT NULL DEFAULT 0, level INT NOT NULL DEFAULT 1, experience INT NOT NULL DEFAULT 0, deletion INT NOT NULL DEFAULT 0)");
$pdo->exec("CREATE TABLE chaos_leaderboard (board TEXT NOT NULL, week INT NOT NULL, player_id INT NOT NULL, value INT NOT NULL DEFAULT 0,
	count INT NOT NULL DEFAULT 0, updated_at INT NOT NULL DEFAULT 0, PRIMARY KEY (board, week, player_id))");
$pdo->exec("INSERT INTO players (id, name, group_id, vocation, level) VALUES (1, 'Quick Blade', 1, 4, 300), (2, 'Slow Hammer', 1, 8, 310),
	(3, 'Mid Arrow', 1, 3, 290), (4, 'Staff Ember', 6, 4, 500)");

// the boards come from the server's leaderboard_config.lua, with mode and format
$boards = chaos_leaderboard_boards();
check(isset($boards['cinder_solo']), 'cinder_solo board read from leaderboard_config.lua');
check(($boards['cinder_solo']['mode'] ?? '') === 'min' && ($boards['cinder_solo']['format'] ?? '') === 'time', 'cinder_solo: mode min, format time');
check(($boards['raid_clear']['mode'] ?? '') === 'min', 'raid_clear: mode min');
check(($boards['worldboss']['mode'] ?? '') === 'add' && ($boards['worldboss']['format'] ?? 'x') === '', 'worldboss: mode add, no format');

// value text: m:ss for time boards (TabRows.valueText), grouped numbers otherwise
check(chaos_leaderboard_value($boards['cinder_solo'], 754) === '12:34', 'time 754 s = 12:34');
check(chaos_leaderboard_value($boards['cinder_solo'], 59) === '0:59', 'time 59 s = 0:59');
check(chaos_leaderboard_value($boards['worldboss'], 1234567) === '1,234,567', 'damage grouped');

$week = chaos_week_key(time(), 6);
$ins = $pdo->prepare('INSERT INTO chaos_leaderboard (board, week, player_id, value, count, updated_at) VALUES (?, ?, ?, ?, 1, ?)');
foreach (array(array(1, 300), array(2, 900), array(3, 450), array(4, 100)) as $r) {
	$ins->execute(array('cinder_solo', $week, $r[0], $r[1], 10));
	$ins->execute(array('worldboss', $week, $r[0], $r[1], 10));
}

// rendered page: the fastest kill first on the time board, the highest damage first on the damage board
$render = static function (string $board): string {
	global $config;
	$_GET = array('board' => $board);
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/leaderboards.php';
	return (string)ob_get_clean();
};
$html = $render('cinder_solo');
$a = strpos($html, 'Quick Blade'); $b = strpos($html, 'Mid Arrow'); $c = strpos($html, 'Slow Hammer');
check($a !== false && $b !== false && $c !== false && $a < $b && $b < $c, 'cinder_solo ranked fastest first');
check(strpos($html, '>5:00<') !== false && strpos($html, '>15:00<') !== false, 'cinder_solo values shown as m:ss');
check(strpos($html, 'Staff Ember') === false, 'staff left out of the board');
$html = $render('worldboss');
$a = strpos($html, 'Slow Hammer'); $b = strpos($html, 'Mid Arrow'); $c = strpos($html, 'Quick Blade');
check($a !== false && $b !== false && $c !== false && $a < $b && $b < $c, 'worldboss ranked highest first');
check(strpos($html, '>900<') !== false, 'worldboss value as a number');

echo $failed === 0 ? "chaos_leaderboards_page_test: OK\n" : "chaos_leaderboards_page_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
