<?php
// php website/tests/chaos_legal_accept_test.php : existing accounts accept the current Terms of Use and Privacy Policy
// (plugins/chaos/legal_lib.php, pages/accept.php, plugin.php): which requests the gate sends to the accept page, the
// way back (pages of this site only), the form (CSRF token, the checkbox), the row (the same as at sign-up: account,
// version, time, no IP), a new version of the texts asking again, and the website setup writing the version for the
// game server's notice. php-cli only, no ZnoteX, an in-memory SQLite database.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));
$GLOBALS['config'] = $config;

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
final class ChaosAcceptFakeDb {
	public PDO $pdo;
	public array $log = array();
	public function __construct(PDO $pdo) { $this->pdo = $pdo; }
	private function run(string $sql, array $p): PDOStatement {
		$this->log[] = array($sql, $p);
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
$DB = new ChaosAcceptFakeDb($pdo);
function db() { return $GLOBALS['DB']; }
$pdo->exec('CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT NOT NULL)');
$pdo->exec("INSERT INTO accounts (id, name) VALUES (7, 'betatester'), (41, 'newbie')");
$pdo->exec('CREATE TABLE chaos_legal_acceptance (id INTEGER PRIMARY KEY AUTOINCREMENT, account_id INT NOT NULL, version TEXT NOT NULL, accepted_at INT NOT NULL)');

$SESSION_USER = 0;
function getSession(string $k) { global $SESSION_USER; return $k === 'user_id' ? $SESSION_USER : null; }

require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/legal_lib.php';

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
$repo = __DIR__ . '/../..';
$version = chaos_legal_version();
// newbie signed up with the checkbox (the sign-up row); betatester is a beta account from before it
chaos_legal_record('newbie', 1790000000);
$rows = $pdo->query('SELECT * FROM chaos_legal_acceptance')->fetchAll(PDO::FETCH_ASSOC);
check(count($rows) === 1 && (int)$rows[0]['account_id'] === 41 && $rows[0]['version'] === $version, 'sign-up row');

// ---------------------------------------------------------------- who has accepted
check(chaos_legal_has_accepted(41), 'signed up with the checkbox: accepted');
check(!chaos_legal_has_accepted(7), 'beta account: not accepted');
check(chaos_legal_has_accepted(0), 'logged out: nothing to ask');

// ---------------------------------------------------------------- which requests pass
$srv = array('REQUEST_URI' => '/myaccount.php');
check(chaos_legal_gate_target(7, '/myaccount.php', array(), $srv) === CHAOS_LEGAL_ACCEPT_URL, 'beta account on its account page: to the accept page');
check(chaos_legal_gate_target(41, '/myaccount.php', array(), $srv) === null, 'accepted account: passes');
check(chaos_legal_gate_target(0, '/myaccount.php', array(), $srv) === null, 'logged out: passes');
$to = chaos_legal_gate_target(7, '/page.php', array('plugin' => 'chaos', 'p' => 'leaderboards'), array('REQUEST_URI' => '/page.php?plugin=chaos&p=leaderboards&board=xp'));
check($to === CHAOS_LEGAL_ACCEPT_URL . '&next=' . rawurlencode('page.php?plugin=chaos&p=leaderboards&board=xp'), 'the page wanted comes back after: ' . $to);
check(chaos_legal_gate_target(7, '/createcharacter.php', array(), array('REQUEST_URI' => '/createcharacter.php')) !== null, 'character creation is gated');
foreach (array('/login.php', '/logout.php', '/register.php', '/recovery.php', '/chaos_pay_webhook.php') as $s) {
	check(chaos_legal_gate_target(7, $s, array(), array('REQUEST_URI' => $s)) === null, "$s passes");
}
check(chaos_legal_gate_target(7, '/page.php', array('plugin' => 'chaos', 'p' => 'accept'), $srv) === null, 'the accept page itself passes');
check(chaos_legal_gate_target(7, '/page.php', array('plugin' => 'chaos', 'p' => 'legal', 'doc' => 'terms'), $srv) === null, 'the legal texts pass (to read them)');
check(chaos_legal_gate_target(7, '/page.php', array('plugin' => 'other', 'p' => 'accept'), $srv) !== null, 'another plugin named accept: gated');
check(chaos_legal_gate_target(7, '/myaccount.php', array(), $srv + array('HTTP_X_REQUESTED_WITH' => 'XMLHttpRequest')) !== null, 'an X-Requested-With header alone does not pass');
check(chaos_legal_gate_target(7, '/admin/index.php', array('p' => 'update'), $srv + array('REQUEST_METHOD' => 'POST')) === null, 'the admin updater background call passes');
check(chaos_legal_gate_target(7, '/admin/index.php', array('p' => 'update'), $srv + array('REQUEST_METHOD' => 'GET')) !== null, 'the admin updater page itself is gated');

// ---------------------------------------------------------------- the way back: this site only
check(chaos_legal_safe_next('page.php?plugin=chaos&p=coins') === 'page.php?plugin=chaos&p=coins', 'a page of the site');
check(chaos_legal_safe_next('/characterprofile.php?name=Arwen') === 'characterprofile.php?name=Arwen', 'leading slash dropped');
foreach (array('', 'https://evil.example/x.php', '//evil.example/x.php', 'javascript:alert(1)', '../x.php', 'x.php?a="><script>',
	'page.php?plugin=chaos&p=accept', "x.php\r\nSet-Cookie: a=b", 'x.php?a=\\evil') as $bad) {
	check(chaos_legal_safe_next($bad) === 'myaccount.php', 'refused next: ' . json_encode($bad));
}
check(chaos_legal_accept_url('/page.php?plugin=chaos&p=accept&next=x') === CHAOS_LEGAL_ACCEPT_URL, 'no loop back to the accept page');

// ---------------------------------------------------------------- the form
check(chaos_legal_accept_post(7, array('chaos_accept_terms' => '1', 'csrf' => 'bad'), 'good', 1) === array(false, 'The form expired. Please try again. / O formulário expirou. Tente de novo.'), 'wrong token: refused');
check(chaos_legal_accept_post(7, array('chaos_accept_terms' => '1', 'csrf' => ''), '', 1)[0] === false, 'no session token: refused');
check(chaos_legal_accept_post(7, array('csrf' => 'good'), 'good', 1) === array(false, CHAOS_LEGAL_ACCEPT_ERROR), 'box not ticked: refused');
check(chaos_legal_accept_post(7, array('chaos_accept_terms' => 'yes', 'csrf' => 'good'), 'good', 1)[0] === false, 'only the value 1 counts');
check(chaos_legal_accept_post(0, array('chaos_accept_terms' => '1', 'csrf' => 'good'), 'good', 1)[0] === false, 'logged out: refused');
check(!chaos_legal_has_accepted(7), 'nothing recorded by a refused form');

// ---------------------------------------------------------------- the page
function render_accept(array $get = array(), array $post = array()): string {
	global $config;
	$_GET = $get;
	$_POST = $post;
	$_SERVER['REQUEST_METHOD'] = $post ? 'POST' : 'GET';
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/accept.php';
	return (string)ob_get_clean();
}
session_start();
$html = render_accept();
check(strpos($html, 'href="login.php"') !== false && strpos($html, 'chaos_accept_terms') === false, 'logged out: log in first');

$SESSION_USER = 7;
$html = render_accept(array('next' => 'page.php?plugin=chaos&p=coins'));
$csrf = (string)($_SESSION['chaos_legal_csrf'] ?? '');
check(strlen($csrf) === 32, 'a session token');
check(strpos($html, '<input type="checkbox" name="chaos_accept_terms" value="1">') !== false, 'the checkbox, unchecked');
check(strpos($html, 'name="csrf" value="' . $csrf . '"') !== false, 'the token in the form');
check(strpos($html, 'name="next" value="page.php?plugin=chaos&amp;p=coins"') !== false, 'the way back, escaped');
check(strpos($html, 'href="page.php?plugin=chaos&amp;p=legal&amp;doc=terms&amp;l=en"') !== false
	&& strpos($html, 'href="page.php?plugin=chaos&amp;p=legal&amp;doc=privacy"') !== false, 'links to both texts in both languages');
check(strpos($html, 'Li e aceito os') !== false && strpos($html, 'Under 18') !== false, 'the same wording as at sign-up');
check(strpos($html, 'href="logout.php"') !== false, 'a way out without accepting');
$html = render_accept(array('next' => 'https://evil.example/'));
check(strpos($html, 'evil') === false && strpos($html, 'name="next" value="myaccount.php"') !== false, 'outside next dropped');

$html = render_accept(array(), array('csrf' => $csrf, 'next' => 'page.php?plugin=chaos&p=coins'));
check(strpos($html, 'id="chaos-legal-accept-error"') !== false && strpos($html, chaos_h(CHAOS_LEGAL_ACCEPT_ERROR)) !== false, 'box not ticked: the error');
check(!chaos_legal_has_accepted(7), 'still not accepted');

$before = count($DB->log);
$html = render_accept(array(), array('csrf' => $csrf, 'chaos_accept_terms' => '1', 'next' => 'page.php?plugin=chaos&p=coins'));
check(strpos($html, 'id="chaos-legal-accepted"') !== false && strpos($html, 'url=page.php?plugin=chaos&amp;p=coins') !== false, 'accepted: back to the page wanted');
check(chaos_legal_has_accepted(7), 'accepted now');
$row = $pdo->query('SELECT * FROM chaos_legal_acceptance WHERE account_id = 7')->fetchAll(PDO::FETCH_ASSOC);
check(count($row) === 1 && $row[0]['version'] === $version && (int)$row[0]['accepted_at'] > 0, 'one row: account, version, time');
check(array_keys($row[0]) === array('id', 'account_id', 'version', 'accepted_at'), 'no IP column written');
$insert = null;
foreach (array_slice($DB->log, $before) as $q) {
	if (strpos($q[0], 'INSERT INTO `chaos_legal_acceptance`') === 0) { $insert = $q; }
}
check($insert !== null && $insert[0] === 'INSERT INTO `chaos_legal_acceptance` (`account_id`, `version`, `accepted_at`) VALUES (?, ?, ?);' && count($insert[1]) === 3, 'the same INSERT as at sign-up, no IP');
render_accept(array(), array('csrf' => $csrf, 'chaos_accept_terms' => '1'));
check((int)$pdo->query('SELECT COUNT(*) FROM chaos_legal_acceptance WHERE account_id = 7')->fetchColumn() === 1, 'a second post adds no row');
check(chaos_legal_gate_target(7, '/myaccount.php', array(), $srv) === null, 'the gate lets the account through now');
$html = render_accept();
check(strpos($html, 'You have accepted') !== false && strpos($html, 'chaos_accept_terms') === false, 'already accepted: no form');

// a new version of the texts asks again
$pdo->exec("UPDATE chaos_legal_acceptance SET version = 'aaaaaaaaaaaaaaaa'");
check(!chaos_legal_has_accepted(7) && !chaos_legal_has_accepted(41), 'an older version: asked again');
check(chaos_legal_gate_target(41, '/myaccount.php', array(), $srv) !== null, 'the sign-up account too');

// ---------------------------------------------------------------- wiring
$plugin = (string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/plugin.php');
check(strpos($plugin, "chaos_legal_gate_target(\$chaosAccountId, (string)(\$_SERVER['SCRIPT_NAME'] ?? ''), \$_GET, \$_SERVER)") !== false
	&& strpos($plugin, "header('Location: ' . \$chaosGate, true, 303);") !== false, 'plugin.php runs the gate on every request');
check(strpos($plugin, "require_once __DIR__ . '/legal_lib.php';") < strpos($plugin, 'chaos_legal_gate_target('), 'legal_lib loaded before the gate');
$setup = (string)file_get_contents(__DIR__ . '/../setup/chaos_setup.php');
check(strpos($setup, "VALUES ('chaos_legal_version', '\$v') ON DUPLICATE KEY UPDATE") !== false, 'setup writes the version for the game server');
$notice = (string)file_get_contents($repo . '/server/data/scripts/chaos/legal_notice_config.lua');
check(strpos($notice, 'url = "' . CHAOS_LEGAL_ACCEPT_URL . '"') !== false, 'the game notice links this page');
$src = (string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/pages/accept.php');
check(strpos($src, "if (!isset(\$config)) { http_response_code(403);") !== false, 'no direct access');

echo $failed === 0 ? "chaos_legal_accept_test: $checks checks OK\n" : "chaos_legal_accept_test: $failed of $checks failed\n";
exit($failed === 0 ? 0 : 1);
