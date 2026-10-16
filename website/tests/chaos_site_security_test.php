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

// ---------------------------------------------------------------- clean addresses (.htaccess, README "Web server")
// The rewrite rules run here over a fake web root, the way Apache 2.4 applies them in a .htaccess: the <FilesMatch>
// deny first (access check), then mod_rewrite (its fixup runs before mod_alias's), an internal rewrite starting the
// request over with the new address (THE_REQUEST stays what the browser sent), and RedirectMatch 404 on an address
// mod_rewrite left alone. Result: "301 <location>", "403", "404", or "run <file>[?query]" / "serve <file>".
function ht_blocks(string $ht): array {
	$blocks = array();
	$conds = array();
	foreach (preg_split('/\R/', $ht) as $line) {
		$line = trim($line);
		if (preg_match('/^RewriteCond\s+(\S+)\s+("[^"]*"|\S+)(?:\s+\[([^\]]*)\])?$/', $line, $m)) {
			$conds[] = array($m[1], trim($m[2], '"'));
		} elseif (preg_match('/^RewriteRule\s+("[^"]*"|\S+)\s+(\S+)(?:\s+\[([^\]]*)\])?$/', $line, $m)) {
			$blocks[] = array('conds' => $conds, 'pattern' => trim($m[1], '"'), 'target' => $m[2], 'flags' => explode(',', $m[3] ?? ''));
			$conds = array();
		}
	}
	return $blocks;
}
function ht_request(string $ht, array $fs, string $method, string $target): string {
	$the = $method . ' ' . $target . ' HTTP/1.1';
	[$path, $query] = array_pad(explode('?', $target, 2), 2, '');
	$path = rawurldecode($path);
	$deny = preg_match('/<FilesMatch "([^"]+)">\s*Require all denied/', $ht, $fm) ? '#' . $fm[1] . '#' : '#^$#';
	$notFound = preg_match('/RedirectMatch 404 "([^"]+)"\R(?:#.*\R)?RedirectMatch 404 "([^"]+)"/', $ht, $rm) ? array('#' . str_replace('#', '\#', $rm[1]) . '#', '#' . $rm[2] . '#') : array();
	$isFile = static function (string $p) use ($fs): bool { return in_array(ltrim($p, '/'), $fs['files'], true); };
	$isDir = static function (string $p) use ($fs): bool { return in_array(rtrim(ltrim($p, '/'), '/'), $fs['dirs'], true); };
	for ($round = 0; $round < 5; $round++) {
		if ($isFile($path) && preg_match($deny, basename($path))) {
			return '403';
		}
		$rewritten = null;
		foreach (ht_blocks($ht) as $b) {
			$rel = ltrim($path, '/');
			if (!preg_match('#' . $b['pattern'] . '#', $rel, $g)) {
				continue;
			}
			$ok = true;
			foreach ($b['conds'] as [$test, $pat]) {
				$val = strtr($test, array('%{REQUEST_METHOD}' => $method, '%{THE_REQUEST}' => $the, '%{REQUEST_FILENAME}' => $path, '$1' => $g[1] ?? ''));
				$neg = $pat[0] === '!';
				$pat = ltrim($pat, '!');
				$hit = $pat === '-f' ? $isFile($val) : ($pat === '-d' ? $isDir($val) : preg_match('#' . str_replace('#', '\#', $pat) . '#', $val) === 1);
				if ($hit === $neg) { $ok = false; break; }
			}
			if (!$ok) {
				continue;
			}
			if (in_array('B', $b['flags'], true)) {
				$g = array_map('rawurlencode', $g);
			}
			$to = preg_replace_callback('/\$(\d)/', static function ($m) use ($g) { return $g[(int)$m[1]] ?? ''; }, $b['target']);
			if ($to === '-') {
				break;
			}
			if (in_array('R=301', $b['flags'], true)) {
				return '301 ' . $to . ($query !== '' ? '?' . $query : '');
			}
			[$to, $q2] = array_pad(explode('?', $to, 2), 2, '');
			$rewritten = array($to, $q2 !== '' ? $q2 : $query, in_array('END', $b['flags'], true));
			break;
		}
		if ($rewritten === null) {
			foreach ($notFound as $re) {
				if (preg_match($re, $path)) {
					return '404';
				}
			}
			if ($isFile($path)) {
				return (substr($path, -4) === '.php' ? 'run ' : 'serve ') . ltrim($path, '/') . ($query !== '' ? '?' . $query : '');
			}
			return $isDir($path) ? 'dir' : '404';
		}
		[$path, $query, $end] = $rewritten;
		if ($end) { // [END]: no more rewriting, only the access and alias checks of the new address
			if ($isFile($path) && preg_match($deny, basename($path))) {
				return '403';
			}
			foreach ($notFound as $re) {
				if (preg_match($re, $path)) {
					return '404';
				}
			}
			return 'run ' . ltrim($path, '/') . ($query !== '' ? '?' . $query : '');
		}
	}
	return 'loop';
}
$fs = array(
	'files' => array('index.php', 'highscores.php', 'page.php', 'characterprofile.php', 'register.php', 'guilds.php', 'chaos_client_api.php',
		'chaos_pay_webhook.php', 'chaos_outfit.php', 'config.local.php', '.env.php', '.env', '.git/config', 'tests/x.php', 'special/x.php', 'install/index.php',
		'SQL/a.sql', 'engine/backups/x.php', 'updates/live/manifest.json', 'updates/x.php', 'admin/index.php', 'layouts/chaos/a.css'),
	'dirs' => array('.git', 'tests', 'special', 'install', 'SQL', 'engine', 'engine/backups', 'updates', 'updates/live', 'admin', 'layouts', 'layouts/chaos'),
);
$cases = array(
	// the clean address runs the page, the query kept
	array('GET', '/highscores', 'run highscores.php'),
	array('GET', '/highscores?list=1&page=2', 'run highscores.php?list=1&page=2'),
	array('GET', '/characterprofile?name=Ash%20Walker', 'run characterprofile.php?name=Ash%20Walker'),
	array('GET', '/page?plugin=chaos&p=wiki', 'run page.php?plugin=chaos&p=wiki'),
	array('POST', '/register', 'run register.php'),
	// a GET / HEAD of the .php address: 301 to the clean one, query kept; never a POST
	array('GET', '/highscores.php', '301 /highscores'),
	array('HEAD', '/highscores.php?list=1', '301 /highscores?list=1'),
	array('GET', '/page.php?plugin=chaos&p=wiki', '301 /page?plugin=chaos&p=wiki'),
	array('GET', '/index.php', '301 /'),
	array('GET', '/index.php?x=1', '301 /?x=1'),
	array('POST', '/register.php', 'run register.php'),
	array('POST', '/page.php?plugin=chaos&p=coins', 'run page.php?plugin=chaos&p=coins'),
	array('PUT', '/highscores.php', 'run highscores.php'),
	// the machine endpoints keep their .php address
	array('GET', '/chaos_client_api.php', 'run chaos_client_api.php'),
	array('POST', '/chaos_client_api.php', 'run chaos_client_api.php'),
	array('GET', '/chaos_pay_webhook.php?psp=paypal', 'run chaos_pay_webhook.php?psp=paypal'),
	array('POST', '/chaos_pay_webhook.php?psp=mercadopago', 'run chaos_pay_webhook.php?psp=mercadopago'),
	array('GET', '/chaos_outfit.php?id=128', 'run chaos_outfit.php?id=128'),
	array('GET', '/updates/live/manifest.json', 'serve updates/live/manifest.json'),
	array('GET', '/admin/index.php', 'run admin/index.php'),
	array('GET', '/layouts/chaos/a.css', 'serve layouts/chaos/a.css'),
	// any other path is a character name (ZnoteX's rule)
	array('GET', '/Ash%20Walker', 'run characterprofile.php?name=Ash%20Walker'),
	array('GET', '/Highscores', 'run characterprofile.php?name=Highscores'),
	array('GET', '/nosuch.php', 'run characterprofile.php?name=nosuch.php'),
	// denied stays denied, also through the new rules
	array('GET', '/config.local.php', '403'),
	array('GET', '/config.local', 'run characterprofile.php?name=config.local'),
	array('GET', '/.env.php', '404'),
	array('GET', '/.env', '403'),
	array('GET', '/.git/config', '404'),
	array('GET', '/tests/x.php', '404'),
	array('GET', '/tests', '404'),
	array('GET', '/special/x.php', '404'),
	array('GET', '/install/index.php', '404'),
	array('GET', '/install', '404'),
	array('GET', '/engine/backups/x.php', '404'),
	array('GET', '/SQL/a.sql', '403'),
	array('GET', '/updates/x.php', 'run updates/x.php'), // the folder's own .htaccess denies it (php off, Require all denied)
);
foreach ($cases as [$method, $target, $want]) {
	$got = ht_request($ht, $fs, $method, $target);
	check($got === $want, ".htaccess $method $target: $want (got $got)");
}
check(preg_match('/RewriteRule "\^\(\[A-Za-z0-9_-\]\+\)\$" \/\$1\.php \[END\]\R(?:.*\R)*?RewriteRule \^\(\.\*\)\$ \/characterprofile\.php\?name=\$1 \[B,END\]/', $ht) === 1,
	'the page rule comes before the character rule');
