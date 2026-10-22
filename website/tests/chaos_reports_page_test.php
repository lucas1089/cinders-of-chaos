<?php
// php website/tests/chaos_reports_page_test.php : the staff page of player reports and the anti-bot log
// (plugins/chaos/pages/reports.php, reports_lib.php) rendered with php-cli over an in-memory SQLite database: admin-only
// access (ZnoteX's page_admin_access), filters, escaping, the CSRF token, close / note / reopen, the log view, and the
// leaderboard hold clause of lib.php. No ZnoteX, no network. Exit status 0 when every check passes.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'), 'page_admin_access' => array('staffacc'));
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/reports_lib.php';

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

$pdo->exec("CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT NOT NULL)");
$pdo->exec("INSERT INTO accounts (id, name) VALUES (1, 'staffacc'), (2, 'player')");
$pdo->exec("CREATE TABLE chaos_reports (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at INT NOT NULL, reporter_id INT NOT NULL,
	reporter_account INT NOT NULL DEFAULT 0, reporter_name TEXT NOT NULL DEFAULT '', target_id INT NOT NULL, target_name TEXT NOT NULL DEFAULT '',
	reason TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', pos_x INT NOT NULL DEFAULT 0, pos_y INT NOT NULL DEFAULT 0, pos_z INT NOT NULL DEFAULT 0,
	target_online INT NOT NULL DEFAULT 0, suspicion INT NOT NULL DEFAULT 0, chat TEXT, status TEXT NOT NULL DEFAULT 'open',
	closed_at INT NOT NULL DEFAULT 0, closed_by TEXT NOT NULL DEFAULT '', staff_note TEXT NOT NULL DEFAULT '')");
$pdo->exec("CREATE TABLE chaos_antibot_log (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at INT NOT NULL, player_id INT NOT NULL,
	account_id INT NOT NULL DEFAULT 0, player_name TEXT NOT NULL DEFAULT '', kind TEXT NOT NULL, score INT NOT NULL DEFAULT 0,
	detail TEXT NOT NULL DEFAULT '', pos_x INT NOT NULL DEFAULT 0, pos_y INT NOT NULL DEFAULT 0, pos_z INT NOT NULL DEFAULT 0)");
$ins = $pdo->prepare("INSERT INTO chaos_reports (created_at, reporter_id, reporter_name, target_id, target_name, reason, note, pos_x, pos_y, pos_z,
	target_online, suspicion, chat) VALUES (?, 1, ?, 2, ?, ?, ?, 32100, 32200, 7, 1, ?, ?)");
