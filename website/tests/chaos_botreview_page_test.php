<?php
// php website/tests/chaos_botreview_page_test.php : the staff page of the bot review (plugins/chaos/pages/botreview.php,
// botreview_lib.php) rendered with php-cli over an in-memory SQLite database: access (admin panel account and a group 4+
// character), the list and its filters, escaping, the day view (signals, explanations, timeline, 30 days, presence
// checks, actions), the CSRF token, reviewed / false positive / escalate / note / presence check request (logged),
// escalated days only for group 5, no other actions. No ZnoteX, no network. Exit status 0 when every check passes.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'), 'page_admin_access' => array('gmacc', 'adminacc', 'tutoracc'));
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/botreview_lib.php';

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
$pdo->exec("INSERT INTO accounts (id, name) VALUES (1, 'gmacc'), (2, 'player'), (3, 'adminacc'), (4, 'tutoracc')");
$pdo->exec("CREATE TABLE players (id INTEGER PRIMARY KEY, name TEXT, account_id INT, group_id INT)");
$pdo->exec("INSERT INTO players (id, name, account_id, group_id) VALUES (10, 'Gm Jo', 1, 4), (11, 'Grimtooth', 2, 1), (12, 'Admin Al', 3, 5), (13, 'Tutor Ty', 4, 2)");
// the tables as sql/chaos_bot.sql makes them (SQLite types)
$pdo->exec("CREATE TABLE chaos_bot_daily (id INTEGER PRIMARY KEY AUTOINCREMENT, player_id INT NOT NULL, account_id INT NOT NULL DEFAULT 0,
	player_name TEXT NOT NULL DEFAULT '', day INT NOT NULL, score INT NOT NULL DEFAULT 0, peak INT NOT NULL DEFAULT 0,
	flagged INT NOT NULL DEFAULT 0, signals TEXT NOT NULL DEFAULT '', reasons TEXT NOT NULL DEFAULT '', timeline TEXT NOT NULL DEFAULT '',
	status TEXT NOT NULL DEFAULT 'none', reviewed_by TEXT NOT NULL DEFAULT '', reviewed_at INT NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '',
	created_at INT NOT NULL, updated_at INT NOT NULL, UNIQUE (player_id, day))");
$pdo->exec("CREATE TABLE chaos_bot_actions (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at INT NOT NULL, player_id INT NOT NULL,
	player_name TEXT NOT NULL DEFAULT '', day INT NOT NULL DEFAULT 0, action TEXT NOT NULL, staff TEXT NOT NULL DEFAULT '',
	staff_group INT NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '', done_at INT NOT NULL DEFAULT 0, result TEXT NOT NULL DEFAULT '')");
$pdo->exec("CREATE TABLE chaos_antibot_log (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at INT NOT NULL, player_id INT NOT NULL,
	account_id INT NOT NULL DEFAULT 0, player_name TEXT NOT NULL DEFAULT '', kind TEXT NOT NULL, score INT NOT NULL DEFAULT 0,
	detail TEXT NOT NULL DEFAULT '', pos_x INT NOT NULL DEFAULT 0, pos_y INT NOT NULL DEFAULT 0, pos_z INT NOT NULL DEFAULT 0)");

