<?php
// php website/tests/chaos_password_test.php : unit tests of overlay/engine/function/chaos_password.php (php-cli only,
// no ZnoteX, no database). Exit status 0 when every check passes.
require __DIR__ . '/../overlay/engine/function/chaos_password.php';

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

// PBKDF2-HMAC-SHA256 itself (RFC 7914 section 11 test vector), the primitive the engine computes with Crypto++
check(bin2hex(hash_pbkdf2('sha256', 'passwd', 'salt', 1, 64, true)) ===
	'55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
	'RFC 7914 PBKDF2-HMAC-SHA256 vector');

// the format
$h = chaos_password_hash('secret pass', 1000);
check((bool)preg_match('#^pbkdf2-sha256\$1000\$[A-Za-z0-9+/]{22}==\$[A-Za-z0-9+/]{43}=$#', $h), "format: $h");
check(strlen(chaos_password_hash('x')) <= 255, 'fits VARCHAR(255)');
check(strlen(chaos_password_hash('x')) === 90, 'default length 90 (120000 iterations)');
check(chaos_password_hash('same', 1000) !== chaos_password_hash('same', 1000), 'random salt: two hashes of one password differ');
$p = chaos_password_parse($h);
check($p !== null && $p['iterations'] === 1000 && strlen($p['salt']) === 16 && strlen($p['key']) === 32, 'parse');

// a fixed hash (salt 16 x 0x01) computed independently of chaos_password_hash
$fixed = 'pbkdf2-sha256$1000$' . base64_encode(str_repeat("\x01", 16)) . '$'
	. base64_encode(hash_pbkdf2('sha256', 'hunter22', str_repeat("\x01", 16), 1000, 32, true));
check(chaos_password_verify('hunter22', $fixed), 'verify fixed hash');
check(!chaos_password_verify('hunter23', $fixed), 'wrong password refused');
check(!chaos_password_verify('', $fixed), 'empty password refused');

// verify / rehash decisions
check(chaos_password_verify('secret pass', $h), 'verify own hash');
check(!chaos_password_verify('Secret pass', $h), 'case matters');
check(chaos_password_needs_rehash($h), 'fewer iterations than configured: rehash');
check(!chaos_password_needs_rehash(chaos_password_hash('a')), 'configured iterations: no rehash');

// legacy SHA-1 (stock TFS / ZnoteX / MySQL SHA1())
$legacy = sha1('test');
check(chaos_password_is_legacy_sha1($legacy), 'legacy detected');
check(chaos_password_verify('test', $legacy), 'legacy verify');
check(chaos_password_verify('test', strtoupper($legacy)), 'legacy upper-case hex verify');
check(!chaos_password_verify('test2', $legacy), 'legacy wrong password refused');
check(chaos_password_needs_rehash($legacy), 'legacy needs rehash');
check(chaos_password_verify('pw', sha1('salt' . 'pw'), 'salt'), 'TFS 0.3 salted legacy verify');

// passwords with characters ZnoteX's array_sanitize would have changed are hashed as typed
$special = "a<b>&'\"c";
check(chaos_password_verify($special, chaos_password_hash($special, 1000)), 'special characters');
check(!chaos_password_verify(htmlentities($special), chaos_password_hash($special, 1000)), 'entity-encoded form is a different password');

// malformed values never verify
foreach (array('', 'x', 'pbkdf2-sha256$1000$$', 'pbkdf2-sha256$abc$AAAA$AAAA', 'pbkdf2-sha1$1000$' . base64_encode('0123456789abcdef') . '$' . base64_encode(str_repeat('k', 32)),
	'pbkdf2-sha256$1000$***$' . base64_encode(str_repeat('k', 32)), 'pbkdf2-sha256$99999999999$AAAA$AAAA',
	'pbkdf2-sha256$1000$' . base64_encode('0123456789abcdef') . '$' . base64_encode('short'), str_repeat('g', 40)) as $bad) {
	check(chaos_password_parse($bad) === null || !chaos_password_verify('x', $bad), "malformed refused: $bad");
	check(!chaos_password_verify('', $bad), "malformed refused (empty password): $bad");
}

// the engine's own output (src/passwordhash.cpp, Crypto++ base64 with padding) verifies here: this hash was written by
// the test server (patch 0014) when the legacy SHA-1 account logged into the game with the password "legacy-pass"
$engine = 'pbkdf2-sha256$120000$XUwEYbwk7QJx7GIxpsJVaQ==$exa6rcA09Efmr8IcOFx13LUOS8sXLaAiT4aJIM/m0zU=';
check(chaos_password_verify('legacy-pass', $engine), 'engine-written hash verifies');
check(!chaos_password_verify('legacy-pas', $engine), 'engine-written hash, wrong password refused');
check(!chaos_password_needs_rehash($engine), 'engine-written hash at the default iterations: no rehash');

// timing: an unknown account (dummy) costs about what a real check costs
$real = chaos_password_hash('timing-pw');
$t0 = microtime(true);
chaos_password_verify('timing-pw', $real);
$t1 = microtime(true);
chaos_password_dummy('timing-pw');
$t2 = microtime(true);
chaos_password_verify('wrong', $legacy);
$t3 = microtime(true);
$ratio = ($t2 - $t1) / max(1e-6, $t1 - $t0);
$ratioLegacy = ($t3 - $t2) / max(1e-6, $t1 - $t0);
check($ratio > 0.33 && $ratio < 3.0, sprintf('dummy %.1f ms vs real %.1f ms', ($t2 - $t1) * 1000, ($t1 - $t0) * 1000));
check($ratioLegacy > 0.33 && $ratioLegacy < 3.0, sprintf('wrong legacy %.1f ms vs real %.1f ms', ($t3 - $t2) * 1000, ($t1 - $t0) * 1000));
printf("real check %.1f ms, dummy %.1f ms, wrong legacy %.1f ms (%d iterations)\n", ($t1 - $t0) * 1000, ($t2 - $t1) * 1000, ($t3 - $t2) * 1000, chaos_password_iterations());

echo ($failed === 0 ? "ok" : "FAILED $failed"), " ($checks checks)\n";
exit($failed === 0 ? 0 : 1);
