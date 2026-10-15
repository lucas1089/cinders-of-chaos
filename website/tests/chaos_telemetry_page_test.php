<?php
// php website/tests/chaos_telemetry_page_test.php : the staff page of balance telemetry (plugins/chaos/pages/
// telemetry.php, telemetry_lib.php) rendered with php-cli over an in-memory SQLite database built from
// server/sql/chaos_telemetry.sql: access (admin panel account AND a character of group 5+), filter validation, the
// rates and their small-group rule, online averages, bosses, deaths, casts, faucets and sinks, store coins per category,
// SVG charts without script or external files, escaping. No ZnoteX, no network. Exit status 0 when every check passes.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'), 'page_admin_access' => array('staffacc', 'helperacc'));
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/telemetry_lib.php';

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
		if (strpos($sql, 'information_schema') !== false) { return array('n' => 1); }
		$r = $this->run($sql, $p)->fetch(PDO::FETCH_ASSOC);
		return $r === false ? false : $r;
	}
	public function fetchAll(string $sql, array $p = array()) { return $this->run($sql, $p)->fetchAll(PDO::FETCH_ASSOC); }
	public function execute(string $sql, array $p = array()) { $this->run($sql, $p); return true; }
}
$DB = new FakeZnoteDb($pdo);
function db() { return $GLOBALS['DB']; }

// the server's tables, turned into SQLite (the same columns)
$sqlFile = file_get_contents(__DIR__ . '/../../server/sql/chaos_telemetry.sql');
preg_match_all('/CREATE TABLE IF NOT EXISTS `(\w+)` \((.*?)\) ENGINE/s', $sqlFile, $mm, PREG_SET_ORDER);
check(count($mm) === 6, 'six telemetry tables in the server SQL');
foreach ($mm as $m) {
	$cols = preg_replace('/, KEY `\w+` \([^)]*\)/', '', $m[2]);
	$cols = str_replace(array(' unsigned', 'bigint', 'smallint', 'tinyint'), array('', 'INTEGER', 'INTEGER', 'INTEGER'), $cols);
	$pdo->exec("CREATE TABLE `{$m[1]}` ($cols)");
}
$pdo->exec("CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT NOT NULL)");
$pdo->exec("INSERT INTO accounts (id, name) VALUES (1, 'staffacc'), (2, 'player'), (3, 'helperacc')");
$pdo->exec("CREATE TABLE players (id INTEGER PRIMARY KEY, account_id INT, group_id INT, name TEXT)");
$pdo->exec("INSERT INTO players (account_id, group_id, name) VALUES (1, 6, 'God Ash'), (2, 1, 'Arwen'), (3, 4, 'Tutor Bram')");
$pdo->exec("CREATE TABLE chaos_shop_purchases (id INTEGER PRIMARY KEY AUTOINCREMENT, account_id INT, player_id INT, player_name TEXT,
	level INT, offer_key TEXT, category TEXT, title TEXT, price INT, list_price INT, created INT)");

$day1 = 1790985600; // 2026-10-03 00:00 UTC
$day2 = $day1 + 86400;
$now = $day2 + 50000;
$ins = static function (string $table, array $row) use ($pdo): void {
	$st = $pdo->prepare('INSERT INTO `' . $table . '` (`' . implode('`, `', array_keys($row)) . '`) VALUES (' . implode(', ', array_fill(0, count($row), '?')) . ')');
	$st->execute(array_values($row));
};
// hunting: day 1 warriors 300-499 (4 characters), day 2 only 2 characters (rates hidden); a mystic bucket
$ins('chaos_telemetry_hunt', array('span' => 'h', 'at' => $day1 + 3600, 'band' => '300-499', 'voc' => 4, 'players' => 4,
	'hunt_seconds' => 7200, 'exp' => 2000000, 'loot' => 300000, 'supplies' => 100000, 'kills' => 900));
$ins('chaos_telemetry_hunt', array('span' => 'h', 'at' => $day2 + 3600, 'band' => '300-499', 'voc' => 8, 'players' => 2,
	'hunt_seconds' => 3600, 'exp' => 900000, 'loot' => 50000, 'supplies' => 10000, 'kills' => 300));
$ins('chaos_telemetry_hunt', array('span' => 'h', 'at' => $day2 + 7200, 'band' => '100-299', 'voc' => 1, 'players' => 5,
	'hunt_seconds' => 18000, 'exp' => 500000, 'loot' => 20000, 'supplies' => 40000, 'kills' => 1000));
// an old daily row outside the default range
$ins('chaos_telemetry_hunt', array('span' => 'd', 'at' => $day1 - 60 * 86400, 'band' => '300-499', 'voc' => 4, 'players' => 50,
	'hunt_seconds' => 360000, 'exp' => 1, 'loot' => 1, 'supplies' => 1, 'kills' => 1));
