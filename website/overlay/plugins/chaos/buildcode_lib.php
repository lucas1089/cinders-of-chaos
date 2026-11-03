<?php
/**
 * Build codes on the website (O391, website/README.md "Build codes"): the PHP twin of the client's codec
 * (client/overlay/modules/game_passivetree/buildcode.lua, ChaosBuildCode; same format, same error kinds, same text
 * form; both are tested against docs/build_code_vectors.txt) and the drawing of a build for
 * page?plugin=chaos&p=build&c=CODE (pages/build.php). The character page (character_lib.php) makes a code of a
 * character's class, level, passive tree and gear with the same encoder.
 *
 * Format "CC1-" + base64url(payload + checksum), no padding, canonical form only. payload = sections: tag (1 byte),
 * length (2 bytes, high first), data. Tags: 1 class (index into chaos_buildcode_classes()), 2 level (2 bytes),
 * 3 tree (the server's tree code: its version byte, then its bytes, see server/data/scripts/chaos/buildshare_core.lua),
 * 4 spells (2 bytes per server spell id), 5 gear (slot 1 byte, server item id 2 bytes). An unknown tag is skipped.
 * Checksum: 3 bytes, h = (h * 257 + x) mod 16777213 over "CC1" and the payload bytes.
 *
 * Names and icons come from the wiki data (wiki_lib.php: spell:<id>, tree:<id>, tree:<id>:<variant>, unique:<id>),
 * item names from the game server's items.xml (chaos_item_name). Everything printed goes through chaos_h().
 */

require_once __DIR__ . '/wiki_lib.php';
require_once __DIR__ . '/sprite_lib.php';

