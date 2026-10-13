<?php
// php website/tests/chaos_leaderboards_page_test.php : the Leaderboards page (plugins/chaos/lib.php, pages/leaderboards.php)
// over an in-memory SQLite database: the boards of the server's leaderboard_config.lua with their mode and format, the
// "min" boards (fastest kills) ranked lowest first and shown as m:ss like the client, the other boards highest first,
// staff left out, and the class tabs of the byClass boards (All classes first, the groups of the client, ranked again per
// class). No ZnoteX, no network. Exit status 0 when every check passes.
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
// the records tables (records.lua), empty until the server publishes its boards
$pdo->exec("CREATE TABLE chaos_records_boards (key TEXT PRIMARY KEY, cat TEXT, name TEXT, mode TEXT, format TEXT, label TEXT, variants TEXT, sizes TEXT, ord INT)");
$pdo->exec("CREATE TABLE chaos_records (slot TEXT, period TEXT, player_id INT, value INT, at INT, voc INT, party INT, members TEXT, count INT, PRIMARY KEY (slot, period, player_id))");
$pdo->exec("CREATE TABLE chaos_records_firsts (season TEXT, target TEXT, board TEXT, name TEXT, members TEXT, guids TEXT, value INT, at INT, PRIMARY KEY (season, target))");
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

// class tabs (byClass, leaderboard_config.lua): the Cinderheart boards have them, the others not
check(!empty($boards['cinder_solo']['byClass']) && !empty($boards['cinder_small']['byClass']) && !empty($boards['cinder_party']['byClass']), 'cinderheart boards: byClass');
check(empty($boards['worldboss']['byClass']) && empty($boards['raid_clear']['byClass']), 'worldboss / raid_clear: no class tabs');
foreach ($boards as $k => $b) {
	check(is_bool($b['byClass']), "$k: byClass read as a boolean");
}
// the groups of the game (LB.classGroups): one per base class, ordered by the base id, ascensions inside, retired ids
// with the class they move to
$groups = chaos_leaderboard_class_groups();
check(array_keys($groups) === array(1, 3, 4, 11, 17, 20, 23), 'class groups ordered by base id like the client');
check($groups[4]['name'] === 'Warrior' && $groups[4]['ids'] === array(4, 8, 14), 'Warrior group: 4, 8, 14');
check(in_array(2, $groups[1]['ids'], true) && in_array(6, $groups[1]['ids'], true) && in_array(9, $groups[1]['ids'], true), 'retired 2, 6, 9 in the Mystic group');

