<?php
// php website/tests/chaos_trends_page_test.php : the Trending builds page (O409; plugins/chaos/lib.php chaos_build_trends,
// pages/trends.php) over an in-memory SQLite database: no table / no snapshot, the newest snapshot only, per class the
// builds most played first with share, keystones, count and average level, the link to the build page, the copy button
// (assets/js/chaos-copy.js, no inline script), no character name anywhere, and the pt-BR page. Exit status 0 when every
// check passes.
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

$render = static function (string $lang = 'en'): string {
	global $config;
	$_GET = array('plugin' => 'chaos', 'p' => 'trends', 'l' => $lang);
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/trends.php';
	return (string)ob_get_clean();
};

check(chaos_share_text(429) === '42.9%' && chaos_share_text(1000) === '100%' && chaos_share_text(5) === '0.5%', 'share text');

// the table of the server (server/sql/chaos_build_trends.sql), in SQLite types; chaos_table_exists remembers its answer
// per request, so the "no table" case is the empty one here
$pdo->exec("CREATE TABLE chaos_build_trends (snapshot INT, class_base INT, rank INT, class_name TEXT, signature TEXT, keystones TEXT,
	count INT, total INT, share INT, avg_level INT, tree_code TEXT, code TEXT, PRIMARY KEY (snapshot, class_base, rank))");
check(chaos_build_trends() === array(0, array()), 'empty table: nothing');
$html = $render();
check(strpos($html, 'No snapshot yet') !== false, 'no snapshot: the page says so');
check(strpos($html, 'chaos-copy.js') === false, 'no snapshot: no script');
$at = mktime(12, 0, 0, 11, 4, 2026);
$full = 'CC1-AQABDwIAAgAyAwAKAQMABAIAQErPzP0hAQ'; // docs/build_code_vectors.txt "old tree code v1"
$stmt = $pdo->prepare('INSERT INTO chaos_build_trends VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
foreach (array(
	array($at, 4, 2, 'Warrior', 'ksCleavingArc', 'Cleaving Arc', 3, 14, 214, 400, 'CB1-AwAEAgBASs_M', ''),
	array($at, 4, 1, 'Warrior', 'ksBulwark+ksCleavingArc', 'Bulwark, Cleaving Arc', 6, 14, 429, 210, 'CB1-AwAEAgBASs_M', $full),
	array($at, 3, 1, 'Ranger', '', '', 4, 4, 1000, 300, 'CB1-AwAEAgBASs_M', $full),
	array($at - 86400, 4, 1, 'Warrior', 'ksOld', 'Old Keystone', 9, 9, 1000, 100, 'CB1-AwAEAgBASs_M', $full),
) as $r) {
	$stmt->execute($r);
}
list($snap, $trends) = chaos_build_trends();
check($snap === $at, 'the newest snapshot');
check(count($trends) === 2, 'two classes');
check(count($trends[4]) === 2 && (int)$trends[4][0]['rank'] === 1, 'ranks in order');
$html = $render();
check(strpos($html, 'Old Keystone') === false, 'an older snapshot is not shown');
check(strpos($html, 'Snapshot of 2026-11-04.') !== false, 'the snapshot day');
$first = strpos($html, 'Bulwark, Cleaving Arc');
$second = strpos($html, '21.4%');
check($first !== false && $second !== false && $first < $second, 'the most played build first');
check(strpos($html, '42.9%') !== false, 'share');
check(strpos($html, '6 characters, average level 210') !== false, 'count and level');
check(strpos($html, '14 active characters') !== false, 'class total');
check(strpos($html, 'No keystone') !== false, 'a build without keystones');
check(strpos($html, chaos_h(chaos_build_url($full))) !== false, 'the link to the build page');
check(strpos($html, 'data-chaos-copy="' . $full . '"') !== false, 'the copy button: the full code');
check(strpos($html, 'data-chaos-copy="CB1-AwAEAgBASs_M"') !== false, 'no full code: the tree code');
check(strpos($html, 'js/chaos-copy.js') !== false, 'the copy script');
check(preg_match('/<script(?![^>]*\bsrc=)[^>]*>/', $html) === 0, 'no inline script');
check(strpos($html, 'No build is played by enough characters yet.') !== false, 'a class without builds');
check(strpos($html, 'characterprofile') === false, 'no character link');
check(is_file(__DIR__ . '/../overlay/plugins/chaos/assets/js/chaos-copy.js'), 'the script file');
// Portuguese (chaos_lang keeps the first request's language in one process; chaos_i18n_test checks every key of the page)
check(chaos_t_in('pt-BR', 'Trending builds') === 'Builds em alta' && chaos_t_in('pt-BR', 'View build') === 'Ver build', 'pt-BR texts');
// the links to the page
check(strpos((string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/pages/build.php'), 'p=trends') !== false, 'the build page links here');
check(strpos((string)file_get_contents(__DIR__ . '/../setup/chaos_setup.php'), "'page?plugin=chaos&p=trends'") !== false, 'the menu entry');

if ($failed > 0) {
	echo "chaos_trends_page_test: $failed failed\n";
	exit(1);
}
echo "chaos_trends_page_test: OK\n";
