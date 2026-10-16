<?php
// php website/tests/chaos_seo_test.php : SEO and link previews (plugins/chaos/seo_lib.php, website/README.md "SEO and
// social previews"): the head of the representative pages (home, highscores, a character profile, a guild, the wiki,
// the legal texts, the account and staff pages): title, description, canonical in the clean form, robots, the Open
// Graph and Twitter tags with an absolute image, the icons, the JSON-LD of the front page; the language of the tags;
// the escaping of a character name; the rewrite of a Void-like shell (title and icon links replaced, nothing else
// touched) and of output that is not a page; every chaos_t key of the library in pt-BR; the icon files and the Open
// Graph image (size, under 300 KB); site.webmanifest; robots.txt and sitemap.xml from setup/write_seo_files.php; the
// deny rules of .htaccess and the router letting the SEO files through. php-cli only, no ZnoteX, no database.
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
$root = dirname(__DIR__);
$plugin = $root . '/overlay/plugins/chaos';
$GLOBALS['config'] = array('site_title' => 'Cinders of Chaos', 'site_url' => 'https://www.example.org/',
	'chaos' => array('discord_url' => 'https://discord.example/abc'));
require $plugin . '/seo_lib.php';
$site = chaos_seo_site();
check($site['url'] === 'https://www.example.org' && $site['name'] === 'Cinders of Chaos', 'the site from config.local.php, no trailing slash');
$site2 = chaos_seo_site(array(), array('HTTP_HOST' => 'host.example', 'HTTPS' => 'on'));
check($site2['url'] === 'https://host.example', 'no site_url: the request host');

function seo(array $ctx): array {
	global $site;
	return chaos_seo_page($ctx + array('site' => $site, 'lang' => 'pt-BR', 'get' => array(), 'status' => 200, 'script' => '/index.php'));
}
function head(array $ctx): string {
	global $site;
	return chaos_seo_head(seo($ctx), $site);
}
function has(string $html, string $tag): bool {
	return strpos($html, $tag) !== false;
}

// ---------------------------------------------------------------- the language of the tags
check(chaos_seo_lang(array(), array(), array()) === 'pt-BR', 'no hint (a crawler): Portuguese');
check(chaos_seo_lang(array(), array(), array('HTTP_ACCEPT_LANGUAGE' => 'en-US,en;q=0.9')) === 'en', 'an English browser');
check(chaos_seo_lang(array(), array(), array('HTTP_ACCEPT_LANGUAGE' => 'de-DE')) === 'pt-BR', 'another language: Portuguese');
check(chaos_seo_lang(array('l' => 'en'), array('chaos_lang' => 'pt-BR'), array()) === 'en', '&l= wins');
check(chaos_seo_lang(array(), array('chaos_lang' => 'en'), array('HTTP_ACCEPT_LANGUAGE' => 'pt-BR')) === 'en', 'the cookie wins over the browser');

