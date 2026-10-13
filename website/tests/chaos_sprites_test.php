<?php
// php website/tests/chaos_sprites_test.php : the sprite images of plugins/chaos/sprite_lib.php and chaos_outfit.php
// (README "Sprite images"): the item and outfit URLs, the placeholder fallback for art that is not ours, the request
// values, the colour table, the outfit drawing on a hand-made sheet (template colours, addons, mount), the cache, the
// wiki's real sprites, the config and the highscores column. php-cli with zlib only (no gd); no pair, no database.
require __DIR__ . '/../overlay/plugins/chaos/sprite_lib.php';
require __DIR__ . '/../overlay/plugins/chaos/wiki_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}
set_error_handler(static function (int $no, string $msg, string $file, int $line): bool {
	check(false, "no PHP notices or warnings: $msg ($file:$line)");
	return true;
});

$tmp = sys_get_temp_dir() . '/chaos_sprites_test_' . getmypid();
@mkdir($tmp . '/out/items', 0755, true);
@mkdir($tmp . '/out/outfits', 0755, true);
register_shutdown_function(static function () use ($tmp): void { exec('rm -rf ' . escapeshellarg($tmp)); });

// ---------------------------------------------------------------- no images on the site
chaos_sprite_root($tmp . '/none');
check(!chaos_sprites_on(), 'no index.json: images off');
check(chaos_item_url(2466) === '', 'no images: no item URL');
check(!chaos_item_published(2466) && !chaos_outfit_published(2073), 'no images: nothing published');
[$png, $src] = chaos_outfit_image(array('id' => '2073'));
check($png === '' && $src === 'placeholder', 'no images: no outfit image (404)');

