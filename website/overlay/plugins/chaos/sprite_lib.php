<?php
/**
 * Item and outfit images from our own client pair (website/README.md "Sprite images").
 *
 * website/tools/gen_sprite_images.py writes <site>/chaos-sprites/ at install time (install_site.sh, CHAOS_SPRITE_PAIR):
 * items/<server id>.png (and -c<n> stack, -f<k> fluid variants), outfits/<look>.png layer sheets, outfits/<look>-d.png
 * default renders, two placeholders and index.json. Only the tiers the owner publishes are drawn (CHAOS_SPRITE_PUBLISH,
 * website/tools/sprite_owners.csv); every other item or look is a neutral placeholder. This file never reads the pair.
 *
 * chaos_outfit.php (site root, ZnoteX's show_outfits imageServer) draws a look with the player's colours, addons and
 * mount from the sheets: the same maths as gen_sprite_images.py tint() / place() / compose() (the client's own drawing:
 * exact template colours, multiply, addon patterns over pattern 0). Needs PHP's gd; without it the default render.
 * Rendered images are cached in engine/cache/chaos-outfits/ (at most CHAOS_SPRITE_CACHE_MAX files).
 */

const CHAOS_SPRITE_URL = '/chaos-sprites';
const CHAOS_OUTFIT_URL = '/chaos_outfit.php';
const CHAOS_SPRITE_CACHE_MAX = 20000;
const CHAOS_OUTFIT_DEFAULT = array(78, 69, 58, 76);
const CHAOS_OUTFIT_MASK = array(array(255, 255, 0), array(255, 0, 0), array(0, 255, 0), array(0, 0, 255));
const CHAOS_ITEM_STACKS = array(50, 25, 10, 5, 4, 3, 2);

/** The chaos-sprites folder (<site>/chaos-sprites); a test may point it elsewhere. */
function chaos_sprite_root(?string $set = null): string {
	static $root = null;
	if ($set !== null) {
		$root = rtrim($set, '/');
		chaos_sprite_index(true);
	}
	return $root ?? dirname(__DIR__, 2) . '/chaos-sprites';
}

/** index.json of the built images, or null when the site has none (images off). */
function chaos_sprite_index(bool $reload = false): ?array {
	static $index = false;
	if ($reload) {
		$index = false;
	}
	if ($index === false) {
		$path = chaos_sprite_root() . '/index.json';
		$raw = is_file($path) ? @file_get_contents($path) : false;
		$data = is_string($raw) ? json_decode($raw, true) : null;
		$index = (is_array($data) && isset($data['items'], $data['outfits'], $data['stamp'])) ? $data : null;
	}
	return $index;
}

function chaos_sprites_on(): bool {
	return chaos_sprite_index() !== null;
}

/** True when the item (server id) is drawn from our art; false for a placeholder or an unknown id. */
function chaos_item_published(int $sid): bool {
	$i = chaos_sprite_index();
	return $i !== null && array_key_exists((string)$sid, $i['items']);
}

/** True when the look is drawn from our art. */
function chaos_outfit_published(int $look): bool {
	$i = chaos_sprite_index();
	return $i !== null && isset($i['outfits'][(string)$look]);
}

/** The URL of an item image: its stack (count) or fluid (client colour 1..8) variant when it has one; the placeholder
 *  for an item that is not ours or not known; '' when the site has no images. */
function chaos_item_url(int $sid, int $count = 1, ?int $fluid = null): string {
	$i = chaos_sprite_index();
	if ($i === null) {
		return '';
	}
	if (!chaos_item_published($sid)) {
		return CHAOS_SPRITE_URL . '/placeholder-item.png';
	}
	$kind = (string)$i['items'][(string)$sid];
	$suffix = '';
	if ($kind === 'c' && $count > 1) {
		foreach (CHAOS_ITEM_STACKS as $n) {
			if ($count >= $n) {
				$suffix = '-c' . $n;
				break;
			}
		}
	} elseif ($kind === 'f' && $fluid !== null && $fluid >= 1 && $fluid <= 8) {
		$suffix = '-f' . $fluid;
	}
	return CHAOS_SPRITE_URL . '/items/' . $sid . $suffix . '.png';
}

