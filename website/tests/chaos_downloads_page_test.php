<?php
// php website/tests/chaos_downloads_page_test.php : the downloads page (layouts/chaos/views/downloads.php) with the
// release info of dl/downloads.json (written by server/deploy/chaos_kit_update.sh): release, date, size and SHA-256
// under a link whose file is listed, nothing under other links, "Coming soon" without a link, escaping, a missing or
// broken file. Any PHP notice or warning fails the test. php-cli only.
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
$notices = array();
set_error_handler(static function (int $no, string $msg, string $file, int $line) use (&$notices): bool {
	$notices[] = "$msg ($file:$line)";
	return true;
});

$ENTRIES = array();
function znote_download_entries(): array { return $GLOBALS['ENTRIES']; }

function render(): string {
	ob_start();
	include __DIR__ . '/../overlay/layouts/chaos/views/downloads.php';
	return (string)ob_get_clean();
}

$tmp = sys_get_temp_dir() . '/chaos_dl_test_' . getmypid();
@mkdir($tmp);
$json = $tmp . '/downloads.json';
$sha = str_repeat('ab', 32);
file_put_contents($json, json_encode(array('release' => 47, 'tag' => 'winpkg-47', 'updated' => '2026-10-21 14:03 UTC',
	'files' => array('CindersOfChaos-Client-Windows.zip' => array('size' => 327155712, 'sha256' => $sha),
		'CindersOfChaos-Client-Linux.tar.gz' => array('size' => 5 * 1048576 + 104858, 'sha256' => 'not-a-hash')))));
$GLOBALS['chaos_downloads_json'] = $json;
$setupDir = $tmp . '/download'; // the launcher setup folder (the view's $GLOBALS['chaos_download_dir']), empty at first
@mkdir($setupDir);
$GLOBALS['chaos_download_dir'] = $setupDir;
$ENTRIES = array(
	array('key' => 'windows_client', 'label' => 'W', 'description' => '', 'url' => 'https://example.org/dl/CindersOfChaos-Client-Windows.zip?x=1'),
	array('key' => 'linux_client', 'label' => 'L', 'description' => '', 'url' => '/dl/CindersOfChaos-Client-Linux.tar.gz'),
	array('key' => 'macos_client', 'label' => 'M<b>', 'description' => 'd', 'url' => '#download-coming-soon'),
);
$out = render();
check(strpos($out, 'Release 47 · 2026-10-21 14:03 UTC · 312 MB') !== false, 'windows: release, date, size');
check(strpos($out, 'SHA-256 <code>' . $sha . '</code>') !== false, 'windows: checksum');
check(substr_count($out, 'chaos-dl__meta') === 1, 'linux: a bad checksum shows no line');
check(strpos($out, 'Coming soon') !== false && strpos($out, 'M&lt;b&gt;') !== false, 'coming soon, escaped label');
check(substr_count($out, '>Download</a>') === 2, 'two download links');

// the Unity client (beta) card: always there, with the launcher note and no download button of its own ...
check(strpos($out, 'Unity client (beta)') !== false && strpos($out, 'chaos-dl__card--unity') !== false, 'unity: the card');
check(strpos($out, 'choose &quot;Unity client (beta)&quot; next to Client') !== false, 'unity: the launcher note');
check(substr_count($out, 'chaos-dl__card') === 5, 'unity: windows, linux, macos and unity cards (the class counts twice on the unity one)');
// ... a direct link only when an entry unity_client has a real address; a placeholder or a hostile one adds none
$ENTRIES[] = array('key' => 'unity_client', 'label' => 'U', 'description' => '', 'url' => 'https://example.org/dl/Unity.zip');
$out2 = render();
check(substr_count($out2, '>Download</a>') === 3 && strpos($out2, 'href="https://example.org/dl/Unity.zip"') !== false,
	'unity: a direct link with an address');
check(substr_count($out2, '<h3>Unity client (beta)</h3>') === 1, 'unity: the entry is not drawn twice');
$ENTRIES[3]['url'] = '#download-coming-soon';
$out2 = render();
check(substr_count($out2, '>Download</a>') === 2 && strpos($out2, 'Unity.zip') === false, 'unity: a placeholder address adds no link');
$ENTRIES[3]['url'] = 'https://example.org/"><script>x</script>';
$out2 = render();
check(strpos($out2, '<script>') === false, 'unity: the address is escaped');
array_pop($ENTRIES);
// every text of the card has a Brazilian Portuguese text
$view = (string)file_get_contents(__DIR__ . '/../overlay/layouts/chaos/views/downloads.php');
$table = require __DIR__ . '/../overlay/plugins/chaos/i18n/pt-BR.php';
preg_match_all("/chaos_t\\('((?:[^'\\\\]|\\\\.)*)'\\)/", $view, $m);
check(count($m[1]) === 7, 'unity and setup: seven chaos_t texts without an argument in the view (' . count($m[1]) . ')');
preg_match_all("/chaos_t\\('((?:[^'\\\\]|\\\\.)*)', /", $view, $m2);
check(count($m2[1]) === 1, 'setup: one chaos_t text with an argument');
foreach (array_merge($m[1], $m2[1]) as $en) {
	$en = str_replace("\\'", "'", $en);
	check(isset($table[$en]) && $table[$en] !== '' && (in_array($en, array('Download', 'Cinders-of-Chaos-Setup.exe · %s MB'), true) || $table[$en] !== $en), 'pt-BR text for: ' . substr($en, 0, 40));
}
check(($table['Unity client (beta)'] ?? '') === 'Cliente Unity (beta)', 'pt-BR: Cliente Unity (beta)');

