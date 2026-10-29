<?php
// php website/tests/chaos_creators_page_test.php : the creator program page (plugins/chaos/creators_lib.php,
// pages/creators.php, creators/creators_data.json, creators/media_kit_manifest.json from website/tools/gen_media_kit.py):
// the data in both languages, the creator code numbers against creator_codes_config.lua, the media kit manifest against
// the art on disk, no zip committed, the page in English and Portuguese, and the menu / sitemap links. php-cli only.
require __DIR__ . '/chaos_pages_helper.php';
$plugin = CHAOS_TEST_REPO . '/website/overlay/plugins/chaos';
require $plugin . '/lib.php';
require $plugin . '/i18n_lib.php';
require $plugin . '/creators_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$d = chaos_creators_data();
$ids = array_map(static function ($b) { return $b['id']; }, $d['benefits']);
foreach (array('code', 'betaopen', 'launchbonus', 'mediakit') as $want) { check(in_array($want, $ids, true), "benefit: $want"); }
foreach ($d['benefits'] as $b) {
	check(in_array($b['status'], array('built', 'open'), true), "{$b['id']} has a known state");
	check(chaos_bi($b['text'], 'pt-BR') !== '' && chaos_bi($b['text'], 'en') !== '', "{$b['id']} in both languages");
	check(chaos_verify_rules((array)($b['verify'] ?? array())) === array(), "{$b['id']} verify: " . implode('; ', chaos_verify_rules((array)($b['verify'] ?? array()))));
}
// the owner's criteria (2026-10-29) are in the data and in the list
$crit = chaos_creators_criteria();
check($crit === array('hoursWeek' => 4, 'viewers' => 10, 'followers' => 500), 'criteria: 4 hours a week, 10 viewers or 500 followers');
$qualify = json_encode($d['qualify']['items'], JSON_UNESCAPED_UNICODE);
foreach (array('4 horas', '10 espectadores', '500 seguidores', 'RMT') as $w) { check(strpos($qualify, $w) !== false, "criteria list says: $w"); }
check($d['qualify']['status'] === 'confirmed', 'the criteria are confirmed');
// the launch window: 15% instead of 10% for 30 days from the launch, in the config and on the page
$lua = (string)file_get_contents(CHAOS_TEST_REPO . '/server/data/scripts/chaos/creator_codes_config.lua');
check(strpos($lua, 'launchBonusPct = 15') !== false && strpos($lua, 'sharePct = 10') !== false && strpos($lua, 'launchBonusDays = 30') !== false, 'config: 15% in the window, 10% otherwise');
foreach ($d['benefits'] as $b) { if ($b['id'] === 'launchbonus') { check($b['status'] === 'built', 'the launch bonus is built'); } }
check(!is_file(CHAOS_TEST_REPO . '/server/data/scripts/chaos/beta_keys.lua'), 'there is no beta key system: the beta is open');
check(strpos(json_encode($d, JSON_UNESCAPED_UNICODE), 'a definir') === false, 'no \"a definir\" left in the creator data');
foreach (array('items', 'steps') as $k) {
	foreach (($k === 'items' ? $d['qualify']['items'] : $d['apply']['steps']) as $line) { check(chaos_bi($line, 'pt-BR') !== '' && chaos_bi($line, 'en') !== '', "$k line in both languages"); }
}
check(chaos_no_dashes((string)file_get_contents($plugin . '/creators/creators_data.json')), 'no em or en dash in the data');
check(count($d['open']) >= 1, 'open questions are listed');

// the media kit manifest against the art on disk; the zip is not in the repository
$kit = chaos_creators_kit();
check(($kit['zip']['name'] ?? '') === 'cinders-of-chaos-media-kit.zip' && ($kit['zip']['path'] ?? '') === 'press/cinders-of-chaos-media-kit.zip', 'the zip name and path');
check(count($kit['files']) >= 9, 'the kit lists its files');
$names = array();
foreach ($kit['files'] as $f) {
	$names[] = $f['name'];
	$path = $f['name'] === 'logo.png' ? CHAOS_TEST_REPO . '/website/overlay/layouts/chaos/assets/img/logo.png'
		: (strpos($f['name'], 'art/') === 0 ? CHAOS_TEST_REPO . '/website/' . $f['name'] : '');
	if ($path !== '') {
		check(is_file($path) && hash_file('sha256', $path) === $f['sha256'] && filesize($path) === $f['bytes'], "kit file {$f['name']} matches the art on disk");
	}
}
check(in_array('logo.png', $names, true) && in_array('art/social-share-1200x630.png', $names, true), 'logo and banner in the kit');
check(in_array('ficha-tecnica.pt-BR.txt', $names, true) && in_array('fact-sheet.en.txt', $names, true), 'fact sheets in pt-BR and en');
check(glob(CHAOS_TEST_REPO . '/website/{,overlay/}press/*.zip', GLOB_BRACE) === array(), 'no zip committed under website/');
check($kit['zip']['bytes'] < 5 * 1048576, 'the kit stays small');

// the page
$en = chaos_render_page('creators', 'en');
$pt = chaos_render_page('creators', 'pt-BR');
foreach (array('Creator Program', 'Who qualifies', 'What you get', 'How to apply', 'Application form', 'Log in to send an application', 'Download the media kit', 'Open beta') as $w) { check(strpos($en, $w) !== false, "page en says: $w"); }
foreach (array('Programa de Criadores', 'Quem pode participar', 'O que você recebe', 'Como pedir', 'Formulário de pedido', 'Entre na sua conta para enviar um pedido', 'Baixar o kit de mídia', 'Beta aberto') as $w) { check(strpos($pt, $w) !== false, "page pt-BR says: $w"); }
foreach (array($en, $pt) as $html) {
	check(strpos($html, 'press/cinders-of-chaos-media-kit.zip') !== false, 'the page links the zip');
	check(strpos($html, 'id="benefit-code"') !== false && strpos($html, 'id="benefit-betaopen"') !== false, 'benefit anchors');
	check(strpos($html, 'id="chaos-creators-discord"') === false, 'no Discord link while the owner has not set one');
	check(strpos($html, 'id="chaos-creators-form"') === false, 'no form for a visitor who is not logged in');
	check(strpos($html, 'Fatal') === false && strpos($html, 'Notice') === false, 'no PHP error');
}

// links
check(strpos((string)file_get_contents(CHAOS_TEST_REPO . '/website/setup/chaos_setup.php'), "p=creators'") !== false, 'the site menu links the program');
check(strpos((string)file_get_contents(CHAOS_TEST_REPO . '/website/setup/write_seo_files.php'), "'creators'") !== false, 'the sitemap lists the program');
check(strpos((string)file_get_contents(CHAOS_TEST_REPO . '/website/install_site.sh'), 'gen_media_kit.py') !== false, 'the installer builds the zip');

echo $failed ? "chaos_creators_page_test: $failed of $checks checks failed\n" : "chaos_creators_page_test: $checks checks OK\n";
exit($failed ? 1 : 0);