// online: two hours of day 2, 12 samples each
$ins('chaos_telemetry_online', array('span' => 'h', 'at' => $day2, 'band' => 'all', 'voc' => 0, 'samples' => 12, 'online_sum' => 120, 'online_max' => 14));
$ins('chaos_telemetry_online', array('span' => 'h', 'at' => $day2 + 3600, 'band' => 'all', 'voc' => 0, 'samples' => 12, 'online_sum' => 240, 'online_max' => 25));
$ins('chaos_telemetry_online', array('span' => 'h', 'at' => $day2, 'band' => '300-499', 'voc' => 4, 'samples' => 12, 'online_sum' => 48, 'online_max' => 5));
$ins('chaos_telemetry_boss', array('span' => 'h', 'at' => $day2, 'boss' => 'World boss: Ashmaw', 'party' => 10, 'kills' => 2, 'timed' => 2,
	'secs_total' => 700, 'secs_min' => 300, 'secs_max' => 400));
$ins('chaos_telemetry_boss', array('span' => 'h', 'at' => $day1, 'boss' => 'Grimjaw', 'party' => 3, 'kills' => 3, 'timed' => 0,
	'secs_total' => 0, 'secs_min' => 0, 'secs_max' => 0));
$ins('chaos_telemetry_deaths', array('span' => 'h', 'at' => $day2, 'band' => '300-499', 'area' => '<script>alert(1)</script> Caves', 'killer' => 'Cinder Imp', 'deaths' => 7));
$ins('chaos_telemetry_deaths', array('span' => 'h', 'at' => $day2, 'band' => '100-299', 'area' => 'near Cinderhold', 'killer' => 'a player', 'deaths' => 2));
$ins('chaos_telemetry_casts', array('span' => 'h', 'at' => $day2, 'voc' => 4, 'spell' => 'Brutal Strike', 'casts' => 1500, 'players' => 4));
$ins('chaos_telemetry_casts', array('span' => 'h', 'at' => $day2, 'voc' => 1, 'spell' => 'Ember Bolt', 'casts' => 900, 'players' => 5));
$ins('chaos_telemetry_economy', array('span' => 'h', 'at' => $day2, 'flow' => 'faucet', 'source' => 'loot', 'band' => '300-499', 'gold' => 350000, 'events' => 30));
$ins('chaos_telemetry_economy', array('span' => 'h', 'at' => $day2, 'flow' => 'sink', 'source' => 'supplies', 'band' => '300-499', 'gold' => 110000, 'events' => 30));
$ins('chaos_telemetry_economy', array('span' => 'h', 'at' => $day1, 'flow' => 'sink', 'source' => 'respec', 'band' => '100-299', 'gold' => 5000, 'events' => 1));
$ins('chaos_shop_purchases', array('account_id' => 2, 'player_id' => 2, 'player_name' => 'Arwen', 'level' => 350, 'offer_key' => 'mount1',
	'category' => 'Mounts', 'title' => 'Ash Steed', 'price' => 750, 'list_price' => 750, 'created' => $day2 + 100));
$ins('chaos_shop_purchases', array('account_id' => 2, 'player_id' => 2, 'player_name' => 'Arwen', 'level' => 120, 'offer_key' => 'xp',
	'category' => 'Boosts', 'title' => 'XP Boost', 'price' => 100, 'list_price' => 100, 'created' => $day2 + 200));

$SESSION_USER = 0;
function getSession(string $k) { global $SESSION_USER; return $k === 'user_id' ? $SESSION_USER : null; }
function render(array $get = array()): string {
	global $config, $now;
	$chaosTelemetryNow = $now;
	$_GET = $get;
	$_SERVER['REQUEST_METHOD'] = 'GET';
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/telemetry.php';
	return (string)ob_get_clean();
}

// ------------------------------------------------------------------ access
$html = render();
check(strpos($html, 'Not found') !== false && strpos($html, 'Telemetry') === false, 'logged out: not found');
$SESSION_USER = 2;
check(strpos(render(), 'Not found') !== false, 'a player: not found');
$SESSION_USER = 3;
check(strpos(render(), 'Not found') !== false, 'an admin panel account whose best character is group 4: not found');
check(!chaos_telemetry_is_admin($config, 3) && chaos_telemetry_is_admin($config, 1), 'group 5+ and the admin panel');
$SESSION_USER = 1;

// ------------------------------------------------------------------ filters
$f = chaos_telemetry_filters(array(), $now);
check($f['from'] === $day2 - 13 * 86400 && $f['to'] === $day2 && $f['until'] === $day2 + 86400, 'default: the last 14 days');
$f = chaos_telemetry_filters(array('band' => "300-499' OR 1=1", 'class' => 'x', 'from' => '2026-02-31', 'to' => '2999-01-01'), $now);
check($f['band'] === '' && $f['class'] === '' && $f['to'] === $day2, 'bad values fall back');
$f = chaos_telemetry_filters(array('from' => '2020-01-01', 'to' => gmdate('Y-m-d', $day2)), $now);
check(($f['to'] - $f['from']) / 86400 === CHAOS_TELEMETRY_MAX_DAYS - 1, 'the range is capped');
$f = chaos_telemetry_filters(array('class' => 'l4'), $now);
check($f['vocs'] === array(4, 8, 14), 'a line: its classes');
check(chaos_telemetry_bands() === array('1-99', '100-299', '300-499', '500-999', '1000+'), 'bands read from telemetry_config.lua');

