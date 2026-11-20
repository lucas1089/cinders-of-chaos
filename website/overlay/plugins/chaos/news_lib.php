<?php
/**
 * The news page "Novidades" / "News" (pages/news.php, website/README.md "News and changelog (O687)"): the changes of
 * the game by week, newest first, the last weeks in full and the older ones in an archive. The data is
 * news/news_data.json, written by website/tools/gen_changelog.py from the patch notes and the curated player-facing
 * entries, so the page cannot drift from them. This file only reads that data and builds HTML; every text is escaped.
 *
 * O688 (README "Featured news (O688)"): a curated entry may be `featured` (a banner on the front page, a NEW badge, a tag
 * on the guide card or server info section it points at) while it is younger than `featured_days`, and may be gated by
 * `live_when` (`flag:<key>` read from $config['chaos']['live'] or the server's scripts/chaos/live_flags.lua, or
 * `date:YYYY-MM-DD`): a gated entry that is not live is in the data file but never shown, anywhere.
 */

if (!function_exists('chaos_news_data')) {

require_once __DIR__ . '/i18n_lib.php';

/** The data file's weeks, validated; array('recent' => int, 'latest' => string, 'weeks' => []) , empty weeks when missing or broken. */
function chaos_news_data(?string $file = null): array {
	$file = $file ?? __DIR__ . '/news/news_data.json';
	$out = array('recent' => 8, 'latest' => '', 'featured_days' => 30, 'featured_max' => 3, 'weeks' => array());
	$text = is_file($file) ? file_get_contents($file) : false;
	$json = $text === false ? null : json_decode((string)$text, true);
	if (!is_array($json) || (int)($json['format'] ?? 0) !== 1 || !is_array($json['weeks'] ?? null)) {
		return $out;
	}
	$out['recent'] = max(1, min(26, (int)($json['recent_weeks'] ?? 8)));
	$out['featured_days'] = max(1, min(120, (int)($json['featured_days'] ?? 30)));
	$out['featured_max'] = max(1, min(6, (int)($json['featured_max'] ?? 3)));
	$out['latest'] = preg_match('/^\d{4}-\d{2}-\d{2}$/', (string)($json['latest'] ?? '')) ? (string)$json['latest'] : '';
	foreach ($json['weeks'] as $week) {
		$start = (string)($week['start'] ?? '');
		if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $start) || !is_array($week['entries'] ?? null)) {
			continue;
		}
		$entries = array();
		foreach ($week['entries'] as $e) {
			if (is_array($e) && preg_match('/^\d{4}-\d{2}-\d{2}$/', (string)($e['date'] ?? '')) && is_array($e['title'] ?? null)
				&& in_array((string)($e['kind'] ?? ''), array('new', 'change', 'balance', 'fix', 'patch'), true)
				&& preg_match('/^[a-z0-9-]{2,60}$/', (string)($e['id'] ?? ''))) {
				$entries[] = $e;
			}
		}
		if ($entries) {
			$out['weeks'][] = array('start' => $start, 'entries' => $entries);
		}
	}
	return $out;
}

/** A text of an entry in the language: pt-BR, else English, else ''. */
function chaos_news_pick($pair, string $lang): string {
	if (!is_array($pair)) {
		return '';
	}
	$v = $pair[$lang] ?? ($pair['en'] ?? '');
	return is_string($v) ? $v : '';
}

/** The points of an entry in the language (the lead words of a patch note's first bullets). */
function chaos_news_points(array $entry, string $lang): array {
	$list = $entry['points'][$lang] ?? ($entry['points']['en'] ?? array());
	return is_array($list) ? array_values(array_filter($list, 'is_string')) : array();
}

function chaos_news_month(int $m, string $lang): string {
	$pt = array('janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro');
	$en = array('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December');
	return ($lang === 'pt-BR' ? $pt : $en)[max(1, min(12, $m)) - 1];
}

