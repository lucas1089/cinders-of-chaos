<?php
// php website/tests/chaos_site_security_test.php : the site's web hardening (website/README.md "Web server"):
// config.local.php from setup/write_config.php (Secure cookie and HSTS for an https:// site, the Content-Security-Policy,
// reCAPTCHA from the environment, a random PayGol secret), the root .htaccess and special/.htaccess, the local router's
// deny list and install_site.sh keeping .git and the non-site files out of the web root. php-cli only, no database.
$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}
$root = dirname(__DIR__);

/** config.local.php for these settings, evaluated over ZnoteX's defaults. */
function written_config(array $env): array {
	$base = array('CHAOS_DB_USER' => 'u', 'CHAOS_DB_NAME' => 'n', 'CHAOS_DB_HOST' => '127.0.0.1', 'CHAOS_DB_PORT' => '1',
		'CHAOS_START_TOWNS' => '1');
	$cmd = '';
	foreach ($env + $base as $k => $v) {
		$cmd .= $k . '=' . escapeshellarg($v) . ' ';
	}
	$out = shell_exec('env -i PATH=' . escapeshellarg((string)getenv('PATH')) . ' ' . $cmd . escapeshellarg(PHP_BINARY) . ' '
		. escapeshellarg(dirname(__DIR__) . '/setup/write_config.php') . ' 2>/dev/null');
	$config = array('session' => array('cookie_secure' => null), 'security' => array('hsts' => false), 'paygol' => array('secretKey' => 'xxxx-xxxx-xxxx-xxxx', 'serviceID' => 86648),
		'use_captcha' => false, 'captcha_site_key' => 'Site key');
	eval('?>' . (string)$out);
	$config['__text'] = (string)$out;
	return $config;
}

// ---------------------------------------------------------------- https: Secure cookie, HSTS, CSP
$c = written_config(array('CHAOS_SITE_URL' => 'https://www.example.org'));
check($c['session']['cookie_secure'] === true, 'https: session cookie Secure');
check($c['security']['hsts'] === true, 'https: HSTS on');
$csp = (string)($c['security']['content_security_policy'] ?? '');
foreach (array("default-src 'self'", "script-src 'self' 'unsafe-inline'", "object-src 'none'", "base-uri 'self'", "frame-ancestors 'self'", "form-action 'self'") as $part) {
	check(strpos($csp, $part) !== false, "CSP has $part");
}
check(strpos($csp, 'unsafe-eval') === false && strpos($csp, 'google') === false, 'CSP: no eval, no Google without reCAPTCHA');
check(($c['security']['content_type_options'] ?? false) === true && ($c['security']['referrer_policy'] ?? '') === 'strict-origin-when-cross-origin', 'nosniff and Referrer-Policy');
// the stock payment callbacks: off, and a random PayGol secret every run
check(preg_match('/^[0-9a-f]{64}$/', (string)$c['paygol']['secretKey']) === 1, 'PayGol secret is 64 random hex digits');
check($c['paygol']['enabled'] === false && $c['pagseguro']['enabled'] === false && $c['paypal']['enabled'] === false, 'stock payments off');
check(written_config(array())['paygol']['secretKey'] !== $c['paygol']['secretKey'], 'a new PayGol secret on every run');
check($c['use_captcha'] === false, 'no reCAPTCHA without keys');

// ---------------------------------------------------------------- http (local): no Secure cookie, no HSTS
$c = written_config(array('CHAOS_SITE_URL' => 'http://127.0.0.1:8095'));
check($c['session']['cookie_secure'] === null && $c['security']['hsts'] === false, 'http: cookie and HSTS left to ZnoteX');

// ---------------------------------------------------------------- reCAPTCHA from the environment
$c = written_config(array('CHAOS_SITE_URL' => 'https://www.example.org', 'CHAOS_RECAPTCHA_SITE_KEY' => "site'key", 'CHAOS_RECAPTCHA_SECRET' => 'sec"ret'));
check($c['use_captcha'] === true && $c['captcha_site_key'] === "site'key" && $c['captcha_secret_key'] === 'sec"ret', 'reCAPTCHA keys written');
check(strpos((string)$c['security']['content_security_policy'], "script-src 'self' 'unsafe-inline' https://www.google.com https://www.gstatic.com") !== false, 'CSP allows reCAPTCHA');
check($c['captcha_use_curl'] === false, 'reCAPTCHA check keeps certificate checks');
check(written_config(array('CHAOS_RECAPTCHA_SITE_KEY' => 'only-one'))['use_captcha'] === false, 'one key alone: off');
check($c['chaos_register_limit']['per_ip'] === 3, 'register limit 3 per hour by default');

