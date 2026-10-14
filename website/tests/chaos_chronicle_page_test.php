<?php
// php website/tests/chaos_chronicle_page_test.php : the Ashen Chronicle on the website (plugins/chaos/chronicle_lib.php,
// pages/chronicle.php) over an in-memory SQLite database with the game server's chaos_chronicle_* tables: the running
// season (chapter states, goal bars, the top contributors from the points), a finished season's record, the Memorial's
// "records" choice hiding a name (on the bars and in the record), escaping, missing tables. No ZnoteX, no network.
// Exit status 0 when every check passes.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/chronicle_lib.php';

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

// the tables as server/sql/chaos_chronicle.sql and chaos_memorial.sql make them (SQLite types)
$pdo->exec("CREATE TABLE chaos_chronicle_state (season INT PRIMARY KEY, arc TEXT NOT NULL DEFAULT '', chapter INT NOT NULL DEFAULT 1,
	done INT NOT NULL DEFAULT 0, started_at INT NOT NULL DEFAULT 0, finished_at INT NOT NULL DEFAULT 0, updated_at INT NOT NULL DEFAULT 0)");
$pdo->exec("CREATE TABLE chaos_chronicle_chapters (season INT NOT NULL, chapter INT NOT NULL, chapter_key TEXT NOT NULL DEFAULT '',
	title TEXT NOT NULL DEFAULT '', title_pt TEXT NOT NULL DEFAULT '', world TEXT NOT NULL DEFAULT '', world_pt TEXT NOT NULL DEFAULT '',
	done_at INT NOT NULL DEFAULT 0, PRIMARY KEY (season, chapter))");
$pdo->exec("CREATE TABLE chaos_chronicle_progress (season INT NOT NULL, chapter INT NOT NULL, goal INT NOT NULL, label TEXT NOT NULL DEFAULT '',
	progress INT NOT NULL DEFAULT 0, target INT NOT NULL DEFAULT 0, done_at INT NOT NULL DEFAULT 0, PRIMARY KEY (season, chapter, goal))");
$pdo->exec("CREATE TABLE chaos_chronicle_contrib (season INT NOT NULL, chapter INT NOT NULL, player_id INT NOT NULL, name TEXT NOT NULL DEFAULT '',
	points INT NOT NULL DEFAULT 0, updated_at INT NOT NULL DEFAULT 0, PRIMARY KEY (season, chapter, player_id))");
$pdo->exec("CREATE TABLE chaos_chronicle_record (season INT NOT NULL, chapter INT NOT NULL, place INT NOT NULL, player_id INT NOT NULL,
	name TEXT NOT NULL DEFAULT '', points INT NOT NULL DEFAULT 0, recorded_at INT NOT NULL DEFAULT 0, PRIMARY KEY (season, chapter, place))");
$pdo->exec("CREATE TABLE server_config (config TEXT PRIMARY KEY, value TEXT NOT NULL DEFAULT '')"); // season overrides (lib.php)
$pdo->exec("CREATE TABLE chaos_memorial_optin (player_id INT PRIMARY KEY, records INT NOT NULL DEFAULT 1, fallen INT NOT NULL DEFAULT 0,
	asked INT NOT NULL DEFAULT 1, updated_at INT NOT NULL DEFAULT 0)");

