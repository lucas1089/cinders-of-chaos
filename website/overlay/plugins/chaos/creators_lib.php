<?php
/**
 * The creator program page (pages/creators.php, website/README.md "Creator program"): who qualifies, what a creator
 * gets, how to apply, the media kit. Texts and states are creators/creators_data.json (pt-BR and en); the media kit
 * file list is creators/media_kit_manifest.json (website/tools/gen_media_kit.py). Each benefit may list `verify` rules
 * that website/tests/chaos_creators_page_test.php checks against the server configs.
 */

if (!function_exists('chaos_creators_data')) {

function chaos_creators_json(string $name): array {
	$file = __DIR__ . '/creators/' . $name;
	$text = is_file($file) ? file_get_contents($file) : false;
	$json = $text === false ? null : json_decode((string)$text, true);
	return is_array($json) ? $json : array();
}

/** {updated, qualify, benefits[], apply, open[]}; empty parts when the file is missing. */
function chaos_creators_data(): array {
	$j = chaos_creators_json('creators_data.json');
	return array(
		'updated' => is_string($j['updated'] ?? null) ? $j['updated'] : '',
		'qualify' => is_array($j['qualify'] ?? null) ? $j['qualify'] : array('status' => '', 'intro' => '', 'items' => array()),
		'benefits' => is_array($j['benefits'] ?? null) ? $j['benefits'] : array(),
		'apply' => is_array($j['apply'] ?? null) ? $j['apply'] : array('intro' => '', 'steps' => array()),
		'open' => is_array($j['open'] ?? null) ? $j['open'] : array(),
	);
}

/** {zip: {name, path, bytes, sha256}, files: [{name, bytes}]}; zip empty without the manifest. */
function chaos_creators_kit(): array {
	$j = chaos_creators_json('media_kit_manifest.json');
	return array('zip' => is_array($j['zip'] ?? null) ? $j['zip'] : array(), 'files' => is_array($j['files'] ?? null) ? $j['files'] : array());
}

function chaos_creators_size(int $bytes): string {
	return $bytes >= 1048576 ? number_format($bytes / 1048576, 1, '.', '') . ' MB' : number_format(max(1, (int)round($bytes / 1024))) . ' KB';
}

}