// ---------------------------------------------------------------- .htaccess (Apache 2.4)
$ht = (string)file_get_contents($root . '/overlay/.htaccess');
check(strpos($ht, 'Options -Indexes') !== false, 'no directory listings');
check(strpos($ht, 'RewriteRule ^(.*)$ /characterprofile.php?name=$1') !== false, "ZnoteX's character rule kept");
check(strpos($ht, 'Order ') === false && strpos($ht, 'Deny from') === false, 'Apache 2.4 syntax only');
if (preg_match('/RedirectMatch 404 "([^"]+)"/', $ht, $m)) {
	$re = '#' . str_replace('#', '\#', $m[1]) . '#';
	foreach (array('/.git/config', '/.git', '/SQL/znote_schema.sql', '/special/database2znoteaac.php', '/engine/backups/x.sql.gz', '/engine/cache/a.cache', '/tests/bootstrap.php', '/tools/x', '/docker/php.ini', '/install/index.php', '/vendor/autoload.php', '/Lua/TFS_10') as $u) {
		check(preg_match($re, $u) === 1, ".htaccess denies $u");
	}
	foreach (array('/index.php', '/guilds.php', '/engine/img/x.png', '/layouts/chaos/assets/css/x.css', '/updates/live/manifest.json', '/installer') as $u) {
		check(preg_match($re, $u) === 0, ".htaccess serves $u");
	}
} else {
	check(false, 'deny rule found');
}
if (preg_match('/<FilesMatch "([^"]+)">\s*Require all denied/', $ht, $m)) {
	foreach (array('composer.json', 'composer.lock', 'docker-compose.yml', 'Dockerfile', 'README.md', 'x.sql', 'x.bak', '.env', 'config.yml', 'config.local.php') as $f) {
		check(preg_match('#' . $m[1] . '#', $f) === 1, ".htaccess denies $f");
	}
	check(preg_match('#' . $m[1] . '#', 'index.php') === 0 && preg_match('#' . $m[1] . '#', 'manifest.json') === 0, '.htaccess serves pages and the update manifest');
}
check(trim((string)preg_replace('/^#.*$/m', '', (string)file_get_contents($root . '/overlay/special/.htaccess'))) === 'Require all denied', 'special/.htaccess: Require all denied');

// ---------------------------------------------------------------- the local router (php -S)
$router = (string)file_get_contents($root . '/setup/router.php');
if (preg_match("/if \\(preg_match\\('(#.+?#i)', \\\$uri\\)/", $router, $m)) {
	foreach (array('/.git/HEAD', '/special/database2znoteaac.php', '/engine/backups/a.sql.gz', '/SQL/znote_schema.sql', '/composer.phar', '/.env.example') as $u) {
		check(preg_match($m[1], $u) === 1, "router denies $u");
	}
} else {
	check(false, 'router rule found');
}

// ---------------------------------------------------------------- install_site.sh: .git and non-site files out of the web root
$sh = (string)file_get_contents($root . '/install_site.sh');
check(strpos($sh, 'CHAOS_SITE_GIT_DIR') !== false && strpos($sh, 'mv "$SITE/.git" "$ZGIT"') !== false, 'git data moved out of the web root');
foreach (array('tests', 'tools', 'docker', 'docker-compose.yml', 'Dockerfile', 'composer.phar') as $f) {
	check(preg_match('/^for f in .*\b' . preg_quote($f, '/') . '\b/ms', $sh) === 1, "install removes $f");
}
check(strpos($sh, 'find "$SITE/special" -mindepth 1 ! -name .htaccess') !== false, 'install empties special/');

echo $failed === 0 ? "chaos_site_security_test: OK\n" : "chaos_site_security_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
