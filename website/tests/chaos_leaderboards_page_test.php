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
// the dropdown filters (lib.php chaos_pick_form): [value, label, selected] of each <option> of the <select name=$name>
$selectOf = static function (string $html, string $name): array {
	if (!preg_match('#<select [^>]*name="' . preg_quote($name, '#') . '"[^>]*>(.*?)</select>#s', $html, $m)) {
		return array();
	}
	preg_match_all('#<option value="([^"]*)"( selected)?>([^<]*)</option>#', $m[1], $om, PREG_SET_ORDER);
	return array_map(static function ($o) { return array(html_entity_decode($o[1], ENT_QUOTES), html_entity_decode($o[3], ENT_QUOTES), $o[2] !== ''); }, $om);
};
$formOf = static function (string $html, string $label): string {
	$at = strpos($html, '<form class="chaos-pick" method="get" action="page');
	while ($at !== false) {
		$end = (int)strpos($html, '</form>', $at);
		$form = substr($html, $at, $end - $at + 7);
		if (strpos($form, 'aria-label="' . $label . '"') !== false) {
			return $form;
		}
		$at = strpos($html, '<form class="chaos-pick"', $end);
	}
	return '';
};
// All classes (default): every class, fastest first, m:ss
$html = $renderClass('cinder_solo', null);
$form = $formOf($html, 'Boards');
check($form !== '', 'weekly boards: a GET form to page');
check(strpos($form, '<input type="hidden" name="plugin" value="chaos">') !== false && strpos($form, '<input type="hidden" name="p" value="leaderboards">') !== false,
	'weekly boards: the form keeps plugin=chaos&p=leaderboards');
check(strpos($form, '<button type="submit" class="chaos-btn chaos-pick__go">Show</button>') !== false, 'weekly boards: a submit button (no JavaScript needed)');
check(strpos($html, '<script src="plugins/chaos/assets/js/chaos-pick.js" defer></script>') !== false, 'the auto-submit script is a file, deferred');
check(preg_match('#<script(?![^>]*\bsrc=)[^>]*>#', $html) === 0, 'no inline script');
$opts = $selectOf($form, 'board');
$names = array_column($opts, 1);
$sorted = $names;
usort($sorted, static function ($a, $b) { return strcasecmp($a, $b); });
check(count($opts) === count($boards) && $names === $sorted, 'weekly boards: one dropdown, every board, sorted by name');
check(array_column(array_filter($opts, static function ($o) { return $o[2]; }), 0) === array('cinder_solo'), 'weekly boards: the board shown is selected');
$copts = $selectOf($form, 'class');
check(array_column($copts, 1) === array('All classes', 'Mystic', 'Ranger', 'Warrior', 'Thief', 'Monk', 'Necromancer', 'Templar'), 'class dropdown: All classes first, then the client order');
check(array_column($copts, 0) === array('all', '1', '3', '4', '11', '17', '20', '23'), 'class dropdown: the class= values of the old tabs');
check(($copts[0][2] ?? false) === true, 'All classes selected by default');
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
check(array_column(array_filter($selectOf($html, 'class'), static function ($o) { return $o[2]; }), 0) === array('17'), 'class dropdown: the class shown is selected (kept when the board changes)');
// a bad class value or a board without class tabs: every class, no class tabs
check(array_column($rowsOf($renderClass('cinder_solo', '999')), 1) === array('Fast Mystic', 'Old Mystic', 'Quick Blade', 'Iron Juggernaut', 'Mid Arrow', 'Slow Hammer'), 'unknown class: every class');
check(array_column($rowsOf($renderClass('cinder_solo', '4 OR 1=1')), 1)[0] === 'Fast Mystic', 'non-numeric class: every class');
$html = $renderClass('worldboss', '4');
check($selectOf($html, 'class') === array(), 'worldboss: no class dropdown');
check(count($rowsOf($html)) === 3 && strpos($html, 'Mid Arrow') !== false, 'worldboss: the class value is ignored');