/** An outfit request's values, each clamped to what the client accepts. */
function chaos_outfit_params(array $get): array {
	$int = static function ($v, int $lo, int $hi, int $def): int {
		if (is_int($v) || (is_string($v) && preg_match('/^\d{1,6}$/', $v))) {
			$n = (int)$v;
			return ($n >= $lo && $n <= $hi) ? $n : $def;
		}
		return $def;
	};
	return array(
		'id' => $int($get['id'] ?? null, 1, 65535, 0),
		'addons' => $int($get['addons'] ?? null, 0, 3, 0),
		'head' => $int($get['head'] ?? null, 0, 132, CHAOS_OUTFIT_DEFAULT[0]),
		'body' => $int($get['body'] ?? null, 0, 132, CHAOS_OUTFIT_DEFAULT[1]),
		'legs' => $int($get['legs'] ?? null, 0, 132, CHAOS_OUTFIT_DEFAULT[2]),
		'feet' => $int($get['feet'] ?? null, 0, 132, CHAOS_OUTFIT_DEFAULT[3]),
		'mount' => $int($get['mount'] ?? null, 0, 65535, 0),
	);
}

/** The URL of a look with its colours (ZnoteX's imageServer form: ?id=&addons=&head=&body=&legs=&feet=). */
function chaos_outfit_url(int $look, int $addons = 0, int $head = 78, int $body = 69, int $legs = 58, int $feet = 76, int $mount = 0): string {
	$p = chaos_outfit_params(array('id' => (string)$look, 'addons' => (string)$addons, 'head' => (string)$head,
		'body' => (string)$body, 'legs' => (string)$legs, 'feet' => (string)$feet, 'mount' => (string)$mount));
	$q = array('id' => $p['id'], 'addons' => $p['addons'], 'head' => $p['head'], 'body' => $p['body'], 'legs' => $p['legs'], 'feet' => $p['feet']);
	if ($p['mount'] > 0) {
		$q['mount'] = $p['mount'];
	}
	return CHAOS_OUTFIT_URL . '?' . http_build_query($q, '', '&');
}

/** The client's outfit colour (0..132) as [r, g, b]: 19 hues x 7 shades, column 0 greys (gen_sprite_images.py). */
function chaos_outfit_colour(int $c): array {
	if ($c < 0 || $c >= 133) {
		$c = 0;
	}
	if ($c % 19 === 0) {
		$g = (int)((1 - $c / 19 / 7) * 255);
		return array($g, $g, $g);
	}
	$h = ($c % 19) / 18.0;
	$sv = array(array(0.25, 1.0), array(0.25, 0.75), array(0.5, 0.75), array(0.667, 0.75), array(1.0, 1.0), array(1.0, 0.75), array(1.0, 0.5));
	[$s, $v] = $sv[intdiv($c, 19)];
	$seg = $h * 6;
	if ($h < 1 / 6) {
		$r = $v; $b = $v * (1 - $s); $g = $b + ($v - $b) * $seg;
	} elseif ($h < 2 / 6) {
		$g = $v; $b = $v * (1 - $s); $r = $g - ($v - $b) * ($seg - 1);
	} elseif ($h < 3 / 6) {
		$g = $v; $r = $v * (1 - $s); $b = $r + ($v - $r) * ($seg - 2);
	} elseif ($h < 4 / 6) {
		$b = $v; $r = $v * (1 - $s); $g = $b - ($v - $r) * ($seg - 3);
	} elseif ($h < 5 / 6) {
		$b = $v; $g = $v * (1 - $s); $r = $g + ($v - $g) * ($seg - 4);
	} else {
		$r = $v; $g = $v * (1 - $s); $b = $r - ($v - $g) * ($seg - 5);
	}
	return array((int)($r * 255), (int)($g * 255), (int)($b * 255));
}