/** "16 a 22 de novembro de 2026" / "16 to 22 November 2026"; a week over a month end names both months. */
function chaos_news_week_label(string $start, string $lang): string {
	$a = new DateTimeImmutable($start);
	$b = $a->modify('+6 days');
	$ma = chaos_news_month((int)$a->format('n'), $lang);
	$mb = chaos_news_month((int)$b->format('n'), $lang);
	$da = (int)$a->format('j');
	$db = (int)$b->format('j');
	$ya = $a->format('Y');
	$yb = $b->format('Y');
	if ($lang === 'pt-BR') {
		if ($ma === $mb && $ya === $yb) {
			return "$da a $db de $mb de $yb";
		}
		return "$da de $ma" . ($ya !== $yb ? " de $ya" : '') . " a $db de $mb de $yb";
	}
	if ($ma === $mb && $ya === $yb) {
		return "$da to $db $mb $yb";
	}
	return "$da $ma" . ($ya !== $yb ? " $ya" : '') . " to $db $mb $yb";
}

/** One date: "20/11/2026" / "20 Nov 2026". */
function chaos_news_date(string $iso, string $lang): string {
	$d = new DateTimeImmutable($iso);
	return $lang === 'pt-BR' ? $d->format('d/m/Y') : $d->format('j M Y');
}

/** The weeks split in the recent ones and the archive: array('recent' => [...], 'archive' => [...]). */
function chaos_news_split(array $data): array {
	return array('recent' => array_slice($data['weeks'], 0, $data['recent']), 'archive' => array_slice($data['weeks'], $data['recent']));
}

/** The newest $n entries as a flat list (the front page), each with its week start. */
function chaos_news_latest(array $data, int $n = 3): array {
	$out = array();
	foreach ($data['weeks'] as $week) {
		foreach ($week['entries'] as $e) {
			$out[] = $e;
			if (count($out) >= $n) {
				return $out;
			}
		}
	}
	return $out;
}

/** A text cut at a word (or a sentence end) within $max characters, "..." when cut. */
function chaos_news_clip(string $text, int $max): string {
	if (mb_strlen($text) <= $max) {
		return $text;
	}
	$cut = mb_substr($text, 0, $max);
	$stop = mb_strrpos($cut, '. ');
	if ($stop !== false && $stop > $max / 2) {
		return mb_substr($cut, 0, $stop + 1);
	}
	$sp = mb_strrpos($cut, ' ');
	return rtrim($sp === false ? $cut : mb_substr($cut, 0, $sp), ',;:') . '...';
}

function chaos_news_h($v): string {
	return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8');
}

function chaos_news_kind_label(string $kind, string $lang): string {
	switch ($kind) {
		case 'new': return chaos_t_in($lang, 'New');
		case 'change': return chaos_t_in($lang, 'Change');
		case 'balance': return chaos_t_in($lang, 'Balance');
		case 'fix': return chaos_t_in($lang, 'Fix');
		default: return chaos_t_in($lang, 'Patch Notes');
	}
}

/** One entry as HTML. $withText false gives the compact form of the front page (title and date only). $new adds the NEW badge (O688). */
function chaos_news_entry_html(array $e, string $lang, bool $withText = true, bool $new = false): string {
	$title = chaos_news_pick($e['title'], $lang);
	$html = '<article class="chaos-newsitem chaos-newsitem--' . chaos_news_h($e['kind']) . ($new ? ' chaos-newsitem--new' : '') . '" id="news-' . chaos_news_h($e['id']) . '">'
		. '<div class="chaos-newsitem__meta">' . ($new ? chaos_news_badge_html($lang) . ' ' : '') . '<span class="chaos-newsitem__kind">' . chaos_news_h(chaos_news_kind_label($e['kind'], $lang)) . '</span> '
		. '<time datetime="' . chaos_news_h($e['date']) . '">' . chaos_news_h(chaos_news_date($e['date'], $lang)) . '</time></div>'
		. '<h3 class="chaos-newsitem__title">' . chaos_news_h($title) . '</h3>';
	if ($withText) {
		$text = chaos_news_pick($e['text'] ?? null, $lang);
		if ($text !== '') {
			$html .= '<p class="chaos-newsitem__text">' . chaos_news_h($text) . '</p>';
		}
		$points = chaos_news_points($e, $lang);
		if ($points) {
			$html .= '<ul class="chaos-newsitem__points">';
			foreach ($points as $p) {
				$html .= '<li>' . chaos_news_h($p) . '</li>';
			}
			$html .= '</ul>';
		}
	}
	$patch = (string)($e['patch'] ?? '');
	if ($patch !== '' && preg_match('/^\d{4}-\d{2}-\d{2}$/', $patch)) {
		$html .= '<p class="chaos-newsitem__more"><a href="page?plugin=chaos&amp;p=patchnotes&amp;id=' . rawurlencode($patch) . '">'
			. chaos_news_h(chaos_t_in($lang, 'Read the full notes')) . '</a></p>';
	}
	return $html . '</article>';
}

