<?php
// php website/tests/chaos_sprites_test.php : the sprite images of plugins/chaos/sprite_lib.php and chaos_outfit.php
// (README "Sprite images"): the item and outfit URLs, the placeholder fallback for art that is not ours, the request
// values, the colour table, the outfit drawing on a hand-made sheet (template colours, addons, mount), the cache, the
// wiki's real sprites, the config and the highscores column. php-cli with gd; no pair, no database.
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
$png = static function (int $w, int $h, array $px): string {
	$im = imagecreatetruecolor($w, $h);
	imagealphablending($im, false);
	imagesavealpha($im, true);
	imagefill($im, 0, 0, 127 << 24);
	foreach ($px as [$x, $y, $r, $g, $b, $a]) {
		imagesetpixel($im, $x, $y, ((127 - intdiv($a * 127, 255)) << 24) | ($r << 16) | ($g << 8) | $b);
	}
	ob_start();
	imagepng($im);
	return (string)ob_get_clean();
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
file_put_contents("$out/outfits/10.png", $png(6 * 32, 64, $px));
file_put_contents("$out/outfits/10-d.png", $png(32, 32, array(array(0, 0, 1, 2, 3, 255))));
// look 20: a 1x1 mount with a negative displacement (-16, -16), no seat; look 30: not ours (no sheet)
file_put_contents("$out/outfits/20.png", $png(32, 32, array(array(31, 31, 9, 9, 9, 255))));
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
$pixel = static function (string $bytes, int $x, int $y): array {
	$im = imagecreatefromstring($bytes);
	$c = imagecolorat($im, $x, $y);
	return array(($c >> 16) & 255, ($c >> 8) & 255, $c & 255, 127 - (($c >> 24) & 127));
};
[$img, $src] = chaos_outfit_image(array('id' => '10', 'head' => '1', 'body' => '19', 'legs' => '114', 'feet' => '0'));
check($src === 'render', 'our look is drawn');
$mul = static function (array $rgb, int $c): array {
	$k = chaos_outfit_colour($c);
	return array(intdiv($rgb[0] * $k[0] + 127, 255), intdiv($rgb[1] * $k[1] + 127, 255), intdiv($rgb[2] * $k[2] + 127, 255), 127);
};
$art = array(200, 100, 50);
check($pixel($img, 0, 0) === $mul($art, 1), 'head part x colour 1');
check($pixel($img, 1, 0) === $mul($art, 19), 'body part x colour 19');
check($pixel($img, 2, 0) === $mul($art, 114), 'legs part x colour 114');
check($pixel($img, 3, 0) === array(200, 100, 50, 127), 'feet part x white: unchanged');
check($pixel($img, 4, 0) === array(200, 100, 50, 127), 'an inexact template colour is left alone');
check($pixel($img, 5, 0)[3] === 0 && $pixel($img, 6, 0)[3] === 0, 'no addons without addons');
[$img] = chaos_outfit_image(array('id' => '10', 'addons' => '1'));
check($pixel($img, 5, 0) === array(10, 20, 30, 127) && $pixel($img, 6, 0)[3] === 0, 'addon 1 only');
[$img] = chaos_outfit_image(array('id' => '10', 'addons' => '3'));
check($pixel($img, 5, 0)[3] === 127 && $pixel($img, 6, 0) === array(40, 50, 60, 127), 'both addons');
// a mount of ours: the mounted pattern (one pixel lower) and the mount drawn by its own displacement
[$img, $src] = chaos_outfit_image(array('id' => '10', 'mount' => '20', 'head' => '0', 'body' => '0', 'legs' => '0', 'feet' => '0'));
$im = imagecreatefromstring($img);
check($src === 'render' && imagesx($im) === 48 && imagesy($im) === 48, 'mounted: canvas covers rider and mount (' . imagesx($im) . 'x' . imagesy($im) . ')');
check($pixel($img, 47, 47) === array(9, 9, 9, 127), 'mount pixel at its place');
check($pixel($img, 0, 1) === array(200, 100, 50, 127) && $pixel($img, 0, 0)[3] === 0, 'rider in its mounted pattern');
check(chaos_outfit_place(array(2, 2, 8, 8, 3, 2, 2, 0, 0, 0, 0), array(3, 4, -32, -32, 1, 1, 1, 1, 1, 14, -2)) === array(array(-26, -42), array(-32, -64), 1),
	'a donor mount with a rider seat (base patch 0034): same as gen_sprite_images.py');
// a mount that is not ours is left out; a look that is not ours is the placeholder
[$img, $src] = chaos_outfit_image(array('id' => '10', 'mount' => '30'));
check($src === 'render' && imagesx(imagecreatefromstring($img)) === 32, 'a mount that is not ours: drawn on foot');
[$img, $src] = chaos_outfit_image(array('id' => '30'));
check($src === 'placeholder' && $pixel($img, 40, 40) === array(58, 54, 56, 127), 'a look that is not ours: the placeholder');
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