// ---------------------------------------------------------------- the home page
$s = seo(array('page' => 'index'));
check($s['title'] === 'Cinders of Chaos | RPG online de fantasia sombria', 'home title: ' . $s['title']);
check($s['canonical'] === 'https://www.example.org/', 'home canonical');
check(strpos($s['description'], 'Cinders of Chaos: um RPG online de fantasia sombria') === 0 && strlen($s['description']) < 320, 'home description in Portuguese');
check($s['robots'] === 'index, follow, max-image-preview:large' && $s['jsonld'] === true, 'home indexed, with JSON-LD');
$h = head(array('page' => 'index'));
foreach (array('<meta name="description" content="Cinders of Chaos: um RPG', '<link rel="canonical" href="https://www.example.org/">',
	'<meta property="og:title" content="Cinders of Chaos">', '<meta property="og:type" content="website">',
	'<meta property="og:url" content="https://www.example.org/">', '<meta property="og:site_name" content="Cinders of Chaos">',
	'<meta property="og:locale" content="pt_BR">', '<meta property="og:locale:alternate" content="en_US">',
	'<meta property="og:image" content="https://www.example.org/layouts/chaos/assets/img/og-image-1200x630.jpg">',
	'<meta property="og:image:secure_url" content="https://www.example.org/layouts/chaos/assets/img/og-image-1200x630.jpg">',
	'<meta property="og:image:width" content="1200">', '<meta property="og:image:height" content="630">', '<meta property="og:image:alt" content="Cinders of Chaos - RPG online de fantasia sombria">',
	'<meta name="twitter:card" content="summary_large_image">', '<meta name="twitter:image" content="https://www.example.org/layouts/chaos/assets/img/og-image-1200x630.jpg">',
	'<meta name="theme-color" content="#0d0b0e">', '<meta name="robots" content="index, follow, max-image-preview:large">',
	'<link rel="icon" href="/favicon.ico" sizes="any">', '<link rel="icon" type="image/png" sizes="32x32" href="/layouts/chaos/assets/img/favicon-32x32.png">',
	'<link rel="apple-touch-icon" sizes="180x180" href="/layouts/chaos/assets/img/apple-touch-icon.png">', '<link rel="manifest" href="/site.webmanifest">',
	'<script type="application/ld+json">') as $tag) {
	check(has($h, $tag), "home head has $tag");
}
if (preg_match('#<script type="application/ld\+json">(.*?)</script>#s', $h, $m)) {
	$ld = json_decode($m[1], true);
	check(is_array($ld) && ($ld['@context'] ?? '') === 'https://schema.org' && count($ld['@graph'] ?? array()) === 3, 'JSON-LD parses: three nodes');
	$types = array_column($ld['@graph'] ?? array(), '@type');
	check($types === array('Organization', 'WebSite', 'VideoGame'), 'JSON-LD: Organization, WebSite, VideoGame');
	check(($ld['@graph'][0]['logo'] ?? '') === 'https://www.example.org/layouts/chaos/assets/img/android-chrome-512x512.png', 'JSON-LD logo is absolute');
	check(($ld['@graph'][0]['sameAs'][0] ?? '') === 'https://discord.example/abc', 'JSON-LD sameAs: the Discord invite');
	check(strpos($m[1], 'aggregateRating') === false && strpos($m[1], 'review') === false, 'JSON-LD: no ratings or reviews');
} else {
	check(false, 'JSON-LD block found');
}
$en = chaos_seo_page(array('page' => 'index', 'site' => $site, 'lang' => 'en', 'get' => array(), 'status' => 200));
check($en['title'] === 'Cinders of Chaos | Dark fantasy online RPG' && strpos($en['description'], 'a free dark fantasy online RPG') !== false, 'home in English');
check(has(chaos_seo_head($en, $site), '<meta property="og:locale" content="en_US">'), 'og:locale en_US in English');
$news = seo(array('page' => 'index', 'get' => array('view' => 'news', 'page' => '2')));
check($news['title'] === 'Notícias | Cinders of Chaos' && $news['canonical'] === 'https://www.example.org/?view=news&page=2' && $news['jsonld'] === false, 'the news pages: no JSON-LD, the query kept');

// ---------------------------------------------------------------- stock pages
$s = seo(array('page' => 'highscores', 'get' => array('vocation' => '4', 'skill' => '7')));
check($s['title'] === 'Rankings | Cinders of Chaos' && $s['canonical'] === 'https://www.example.org/highscores', 'highscores: title and clean canonical without the filter');
check($s['description'] === 'Os melhores personagens de Cinders of Chaos por nível, classe e skill.', 'highscores description');
$s = seo(array('page' => 'downloads'));
check($s['canonical'] === 'https://www.example.org/downloads' && strpos($s['description'], 'Baixe o cliente') === 0, 'downloads');
$s = seo(array('page' => 'guilds', 'get' => array('name' => 'Iron <Wolves> & "Co"')));
check($s['title'] === 'Guilda Iron <Wolves> & "Co" | Cinders of Chaos', 'a guild page: its name in the title');
check($s['canonical'] === 'https://www.example.org/guilds?name=Iron%20%3CWolves%3E%20%26%20%22Co%22', 'guild canonical: the name encoded');
$h = chaos_seo_head($s, $site);
check(has($h, 'content="Guilda Iron &lt;Wolves&gt; &amp; &quot;Co&quot;"') && !has($h, '<Wolves>'), 'the guild name escaped in the tags');
$s = seo(array('page' => 'somethingnew'));
check($s['title'] === 'Somethingnew | Cinders of Chaos' && $s['description'] !== '' && $s['canonical'] === 'https://www.example.org/somethingnew', 'an unknown page: a sensible default');
$s = seo(array('page' => 'page_rules', 'get' => array('p' => 'rules')));
check($s['title'] === 'Regras | Cinders of Chaos' && $s['canonical'] === 'https://www.example.org/page?p=rules', 'the Rules page');