// ---------------------------------------------------------------- a hand-made set
$canvas = static function (int $w, int $h, array $px): array {
	$c = array_fill(0, $h, array_fill(0, $w, array(0, 0, 0, 0)));
	foreach ($px as [$x, $y, $r, $g, $b, $a]) {
		$c[$y][$x] = array($r, $g, $b, $a);
	}
	return $c;
};
$png = static function (int $w, int $h, array $px) use ($canvas): string {
	return chaos_sprite_png($canvas($w, $h, $px));
};
// a .raw sheet as gen_sprite_images.py save_raw() writes it: zlib(u16 width, u16 height, RGBA rows)
$raw = static function (int $w, int $h, array $px) use ($canvas): string {
	$bytes = '';
	foreach ($canvas($w, $h, $px) as $row) {
		foreach ($row as $c) {
			$bytes .= pack('C4', ...$c);
		}
	}
	return (string)gzcompress(pack('vv', $w, $h) . $bytes, 9);
};
// [width, height, rows of [r, g, b, a]] of a PNG written by chaos_sprite_png (8-bit RGBA, filter 0)
$decode = static function (string $png): array {
	$p = 8; $idat = ''; $w = $h = 0;
	while ($p < strlen($png)) {
		$len = unpack('N', substr($png, $p, 4))[1]; $type = substr($png, $p + 4, 4); $data = substr($png, $p + 8, $len);
		check(unpack('N', substr($png, $p + 8 + $len, 4))[1] === crc32($type . $data), "PNG chunk $type CRC");
		if ($type === 'IHDR') { $wh = unpack('Nw/Nh', $data); $w = $wh['w']; $h = $wh['h']; }
		if ($type === 'IDAT') { $idat .= $data; }
		$p += 12 + $len;
	}
	$bytes = (string)gzuncompress($idat);
	$rows = array();
	for ($y = 0; $y < $h; $y++) {
		$line = substr($bytes, $y * (1 + 4 * $w), 1 + 4 * $w);
		check($line[0] === "\0", 'PNG row filter 0');
		$rows[] = array_chunk(array_values(unpack('C*', substr($line, 1))), 4);
	}
	return array($w, $h, $rows);
};
$out = $tmp . '/out';
file_put_contents("$out/placeholder-item.png", $png(32, 32, array(array(5, 5, 44, 40, 42, 255))));
file_put_contents("$out/placeholder-outfit.png", $png(64, 64, array(array(40, 40, 58, 54, 56, 255))));
// look 10: 1x1, 3 addon patterns, 2 mount patterns, a template; column = z * 3 + y, row 0 art, row 1 template
$px = array();
foreach (array(0, 3) as $c0) {                       // z 0 and z 1 (mounted) draw the same, z 1 one pixel lower
	$dy = $c0 ? 1 : 0;
	$px[] = array($c0 * 32 + 0, 0 + $dy, 200, 100, 50, 255);   $px[] = array($c0 * 32 + 0, 32 + $dy, 255, 255, 0, 255); // head
	$px[] = array($c0 * 32 + 1, 0 + $dy, 200, 100, 50, 255);   $px[] = array($c0 * 32 + 1, 32 + $dy, 255, 0, 0, 255);   // body
	$px[] = array($c0 * 32 + 2, 0 + $dy, 200, 100, 50, 255);   $px[] = array($c0 * 32 + 2, 32 + $dy, 0, 255, 0, 255);   // legs
	$px[] = array($c0 * 32 + 3, 0 + $dy, 200, 100, 50, 255);   $px[] = array($c0 * 32 + 3, 32 + $dy, 0, 0, 255, 255);   // feet
	$px[] = array($c0 * 32 + 4, 0 + $dy, 200, 100, 50, 255);   $px[] = array($c0 * 32 + 4, 32 + $dy, 254, 254, 0, 255); // not a template colour
	$px[] = array(($c0 + 1) * 32 + 5, 0 + $dy, 10, 20, 30, 255);   // addon 1
	$px[] = array(($c0 + 2) * 32 + 6, 0 + $dy, 40, 50, 60, 255);   // addon 2
}
file_put_contents("$out/outfits/10.raw", $raw(6 * 32, 64, $px));
// look 20: a 1x1 mount with a negative displacement (-16, -16), no seat; look 30: not ours (no sheet)
file_put_contents("$out/outfits/20.raw", $raw(32, 32, array(array(31, 31, 9, 9, 9, 255))));
$index = array('version' => 1, 'stamp' => 'abcdef0123456789', 'publish' => array('own', 'donor'),
	'items' => array('2466' => '', '27990' => 'c', '2006' => 'f'),
	'outfits' => array('10' => array(1, 1, 0, 0, 3, 2, 2, 0, 0, 0, 0), '20' => array(1, 1, -16, -16, 1, 1, 1, 1, 0, 0, 0)));
file_put_contents("$out/index.json", json_encode($index));
chaos_sprite_root($out);
check(chaos_sprites_on(), 'index.json read');

// ---------------------------------------------------------------- item URLs and the placeholder
check(chaos_item_url(2466) === '/chaos-sprites/items/2466.png', 'our item');
check(chaos_item_url(2400) === '/chaos-sprites/placeholder-item.png', 'an item that is not ours: the placeholder');
check(chaos_item_url(-5) === '/chaos-sprites/placeholder-item.png', 'a bad id: the placeholder');
$stacks = array(1 => '', 2 => '-c2', 4 => '-c4', 5 => '-c5', 9 => '-c5', 10 => '-c10', 24 => '-c10', 25 => '-c25', 49 => '-c25', 50 => '-c50', 100 => '-c50');
foreach ($stacks as $n => $suffix) {
	check(chaos_item_url(27990, $n) === "/chaos-sprites/items/27990$suffix.png", "stack of $n");
}
check(chaos_item_url(2466, 50) === '/chaos-sprites/items/2466.png', 'count on a non-stackable item: the item');
check(chaos_item_url(2006, 1, 2) === '/chaos-sprites/items/2006-f2.png', 'fluid colour 2');
check(chaos_item_url(2006, 1, 0) === '/chaos-sprites/items/2006.png' && chaos_item_url(2006, 1, 9) === '/chaos-sprites/items/2006.png', 'empty or bad fluid: the item');