$ins->execute(array(1791000000, 'Arwen', 'Grimtooth', 'botting', 'same circle for hours', 143, "[12:01] World Chat: <script>alert(1)</script>\n[12:02] Help: where is the boat"));
$ins->execute(array(1791000100, 'Bram', 'Shady Sam', 'scam', 'took my gold', 0, ''));
$ins->execute(array(1791000200, 'Cora', 'Grimtooth', 'name', 'rude name', 12, ''));
$pdo->exec("INSERT INTO chaos_antibot_log (created_at, player_id, player_name, kind, score, detail) VALUES
	(1791000300, 2, 'Grimtooth', 'score', 131, 'score 131; timing 1.00 cv 0.006 n 32'),
	(1791000400, 2, 'Grimtooth', 'check_fail', 171, 'no answer after 76 s, attempt 1, action temple'),
	(1791000500, 5, 'Elda', 'check_pass', 24, 'answered in 9 s, attempt 1')");

$SESSION_USER = 0;
function getSession(string $k) { global $SESSION_USER; return $k === 'user_id' ? $SESSION_USER : null; }
function render(array $get = array(), array $post = array()): string {
	global $config;
	$_GET = $get; $_POST = $post;
	$_SERVER['REQUEST_METHOD'] = $post ? 'POST' : 'GET';
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/reports.php';
	return (string)ob_get_clean();
}
session_start();

// access
$html = render();
check(strpos($html, 'Not found') !== false && strpos($html, 'Grimtooth') === false, 'logged out: not found');
$SESSION_USER = 2;
$html = render();
check(strpos($html, 'Not found') !== false && strpos($html, 'Grimtooth') === false, 'player account: not found');
check(!chaos_reports_is_admin($config, 2) && chaos_reports_is_admin($config, 1), 'admin check by account name');
$SESSION_USER = 1;

// list, escaping, filters
$html = render();
check(strpos($html, 'Player Reports') !== false && substr_count($html, 'name="rid"') === 3, 'three open reports with a form each');
check(strpos($html, '<script>alert(1)</script>') === false && strpos($html, '&lt;script&gt;alert(1)&lt;/script&gt;') !== false, 'chat escaped');
check(strpos($html, 'World Chat') !== false && strpos($html, 'Position 32100, 32200, 7') !== false, 'chat lines and position');
check(strpos($html, 'class="num chaos-gold">143') !== false, 'high suspicion highlighted');
$html = render(array('reason' => 'scam'));
check(strpos($html, 'Shady Sam') !== false && strpos($html, 'Grimtooth') === false, 'filter by reason');
$html = render(array('name' => 'grimtooth'));
check(substr_count($html, 'name="rid"') === 2 && strpos($html, 'Shady Sam') === false, 'filter by name (target or reporter)');
$html = render(array('name' => "x' OR 1=1 --", 'status' => 'nope', 'reason' => 'drop'));
check(substr_count($html, 'name="rid"') === 3, 'bad filters ignored');
$f = chaos_report_filters(array('status' => 'all', 'page' => '-4'));
check($f['status'] === 'all' && $f['page'] === 1, 'filter validation');

// CSRF and actions
$html = render(array(), array('rid' => '1', 'do' => 'close', 'note' => 'x', 'csrf' => 'wrong'));
check(strpos($html, 'The form expired') !== false, 'CSRF token checked');
check($pdo->query("SELECT status FROM chaos_reports WHERE id = 1")->fetchColumn() === 'open', 'nothing changed without the token');
$token = $_SESSION['chaos_reports_csrf'];
$html = render(array(), array('rid' => '1', 'do' => 'close', 'note' => "  watched him 20 min,\nanswered the check  ", 'csrf' => $token));
check(strpos($html, 'Report #1 closed.') !== false, 'closed');
$row = $pdo->query("SELECT status, closed_by, staff_note, closed_at FROM chaos_reports WHERE id = 1")->fetch(PDO::FETCH_ASSOC);
check($row['status'] === 'closed' && $row['closed_by'] === 'web:staffacc' && $row['staff_note'] === 'watched him 20 min, answered the check'
	&& (int)$row['closed_at'] > 0, 'close stored with the staff note');
check(substr_count($html, 'name="rid"') === 2, 'closed report leaves the open list');
$html = render(array(), array('rid' => '1', 'do' => 'close', 'note' => '', 'csrf' => $token));
check(strpos($html, 'already closed') !== false, 'close twice refused');
$html = render(array('status' => 'closed'));
check(strpos($html, 'Reopen') !== false && strpos($html, 'by web:staffacc') !== false, 'closed tab');
render(array(), array('rid' => '1', 'do' => 'note', 'note' => 'second look: fine', 'csrf' => $token));
check($pdo->query("SELECT staff_note FROM chaos_reports WHERE id = 1")->fetchColumn() === 'second look: fine', 'note saved');
render(array(), array('rid' => '1', 'do' => 'reopen', 'csrf' => $token));
check($pdo->query("SELECT status FROM chaos_reports WHERE id = 1")->fetchColumn() === 'open', 'reopened');
$html = render(array(), array('rid' => '99', 'do' => 'close', 'csrf' => $token));
check(strpos($html, 'No report #99.') !== false, 'unknown report');
$html = render(array(), array('rid' => '2', 'do' => 'ban', 'csrf' => $token));
check(strpos($html, 'Unknown action.') !== false, 'no other actions');
$SESSION_USER = 2;
$html = render(array(), array('rid' => '2', 'do' => 'close', 'csrf' => $token));
check($pdo->query("SELECT status FROM chaos_reports WHERE id = 2")->fetchColumn() === 'open', 'a player cannot post actions');
$SESSION_USER = 1;

// the anti-bot log
$html = render(array('log' => '1'));
check(strpos($html, 'chaos-antibot-log') !== false && strpos($html, 'check fail') !== false && strpos($html, 'Elda') !== false, 'log view');
$html = render(array('log' => '1', 'name' => 'Grimtooth'));
check(strpos($html, 'Elda') === false && substr_count($html, '<td>Grimtooth') === 0 && substr_count($html, '>Grimtooth</a>') === 2, 'log of one character');

// a bug report (System > Report a Bug, reports.lua RP.onReportBug): its own reason, details instead of chat
$ins->execute(array(1791000300, 'Dana', 'Dana', 'bug', '[map] hole in the bridge', 0, "Category: map\nCharacter position: 1, 2, 7"));
$html = render(array('reason' => 'bug'));
check(strpos($html, '[map] hole in the bridge') !== false && strpos($html, 'Shady Sam') === false, 'filter by reason bug');
check(strpos($html, '<summary>Details</summary>') !== false && strpos($html, '(bug report)') !== false, 'bug report details');

// the leaderboard hold clause (lib.php)
check(strpos(chaos_antibot_hold_sql(), 'NOT EXISTS (SELECT 1 FROM `chaos_antibot_holds`') !== false, 'hold clause for the boards');
// the staff's tester bots never rank (server/README.md "Tester bots"; the game's Chaos.storage.tester)
check(chaos_tester_sql() === ' AND NOT EXISTS (SELECT 1 FROM `player_storage` `ts` WHERE `ts`.`player_id` = `p`.`id` AND `ts`.`key` = 7102900 AND `ts`.`value` = 1)',
	'tester clause for the boards');
check(strpos(chaos_tester_sql('`players`'), '`players`.`id`') !== false, 'tester clause with another alias');
check(preg_match('/Chaos\.storage\.tester = 7102900\b/', (string)file_get_contents(__DIR__ . '/../../server/data/scripts/chaos/chaos_constants.lua')) === 1,
	'the website uses the game\'s tester storage key');

echo $failed === 0 ? "chaos_reports_page_test: OK\n" : "chaos_reports_page_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