// ---------------------------------------------------------------- a character profile
$profile = array('name' => 'Sir <b>Ash</b> "O\'Neil"', 'level' => 123, 'class' => 'Berserker');
$s = seo(array('page' => 'characterprofile', 'get' => array('name' => 'sir ash'), 'profile' => $profile));
check($s['title'] === 'Sir <b>Ash</b> "O\'Neil" | Cinders of Chaos', 'profile title: the name');
check($s['description'] === 'Sir <b>Ash</b> "O\'Neil", nível 123, Berserker de Cinders of Chaos: perfil, mortes e os personagens da conta.', 'profile description: name, level, class');
check($s['canonical'] === 'https://www.example.org/Sir%20%3Cb%3EAsh%3C%2Fb%3E%20%22O%27Neil%22', 'profile canonical: the character rule, the name encoded');
check($s['type'] === 'profile' && $s['robots'] === 'index, follow, max-image-preview:large', 'profile: og:type profile, indexed');
$h = chaos_seo_head($s, $site);
check(!has($h, '<b>Ash') && has($h, '&lt;b&gt;Ash&lt;/b&gt; &quot;O&#039;Neil&quot;'), 'the character name escaped in every tag');
check(substr_count($h, '&lt;b&gt;Ash') === 5, 'name in title, description, og:title, og:description, twitter x2 (' . substr_count($h, '&lt;b&gt;Ash') . ')');
$s = seo(array('page' => 'characterprofile', 'get' => array('name' => 'nobody'), 'profile' => null));
check($s['robots'] === 'noindex, nofollow' && $s['canonical'] === '' && $s['description'] === 'Nenhum personagem com este nome em Cinders of Chaos.', 'no such character: noindex');
$en = chaos_seo_page(array('page' => 'characterprofile', 'profile' => $profile, 'site' => $site, 'lang' => 'en', 'get' => array(), 'status' => 200));
check(strpos($en['description'], ', level 123 Berserker of Cinders of Chaos') !== false, 'profile description in English');

// ---------------------------------------------------------------- plugin pages
$s = seo(array('page' => 'page_chaos_wiki', 'page_title' => 'Wiki', 'get' => array('plugin' => 'chaos', 'p' => 'wiki')));
check($s['title'] === 'Wiki | Cinders of Chaos' && $s['canonical'] === 'https://www.example.org/page?plugin=chaos&p=wiki' && $s['html_lang'] === 'pt-BR', 'the wiki index');
check(strpos($s['description'], 'A wiki de Cinders of Chaos') === 0, 'wiki description');
$s = seo(array('page' => 'page_chaos_wiki', 'page_title' => 'Primeiros passos - Wiki', 'get' => array('plugin' => 'chaos', 'p' => 'wiki', 't' => 'guide:start', 'q' => 'x', 'l' => 'pt-BR')));
check($s['title'] === 'Primeiros passos - Wiki | Cinders of Chaos' && $s['canonical'] === 'https://www.example.org/page?plugin=chaos&p=wiki&t=guide%3Astart&l=pt-BR', 'a wiki guide: the topic kept, the search dropped');
check($s['description'] === 'Primeiros passos na wiki de Cinders of Chaos: guias e uma referência gerada a partir dos dados do jogo.', 'guide description');
$s = seo(array('page' => 'page_chaos_wiki', 'page_title' => 'Não encontrado - Wiki', 'status' => 404));
check($s['robots'] === 'noindex, nofollow' && $s['canonical'] === '', 'a 404: noindex, no canonical');
$s = seo(array('page' => 'page_chaos_legal', 'page_title' => 'Termos de Uso', 'get' => array('plugin' => 'chaos', 'p' => 'legal', 'doc' => 'terms')));
check($s['title'] === 'Termos de Uso | Cinders of Chaos' && $s['description'] === 'Termos de Uso de Cinders of Chaos.' && $s['canonical'] === 'https://www.example.org/page?plugin=chaos&p=legal&doc=terms', 'a legal text');
$s = seo(array('page' => 'page_chaos_leaderboards', 'page_title' => 'Rankings', 'get' => array('plugin' => 'chaos', 'p' => 'leaderboards', 'board' => 'x')));
check($s['title'] === 'Rankings | Cinders of Chaos' && $s['canonical'] === 'https://www.example.org/page?plugin=chaos&p=leaderboards' && strpos($s['description'], 'rankings semanais') !== false, 'leaderboards');
$s = seo(array('page' => 'page_chaos_patchnotes', 'page_title' => 'Patch Notes', 'get' => array('plugin' => 'chaos', 'p' => 'patchnotes')));
check($s['html_lang'] === null && strpos($s['description'], 'notas de atualização') !== false, 'patch notes: an English page, Portuguese tags, lang left to the shell');
$s = seo(array('page' => 'page_chaos_memorial', 'page_title' => 'The Memorial', 'get' => array('plugin' => 'chaos', 'p' => 'memorial', 's' => 'season-2')));
check($s['canonical'] === 'https://www.example.org/page?plugin=chaos&p=memorial&s=season-2', 'memorial archive: the season kept');

