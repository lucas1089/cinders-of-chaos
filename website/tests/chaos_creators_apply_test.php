<?php
// php website/tests/chaos_creators_apply_test.php : the creator program's application form (plugins/chaos/creators_lib.php,
// pages/creators.php, pages/creator.php, install.sql table chaos_creator_applications) over an in-memory SQLite database:
// the criteria (4 hours a week, 10 viewers or 500 followers, the no-RMT promise), the https channel link, the character
// must be the account's, the limits (one open application, 3 a day, 5 an hour per address), the staff review, and the
// page's CSRF check and Discord link that shows only when set. No ZnoteX, no network. Exit status 0 when every check passes.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/creator_lib.php';
require __DIR__ . '/../overlay/plugins/chaos/creators_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$TABLES = array('chaos_creator_applications' => true);
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

// the table from install.sql, turned into SQLite
$install = file_get_contents(__DIR__ . '/../overlay/plugins/chaos/install.sql');
check(preg_match('/CREATE TABLE IF NOT EXISTS `chaos_creator_applications` \((.*?)\) ENGINE/s', $install, $m) === 1, 'install.sql has the applications table');
$cols = array();
foreach (preg_split('/,\n/', trim($m[1])) as $line) {
	$line = trim($line);
	if (preg_match('/^`(\w+)` (\w+)/', $line, $c)) {
		$auto = strpos($line, 'AUTO_INCREMENT') !== false;
		$cols[] = $c[1] . ($auto ? ' INTEGER PRIMARY KEY AUTOINCREMENT' : (preg_match('/int/', $c[2]) ? ' INTEGER' : ' TEXT') . ' NOT NULL DEFAULT ' . (preg_match('/int/', $c[2]) ? '0' : "''"));
	}
}
$pdo->exec('CREATE TABLE chaos_creator_applications (' . implode(', ', $cols) . ')');
$pdo->exec('CREATE TABLE players (id INTEGER PRIMARY KEY, name TEXT, account_id INT)');
$pdo->exec("INSERT INTO players VALUES (1, 'Ember Streams', 2), (2, 'Other Streams', 3), (3, 'Third One', 4)");

$crit = chaos_creators_criteria();
check($crit === array('hoursWeek' => 4, 'viewers' => 10, 'followers' => 500), 'criteria from the data file');

$good = array('platform' => 'twitch', 'channel_url' => 'https://twitch.example/ember', 'character_name' => 'Ember Streams', 'hours_week' => 6,
	'viewers_avg' => 12, 'followers' => 40, 'message' => 'Hello', 'agree' => '1');
// ---------------------------------------------------------------- the form's checks
[$e] = chaos_creators_validate($good, $crit);
check($e === array(), 'a good application passes');
[$e] = chaos_creators_validate(array_merge($good, array('viewers_avg' => 3, 'followers' => 500)), $crit);
check($e === array(), '500 followers are enough without viewers');
[$e] = chaos_creators_validate(array_merge($good, array('hours_week' => 3)), $crit);
check($e && $e[0][0] === 'The program asks for streams or videos of the game at least %d hours a week.' && $e[0][1] === 4, 'under 4 hours a week is refused');
[$e] = chaos_creators_validate(array_merge($good, array('viewers_avg' => 9, 'followers' => 499)), $crit);
check($e && $e[0][1] === 10 && $e[0][2] === 500, '9 viewers and 499 followers are refused');
[$e] = chaos_creators_validate(array_merge($good, array('agree' => '')), $crit);
check($e && strpos((string)$e[0], 'trade accounts') !== false, 'no promise, no application');
foreach (array('http://twitch.example/x', 'javascript:alert(1)', 'twitch.example', 'https://x y.example', '') as $bad) {
	[$e] = chaos_creators_validate(array_merge($good, array('channel_url' => $bad)), $crit);
	check($e !== array(), 'refused channel link: ' . $bad);
}
[$e] = chaos_creators_validate(array_merge($good, array('platform' => 'myspace')), $crit);
check($e !== array(), 'unknown platform');
[$e] = chaos_creators_validate(array_merge($good, array('message' => str_repeat('x', 1001))), $crit);
check($e !== array(), 'message over 1000 characters');

