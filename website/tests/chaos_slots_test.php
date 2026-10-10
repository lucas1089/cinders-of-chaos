<?php
// php website/tests/chaos_slots_test.php : character slots of overlay/plugins/chaos/lib.php (php-cli only, no ZnoteX,
// a fake database). Reads the real server/data/scripts/chaos/pact_config.lua. Exit status 0 when every check passes.

$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));

// the ZnoteX db() helper, faked: the extras table exists; rows per account
class ChaosFakeDb {
	public $extras = array();
	public function fetchOne(string $sql, array $params = array()) {
		return array('n' => 1);
	}
	public function fetchAll(string $sql, array $params = array()) {
		$out = array();
		foreach ($this->extras[(int)($params[0] ?? 0)] ?? array() as $key => $amount) {
			$out[] = array('extra_key' => $key, 'amount' => $amount);
		}
		return $out;
	}
}
$fakeDb = new ChaosFakeDb();
function db() {
	global $fakeDb;
	return $fakeDb;
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

// pact_config.lua `characters` (the same numbers as limits.charSlots, checked by server/tests/pact_test.lua)
$cfg = chaos_character_slot_config();
$text = file_get_contents(__DIR__ . '/../../server/data/scripts/chaos/pact_config.lua');
preg_match('/characters\s*=\s*\{\s*free\s*=\s*(\d+),\s*maxExtra\s*=\s*(\d+)/', $text, $m);
check(isset($m[1]) && $cfg['free'] === (int)$m[1] && $cfg['maxExtra'] === (int)$m[2], 'free / maxExtra read from pact_config.lua');

// the arithmetic
check(chaos_character_limit_of(array('free' => 5, 'maxExtra' => 10), 0, 0) === 5, 'free only');
check(chaos_character_limit_of(array('free' => 5, 'maxExtra' => 10), 3, 0) === 8, 'bought slots');
check(chaos_character_limit_of(array('free' => 5, 'maxExtra' => 10), 99, 0) === 15, 'bought slots capped');
check(chaos_character_limit_of(array('free' => 5, 'maxExtra' => 10), 2, 4) === 11, 'legacy slots on top, not capped');
check(chaos_character_limit_of(array('free' => 5, 'maxExtra' => 10), -2, -1) === 5, 'negative amounts ignored');

// per account, through the (fake) database
$fakeDb->extras = array(7 => array('charSlots' => 2), 8 => array('charSlots' => 1, 'charSlotsLegacy' => 3));
check(chaos_character_limit(0) === $cfg['free'], 'no account: free');
check(chaos_character_limit(6) === $cfg['free'], 'nothing bought');
check(chaos_character_limit(7) === $cfg['free'] + 2, 'two slots bought');
check(chaos_character_limit(8) === $cfg['free'] + 4, 'bought + legacy');

// unreadable server data: the defaults
$config['chaos']['server_data'] = '/nonexistent';
check(chaos_character_slot_config() === array('free' => 5, 'maxExtra' => 10), 'defaults without the server files');

echo ($failed === 0 ? "ok" : "FAILED $failed"), " ($checks checks)\n";
exit($failed === 0 ? 0 : 1);
