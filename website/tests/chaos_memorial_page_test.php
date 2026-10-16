<?php
// php website/tests/chaos_memorial_page_test.php : the Capital Memorial on the website (plugins/chaos/memorial_lib.php,
// pages/memorial.php) over an in-memory SQLite database with the game server's chaos_memorial_entries: the seasons
// newest first and the archive (&s=), realm firsts grouped with hidden members counted and never named, a record whose
// holder is hidden, a fall shown only with its yes, escaping, a bad season key, an empty Memorial. No ZnoteX, no network.
// Exit status 0 when every check passes.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/memorial_lib.php';
function znote_plugin_asset(string $plugin, string $path): string { return 'plugins/' . $plugin . '/assets/' . $path; }

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

$pdo->exec("CREATE TABLE chaos_memorial_entries (season TEXT NOT NULL, kind TEXT NOT NULL, entry_key TEXT NOT NULL, player_id INT NOT NULL,
	name TEXT NOT NULL DEFAULT '', title TEXT NOT NULL DEFAULT '', detail TEXT NOT NULL DEFAULT '', level INT NOT NULL DEFAULT 0,
	class TEXT NOT NULL DEFAULT '', at INT NOT NULL DEFAULT 0, ord INT NOT NULL DEFAULT 0, shown INT NOT NULL DEFAULT 0,
	season_name TEXT NOT NULL DEFAULT '', PRIMARY KEY (season, kind, entry_key, player_id))");
