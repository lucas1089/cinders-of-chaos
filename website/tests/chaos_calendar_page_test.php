<?php
// php website/tests/chaos_calendar_page_test.php : the calendar page (plugins/chaos/calendar_lib.php, pages/calendar.php,
// calendar/calendar_data.json written by website/tools/gen_calendar_data.py): the dates of the owner's plan, the season
// length, "to be set" for what is undecided, the view at a given time, the page in English and Portuguese, the
// "seasons are optional" statement on the page, the home page and the wiki guide, and the menu / sitemap links.
// The data file itself is checked against the server files by gen_calendar_data.py --check. php-cli only.
require __DIR__ . '/chaos_pages_helper.php';
$plugin = CHAOS_TEST_REPO . '/website/overlay/plugins/chaos';
require $plugin . '/lib.php';
require $plugin . '/i18n_lib.php';
require $plugin . '/calendar_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$d = chaos_calendar_data();
$byId = array();
foreach ($d['events'] as $e) { $byId[$e['id']] = $e; }
check(isset($byId['beta1'], $byId['beta2'], $byId['launch'], $byId['wipe']), 'beta 1, beta 2, wipe and launch exist');
check(chaos_calendar_fmt($byId['beta1']['start'], 'pt-BR') === '31/10/2026 15:00 (UTC-3)', 'beta 1: 31/10 15:00');
check(chaos_calendar_fmt($byId['beta2']['start'], 'pt-BR') === '07/11/2026 15:00 (UTC-3)', 'beta 2: 07/11 15:00');
check(chaos_calendar_fmt($byId['launch']['start'], 'en') === '20 Nov 2026, 15:00 (UTC-3)', 'launch: 20 Nov 15:00');
check($byId['launch']['status'] === 'proposal', 'the launch is a proposal until the owner confirms');
check(!empty($byId['beta1']['patchnoteReady']), 'the beta 1 patch note exists');
check(isset($byId['founder']) && chaos_calendar_fmt($byId['founder']['start'], 'pt-BR') === '20/11/2026 15:00 (UTC-3)', 'the Founder Pack sale starts at the launch');
check(chaos_calendar_fmt($byId['founder']['end'], 'pt-BR') === '18/12/2026 15:00 (UTC-3)', 'the Founder Pack sale ends 18/12/2026 15:00');
check(count($d['seasons']) >= 1 && $d['seasons'][0]['lengthWeeks'] === 13, 'Season 1 is 13 weeks');
check(isset($d['wipe']['betaToLaunch'], $d['wipe']['seasonToSeason']), 'both wipe rules');
check(count($d['open']) >= 5, 'open questions are listed');
foreach (array('events', 'cycles', 'open') as $list) {
	foreach ($d[$list] as $e) {
		foreach (array('title', 'text') as $f) {
			if (isset($e[$f])) { check(chaos_bi($e[$f], 'pt-BR') !== '' && chaos_bi($e[$f], 'en') !== '', "{$e['id']}.$f in both languages"); }
		}
	}
}
$json = (string)file_get_contents($plugin . '/calendar/calendar_data.json');
check(chaos_no_dashes($json), 'no em or en dash in the data');
foreach ($d['wipe'] as $w) {
	foreach (array_merge($w['reset'], $w['kept']) as $line) { check(chaos_bi($line, 'pt-BR') !== '' && chaos_bi($line, 'en') !== '', 'wipe line in both languages'); }
}

// the view at a given time
$t = static function (string $iso): int { return (new DateTimeImmutable($iso))->getTimestamp(); };
$v = chaos_calendar_view($d, $t('2026-10-29T12:00:00-03:00'));
check($v['next']['id'] === 'beta1', 'on 29 Oct the next is beta 1');
$v = chaos_calendar_view($d, $t('2026-11-01T00:00:00-03:00'));
check($v['next']['id'] === 'beta2', 'on 1 Nov the next is beta 2');
$v = chaos_calendar_view($d, $t('2026-12-01T00:00:00-03:00'));
check($v['next'] === null, 'after the launch there is no next event');
check($v['seasons'][0]['state'] === ($v['seasons'][0]['known'] ? 'running' : 'tbd'), 'a season with undecided dates is "tbd"');
check($v['cycles'][0]['show'] !== null && $v['cycles'][1]['show'] !== null, 'the PvP and Tower cycles show a window');

// the page
$now = $t('2026-10-29T12:00:00-03:00');
$en = chaos_render_page('calendar', 'en', $now);
$pt = chaos_render_page('calendar', 'pt-BR', $now);
foreach (array('Calendar', 'Open beta, weekend 1', 'Launch', '13 weeks (91 days)', 'To be set', 'What stays and what resets', 'Still to be decided', 'seasons are optional') as $w) {
	check(strpos($en, $w) !== false, "page en says: $w");
}
check(strpos($pt, 'Pacote Fundador') !== false && strpos($en, 'Founder Pack') !== false, 'the page lists the Founder Pack in both languages');
foreach (array('Calendário', 'Beta aberto, fim de semana 1', 'Lançamento', '13 semanas (91 dias)', 'A definir', 'O que fica e o que zera', 'Ainda a decidir', 'as temporadas são opcionais', '20/11/2026 15:00') as $w) {
	check(strpos($pt, $w) !== false, "page pt-BR says: $w");
}
foreach (array($en, $pt) as $html) {
	check(strpos($html, 'id="chaos-calendar-next"') !== false && strpos($html, 'id="wipe-seasonToSeason"') !== false && strpos($html, 'id="chaos-calendar-optional"') !== false, 'page anchors');
	check(strpos($html, 'Fatal') === false && strpos($html, 'Notice') === false, 'no PHP error');
}

// "your character is permanent, seasons are optional, the legacy is cosmetic": the page, the home page and the wiki guide
check(strpos((string)file_get_contents(CHAOS_TEST_REPO . '/website/overlay/layouts/chaos/views/index.php'), 'seu personagem é permanente, as temporadas são opcionais, o legado é cosmético') !== false
	|| stripos((string)file_get_contents(CHAOS_TEST_REPO . '/website/overlay/layouts/chaos/views/index.php'), 'Seu personagem é permanente, as temporadas são opcionais, o legado é cosmético') !== false, 'the home page says it');
foreach (array('pt-BR' => 'Seu personagem é permanente, as temporadas são opcionais, o legado é cosmético', 'en' => 'Your character is permanent, seasons are optional, the legacy is cosmetic') as $l => $line) {
	check(strpos((string)file_get_contents($plugin . "/wiki/guides/seasons.$l.md"), $line) !== false, "the wiki season guide ($l) says it");
}

// links
$setup = (string)file_get_contents(CHAOS_TEST_REPO . '/website/setup/chaos_setup.php');
check(strpos($setup, "p=calendar'") !== false, 'the site menu links the calendar');
check(strpos((string)file_get_contents(CHAOS_TEST_REPO . '/website/setup/write_seo_files.php'), "'calendar'") !== false, 'the sitemap lists the calendar');
check(strpos((string)file_get_contents($plugin . '/seo_lib.php'), 'page_chaos_calendar') !== false, 'the page has a description');

echo $failed ? "chaos_calendar_page_test: $failed of $checks checks failed\n" : "chaos_calendar_page_test: $checks checks OK\n";
exit($failed ? 1 : 0);
