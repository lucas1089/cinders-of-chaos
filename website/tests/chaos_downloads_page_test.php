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
check(count($m[1]) === 4, 'unity: four chaos_t texts in the view (' . count($m[1]) . ')');
foreach ($m[1] as $en) {
	$en = str_replace("\\'", "'", $en);
	check(isset($table[$en]) && $table[$en] !== '' && ($en === 'Download' || $table[$en] !== $en), 'pt-BR text for: ' . substr($en, 0, 40));
}
check(($table['Unity client (beta)'] ?? '') === 'Cliente Unity (beta)', 'pt-BR: Cliente Unity (beta)');

file_put_contents($json, '{broken');
$out = render();
check(strpos($out, 'chaos-dl__meta') === false && substr_count($out, '>Download</a>') === 2, 'a broken file: links only');
unlink($json);
$out = render();
check(strpos($out, 'chaos-dl__meta') === false, 'no file: links only');
@rmdir($tmp);

check(count($notices) === 0, 'no PHP notices: ' . implode('; ', $notices));
echo "chaos_downloads_page_test: $checks checks, $failed failed\n";
exit($failed ? 1 : 0);
