<?php
// php website/tests/chaos_referral_test.php : the referral code field of overlay/plugins/chaos/referral.php (php-cli
// only, no ZnoteX, a fake database). Reads the real server/data/scripts/chaos/referral_config.lua. Exit status 0 when
// every check passes.

$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));

// the ZnoteX db() helper, faked: tables exist; codes; inserted rows recorded
class ChaosFakeDb {
	public $codes = array('ABCD2345' => 7);
	public $accounts = array('newbie' => 9);
	public $inserted = array();
	public function fetchOne(string $sql, array $params = array()) {
		if (strpos($sql, 'information_schema') !== false) {
			return array('n' => 1);
		}
		if (strpos($sql, 'chaos_referral_codes') !== false) {
			return isset($this->codes[$params[0]]) ? array('account_id' => $this->codes[$params[0]]) : false;
		}
		if (strpos($sql, 'FROM `accounts`') !== false) {
			return isset($this->accounts[$params[0]]) ? array('id' => $this->accounts[$params[0]]) : false;
		}
		return false;
	}
	public function fetchAll(string $sql, array $params = array()) {
		return array();
	}
	public function execute(string $sql, array $params = array()) {
		$this->inserted[] = array($sql, $params);
		return true;
	}
}
$fakeDb = new ChaosFakeDb();
function db() {
	global $fakeDb;
	return $fakeDb;
}

$hooks = array();
function znote_hook_register(string $hook, callable $callback, int $priority = 10): void {
	global $hooks;
	$hooks[$hook][] = $callback;
}

require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/referral.php';

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

// settings read from referral_config.lua (the same alphabet and length as the server's)
$s = chaos_referral_settings();
$text = file_get_contents(__DIR__ . '/../../server/data/scripts/chaos/referral_config.lua');
preg_match('/code\s*=\s*\{length\s*=\s*(\d+),\s*alphabet\s*=\s*"([A-Z0-9]+)"/', $text, $m);
check(isset($m[1]) && $s['length'] === (int)$m[1] && $s['alphabet'] === $m[2], 'length and alphabet from referral_config.lua');
check($s['enabled'] === (bool)preg_match('/^\s*enabled\s*=\s*true/m', $text), 'enabled flag from the config');
preg_match('/^\s*entryDays\s*=\s*(\d+)/m', $text, $m);
check($s['entryDays'] === (int)$m[1], 'entry window from the config');

// normalizing, as referral_core.lua normalize
check(chaos_referral_normalize('abcd-2345', $s) === 'ABCD2345', 'lower case and dash');
check(chaos_referral_normalize(' ABCD 2345 ', $s) === 'ABCD2345', 'spaces');
check(chaos_referral_normalize('ABCD234', $s) === null, 'too short');
check(chaos_referral_normalize('ABCD2340', $s) === null, '0 is not in the alphabet');
check(chaos_referral_normalize(str_repeat('A', 60), $s) === null, 'far too long');

// the posted field
$owner = 'chaos_referral_owner';
check(chaos_referral_check('', $s, $owner) === array('', null, 0), 'empty field: no referral, no error');
check(chaos_referral_check('  ', $s, $owner) === array('', null, 0), 'blank field');
$r = chaos_referral_check('nonsense!', $s, $owner);
check($r[0] !== '' && $r[1] === null, 'bad format: an error');
$r = chaos_referral_check('ZZZZ-2345', $s, $owner);
check(strpos($r[0], 'No account') === 0, 'unknown code: an error');
$r = chaos_referral_check('abcd-2345', $s, $owner);
check($r === array('', 'ABCD2345', 7), 'a known code');
$off = $s;
$off['enabled'] = false;
check(chaos_referral_check('nonsense!', $off, $owner) === array('', null, 0), 'program off: the field is ignored');

// recording the pending link
check(chaos_referral_record(9, 7, 'ABCD2345', '203.0.113.5') === true, 'recorded');
$last = end($fakeDb->inserted);
check(strpos($last[0], 'INSERT IGNORE INTO `chaos_referrals`') === 0 && strpos($last[0], "'pending'") !== false, 'a pending row, never replaced');
check($last[1][0] === 9 && $last[1][1] === 7 && $last[1][2] === 'ABCD2345' && $last[1][3] === '203.0.113.5', 'its values');
check(chaos_referral_record(7, 7, 'ABCD2345', '') === false, 'not the own code');
check(chaos_referral_record(0, 7, 'ABCD2345', '') === false, 'no account');

// form value: posted, else ?ref=, cleaned
$_GET['ref'] = 'abcd-2345<script>';
check(chaos_referral_form_value() === 'abcd-2345scr', 'from the link, cleaned and cut to 12');
$_POST['referral_code'] = 'WXYZ-2345';
check(chaos_referral_form_value() === 'WXYZ-2345', 'the posted value first');
unset($_GET['ref'], $_POST['referral_code']);

// the register.php hooks: an invalid code stops the registration; a valid one is recorded after it
$_SERVER['REQUEST_METHOD'] = 'POST';
$_SERVER['SCRIPT_NAME'] = '/register.php';
$_SERVER['REMOTE_ADDR'] = '198.51.100.7';
$_POST = array('referral_code' => 'ZZZZ-2345');
$GLOBALS['errors'] = array();
require __DIR__ . '/../overlay/plugins/chaos/referral.php';
check(count($GLOBALS['errors']) === 0, 'init.php empties $errors after the plugins: nothing added yet');
$GLOBALS['errors'] = array(); // what init.php does
chaos_referral_add_error(); // the register_header view, after register.php's own checks
check(count($GLOBALS['errors']) === 1 && strpos($GLOBALS['errors'][0], 'No account') === 0, 'unknown code: registration stopped with a message');
chaos_referral_add_error();
check(count($GLOBALS['errors']) === 1, 'the message is added once');
check(empty($hooks['account.registered']), 'nothing recorded for it');
$_POST = array('referral_code' => 'ABCD-2345');
$GLOBALS['errors'] = array();
require __DIR__ . '/../overlay/plugins/chaos/referral.php';
chaos_referral_add_error();
check(count($GLOBALS['errors']) === 0, 'a known code: no error');
check(count($hooks['account.registered'] ?? array()) === 1, 'recorded once the account exists');
$fakeDb->inserted = array();
$hooks['account.registered'][0](array('name' => 'newbie', 'email' => 'n@example.com'));
check(count($fakeDb->inserted) === 1 && $fakeDb->inserted[0][1][0] === 9 && $fakeDb->inserted[0][1][3] === '198.51.100.7', 'pending link of the new account with its IP');
$_SERVER['SCRIPT_NAME'] = '/login.php';
$GLOBALS['errors'] = array();
require __DIR__ . '/../overlay/plugins/chaos/referral.php';
chaos_referral_add_error();
check(count($GLOBALS['errors']) === 0, 'other pages are left alone');

echo ($failed === 0 ? "ok" : "FAILED $failed"), " ($checks checks)\n";
exit($failed === 0 ? 0 : 1);