$pdo->exec("INSERT INTO players (id, name, group_id, vocation, level) VALUES (5, 'Fast Mystic', 1, 5, 280), (6, 'Old Mystic', 1, 9, 270),
	(7, 'Iron Juggernaut', 1, 8, 260)");
foreach (array(array(5, 200), array(6, 250), array(7, 350)) as $r) {
	$ins->execute(array('cinder_solo', $week, $r[0], $r[1], 10));
}
$renderClass = static function (string $board, ?string $class): string {
	global $config;
	$_GET = array('board' => $board);
	if ($class !== null) {
		$_GET['class'] = $class;
	}
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/leaderboards.php';
	return (string)ob_get_clean();
};
$rowsOf = static function (string $html): array {
	preg_match_all('#<tr class="[^"]*">\s*<td>(\d+)</td>\s*<td><a [^>]*>([^<]+)</a></td>\s*<td>[^<]*</td>\s*<td class="num">([^<]+)</td>#', $html, $m, PREG_SET_ORDER);
	return array_map(static function ($x) { return array((int)$x[1], $x[2], $x[3]); }, $m);
};
// All classes (default): every class, fastest first, m:ss
$html = $renderClass('cinder_solo', null);
check(strpos($html, 'aria-label="Classes"') !== false, 'cinder_solo shows class tabs');
$tabs = substr($html, (int)strpos($html, 'aria-label="Classes"'));
$tabs = substr($tabs, 0, (int)strpos($tabs, '</nav>'));
preg_match_all('#<a class="chaos-tab( is-active)?" href="([^"]+)"[^>]*>(?:<img[^>]*> )?([^<]+)</a>#', $tabs, $tm, PREG_SET_ORDER);
check(array_map('trim', array_column($tm, 3)) === array('All classes', 'Mystic', 'Ranger', 'Warrior', 'Thief', 'Monk', 'Necromancer', 'Templar'), 'class tabs: All classes first, then the client order');
check(($tm[0][1] ?? '') === ' is-active', 'All classes active by default');
check(strpos($tm[3][2] ?? '', 'board=cinder_solo&amp;class=4') !== false, 'Warrior tab links class=4');
check(array_column($rowsOf($html), 1) === array('Fast Mystic', 'Old Mystic', 'Quick Blade', 'Iron Juggernaut', 'Mid Arrow', 'Slow Hammer'), 'all classes: fastest first');
// Warrior tab: Warrior and its ascensions only, ranked again from 1, still m:ss
$rows = $rowsOf($renderClass('cinder_solo', '4'));
check(array_column($rows, 1) === array('Quick Blade', 'Iron Juggernaut', 'Slow Hammer'), 'Warrior tab: the Warrior line, fastest first');
check(array_column($rows, 0) === array(1, 2, 3), 'Warrior tab: ranks from 1');
check(array_column($rows, 2) === array('5:00', '5:50', '15:00'), 'Warrior tab: m:ss');
// Mystic tab: the retired id 9 counts as a Mystic
$html = $renderClass('cinder_solo', '1');
check(array_column($rowsOf($html), 1) === array('Fast Mystic', 'Old Mystic'), 'Mystic tab: Elementalist and the retired id');
check(strpos($html, 'Cinderheart Solo &middot; Mystic') !== false, 'heading names the class tab');
// a class without scores: the empty line names it; the other board tabs keep the class
$html = $renderClass('cinder_solo', '17');
check(strpos($html, 'No Monk on this board yet this week.') !== false, 'empty class tab message');
check(strpos($html, 'board=cinder_small&amp;class=17') !== false, 'board tab to another class board keeps the class');
check(strpos($html, 'board=worldboss&amp;class') === false, 'board tab to a board without class tabs drops the class');
// a bad class value or a board without class tabs: every class, no class tabs
check(array_column($rowsOf($renderClass('cinder_solo', '999')), 1) === array('Fast Mystic', 'Old Mystic', 'Quick Blade', 'Iron Juggernaut', 'Mid Arrow', 'Slow Hammer'), 'unknown class: every class');
check(array_column($rowsOf($renderClass('cinder_solo', '4 OR 1=1')), 1)[0] === 'Fast Mystic', 'non-numeric class: every class');
$html = $renderClass('worldboss', '4');
check(strpos($html, 'aria-label="Classes"') === false, 'worldboss: no class tabs');
check(count($rowsOf($html)) === 3 && strpos($html, 'Mid Arrow') !== false, 'worldboss: the class value is ignored');


// ---- records (records.lua): the boards the server published, the filters, ties to the earlier time, staff left out
check(strpos($renderClass('worldboss', null), 'No records yet') !== false, 'records: nothing before the server published boards');
$pdo->exec("INSERT INTO chaos_records_boards VALUES ('omen', 'bosses', 'Omen Guardians', 'min', 'time', 'Fastest', 'bloodmoon=Sangrith;storm=Thalcyra', 'solo=Solo;small=2-3;party=4-5', 1),
	('tower_floor', 'tower', 'Highest Floor', 'max', '', 'Floor', '', '', 2)");
$ri = $pdo->prepare('INSERT INTO chaos_records VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)');
foreach (array(array(1, 300, 50, 4), array(2, 280, 90, 8), array(3, 300, 40, 3), array(4, 100, 10, 4), array(7, 3700, 5, 8)) as $r) {
	$ri->execute(array('omen|storm|small', 'all', $r[0], $r[1], $r[2], $r[3], 2, 'A, B'));
}
$ri->execute(array('omen|bloodmoon|solo', 'all', 1, 500, 1, 4, 1, 'Quick Blade'));
$ri->execute(array('tower_floor|-|-', 'all', 1, 90, 1, 4, 1, ''));
$ri->execute(array('tower_floor|-|-', 'all', 2, 120, 1, 8, 1, ''));
$ri->execute(array('tower_floor|-|-', 'w' . $week, 1, 60, 1, 4, 1, ''));
$season = chaos_records_season_key(time());
$pdo->prepare("INSERT INTO chaos_records_firsts VALUES (?, 'ascended:cinder', 'ascended', 'Cinderheart', 'Quick Blade, Mid Arrow', '1,3', 900, 100)")->execute(array($season));
$renderRec = static function (array $get): string {
	global $config;
	$_GET = $get;
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/leaderboards.php';
	return (string)ob_get_clean();
};
$recRows = static function (string $html): array {
	$html = substr($html, (int)strpos($html, 'chaos-records'));
	preg_match_all('#<tr class="[^"]*">\s*<td>(\d+)</td>\s*<td><a [^>]*>([^<]+)</a></td>\s*<td>[^<]*</td>\s*<td class="num">([^<]+)</td>#', $html, $m, PREG_SET_ORDER);
	return array_map(static function ($x) { return array($x[2], $x[3]); }, $m);
};
$html = $renderRec(array('rb' => 'omen', 'rv' => 'storm', 'rs' => 'small', 'rp' => 'all'));
check(strpos($html, 'aria-label="Record boards"') !== false && strpos($html, 'aria-label="Party size"') !== false, 'records: board and size tabs');
check(array_column($recRows($html), 0) === array('Slow Hammer', 'Mid Arrow', 'Quick Blade', 'Iron Juggernaut'), 'records: fastest first, tie to the earlier time, staff left out');
check(array_column($recRows($html), 1) === array('4:40', '5:00', '5:00', '1:01:40'), 'records: m:ss and h:mm:ss');
check(strpos($html, 'title="A, B"') !== false, 'records: the party in the tooltip');
$html = $renderRec(array('rb' => 'omen', 'rv' => 'storm', 'rs' => 'small', 'rp' => 'all', 'rc' => '4'));
check(array_column($recRows($html), 0) === array('Slow Hammer', 'Quick Blade', 'Iron Juggernaut'), 'records: Warrior class tab (4, 8, 14)');
$html = $renderRec(array('rb' => 'omen', 'rv' => 'nope', 'rs' => 'zzz', 'rp' => 'all'));
check(array_column($recRows($html), 0) === array('Quick Blade'), 'records: bad filters fall back to the first variant and size');
$html = $renderRec(array('rb' => 'tower_floor', 'rp' => 'all'));
check(array_column($recRows($html), 0) === array('Slow Hammer', 'Quick Blade'), 'records: max board highest first');
check(strpos($html, 'aria-label="Party size"') === false, 'records: no size tabs on a board without sizes');
$html = $renderRec(array('rb' => 'tower_floor', 'rp' => 'week'));
check(array_column($recRows($html), 1) === array('60'), 'records: this week only');
$html = $renderRec(array('rb' => 'tower_floor', 'rp' => 'season'));
check(strpos($html, 'No result on this board in this view yet') !== false, 'records: empty season view');
check(strpos($html, 'Quick Blade, Mid Arrow') !== false && strpos($html, 'Cinderheart') !== false, 'records: realm firsts of the season');
check(chaos_records_value('pct', 4512) === '45.12%' && chaos_records_value('', 1500) === '1,500', 'records: value formats');
check(preg_match('/^(s\d+|q\d{5})$/', $season) === 1, 'records: season key');
check(count(chaos_records_categories()) === 6, 'records: categories read from records_config.lua');

echo $failed === 0 ? "chaos_leaderboards_page_test: OK\n" : "chaos_leaderboards_page_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