check(substr_count($ht, 'RewriteCond %{REQUEST_METHOD} ^(GET|HEAD)$') === 2 && substr_count($ht, '[R=301,L]') === 2, 'only GET and HEAD are redirected');
check(strpos((string)file_get_contents($root . '/overlay/updates/.htaccess'), 'RewriteEngine Off') !== false, 'updates/: no rewriting at all');

// ---------------------------------------------------------------- the nginx block of the README: the same addresses
$readme = (string)file_get_contents($root . '/README.md');
check(preg_match('/^map "\$request_method:\$request_uri" \$chaos_clean_url \{\R\s+default "";\R\s+"~([^"]+)" "([^"]+)";\R\s+"~([^"]+)" "([^"]+)";\R\}/m', $readme, $nm) === 1, 'nginx: the clean address map');
$ngx = static function (string $method, string $uri) use ($nm): string {
	foreach (array(array($nm[1], $nm[2]), array($nm[3], $nm[4])) as [$re, $val]) {
		if (preg_match('#' . $re . '#', $method . ':' . $uri, $g)) {
			return (string)preg_replace_callback('/\$(\w+)/', static function ($m) use ($g) { return $g[$m[1]] ?? ''; }, $val);
		}
	}
	return '';
};
if (!empty($nm)) {
	foreach (array(array('GET', '/highscores.php', '/highscores'), array('HEAD', '/highscores.php?list=1&x=2', '/highscores?list=1&x=2'),
		array('GET', '/index.php', '/'), array('GET', '/index.php?x=1', '/?x=1'), array('GET', '/page.php?plugin=chaos&p=wiki', '/page?plugin=chaos&p=wiki'),
		array('POST', '/register.php', ''), array('PUT', '/highscores.php', ''), array('GET', '/chaos_client_api.php', ''),
		array('GET', '/chaos_pay_webhook.php?psp=paypal', ''), array('GET', '/chaos_outfit.php?id=1', ''), array('GET', '/tests/x.php', ''),
		array('GET', '/updates/x.php', ''), array('GET', '/admin/index.php', ''), array('GET', '/.env.php', ''), array('GET', '/config.local.php', ''),
		array('GET', '/highscores', '')) as [$method, $uri, $want]) {
		check($ngx($method, $uri) === $want, "nginx: $method $uri -> " . ($want === '' ? 'no redirect' : $want));
	}
}
check(strpos($readme, "    set \$chaos_301 \$chaos_clean_url;\n    if (!-f \$request_filename) { set \$chaos_301 \"\"; }\n    if (\$chaos_301) { return 301 \$chaos_301; }") !== false, 'nginx: the 301 only for an existing page');
check(strpos($readme, "        try_files \$uri \$uri/ @page;") !== false
	&& strpos($readme, "        if (-f \$request_filename.php) { rewrite \"^/([A-Za-z0-9_-]+)\$\" /\$1.php last; }\n        rewrite ^/(.*)\$ /characterprofile.php?name=\$1 last;") !== false,
	'nginx: /page runs page.php, then the character rule');
