<?php
/**
 * The public calendar (pages/calendar.php, website/README.md "Calendar"): betas, wipe, launch, the seasons, the other
 * cycles, the patch note cadence and the wipe rules. The data is calendar/calendar_data.json, written by
 * website/tools/gen_calendar_data.py from the game server's files (season_config.lua and others), so the page cannot
 * drift from them. Times are server time, UTC-3 (no daylight saving). What is undecided shows as "a definir".
 */

if (!function_exists('chaos_calendar_data')) {

/** The generated data; empty lists when the file is missing or broken. */
function chaos_calendar_data(?string $file = null): array {
	$file = $file ?? __DIR__ . '/calendar/calendar_data.json';
	$text = is_file($file) ? file_get_contents($file) : false;
	$json = $text === false ? null : json_decode((string)$text, true);
	$out = array('events' => array(), 'seasons' => array(), 'cycles' => array(), 'patchnotes' => array(), 'wipe' => array(), 'open' => array());
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

function chaos_calendar_dt(string $iso): ?DateTimeImmutable {
	try {
		return new DateTimeImmutable($iso);
	} catch (Throwable $e) {
		return null;
	}
}

/** "20/11/2026 15:00 (UTC-3)" in Portuguese, "20 Nov 2026, 15:00 (UTC-3)" in English; the time is left out when !$hasTime. */
function chaos_calendar_fmt(string $iso, ?string $lang = null, bool $hasTime = true): string {
	$dt = chaos_calendar_dt($iso);
	if ($dt === null) {
		return '';
	}
	$lang = $lang ?? chaos_lang();
	if ($lang === 'pt-BR') {
		return $dt->format($hasTime ? 'd/m/Y H:i' : 'd/m/Y') . ($hasTime ? ' (UTC-3)' : '');
	}
	return $dt->format($hasTime ? 'j M Y, H:i' : 'j M Y') . ($hasTime ? ' (UTC-3)' : '');
}

/**
 * The view of the data at the time $now (unix): the next event, each season with its state and what to show
 * (dates known, or "to be set" with the proposal), and for every cycle its running or next window.
 * A season with startsAtLaunch false and firstSeason true has no fixed dates yet.
 */
function chaos_calendar_view(array $data, int $now): array {
	$next = null;
	foreach ($data['events'] as $e) {
		$dt = chaos_calendar_dt((string)($e['start'] ?? ''));
		if ($dt !== null && $dt->getTimestamp() > $now && $next === null) {
			$next = $e;
		}
	}
	$seasons = array();
	foreach ($data['seasons'] as $s) {
		$known = !empty($s['startsAtLaunch']) || empty($s['firstSeason']);
		$a = chaos_calendar_dt((string)$s['start']);
		$b = chaos_calendar_dt((string)$s['finish']);
		$state = 'tbd';
		if ($known && $a !== null && $b !== null) {
			$state = $now < $a->getTimestamp() ? 'coming' : ($now < $b->getTimestamp() ? 'running' : 'ended');
		}
		$seasons[] = array('season' => $s, 'known' => $known, 'state' => $state);
	}
	$cycles = array();
	foreach ($data['cycles'] as $c) {
		$show = null;
		foreach ($c['windows'] ?? array() as $w) {
			$end = chaos_calendar_dt((string)$w['end']);
			if ($end !== null && $end->getTimestamp() > $now) {
				$start = chaos_calendar_dt((string)$w['start']);
				$show = array('window' => $w, 'running' => $start !== null && $start->getTimestamp() <= $now);
				break;
			}
		}
		$cycles[] = array('cycle' => $c, 'show' => $show);
	}
	return array('next' => $next, 'seasons' => $seasons, 'cycles' => $cycles);
}

}