/** A week: a heading and its entries; $newIds (id => true) marks the entries that wear the NEW badge. */
function chaos_news_week_html(array $week, string $lang, array $newIds = array()): string {
	$html = '<section class="chaos-newsweek" id="week-' . chaos_news_h($week['start']) . '"><h2 class="chaos-subheading">'
		. chaos_news_h(chaos_t_in($lang, 'Week of %s', chaos_news_week_label($week['start'], $lang))) . '</h2>';
	foreach ($week['entries'] as $e) {
		$html .= chaos_news_entry_html($e, $lang, true, isset($newIds[$e['id']]));
	}
	return $html . '</section>';
}

/** The block of the front page: the newest entries, a link to the page. '' without data. Without $data: the live entries, the fresh featured ones badged. */
function chaos_news_home_html(?array $data = null, ?string $lang = null, int $n = 3, ?array $newIds = null): string {
	$lang = $lang ?? chaos_lang();
	if ($data === null) {
		$data = chaos_news_live_data();
		$newIds = $newIds ?? chaos_news_fresh_ids($data);
	}
	$newIds = $newIds ?? array();
	$latest = chaos_news_latest($data, $n);
	if (!$latest) {
		return '';
	}
	$html = '<section class="chaos-box chaos-newshome" id="novidades"><h2 class="chaos-heading">' . chaos_news_h(chaos_t_in($lang, 'What is new')) . '</h2><div class="chaos-newshome__list">';
	foreach ($latest as $e) {
		$html .= '<div class="chaos-newshome__item"><div class="chaos-newsitem__meta">' . (isset($newIds[$e['id']]) ? chaos_news_badge_html($lang) . ' ' : '') . '<span class="chaos-newsitem__kind">' . chaos_news_h(chaos_news_kind_label($e['kind'], $lang)) . '</span> '
			. '<time datetime="' . chaos_news_h($e['date']) . '">' . chaos_news_h(chaos_news_date($e['date'], $lang)) . '</time></div>'
			. '<h3 class="chaos-newsitem__title"><a href="page?plugin=chaos&amp;p=news#news-' . chaos_news_h($e['id']) . '">' . chaos_news_h(chaos_news_pick($e['title'], $lang)) . '</a></h3>'
			. '<p class="chaos-newsitem__text">' . chaos_news_h(chaos_news_clip(chaos_news_pick($e['text'] ?? null, $lang), 190)) . '</p></div>';
	}
	return $html . '</div><a class="chaos-btn chaos-btn--ghost" href="page?plugin=chaos&amp;p=news">' . chaos_news_h(chaos_t_in($lang, 'All the news')) . '</a></section>';
}

// ---------------------------------------------------------------- featured news and gates (O688)

/** The live flags: name => true (on) or 'YYYY-MM-DD' (on since that day). $config['chaos']['live'] and the server's scripts/chaos/live_flags.lua (`name = true`); the config wins. */
function chaos_news_flags(?array $override = null): array {
	if ($override !== null) {
		return $override;
	}
	$flags = array();
	$text = function_exists('chaos_read_server_file') ? chaos_read_server_file('scripts/chaos/live_flags.lua') : '';
	$text = (string)preg_replace('/--[^\n]*/', '', $text);
	if (preg_match_all('/(?<![\w.])([a-z][a-z0-9_]{1,40})\s*=\s*(true|"\d{4}-\d{2}-\d{2}")/', $text, $m, PREG_SET_ORDER)) {
		foreach ($m as $row) {
			$flags[$row[1]] = $row[2] === 'true' ? true : trim($row[2], '"');
		}
	}
	$cfg = function_exists('chaos_cfg') ? chaos_cfg('live', array()) : array();
	foreach (is_array($cfg) ? $cfg : array() as $name => $value) {
		if (is_string($name) && preg_match('/^[a-z][a-z0-9_]{1,40}$/', $name)) {
			if ($value === true || $value === 1 || $value === '1') {
				$flags[$name] = true;
			} elseif (is_string($value) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $value)) {
				$flags[$name] = $value;
			} else {
				unset($flags[$name]);
			}
		}
	}
	return $flags;
}