// ---------------------------------------------------------------- submit
$now = 1800000000;
check(chaos_creators_submit(0, $good, '1.1.1.1', $now)[0] === false, 'logged out: refused');
[$ok, $msg] = chaos_creators_submit(2, array_merge($good, array('character_name' => 'Other Streams')), '1.1.1.1', $now);
check(!$ok && $msg === 'That character is not on your account.', "someone else's character is refused");
[$ok, $msg, $args] = chaos_creators_submit(2, array_merge($good, array('hours_week' => 1)), '1.1.1.1', $now);
check(!$ok && $args === array(4), 'criteria message carries its number');
[$ok, $msg] = chaos_creators_submit(2, $good, '1.1.1.1', $now);
check($ok, 'stored: ' . $msg);
$row = $pdo->query('SELECT * FROM chaos_creator_applications')->fetch(PDO::FETCH_ASSOC);
check($row['account_id'] == 2 && $row['status'] === 'new' && $row['character_name'] === 'Ember Streams' && $row['ip'] === '1.1.1.1' && (int)$row['created_at'] === $now, 'the row');
[$ok, $msg] = chaos_creators_submit(2, $good, '1.1.1.1', $now + 5);
check(!$ok && strpos($msg, 'already have an application') !== false, 'one open application per account');
$list = chaos_creators_applications();
check(count($list) === 1 && $list[0]['platform'] === 'twitch', 'the staff list');

// ---------------------------------------------------------------- review, then a new one, and the limits
[$ok] = chaos_creators_review((int)$row['id'], 'rejected', 'web:owner', $now + 10);
check($ok && $pdo->query('SELECT status FROM chaos_creator_applications')->fetchColumn() === 'rejected', 'rejected');
check(chaos_creators_review((int)$row['id'], 'deleted', 'x')[0] === false, 'unknown action');
check(chaos_creators_review(999, 'approved', 'x')[0] === false, 'unknown application');
[$ok] = chaos_creators_submit(2, $good, '1.1.1.1', $now + 20);
check($ok, 'after a review the account may apply again');
chaos_creators_review((int)$pdo->query('SELECT MAX(id) FROM chaos_creator_applications')->fetchColumn(), 'approved', 'web:owner', $now + 21);
[$ok] = chaos_creators_submit(2, $good, '1.1.1.1', $now + 30);
check($ok, 'third application of the day');
chaos_creators_review((int)$pdo->query('SELECT MAX(id) FROM chaos_creator_applications')->fetchColumn(), 'rejected', 'web:owner', $now + 31);
[$ok, $msg] = chaos_creators_submit(2, $good, '1.1.1.1', $now + 40);
check(!$ok && strpos($msg, 'today') !== false, '3 applications per account a day');
[$ok] = chaos_creators_submit(2, $good, '1.1.1.1', $now + 86500);
check($ok, 'the next day it works again');
// per address: 5 an hour; accounts 3 and 4 and the address of the others
$pdo->exec('DELETE FROM chaos_creator_applications');
$ipCount = 0;
for ($i = 0; $i < 5; $i++) {
	$pdo->exec("INSERT INTO chaos_creator_applications (account_id, character_name, platform, channel_url, ip, status, created_at) VALUES (" . (100 + $i) . ", 'x', 'twitch', 'https://x.example', '5.5.5.5', 'rejected', " . ($now + 100) . ")");
}
[$ok, $msg] = chaos_creators_submit(3, array_merge($good, array('character_name' => 'Other Streams')), '5.5.5.5', $now + 200);
check(!$ok && strpos($msg, 'your address') !== false, '5 applications per address an hour');
[$ok] = chaos_creators_submit(3, array_merge($good, array('character_name' => 'Other Streams')), '6.6.6.6', $now + 200);
check($ok, 'another address is fine');
[$ok] = chaos_creators_submit(4, array_merge($good, array('character_name' => 'Third One')), '5.5.5.5', $now + 3800);
check($ok, 'an hour later the address is fine');
$TABLES['chaos_creator_applications'] = false;
$GLOBALS['TABLES'] = $TABLES;

// ---------------------------------------------------------------- the pages
$page = file_get_contents(__DIR__ . '/../overlay/plugins/chaos/pages/creators.php');
check(strpos($page, 'hash_equals($csrf') !== false && strpos($page, 'name="csrf"') !== false, 'the form has a CSRF token and the page checks it');
check(strpos($page, "'REQUEST_METHOD'") !== false && strpos($page, "chaos_creators_submit") !== false, 'the form posts to the library');
check(strpos($page, "\$GLOBALS['config']['chaos']['discord_url']") !== false && strpos($page, 'preg_match(\'#^https://#\'') !== false, 'the Discord link comes from the config and shows only when set (https)');
$admin = file_get_contents(__DIR__ . '/../overlay/plugins/chaos/pages/creator.php');
check(strpos($admin, 'chaos_creators_applications()') !== false && strpos($admin, '$isAdmin && in_array($_POST[\'do\'], array(\'app_approved\'') !== false, 'staff read and review the applications in the admin part');
$sql = (string)file_get_contents(__DIR__ . '/../../server/sql/chaos_creator_codes.sql');
check(strpos($sql, 'chaos_creator_applications') === false, 'the table is the website\'s only (install.sql), not the game server\'s');

echo $failed === 0 ? "chaos_creators_apply_test: $checks checks OK\n" : "chaos_creators_apply_test: $failed of $checks checks FAILED\n";
exit($failed === 0 ? 0 : 1);
