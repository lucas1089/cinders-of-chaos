<?php
/**
 * The beginner guide (pages/guide.php, website/README.md "Beginner guide (O373)"): the first steps of a new player, then
 * every feature by the level where it opens, then what any level can use. The data is guide/guide_data.json, written by
 * server/tools/gen_guide_data.lua from the game's "How it works" cards (the same texts the client shows on a window's ?
 * button and in its help search), unlocks_config.lua and server/tools/guide_config.lua, so the page cannot drift from the
 * game. Texts come in both languages ({"en", "pt-BR"}, chaos_bi()).
 */

if (!function_exists('chaos_guide_data')) {

/** The generated data; empty lists when the file is missing or broken. */
function chaos_guide_data(?string $file = null): array {
	$file = $file ?? __DIR__ . '/guide/guide_data.json';
	$text = is_file($file) ? file_get_contents($file) : false;
	$json = $text === false ? null : json_decode((string)$text, true);
	$out = array('intro' => array(), 'headings' => array(), 'steps' => array(), 'levels' => array(), 'anytime' => array(), 'cards' => array());
	if (!is_array($json)) {
		return $out;
	}
	foreach (array_keys($out) as $k) {
		if (is_array($json[$k] ?? null)) {
			$out[$k] = $json[$k];
		}
	}
	return $out;
}

/** The sections in page order: [{id, title, groups: [{id, level|null, cards: [[key, card, tip|null]]}]}]; unknown keys dropped. */
function chaos_guide_view(array $data): array {
	$card = static function (string $key) use ($data): ?array {
		return is_array($data['cards'][$key] ?? null) ? $data['cards'][$key] : null;
	};
	$steps = array();
	foreach ($data['steps'] as $s) {
		$c = $card((string)($s['card'] ?? ''));
		if ($c !== null) {
			$steps[] = array((string)$s['card'], $c, $s['tip'] ?? null);
		}
	}
	$levels = array();
	foreach ($data['levels'] as $l) {
		$list = array();
		foreach ((array)($l['cards'] ?? array()) as $k) {
			$c = $card((string)$k);
			if ($c !== null) {
				$list[] = array((string)$k, $c, null);
			}
		}
		if ($list) {
			$levels[] = array('id' => 'level-' . (int)$l['level'], 'level' => (int)$l['level'], 'cards' => $list);
		}
	}
	$any = array();
	foreach ($data['anytime'] as $k) {
		$c = $card((string)$k);
		if ($c !== null) {
			$any[] = array((string)$k, $c, null);
		}
	}
	$h = $data['headings'];
	return array(
		array('id' => 'steps', 'title' => $h['steps'] ?? 'First steps', 'groups' => array(array('id' => '', 'level' => null, 'cards' => $steps))),
		array('id' => 'levels', 'title' => $h['levels'] ?? 'As you level up', 'groups' => $levels),
		array('id' => 'anytime', 'title' => $h['anytime'] ?? 'Any level', 'groups' => array(array('id' => '', 'level' => null, 'cards' => $any))),
	);
}

/** One card: title, level and menu path, the tip of a first step, the rows under their headings. Everything escaped. */
function chaos_guide_card_html(string $key, array $card, $tip, array $headings, ?string $lang = null): string {
	$h = static function ($s): string { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); };
	$meta = array();
	if (isset($card['level']) && $card['level'] !== null) {
		$meta[] = chaos_t_in($lang, 'Level %d+', (int)$card['level']);
	}
	if (!empty($card['menu'])) {
		$meta[] = chaos_t_in($lang, 'In game: %s', (string)$card['menu']);
	}
	$out = '<article class="chaos-guide-card" id="card-' . $h($key) . '">';
	$out .= '<h3 class="chaos-guide-card__title">' . $h(chaos_bi($card['title'] ?? '', $lang)) . '</h3>';
	if ($meta) {
		$out .= '<p class="chaos-guide-card__meta">' . $h(implode(' · ', $meta)) . '</p>';
	}
	if ($tip !== null && chaos_bi($tip, $lang) !== '') {
		$out .= '<p class="chaos-guide-card__tip">' . $h(chaos_bi($tip, $lang)) . '</p>';
	}
	$out .= '<dl class="chaos-guide-card__rows">';
	foreach ((array)($card['rows'] ?? array()) as $row) {
		$id = (string)($row['id'] ?? '');
		$label = chaos_bi($headings['rows'][$id] ?? $id, $lang);
		$out .= '<dt>' . $h($label) . '</dt><dd>' . $h(chaos_bi($row['text'] ?? '', $lang)) . '</dd>';
	}
	return $out . '</dl></article>';
}

}
