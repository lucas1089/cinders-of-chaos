<?php
// php website/tests/chaos_community_page_test.php : the community goal on the website (plugins/chaos/community_lib.php,
// pages/community.php and the front page block of layouts/chaos/views/index.php) over an in-memory SQLite database
// with the game server's chaos_community_* tables: the current period only, the bar and its percent, the open stage
// buffs, the top contributors, the week's world modifiers (seed / staff), the news lines, escaping, an empty or missing
// set of tables, the realm labels of separate goals. No ZnoteX, no network. Exit status 0 when every check passes.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/community_lib.php';

$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$TABLES = true; // information_schema answer
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

// the tables as server/sql/chaos_community.sql makes them (SQLite types)
$pdo->exec("CREATE TABLE chaos_community_goal (period INT NOT NULL, realm INT NOT NULL DEFAULT 0, name TEXT NOT NULL DEFAULT '',
	target INT NOT NULL DEFAULT 0, progress INT NOT NULL DEFAULT 0, stage INT NOT NULL DEFAULT 0, finish INT NOT NULL DEFAULT 0,
	finished INT NOT NULL DEFAULT 0, updated_at INT NOT NULL DEFAULT 0, PRIMARY KEY (period, realm))");
$pdo->exec("CREATE TABLE chaos_community_buffs (period INT NOT NULL, realm INT NOT NULL DEFAULT 0, stage INT NOT NULL, name TEXT NOT NULL DEFAULT '',
	text TEXT NOT NULL DEFAULT '', started_at INT NOT NULL DEFAULT 0, ends_at INT NOT NULL DEFAULT 0, PRIMARY KEY (period, realm, stage))");
$pdo->exec("CREATE TABLE chaos_community_contrib (period INT NOT NULL, player_id INT NOT NULL, realm INT NOT NULL DEFAULT 0, name TEXT NOT NULL DEFAULT '',
	points INT NOT NULL DEFAULT 0, day INT NOT NULL DEFAULT 0, day_points INT NOT NULL DEFAULT 0, day_src TEXT NOT NULL DEFAULT '',
	place INT NOT NULL DEFAULT 0, token INT NOT NULL DEFAULT 0, rewarded INT NOT NULL DEFAULT 0, updated_at INT NOT NULL DEFAULT 0,
	PRIMARY KEY (period, player_id))");
$pdo->exec("CREATE TABLE chaos_community_week (week INT NOT NULL PRIMARY KEY, mods TEXT NOT NULL DEFAULT '', names TEXT NOT NULL DEFAULT '',
	texts TEXT, source TEXT NOT NULL DEFAULT 'seed', finish INT NOT NULL DEFAULT 0, updated_at INT NOT NULL DEFAULT 0)");
$pdo->exec("CREATE TABLE chaos_community_history (id INTEGER PRIMARY KEY AUTOINCREMENT, period INT NOT NULL DEFAULT 0, realm INT NOT NULL DEFAULT 0,
	kind TEXT NOT NULL DEFAULT '', text TEXT NOT NULL DEFAULT '', created_at INT NOT NULL DEFAULT 0)");

$now = 1791643020; // 2026-10-10 14:37 UTC
// last week's goal (ended) and this week's
$pdo->exec("INSERT INTO chaos_community_goal VALUES (20260928, 0, 'Fuel the Brazier', 1500000, 1600000, 4, " . ($now - 6 * 86400) . ", 1, 0)");
$pdo->exec("INSERT INTO chaos_community_goal VALUES (20261005, 0, 'Fuel the Brazier', 1500000, 912345, 2, " . ($now + 141780) . ", 0, $now)");
$pdo->exec("INSERT INTO chaos_community_buffs VALUES (20261005, 0, 1, 'Kindled Brazier', '+10% experience from monsters', " . ($now - 18000) . ", " . ($now + 68400) . ")");
$pdo->exec("INSERT INTO chaos_community_buffs VALUES (20261005, 0, 2, 'Ashen Bounty', '+10% Chaos loot quantity', " . ($now - 93600) . ", " . ($now - 7200) . ")");
$ins = $pdo->prepare("INSERT INTO chaos_community_contrib (period, player_id, realm, name, points, updated_at) VALUES (?, ?, 0, ?, ?, ?)");
foreach (array(array(20261005, 1, 'Vexa Nightbloom', 41250, 5), array(20261005, 2, 'Mira', 27410, 3), array(20261005, 3, '<b>Bold</b>', 33980, 4),
	array(20261005, 4, 'Zero', 0, 1), array(20260928, 5, 'Last Week', 99999, 1), array(20261005, 6, 'Tie Late', 27410, 9)) as $r) {
	$ins->execute($r);
}
$pdo->exec("INSERT INTO chaos_community_week VALUES (20260928, 'gilded_week', 'Gilded Week', 'Treasure goblins appear twice as often.', 'seed', " . ($now - 6 * 86400) . ", 0)");
$pdo->exec("INSERT INTO chaos_community_week VALUES (20261005, 'restless_dead,forgefire', 'Restless Dead|Forgefire',
	'Undead give 30% more experience and 30% more Chaos loot.|Crafting orbs cost 20% less: each orb used has a 20% chance to be kept.', 'seed', " . ($now + 141780) . ", 0)");