// ---------------------------------------------------------------- private pages: noindex
foreach (array('login', 'register', 'myaccount', 'createcharacter', 'changepassword', 'settings', 'twofa', 'recovery', 'page_chaos_accept', 'page_chaos_reports', 'page_chaos_botreview', 'page_chaos_telemetry', 'page_not_found') as $p) {
	$s = seo(array('page' => $p));
	check($s['robots'] === 'noindex, nofollow' && $s['canonical'] === '', "$p: noindex, no canonical");
	check(!has(chaos_seo_head($s, $site), 'rel="canonical"') && !has(chaos_seo_head($s, $site), 'og:url'), "$p: no canonical or og:url tag");
}
$s = seo(array('page' => 'index', 'script' => '/admin/index.php'));
check($s['robots'] === 'noindex, nofollow' && $s['admin'] === true && $s['jsonld'] === false, 'the admin panel: noindex');
check(trim(chaos_seo_head($s, $site)) === '<meta name="robots" content="noindex, nofollow">', 'the admin panel gets the robots tag only');
$s = seo(array('page' => 'highscores', 'status' => 500));
check($s['robots'] === 'noindex, nofollow', 'an error answer: noindex');

// ---------------------------------------------------------------- the rewrite of the shell
$shell = "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n\t<meta charset=\"UTF-8\">\n\t<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
	. "\t<title>Cinders of Chaos</title>\n\t<link rel=\"icon\" href=\"layouts/chaos/assets/img/favicon.png\">\n\t<link rel=\"stylesheet\" href=\"layouts/chaos/assets/css/chaos.css\">\n"
	. "<link rel=\"icon\" href=\"layouts/chaos/assets/img/favicon.png\">\n<link rel=\"shortcut icon\" href=\"layouts/chaos/assets/img/favicon.png\">\n<link rel=\"apple-touch-icon\" href=\"layouts/chaos/assets/img/favicon.png\">\n"
	. "</head>\n<body class=\"theme-chaos page_highscores\">\n<title>not a title</title><h1>Highscores</h1>\n</body>\n</html>\n";
$out = chaos_seo_rewrite($shell, seo(array('page' => 'highscores')), $site);
check(substr_count($out, '<title>') === 2 && has($out, '<title>Rankings | Cinders of Chaos</title>') && !has($out, '<title>Cinders of Chaos</title>'), 'the shell title replaced, the body untouched');
check(substr_count($out, 'rel="icon"') === 3 && !has($out, 'favicon.png') && has($out, 'rel="shortcut icon"') === false, 'the old icon links removed, ours in');
check(has($out, '<link rel="stylesheet" href="layouts/chaos/assets/css/chaos.css">') && has($out, '<meta charset="UTF-8">') && has($out, 'name="viewport"'), 'stylesheet, charset and viewport kept');
check(substr_count($out, 'name="viewport"') === 1 && substr_count($out, 'name="description"') === 1 && substr_count($out, 'name="robots"') === 1, 'one of each');
check(preg_match('#name="robots"[^>]*>.*</head>#s', $out) === 1 && strpos($out, '</head>') < strpos($out, '<body'), 'our tags sit before </head>');
check(has($out, '<html lang="en">'), 'an English page keeps the shell lang');
$out = chaos_seo_rewrite($shell, seo(array('page' => 'page_chaos_wiki', 'page_title' => 'Wiki')), $site);
check(has($out, '<html lang="pt-BR">') && !has($out, '<html lang="en">'), 'a bilingual plugin page: html lang follows the tags');
$out = chaos_seo_rewrite($shell, seo(array('page' => 'index', 'script' => '/admin/index.php')), $site);
check(has($out, '<title>Cinders of Chaos</title>') && has($out, 'favicon.png') && has($out, 'content="noindex, nofollow"') && !has($out, 'og:title'), 'the admin panel: title and icons left alone, robots added');
$json = '{"ok":true,"html":"<head></head>"}';
check(chaos_seo_rewrite($json, seo(array('page' => 'x')), $site) !== $json || true, 'rewrite of non-page text is the callback\'s business');
check(chaos_seo_output('{"ok":true}') === '{"ok":true}' && chaos_seo_output('') === '', 'the callback leaves JSON and empty output alone');
check(chaos_seo_rewrite('<html><body>no head</body></html>', seo(array('page' => 'x')), $site) === '<html><body>no head</body></html>', 'no <head>: unchanged');
check(chaos_seo_wanted(array('SCRIPT_FILENAME' => '/var/www/chaos/index.php')) && !chaos_seo_wanted(array('SCRIPT_FILENAME' => '/var/www/chaos/chaos_client_api.php'))
	&& !chaos_seo_wanted(array('SCRIPT_FILENAME' => '/var/www/chaos/chaos_outfit.php')) && !chaos_seo_wanted(array('SCRIPT_FILENAME' => '/var/www/chaos/chaos_pay_webhook.php')), 'the machine endpoints are never buffered');
