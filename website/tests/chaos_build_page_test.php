<?php
// php website/tests/chaos_build_page_test.php : build codes on the website (O391; plugins/chaos/buildcode_lib.php,
// pages/build.php): the shared vectors of docs/build_code_vectors.txt (the client's Lua codec reads the same file),
// every one-character typo refused, the tables against the client codec and the server's tree code, the tree code
// encoder against the server's codes, item names (items.xml with its cache, the CSV, uniques), the page (names and
// icons from the wiki data, escaping, a bad code, the form) and its link preview tags. php-cli only, no database.
$repo = realpath(__DIR__ . '/../..');
$config = array('chaos' => array('server_data' => $repo . '/server/data'));
$GLOBALS['config'] = $config;
$plugin = $repo . '/website/overlay/plugins/chaos';
require $plugin . '/lib.php';
require $plugin . '/buildcode_lib.php';
require_once $plugin . '/seo_lib.php';
function znote_plugin_asset(string $plugin, string $path): string { return 'plugins/' . $plugin . '/assets/' . $path; }

$failed = 0;
$checks = 0;
$fails = array(); // printed at the end: the page sets response codes, which output before would block
function check(bool $ok, string $what): void {
	global $failed, $checks, $fails;
	$checks++;
	if (!$ok) { $failed++; $fails[] = "FAIL: $what"; }
}

/** The parts of a text form an encoder takes. */
function parse_desc(string $desc): array {
	$card = array();
	foreach ($desc === '' ? array() : explode(';', $desc) as $kv) {
		list($k, $v) = explode('=', $kv, 2);
		if ($k === 'class' || $k === 'tree') {
			$card[$k] = $v;
		} elseif ($k === 'level') {
			$card['level'] = (int)$v;
		} elseif ($k === 'spells') {
			$card['spells'] = array_map('intval', explode(',', $v));
		} elseif ($k === 'gear') {
			$card['gear'] = array();
			foreach (explode(',', $v) as $g) {
				list($s, $id) = explode(':', $g);
				$card['gear'][] = array('slot' => (int)$s, 'id' => (int)$id);
			}
		}
	}
	return $card;
}

// ---------------------------------------------------------------- shared vectors
$ok = 0;
$bad = 0;
$sample = '';
foreach (file($repo . '/docs/build_code_vectors.txt', FILE_IGNORE_NEW_LINES) as $line) {
	if ($line === '' || $line[0] === '#') {
		continue;
	}
	$p = explode('|', $line);
	if ($p[0] === 'ok') {
		$ok++;
		list(, $name, $desc, $code) = $p;
		$r = chaos_buildcode_decode($code);
		check(isset($r['card']), "$name: decodes (" . ($r['error'] ?? '') . ')');
		if (!isset($r['card'])) {
			continue;
		}
		check(chaos_buildcode_describe($r['card']) === $desc, "$name: text form\n  " . chaos_buildcode_describe($r['card']) . "\n  $desc");
		if (strpos($desc, 'skipped=') === false) {
			check((chaos_buildcode_encode(parse_desc($desc))['code'] ?? '') === $code, "$name: encode gives the same code");
		}
		$t = $r['card']['tree_info'] ?? null;
		if (is_array($t) && empty($t['newer'])) {
			// the site's tree encoder writes the server's own code (buildshare_core.lua B.encode)
			check(chaos_buildcode_tree_encode($t, $t['version']) === $r['card']['tree'], "$name: tree code as the server writes it");
		}
		if ($name === 'deadeye 600') {
			$sample = $code;
		}
	} elseif ($p[0] === 'bad') {
		$bad++;
		$r = chaos_buildcode_decode($p[2]);
		check(!isset($r['card']) && ($r['error'] ?? '') === $p[1], 'bad ' . $p[2] . ': ' . ($r['error'] ?? 'decoded') . ' (want ' . $p[1] . ')');
	}
}
check($ok >= 8 && $bad >= 15, "vectors read: $ok ok, $bad bad");

// ---------------------------------------------------------------- typos
$alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
$passed = 0;
for ($i = 4; $i < strlen($sample); $i++) {
	for ($k = 0; $k < 64; $k += 7) {
		if ($alpha[$k] !== $sample[$i] && isset(chaos_buildcode_decode(substr($sample, 0, $i) . $alpha[$k] . substr($sample, $i + 1))['card'])) {
			$passed++;
		}
	}
}
check($passed === 0, 'every one-character change refused');
check(chaos_buildcode_extract('look [build ' . $sample . '] here') === $sample, 'extract from a chat line');