// ---------------------------------------------------------------- outfit URLs and request values
check(chaos_outfit_url(10, 3, 1, 2, 3, 4) === '/chaos_outfit.php?id=10&addons=3&head=1&body=2&legs=3&feet=4', 'outfit URL');
check(chaos_outfit_url(10, 9, 500, -1, 3, 4, 20) === '/chaos_outfit.php?id=10&addons=0&head=78&body=69&legs=3&feet=4&mount=20', 'outfit URL: clamped values');
$p = chaos_outfit_params(array('id' => '10<script>', 'addons' => array('1'), 'head' => '132', 'body' => '133', 'legs' => '0x10', 'feet' => ' 5', 'mount' => '99999999'));
check($p === array('id' => 0, 'addons' => 0, 'head' => 132, 'body' => 69, 'legs' => 58, 'feet' => 76, 'mount' => 0), 'request values: only plain numbers in range');
check(chaos_outfit_params(array())['id'] === 0, 'no id');

// ---------------------------------------------------------------- the colour table (gen_sprite_images_test.py has the same values)
check(chaos_outfit_colour(0) === array(255, 255, 255), 'colour 0 white');
check(chaos_outfit_colour(1) === array(255, 212, 191), 'colour 1 ffd4bf');
check(chaos_outfit_colour(19) === array(218, 218, 218), 'colour 19 grey');
check(chaos_outfit_colour(114) === array(36, 36, 36), 'colour 114 darkest grey');
check(chaos_outfit_colour(133) === chaos_outfit_colour(0) && chaos_outfit_colour(-3) === chaos_outfit_colour(0), 'out of range: colour 0');
$py = json_decode('[[255,255,255],[255,212,191],[255,233,191],[255,255,191],[233,255,191],[212,255,191],[191,255,191],[191,255,212],[191,255,233],[191,255,255],[191,233,255],[191,212,255],[191,191,255],[212,191,255],[233,191,255],[255,191,255],[255,191,233],[255,191,212],[255,191,191]]', true);
for ($c = 0; $c < 19; $c++) {
	check(chaos_outfit_colour($c) === $py[$c], "colour $c as the client's table");
}

// ---------------------------------------------------------------- drawing a look from its sheet
$pixel = static function (string $bytes, int $x, int $y) use ($decode): array {
	return $decode($bytes)[2][$y][$x];
};
[$img, $src] = chaos_outfit_image(array('id' => '10', 'head' => '1', 'body' => '19', 'legs' => '114', 'feet' => '0'));
check($src === 'render', 'our look is drawn');
$mul = static function (array $rgb, int $c): array {
	$k = chaos_outfit_colour($c);
	return array(intdiv($rgb[0] * $k[0] + 127, 255), intdiv($rgb[1] * $k[1] + 127, 255), intdiv($rgb[2] * $k[2] + 127, 255), 255);
};
$art = array(200, 100, 50);
check($pixel($img, 0, 0) === $mul($art, 1), 'head part x colour 1');
check($pixel($img, 1, 0) === $mul($art, 19), 'body part x colour 19');
check($pixel($img, 2, 0) === $mul($art, 114), 'legs part x colour 114');
check($pixel($img, 3, 0) === array(200, 100, 50, 255), 'feet part x white: unchanged');
check($pixel($img, 4, 0) === array(200, 100, 50, 255), 'an inexact template colour is left alone');
check($pixel($img, 5, 0)[3] === 0 && $pixel($img, 6, 0)[3] === 0, 'no addons without addons');
[$img] = chaos_outfit_image(array('id' => '10', 'addons' => '1'));
check($pixel($img, 5, 0) === array(10, 20, 30, 255) && $pixel($img, 6, 0)[3] === 0, 'addon 1 only');
[$img] = chaos_outfit_image(array('id' => '10', 'addons' => '3'));
check($pixel($img, 5, 0)[3] === 255 && $pixel($img, 6, 0) === array(40, 50, 60, 255), 'both addons');
// a mount of ours: the mounted pattern (one pixel lower) and the mount drawn by its own displacement
[$img, $src] = chaos_outfit_image(array('id' => '10', 'mount' => '20', 'head' => '0', 'body' => '0', 'legs' => '0', 'feet' => '0'));
[$iw, $ih] = $decode($img);
check($src === 'render' && $iw === 48 && $ih === 48, "mounted: canvas covers rider and mount ({$iw}x{$ih})");
check($pixel($img, 47, 47) === array(9, 9, 9, 255), 'mount pixel at its place');
check($pixel($img, 0, 1) === array(200, 100, 50, 255) && $pixel($img, 0, 0)[3] === 0, 'rider in its mounted pattern');
// a half-transparent pixel keeps its 8-bit alpha (no gd round trip), as gen_sprite_images.py writes it
file_put_contents("$out/outfits/20.raw", $raw(32, 32, array(array(31, 31, 9, 9, 9, 255), array(30, 31, 90, 60, 30, 101))));
[$img] = chaos_outfit_image(array('id' => '10', 'mount' => '20'));
check($pixel($img, 46, 47) === array(90, 60, 30, 101), 'alpha 101 kept exactly');
check(chaos_outfit_place(array(2, 2, 8, 8, 3, 2, 2, 0, 0, 0, 0), array(3, 4, -32, -32, 1, 1, 1, 1, 1, 14, -2)) === array(array(-26, -42), array(-32, -64), 1),
	'a donor mount with a rider seat (base patch 0034): same as gen_sprite_images.py');
