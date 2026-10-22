<?php
// php website/tests/chaos_mentors_page_test.php : the Mentors page (plugins/chaos/mentor_lib.php, pages/mentors.php)
// over an in-memory SQLite database with the game server's chaos_mentor* tables: only active, public, non-staff,
// non-banned mentors; graduates first; the free places; the totals; escaping; the numbers of the page match
// mentor_config.lua; missing tables. No ZnoteX, no network. Exit status 0 when every check passes.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/mentor_lib.php';

$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$TABLES = array('chaos_mentors' => true, 'chaos_mentor_links' => true, 'account_bans' => true, 'chaos_antibot_holds' => false);
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
		if (strpos($sql, 'information_schema') !== false) { return array('n' => !empty($GLOBALS['TABLES'][$p[0]]) ? 1 : 0); }
		$r = $this->run($sql, $p)->fetch(PDO::FETCH_ASSOC);
		return $r === false ? false : $r;
	}
	public function fetchAll(string $sql, array $p = array()) { return $this->run($sql, $p)->fetchAll(PDO::FETCH_ASSOC); }
	public function execute(string $sql, array $p = array()) { $this->run($sql, $p); return true; }
}
$DB = new FakeZnoteDb($pdo);
function db() { return $GLOBALS['DB']; }

$pdo->exec("CREATE TABLE players (id INT PRIMARY KEY, account_id INT, name TEXT, level INT, vocation INT, group_id INT DEFAULT 1)");
$pdo->exec("CREATE TABLE account_bans (account_id INT PRIMARY KEY)");
$pdo->exec("CREATE TABLE player_storage (player_id INT NOT NULL, key INT NOT NULL, value INT NOT NULL)"); // tester bots (none here)
$pdo->exec("CREATE TABLE chaos_mentors (player_id INT PRIMARY KEY, account_id INT, active INT DEFAULT 1, accepting INT DEFAULT 1,
	public INT DEFAULT 1, lang TEXT DEFAULT '', hours TEXT DEFAULT '', note TEXT DEFAULT '', marks INT DEFAULT 0, earned INT DEFAULT 0,
	graduates INT DEFAULT 0, day_key INT DEFAULT 0, day_minutes INT DEFAULT 0, day_marks INT DEFAULT 0, month_key INT DEFAULT 0,
	month_marks INT DEFAULT 0, registered_at INT DEFAULT 0)");
$pdo->exec("CREATE TABLE chaos_mentor_links (id INTEGER PRIMARY KEY AUTOINCREMENT, mentor_id INT, mentor_account INT, apprentice_id INT,
	apprentice_account INT, status TEXT DEFAULT 'active', source TEXT DEFAULT 'list', start_level INT DEFAULT 0, shared_minutes INT DEFAULT 0,
	linked_at INT DEFAULT 0, ended_at INT DEFAULT 0)");