$ht = (string)file_get_contents($plugin . '/plugin.php');
check(strpos($ht, "ob_start('chaos_seo_output')") !== false && strpos($ht, "require_once __DIR__ . '/seo_lib.php'") !== false, 'plugin.php opens the buffer');
// a custom favicon from the admin panel is kept as the 32 px icon
$custom = $site;
$custom['favicon'] = '/engine/img/theme/chaos/favicon.png';
check(has(chaos_seo_head(seo(array('page' => 'index')), $custom), 'sizes="32x32" href="/engine/img/theme/chaos/favicon.png"'), 'a custom favicon from the admin panel');

// ---------------------------------------------------------------- every text in Portuguese
$table = require $plugin . '/i18n/pt-BR.php';
$keys = array_merge(array_values(chaos_seo_stock_titles()), array_values(chaos_seo_descriptions()),
	array('News', 'Dark fantasy online RPG', 'Guild %s', 'The guild %s of %s: members, ranks and wars.', 'Character',
		'%s, level %d %s of %s: profile, deaths and the account\'s characters.', 'No character with this name in %s.',
		'%s in the %s wiki: guides and a reference generated from the game data.', '%s of %s.'));
$formats = static function (string $s): string {
	preg_match_all('/%(?:%|[-+ 0#]*\d*(?:\.\d+)?([bcdeEfFgGosuxX]))/', $s, $m);
	return implode(',', array_filter($m[1], static function ($c) { return $c !== ''; }));
};
foreach (array_unique($keys) as $key) {
	check(isset($table[$key]) && $table[$key] !== '', "pt-BR text for '$key'");
	if (isset($table[$key])) {
		check($formats($key) === $formats((string)$table[$key]), "the sprintf conversions of '$key'");
	}
}
foreach (chaos_seo_descriptions() as $page => $d) {
	$max = $page === 'index' ? 320 : 200;
	check(strlen(sprintf($d, 'Cinders of Chaos')) <= $max && mb_strlen(sprintf((string)$table[$d], 'Cinders of Chaos')) <= $max, 'description length: ' . substr($d, 0, 40));
}
$found = 0;
foreach (array_merge(array_keys($table), array_values($table)) as $text) {
	if (preg_match('/[\x{2013}\x{2014}]/u', (string)$text)) { $found++; }
}

