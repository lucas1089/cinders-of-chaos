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
