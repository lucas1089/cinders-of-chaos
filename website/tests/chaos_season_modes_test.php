<?php
// php website/tests/chaos_season_modes_test.php : the season mode tabs of the season ladder and the fallen marks
// (overlay/plugins/chaos/lib.php, pages/seasons.php; php-cli only, no ZnoteX, a fake database). Reads the real
// server/data/scripts/chaos/season_config.lua. Exit status 0 when every check passes.

$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));

// the ZnoteX db() helper, faked: every table exists; queries are recorded; rows by what is asked
class ChaosFakeDb {
	public $queries = array();
	public $ladder = array();
	public $fallen = array();
	public function fetchOne(string $sql, array $params = array()) {
		return array('n' => 1);
	}
	public function fetchAll(string $sql, array $params = array()) {
		$this->queries[] = array($sql, $params);
		if (strpos($sql, '`server_config`') !== false) {
			return array(array('config' => 'chaos_season_1_start', 'value' => (string)(time() - 3600)),
				array('config' => 'chaos_season_1_end', 'value' => (string)(time() + 86400)));
		}
		if (strpos($sql, 'WHERE `m`.`fallen_at` > 0;') !== false) {
			return $this->fallen;
		}
		if (strpos($sql, 'FROM `players` `p`') !== false) {
			return $this->ladder;
		}
		return array();
	}
}
$fakeDb = new ChaosFakeDb();
function db() {
	global $fakeDb;
	return $fakeDb;
}
function znote_plugin_asset(string $plugin, string $path): string {
	return '/' . $plugin . '/' . $path;
}

require __DIR__ . '/../overlay/plugins/chaos/lib.php';

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
function lastQuery(): array {
	global $fakeDb;
	return end($fakeDb->queries) ?: array('', array());
}

// the tabs: every mode of season_config.lua `modes.list`, plus All and Fallen
$text = file_get_contents(__DIR__ . '/../../server/data/scripts/chaos/season_config.lua');
$keys = array();
foreach (chaos_lua_entries(chaos_lua_block(chaos_lua_block($text, 'modes'), 'list')) as $entry) {
	$keys[] = (string)chaos_lua_field($entry, 'key');
}
$tabs = chaos_season_mode_tabs();
check($keys === array('standard', 'ssf', 'hc', 'hcssf'), 'modes read from season_config.lua: ' . implode(',', $keys));
check(array_keys($tabs) === array_merge(array('all'), $keys, array('fallen')), 'tabs: All, every mode, Fallen');
foreach ($tabs as $key => $label) {
	check(chaos_season_mode_clause($key) !== null, "clause for $key");
}
check(chaos_season_mode_clause("x' OR 1 = 1") === null, 'an unknown tab has no SQL');
check(strpos(chaos_season_mode_clause('hc'), '`m`.`fallen_at` = 0') !== false, 'Hardcore: living only');

// the class ladder per tab
$n = count($fakeDb->queries);
check(chaos_class_ladder(4, 10, 1, 'bogus') === array(), 'unknown tab: nothing');
check(count($fakeDb->queries) === $n, 'and no query');
chaos_class_ladder(4, 10, 1, 'ssf');
list($sql, $params) = lastQuery();
check(strpos($sql, 'LEFT JOIN `chaos_season_modes` `m`') !== false, 'joins the modes');
check(strpos($sql, '`m`.`ssf` = 1 AND `m`.`hc` = 0') !== false, 'SSF clause');
check(strpos($sql, '`s`.`migrated_at` = 0') !== false, 'living characters of the season');
check($params[0] === 1 && end($params) === 10, 'season first, limit last');
chaos_class_ladder(4, 10, 1, 'fallen');
list($sql) = lastQuery();
check(strpos($sql, '`m`.`fallen_at` > 0') !== false, 'Fallen clause');
check(strpos($sql, 'migrated_at') === false, 'fallen characters are migrated: kept');
check(strpos($sql, 'ORDER BY `m`.`fallen_level` DESC') !== false, 'highest fall first');
chaos_class_ladder(4, 10);
list($sql) = lastQuery();
check(strpos($sql, 'chaos_season_modes') === false, 'the all-time ladder is unchanged');

// the skull
$marks = array('Grim' => array('level' => 88, 'cause' => 'killed by <a> dragon'));
check(chaos_fallen_html($marks, 'Bob') === '', 'not fallen: nothing');
$html = chaos_fallen_html($marks, 'Grim');
check(strpos($html, '&#9760;') !== false, 'skull');
check(strpos($html, 'level 88') !== false && strpos($html, '&lt;a&gt;') !== false, 'tooltip, escaped');

// the page: the Fallen tab of a running season
$fakeDb->ladder = array(array('name' => 'Grim', 'level' => 20, 'vocation' => 4, 'experience' => 1, 'fallen_level' => 88,
	'fallen_cause' => 'killed by a dragon'));
$_GET['mode'] = 'fallen';
ob_start();
include __DIR__ . '/../overlay/plugins/chaos/pages/seasons.php';
$page = ob_get_clean();
check(strpos($page, 'is-active" href="page.php?plugin=chaos&amp;p=seasons&amp;mode=fallen"') !== false, 'Fallen tab active');
check(strpos($page, 'Fallen in Hardcore at level 88 (killed by a dragon)') !== false, 'the fall on the page');
check(strpos($page, '<span class="chaos-ladder__lvl">88</span>') !== false, 'the level it fell at');
$_GET['mode'] = 'hc';
$fakeDb->fallen = array(array('name' => 'Grim', 'fallen_level' => 88, 'fallen_cause' => 'killed by a dragon'));
ob_start();
include __DIR__ . '/../overlay/plugins/chaos/pages/seasons.php';
$page = ob_get_clean();
check(strpos($page, 'mode=hc"') !== false && strpos($page, 'Hardcore</a>') !== false, 'Hardcore tab');

echo $failed ? "$failed of $checks checks FAILED\n" : "chaos_season_modes_test: OK ($checks checks)\n";
exit($failed ? 1 : 0);