// ---- records (records.lua): the boards the server published, the filters, ties to the earlier time, staff left out
check(strpos($renderClass('worldboss', null), 'No records yet') !== false, 'records: nothing before the server published boards');
$pdo->exec("INSERT INTO chaos_records_boards VALUES ('omen', 'bosses', 'Omen Guardians', 'min', 'time', 'Fastest', 'bloodmoon=Sangrith;storm=Thalcyra', 'solo=Solo;small=2-3;party=4-5', 1),
	('tower_floor', 'tower', 'Highest Floor', 'max', '', 'Floor', '', '', 2)");
$pdo->exec("INSERT INTO chaos_records_boards VALUES ('x\"><b>', 'misc', '<Ember> & \"Ash\"', 'max', '', 'Score', '', '', 9)");
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
// a world boss first keeps the short title name ("Skaldra"); the list names the boss in full (live test 2026-10-14)
$pdo->exec("INSERT INTO chaos_records_boards VALUES ('wb_time', 'bosses', 'World Boss Kill Time', 'min', 'time', 'Fastest', 'kaelgor=Kaelgor the Infernal Warlord;skaldra=Skaldra the Rime Queen', '', 3)");
$pdo->prepare("INSERT INTO chaos_records_firsts VALUES (?, 'wb_time:skaldra', 'wb_time', 'Skaldra', 'Rime Breaker', '5', 400, 120)")->execute(array($season));
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
check(strpos($html, 'aria-label="Record boards"') !== false && strpos($html, 'aria-label="Party size"') !== false, 'records: board dropdown and size tabs');
$form = $formOf($html, 'Record boards');
check(strpos($form, 'action="page#records"') !== false, 'records form: lands on the records box');
foreach (array('plugin' => 'chaos', 'p' => 'leaderboards', 'rp' => 'all', 'rs' => 'small') as $k => $v) {
	check(strpos($form, '<input type="hidden" name="' . $k . '" value="' . $v . '">') !== false, "records form: keeps $k=$v");
}
check(strpos($form, 'name="rb" data-chaos-autosubmit data-chaos-reset="rv rs"') !== false, 'records form: a new board drops the boss and party size');
check(array_column($selectOf($form, 'rb'), 1) === array('<Ember> & "Ash"', 'Highest Floor', 'Omen Guardians', 'World Boss Kill Time'), 'records: boards sorted by name');
check(array_column(array_filter($selectOf($form, 'rb'), static function ($o) { return $o[2]; }), 0) === array('omen'), 'records: the board shown is selected');
check(strpos($form, '&lt;Ember&gt; &amp; &quot;Ash&quot;') !== false && strpos($html, '<Ember>') === false, 'records: board names escaped');
check(strpos($form, 'value="x&quot;&gt;&lt;b&gt;"') !== false, 'records: board keys escaped');
check($selectOf($form, 'rv') === array(array('bloodmoon', 'Sangrith', false), array('storm', 'Thalcyra', true)), 'records: the boss dropdown in the server order, the boss shown selected');
check(strpos($form, '<span class="chaos-pick__label">Boss</span>') !== false, 'records: a boss board labels its variants Boss');
check(array_column($selectOf($form, 'rc'), 1) === array('All classes', 'Mystic', 'Ranger', 'Warrior', 'Thief', 'Monk', 'Necromancer', 'Templar'), 'records: class dropdown, All classes first');
check(strpos($html, 'aria-label="Record period"') !== false && substr_count($html, 'rp=week') >= 1 && substr_count($html, 'rp=season') >= 1, 'records: the period stays three tabs');
check(strpos($html, 'p=leaderboards&amp;rb=omen&amp;rp=season&amp;rv=storm&amp;rs=small&amp;rc=all#records') !== false, 'records: period tab links keep every filter');
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
check($selectOf($html, 'rv') === array() && strpos($formOf($html, 'Record boards'), 'name="rs"') === false, 'records: no boss dropdown and no size on a board without them');
$html = $renderRec(array('rb' => 'tower_floor', 'rp' => 'week'));
check(array_column($recRows($html), 1) === array('60'), 'records: this week only');
$html = $renderRec(array('rb' => 'tower_floor', 'rp' => 'season'));
check(strpos($html, 'No result on this board in this view yet') !== false, 'records: empty season view');
check(strpos($html, 'Quick Blade, Mid Arrow') !== false && strpos($html, 'Cinderheart') !== false, 'records: realm firsts of the season');
check(strpos($html, '<td>Skaldra the Rime Queen</td>') !== false && strpos($html, '<td>Skaldra</td>') === false,
	'records: a realm first names the boss in full, not its key');
check(chaos_records_first_name(array('target' => 'trials:warrior.cruel', 'name' => 'Gauntlet Champion'),
	array('trials' => array('name' => 'Trials', 'variants' => array('cruel' => 'Cruel')))) === 'Gauntlet Champion (Cruel)',
	'records: a trials first as the server announced it');
check(chaos_records_first_name(array('target' => 'gone:x', 'name' => 'Old Boss'), array()) === 'Old Boss',
	'records: an unknown board keeps the stored name');
check(chaos_records_value('pct', 4512) === '45.12%' && chaos_records_value('', 1500) === '1,500', 'records: value formats');
check(preg_match('/^(s\d+|q\d{5})$/', $season) === 1, 'records: season key');
check(count(chaos_records_categories()) === 6, 'records: categories read from records_config.lua');

// the sort of the dropdowns: accents folded (the client's BoardPick.fold), ties by the key
check(array_keys(chaos_sort_options(array('b' => 'Zelo', 'a' => 'Égide', 'c' => 'escudo', 'd' => 'Arena'))) === array('d', 'a', 'c', 'b'), 'sort: accents fold to their base letter');
check(array_keys(chaos_sort_options(array('y' => 'Same', 'x' => 'Same'))) === array('x', 'y'), 'sort: ties by key');
check(chaos_sort_fold('ÇÃO Ñ') === 'cao n', 'fold: pt-BR accents');
// a select and its labels escaped; the selected value compared as a string
$sel = chaos_pick_select('a"b', '<L>', array('1' => '<one>', '01' => 'two'), '01');
check(strpos($sel, 'name="a&quot;b"') !== false && strpos($sel, '&lt;L&gt;') !== false && strpos($sel, '&lt;one&gt;') !== false, 'select: escaped');
check(strpos($sel, '<option value="01" selected>two</option>') !== false && strpos($sel, '<option value="1">') !== false, 'select: selected by string');

echo $failed === 0 ? "chaos_leaderboards_page_test: OK\n" : "chaos_leaderboards_page_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
