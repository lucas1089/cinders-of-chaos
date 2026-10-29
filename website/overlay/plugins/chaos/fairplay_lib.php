<?php
/**
 * The fair-play pledge page (pages/fairplay.php, website/README.md "Fair play"): what the store never sells, what it
 * sells and the time savers with their limits. The one source is fairplay/fairplay_data.json (Portuguese and English
 * texts, written from docs/PRICES.md); each entry lists `verify` rules (a file of the repository and a text it must
 * contain) that website/tests/chaos_fairplay_page_test.php checks, so a changed price rule or limit in the server
 * configs fails the test until this page follows.
 */

if (!function_exists('chaos_fairplay_data')) {

/** The data: {updated, never[], sold[], timesavers[], gray}. Empty lists when the file is missing or broken. */
function chaos_fairplay_data(?string $file = null): array {
	$file = $file ?? __DIR__ . '/fairplay/fairplay_data.json';
	$text = is_file($file) ? file_get_contents($file) : false;
	$json = $text === false ? null : json_decode((string)$text, true);
	$out = array('updated' => '', 'never' => array(), 'sold' => array(), 'timesavers' => array(), 'gray' => array());
	if (!is_array($json)) {
		return $out;
	}
	$out['updated'] = is_string($json['updated'] ?? null) ? $json['updated'] : '';
	$out['gray'] = is_array($json['gray'] ?? null) ? $json['gray'] : array();
	foreach (array('never', 'sold', 'timesavers') as $list) {
		foreach (is_array($json[$list] ?? null) ? $json[$list] : array() as $e) {
			if (is_array($e) && is_string($e['id'] ?? null) && is_array($e['title'] ?? null)) {
				$out[$list][] = $e;
			}
		}
	}
	return $out;
}

}
