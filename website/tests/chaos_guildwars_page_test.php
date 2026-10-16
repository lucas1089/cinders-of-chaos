<?php
// php website/tests/chaos_guildwars_page_test.php : the guild wars page (plugins/chaos/guildwar_lib.php,
// pages/guildwars.php) over an in-memory SQLite database with the game server's chaos_guildwar tables: running wars
// only in "Wars now" (score, terms, time left), ended wars only in the history (winner, payout, draw, end reason, the
// kills that did not count), pending / declined offers nowhere, escaping, links, missing tables. No ZnoteX, no network.
// Exit status 0 when every check passes.
$config = array('chaos' => array());
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/guildwar_lib.php';

$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$TABLES = true;
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
		if (strpos($sql, 'information_schema') !== false) { return array('n' => $GLOBALS['TABLES'] ? 1 : 0); }
		$r = $this->run($sql, $p)->fetch(PDO::FETCH_ASSOC);
		return $r === false ? false : $r;
	}
	public function fetchAll(string $sql, array $p = array()) { return $this->run($sql, $p)->fetchAll(PDO::FETCH_ASSOC); }
	public function execute(string $sql, array $p = array()) { $this->run($sql, $p); return true; }
}
$DB = new FakeZnoteDb($pdo);
function db() { return $GLOBALS['DB']; }

// the tables as server/sql/chaos_guildwar.sql makes them (SQLite types)
$pdo->exec("CREATE TABLE chaos_guildwar (id INTEGER PRIMARY KEY, war_id INT NOT NULL DEFAULT 0, guild1 INT NOT NULL, guild2 INT NOT NULL,
	name1 TEXT NOT NULL DEFAULT '', name2 TEXT NOT NULL DEFAULT '', realm INT NOT NULL DEFAULT 0, frag_limit INT NOT NULL DEFAULT 0,
	hours INT NOT NULL DEFAULT 0, stake INT NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'pending', declared_by INT NOT NULL DEFAULT 0,
	declared_at INT NOT NULL DEFAULT 0, expires_at INT NOT NULL DEFAULT 0, started_at INT NOT NULL DEFAULT 0, ends_at INT NOT NULL DEFAULT 0,
	ended_at INT NOT NULL DEFAULT 0, kills1 INT NOT NULL DEFAULT 0, kills2 INT NOT NULL DEFAULT 0, winner INT NOT NULL DEFAULT 0,
	reason TEXT NOT NULL DEFAULT '', escrow1 INT NOT NULL DEFAULT 0, escrow2 INT NOT NULL DEFAULT 0, payout INT NOT NULL DEFAULT 0,
	fee INT NOT NULL DEFAULT 0)");
$pdo->exec("CREATE TABLE chaos_guildwar_kills (id INTEGER PRIMARY KEY, war_id INT NOT NULL, at INT NOT NULL, killer_id INT NOT NULL DEFAULT 0,
	killer_name TEXT NOT NULL DEFAULT '', killer_guild INT NOT NULL DEFAULT 0, victim_id INT NOT NULL DEFAULT 0, victim_name TEXT NOT NULL DEFAULT '',
	victim_guild INT NOT NULL DEFAULT 0, victim_level INT NOT NULL DEFAULT 0, counted INT NOT NULL DEFAULT 0, reason TEXT NOT NULL DEFAULT '')");

$now = 1791643020;
$ins = $pdo->prepare("INSERT INTO chaos_guildwar (id, guild1, guild2, name1, name2, frag_limit, hours, stake, status, started_at, ends_at, ended_at,
	kills1, kills2, winner, reason, payout) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
// a running war, a pending offer, a declined one, a war won by the frag limit, a draw, a surrender
$ins->execute(array(1, 10, 20, 'Ashen Wolves', 'Iron Crows', 25, 24, 500000, 'active', $now - 3600, $now + 82800, 0, 7, 3, 0, '', 0));
$ins->execute(array(2, 30, 10, 'Night Pact', 'Ashen Wolves', 10, 6, 0, 'pending', 0, 0, 0, 0, 0, 0, '', 0));
$ins->execute(array(3, 30, 20, 'Night Pact', 'Iron Crows', 10, 6, 0, 'declined', 0, 0, $now - 500, 0, 0, 0, 'declined', 0));
$ins->execute(array(4, 20, 30, 'Iron Crows', '<b>Bold</b>', 10, 24, 1000000, 'ended', $now - 90000, $now - 3600, $now - 7200, 10, 4, 20, 'limit', 1800000));
$ins->execute(array(5, 10, 30, 'Ashen Wolves', '<b>Bold</b>', 50, 6, 0, 'ended', $now - 30000, $now - 8400, $now - 8400, 5, 5, 0, 'time', 0));
$ins->execute(array(6, 10, 20, 'Ashen Wolves', 'Iron Crows', 25, 72, 200000, 'ended', $now - 200000, $now - 1000, $now - 100000, 2, 0, 20, 'surrender', 360000));
$k = $pdo->prepare("INSERT INTO chaos_guildwar_kills (war_id, at, counted, reason) VALUES (?, ?, ?, ?)");
foreach (array(array(4, 1, 1, 'ok'), array(4, 2, 0, 'same IP'), array(4, 3, 0, 'repeat'), array(4, 4, 1, 'ok'), array(1, 5, 1, 'ok')) as $r) {
	$k->execute($r);
}