// ---------------------------------------------------------------- the same tables as the client and the server
$lua = (string)file_get_contents($repo . '/client/overlay/modules/game_passivetree/buildcode.lua');
preg_match_all("/\{'([a-z]+)', (\d+), '([A-Za-z ]+)'\}/", $lua, $m, PREG_SET_ORDER);
$fromLua = array();
foreach ($m as $i => $x) {
	$fromLua[$i + 1] = array($x[1], (int)$x[2], $x[3]);
}
check($fromLua === chaos_buildcode_classes(), 'the class table is the client codec\'s');
foreach (chaos_buildcode_classes() as $c) {
	check(chaos_class_name($c[1]) === $c[2], 'class name of vocation ' . $c[1] . ' as lib.php');
	check(chaos_buildcode_class_of_vocation($c[1]) === $c[0], 'class of vocation ' . $c[1]);
}
check(chaos_buildcode_class_of_vocation(2) === 'mystic', 'a retired vocation follows its new class');
check(preg_match("/C\.GEAR_SLOTS = \{([0-9, ]+)\}/", $lua, $g) === 1 && $g[1] === implode(', ', array_keys(chaos_buildcode_slots())), 'gear slots as the client');
$core = (string)file_get_contents($repo . '/server/data/scripts/chaos/buildshare_core.lua');
check(preg_match('/B\.PARAGON_KEYS = \{([^}]*)\}/', $core, $pk) === 1
	&& str_replace(array('"', ' '), '', $pk[1]) === implode(',', chaos_buildcode_paragon_keys()), 'Paragon keys as the server');
check(preg_match('/B\.VERSION = (\d+)/', $core, $bv) === 1 && (int)$bv[1] === CHAOS_BUILDCODE_TREE_LAYOUT_MAX, 'tree layouts up to the server\'s tree code version');
check(preg_match('/B\.CLASS_LINES = \{"warrior", "ranger", "mystic", "thief"\}/', $core) === 1
	&& chaos_buildcode_tree_lines() === array(4 => 1, 3 => 2, 1 => 3, 11 => 4), 'tree class lines as the server');

// encode cleaning
$r = chaos_buildcode_decode(chaos_buildcode_encode(array('spells' => array(5, 5, 0, -1, 70000, 'x', 6),
	'gear' => array(array('slot' => 10, 'id' => 9), array('slot' => 3, 'id' => 8), array('slot' => 1, 'id' => 7))))['code']);
check($r['card']['spells'] === array(5, 6) && count($r['card']['gear']) === 2 && $r['card']['gear'][0]['slot'] === 1, 'bad entries dropped, gear in slot order');
check((chaos_buildcode_encode(array('class' => 'paladin'))['error'] ?? '') === 'class', 'an unknown class');
check((chaos_buildcode_encode(array('tree' => 'CB6-AwCRDq5'))['error'] ?? '') === 'tree', 'a damaged tree code');

// ---------------------------------------------------------------- item names
$csvRow = null;
foreach (array_slice(file($repo . '/server/data/items/base_item_names.csv', FILE_IGNORE_NEW_LINES), 1) as $l) {
	$f = str_getcsv($l, ',', '"', '');
	if (chaos_wiki_entry('unique:' . $f[0]) === null) {
		$csvRow = $f;
		break;
	}
}
check($csvRow !== null && chaos_item_name((int)$csvRow[0]) === ucfirst($csvRow[2]), 'a name from base_item_names.csv');
check(chaos_item_name(28693) === 'Fletcher\'s First Sheath', 'a unique of a stock id takes its wiki name');
check(chaos_item_name(2466) === 'Aetherbound Plate', 'a unique\'s name from the wiki');
check(chaos_item_name(1) === 'item 1', 'an unknown id');
$tmp = sys_get_temp_dir() . '/chaos_build_test_' . getmypid();
@mkdir($tmp . '/items', 0700, true);
file_put_contents($tmp . '/items/items.xml', '<items><item id="100" article="a" name="void stone &amp; ash"/><item fromid="200" toid="202" name="ember"><attribute key="x" value="1"/></item><item id="28693" name="better quiver"/></items>');
$GLOBALS['config']['chaos']['server_data'] = $tmp;
$names = chaos_item_names(true);
check(($names[100] ?? '') === 'void stone & ash' && ($names[201] ?? '') === 'ember' && ($names[28693] ?? '') === 'better quiver', 'items.xml: ids, ranges, entities');
$GLOBALS['config']['chaos']['server_data'] = $repo . '/server/data';
chaos_item_names(true);
array_map('unlink', glob($tmp . '/items/*'));
@rmdir($tmp . '/items');
@rmdir($tmp);