$now = time();
$today = (int)date('Ymd', $now);
$old = (int)date('Ymd', $now - 20 * 86400);
$ins = $pdo->prepare("INSERT INTO chaos_bot_daily (player_id, account_id, player_name, day, score, peak, flagged, signals, reasons, timeline, status,
	created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
$sig = 'timing=0.00;reaction=1.00;loot=0.00;heal=1.00;retarget=1.00;nonstop=1.00;silence=1.00;route=1.00;loop=0.72;presence=1.00;cluster=0.00';
$ins->execute(array(11, 2, 'Grimtooth', $today, 97, 99, 1, $sig,
	'heal 1.00: 97% of 40 heals fit one HP threshold (65%) | silence 1.00: <b>no</b> noise | presence 1.00: missed a presence check while still acting',
	'0=40,1=88,2=95,3=99', 'new', $now, $now));
$ins->execute(array(11, 2, 'Grimtooth', $old, 71, 80, 1, $sig, 'old day', '5=70,6=72', 'new', $now, $now));
$ins->execute(array(14, 5, 'Helpy', $today, 29, 36, 0, 'heal=1.00;reaction=1.00;nonstop=1.00', 'automation without unattended signs: typical for the allowed client helper', '9=20,10=29', 'none', $now, $now));
$ins->execute(array(15, 6, "Bad'Name<x>", $today, 64, 70, 1, 'nonstop=1.00;silence=0.60;bogus=9;timing=7', 'x', 'nope,25=80,3=150', 'escalated', $now, $now));
$pdo->exec("INSERT INTO chaos_antibot_log (created_at, player_id, player_name, kind, score, detail) VALUES ($now, 11, 'Grimtooth', 'check_fail', 140, 'no answer after 80 s, attempt 1, action log')");

$SESSION_USER = 0;
function getSession(string $k) { global $SESSION_USER; return $k === 'user_id' ? $SESSION_USER : null; }
function render(array $get = array(), array $post = array()): string {
	global $config;
	$_GET = $get; $_POST = $post;
	$_SERVER['REQUEST_METHOD'] = $post ? 'POST' : 'GET';
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/botreview.php';
	return (string)ob_get_clean();
}
session_start();

// access
$html = render();
check(strpos($html, 'Not found') !== false && strpos($html, 'Grimtooth') === false, 'logged out: not found');
$SESSION_USER = 2;
check(strpos(render(), 'Not found') !== false, 'player account: not found');
$SESSION_USER = 4;
check(strpos(render(), 'Not found') !== false, 'an admin panel account with only a tutor (group 2): not found');
check(chaos_botreview_group($config, 1) === 4 && chaos_botreview_group($config, 3) === 5 && chaos_botreview_group($config, 2) === 0, 'groups');
$SESSION_USER = 1;

// list
$html = render();
check(strpos($html, 'Bot Review') !== false && strpos($html, '>Grimtooth</strong>') !== false, 'flagged day listed');
check(strpos($html, 'Helpy') === false, 'a day under flagAt is not on the list');
check(strpos($html, 'Bad&#039;Name&lt;x&gt;') === false, 'escalated days are on their own tab');
check(substr_count($html, '>Grimtooth</strong>') === 1, 'last 7 days by default (the 20 days old one is not listed)');
check(strpos($html, 'Heals at one HP threshold 1.00') !== false, 'strongest signals shown');
$html = render(array('days' => '30'));
check(substr_count($html, '>Grimtooth</strong>') === 2, 'last 30 days');
$html = render(array('status' => 'escalated'));
check(strpos($html, 'Bad&#039;Name&lt;x&gt;') !== false && strpos($html, '<x>') === false, 'escalated tab, name escaped');
$html = render(array('status' => 'all', 'name' => 'grim'));
check(strpos($html, 'Grimtooth') !== false && strpos($html, 'Bad&#039;') === false, 'name filter');
$f = chaos_botreview_filters(array('status' => "x' OR 1=1", 'days' => '999', 'name' => '<script>', 'page' => '-3'));
check($f['status'] === 'new' && $f['days'] === 7 && $f['name'] === '' && $f['page'] === 1, 'bad filters ignored');

// parsers
$p = chaos_botreview_parse_signals('nonstop=1.00;silence=0.60;bogus=9;timing=7;heal=x');
check($p === array('nonstop' => 1.0, 'silence' => 0.6, 'timing' => 1.0), 'signals parsed, unknown dropped, clamped');
check(chaos_botreview_parse_timeline('nope,25=80,3=150,1=20') === array(1 => 20, 3 => 100), 'timeline parsed and bounded');

// the day view
$html = render(array('id' => '1'));
check(strpos($html, 'chaos-botreview-signals') !== false && strpos($html, 'Missed presence check') !== false, 'signal table');
check(strpos($html, '&lt;b&gt;no&lt;/b&gt; noise') !== false && strpos($html, '<b>no</b>') === false, 'explanations escaped');
check(substr_count($html, '<li>') === 3, 'three explanations');
check(strpos($html, 'title="03:00: 99"') !== false && strpos($html, 'title="12:00: offline"') !== false, 'hourly timeline');
check(strpos($html, 'chaos-botreview-history') !== false && substr_count($html, '&amp;id=') >= 2, '30 days of the character');
check(strpos($html, 'check fail') !== false && strpos($html, 'no answer after 80 s') !== false, 'presence checks from the anti-bot log');
check(strpos($html, 'value="escalate"') !== false && strpos($html, 'value="check"') !== false, 'review buttons');

// CSRF and actions
$html = render(array('id' => '1'), array('rid' => '1', 'do' => 'reviewed', 'note' => 'x', 'csrf' => 'wrong'));
check(strpos($html, 'The form expired') !== false, 'CSRF token checked');
check($pdo->query("SELECT status FROM chaos_bot_daily WHERE id = 1")->fetchColumn() === 'new', 'nothing changed without the token');
$token = $_SESSION['chaos_botreview_csrf'];
$html = render(array(), array('rid' => '1', 'do' => 'false_positive', 'note' => "  helper user,\npassed the check  ", 'csrf' => $token));
check(strpos($html, 'marked false positive') !== false, 'false positive');
$r = $pdo->query("SELECT status, reviewed_by, note, reviewed_at FROM chaos_bot_daily WHERE id = 1")->fetch(PDO::FETCH_ASSOC);
check($r['status'] === 'false_positive' && $r['reviewed_by'] === 'web:gmacc' && $r['note'] === 'helper user, passed the check' && (int)$r['reviewed_at'] > 0, 'stored');
$a = $pdo->query("SELECT action, staff, staff_group, note, day FROM chaos_bot_actions ORDER BY id DESC LIMIT 1")->fetch(PDO::FETCH_ASSOC);
check($a['action'] === 'false_positive' && $a['staff'] === 'web:gmacc' && (int)$a['staff_group'] === 4 && (int)$a['day'] === $today, 'action logged');
render(array(), array('rid' => '1', 'do' => 'reviewed', 'note' => 'second look', 'csrf' => $token));
check($pdo->query("SELECT status FROM chaos_bot_daily WHERE id = 1")->fetchColumn() === 'reviewed', 'reviewed');
$html = render(array(), array('rid' => '1', 'do' => 'check', 'note' => '', 'csrf' => $token));
check(strpos($html, 'Presence check requested for Grimtooth') !== false, 'presence check requested');
check((int)$pdo->query("SELECT COUNT(*) FROM chaos_bot_actions WHERE action = 'check' AND done_at = 0 AND player_id = 11")->fetchColumn() === 1, 'waiting for the server');
$html = render(array(), array('rid' => '1', 'do' => 'check', 'note' => '', 'csrf' => $token));
check(strpos($html, 'already waiting') !== false, 'one waiting check per character');
check(strpos($html, '(waiting)') !== false, 'the waiting request is shown');
render(array(), array('rid' => '1', 'do' => 'escalate', 'note' => 'ban case, see report 12', 'csrf' => $token));
check($pdo->query("SELECT status FROM chaos_bot_daily WHERE id = 1")->fetchColumn() === 'escalated', 'GM escalates');
$html = render(array(), array('rid' => '1', 'do' => 'false_positive', 'note' => '', 'csrf' => $token));
check(strpos($html, 'only an administrator') !== false && $pdo->query("SELECT status FROM chaos_bot_daily WHERE id = 1")->fetchColumn() === 'escalated',
	'a GM cannot change an escalated day');
check(strpos($html, 'chaos-botreview-locked') !== false && strpos($html, 'value="escalate"') === false, 'locked view for the GM');
render(array(), array('rid' => '1', 'do' => 'note', 'note' => 'GM note on an escalated day', 'csrf' => $token));
check($pdo->query("SELECT note FROM chaos_bot_daily WHERE id = 1")->fetchColumn() === 'GM note on an escalated day', 'a note is still allowed');
$html = render(array(), array('rid' => '1', 'do' => 'ban', 'csrf' => $token));
check(strpos($html, 'Unknown action.') !== false, 'no other actions (nothing here bans)');
$html = render(array(), array('rid' => '99', 'do' => 'reviewed', 'csrf' => $token));
check(strpos($html, 'No such day.') !== false, 'unknown day');
$SESSION_USER = 3;
$html = render(array(), array('rid' => '1', 'do' => 'reviewed', 'note' => 'admin: 7 day ban per ladder', 'csrf' => $token));
check($pdo->query("SELECT status FROM chaos_bot_daily WHERE id = 1")->fetchColumn() === 'reviewed', 'an administrator decides an escalated day');
check($pdo->query("SELECT staff FROM chaos_bot_actions ORDER BY id DESC LIMIT 1")->fetchColumn() === 'web:adminacc', 'logged with the administrator');
$SESSION_USER = 2;
render(array(), array('rid' => '3', 'do' => 'reviewed', 'csrf' => $token));
check($pdo->query("SELECT status FROM chaos_bot_daily WHERE id = 3")->fetchColumn() === 'none', 'a player cannot post actions');
check(chaos_botreview_action('reviewed', 1, '', 'x', 2, $now)[0] === false, 'the lib refuses group 2 too');

// the SQL file and the server's table names agree
$sql = (string)file_get_contents(__DIR__ . '/../../server/sql/chaos_bot.sql');
foreach (array('chaos_bot_daily', 'chaos_bot_actions', '`reasons`', '`timeline`', 'UNIQUE KEY `uniq_player_day`', '`done_at`') as $needle) {
	check(strpos($sql, $needle) !== false, "chaos_bot.sql has $needle");
}
$cfgLua = (string)file_get_contents(__DIR__ . '/../../server/data/scripts/chaos/botreview_config.lua');
check(strpos($cfgLua, 'flagAt = 50') !== false, 'the page text says 50, as botreview_config.lua flagAt');

if ($failed > 0) {
	echo "chaos_botreview_page_test: $failed failed\n";
	exit(1);
}
echo "chaos_botreview_page_test: all passed\n";