/** Today (site time, America/Sao_Paulo like the launch), YYYY-MM-DD; the tests set $GLOBALS['chaos_news_today']. */
function chaos_news_today(): string {
	$set = $GLOBALS['chaos_news_today'] ?? null;
	if (is_string($set) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $set)) {
		return $set;
	}
	return (new DateTimeImmutable('now', new DateTimeZone('America/Sao_Paulo')))->format('Y-m-d');
}

/** Whole days from $date to $today (negative for a date in the future). */
function chaos_news_age(string $date, string $today): int {
	return (int)(new DateTimeImmutable($date))->diff(new DateTimeImmutable($today))->format('%r%a');
}

/**
 * The date an entry counts from, or null when it is gated off. No `live_when`: its own date. `date:D`: live from D.
 * `flag:K`: live while the flag K is on; a flag set to a day counts from that day (a day in the future: not live yet).
 * Anything else reads as off (fail closed). A gated entry's date is never earlier than its gate's.
 */
function chaos_news_live_date(array $e, string $today, array $flags): ?string {
	$when = $e['live_when'] ?? null;
	if ($when === null) {
		return (string)$e['date'];
	}
	if (!is_string($when) || !preg_match('/^(?:date:(\d{4}-\d{2}-\d{2})|flag:([a-z][a-z0-9_]{1,40}))$/', $when, $m)) {
		return null;
	}
	$from = null;
	if (($m[1] ?? '') !== '') {
		$from = $m[1];
	} else {
		$v = $flags[$m[2]] ?? false;
		if ($v === true) {
			$from = (string)$e['date'];
		} elseif (is_string($v) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $v)) {
			$from = $v;
		} else {
			return null;
		}
	}
	if ($from > $today) {
		return null;
	}
	return max((string)$e['date'], $from);
}

/** The Monday (YYYY-MM-DD) of the week of a date. */
function chaos_news_monday(string $date): string {
	$d = new DateTimeImmutable($date);
	return $d->modify('-' . ((int)$d->format('N') - 1) . ' days')->format('Y-m-d');
}

/**
 * The data with the entries that are gated off removed and the others dated by their live date, the weeks built again
 * (an entry that went live later than it was written sits in the week it went live). Nothing else changes.
 */
function chaos_news_live(array $data, ?string $today = null, ?array $flags = null): array {
	$today = $today ?? chaos_news_today();
	$flags = chaos_news_flags($flags);
	$flat = array();
	foreach ($data['weeks'] as $week) {
		foreach ($week['entries'] as $e) {
			$date = chaos_news_live_date($e, $today, $flags);
			if ($date !== null) {
				$e['date'] = $date;
				$flat[] = $e;
			}
		}
	}
	usort($flat, static function (array $a, array $b): int { return strcmp($b['date'], $a['date']); }); // stable: ties keep the file order
	$weeks = array();
	foreach ($flat as $e) {
		$start = chaos_news_monday($e['date']);
		if (!$weeks || $weeks[count($weeks) - 1]['start'] !== $start) {
			$weeks[] = array('start' => $start, 'entries' => array());
		}
		$weeks[count($weeks) - 1]['entries'][] = $e;
	}
	$data['weeks'] = $weeks;
	$data['latest'] = $flat ? $flat[0]['date'] : '';
	return $data;
}

/** The data file, live entries only (what every page shows). */
function chaos_news_live_data(?string $file = null, ?string $today = null, ?array $flags = null): array {
	$file = $file ?? (isset($GLOBALS['chaos_news_file']) ? (string)$GLOBALS['chaos_news_file'] : null);
	return chaos_news_live(chaos_news_data($file), $today, $flags);
}

