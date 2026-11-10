<?php
/**
 * The Starter Builds guide (pages/starterbuilds.php, O448): three Recommended builds for every class, each with what it
 * does, how it plays, its price, the keystones it walks to (with the point each one arrives at), the spells to lean on, what
 * to wear, a card set that fits and an import code for each point cut. The data is guide/starter_builds_data.json, written by
 * server/tools/gen_starter_builds.lua from the game's own build data (passive_builds_config.lua, passive_builds_data.lua)
 * and the hand-written words of server/tools/starter_builds_config.lua, so the page cannot drift from the game. The guide is
 * qualitative: it holds no damage figure, no percent and no DPS (the generator and the tests stop on one). Texts come in
 * both languages ({"en", "pt-BR"}, chaos_bi()).
 */

if (!function_exists('chaos_starter_data')) {

/** The generated data; empty lists when the file is missing or broken. */
function chaos_starter_data(?string $file = null): array {
	$file = $file ?? __DIR__ . '/guide/starter_builds_data.json';
	$text = is_file($file) ? file_get_contents($file) : false;
	$json = $text === false ? null : json_decode((string)$text, true);
	$out = array('intro' => array(), 'howTo' => array(), 'headings' => array(), 'cuts' => array(), 'classes' => array(), 'format' => '');
	if (!is_array($json)) {
		return $out;
	}
	foreach (array_keys($out) as $k) {
		if (isset($json[$k]) && (is_array($json[$k]) || is_string($json[$k]))) {
			$out[$k] = $json[$k];
		}
	}
	return $out;
}

/** A heading or label of the data in the language of the page. */
function chaos_starter_label(array $data, string $key, ?string $lang = null): string {
	return chaos_bi($data['headings'][$key] ?? $key, $lang);
}

/** "23 points, level 100" in the language of the page. */
function chaos_starter_cut_label(array $data, int $points, int $level, ?string $lang = null): string {
	return $points . ' ' . chaos_starter_label($data, 'points', $lang) . ', ' . chaos_starter_label($data, 'level', $lang) . ' ' . $level;
}

/** A tree code as the game writes it (CB<version>- and url-safe base64), or '' for anything else. */
function chaos_starter_code(string $code): string {
	return preg_match('/^CB\d{1,3}-[A-Za-z0-9_-]{4,900}$/', $code) === 1 ? $code : '';
}

/** One build as a card: name and kind, what it does, how it plays, price, keystones, spells, gear, cards, codes. Escaped. */
function chaos_starter_build_html(array $b, array $data, ?string $lang = null): string {
	$h = static function ($s): string { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); };
	$id = (string)($b['id'] ?? '');
	$out = '<article class="chaos-guide-card chaos-sb-build" id="build-' . $h($id) . '">';
	$out .= '<h3 class="chaos-guide-card__title">' . $h($b['name'] ?? '') . '</h3>';
	$out .= '<p class="chaos-guide-card__meta">' . $h(chaos_bi($b['kind'] ?? '', $lang)) . '</p>';
	$out .= '<dl class="chaos-guide-card__rows">';
	$row = static function (string $label, string $html) use ($h): string {
		return '<dt>' . $h($label) . '</dt><dd>' . $html . '</dd>';
	};
	$out .= $row(chaos_starter_label($data, 'what', $lang), $h(chaos_bi($b['what'] ?? '', $lang)));
	$out .= $row(chaos_starter_label($data, 'plays', $lang), $h(chaos_bi($b['style'] ?? '', $lang)));
	$out .= $row(chaos_starter_label($data, 'price', $lang), $h(chaos_bi($b['price'] ?? '', $lang)));
	$keystones = array();
	foreach ((array)($b['keystones'] ?? array()) as $k) {
		$keystones[] = '<strong>' . $h($k['name'] ?? '') . '</strong>, ' . $h(chaos_starter_label($data, 'point', $lang)) . ' ' . (int)($k['point'] ?? 0);
	}
	$out .= $row(chaos_starter_label($data, 'keystones', $lang), $keystones ? implode('<br>', $keystones) : $h(chaos_starter_label($data, 'noKeystone', $lang)));
	$spells = array();
	foreach ((array)($b['spells'] ?? array()) as $s) {
		$spells[] = $h($s);
	}
	$out .= $row(chaos_starter_label($data, 'cast', $lang), implode(', ', $spells));
	$out .= $row(chaos_starter_label($data, 'wear', $lang), $h(chaos_bi($b['gear'] ?? '', $lang)));
	$cards = $b['cards'] ?? array();
	if (isset($cards['set'])) {
		$out .= $row(chaos_starter_label($data, 'cards', $lang), '<strong>' . $h(chaos_bi($cards['name'] ?? '', $lang)) . '</strong>: ' . $h(chaos_bi($cards['text'] ?? '', $lang)));
	} elseif (isset($cards['none'])) {
		$out .= $row(chaos_starter_label($data, 'cards', $lang), $h(chaos_bi($cards['none'], $lang)));
	}
	$codes = array();
	foreach ((array)($b['codes'] ?? array()) as $c) {
		$code = chaos_starter_code((string)($c['code'] ?? ''));
		if ($code !== '') {
			$codes[] = '<span class="chaos-sb-cut">' . $h(chaos_starter_cut_label($data, (int)($c['points'] ?? 0), (int)($c['level'] ?? 0), $lang))
				. '</span> <code class="chaos-sb-code">' . $h($code) . '</code>';
		}
	}
	$out .= $row(chaos_starter_label($data, 'codes', $lang), $codes ? implode('<br>', $codes) : '');
	return $out . '</dl></article>';
}

}