// helpers
check(chaos_guildwar_left(93784) === '1d 2h' && chaos_guildwar_left(4980) === '1h 23m' && chaos_guildwar_left(5) === '1m', 'time left');
check(chaos_guildwar_reason('limit') === 'frag limit reached' && chaos_guildwar_reason('surrender') === 'surrender', 'reasons');
check(chaos_guildwar_terms(array('frag_limit' => 25, 'hours' => 24, 'stake' => 500000)) === 'first to 25 kills, 24 hours, 500,000 gold at stake per side', 'terms');
check(chaos_guildwar_terms(array('frag_limit' => 10, 'hours' => 6, 'stake' => 0)) === 'first to 10 kills, 6 hours, no stake', 'terms, no stake');

// the state
$s = chaos_guildwar_state($now);
check($s['ok'], 'tables found');
check(count($s['active']) === 1 && $s['active'][0]['id'] === 1, 'only the running war is current');
check($s['active'][0]['left'] === 82800 && $s['active'][0]['kills1'] === 7, 'score and time left');
check(array_column($s['history'], 'id') === array(4, 5, 6), 'history: ended wars only, newest first');
check($s['history'][0]['winner'] === 'Iron Crows' && $s['history'][0]['payout'] === 1800000, 'winner and payout');
check($s['history'][0]['counted'] === 2 && $s['history'][0]['refused'] === 2, 'counted and refused kills');
check($s['history'][1]['winner'] === '' && $s['history'][1]['reason'] === 'time is up', 'a draw');
check($s['history'][2]['reason'] === 'surrender', 'a surrender');

// the html
$html = chaos_guildwar_html($s);
check(strpos($html, 'Wars now') !== false && strpos($html, 'History') !== false, 'two sections');
check(strpos($html, '7 : 3') !== false && strpos($html, '23h 0m') !== false, 'running score and time');
check(strpos($html, 'Night Pact') === false, 'pending and declined offers are not shown');
check(strpos($html, '&lt;b&gt;Bold&lt;/b&gt;') !== false && strpos($html, '<b>Bold</b>') === false, 'names escaped');
check(strpos($html, 'guilds?name=Iron%20Crows') !== false, 'guild links');
check(strpos($html, 'Iron Crows won') !== false && strpos($html, '1,800,000 gold') !== false, 'won with the payout');
check(strpos($html, 'Draw') !== false, 'draw shown');

// the page
function render_page(): string {
	global $config;
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/guildwars.php';
	return (string)ob_get_clean();
}
$page = render_page();
check(strpos($page, 'Guild Wars') !== false && strpos($page, 'chaos-wars') !== false, 'the page renders with the tables');

// no tables: no board, the page says so (chaos_table_exists caches per request: a fresh process)
$cmd = escapeshellarg(PHP_BINARY) . ' -r ' . escapeshellarg('$GLOBALS["config"] = array(); require "' . __DIR__ . '/../overlay/plugins/chaos/lib.php"; require "'
	. __DIR__ . '/../overlay/plugins/chaos/guildwar_lib.php"; final class D { function fetchOne($s, $p = array()) { return array("n" => 0); } '
	. 'function fetchAll($s, $p = array()) { return array(); } } function db() { return new D(); } $s = chaos_guildwar_state(1); '
	. 'echo ($s["ok"] ? "ok" : "no") . "|" . chaos_guildwar_html($s);');
check(trim((string)shell_exec($cmd)) === 'no|', 'no tables: nothing');
// tables but empty
$pdo->exec('DELETE FROM chaos_guildwar');
$empty = chaos_guildwar_html(chaos_guildwar_state($now));
check(strpos($empty, 'No guilds are at war.') !== false && strpos($empty, 'No war has ended yet.') !== false, 'empty tables');

echo $failed === 0 ? "chaos_guildwars_page_test: OK\n" : "chaos_guildwars_page_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