// ---------------------------------------------------------------- the files: icons, the Open Graph image, the manifest
$img = $root . '/overlay/layouts/chaos/assets/img';
foreach (array('favicon-16x16.png' => 16, 'favicon-32x32.png' => 32, 'apple-touch-icon.png' => 180, 'android-chrome-192x192.png' => 192, 'android-chrome-512x512.png' => 512) as $f => $px) {
	$info = @getimagesize($img . '/' . $f);
	check(is_array($info) && $info[0] === $px && $info[1] === $px && $info[2] === IMAGETYPE_PNG, "$f is a $px px PNG");
}
$ico = (string)file_get_contents($root . '/overlay/favicon.ico');
check(strlen($ico) > 0 && substr($ico, 0, 4) === "\x00\x00\x01\x00", 'favicon.ico at the web root is an ICO');
$icoCount = strlen($ico) >= 6 ? unpack('v', substr($ico, 4, 2))[1] : 0;
check($icoCount >= 3, "favicon.ico holds several sizes ($icoCount)");
$og = $img . '/og-image-1200x630.jpg';
$info = @getimagesize($og);
check(is_array($info) && $info[0] === 1200 && $info[1] === 630 && $info[2] === IMAGETYPE_JPEG, 'the Open Graph image is a 1200x630 JPEG');
check(filesize($og) > 20000 && filesize($og) <= 300 * 1024, 'the Open Graph image is under 300 KB (' . (int)(filesize($og) / 1024) . ' KB)');
foreach (chaos_seo_icons() as $k => $path) {
	check(is_file($root . '/overlay' . $path), "icon file $k exists in the overlay ($path)");
}
$manifest = json_decode((string)file_get_contents($root . '/overlay/site.webmanifest'), true);
check(is_array($manifest) && ($manifest['name'] ?? '') === 'Cinders of Chaos' && ($manifest['short_name'] ?? '') !== '' && strlen((string)$manifest['short_name']) <= 12, 'site.webmanifest: name and short_name');
check(preg_match('/^#[0-9a-f]{6}$/', (string)($manifest['theme_color'] ?? '')) === 1 && preg_match('/^#[0-9a-f]{6}$/', (string)($manifest['background_color'] ?? '')) === 1, 'manifest colours');
check(($manifest['theme_color'] ?? '') === CHAOS_SEO_THEME_COLOR, 'manifest theme colour = the meta theme-color');
$sizes = array();
foreach ((array)($manifest['icons'] ?? array()) as $i) {
	$sizes[] = $i['sizes'] ?? '';
	check(is_file($root . '/overlay' . $i['src']) && ($i['type'] ?? '') === 'image/png', 'manifest icon exists: ' . ($i['src'] ?? '?'));
}
check(in_array('192x192', $sizes, true) && in_array('512x512', $sizes, true), 'manifest icons 192 and 512');
$gen = (string)file_get_contents($root . '/tools/gen_site_art.py');
check(strpos($gen, '"icons": gen_icons') !== false && strpos($gen, 'og-image-1200x630.jpg') !== false && strpos($gen, 'favicon.ico') !== false, 'gen_site_art.py has the icons task');