function chaos_sprite_s16(int $v): int {
	$v &= 0xFFFF;
	return $v >= 32768 ? $v - 65536 : $v;
}

/** [rider [x, y], mount [x, y] or null, z pattern]: the frames' top-left relative to the tile, facing south
 *  (gen_sprite_images.py place(); meta = [w, h, dx, dy, py, pz, layers, negative, bones, bx, by]). */
function chaos_outfit_place(array $rider, ?array $mount): array {
	[$w, $h, $dx, $dy, , $pz, , $neg, $bones, $bx, $by] = $rider;
	$z = ($mount !== null && $pz > 1) ? 1 : 0;
	if (!$z) {
		return array(array(-$dx - ($w - 1) * 32, -$dy - ($h - 1) * 32), null, 0);
	}
	[$mw, $mh, $mdx, $mdy, , , , $mneg, $mbones, $mbx, $mby] = $mount;
	$x = 0; $y = 0;
	if (!$mneg) {
		$x -= $mdx; $y -= $mdy;
	}
	$mx = $x; $my = $y;
	if ($bones && $mbones) {
		$bonus = abs($mw - $w) * 32;
		$mx += ($bx & 0xFFFF) - ($mbx & 0xFFFF) + $bonus;
		$my += ($by & 0xFFFF) - ($mby & 0xFFFF) + $bonus;
	}
	$mxy = array($mx - $mdx - ($mw - 1) * 32, $my - $mdy - ($mh - 1) * 32);
	if ($neg || $mneg) {
		if (!$mneg) {
			$x += $mdx; $y += $mdy;
		}
		if ($mneg && $mbones && !$bones) {
			$x += chaos_sprite_s16($mbx); $y += chaos_sprite_s16($mby);
		}
	} else {
		$x += $dx; $y += $dy;
	}
	return array(array($x - $dx - ($w - 1) * 32, $y - $dy - ($h - 1) * 32), $mxy, 1);
}

/** RGBA pixels (8-bit alpha) of a rectangle of a GD image: list of [r, g, b, a] rows. */
function chaos_sprite_pixels($img, int $x0, int $y0, int $w, int $h): array {
	$out = array();
	for ($y = 0; $y < $h; $y++) {
		$row = array();
		for ($x = 0; $x < $w; $x++) {
			$c = imagecolorat($img, $x0 + $x, $y0 + $y);
			$a7 = ($c >> 24) & 0x7F;
			$row[] = array(($c >> 16) & 0xFF, ($c >> 8) & 0xFF, $c & 0xFF, $a7 >= 127 ? 0 : ($a7 === 0 ? 255 : (int)round((127 - $a7) * 255 / 127)));
		}
		$out[] = $row;
	}
	return $out;
}

/** Alpha-composite src pixels onto the canvas (arrays) at (x, y): the client's normal blending. */
function chaos_sprite_over(array &$canvas, array $src, int $x0, int $y0): void {
	foreach ($src as $y => $row) {
		foreach ($row as $x => $s) {
			$sa = $s[3];
			if ($sa === 0) {
				continue;
			}
			$d = &$canvas[$y0 + $y][$x0 + $x];
			if ($sa === 255 || $d[3] === 0) {
				$d = $s;
			} else {
				$fs = $sa / 255; $fd = $d[3] / 255;
				$oa = $fs + $fd * (1 - $fs);
				for ($k = 0; $k < 3; $k++) {
					$d[$k] = (int)round(($s[$k] * $fs + $d[$k] * $fd * (1 - $fs)) / $oa);
				}
				$d[3] = (int)round($oa * 255);
			}
			unset($d);
		}
	}
}

/** Multiply the canvas under each exact template colour by that part's outfit colour: (v * c + 127) / 255. */
function chaos_sprite_tint(array &$canvas, array $mask, array $colours, int $x0, int $y0): void {
	$rgb = array_map('chaos_outfit_colour', $colours);
	foreach ($mask as $y => $row) {
		foreach ($row as $x => $m) {
			if ($m[3] === 0) {
				continue;
			}
			foreach (CHAOS_OUTFIT_MASK as $part => $key) {
				if ($m[0] === $key[0] && $m[1] === $key[1] && $m[2] === $key[2]) {
					$d = &$canvas[$y0 + $y][$x0 + $x];
					for ($k = 0; $k < 3; $k++) {
						$d[$k] = intdiv($d[$k] * $rgb[$part][$k] + 127, 255);
					}
					unset($d);
					break;
				}
			}
		}
	}
}

