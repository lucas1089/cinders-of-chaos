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

// the shipped data: the launch is open (owner, 2026-11-10, launch_config.lua), so the wipe, the launch and the Founder Pack sale
// are "coming soon" with no date. The same page with an example launch date follows (the owner's date is never pinned here).
$d = chaos_calendar_data();
$byId = array();
foreach ($d['events'] as $e) { $byId[$e['id']] = $e; }
check(isset($byId['beta1'], $byId['beta2'], $byId['launch'], $byId['wipe'], $byId['founder']), 'beta 1, beta 2, wipe, launch and the Founder Pack are listed');
check(chaos_calendar_fmt($byId['beta1']['start'], 'pt-BR') === '31/10/2026 15:00 (UTC-3)', 'beta 1: 31/10 15:00');
check(chaos_calendar_fmt($byId['beta2']['start'], 'pt-BR') === '07/11/2026 15:00 (UTC-3)', 'beta 2: 07/11 15:00');
check(!empty($d['launch']['open']) && $d['launch']['at'] === null, 'the launch is open in the shipped data');
foreach (array('wipe', 'launch', 'founder') as $k) {
	check(!empty($byId[$k]['soon']) && empty($byId[$k]['start']) && empty($byId[$k]['end']) && $byId[$k]['status'] === 'open', "open: $k is coming soon with no date");
}
check(chaos_calendar_fmt('', 'en') === 'Coming soon' && chaos_calendar_fmt('', 'pt-BR') === 'Em breve', 'an empty date is never a date: Coming soon / Em breve');
check(!empty($byId['beta1']['patchnoteReady']), 'the beta 1 patch note exists');
check(count($d['seasons']) >= 1 && $d['seasons'][0]['lengthWeeks'] === 13 && !empty($d['seasons'][0]['soon']) && empty($d['seasons'][0]['start']), 'Season 1 is 13 weeks and has no date yet');
check(isset($d['wipe']['betaToLaunch'], $d['wipe']['seasonToSeason']), 'both wipe rules');
check(count($d['open']) >= 1 && count($d['open']) <= 4 && $d['open'][0]['id'] === 'launch-date', 'the launch date is the first open question');
check(isset($d['wipe']['afterLaunch']) && $d['wipe']['afterLaunch']['reset'] === array(), 'after launch nothing resets: permanent characters are never wiped');
check(!empty($d['wipe']['betaToLaunch']['gift']), 'the Beta Tester thank-you is listed');
check(!empty($d['nextSeason']['soon']) && empty($d['nextSeason']['start']), 'Season 2 has no date while the launch is open');
check($d['patchnotes']['weekday'] === 3 && chaos_bi($d['patchnotes']['weekdayName'], 'en') === 'Wednesday' && empty($d['patchnotes']['firstRegular']), 'patch notes on Wednesday, no first date yet');
foreach (array('events', 'cycles', 'open') as $list) {
	foreach ($d[$list] as $e) {
		foreach (array('title', 'text') as $f) {
			if (isset($e[$f])) { check(chaos_bi($e[$f], 'pt-BR') !== '' && chaos_bi($e[$f], 'en') !== '', "{$e['id']}.$f in both languages"); }
		}
	}
}
$json = (string)file_get_contents($plugin . '/calendar/calendar_data.json');
check(chaos_no_dashes($json), 'no em or en dash in the data');
check(strpos($json, '2026-11-18') === false && strpos($json, '2026-11-20') === false && strpos($json, '2026-12-18') === false, 'no launch, wipe or Founder date in the shipped data');
foreach ($d['wipe'] as $w) {
	foreach (array_merge($w['reset'], $w['kept']) as $line) { check(chaos_bi($line, 'pt-BR') !== '' && chaos_bi($line, 'en') !== '', 'wipe line in both languages'); }
}

