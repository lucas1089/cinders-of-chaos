<?php
// php website/tests/chaos_launch_test.php : the launch moment on the website (O463): overlay/plugins/chaos/launch_lib.php (the
// one value of the game server's launch_config.lua, "open" or a date) and what follows it in lib.php chaos_seasons(): while the
// launch is open Season 1 has no date and is "soon"; with an example launch it has the dates; a season started by hand runs
// lengthDays. A missing or broken value reads as open. Real server/data/scripts/chaos/season_config.lua, a fake database.
// php-cli only. Exit status 0 when every check passes.

$tmp = sys_get_temp_dir() . '/chaos_launch_test_' . getmypid();
mkdir($tmp . '/scripts/chaos', 0777, true);
$config = array('chaos' => array('server_data' => $tmp));
$GLOBALS['config'] = $config;

class ChaosFakeDb {
	public $overrides = array();
	public function fetchOne(string $sql, array $params = array()) { return array('n' => 1); }
	public function fetchAll(string $sql, array $params = array()) {
		return strpos($sql, '`server_config`') !== false ? $this->overrides : array();
	}
}
$fakeDb = new ChaosFakeDb();
function db() { global $fakeDb; return $fakeDb; }

require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/launch_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$repoCfg = __DIR__ . '/../../server/data/scripts/chaos/';
$shipped = (string)file_get_contents($repoCfg . 'launch_config.lua');
check(preg_match('/^\s*launch\s*=\s*"open"/m', $shipped) === 1, 'the shipped launch is open (owner, 2026-11-10)');
copy($repoCfg . 'season_config.lua', $tmp . '/scripts/chaos/season_config.lua');
$setLaunch = static function (string $text) use ($tmp): void { file_put_contents($tmp . '/scripts/chaos/launch_config.lua', $text); };

// ---- launch_lib: the reader and the texts
$open = chaos_launch_config('return {launch = "open", offsets = {}}');
check($open['open'] === true && $open['launch'] === null && $open['raw'] === 'open', 'open');
$set = chaos_launch_config("return {\n\tlaunch = \"2031-03-14 15:00\", -- launch = \"open\"\n}");
check($set['open'] === false && $set['launch'] !== null && $set['launch']->format('Y-m-d H:i') === '2031-03-14 15:00', 'a date, a commented "open" does not count');
foreach (array('', 'return {}', 'return {launch = "soon"}', 'return {launch = "2031-02-30 15:00"}', 'return {launch = "2031-03-14"}', 'return {launch = "2031-13-01 15:00"}') as $bad) {
	check(chaos_launch_config($bad)['open'] === true, 'a missing or broken value is open: ' . $bad);
}
check(chaos_launch_text('en', $open) === 'Coming soon' && chaos_launch_text('pt-BR', $open) === 'Em breve', 'open: Coming soon / Em breve');
check(chaos_launch_text('en', $open, 28) === 'Coming soon', 'open: a derived date is soon too');
check(chaos_launch_text('en', $set) === '14 Mar 2031, 15:00' && chaos_launch_text('pt-BR', $set) === '14/03/2031 15:00', 'a date, both languages');
check(chaos_launch_text('pt-BR', $set, 0, true, true) === '14/03/2031 15:00 (UTC-3)', 'a date with the zone');
check(chaos_launch_text('pt-BR', $set, 28, false) === '11/04/2031' && chaos_launch_text('en', $set, -2, false) === '12 Mar 2031', 'derived dates: +28 and -2 days, no time');
file_put_contents($tmp . '/scripts/chaos/launch_config.lua', 'return {launch = "2031-03-14 15:00"}');
check(chaos_launch_text('en') === '14 Mar 2031, 15:00', 'no config argument reads the server file');
unlink($tmp . '/scripts/chaos/launch_config.lua');
check(chaos_launch_text('en') === 'Coming soon', 'no server file reads as open');

// ---- chaos_seasons(): the launch is open, no season date, "soon"
$setLaunch('return {launch = "open"}');
$s = chaos_seasons();
check(isset($s[1]) && $s[1]['start'] === 0 && $s[1]['finish'] === 0 && $s[1]['soon'] === true && $s[1]['length'] === 91, 'open: Season 1 has no dates, is soon, and keeps its length');
check($s[1]['name'] === 'Season of Ash' && $s[1]['modifier'] === 'Ashfall', 'open: the rest of the season is read as before');
// a season started by hand (/season start writes chaos_season_1_start): it runs lengthDays
$fakeDb->overrides = array(array('config' => 'chaos_season_1_start', 'value' => '1800000000'));
$s = chaos_seasons();
check($s[1]['start'] === 1800000000 && $s[1]['finish'] === 1800000000 + 91 * 86400 && $s[1]['soon'] === false, 'open: a season started by hand runs 91 days');
$fakeDb->overrides = array();

// ---- with an example launch: the dates come back, at the launch hour
$setLaunch('return {launch = "2031-03-14 15:00"}');
$s = chaos_seasons();
$a = (new DateTimeImmutable('2031-03-14T15:00:00-03:00'))->getTimestamp();
$b = (new DateTimeImmutable('2031-06-13T15:00:00-03:00'))->getTimestamp();
check($s[1]['start'] === $a && $s[1]['finish'] === $b && $s[1]['soon'] === false, 'set: Season 1 starts with the launch and ends 91 days later');
$setLaunch('return {launch = "2031-03-14 18:00"}');
$s = chaos_seasons();
check($s[1]['start'] === (new DateTimeImmutable('2031-03-14T18:00:00-03:00'))->getTimestamp(), 'set: the launch hour is the season hour');
// a broken value reads as open: no season date is invented
$setLaunch('return {launch = "soon"}');
$s = chaos_seasons();
check($s[1]['start'] === 0 && $s[1]['soon'] === true, 'a broken launch value: Season 1 is soon, no date');

foreach (glob($tmp . '/scripts/chaos/*') as $f) { unlink($f); }
rmdir($tmp . '/scripts/chaos');
rmdir($tmp . '/scripts');
rmdir($tmp);
echo $failed ? "chaos_launch_test: $failed of $checks checks failed\n" : "chaos_launch_test: $checks checks OK\n";
exit($failed ? 1 : 0);