// ---------------------------------------------------------------- the launcher setup (ROADMAP O552)
$exe = $setupDir . '/Cinders-of-Chaos-Setup.exe';
$sumFile = $exe . '.sha256';
$ssum = str_repeat('cd', 32);
$rmSetup = static function () use ($exe, $sumFile): void { foreach (array($exe, $sumFile) as $f) { if (is_file($f)) { unlink($f); } } };
$out = render();
check(strpos($out, 'download/Cinders-of-Chaos-Setup.exe') === false && strpos($out, 'chaos-dl__card--setup') === false, 'setup: no file, no setup card');
check(strpos($out, 'Download the client for your system and unpack it') !== false, 'setup: no file, the unpack step as before');
file_put_contents($exe, str_repeat('x', 6 * 1048576 + 300000));
check(strpos(render(), 'chaos-dl__card--setup') === false, 'setup: file without a sum file is not shown');
file_put_contents($sumFile, "$ssum  Cinders-of-Chaos-Setup.exe\n");
$out = render();
check(strpos($out, 'chaos-dl__card--setup') !== false && strpos($out, 'href="download/Cinders-of-Chaos-Setup.exe"') !== false, 'setup: the button is the site-relative setup file');
check(strpos($out, 'SHA-256 <code>' . $ssum . '</code>') !== false, 'setup: its SHA-256');
check(strpos($out, 'Cinders-of-Chaos-Setup.exe · 6.3 MB') !== false, 'setup: its size');
check(strpos($out, 'The installer and launcher for Windows 10 and 11 (64-bit). It installs the game into your own folder, needs no administrator rights and keeps the game up to date.') !== false, 'setup: the card text');
check(strpos($out, 'On Windows, download the setup, run it and start the game from the launcher.') !== false
	&& strpos($out, 'Download the client for your system and unpack it') === false, 'setup: the how to start step');
// the setup wins over the configured windows_client link (and its release line); linux and macos stay as they are
check(strpos($out, 'Windows.zip') === false && strpos($out, 'Release 47') === false, 'setup: wins over the configured windows link');
check(substr_count($out, '>Download</a>') === 2 && strpos($out, 'CindersOfChaos-Client-Linux.tar.gz') !== false && strpos($out, 'Coming soon') !== false, 'setup: linux and macos cards unchanged');
// an upper case sum with a binary marker and a CRLF is fine; the sum is shown in lower case
file_put_contents($sumFile, strtoupper($ssum) . " *Cinders-of-Chaos-Setup.exe\r\n");
check(strpos(render(), 'SHA-256 <code>' . $ssum . '</code>') !== false, 'setup: upper case sum with a binary marker');
// bad sums: too short, not hex, the name of another file, no name, an empty file, an extra word
foreach (array('short' => "abcd  Cinders-of-Chaos-Setup.exe\n", 'not hex' => str_repeat('zz', 32) . "  Cinders-of-Chaos-Setup.exe\n",
	'other name' => "$ssum  Other.exe\n", 'no name' => "$ssum\n", 'empty' => '', 'extra word' => "$ssum  Cinders-of-Chaos-Setup.exe x\n") as $what => $body) {
	file_put_contents($sumFile, $body);
	$out = render();
	check(strpos($out, 'chaos-dl__card--setup') === false && strpos($out, 'download/Cinders-of-Chaos-Setup.exe') === false
		&& strpos($out, 'href="https://example.org/dl/CindersOfChaos-Client-Windows.zip?x=1"') !== false
		&& strpos($out, 'Download the client for your system and unpack it') !== false, "setup: a bad sum file ($what) leaves the page as before");
}
file_put_contents($sumFile, "$ssum  Cinders-of-Chaos-Setup.exe\n");
file_put_contents($exe, '');
check(strpos(render(), 'chaos-dl__card--setup') === false, 'setup: an empty file is not shown');
$rmSetup();
file_put_contents($sumFile, "$ssum  Cinders-of-Chaos-Setup.exe\n");
check(strpos(render(), 'chaos-dl__card--setup') === false, 'setup: a sum without the file is not shown');
$rmSetup();
// with the setup and no configured windows link at all ("Coming soon" today) the setup card is there
file_put_contents($exe, str_repeat('x', 1048576));
file_put_contents($sumFile, "$ssum  Cinders-of-Chaos-Setup.exe\n");
$ENTRIES[0]['url'] = '#download-coming-soon';
$out = render();
check(strpos($out, 'href="download/Cinders-of-Chaos-Setup.exe"') !== false && substr_count($out, 'Coming soon') === 1, 'setup: replaces the "Coming soon" of the windows card');
$ENTRIES[0]['url'] = 'https://example.org/dl/CindersOfChaos-Client-Windows.zip?x=1';
$rmSetup();
// pt-BR: the new texts are translated
foreach (array('The installer and launcher for Windows 10 and 11 (64-bit). It installs the game into your own folder, needs no administrator rights and keeps the game up to date.',
	'On Windows, download the setup, run it and start the game from the launcher. On Linux, download the client and unpack it into a folder of your choice.') as $en) {
	check(isset($table[$en]) && $table[$en] !== $en && $table[$en] !== '', 'pt-BR setup text: ' . substr($en, 0, 40));
}
check(isset($table['Cinders-of-Chaos-Setup.exe · %s MB']) && substr_count($table['Cinders-of-Chaos-Setup.exe · %s MB'], '%s') === 1, 'pt-BR setup size line keeps its %s');

