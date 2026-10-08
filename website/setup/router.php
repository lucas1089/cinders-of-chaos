<?php
/**
 * Router for PHP's built-in web server (local testing only), standing in for ZnoteX's .htaccess files:
 *   php -S 127.0.0.1:8095 -t <site> <repo>/website/setup/router.php
 * Existing files are served as they are; internals are refused; any other path is a character name.
 */
$uri  = rawurldecode((string)parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH));
$root = $_SERVER['DOCUMENT_ROOT'];

// never serve repository internals, schemas, caches, plugin code or the installer's leftovers
if (preg_match('#(^|/)(\.[^/]*|SQL|Lua|tests|docker|tools|cache|node_modules|vendor|composer\.[a-z]+|phpunit\.xml|phpstan\.neon|Dockerfile|docker-compose\.yml|config\.local\.php|install)(/|$)|\.(sql|md|lock|dist|log|json|bbcode)$#i', $uri)
	|| (preg_match('#^/plugins/#', $uri) && !preg_match('#^/plugins/[a-z0-9_-]+/assets/#', $uri))) {
	http_response_code(404);
	exit('not found');
}
if ($uri === '/' || is_file($root . $uri) || is_dir($root . $uri)) {
	return false; // the built-in server handles it (index.php, static files, other .php scripts)
}
$_GET['name'] = ltrim($uri, '/');
chdir($root);
require $root . '/characterprofile.php';