$t = 1795000000;
$ins = $pdo->prepare("INSERT INTO chaos_memorial_entries VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
foreach (array(
	// season 1 (older)
	array('s1', 'first', 'wb_time:kaelgor', 1, 'Vexa', 'Kaelgor (World Boss Kill)', '', 500, 'Templar', $t - 9000, 1, 1, 'Season of Ash'),
	array('s1', 'fallen', '7', 7, 'Old Fred', 'Hardcore', 'killed by a rat', 12, 'Ranger', $t - 8000, 1, 1, 'Season of Ash'),
	// season 2 (current)
	array('s2', 'first', 'wb_time:skaldra', 1, 'Vexa', 'Skaldra (World Boss Kill)', '', 500, 'Templar', $t - 100, 2, 1, 'Season of Embers'),
	array('s2', 'first', 'wb_time:skaldra', 2, 'Mira', 'Skaldra (World Boss Kill)', '', 480, 'Necromancer', $t - 100, 2, 0, 'Season of Embers'),
	array('s2', 'first', 'wb_time:skaldra', 3, '<b>Bold</b>', 'Skaldra (World Boss Kill)', '', 470, 'Monk', $t - 100, 2, 1, 'Season of Embers'),
	array('s2', 'first', 'omen:bloodmoon', 2, 'Mira', 'Sangrith (Omen Guardians)', '', 480, 'Necromancer', $t - 500, 1, 0, 'Season of Embers'),
	array('s2', 'record', 'wb_time|skaldra', 2, 'Mira', 'World Boss Kill, Skaldra', '4:12', 480, 'Necromancer', $t - 50, 1, 0, 'Season of Embers'),
	array('s2', 'record', 'tower_floor|-', 1, 'Vexa', 'Highest Floor', '120', 500, 'Templar', $t - 40, 2, 1, 'Season of Embers'),
	array('s2', 'fallen', '8', 8, 'Shown Sam', 'Hardcore', 'killed by a dragon lord', 88, 'Ranger', $t - 30, 1, 1, 'Season of Embers'),
	array('s2', 'fallen', '9', 9, 'Secret Sue', 'Hardcore', 'killed by a lich', 70, 'Mystic', $t - 20, 2, 0, 'Season of Embers'),
	array('../x', 'first', 'k', 1, 'Evil', 'T', '', 1, '', $t + 10, 1, 1, 'Bad')) as $r) {
	$ins->execute($r);
}

check(chaos_memorial_names(array('Vexa'), 0) === 'Vexa', 'one name');
check(chaos_memorial_names(array('Vexa', 'Bold'), 1) === 'Vexa, Bold and 1 other', 'hidden counted');
check(chaos_memorial_names(array(), 2) === '2 others', 'only hidden');
check(chaos_memorial_names(array(), 0) === 'heroes who keep their names', 'nobody');
$seasons = chaos_memorial_seasons();
check(array_column($seasons, 'key') === array('s2', 's1'), 'seasons newest first, bad keys dropped: ' . implode(',', array_column($seasons, 'key')));
check($seasons[0]['name'] === 'Season of Embers', 'season name');
$s = chaos_memorial_season('s2');
check(count($s['firsts']) === 2 && $s['firsts'][0]['title'] === 'Sangrith (Omen Guardians)', 'firsts grouped, in order');
check($s['firsts'][0]['names'] === array() && $s['firsts'][0]['hidden'] === 1, 'a hidden member is counted, not named');
check($s['firsts'][1]['names'] === array('Vexa', '<b>Bold</b>') && $s['firsts'][1]['hidden'] === 1, 'a party first');
check(count($s['records']) === 2 && $s['records'][0]['name'] === '' && $s['records'][1]['name'] === 'Vexa', 'a hidden record holder');
check(count($s['fallen']) === 1 && $s['fallen'][0]['name'] === 'Shown Sam', 'only the fall that said yes');
check(chaos_memorial_season('../x')['firsts'] === array(), 'a bad key reads nothing');
$html = chaos_memorial_season_html($s);
check(strpos($html, 'Mira') === false && strpos($html, 'Secret Sue') === false, 'hidden names are never printed');
check(strpos($html, '&lt;b&gt;Bold&lt;/b&gt;') !== false && strpos($html, '<b>Bold</b>') === false, 'escaped');
check(strpos($html, 'a hero who keeps their name') !== false, 'the hidden holder line');
check(strpos($html, 'Vexa, &lt;b&gt;Bold&lt;/b&gt; and 1 other') !== false, 'the party line');
check(strpos($html, 'killed by a dragon lord') !== false && strpos($html, '>88<') !== false, 'the fall: cause and level');

function render_page(array $get = array()): string {
	global $config;
	$_GET = $get;
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/memorial.php';
	return (string)ob_get_clean();
}
$page = render_page();
check(strpos($page, 'Season of Embers') !== false && strpos($page, 'Skaldra') !== false && strpos($page, '(archive)') === false, 'the current season');
check(strpos($page, 'p=memorial&amp;s=s1') !== false, 'a link to the archive');
$arch = render_page(array('s' => 's1'));
check(strpos($arch, 'Old Fred') !== false && strpos($arch, '(archive)') !== false && strpos($arch, 'Skaldra') === false, 'the archive');
$bad = render_page(array('s' => "s9' OR 1=1"));
check(strpos($bad, 'Season of Embers') !== false, 'an unknown key shows the current season');
check(strpos($page, '<form class="chaos-pick"') === false, 'two seasons: links, no dropdown');
// more than six seasons: one dropdown with the same &s= values, the season shown selected, a submit button
foreach (array(3, 4, 5, 6, 7) as $n) {
	$ins->execute(array('s' . $n, 'first', 'k' . $n, 1, 'Vexa', 'T', '', 1, '', $t - 100 + $n, 1, 1, $n === 7 ? 'Season <7> & "Ash"' : 'Season ' . $n));
}
$many = render_page(array('s' => 's4'));
check(strpos($many, '<form class="chaos-pick" method="get" action="page" aria-label="Seasons">') !== false, 'seven seasons: a dropdown form');
check(strpos($many, '<input type="hidden" name="p" value="memorial">') !== false && strpos($many, 'name="s" data-chaos-autosubmit') !== false, 'the dropdown sends p=memorial&s=');
check(strpos($many, '<option value="s4" selected>Season 4</option>') !== false, 'the season shown is selected');
check(strpos($many, 'Season &lt;7&gt; &amp; &quot;Ash&quot;') !== false && strpos($many, 'Season <7>') === false, 'season names escaped');
check(strpos($many, 'chaos-pick__go">Show</button>') !== false && strpos($many, 'chaos-pick.js') !== false, 'button without JavaScript, auto-submit with it');
check(strpos($many, 'chaos-memorial__seasons') === false, 'no link row any more');
$pdo->exec('DELETE FROM chaos_memorial_entries');
check(strpos(render_page(), 'The Memorial is still empty') !== false, 'empty');

echo $failed === 0 ? "chaos_memorial_page_test: OK\n" : "chaos_memorial_page_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