$now = 1795000000;
// season 1 finished with 3 chapters written; season 2 running, chapter 2 open
$pdo->exec("INSERT INTO chaos_chronicle_state VALUES (1, 's1', 4, 3, 100, " . ($now - 86400) . ", 0)");
$pdo->exec("INSERT INTO chaos_chronicle_state VALUES (2, 's1', 2, 1, $now, 0, 0)");
$ins = $pdo->prepare("INSERT INTO chaos_chronicle_chapters VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
foreach (array(1, 2) as $season) {
	$ins->execute(array($season, 1, 'ash_thickens', 'I. The Ash Thickens', 'I. As Cinzas se Adensam', 'Ash drifts mark the streets.', 'Montes de cinza.', $now - 5000));
	$ins->execute(array($season, 2, 'wound_walls', 'II. The Wound Beside the Walls', 'II. A Ferida ao Lado das Muralhas', '', '', $season === 1 ? $now - 4000 : 0));
	$ins->execute(array($season, 3, 'omens_ashfall', 'III. Omens in the Ashfall', 'III. Presságios na Chuva de Cinzas', '', '', $season === 1 ? $now - 3000 : 0));
}
$pdo->exec("INSERT INTO chaos_chronicle_progress VALUES (2, 2, 1, 'World bosses slain', 12, 30, 0), (2, 2, 2, 'Rifts sealed, tiers 6-10', 400, 800, 0),
	(2, 1, 1, 'Characters reaching level 100', 150, 150, " . ($now - 5000) . ")");
$c = $pdo->prepare("INSERT INTO chaos_chronicle_contrib VALUES (2, ?, ?, ?, ?, ?)");
foreach (array(array(2, 11, 'Vexa', 300, 5), array(2, 12, '<b>Bold</b>', 250, 3), array(2, 13, 'Hidden Hal', 280, 4), array(2, 14, 'Zero', 0, 1),
	array(1, 11, 'Vexa', 999, 1)) as $r) {
	$c->execute($r);
}
$pdo->exec("INSERT INTO chaos_chronicle_record VALUES (1, 1, 1, 13, 'Hidden Hal', 900, 1), (1, 1, 2, 11, 'Vexa', 800, 1), (1, 2, 1, 12, 'Mira', 50, 1)");
$pdo->exec("INSERT INTO chaos_memorial_optin VALUES (13, 0, 0, 1, 0), (11, 1, 1, 1, 0)");

check(chaos_chronicle_pct(400, 800) === 50.0 && chaos_chronicle_pct(5, 0) === 0.0 && chaos_chronicle_pct(900, 800) === 100.0, 'percent');
$s = chaos_chronicle_state(5, 5);
check($s['ok'], 'tables found');
check($s['current'] !== null && $s['current']['season'] === 2, 'the running season');
check(count($s['past']) === 1 && $s['past'][0]['season'] === 1 && $s['past'][0]['finished'], 'the finished season');
$cur = $s['current'];
check($cur['chapters'][0]['state'] === 'done' && $cur['chapters'][1]['state'] === 'open' && $cur['chapters'][2]['state'] === 'locked', 'chapter states');
check($cur['chapters'][1]['pct'] === 45.0, 'open chapter percent (mean of the goals): ' . $cur['chapters'][1]['pct']);
$names = array_column($cur['chapters'][1]['top'], 'name');
check($names === array('Vexa', CHAOS_CHRONICLE_HIDDEN, '<b>Bold</b>'), 'top: points order, a hidden name, no zero row: ' . implode(',', $names));
$past = $s['past'][0];
check($past['chapters'][0]['top'][0]['hidden'] && $past['chapters'][0]['top'][1]['name'] === 'Vexa', 'the record hides the same name');
check($past['chapters'][2]['state'] === 'done', 'a finished season keeps its written chapters');

$html = chaos_chronicle_season_html($cur, true);
check(strpos($html, 'World bosses slain: 12 / 30') !== false, 'goal bar text');
check(strpos($html, 'style="width:40.0%"') !== false, 'goal bar width');
check(strpos($html, 'Open: 45% written') !== false, 'open chapter line');
check(strpos($html, 'Ash drifts mark the streets.') !== false && strpos($html, 'Montes de cinza.') !== false, 'what changed, en and pt');
check(strpos($html, '&lt;b&gt;Bold&lt;/b&gt;') !== false && strpos($html, '<b>Bold</b>') === false, 'names escaped');
check(strpos($html, 'characterprofile.php?name=Hidden') === false && strpos($html, 'Hidden Hal') === false, 'a hidden name is never printed');
check(strpos($html, 'Not yet told') !== false, 'a locked chapter');
check(strpos($html, 'As Cinzas se Adensam') !== false, 'the Portuguese title');
$phtml = chaos_chronicle_season_html($past, false);
check(strpos($phtml, 'Hidden Hal') === false && strpos($phtml, 'Vexa') !== false, 'record html hides');
check(strpos($phtml, 'World bosses slain') === false, 'no bars in the record');

function render_page(): string {
	global $config;
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/chronicle.php';
	return (string)ob_get_clean();
}
$page = render_page();
check(strpos($page, 'The Ashen Chronicle') !== false && strpos($page, 'A Crônica das Cinzas') !== false, 'the page renders');
check(strpos($page, 'The record of') !== false, 'the page has the record');
check(strpos($page, 'p=memorial') !== false, 'the page links the Memorial');
// no tables: the page says so (fresh process: chaos_table_exists caches per request)
$cmd = escapeshellarg(PHP_BINARY) . ' -r ' . escapeshellarg('$GLOBALS["config"] = array(); require "' . __DIR__ . '/../overlay/plugins/chaos/lib.php"; require "'
	. __DIR__ . '/../overlay/plugins/chaos/chronicle_lib.php"; final class D { function fetchOne($s, $p = array()) { return array("n" => 0); } '
	. 'function fetchAll($s, $p = array()) { return array(); } } function db() { return new D(); } $s = chaos_chronicle_state(); '
	. 'echo ($s["ok"] ? "ok" : "no") . "|" . ($s["current"] === null ? "none" : "x");');
check(trim((string)shell_exec($cmd)) === 'no|none', 'no tables: nothing');
// empty tables: the blank first page
$pdo->exec('DELETE FROM chaos_chronicle_state');
check(strpos(render_page(), 'The first page is still blank') !== false, 'empty: the page says so');

echo $failed === 0 ? "chaos_chronicle_page_test: OK\n" : "chaos_chronicle_page_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
