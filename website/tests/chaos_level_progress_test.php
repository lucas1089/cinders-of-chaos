<?php
// php website/tests/chaos_level_progress_test.php : the experience bar of characterprofile.php ("Level 20 ... x% to 21",
// "Need n experience to reach level 21"). ZnoteX's level_to_experience() and the profile's six lines are copied below
// from the pinned ZnoteX (install_site.sh ZNOTEX_COMMIT); with CHAOS_ZNOTEX_DIR set to a checkout of it, the copies
// are compared with the real files. The curve must be the game server's: stock TFS Player::getExpForLevel,
// exp(L) = (50*l^3 - 150*l^2 + 400*l) / 3 with l = L - 1 (server *_core.lua expForLevel; no engine patch changes it).
// So level 20 starts at 98,800 and level 21 at 116,000. php-cli only; ZnoteX itself is not needed.
$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

// ZnoteX engine/function/general.php
const ZNOTEX_LEVEL_TO_EXPERIENCE = 'return 50/3*(pow($level, 3) - 6*pow($level, 2) + 17*$level - 12);';
function level_to_experience($level) {
	return 50/3*(pow($level, 3) - 6*pow($level, 2) + 17*$level - 12);
}

// ZnoteX characterprofile.php, with patches/znotex-chaos-level-progress.patch (the percentage rounded down: round(.., 2)
// showed 100% one experience short of level 101 and up)
const ZNOTEX_PROFILE_LINES = array(
	'$level_start_exp = (int)level_to_experience($level_raw);',
	'$level_next_exp = (int)level_to_experience($level_raw + 1);',
	'$level_exp_span = max(1, $level_next_exp - $level_start_exp);',
	'$level_exp_done = min($level_exp_span, max(0, $experience_raw - $level_start_exp));',
	'$level_needed = max(0, $level_next_exp - $experience_raw);',
);
function profile_bar(int $level_raw, int $experience_raw): array {
	$level_start_exp = (int)level_to_experience($level_raw);
	$level_next_exp = (int)level_to_experience($level_raw + 1);
	$level_exp_span = max(1, $level_next_exp - $level_start_exp);
	$level_exp_done = min($level_exp_span, max(0, $experience_raw - $level_start_exp));
	$level_percent = floor(($level_exp_done / $level_exp_span) * 10000) / 100;
	$level_needed = max(0, $level_next_exp - $experience_raw);
	return array($level_percent, $level_needed);
}

// the game server's curve (TFS Player::getExpForLevel)
function tfs_exp(int $level): int {
	$l = $level - 1;
	return intdiv(50 * $l * $l * $l - 150 * $l * $l + 400 * $l, 3);
}

const PATCHED_PERCENT = '$level_percent = floor(($level_exp_done / $level_exp_span) * 10000) / 100;';
$patch = (string)file_get_contents(__DIR__ . '/../patches/znotex-chaos-level-progress.patch');
check(strpos($patch, "+++ b/characterprofile.php") !== false, 'patch covers characterprofile.php');
check(strpos($patch, '+' . "\t\t\t\t\t\t" . PATCHED_PERCENT) !== false, 'patch adds the rounded-down percentage');
check(strpos($patch, '-' . "\t\t\t\t\t\t" . '$level_percent = round(($level_exp_done / $level_exp_span) * 100, 2);') !== false,
	'patch removes the rounded percentage');
check(strpos((string)file_get_contents(__FILE__), "\t" . PATCHED_PERCENT) !== false, 'test uses the patched line');

$dir = getenv('CHAOS_ZNOTEX_DIR');
if ($dir !== false && $dir !== '') {
	$general = (string)@file_get_contents($dir . '/engine/function/general.php');
	check(strpos($general, ZNOTEX_LEVEL_TO_EXPERIENCE) !== false, 'ZnoteX level_to_experience unchanged');
	$profile = (string)@file_get_contents($dir . '/characterprofile.php');
	foreach (ZNOTEX_PROFILE_LINES as $line) {
		check(strpos($profile, $line) !== false, "ZnoteX characterprofile.php has: $line");
	}
}

for ($lv = 1; $lv <= 2000; $lv++) {
	if ((int)level_to_experience($lv) !== tfs_exp($lv)) {
		check(false, "level $lv: ZnoteX " . (int)level_to_experience($lv) . ' != server ' . tfs_exp($lv));
		break;
	}
}
check(tfs_exp(1) === 0 && tfs_exp(2) === 100 && tfs_exp(8) === 4200 && tfs_exp(20) === 98800
	&& tfs_exp(21) === 116000 && tfs_exp(100) === 15694800, 'known table values');

foreach (array(1, 8, 20, 100) as $lv) {
	$start = tfs_exp($lv);
	$next = tfs_exp($lv + 1);
	$span = $next - $start;
	list($pct, $need) = profile_bar($lv, $start);
	check($pct == 0 && $need === $span, "level $lv at its own experience: 0%, need $span (got $pct%, $need)");
	list($pct, $need) = profile_bar($lv, $start + intdiv($span, 2));
	check($pct == 50 && $need === $span - intdiv($span, 2), "level $lv halfway: 50% (got $pct%, $need)");
	list($pct, $need) = profile_bar($lv, $next - 1);
	check($pct < 100 && $pct >= 99 && $need === 1, "level $lv one below the next level: <100%, need 1 (got $pct%, $need)");
}

// the reported row (level 20, 116,000): 116,000 is level 21's experience on the server's curve, so the row is a
// level-21 character stored as 20; the page is right to show 100% and need 0.
list($pct, $need) = profile_bar(20, 116000);
check($pct == 100 && $need === 0, "level 20 with 116000: 100%, need 0 (got $pct%, $need)");

echo $failed ? "$failed failed\n" : "chaos_level_progress_test: OK\n";
exit($failed ? 1 : 0);