// ---------------------------------------------------------------- download/ is served, and nothing in it runs
$root = dirname(__DIR__);
$ht = (string)file_get_contents($root . '/overlay/.htaccess');
foreach (array('/download/Cinders-of-Chaos-Setup.exe', '/download/Cinders-of-Chaos-Setup.exe.sha256') as $u) {
	if (preg_match_all('/RedirectMatch 404 "([^"]+)"/', $ht, $rm)) {
		foreach ($rm[1] as $rule) {
			check(preg_match('#' . str_replace('#', '\#', $rule) . '#', $u) === 0, ".htaccess serves $u (rule $rule)");
		}
	}
	if (preg_match('/<FilesMatch "([^"]+)">\s*Require all denied/', $ht, $fm)) {
		check(preg_match('#' . $fm[1] . '#', basename($u)) === 0, '.htaccess serves ' . basename($u));
	}
}
$dht = (string)file_get_contents($root . '/overlay/download/.htaccess');
check(strpos($dht, 'RewriteEngine Off') !== false && strpos($dht, 'php_flag engine off') !== false && strpos($dht, 'Options -Indexes -ExecCGI') !== false, 'download/.htaccess: static files only');
check(preg_match('/<FilesMatch "([^"]+)">\s*Require all denied/', $dht, $dm) === 1 && preg_match('#' . $dm[1] . '#', 'x.php') === 1 && preg_match('#' . $dm[1] . '#', 'x.phtml') === 1
	&& preg_match('#' . $dm[1] . '#', 'Cinders-of-Chaos-Setup.exe') === 0 && preg_match('#' . $dm[1] . '#', 'Cinders-of-Chaos-Setup.exe.sha256') === 0, 'download/.htaccess: scripts denied, .exe and .sha256 served');
$router = (string)file_get_contents($root . '/setup/router.php');
check(preg_match("/if \\(preg_match\\('(#.+?#i)', \\\$uri\\)/", $router, $rr) === 1 && preg_match($rr[1], '/download/Cinders-of-Chaos-Setup.exe') === 0
	&& preg_match($rr[1], '/download/Cinders-of-Chaos-Setup.exe.sha256') === 0, 'the local router serves the setup and its sum');
check(strpos($router, "preg_match('#^/download/#', \$uri)") !== false, 'the local router refuses a script in download/');
$readme = (string)file_get_contents($root . '/README.md');
check(strpos($readme, 'location ^~ /download/ {') !== false && strpos($readme, "location ~ \\.(php|phtml|phar)\$ { deny all; }\n        location ~ \\.exe\$") !== false, 'nginx: download/ block denies scripts, serves .exe');
if (preg_match('/location ~ \\\\\.\(([a-z|]+)\)\$ \{ deny all; \}/', $readme, $nm)) {
	foreach (array('exe', 'sha256') as $ext) {
		check(!in_array($ext, explode('|', $nm[1]), true), "the nginx block serves .$ext");
	}
}

file_put_contents($json, '{broken');
$out = render();
check(strpos($out, 'chaos-dl__meta') === false && substr_count($out, '>Download</a>') === 2, 'a broken file: links only');
unlink($json);
$out = render();
check(strpos($out, 'chaos-dl__meta') === false, 'no file: links only');
@rmdir($setupDir);
@rmdir($tmp);

check(count($notices) === 0, 'no PHP notices: ' . implode('; ', $notices));
echo "chaos_downloads_page_test: $checks checks, $failed failed\n";
exit($failed ? 1 : 0);