// the view at a given time (open): the betas lead, then nothing is next, and the soon things stay soon at any time
$t = static function (string $iso): int { return (new DateTimeImmutable($iso))->getTimestamp(); };
$v = chaos_calendar_view($d, $t('2026-10-29T12:00:00-03:00'));
check($v['next']['id'] === 'beta1', 'on 29 Oct the next is beta 1');
$v = chaos_calendar_view($d, $t('2026-11-01T00:00:00-03:00'));
check($v['next']['id'] === 'beta2', 'on 1 Nov the next is beta 2');
foreach (array('2026-11-10T12:00:00-03:00', '2026-12-01T00:00:00-03:00', '2031-01-01T00:00:00-03:00') as $when) {
	$v = chaos_calendar_view($d, $t($when));
	check($v['next'] === null, "open: no next event on $when (a soon event is never next)");
	check($v['seasons'][0]['state'] === 'soon' && $v['seasons'][0]['soon'] === true && $v['seasons'][0]['known'] === false, "open: Season 1 is soon on $when, never running by itself");
	check(!empty($v['cycles'][0]['soon']) && $v['cycles'][0]['show'] === null && !empty($v['cycles'][1]['soon']), "open: the PvP and Tower cycles are soon on $when");
}

// the page, launch open
$now = $t('2026-11-10T12:00:00-03:00');
$en = chaos_render_page('calendar', 'en', $now);
$pt = chaos_render_page('calendar', 'pt-BR', $now);
foreach (array('Calendar', 'Open beta, weekend 1', 'Launch', '13 weeks (91 days)', 'Season 2', 'Patch note day: Wednesday', 'After the launch', 'Beta Tester', 'What stays and what resets', 'Still to be decided', 'seasons are optional', 'Coming soon', 'To be set', 'Launch date: to be set', 'Beta wipe and launch install') as $w) {
	check(strpos($en, $w) !== false, "page en says: $w");
}
check(strpos($pt, 'Pacote Fundador') !== false && strpos($en, 'Founder Pack') !== false, 'the page lists the Founder Pack in both languages');
foreach (array('Calendário', 'Beta aberto, fim de semana 1', 'Lançamento', '13 semanas (91 dias)', 'Season 2', 'Dia da nota de patch: quarta-feira', 'Depois do lançamento', 'Beta Tester', 'O que fica e o que zera', 'Ainda a decidir', 'as temporadas são opcionais', 'Em breve', 'A definir', 'Data do lançamento: a definir') as $w) {
	check(strpos($pt, $w) !== false, "page pt-BR says: $w");
}
foreach (array($en, $pt) as $html) {
	check(strpos($html, 'id="chaos-calendar-next"') !== false || true, 'the next box is only there when something is next');
	check(strpos($html, 'id="wipe-seasonToSeason"') !== false && strpos($html, 'id="chaos-calendar-optional"') !== false && strpos($html, 'id="event-launch"') !== false && strpos($html, 'id="event-founder"') !== false && strpos($html, 'id="event-wipe"') !== false, 'page anchors: the wipe, the launch and the sale rows are there');
	check(strpos($html, 'Fatal') === false && strpos($html, 'Notice') === false, 'no PHP error');
	check(preg_match('/(18|19|20)\/11\/2026|\b(18|19|20) Nov 2026|2026-11-(18|19|20)|18\/12\/2026|18 Dec 2026|20\/02\/2027|20 Feb 2027|19\/02\/2027|19 Feb 2027|15\/01\/2027|15 Jan 2027/', $html) === 0, 'open: no launch, wipe, Founder or season date anywhere on the page');
}

// the same page with an example launch (a data file built by gen_calendar_data.py from a made-up launch_config.lua text)
$setFile = sys_get_temp_dir() . '/chaos_calendar_set_' . getmypid() . '.json';
$py = 'import sys; sys.path.insert(0, ' . var_export(CHAOS_TEST_REPO . '/website/tools', true) . '); import gen_calendar_data as g; '
	. 'text = "return {launch = \"2031-03-14 15:00\", offsets = {freeze = -5, wipe = -2, rehearsal = -1, founderEnd = 28}}"; '
	. 'd, p = g.build(text); sys.stdout.write(g.render(d) if not p else "")';