if (!function_exists('chaos_buildcode_classes')) {

define('CHAOS_BUILDCODE_PREFIX', 'CC');
define('CHAOS_BUILDCODE_VERSION', 1);
define('CHAOS_BUILDCODE_MAX', 1000);
define('CHAOS_BUILDCODE_MAX_SPELLS', 16);
define('CHAOS_BUILDCODE_TREE_LAYOUT_MAX', 6);
define('CHAOS_BUILDCODE_MOD', 16777213);
define('CHAOS_BUILDCODE_ALPHABET', 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_');

/** index (the code's class byte) => [key, vocation id, name]. Append only, never reorder (= buildcode.lua C.CLASSES). */
function chaos_buildcode_classes(): array {
	return array(
		1 => array('warrior', 4, 'Warrior'), 2 => array('juggernaut', 8, 'Juggernaut'), 3 => array('berserker', 14, 'Berserker'),
		4 => array('ranger', 3, 'Ranger'), 5 => array('deadeye', 7, 'Deadeye'), 6 => array('beastmaster', 15, 'Beastmaster'),
		7 => array('mystic', 1, 'Mystic'), 8 => array('elementalist', 5, 'Elementalist'), 9 => array('illusionist', 10, 'Illusionist'),
		10 => array('thief', 11, 'Thief'), 11 => array('ninja', 12, 'Ninja'), 12 => array('samurai', 13, 'Samurai'),
		13 => array('monk', 17, 'Monk'), 14 => array('shadowfist', 18, 'Shadowfist'), 15 => array('ironsage', 19, 'Iron Sage'),
		16 => array('necromancer', 20, 'Necromancer'), 17 => array('lich', 21, 'Lich'), 18 => array('bonelord', 22, 'Bone Lord'),
		19 => array('templar', 23, 'Templar'), 20 => array('inquisitor', 24, 'Inquisitor'), 21 => array('sentinel', 25, 'Sentinel'),
	);
}

/** The Paragon stat keys of the tree code (buildshare_core.lua B.PARAGON_KEYS, append only), 1-based. */
function chaos_buildcode_paragon_keys(): array {
	return array(1 => 'damage', 2 => 'critDamage', 3 => 'health', 4 => 'reduction', 5 => 'speed', 6 => 'mana', 7 => 'goldFind', 8 => 'itemFind');
}

/** The class lines of the tree code's class byte (buildshare_core.lua B.CLASS_LINES): base vocation id => byte. */
function chaos_buildcode_tree_lines(): array {
	return array(4 => 1, 3 => 2, 1 => 3, 11 => 4);
}

/** The gear slots of a code (TFS slot numbers; the backpack is never in a code) and their names. */
function chaos_buildcode_slots(): array {
	return array(1 => 'Head', 2 => 'Amulet', 4 => 'Armour', 5 => 'Right hand', 6 => 'Left hand', 7 => 'Legs', 8 => 'Feet',
		9 => 'Ring', 10 => 'Ammo');
}

function chaos_buildcode_class_index(string $key): ?int {
	foreach (chaos_buildcode_classes() as $i => $c) {
		if ($c[0] === $key) {
			return $i;
		}
	}
	return null;
}

/** The class key of a vocation id (retired ids follow their new class), or null. */
function chaos_buildcode_class_of_vocation(int $vocation): ?string {
	$retired = function_exists('chaos_retired_vocations') ? chaos_retired_vocations() : array();
	$vocation = $retired[$vocation] ?? $vocation;
	foreach (chaos_buildcode_classes() as $c) {
		if ($c[1] === $vocation) {
			return $c[0];
		}
	}
	return null;
}

function chaos_buildcode_checksum(string $head, array $bytes, int $count): int {
	$h = 0;
	for ($i = 0, $n = strlen($head); $i < $n; $i++) {
		$h = ($h * 257 + ord($head[$i])) % CHAOS_BUILDCODE_MOD;
	}
	for ($i = 0; $i < $count; $i++) {
		$h = ($h * 257 + $bytes[$i]) % CHAOS_BUILDCODE_MOD;
	}
	return $h;
}

/** base64url without padding of a byte list. */
function chaos_buildcode_b64(array $bytes): string {
	$out = '';
	$alpha = CHAOS_BUILDCODE_ALPHABET;
	for ($i = 0, $n = count($bytes); $i < $n; $i += 3) {
		$a = $bytes[$i];
		$b = $bytes[$i + 1] ?? null;
		$c = $bytes[$i + 2] ?? null;
		$v = ($a << 16) | (($b ?? 0) << 8) | ($c ?? 0);
		$chars = 2 + ($b !== null ? 1 : 0) + ($c !== null ? 1 : 0);
		for ($k = 1; $k <= $chars; $k++) {
			$out .= $alpha[($v >> (6 * (4 - $k))) & 63];
		}
	}
	return $out;
}

/** The bytes of a base64url text, or null (a bad character or length, or not the canonical form). */
function chaos_buildcode_unb64(string $text): ?array {
	if (strlen($text) % 4 === 1 || !preg_match('/^[A-Za-z0-9_-]*$/', $text)) {
		return null;
	}
	$bytes = array();
	for ($i = 0, $n = strlen($text); $i < $n; $i += 4) {
		$chunk = substr($text, $i, 4);
		$v = 0;
		for ($k = 0; $k < 4; $k++) {
			$v = ($v << 6) | ($k < strlen($chunk) ? strpos(CHAOS_BUILDCODE_ALPHABET, $chunk[$k]) : 0);
		}
		for ($k = 1; $k < strlen($chunk); $k++) {
			$bytes[] = ($v >> (8 * (3 - $k))) & 255;
		}
	}
	return chaos_buildcode_b64($bytes) === $text ? $bytes : null;
}

/** [version, bytes] of a tree code with a good checksum, or null. */
function chaos_buildcode_tree_bytes(string $code): ?array {
	if (!preg_match('/^CB(\d{1,3})-([A-Za-z0-9_-]+)$/', $code, $m) || (int)$m[1] < 1 || (int)$m[1] > 255) {
		return null;
	}
	$bytes = chaos_buildcode_unb64($m[2]);
	if ($bytes === null || count($bytes) < 5) {
		return null;
	}
	$n = count($bytes);
	if (chaos_buildcode_checksum('CB' . (int)$m[1], $bytes, $n - 3) !== ($bytes[$n - 3] << 16 | $bytes[$n - 2] << 8 | $bytes[$n - 1])) {
		return null;
	}
	return array((int)$m[1], $bytes);
}

/**
 * What a tree code holds: [code, version, line, nodes (sorted ids), paragon (key => points), masteries (id => choice)],
 * or [code, version, newer => true] for a layout newer than this file; null when damaged.
 */
function chaos_buildcode_read_tree(string $code): ?array {
	$tb = chaos_buildcode_tree_bytes($code);
	if ($tb === null) {
		return null;
	}
	list($version, $bytes) = $tb;
	if ($version > CHAOS_BUILDCODE_TREE_LAYOUT_MAX) {
		return array('code' => $code, 'version' => $version, 'newer' => true);
	}
	$last = count($bytes) - 4; // index of the last byte before the checksum
	$info = array('code' => $code, 'version' => $version, 'line' => $bytes[0], 'nodes' => array(), 'paragon' => array(), 'masteries' => array());
	$flags = $bytes[1] ?? 0;
	$pos = 2;
	$keys = chaos_buildcode_paragon_keys();
	if ($flags & 1) {
		$count = $bytes[$pos] ?? 0;
		$pos++;
		for ($i = 0; $i < $count; $i++) {
			$key = $keys[$bytes[$pos] ?? 0] ?? null;
			if ($key === null || $pos + 1 > $last) {
				return null;
			}
			$info['paragon'][$key] = $bytes[$pos + 1];
			$pos += 2;
		}
	}
	if ($version >= 2 && ($flags & 2)) {
		$count = $bytes[$pos] ?? 0;
		$pos++;
		for ($i = 0; $i < $count; $i++) {
			if ($pos + 2 > $last) {
				return null;
			}
			$info['masteries'][($bytes[$pos] << 8) | $bytes[$pos + 1]] = $bytes[$pos + 2];
			$pos += 3;
		}
	}
	if ($pos > $last + 1) {
		return null;
	}
	for ($i = $pos; $i <= $last; $i++) {
		for ($bit = 0; $bit < 8; $bit++) {
			if (($bytes[$i] >> $bit) & 1) {
				$info['nodes'][] = ($i - $pos) * 8 + $bit;
			}
		}
	}
	ksort($info['masteries']);
	return $info;
}

/**
 * A tree code (version 6 layout, buildshare_core.lua B.encode) of [line, nodes, paragon (key => points), masteries
 * (id => choice)]: the character page makes one from the database.
 */
function chaos_buildcode_tree_encode(array $build, int $version = 6): string {
	$bytes = array(max(0, min(255, (int)($build['line'] ?? 0))));
	$stats = array();
	foreach (chaos_buildcode_paragon_keys() as $i => $key) {
		$p = (int)($build['paragon'][$key] ?? 0);
		if ($p > 0) {
			$stats[] = array($i, min($p, 255));
		}
	}
	$mastery = array();
	if ($version >= 2) {
		foreach ((array)($build['masteries'] ?? array()) as $id => $choice) {
			$id = (int)$id;
			$choice = (int)$choice;
			if ($id > 0 && $id < 65536 && $choice > 0 && $choice < 256) {
				$mastery[$id] = $choice;
			}
		}
		ksort($mastery);
		$mastery = array_slice($mastery, 0, 255, true);
	}
	$bytes[] = (count($stats) > 0 ? 1 : 0) + (count($mastery) > 0 ? 2 : 0);
	if ($stats) {
		$bytes[] = count($stats);
		foreach ($stats as $s) {
			$bytes[] = $s[0];
			$bytes[] = $s[1];
		}
	}
	if ($mastery) {
		$bytes[] = count($mastery);
		foreach ($mastery as $id => $choice) {
			$bytes[] = $id >> 8;
			$bytes[] = $id & 255;
			$bytes[] = $choice;
		}
	}
	$bits = array();
	$max = -1;
	foreach ((array)($build['nodes'] ?? array()) as $id) {
		$id = (int)$id;
		if ($id >= 0 && $id < 65536) {
			$bits[$id >> 3] = ($bits[$id >> 3] ?? 0) | (1 << ($id & 7));
			$max = max($max, $id >> 3);
		}
	}
	for ($b = 0; $b <= $max; $b++) {
		$bytes[] = $bits[$b] ?? 0;
	}
	$head = 'CB' . $version;
	$h = chaos_buildcode_checksum($head, $bytes, count($bytes));
	$bytes[] = ($h >> 16) & 255;
	$bytes[] = ($h >> 8) & 255;
	$bytes[] = $h & 255;
	return $head . '-' . chaos_buildcode_b64($bytes);
}

/**
 * The code of a card [class => key, level, tree => tree code, spells => [ids], gear => [[slot, id]]] (every part
 * optional; bad spell and gear entries are dropped): ['code' => string] or ['error' => kind].
 */
function chaos_buildcode_encode(array $card): array {
	$sections = array();
	$push16 = static function (array &$d, int $v): void {
		$d[] = ($v >> 8) & 255;
		$d[] = $v & 255;
	};
	if (isset($card['class'])) {
		$index = chaos_buildcode_class_index((string)$card['class']);
		if ($index === null) {
			return array('error' => 'class');
		}
		$sections[] = array(1, array($index));
	}
	if (isset($card['level'])) {
		$level = is_numeric($card['level']) ? (int)$card['level'] : 0;
		if ($level < 1 || $level > 65535) {
			return array('error' => 'level');
		}
		$d = array();
		$push16($d, $level);
		$sections[] = array(2, $d);
	}
	if (isset($card['tree'])) {
		$tb = chaos_buildcode_tree_bytes((string)$card['tree']);
		if ($tb === null) {
			return array('error' => 'tree');
		}
		$sections[] = array(3, array_merge(array($tb[0]), $tb[1]));
	}
	if (!empty($card['spells']) && is_array($card['spells'])) {
		$d = array();
		$seen = array();
		foreach ($card['spells'] as $raw) {
			$id = is_numeric($raw) ? (int)$raw : 0;
			if ($id > 0 && $id < 65536 && !isset($seen[$id]) && count($d) < CHAOS_BUILDCODE_MAX_SPELLS * 2) {
				$seen[$id] = true;
				$push16($d, $id);
			}
		}
		if ($d) {
			$sections[] = array(4, $d);
		}
	}
	if (!empty($card['gear']) && is_array($card['gear'])) {
		$bySlot = array();
		foreach ($card['gear'] as $g) {
			$slot = (int)($g['slot'] ?? ($g[0] ?? 0));
			$id = (int)($g['id'] ?? ($g[1] ?? 0));
			if ($id > 0 && $id < 65536) {
				$bySlot[$slot] = $id;
			}
		}
		$d = array();
		foreach (array_keys(chaos_buildcode_slots()) as $slot) {
			if (isset($bySlot[$slot])) {
				$d[] = $slot;
				$push16($d, $bySlot[$slot]);
			}
		}
		if ($d) {
			$sections[] = array(5, $d);
		}
	}
	$bytes = array();
	foreach ($sections as $s) {
		$bytes[] = $s[0];
		$push16($bytes, count($s[1]));
		foreach ($s[1] as $b) {
			$bytes[] = $b;
		}
	}
	$head = CHAOS_BUILDCODE_PREFIX . CHAOS_BUILDCODE_VERSION;
	$h = chaos_buildcode_checksum($head, $bytes, count($bytes));
	$bytes[] = ($h >> 16) & 255;
	$bytes[] = ($h >> 8) & 255;
	$bytes[] = $h & 255;
	$code = $head . '-' . chaos_buildcode_b64($bytes);
	return strlen($code) > CHAOS_BUILDCODE_MAX ? array('error' => 'toolong') : array('code' => $code);
}

/** The first full build code inside a text, or null. */
function chaos_buildcode_extract(string $text): ?string {
	return preg_match('/(CC\d+-[A-Za-z0-9_-]+)/', $text, $m) ? $m[1] : null;
}

/**
 * ['card' => [class, vocation, name, level, tree, tree_info, spells, gear => [[slot, id]], skipped]] or
 * ['error' => kind] (empty, toolong, format, version, damaged, checksum, class, level, tree, spells, gear).
 */
function chaos_buildcode_decode(string $code): array {
	$code = trim($code);
	if ($code === '') {
		return array('error' => 'empty');
	}
	if (strlen($code) > CHAOS_BUILDCODE_MAX) {
		return array('error' => 'toolong');
	}
	if (!preg_match('/^CC(\d+)-([A-Za-z0-9_-]*)$/', $code, $m)) {
		return array('error' => 'format');
	}
	if ($m[1] !== (string)CHAOS_BUILDCODE_VERSION) {
		return array('error' => 'version');
	}
	$bytes = chaos_buildcode_unb64($m[2]);
	if ($bytes === null || count($bytes) < 3) {
		return array('error' => 'damaged');
	}
	$n = count($bytes);
	$head = CHAOS_BUILDCODE_PREFIX . CHAOS_BUILDCODE_VERSION;
	if (chaos_buildcode_checksum($head, $bytes, $n - 3) !== ($bytes[$n - 3] << 16 | $bytes[$n - 2] << 8 | $bytes[$n - 1])) {
		return array('error' => 'checksum');
	}
	$card = array('spells' => array(), 'gear' => array(), 'skipped' => 0);
	$seen = array();
	$classes = chaos_buildcode_classes();
	$slots = chaos_buildcode_slots();
	$pos = 0;
	$last = $n - 4;
	while ($pos <= $last) {
		if ($pos + 2 > $last) {
			return array('error' => 'damaged');
		}
		$tag = $bytes[$pos];
		$len = ($bytes[$pos + 1] << 8) | $bytes[$pos + 2];
		$from = $pos + 3;
		$to = $pos + 2 + $len;
		if ($to > $last || isset($seen[$tag])) {
			return array('error' => 'damaged');
		}
		$seen[$tag] = true;
		if ($tag === 1) {
			$c = $len === 1 ? ($classes[$bytes[$from]] ?? null) : null;
			if ($c === null) {
				return array('error' => 'class');
			}
			$card['class'] = $c[0];
			$card['vocation'] = $c[1];
			$card['name'] = $c[2];
		} elseif ($tag === 2) {
			$level = $len === 2 ? (($bytes[$from] << 8) | $bytes[$from + 1]) : 0;
			if ($level < 1) {
				return array('error' => 'level');
			}
			$card['level'] = $level;
		} elseif ($tag === 3) {
			if ($len < 6) {
				return array('error' => 'tree');
			}
			$card['tree'] = 'CB' . $bytes[$from] . '-' . chaos_buildcode_b64(array_slice($bytes, $from + 1, $len - 1));
			$card['tree_info'] = chaos_buildcode_read_tree($card['tree']);
			if ($card['tree_info'] === null) {
				return array('error' => 'tree');
			}
		} elseif ($tag === 4) {
			if ($len % 2 !== 0 || $len > CHAOS_BUILDCODE_MAX_SPELLS * 2) {
				return array('error' => 'spells');
			}
			for ($i = $from; $i <= $to; $i += 2) {
				$card['spells'][] = ($bytes[$i] << 8) | $bytes[$i + 1];
			}
		} elseif ($tag === 5) {
			if ($len % 3 !== 0) {
				return array('error' => 'gear');
			}
			$prev = 0;
			for ($i = $from; $i <= $to; $i += 3) {
				$slot = $bytes[$i];
				$id = ($bytes[$i + 1] << 8) | $bytes[$i + 2];
				if (!isset($slots[$slot]) || $slot <= $prev || $id === 0) {
					return array('error' => 'gear');
				}
				$prev = $slot;
				$card['gear'][] = array('slot' => $slot, 'id' => $id);
			}
		} else {
			$card['skipped']++; // a part a newer client added
		}
		$pos = $to + 1;
	}
	return array('card' => $card);
}

/** The one-line text form of a decoded card (= buildcode.lua C.describe; docs/build_code_vectors.txt). */
function chaos_buildcode_describe(array $card): string {
	$parts = array();
	if (isset($card['class'])) {
		$parts[] = 'class=' . $card['class'];
	}
	if (isset($card['level'])) {
		$parts[] = 'level=' . (int)$card['level'];
	}
	if (isset($card['tree'])) {
		$parts[] = 'tree=' . $card['tree'];
		$t = $card['tree_info'] ?? null;
		if (is_array($t) && !empty($t['newer'])) {
			$parts[] = 'newer=1';
		} elseif (is_array($t)) {
			$parts[] = 'line=' . (int)$t['line'];
			$parts[] = 'nodes=' . implode(',', $t['nodes']);
			$p = array();
			foreach (chaos_buildcode_paragon_keys() as $key) {
				if (isset($t['paragon'][$key])) {
					$p[] = $key . ':' . (int)$t['paragon'][$key];
				}
			}
			if ($p) {
				$parts[] = 'paragon=' . implode(',', $p);
			}
			$ms = array();
			foreach ($t['masteries'] as $id => $choice) {
				$ms[] = (int)$id . ':' . (int)$choice;
			}
			if ($ms) {
				$parts[] = 'masteries=' . implode(',', $ms);
			}
		}
	}
	if (!empty($card['spells'])) {
		$parts[] = 'spells=' . implode(',', array_map('intval', $card['spells']));
	}
	if (!empty($card['gear'])) {
		$g = array();
		foreach ($card['gear'] as $it) {
			$g[] = (int)$it['slot'] . ':' . (int)$it['id'];
		}
		$parts[] = 'gear=' . implode(',', $g);
	}
	if (($card['skipped'] ?? 0) > 0) {
		$parts[] = 'skipped=' . (int)$card['skipped'];
	}
	return implode(';', $parts);
}

/** The error text of a decode error kind. */
function chaos_buildcode_error_text(string $kind): string {
	$texts = array(
		'empty' => 'Paste a build code to see the build.',
		'toolong' => 'That build code is too long.',
		'format' => 'That is not a full build code. Full build codes start with CC1- (the client: Passive Tree > Build Code > Copy Full Build).',
		'version' => 'That build code is from a newer format than this site reads yet.',
		'checksum' => 'That build code is damaged: the checksum does not match (check for a typo).',
		'tree' => 'The passive tree part of that build code is damaged.',
	);
	return $texts[$kind] ?? 'That build code is damaged (check for a typo or a missing part).';
}

/** The page address of a code. */
function chaos_build_url(string $code): string {
	return 'page?plugin=chaos&p=build&c=' . rawurlencode($code);
}

// ---------------------------------------------------------------------------------------------------------------- items

/**
 * Item names by server id: the game server's items.xml (server_data/items/items.xml; ranges fromid..toid too), else
 * data/items/base_item_names.csv. Read once per request and cached in engine/cache/ by the file's size and time.
 */
function chaos_item_names(bool $reload = false): array {
	static $names = null;
	if ($names !== null && !$reload) {
		return $names;
	}
	$names = array();
	$csv = chaos_data_path('items/base_item_names.csv');
	if ($csv !== '' && is_readable($csv) && ($fh = fopen($csv, 'r')) !== false) {
		fgetcsv($fh, 0, ',', '"', '');
		while (($row = fgetcsv($fh, 0, ',', '"', '')) !== false) {
			if (count($row) >= 3 && ctype_digit((string)$row[0])) {
				$names[(int)$row[0]] = (string)$row[2];
			}
		}
		fclose($fh);
	}
	$xml = chaos_data_path('items/items.xml');
	if ($xml === '' || !is_readable($xml)) {
		return $names;
	}
	$stamp = filesize($xml) . '-' . filemtime($xml);
	$cacheDir = dirname(__DIR__, 2) . '/engine/cache';
	$cache = $cacheDir . '/chaos-item-names.json';
	$cached = is_readable($cache) ? json_decode((string)file_get_contents($cache), true) : null;
	if (is_array($cached) && ($cached['stamp'] ?? '') === $stamp && is_array($cached['names'] ?? null)) {
		foreach ($cached['names'] as $id => $name) {
			$names[(int)$id] = (string)$name;
		}
		return $names;
	}
	$text = (string)file_get_contents($xml);
	$fromXml = array();
	if (preg_match_all('/<item\s([^>]*?)\/?>/', $text, $m)) {
		foreach ($m[1] as $attrs) {
			if (!preg_match('/\bname="([^"]*)"/', $attrs, $n)) {
				continue;
			}
			$name = html_entity_decode($n[1], ENT_QUOTES | ENT_XML1, 'UTF-8');
			if (preg_match('/\bid="(\d+)"/', $attrs, $id)) {
				$fromXml[(int)$id[1]] = $name;
			} elseif (preg_match('/\bfromid="(\d+)"/', $attrs, $a) && preg_match('/\btoid="(\d+)"/', $attrs, $b)
					&& (int)$b[1] >= (int)$a[1] && (int)$b[1] - (int)$a[1] < 2000) {
				for ($i = (int)$a[1]; $i <= (int)$b[1]; $i++) {
					$fromXml[$i] = $name;
				}
			}
		}
	}
	if (is_dir($cacheDir) && is_writable($cacheDir)) {
		@file_put_contents($cache, json_encode(array('stamp' => $stamp, 'names' => $fromXml)), LOCK_EX);
	}
	foreach ($fromXml as $id => $name) {
		$names[$id] = $name;
	}
	return $names;
}

/** The name of an item: a unique's name from the wiki first, then items.xml, else "item <id>". */
function chaos_item_name(int $id): string {
	$u = chaos_wiki_entry('unique:' . $id);
	if ($u !== null) {
		return (string)$u['entry']['name'];
	}
	$name = chaos_item_names()[$id] ?? '';
	return $name !== '' ? ucfirst($name) : 'item ' . $id;
}

/** One gear row: image, name (a link to the wiki for a unique), slot. */
function chaos_build_gear_cell(int $id, string $label): string {
	$name = chaos_item_name($id);
	$img = chaos_sprite_img(chaos_item_url($id), $name, 32, 32, 'chaos-sprite chaos-build__item');
	$u = chaos_wiki_entry('unique:' . $id);
	$nameHtml = $u !== null ? '<a href="' . chaos_h(chaos_wiki_url('unique:' . $id, 'en')) . '">' . chaos_h($name) . '</a>' : chaos_h($name);
	return '<li class="chaos-build__gear">' . $img . '<span><span class="chaos-muted">' . chaos_h($label) . '</span> ' . $nameHtml . '</span></li>';
}

// ---------------------------------------------------------------------------------------------------------------- drawing

/** The wiki entry of a tree node for a class: tree:<id>, else the class's variant tree:<id>:<key>, else null. */
function chaos_build_tree_entry(int $id, string $className): ?array {
	$e = chaos_wiki_entry('tree:' . $id);
	if ($e !== null) {
		return $e['entry'];
	}
	static $variants = null;
	if ($variants === null) {
		$variants = array();
		foreach (chaos_wiki_index() as $eid => $at) {
			if (preg_match('/^tree:(\d+):/', (string)$eid, $m)) {
				$variants[(int)$m[1]][] = chaos_wiki_data()['tabs'][$at[0]]['entries'][$at[1]];
			}
		}
	}
	$list = $variants[$id] ?? array();
	foreach ($list as $entry) {
		// "Keystone. Mystic, Elementalist.": the variant whose class list names this class
		if ($className !== '' && preg_match('/[ .,]' . preg_quote($className, '/') . '[.,]/', (string)($entry['sub'] ?? ''))) {
			return $entry;
		}
	}
	return $list[0] ?? null;
}

/** A named node: icon, name (a link to its wiki entry), and the chosen effect of a mastery. */
function chaos_build_node_item(array $entry, ?int $choice): string {
	$name = (string)($entry['name'] ?? '');
	$h = '<li>' . chaos_wiki_icon($entry, 24, 'chaos-wiki-icon chaos-wiki-icon--row')
		. '<a href="' . chaos_h(chaos_wiki_url((string)$entry['id'], 'en')) . '">' . chaos_h($name) . '</a>';
	if ($choice !== null) {
		$effect = '';
		foreach ((array)($entry['sections'] ?? array()) as $s) {
			if (isset($s['rows'][$choice - 1][0])) {
				$effect = (string)$s['rows'][$choice - 1][0];
				break;
			}
		}
		$h .= ': ' . ($effect !== '' ? chaos_h($effect) : 'effect ' . (int)$choice);
	}
	return $h . '</li>';
}

/** The passive tree part: points, keystones, notables, masteries, small nodes, Paragon. */
function chaos_build_tree_html(?array $t, string $className): string {
	if ($t === null) {
		return '<p class="chaos-empty">This code has no passive tree.</p>';
	}
	if (!empty($t['newer'])) {
		return '<p class="chaos-note">The passive tree of this code is from a newer format than this site reads yet; the game can still import it.</p>';
	}
	$groups = array('keystone' => array(), 'notable' => array(), 'mastery' => array());
	$small = 0;
	foreach ($t['nodes'] as $id) {
		if ($id === 1) {
			continue; // the start
		}
		$e = chaos_build_tree_entry($id, $className);
		$group = is_array($e) ? (string)($e['group'] ?? 'notable') : '';
		if ($e === null || !isset($groups[$group])) {
			$small++;
			continue;
		}
		$groups[$group][] = chaos_build_node_item($e, $group === 'mastery' ? (int)($t['masteries'][$id] ?? 1) : null);
	}
	$points = count(array_filter($t['nodes'], static function ($id) { return $id !== 1; }));
	$h = '<p><strong class="chaos-gold">' . $points . '</strong> passive points: ' . count($groups['keystone']) . ' keystones, '
		. count($groups['notable']) . ' notables, ' . count($groups['mastery']) . ' masteries and ' . $small . ' small nodes.</p>';
	$titles = array('keystone' => 'Keystones', 'notable' => 'Notables', 'mastery' => 'Masteries');
	foreach ($groups as $g => $items) {
		if ($items) {
			$h .= '<h3 class="chaos-build__h3">' . $titles[$g] . '</h3><ul class="chaos-build__list">' . implode('', $items) . '</ul>';
		}
	}
	if ($t['paragon']) {
		$h .= '<h3 class="chaos-build__h3">Paragon</h3><ul class="chaos-build__list">';
		foreach ($t['paragon'] as $key => $points) {
			$h .= '<li>' . chaos_h(ucfirst(strtolower(preg_replace('/([a-z])([A-Z])/', '$1 $2', $key)))) . ': <strong>' . (int)$points . '</strong></li>';
		}
		$h .= '</ul>';
	}
	return $h;
}

/** The spells, in rotation order, with their wiki icons. */
function chaos_build_spells_html(array $spells): string {
	if (!$spells) {
		return '<p class="chaos-empty">This code has no spells.</p>';
	}
	$h = '<ol class="chaos-build__list chaos-build__spells">';
	foreach ($spells as $id) {
		$e = chaos_wiki_entry('spell:' . (int)$id);
		if ($e === null) {
			$h .= '<li>Spell ' . (int)$id . '</li>';
			continue;
		}
		$entry = $e['entry'];
		$h .= '<li>' . chaos_wiki_icon($entry, 24, 'chaos-wiki-icon chaos-wiki-icon--row')
			. '<a href="' . chaos_h(chaos_wiki_url('spell:' . (int)$id, 'en')) . '">' . chaos_h($entry['name'] ?? '') . '</a>'
			. ' <span class="chaos-muted">' . chaos_h($entry['sub'] ?? '') . '</span></li>';
	}
	return $h . '</ol>';
}

/** The gear list of [[slot, id]]. */
function chaos_build_gear_html(array $gear): string {
	if (!$gear) {
		return '<p class="chaos-empty">This code has no gear.</p>';
	}
	$slots = chaos_buildcode_slots();
	$h = '<ul class="chaos-build__list chaos-build__gearlist">';
	foreach ($gear as $g) {
		$h .= chaos_build_gear_cell((int)$g['id'], $slots[(int)$g['slot']] ?? '');
	}
	return $h . '</ul>';
}

/** The headline of a card: "Deadeye, level 600", or "A build". */
function chaos_build_title(array $card): string {
	$name = (string)($card['name'] ?? '');
	if ($name !== '' && isset($card['level'])) {
		return $name . ', level ' . (int)$card['level'];
	}
	return $name !== '' ? $name : 'A build';
}

/** The whole build: class, tree, spells, gear and the share box. */
function chaos_build_html(array $card, string $code, string $siteUrl = ''): string {
	$className = (string)($card['name'] ?? '');
	$h = '<div class="chaos-build">';
	if ($className !== '') {
		$base = chaos_base_of((int)$card['vocation']);
		$line = $base !== null ? (chaos_class_lines()[$base]['name'] ?? '') : '';
		$h .= '<p class="chaos-lead">' . chaos_h($className) . ($line !== '' && $line !== $className ? ' (' . chaos_h($line) . ' line)' : '')
			. (isset($card['level']) ? ', level ' . (int)$card['level'] : '') . '. <a href="'
			. chaos_h(chaos_wiki_url('class:' . strtolower(str_replace(' ', '', $line !== '' ? $line : $className)), 'en')) . '">About the class</a></p>';
	}
	$h .= '<div class="chaos-build__cols"><section><h2 class="chaos-subheading">Passive tree</h2>'
		. chaos_build_tree_html($card['tree_info'] ?? null, $className) . '</section>'
		. '<section><h2 class="chaos-subheading">Spell rotation</h2>' . chaos_build_spells_html($card['spells'] ?? array())
		. '<h2 class="chaos-subheading">Gear</h2>' . chaos_build_gear_html($card['gear'] ?? array()) . '</section></div>';
	if (($card['skipped'] ?? 0) > 0) {
		$h .= '<p class="chaos-note">This code has parts from a newer client that the site does not show yet.</p>';
	}
	$link = ($siteUrl !== '' ? rtrim($siteUrl, '/') . '/' : '') . chaos_build_url($code);
	$h .= '<h2 class="chaos-subheading">Share</h2><p><label>Link <input class="chaos-build__share" type="text" readonly value="'
		. chaos_h($link) . '"></label></p><p><label>Code <input class="chaos-build__share" type="text" readonly value="'
		. chaos_h($code) . '"></label></p><p class="chaos-note">In the game: Passive Tree &gt; Build Code, paste the code and press Import. '
		. 'The tree is previewed first; it is applied only by your class line and with the reset price the game shows.</p>';
	return $h . '</div>';
}

} // function_exists