/** The feature block of an entry (clip, target, rank, headline, pitch) or null: a featured entry only. */
function chaos_news_feature(array $e): ?array {
	if (!isset($e['featured']) || $e['featured'] !== true) {
		return null;
	}
	$f = is_array($e['feature'] ?? null) ? $e['feature'] : array();
	$clip = (string)($f['clip'] ?? '');
	$target = (string)($f['target'] ?? '');
	$rank = (int)($f['rank'] ?? 50);
	return array(
		'clip' => preg_match('/^[a-z0-9-]{2,40}$/', $clip) ? $clip : '',
		'target' => preg_match('/^(guide|serverinfo):[a-z0-9_-]{2,40}$/', $target) ? $target : '',
		'rank' => max(1, min(99, $rank)),
		'headline' => is_array($f['headline'] ?? null) ? $f['headline'] : array(),
		'pitch' => is_array($f['pitch'] ?? null) ? $f['pitch'] : array(),
	);
}

/** The fresh featured entries of live data, newest first (then lower rank, then file order); $max null: all of them. */
function chaos_news_featured(array $live, ?string $today = null, ?int $max = null): array {
	$today = $today ?? chaos_news_today();
	$days = (int)($live['featured_days'] ?? 30);
	$out = array();
	$i = 0;
	foreach ($live['weeks'] as $week) {
		foreach ($week['entries'] as $e) {
			$f = chaos_news_feature($e);
			$age = chaos_news_age($e['date'], $today);
			if ($f !== null && $age >= 0 && $age < $days) {
				$out[] = array('e' => $e, 'f' => $f, 'i' => $i++);
			}
		}
	}
	usort($out, static function (array $a, array $b): int {
		return strcmp($b['e']['date'], $a['e']['date']) ?: ($a['f']['rank'] <=> $b['f']['rank']) ?: ($a['i'] <=> $b['i']);
	});
	if ($max !== null) {
		$out = array_slice($out, 0, $max);
	}
	return array_map(static function (array $r): array { return $r['e']; }, $out);
}

/** id => true of every fresh featured entry (they all wear the NEW badge, the banner shows only the first few). */
function chaos_news_fresh_ids(array $live, ?string $today = null): array {
	$ids = array();
	foreach (chaos_news_featured($live, $today) as $e) {
		$ids[$e['id']] = true;
	}
	return $ids;
}

/** "guide:spellbook" / "serverinfo:endgame" => true for the sections a fresh featured entry points at (the "Novo" tag of the guide and the server info page). */
function chaos_news_fresh_targets(?array $live = null, ?string $today = null): array {
	$live = $live ?? chaos_news_live_data();
	$out = array();
	foreach (chaos_news_featured($live, $today) as $e) {
		$f = chaos_news_feature($e);
		if ($f !== null && $f['target'] !== '') {
			$out[$f['target']] = true;
		}
	}
	return $out;
}

/** The small NEW / NOVO badge. $class adds a modifier ("menu", "tag"). */
function chaos_news_badge_html(?string $lang = null, string $class = ''): string {
	return '<span class="chaos-newbadge' . ($class !== '' ? ' chaos-newbadge--' . chaos_news_h($class) : '') . '">' . chaos_news_h(chaos_t_in($lang, 'NEW')) . '</span>';
}

/** The picture of a banner card: the clip's poster, else the still of the clip's slot, else ''. */
function chaos_news_feature_picture(string $clip, ?array $files = null): string {
	if ($clip === '' || !function_exists('chaos_media_url')) {
		return '';
	}
	$url = chaos_media_url('clip-' . $clip . '.jpg', $files);
	if ($url === '' && function_exists('chaos_media_action_slots')) {
		$slot = chaos_media_action_slots()[$clip] ?? null;
		if ($slot !== null && $slot[1] !== '') {
			$url = chaos_media_url($slot[1], $files);
		}
	}
	return $url;
}

/** The address of the section a feature points at. */
function chaos_news_target_url(string $target): string {
	list($kind, $id) = explode(':', $target, 2);
	return $kind === 'guide' ? 'page?plugin=chaos&amp;p=guide#card-' . chaos_news_h($id) : 'serverinfo#' . chaos_news_h($id);
}

/**
 * The "Novidade" banner of the front page (under the hero): the fresh featured entries, newest first, at most
 * `featured_max` (3), each with its headline, one line, a picture when its clip or still is there, and links to the
 * news entry and to the guide or server info section. '' when nothing is fresh and live.
 */