// measured in our client (website/README.md "Sprite images"): frame top-left of rider and mount, facing south
$measured = array(
	array(array(2, 2, 8, 8, 3, 2, 2, 0, 0, 0, 0), array(3, 4, -32, -32, 1, 2, 1, 1, 1, 14, -2), array(-26, -42), array(-32, -64)),   // 2073 on 2133
	array(array(2, 2, 8, 8, 3, 2, 2, 0, 0, 0, 0), array(5, 4, -64, -32, 1, 2, 1, 1, 1, 14, -10), array(-26, -50), array(-64, -64)),  // 2073 on 2134
	array(array(2, 2, 8, 8, 3, 2, 2, 0, 0, 0, 0), array(3, 5, -32, -32, 1, 2, 1, 1, 1, 14, -8), array(-26, -48), array(-32, -96)),   // 2073 on 2135
	array(array(2, 2, 8, 8, 3, 2, 2, 0, 0, 0, 0), array(2, 2, 0, 0, 1, 1, 1, 0, 0, 0, 0), array(-32, -32), array(-32, -32)),         // 2073 on stock 368
);
foreach ($measured as $k => [$rider, $mount, $rxy, $mxy]) {
	[$r, $m] = chaos_outfit_place($rider, $mount);
	check($r === $rxy && $m === $mxy, "client measurement $k: rider " . implode(',', $r) . ' mount ' . implode(',', $m));
}
// a mount that is not ours is left out; a look that is not ours is the placeholder
[$img, $src] = chaos_outfit_image(array('id' => '10', 'mount' => '30'));
check($src === 'render' && $decode($img)[0] === 32, 'a mount that is not ours: drawn on foot');
[$img, $src] = chaos_outfit_image(array('id' => '30'));
check($src === 'placeholder' && $pixel($img, 40, 40) === array(58, 54, 56, 255), 'a look that is not ours: the placeholder');
[$img, $src] = chaos_outfit_image(array('id' => 'abc'));
check($src === 'placeholder', 'a bad id: the placeholder');

// ---------------------------------------------------------------- the cache
$cache = $tmp . '/cache';
[$a, $src] = chaos_outfit_image(array('id' => '10', 'head' => '5'), $cache);
check($src === 'render' && count(glob("$cache/*.png")) === 1, 'rendered and cached');
[$b, $src] = chaos_outfit_image(array('id' => '10', 'head' => '5'), $cache);
check($src === 'cache' && $a === $b, 'second request from the cache');
[, $src] = chaos_outfit_image(array('id' => '30'), $cache);
check(count(glob("$cache/*.png")) === 1, 'placeholders are not cached');