// ---------------------------------------------------------------- the page
function render_build(array $get): array {
	global $config;
	$_GET = $get;
	$GLOBALS['page_title'] = '';
	$GLOBALS['page_description'] = '';
	http_response_code(200);
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/build.php';
	return array((string)ob_get_clean(), (int)http_response_code(), $GLOBALS['page_title'], $GLOBALS['page_description']);
}
list($html, $status, $title, $desc) = render_build(array('plugin' => 'chaos', 'p' => 'build', 'c' => $sample));
check($status === 200 && $title === 'Deadeye, level 600 - Build', 'title: ' . $title);
check(strpos($desc, 'Deadeye, level 600 build: 42 passive points, 3 spells, 4 items') !== false, 'description: ' . $desc);
check(strpos($html, 'Reaping Gyre') !== false && strpos($html, 'Town Portal') !== false, 'spell names from the wiki');
check(strpos($html, 'p=wiki&amp;t=spell%3A254') !== false && strpos($html, 'sp-280.png') !== false, 'a spell links its wiki entry with its icon');
check(strpos($html, 'Aetherbound Plate') !== false && strpos($html, 'Right hand') !== false, 'gear names and slots');
check(preg_match('/<strong class="chaos-gold">42<\/strong> passive points/', $html) === 1, 'points counted');
check(strpos($html, '(Ranger line)') !== false, 'the class line');
$e542 = chaos_build_tree_entry(542, 'Deadeye');
check($e542 !== null && strpos($html, chaos_h($e542['name'])) !== false, 'a keystone named from the wiki');
check(strpos($html, 'value="' . $sample . '"') !== false && strpos($html, 'page?plugin=chaos&amp;p=build&amp;c=' . $sample) !== false, 'share link and code');
list($html, $status) = render_build(array('c' => '<script>alert(1)</script>'));
check($status === 404 && strpos($html, '<script>alert') === false && strpos($html, '&lt;script&gt;') !== false, 'a bad code: 404, escaped in the form');
check(strpos($html, 'That is not a full build code') !== false, 'the error text');
list($html, $status) = render_build(array('c' => 'CC1-AQABBUcNGQ'));
check(strpos($html, 'checksum does not match') !== false, 'a typo: the checksum text');
list($html, $status, $title) = render_build(array());
check($status === 200 && $title === 'Build' && strpos($html, 'Copy Full Build') !== false && strpos($html, 'chaos-error') === false, 'no code: the form and how to make one');
list($html) = render_build(array('c' => 'CC1-AQABEQMACAkDAAQCcDpubK5y'));
check(strpos($html, 'newer format than this site reads') !== false && strpos($html, 'Lich') !== false, 'a newer tree code');
foreach (array('build.php', '../buildcode_lib.php') as $f) {
	$text = (string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/pages/' . $f);
	check(strpos($text, "\u{2014}") === false && strpos($text, "\u{2013}") === false, "$f: no dashes");
}

// ---------------------------------------------------------------- link preview
$seo = chaos_seo_page(array('page' => 'page_chaos_build', 'get' => array('plugin' => 'chaos', 'p' => 'build', 'c' => $sample, 'x' => 'y'),
	'page_title' => 'Deadeye, level 600 - Build', 'page_description' => 'A Deadeye build.', 'lang' => 'en',
	'site' => array('name' => 'Cinders of Chaos', 'url' => 'https://example.test', 'discord' => '', 'favicon' => '')));
check($seo['description'] === 'A Deadeye build.' && $seo['og_title'] === 'Deadeye, level 600 - Build', 'the page\'s own description and title');
check($seo['canonical'] === 'https://example.test/page?plugin=chaos&p=build&c=' . $sample, 'canonical keeps the code: ' . $seo['canonical']);
$seo = chaos_seo_page(array('page' => 'page_chaos_build', 'get' => array(), 'lang' => 'pt-BR', 'status' => 404,
	'site' => array('name' => 'Cinders of Chaos', 'url' => 'https://example.test', 'discord' => '', 'favicon' => '')));
check(strpos($seo['robots'], 'noindex') === 0 && strpos($seo['description'], 'Uma build compartilhada') === 0, 'a bad code is not indexed; the default description in Portuguese');

echo $fails ? implode("\n", $fails) . "\n" : '';
echo $failed === 0 ? "chaos_build_page_test: OK ($checks checks)\n" : "chaos_build_page_test: $failed of $checks failed\n";
exit($failed === 0 ? 0 : 1);