check(preg_match('/^\s*try_files[^;\n]*\$uri\.php/m', $readme) === 0, 'nginx: never try_files $uri.php (it would send the PHP source)');
check(strpos($readme, '    set $chaos_301') < strpos($readme, '    location ~ /\. { deny all; }'), 'nginx: the redirect before the locations');

// ---------------------------------------------------------------- our links: the clean form
require_once $root . '/overlay/plugins/chaos/lib.php';
foreach (array('highscores.php?x=1' => 'highscores?x=1', '/page.php?p=rules' => '/page?p=rules', 'index.php' => './', '/index.php' => '/',
	'page.php#records' => 'page#records', 'admin/index.php' => 'admin/index.php', 'https://example.org/a.php' => 'https://example.org/a.php',
	'chaos_client_api.php' => 'chaos_client_api.php', '/chaos_pay_webhook.php?psp=paypal' => '/chaos_pay_webhook.php?psp=paypal',
	'chaos_outfit.php?id=1' => 'chaos_outfit.php?id=1', 'page?p=rules' => 'page?p=rules') as $in => $want) {
	check(chaos_clean_url($in) === $want, "chaos_clean_url($in) = $want");
}
$links = array();
foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root . '/overlay', FilesystemIterator::SKIP_DOTS)) as $f) {
	if (preg_match('/\.(php|js)$/', $f->getFilename())) {
		$src = (string)file_get_contents($f->getPathname());
		// href / action / Location / site URL to a top-level .php page (the machine endpoints excepted)
		if (preg_match_all('~(?:href=|action=|Location: |\$site \. \'/|\$base \. \'/|siteUrl \. \'/|rtrim\(\$siteUrl, \'/\'\) \. \'/)["\']?/?(?!chaos_client_api|chaos_pay_webhook|chaos_outfit)[a-z_]+\.php\b~', $src, $lm)) {
			foreach ($lm[0] as $l) {
				$links[] = substr($f->getPathname(), strlen($root) + 1) . ': ' . $l;
			}
		}
		if (preg_match_all('~\bpage\.php\?~', $src, $lm)) {
			$links[] = substr($f->getPathname(), strlen($root) + 1) . ': page.php?';
		}
	}
}
check($links === array(), 'our links use the clean form: ' . implode(' | ', array_slice($links, 0, 6)));
$setup = (string)file_get_contents($root . '/setup/chaos_setup.php');
check(preg_match("/\\\$menu\('[^']+', '[a-z_]+\.php/", $setup) === 0, 'setup: menu entries in the clean form');
check(strpos($setup, "chaos_clean_url((string)\$row['url'])") !== false, 'setup: old .php menu entries made clean');
check(strpos((string)file_get_contents($root . '/setup/rules.bbcode'), '[url=/page.php') === false, 'the Rules page links the clean form');
$menuPatch = (string)file_get_contents($root . '/patches/znotex-chaos-clean-urls.patch');
check(strpos($menuPatch, "+++ b/engine/function/menus.php") !== false && strpos($menuPatch, "+		\$page .= '.php';") !== false, "the patch: ZnoteX's menu checks read a clean address");
// a page form that posts never posts to an address that answers 301 (only GET / HEAD of a .php address do)
foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root . '/overlay', FilesystemIterator::SKIP_DOTS)) as $f) {
	if (substr($f->getFilename(), -4) === '.php' && preg_match_all('~<form[^>]*method="post"[^>]*>~i', (string)file_get_contents($f->getPathname()), $fm)) {
		foreach ($fm[0] as $form) {
			check(preg_match('~action="/?[a-z_]+\.php~', $form) === 0, 'POST form to a clean address: ' . $form);
		}
	}
}

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