function chaos_news_banner_html(?array $live = null, ?string $lang = null, ?string $today = null, ?array $files = null): string {
	$lang = $lang ?? chaos_lang();
	$live = $live ?? chaos_news_live_data(null, $today);
	$list = chaos_news_featured($live, $today, (int)($live['featured_max'] ?? 3));
	if (!$list) {
		return '';
	}
	$html = '<section class="chaos-box chaos-novelty" id="novidade" aria-labelledby="chaos-novelty-title">'
		. '<h2 class="chaos-heading" id="chaos-novelty-title">' . chaos_news_badge_html($lang) . ' ' . chaos_news_h(chaos_t_in($lang, 'New in the game')) . '</h2>'
		. '<div class="chaos-novelty__grid chaos-novelty__grid--' . count($list) . '">';
	foreach ($list as $e) {
		$f = chaos_news_feature($e);
		$headline = chaos_news_pick($f['headline'], $lang);
		$headline = $headline !== '' ? $headline : chaos_news_pick($e['title'], $lang);
		$pitch = chaos_news_pick($f['pitch'], $lang);
		$pitch = $pitch !== '' ? $pitch : chaos_news_clip(chaos_news_pick($e['text'] ?? null, $lang), 140);
		$news = 'page?plugin=chaos&amp;p=news#news-' . chaos_news_h($e['id']);
		$pic = chaos_news_feature_picture($f['clip'], $files);
		$html .= '<article class="chaos-novelty__card">';
		if ($pic !== '') {
			$html .= '<a class="chaos-novelty__pic" href="' . $news . '" tabindex="-1" aria-hidden="true"><img src="' . chaos_news_h($pic) . '" width="1280" height="720" loading="lazy" decoding="async" alt=""></a>';
		}
		$html .= '<div class="chaos-novelty__body"><div class="chaos-newsitem__meta"><time datetime="' . chaos_news_h($e['date']) . '">' . chaos_news_h(chaos_news_date($e['date'], $lang)) . '</time></div>'
			. '<h3 class="chaos-novelty__title"><a href="' . $news . '">' . chaos_news_h($headline) . '</a></h3>'
			. '<p class="chaos-novelty__pitch">' . chaos_news_h($pitch) . '</p><p class="chaos-novelty__links">'
			. '<a class="chaos-btn chaos-btn--ghost" href="' . $news . '">' . chaos_news_h(chaos_t_in($lang, 'Read more')) . '</a>';
		if ($f['target'] !== '') {
			$label = strpos($f['target'], 'guide:') === 0 ? 'In the guide' : 'On the server info page';
			$html .= ' <a class="chaos-novelty__more" href="' . chaos_news_target_url($f['target']) . '">' . chaos_news_h(chaos_t_in($lang, $label)) . '</a>';
		}
		$html .= '</p></div></article>';
	}
	return $html . '</div></section>';
}

/**
 * The page's HTML with the NEW badge on the menu item that leads to the news page, while a featured entry is fresh
 * (plugin.php's output callback runs this on every page). Only a link to page?plugin=chaos&p=news with no class of ours
 * (the buttons and the entry titles are ours; the menu's links have none) and no badge yet.
 */
function chaos_news_menu_badge(string $html, ?string $lang = null, ?array $live = null, ?string $today = null): string {
	if (stripos($html, 'p=news') === false) {
		return $html;
	}
	$live = $live ?? chaos_news_live_data(null, $today);
	if (!chaos_news_featured($live, $today, 1)) {
		return $html;
	}
	$badge = ' ' . chaos_news_badge_html($lang, 'menu');
	$out = preg_replace_callback(
		'#(<a\b(?![^>]*\bclass=["\'][^"\']*\bchaos-)[^>]*\bhref=(["\'])/?page(?:\.php)?\?plugin=chaos(?:&|&amp;)p=news(?:(?:&|&amp;)l=[A-Za-z-]+)?\2[^>]*>)((?:(?!</a>).)*?)(</a>)#is',
		static function (array $m) use ($badge): string {
			return strpos($m[3], 'chaos-newbadge') !== false ? $m[0] : $m[1] . $m[3] . $badge . $m[4];
		},
		$html
	);
	return $out === null ? $html : $out;
}

} // function_exists guard
