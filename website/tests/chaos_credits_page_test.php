<?php
// php website/tests/chaos_credits_page_test.php : the Credits page (plugins/chaos/credits_lib.php, pages/credits.php)
// with the generated data (credits/credits_data.json from docs/CREDITS.md by client/tools/gen_credits.py): both
// languages, every section and entry, the required credit lines word for word, escaping, source links, a missing
// data file, the footer and site credits links. Any PHP notice or warning fails the test. php-cli only.
$config = array();
$GLOBALS['config'] = $config;

$failed = 0;
$checks = 0;
$failures = array();
function check(bool $ok, string $what): void {
	global $failed, $checks, $failures;
	$checks++;
	if (!$ok) {
		$failed++;
		$failures[] = "FAIL: $what";
	}
}
$notices = array();
set_error_handler(static function (int $no, string $msg, string $file, int $line) use (&$notices): bool {
	$notices[] = "$msg ($file:$line)";
	return true;
});

require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/credits_lib.php';

function render_credits(array $get): array {
	global $config;
	$_GET = $get;
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/credits.php';
	return array((string)ob_get_clean(), (string)($GLOBALS['page_title'] ?? ''));
}

// ---------------------------------------------------------------- the data
$data = chaos_credits_data();
check(count($data) >= 5, 'data: sections');
$names = array();
$credits = array();
foreach ($data as $s) {
	foreach ($s['entries'] as $e) {
		$names[] = $e['name'];
		if (isset($e['credit'])) {
			$credits[] = $e['credit'];
		}
	}
}
check(count($names) >= 30, 'data: entries');
check(in_array("Will's Pixel Explosions - Will Tice / unTied Games", $credits, true), 'data: explosions credit line');
check(in_array('Super Pixel Effects Gigapack - Will Tice / unTied Games', $credits, true), 'data: gigapack credit line');
foreach (array('Cinzel', 'Alegreya SC', 'Alegreya Sans', 'IM Fell English', 'PT Sans', 'xBRZ 1.8', 'ZnoteX', 'FX Pack 1-4') as $want) {
	check(in_array($want, $names, true), "data: $want");
}
check(chaos_credits_data(__DIR__ . '/no_such_file.json') === array(), 'data: a missing file gives no section');

// ---------------------------------------------------------------- the page in both languages
list($pt, $ptTitle) = render_credits(array());
list($en, $enTitle) = render_credits(array('l' => 'en'));
check($ptTitle === 'Créditos' && $enTitle === 'Credits', 'page titles');
check(strpos($pt, 'lang="pt-BR"') !== false && strpos($en, 'lang="en"') !== false, 'page languages');
check(strpos($pt, 'href="page.php?plugin=chaos&amp;p=credits&amp;l=en"') !== false, 'pt-BR page links English');
check(strpos($en, 'href="page.php?plugin=chaos&amp;p=credits"') !== false, 'English page links Portuguese');
foreach ($data as $s) {
	check(strpos($pt, '<h2 class="chaos-heading">' . chaos_h($s['pt']) . '</h2>') !== false, 'pt-BR heading ' . $s['title']);
	check(strpos($en, '<h2 class="chaos-heading">' . chaos_h($s['title']) . '</h2>') !== false, 'English heading ' . $s['title']);
}
foreach ($names as $n) {
	check(strpos($pt, '<strong>' . chaos_h($n) . '</strong>') !== false, "entry $n");
}
foreach ($credits as $c) {
	check(strpos($en, '<div class="chaos-credits__credit">' . chaos_h($c) . '</div>') !== false, "credit line $c");
}
check(strpos($pt, 'Autor: Will Tice / unTied Games') !== false && strpos($en, 'Author: Will Tice / unTied Games') !== false, 'author labels');
check(strpos($en, '<a href="https://github.com/NDISCOVER/Cinzel" rel="noopener nofollow">') !== false, 'source link');

// ---------------------------------------------------------------- rendering rules
$html = chaos_credits_render(array(array('title' => 'T<x>', 'pt' => 'P<y>', 'note' => 'n&<', 'entries' => array(
	array('name' => '<script>', 'source' => 'javascript:alert(1)'), array('name' => 'b', 'source' => 'https://e.example/"x')))), 'pt-BR');
check(strpos($html, '<script>') === false && strpos($html, '&lt;script&gt;') !== false, 'names escaped');
check(strpos($html, 'P&lt;y&gt;') !== false && strpos($html, 'n&amp;&lt;') !== false, 'heading and note escaped');
check(strpos($html, 'href="javascript') === false && strpos($html, '<a ') === false, 'only http(s) sources are links');
check(strpos(chaos_credits_render(array(), 'en'), 'not available yet') !== false, 'no data: a note');

$src = (string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/pages/credits.php');
check(strpos($src, "if (!isset(\$config)) { http_response_code(403);") !== false, 'no direct access');

// ---------------------------------------------------------------- links
$locale = include __DIR__ . '/../overlay/layouts/chaos/locale/en.php';
check(strpos((string)$locale['void.footer.copyright'], '<a href="page.php?plugin=chaos&amp;p=credits">') !== false, 'footer links the credits');
check(strpos((string)file_get_contents(__DIR__ . '/../overlay/layouts/chaos/views/credits.php'), 'page.php?plugin=chaos&amp;p=credits') !== false, 'site credits page links the game credits');

foreach ($notices as $n) {
	$failures[] = "NOTICE: $n";
	$failed++;
}
foreach ($failures as $f) {
	echo $f, "\n";
}
echo "chaos_credits_page_test: $checks checks, ", $failed ? "$failed failed" : 'OK', "\n";
exit($failed ? 1 : 0);