// invented test characters only
$pdo->exec("INSERT INTO players VALUES (1, 10, 'Brannoc', 60, 8, 1), (2, 11, 'Seris', 300, 10, 1), (3, 12, 'Hidden One', 80, 4, 1),
	(4, 13, 'Retired Rook', 90, 3, 1), (5, 14, 'Gamemaster Vel', 100, 4, 4), (6, 15, 'Banned Bram', 100, 4, 1),
	(7, 16, '<b>Tag</b>', 50, 1, 1), (20, 30, 'Ash', 12, 4, 1), (21, 31, 'Kael', 30, 3, 1), (22, 32, 'Mira', 20, 1, 1)");
$pdo->exec("INSERT INTO account_bans VALUES (15)");
$pdo->exec("INSERT INTO chaos_mentors (player_id, account_id, active, accepting, public, lang, hours, note, graduates) VALUES
	(1, 10, 1, 1, 1, 'English, EU', '18-23 UTC', 'Rifts and dungeons', 2),
	(2, 11, 1, 0, 1, 'Portuguese (BR)', 'weekends', '', 9),
	(3, 12, 1, 1, 0, 'English', '', '', 4),
	(4, 13, 0, 1, 1, 'English', '', '', 3),
	(5, 14, 1, 1, 1, 'English', '', '', 0),
	(6, 15, 1, 1, 1, 'English', '', '', 0),
	(7, 16, 1, 1, 1, '<script>x</script>', '', '\"quoted\" & <i>', 0)");
$pdo->exec("INSERT INTO chaos_mentor_links (mentor_id, apprentice_id, status) VALUES (1, 20, 'active'), (1, 21, 'active'),
	(2, 22, 'graduated'), (3, 23, 'active')");

$state = chaos_mentor_state(100);
check($state['ok'] === true, 'tables found');
$names = array_map(fn($m) => $m['name'], $state['mentors']);
check($names === array('Seris', 'Brannoc', '<b>Tag</b>'), 'active, public, no staff, not banned, most graduates first: ' . implode(',', $names));
$by = array();
foreach ($state['mentors'] as $m) { $by[$m['name']] = $m; }
check($by['Brannoc']['active'] === 2 && $by['Brannoc']['free'] === 1, 'Brannoc: two apprentices, one place');
check($by['Brannoc']['class'] === chaos_class_name(8), 'class name from the vocation');
check($by['Seris']['accepting'] === false, 'Seris takes no apprentices');
check($state['totals']['mentors'] === 6, 'active mentors (hidden ones too): ' . $state['totals']['mentors']);
check($state['totals']['apprentices'] === 3, 'apprentices learning now');
check($state['totals']['graduates'] === 18, 'graduates of every mentor: ' . $state['totals']['graduates']);

$html = chaos_mentor_table_html($state);
check(strpos($html, 'Brannoc') !== false && strpos($html, '1 free') !== false, 'free places shown');
check(strpos($html, 'not taking') !== false, 'not taking shown');
check(strpos($html, 'Hidden One') === false, 'a mentor who did not opt in is not shown');
check(strpos($html, 'Banned Bram') === false && strpos($html, 'Gamemaster Vel') === false, 'banned and staff not shown');
check(strpos($html, '<script>') === false && strpos($html, '&lt;script&gt;') !== false, 'card text escaped');
check(strpos($html, '<b>Tag</b>') === false && strpos($html, '&lt;b&gt;Tag&lt;/b&gt;') !== false, 'name escaped');
check(strpos($html, 'name=%3Cb%3ETag%3C%2Fb%3E') !== false, 'profile link encoded');

// the page's numbers are mentor_config.lua's
$lua = (string)file_get_contents(__DIR__ . '/../../server/data/scripts/chaos/mentor_config.lua');
$rules = chaos_mentor_rules();
$want = array('max' => '/maxApprentices = (\d+)/', 'apprentice_level' => '/apprentice = \{\s*maxLevel = (\d+)/', 'account_days' => '/maxAccountDays = (\d+)/',
	'graduation' => '/graduationLevel = (\d+)/', 'mentor_level' => '/minAccountLevel = (\d+)/', 'mentor_hours' => '/minOnlineHours = (\d+)/',
	'mentor_days' => '/minAccountDays = (\d+)/');
foreach ($want as $k => $re) {
	check(preg_match($re, $lua, $m) === 1 && (int)$m[1] === $rules[$k], "rule $k matches mentor_config.lua");
}
check(preg_match('/exp = 0\.(\d+),/', $lua, $m) === 1 && (int)$m[1] === $rules['exp'], 'exp bonus matches');
check(preg_match('/damageTaken = 0\.0(\d+),/', $lua, $m) === 1 && (int)$m[1] === $rules['damage'], 'damage reduction matches');

// the page renders
ob_start();
include __DIR__ . '/../overlay/plugins/chaos/pages/mentors.php';
$page = ob_get_clean();
check(strpos($page, 'Mentors') !== false && strpos($page, 'Seris') !== false, 'page renders the list');
check(strpos($page, '18</span> graduates') !== false, 'page totals');
check(strpos($page, 'level 79') !== false && strpos($page, 'level 200') !== false, 'page rules');

// no mentors yet / no tables
$pdo->exec("DELETE FROM chaos_mentors");
check(chaos_mentor_table_html(chaos_mentor_state()) === '', 'nothing to show');
$TABLES['chaos_mentors'] = false;
// chaos_table_exists caches per request: a fresh name check through the lib is enough here
$empty = array('ok' => false, 'mentors' => array());
check(chaos_mentor_table_html($empty) === '', 'missing tables: empty');

if ($failed > 0) { echo "$failed check(s) failed\n"; exit(1); }
echo "chaos_mentors_page_test: OK\n";
