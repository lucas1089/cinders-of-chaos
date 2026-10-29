<?php
/**
 * Router for PHP's built-in web server (local testing only), standing in for ZnoteX's .htaccess files:
 *   php -S 127.0.0.1:8095 -t <site> <repo>/website/setup/router.php
 * Existing files are served as they are; internals are refused; /page runs page.php (a GET of /page.php is sent
 * there); any other path is a character name.
 */
$uri  = rawurldecode((string)parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH));
$root = $_SERVER['DOCUMENT_ROOT'];

// never serve repository internals, schemas, caches, plugin code or the installer's leftovers
if (preg_match('#(^|/)(\.[^/]*|SQL|Lua|tests|docker|tools|special|backups|cache|node_modules|vendor|composer\.[a-z]+|phpunit\.xml|phpstan\.neon|Dockerfile|docker-compose\.yml|config\.local\.php|install)(/|$)|\.(sql|md|lock|dist|log|json|bbcode|example|bak|yml|yaml|env|phar)$#i', $uri)
	|| (preg_match('#^/plugins/#', $uri) && !preg_match('#^/plugins/[a-z0-9_-]+/assets/#', $uri))) {
	http_response_code(404);
	exit('not found');
}
// clean addresses, as the .htaccess: a GET / HEAD of /page.php goes to /page (301, query kept; never the machine
// endpoints), and /page runs page.php
$method = (string)($_SERVER['REQUEST_METHOD'] ?? 'GET');
if (($method === 'GET' || $method === 'HEAD') && preg_match('#^/([A-Za-z0-9_-]+)\.php$#', $uri, $m)
	&& !in_array($m[1], array('chaos_client_api', 'chaos_pay_webhook', 'chaos_outfit', 'chaos_launcher_feed'), true) && is_file($root . $uri)) {
	$q = (string)parse_url($_SERVER['REQUEST_URI'], PHP_URL_QUERY);
	header('Location: ' . ($m[1] === 'index' ? '/' : '/' . $m[1]) . ($q !== '' ? '?' . $q : ''), true, 301);
	exit;
}
if (preg_match('#^/([A-Za-z0-9_-]+)$#', $uri, $m) && !is_dir($root . $uri) && is_file($root . '/' . $m[1] . '.php')) {
	$_SERVER['SCRIPT_NAME'] = $_SERVER['PHP_SELF'] = '/' . $m[1] . '.php';
	$_SERVER['SCRIPT_FILENAME'] = $root . '/' . $m[1] . '.php';
	unset($m, $method);
	chdir($root);
	require $_SERVER['SCRIPT_FILENAME'];
	return true;
}
if ($uri === '/' || is_file($root . $uri) || is_dir($root . $uri)) {
	return false; // the built-in server handles it (index.php, static files, other .php scripts)
}
$_GET['name'] = ltrim($uri, '/');
chdir($root);
require $root . '/characterprofile.php';