/** The look as a canvas of RGBA rows (gen_sprite_images.py compose()), or null when it is not ours or gd is missing.
 *  p = chaos_outfit_params(); the mount is drawn only when it is ours too and the look has a mounted pattern. */
function chaos_outfit_canvas(array $p): ?array {
	$i = chaos_sprite_index();
	if ($i === null || !function_exists('imagecreatefrompng') || !chaos_outfit_published($p['id'])) {
		return null;
	}
	$rider = $i['outfits'][(string)$p['id']];
	$mount = ($p['mount'] > 0 && chaos_outfit_published($p['mount'])) ? $i['outfits'][(string)$p['mount']] : null;
	[$rxy, $mxy, $z] = chaos_outfit_place($rider, $mount);
	[$w, $h, , , $py, , $layers] = $rider;
	$rects = array(array($rxy[0], $rxy[1], $w * 32, $h * 32));
	if ($mxy !== null) {
		$rects[] = array($mxy[0], $mxy[1], $mount[0] * 32, $mount[1] * 32);
	}
	$left = min(array_column($rects, 0)); $top = min(array_column($rects, 1));
	$right = max(array_map(static function ($r) { return $r[0] + $r[2]; }, $rects));
	$bottom = max(array_map(static function ($r) { return $r[1] + $r[3]; }, $rects));
	$canvas = array_fill(0, $bottom - $top, array_fill(0, $right - $left, array(0, 0, 0, 0)));
	$dir = chaos_sprite_root() . '/outfits/';
	if ($mxy !== null) {
		$ms = is_file($dir . $p['mount'] . '.png') ? @imagecreatefrompng($dir . $p['mount'] . '.png') : false;
		if ($ms !== false) {
			chaos_sprite_over($canvas, chaos_sprite_pixels($ms, 0, 0, $mount[0] * 32, $mount[1] * 32), $mxy[0] - $left, $mxy[1] - $top);
		}
	}
	$sheet = is_file($dir . $p['id'] . '.png') ? @imagecreatefrompng($dir . $p['id'] . '.png') : false;
	if ($sheet === false) {
		return null;
	}
	$cw = $w * 32; $ch = $h * 32;
	$colours = array($p['head'], $p['body'], $p['legs'], $p['feet']);
	for ($y = 0; $y < $py; $y++) {
		if ($y > 0 && !($p['addons'] & (1 << ($y - 1)))) {
			continue;
		}
		$col = $z * $py + $y;
		chaos_sprite_over($canvas, chaos_sprite_pixels($sheet, $col * $cw, 0, $cw, $ch), $rxy[0] - $left, $rxy[1] - $top);
		if ($layers > 1) {
			chaos_sprite_tint($canvas, chaos_sprite_pixels($sheet, $col * $cw, $ch, $cw, $ch), $colours, $rxy[0] - $left, $rxy[1] - $top);
		}
	}
	return $canvas;
}

/** PNG bytes of a canvas. */
function chaos_sprite_png(array $canvas): string {
	$h = count($canvas); $w = $h ? count($canvas[0]) : 0;
	$img = imagecreatetruecolor(max(1, $w), max(1, $h));
	imagealphablending($img, false);
	imagesavealpha($img, true);
	foreach ($canvas as $y => $row) {
		foreach ($row as $x => $c) {
			$a7 = 127 - (int)round($c[3] * 127 / 255);
			imagesetpixel($img, $x, $y, ($a7 << 24) | ($c[0] << 16) | ($c[1] << 8) | $c[2]);
		}
	}
	ob_start();
	imagepng($img);
	return (string)ob_get_clean();
}