// ---------------------------------------------------------------- wiki: the real sprite only when it is ours
$e = array('name' => 'Aetherbound Plate', 'icon' => 'wiki/i/it-sunsworn-armor.png', 'sprite' => array('item' => 2466));
$html = chaos_wiki_icon($e, 64, 'chaos-wiki-entry__icon');
check(strpos($html, 'src="/chaos-sprites/items/2466.png"') !== false && strpos($html, 'chaos-sprite') !== false, 'wiki: our sprite');
$e['sprite'] = array('item' => 2400);
check(strpos(chaos_wiki_icon($e, 64), 'it-sunsworn-armor.png') !== false, 'wiki: not ours: the themed icon');
$e['sprite'] = array('outfit' => 10, 'addons' => 3);
check(strpos(chaos_wiki_icon($e, 32), 'src="/chaos_outfit.php?id=10&amp;addons=3') !== false, 'wiki: our look with its addons');
$e['sprite'] = array('item' => '2466');
check(strpos(chaos_wiki_icon($e, 64), 'it-sunsworn-armor.png') !== false, 'wiki: a sprite reference must be a number');
$entry = array('id' => 'store:9', 'name' => 'Supplies', 'sections' => array(array('h' => 'Offers', 'cols' => array('Offer', 'Coins'),
	'rows' => array(array('Plate', '10'), array('Potion <b>', '5')), 'sprites' => array(array('item' => 2466), false))));
$html = chaos_wiki_entry_html($entry, 'en');
check(substr_count($html, '<img') === 1 && strpos($html, 'items/2466.png') !== false && strpos($html, 'Potion &lt;b&gt;') !== false, 'wiki store rows: a sprite where there is one');
$data = json_decode((string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/wiki/wiki_data.json'), true);
$uniques = $sets = $rows = 0;
foreach ($data['tabs'] as $tab) {
	foreach ($tab['entries'] as $en) {
		if ($tab['id'] === 'uniques') { $uniques += (int)(($en['sprite']['item'] ?? 0) === (int)substr($en['id'], 7)); }
		if ($tab['id'] === 'sets') { $sets += (int)is_int($en['sprite']['item'] ?? null); }
		foreach ($en['sections'] ?? array() as $s) {
			if (isset($s['sprites'])) { $rows += (int)(count($s['sprites']) === count($s['rows'])); }
		}
	}
}
check($uniques > 100 && $sets >= 8 && $rows > 5, "wiki data: every unique and every set made of uniques names its sprite ($uniques, $sets, $rows)");

// ---------------------------------------------------------------- config and views
$wc = (string)file_get_contents(__DIR__ . '/../setup/write_config.php');
check(strpos($wc, "'imageServer' => '/chaos_outfit.php'") !== false && strpos($wc, "\\\$config['shop']['imageServer'] = '/chaos-sprites/items'") !== false,
	'config: ZnoteX outfit and item images point at ours');
check(strpos($wc, "env('CHAOS_SPRITES') === '1'") !== false, 'config: images on only when the set is installed');
$inst = (string)file_get_contents(__DIR__ . '/../install_site.sh');
check(strpos($inst, 'gen_sprite_images.py') !== false && strpos($inst, 'CHAOS_SPRITE_PUBLISH') !== false, 'installer builds the set');
$hs = (string)file_get_contents(__DIR__ . '/../overlay/layouts/chaos/views/highscores.php');
check(strpos($hs, 'chaos_outfit_url(') !== false && strpos($hs, '$showLooks') !== false, 'highscores: outfit column');
$ep = (string)file_get_contents(__DIR__ . '/../overlay/chaos_outfit.php');
check(strpos($ep, 'chaos_outfit_serve($_GET)') !== false && strpos($ep, 'engine/init') === false, 'endpoint loads no ZnoteX');

echo $failed === 0 ? "chaos_sprites_test: OK ($checks checks)\n" : "chaos_sprites_test: $failed of $checks failed\n";
exit($failed === 0 ? 0 : 1);