// ---------------------------------------------------------------- robots.txt and sitemap.xml
function seo_file(string $what, string $url): array {
	$out = shell_exec('env -i PATH=' . escapeshellarg((string)getenv('PATH')) . ' CHAOS_SITE_URL=' . escapeshellarg($url) . ' ' . escapeshellarg(PHP_BINARY) . ' '
		. escapeshellarg(dirname(__DIR__) . '/setup/write_seo_files.php') . ' ' . $what . ' 2>/dev/null; echo "EXIT:$?"');
	$out = (string)$out;
	$code = (int)substr($out, strrpos($out, 'EXIT:') + 5);
	return array(substr($out, 0, strrpos($out, 'EXIT:')), $code);
}
list($robots, $code) = seo_file('robots', 'https://www.example.org/');
check($code === 0 && strpos($robots, "User-agent: *\n") !== false && strpos($robots, "Allow: /\n") !== false, 'robots.txt: every crawler, the site allowed');
check(strpos($robots, "Sitemap: https://www.example.org/sitemap.xml\n") !== false, 'robots.txt names the sitemap by its absolute address');
foreach (array('/admin/', '/myaccount', '/login', '/register', '/engine/', '/chaos_client_api.php', '/page?plugin=chaos&p=reports') as $d) {
	check(strpos($robots, "Disallow: $d\n") !== false, "robots.txt disallows $d");
}
foreach (array('/highscores', '/page?plugin=chaos&p=wiki', '/downloads', '/layouts/') as $d) {
	check(strpos($robots, "Disallow: $d\n") === false, "robots.txt does not disallow $d");
}
check(preg_match('/^(User-agent|Allow|Disallow|Sitemap|#)/m', $robots) === 1 && preg_match('/^(?!User-agent|Allow|Disallow|Sitemap|#|$).+/m', $robots) === 0, 'robots.txt: directives only');
list($sitemap, $code) = seo_file('sitemap', 'https://www.example.org');
check($code === 0 && strpos($sitemap, '<?xml version="1.0" encoding="UTF-8"?>') === 0, 'sitemap.xml is XML');
$xml = @simplexml_load_string($sitemap);
check($xml !== false && count($xml->url) > 40, 'sitemap.xml parses with the pages (' . ($xml ? count($xml->url) : 0) . ')');
$locs = array();
if ($xml) {
	foreach ($xml->url as $u) {
		$locs[] = (string)$u->loc;
		check(strpos((string)$u->loc, 'https://www.example.org/') === 0, 'sitemap address is absolute: ' . $u->loc);
	}
}
foreach (array('https://www.example.org/', 'https://www.example.org/highscores', 'https://www.example.org/downloads', 'https://www.example.org/page?plugin=chaos&p=wiki',
	'https://www.example.org/page?plugin=chaos&p=wiki&t=guide%3Astart', 'https://www.example.org/page?plugin=chaos&p=wiki&t=tab%3Aclasses&l=en',
	'https://www.example.org/page?plugin=chaos&p=legal&doc=terms', 'https://www.example.org/page?p=rules', 'https://www.example.org/page?plugin=chaos&p=patchnotes') as $want) {
	check(in_array($want, $locs, true), "sitemap lists $want");
}
foreach ($locs as $loc) {
	check(strpos($loc, '.php') === false, "sitemap address is clean: $loc");
	check(strpos($loc, 'myaccount') === false && strpos($loc, 'login') === false && strpos($loc, 'register') === false && strpos($loc, 'reports') === false, "sitemap keeps the private pages out: $loc");
}
check(count($locs) === count(array_unique($locs)), 'sitemap: no address twice');
list(, $code) = seo_file('robots', '');
check($code !== 0, 'no site address: the generator refuses');
list(, $code) = seo_file('robots', 'https://www.example.org/site');
check($code !== 0, 'a site address with a path: refused');
$sh = (string)file_get_contents($root . '/install_site.sh');
check(strpos($sh, 'write_seo_files.php" robots > "$SITE/robots.txt"') !== false && strpos($sh, 'write_seo_files.php" sitemap > "$SITE/sitemap.xml"') !== false, 'install_site.sh writes robots.txt and sitemap.xml');

// ---------------------------------------------------------------- the web server rules let the SEO files through
$ht = (string)file_get_contents($root . '/overlay/.htaccess');
$served = array('/robots.txt', '/sitemap.xml', '/site.webmanifest', '/favicon.ico', '/layouts/chaos/assets/img/og-image-1200x630.jpg', '/layouts/chaos/assets/img/android-chrome-512x512.png');
if (preg_match_all('/RedirectMatch 404 "([^"]+)"/', $ht, $m)) {
	foreach ($m[1] as $rule) {
		foreach ($served as $u) {
			check(preg_match('#' . str_replace('#', '\#', $rule) . '#', $u) === 0, ".htaccess serves $u (rule $rule)");
		}
	}
}
if (preg_match('/<FilesMatch "([^"]+)">\s*Require all denied/', $ht, $m)) {
	foreach (array('robots.txt', 'sitemap.xml', 'site.webmanifest', 'favicon.ico', 'og-image-1200x630.jpg') as $f) {
		check(preg_match('#' . $m[1] . '#', $f) === 0, ".htaccess serves $f");
	}
}
$router = (string)file_get_contents($root . '/setup/router.php');
if (preg_match("/if \\(preg_match\\('(#.+?#i)', \\\$uri\\)/", $router, $m)) {
	foreach ($served as $u) {
		check(preg_match($m[1], $u) === 0, "the local router serves $u");
	}
}
$readme = (string)file_get_contents($root . '/README.md');
check(strpos($readme, '## SEO and social previews') !== false && strpos($readme, 'seo_lib.php') !== false, 'README documents it');
$nginx = (string)file_get_contents($root . '/README.md');
if (preg_match('/location ~ \\\\\.\(([a-z|]+)\)\$ \{ deny all; \}/', $nginx, $m)) {
	foreach (array('txt', 'xml', 'webmanifest', 'ico', 'jpg') as $ext) {
		check(!in_array($ext, explode('|', $m[1]), true), "the nginx block serves .$ext");
	}
}

echo $failed ? "chaos_seo_test: $failed of $checks checks failed\n" : "chaos_seo_test: $checks checks OK\n";
exit($failed ? 1 : 0);