$pdo->exec("INSERT INTO chaos_community_history (period, realm, kind, text, created_at) VALUES
	(20261005, 0, 'stage', 'Community goal 25% reached! Kindled Brazier: +10% experience from monsters for 24 hours.', " . ($now - 18000) . "),
	(20261005, 0, 'override', 'staff note: not shown', " . ($now - 100) . "),
	(20260928, 0, 'end', 'The community goal ended at 100%. Top contributors: Last Week.', " . ($now - 6 * 86400) . ")");

// helpers
check(chaos_community_pct(912345, 1500000) === 60.8, 'percent with one decimal');
check(chaos_community_pct(3000000, 1500000) === 100.0, 'percent stops at 100');
check(chaos_community_pct(5, 0) === 0.0, 'no target');
check(chaos_community_left(93784) === '1d 2h' && chaos_community_left(4980) === '1h 23m' && chaos_community_left(5) === '1m', 'time left');
check(chaos_community_realm_name(0, 1) === '' && chaos_community_realm_name(0, 2) === 'Standard realm'
	&& chaos_community_realm_name(3, 2) === 'Season realm 3', 'realm labels');

// the state
$s = chaos_community_state($now);
check($s['ok'], 'tables found');
check(count($s['goals']) === 1 && $s['goals'][0]['progress'] === 912345 && $s['goals'][0]['pct'] === 60.8, 'only the running goal');
check($s['goals'][0]['left'] === 141780, 'time left of the goal');
$names = array_column($s['goals'][0]['top'], 'name');
check($names === array('Vexa Nightbloom', '<b>Bold</b>', 'Mira', 'Tie Late'), 'top: this period, points, ties by time, no zero rows');
check(count($s['buffs']) === 1 && $s['buffs'][0]['name'] === 'Kindled Brazier' && $s['buffs'][0]['left'] === 68400, 'only open buffs');
check($s['week'] && count($s['week']['mods']) === 2 && $s['week']['mods'][1]['name'] === 'Forgefire' && !$s['week']['staff'], 'this week');
check(count($s['news']) === 2 && strpos($s['news'][0]['text'], '25% reached') !== false, 'news: stages and ends only, newest first');

// the block
$html = chaos_community_block_html($s);
check(strpos($html, 'chaos-community__bar') !== false && strpos($html, 'style="width:60.8%"') !== false, 'the bar');
check(substr_count($html, 'chaos-community__mark') === 3, 'three stage marks');
check(strpos($html, '912,345 / 1,500,000  (60.8%)') !== false, 'the bar text');
check(strpos($html, 'Kindled Brazier') !== false && strpos($html, 'Ashen Bounty') === false, 'the open stage buff only');
check(strpos($html, 'Restless Dead') !== false && strpos($html, 'Gilded Week') === false, 'this week only');
check(strpos($html, 'Vexa') === false, 'the front page block has no table');
$full = chaos_community_block_html($s, true);
check(strpos($full, '&lt;b&gt;Bold&lt;/b&gt;') !== false && strpos($full, '<b>Bold</b>') === false, 'names escaped');
check(strpos($full, 'characterprofile.php?name=Vexa%20Nightbloom') !== false, 'profile links');
check(strpos($full, 'Latest') !== false && strpos($full, 'staff note') === false, 'news without staff lines');

// a staff override and separate realms
$pdo->exec("UPDATE chaos_community_week SET source = 'staff' WHERE week = 20261005");
$pdo->exec("INSERT INTO chaos_community_goal VALUES (20261005, 3, 'Fuel the Brazier', 1500000, 150000, 0, " . ($now + 141780) . ", 0, $now)");
$s2 = chaos_community_state($now);
check($s2['week']['staff'] && strpos(chaos_community_block_html($s2), 'set by the staff') !== false, 'staff override shown');
check(count($s2['goals']) === 2 && $s2['goals'][0]['realm_name'] === 'Standard realm' && $s2['goals'][1]['realm_name'] === 'Season realm 3', 'two realms');

// the page
function render_page(): string {
	global $config, $now;
	$chaos_page_now = $now;
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/community.php';
	return (string)ob_get_clean();
}
$page = render_page();
check(strpos($page, 'Community goal') !== false && strpos($page, 'chaos-community__top') !== false, 'the page renders with the table');
// no tables: nothing, and the page says so
$TABLES = false;
$GLOBALS['TABLES'] = false;
// chaos_table_exists caches per request: a new state call still says ok, so test the cache-free path through a fresh process
$cmd = escapeshellarg(PHP_BINARY) . ' -r ' . escapeshellarg('$GLOBALS["config"] = array(); require "' . __DIR__ . '/../overlay/plugins/chaos/lib.php"; require "'
	. __DIR__ . '/../overlay/plugins/chaos/community_lib.php"; final class D { function fetchOne($s, $p = array()) { return array("n" => 0); } '
	. 'function fetchAll($s, $p = array()) { return array(); } } function db() { return new D(); } $s = chaos_community_state(1); '
	. 'echo ($s["ok"] ? "ok" : "no") . "|" . chaos_community_block_html($s);');
check(trim((string)shell_exec($cmd)) === 'no|', 'no tables: no block');
// tables but nothing written yet: no block
$pdo->exec('DELETE FROM chaos_community_goal'); $pdo->exec('DELETE FROM chaos_community_week');
$GLOBALS['TABLES'] = true;
check(chaos_community_block_html(chaos_community_state($now)) === '', 'empty tables: no block');
check(strpos(render_page(), 'has not been lit yet') !== false, 'the page says so');

echo $failed === 0 ? "chaos_community_page_test: OK\n" : "chaos_community_page_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