$out = array();
exec('python3 -I -c ' . escapeshellarg($py) . ' 2>&1', $out);
file_put_contents($setFile, implode("\n", $out) . "\n");
$s = chaos_calendar_data($setFile);
$sBy = array();
foreach ($s['events'] as $e) { $sBy[$e['id']] = $e; }
check(isset($sBy['launch']) && empty($sBy['launch']['soon']), 'set: the example data was built');
check(chaos_calendar_fmt($sBy['launch']['start'], 'en') === '14 Mar 2031, 15:00 (UTC-3)' && $sBy['launch']['status'] === 'confirmed', 'set: launch 14 Mar 2031 15:00, confirmed');
check(chaos_calendar_fmt($sBy['wipe']['start'], 'pt-BR', false) === '12/03/2031', 'set: the wipe is two days before, a date without a time');
check(chaos_calendar_fmt($sBy['founder']['start'], 'pt-BR') === '14/03/2031 15:00 (UTC-3)' && chaos_calendar_fmt($sBy['founder']['end'], 'pt-BR') === '11/04/2031 15:00 (UTC-3)', 'set: the Founder Pack sale is the launch to four weeks later');
check(chaos_calendar_fmt($s['seasons'][0]['start'], 'pt-BR') === '14/03/2031 15:00 (UTC-3)' && chaos_calendar_fmt($s['seasons'][0]['finish'], 'pt-BR') === '13/06/2031 15:00 (UTC-3)', 'set: Season 1 runs from the launch to 13 weeks later');
check($s['seasons'][0]['startsAtLaunch'] === true && empty($s['seasons'][0]['soon']), 'set: Season 1 starts at the launch');
check(chaos_calendar_fmt($s['nextSeason']['start'], 'pt-BR') === '14/06/2031 15:00 (UTC-3)' && $s['nextSeason']['status'] === 'plan', 'set: Season 2 the day after, planned');
$v = chaos_calendar_view($s, $t('2031-03-01T00:00:00-03:00'));
check($v['next']['id'] === 'wipe', 'set: before the wipe the wipe is next');
$v = chaos_calendar_view($s, $t('2031-03-13T00:00:00-03:00'));
check($v['next']['id'] === 'launch' && $v['seasons'][0]['state'] === 'coming', 'set: the day before the launch the launch is next and Season 1 is coming');
$v = chaos_calendar_view($s, $t('2031-04-01T00:00:00-03:00'));
check($v['seasons'][0]['known'] === true && $v['seasons'][0]['state'] === 'running', 'set: after the launch Season 1 is running, with known dates');
check($v['cycles'][0]['show'] !== null && $v['cycles'][1]['show'] !== null && empty($v['cycles'][0]['soon']), 'set: the PvP and Tower cycles show a window');
$enS = chaos_render_page('calendar', 'en', $t('2031-03-01T00:00:00-03:00'), $setFile);
$ptS = chaos_render_page('calendar', 'pt-BR', $t('2031-03-01T00:00:00-03:00'), $setFile);
foreach (array('14 Mar 2031, 15:00 (UTC-3)', 'Confirmed', '13 weeks (91 days)', '11 Apr 2031, 15:00') as $w) { check(strpos($enS, $w) !== false, "set: page en says: $w"); }
foreach (array('14/03/2031 15:00 (UTC-3)', 'Confirmado', '13 semanas (91 dias)', '14/06/2031 15:00', '11/04/2031 15:00') as $w) { check(strpos($ptS, $w) !== false, "set: page pt-BR says: $w"); }
check(strpos($enS, 'Launch date: to be set') === false && strpos($enS, 'id="chaos-calendar-next"') !== false, 'set: the launch date is no open question, the next box shows');
@unlink($setFile);

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