// ------------------------------------------------------------------ the page
$html = render();
check(strpos($html, 'Balance Telemetry') !== false && substr_count($html, '<svg') >= 6, 'the page with its charts');
check(stripos($html, '<script') === false, 'no script at all (the area name is escaped)');
check(strpos($html, '&lt;script&gt;alert(1)&lt;/script&gt; Caves') !== false, 'the area name shown escaped');
check(!preg_match('~(src|href)="https?://~', $html), 'no external file');
$days = chaos_telemetry_hunt_days(chaos_telemetry_filters(array(), $now));
check($days[$day1]['xph'] === 1000000 && $days[$day1]['gph'] === 100000, 'day 1: 2M xp and 200k gold in 2 h');
check($days[$day2]['players'] === 7 && $days[$day2]['xph'] === 233333, 'day 2: 1.4M xp in 6 h by 7 character-hours');
$classesRates = chaos_telemetry_hunt_classes(chaos_telemetry_filters(array(), $now));
check($classesRates[8]['xph'] === null && $classesRates[8]['hours'] == 1.0, 'two Juggernauts: the rate is hidden, the hours shown');
check($classesRates[1]['gph'] === -4000, 'gold per hour can be negative (supplies above loot)');
check(!isset($classesRates[4]) || $classesRates[4]['xph'] === 1000000, 'the old daily row is outside the range');
$html = render(array('class' => 'l4', 'band' => '300-499'));
check(strpos($html, 'level 300-499, Warrior (line)') !== false, 'the scope line');
check(strpos($html, 'Mystic') === false || strpos($html, '<td>Mystic</td>') === false, 'the class filter leaves the Mystics out of the class table');
$onl = chaos_telemetry_online_days(chaos_telemetry_filters(array(), $now));
check($onl[$day2]['avg'] == 15 && $onl[$day2]['max'] === 25, 'online: 360 over 24 samples, peak 25');
$onl = chaos_telemetry_online_days(chaos_telemetry_filters(array('class' => 'c4'), $now));
check($onl[$day2]['avg'] == 2 && $onl[$day2]['max'] === 5, 'online of one class over the total samples');
$bosses = chaos_telemetry_bosses(chaos_telemetry_filters(array(), $now));
check(count($bosses) === 2, 'two boss rows');
$html = render();
check(strpos($html, '<td>World boss: Ashmaw</td><td class="num">10</td><td class="num">2</td>') !== false
	&& strpos($html, '5:50') !== false && strpos($html, '5:00') !== false && strpos($html, '6:40') !== false, 'boss times: average, best, slowest');
[$areas, $pairs] = chaos_telemetry_deaths(chaos_telemetry_filters(array('band' => '100-299'), $now));
check(count($areas) === 1 && $areas[0]['area'] === 'near Cinderhold', 'deaths by band');
$casts = chaos_telemetry_casts(chaos_telemetry_filters(array('class' => 'l1'), $now));
check(count($casts) === 1 && $casts[0]['spell'] === 'Ember Bolt', 'casts by class line');
[$eco, $src] = chaos_telemetry_economy(chaos_telemetry_filters(array(), $now));
check($eco[$day2]['faucet'] === 350000 && $eco[$day2]['sink'] === 110000 && $eco[$day1]['sink'] === 5000, 'faucets and sinks per day');
check(count($src) === 3, 'per source');
$store = chaos_telemetry_store(chaos_telemetry_filters(array(), $now));
check($store[0]['category'] === 'Mounts' && (int)$store[0]['coins'] === 750 && count($store) === 2, 'coins per category');
$store = chaos_telemetry_store(chaos_telemetry_filters(array('band' => '100-299'), $now));
check(count($store) === 1 && $store[0]['category'] === 'Boosts', 'store by the buyer level band');

// ------------------------------------------------------------------ the charts
$svg = chaos_telemetry_line_svg('t', array(array('name' => 'A', 'color' => '#bf8a26', 'points' => array($day1 => 5, $day2 => null))));
check(substr_count($svg, '<circle') === 1 && strpos($svg, '<title>A 2026-10-03: 5</title>') !== false, 'a gap for a hidden rate; a tooltip per point');
check(strpos(chaos_telemetry_line_svg('t', array()), 'No data') !== false, 'an empty chart says so');
$svg = chaos_telemetry_bar_svg('t', array(array('<b>', 3), array('x', 6)));
check(strpos($svg, '&lt;b&gt;') !== false && strpos($svg, '<b>') === false, 'bar labels escaped');
check(chaos_telemetry_axis_max(7300) == 10000 && chaos_telemetry_axis_max(180) == 200, 'nice axis tops');
check(chaos_telemetry_clock(3725) === '1:02:05' && chaos_telemetry_clock(null) === '-', 'clock');

if ($failed > 0) {
	echo "$failed check(s) failed\n";
	exit(1);
}
echo "chaos_telemetry_page_test: all checks passed\n";