/** A file's bytes, '' when it is not there. */
function chaos_sprite_read(string $path): string {
	return is_file($path) ? (string)file_get_contents($path) : '';
}

/** [PNG bytes, source] of an outfit request: 'render', 'cache', 'default' (no gd) or 'placeholder'. */
function chaos_outfit_image(array $get, ?string $cacheDir = null): array {
	$p = chaos_outfit_params($get);
	$i = chaos_sprite_index();
	$root = chaos_sprite_root();
	if ($i === null || !chaos_outfit_published($p['id'])) {
		return array(chaos_sprite_read($root . '/placeholder-outfit.png'), 'placeholder');
	}
	if (!function_exists('imagecreatefrompng')) {
		return array(chaos_sprite_read($root . '/outfits/' . $p['id'] . '-d.png'), 'default');
	}
	$key = sha1($i['stamp'] . '|' . implode(',', $p));
	$file = $cacheDir !== null ? $cacheDir . '/' . $key . '.png' : null;
	if ($file !== null && is_file($file)) {
		return array((string)file_get_contents($file), 'cache');
	}
	$canvas = chaos_outfit_canvas($p);
	if ($canvas === null) {
		return array(chaos_sprite_read($root . '/placeholder-outfit.png'), 'placeholder');
	}
	$png = chaos_sprite_png($canvas);
	if ($file !== null && (is_dir($cacheDir) || @mkdir($cacheDir, 0755, true))
			&& count((array)@scandir($cacheDir)) < CHAOS_SPRITE_CACHE_MAX + 2) {
		@file_put_contents($file . '.tmp', $png);
		@rename($file . '.tmp', $file);
	}
	return array($png, 'render');
}

/** chaos_outfit.php: answer one outfit image request (always an image; never reads ZnoteX or the database). */
function chaos_outfit_serve(array $get): void {
	$cache = dirname(chaos_sprite_root()) . '/engine/cache/chaos-outfits';
	[$png, $source] = chaos_outfit_image($get, $cache);
	if ($png === '') {
		http_response_code(404);
		return;
	}
	$etag = '"' . substr(sha1($png), 0, 20) . '"';
	header('Content-Type: image/png');
	header('Cache-Control: public, max-age=86400');
	header('X-Content-Type-Options: nosniff');
	header('ETag: ' . $etag);
	header('X-Chaos-Sprite: ' . $source);
	if (trim((string)($_SERVER['HTTP_IF_NONE_MATCH'] ?? '')) === $etag) {
		http_response_code(304);
		return;
	}
	header('Content-Length: ' . strlen($png));
	echo $png;
}

/** An <img> of a sprite for our pages: escaped URL, alt text, size, crisp scaling. '' when there is no URL. */
function chaos_sprite_img(string $url, string $alt, int $w, int $h, string $class = 'chaos-sprite'): string {
	if ($url === '') {
		return '';
	}
	$e = static function (string $v): string { return htmlspecialchars($v, ENT_QUOTES, 'UTF-8'); };
	return '<img class="' . $e($class) . '" src="' . $e($url) . '" alt="' . $e($alt) . '" width="' . $w . '" height="' . $h
		. '" loading="lazy" decoding="async">';
}

/** A wiki sprite reference {item: sid} or {outfit: look, addons} -> [url, w, h] when it is ours, else null
 *  (the wiki then shows its themed icon). */
function chaos_sprite_ref(array $ref): ?array {
	if (isset($ref['item']) && is_int($ref['item']) && chaos_item_published($ref['item'])) {
		return array(chaos_item_url($ref['item']), 32, 32);
	}
	if (isset($ref['outfit']) && is_int($ref['outfit']) && chaos_outfit_published($ref['outfit'])) {
		$m = chaos_sprite_index()['outfits'][(string)$ref['outfit']];
		$addons = isset($ref['addons']) && is_int($ref['addons']) ? $ref['addons'] : 0;
		return array(chaos_outfit_url($ref['outfit'], $addons), $m[0] * 32, $m[1] * 32);
	}
	return null;
}
