<?php
/**
 * The launch moment on the website (O463): the one value of the game server's launch_config.lua (CHAOS_SERVER_DATA), "open"
 * (no date yet, the owner's hold of 2026-11-10) or "YYYY-MM-DD HH:MM" in server time (America/Sao_Paulo, UTC-3).
 * The game server reads the same file (launch_core.lua); website/tools/gen_calendar_data.py, gen_promo_kit.py and
 * gen_streamer_kit.py read it too. In the open state every text that would print the date says "Coming soon" ("Em breve").
 * A missing or broken file reads as open (fail closed): the site never prints a date it cannot read.
 */

if (!function_exists('chaos_launch_config')) {

/**
 * The launch of a launch_config.lua text (default: the server's file): {open: bool, launch: DateTimeImmutable|null,
 * raw: string|null}. open is true unless the value is a real "YYYY-MM-DD HH:MM".
 */
function chaos_launch_config(?string $text = null): array {
	$text = $text ?? (function_exists('chaos_read_server_file') ? chaos_read_server_file('scripts/chaos/launch_config.lua') : '');
	$text = (string)preg_replace('/--[^\n]*/', '', $text);
	$raw = null;
	if (preg_match('/(?<![\w.])launch\s*=\s*"([^"\n]*)"/', $text, $m)) {
		$raw = $m[1];
	}
	$dt = null;
	if ($raw !== null && $raw !== 'open') {
		$d = DateTimeImmutable::createFromFormat('!Y-m-d H:i', $raw, new DateTimeZone('America/Sao_Paulo'));
		$errors = DateTimeImmutable::getLastErrors();
		if ($d !== false && (!$errors || ($errors['warning_count'] === 0 && $errors['error_count'] === 0)) && $d->format('Y-m-d H:i') === $raw) {
			$dt = $d;
		}
	}
	return array('open' => $dt === null, 'launch' => $dt, 'raw' => $raw);
}

/** "Em breve" or "Coming soon". */
function chaos_launch_soon_text(string $lang): string {
	return $lang === 'pt-BR' ? 'Em breve' : 'Coming soon';
}

/**
 * The launch plus $days days as text in $lang: "20/11/2026 15:00" or "20 Nov 2026, 15:00" (with "(UTC-3)" when $zone), the
 * date alone when !$withTime; "Em breve" / "Coming soon" while the launch is open.
 */
function chaos_launch_text(string $lang, ?array $cfg = null, int $days = 0, bool $withTime = true, bool $zone = false): string {
	$cfg = $cfg ?? chaos_launch_config();
	if ($cfg['launch'] === null) {
		return chaos_launch_soon_text($lang);
	}
	$dt = $days === 0 ? $cfg['launch'] : $cfg['launch']->modify(($days > 0 ? '+' : '') . $days . ' days');
	if ($lang === 'pt-BR') {
		return $dt->format($withTime ? 'd/m/Y H:i' : 'd/m/Y') . ($withTime && $zone ? ' (UTC-3)' : '');
	}
	return $dt->format($withTime ? 'j M Y, H:i' : 'j M Y') . ($withTime && $zone ? ' (UTC-3)' : '');
}

}
