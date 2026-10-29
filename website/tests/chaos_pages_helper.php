<?php
// Shared by chaos_fairplay_page_test.php, chaos_calendar_page_test.php and chaos_creators_page_test.php (not a test).
// Renders a plugin page in its own php process, so the language of the request (&l=) and the clock are fresh each time,
// and checks the `verify` rules of the data files against the repository (file + text it must contain).

define('CHAOS_TEST_REPO', realpath(__DIR__ . '/../..'));

/** The HTML of pages/<page>.php for ?l=<lang>; $now sets $GLOBALS['chaos_calendar_now'] (the calendar's clock). */
function chaos_render_page(string $page, string $lang, ?int $now = null): string {
	$plugin = CHAOS_TEST_REPO . '/website/overlay/plugins/chaos';
	$code = '$config = array("chaos" => array("server_data" => ' . var_export(CHAOS_TEST_REPO . '/server/data', true) . '));'
		. '$GLOBALS["config"] = $config; $_GET = array("plugin" => "chaos", "p" => ' . var_export($page, true) . ', "l" => ' . var_export($lang, true) . ');'
		. ($now !== null ? '$GLOBALS["chaos_calendar_now"] = ' . (int)$now . ';' : '')
		. 'ob_start(); error_reporting(E_ALL & ~E_WARNING); require ' . var_export($plugin . '/lib.php', true) . ';'
		. 'include ' . var_export($plugin . '/pages/' . $page . '.php', true) . '; echo ob_get_clean();';
	$out = array();
	$status = 0;
	exec(escapeshellarg(PHP_BINARY) . ' -r ' . escapeshellarg($code) . ' 2>&1', $out, $status);
	return implode("\n", $out);
}

/** Failures of the verify rules [{file, has}] (empty when every rule holds). */
function chaos_verify_rules(array $rules): array {
	$bad = array();
	foreach ($rules as $r) {
		$path = CHAOS_TEST_REPO . '/' . ($r['file'] ?? '');
		if (!is_file($path) || strpos((string)file_get_contents($path), (string)($r['has'] ?? "\0")) === false) {
			$bad[] = ($r['file'] ?? '?') . ': ' . ($r['has'] ?? '?');
		}
	}
	return $bad;
}

/** No em-dash or en-dash in a text (the docs and page prose rule). */
function chaos_no_dashes(string $text): bool {
	return strpos($text, "\u{2014}") === false && strpos($text, "\u{2013}") === false;
}
