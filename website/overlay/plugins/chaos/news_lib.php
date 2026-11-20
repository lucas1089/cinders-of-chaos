<?php
/**
 * The news page "Novidades" / "News" (pages/news.php, website/README.md "News and changelog (O687)"): the changes of
 * the game by week, newest first, the last weeks in full and the older ones in an archive. The data is
 * news/news_data.json, written by website/tools/gen_changelog.py from the patch notes and the curated player-facing
 * entries, so the page cannot drift from them. This file only reads that data and builds HTML; every text is escaped.
 */

if (!function_exists('chaos_news_data')) {

require_once __DIR__ . '/i18n_lib.php';

/** The data file's weeks, validated; array('recent' => int, 'latest' => string, 'weeks' => []) , empty weeks when missing or broken. */
function chaos_news_data(?string $file = null): array {
	$file = $file ?? __DIR__ . '/news/news_data.json';
	$out = array('recent' => 8, 'latest' => '', 'weeks' => array());
	$text = is_file($file) ? file_get_contents($file) : false;
	$json = $text === false ? null : json_decode((string)$text, true);
	if (!is_array($json) || (int)($json['format'] ?? 0) !== 1 || !is_array($json['weeks'] ?? null)) {
		return $out;
	}
	$out['recent'] = max(1, min(26, (int)($json['recent_weeks'] ?? 8)));
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

/** One entry as HTML. $withText false gives the compact form of the front page (title and date only). */
function chaos_news_entry_html(array $e, string $lang, bool $withText = true): string {
	$title = chaos_news_pick($e['title'], $lang);
	$html = '<article class="chaos-newsitem chaos-newsitem--' . chaos_news_h($e['kind']) . '" id="news-' . chaos_news_h($e['id']) . '">'
		. '<div class="chaos-newsitem__meta"><span class="chaos-newsitem__kind">' . chaos_news_h(chaos_news_kind_label($e['kind'], $lang)) . '</span> '
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

/** A week: a heading and its entries. */
function chaos_news_week_html(array $week, string $lang): string {
	$html = '<section class="chaos-newsweek" id="week-' . chaos_news_h($week['start']) . '"><h2 class="chaos-subheading">'
		. chaos_news_h(chaos_t_in($lang, 'Week of %s', chaos_news_week_label($week['start'], $lang))) . '</h2>';
	foreach ($week['entries'] as $e) {
		$html .= chaos_news_entry_html($e, $lang);
	}
	return $html . '</section>';
}

/** The block of the front page: the newest entries, a link to the page. '' without data. */
function chaos_news_home_html(?array $data = null, ?string $lang = null, int $n = 3): string {
	$lang = $lang ?? chaos_lang();
	$data = $data ?? chaos_news_data();
	$latest = chaos_news_latest($data, $n);
	if (!$latest) {
		return '';
	}
	$html = '<section class="chaos-box chaos-newshome" id="novidades"><h2 class="chaos-heading">' . chaos_news_h(chaos_t_in($lang, 'What is new')) . '</h2><div class="chaos-newshome__list">';
	foreach ($latest as $e) {
		$html .= '<div class="chaos-newshome__item"><div class="chaos-newsitem__meta"><span class="chaos-newsitem__kind">' . chaos_news_h(chaos_news_kind_label($e['kind'], $lang)) . '</span> '
			. '<time datetime="' . chaos_news_h($e['date']) . '">' . chaos_news_h(chaos_news_date($e['date'], $lang)) . '</time></div>'
			. '<h3 class="chaos-newsitem__title"><a href="page?plugin=chaos&amp;p=news#news-' . chaos_news_h($e['id']) . '">' . chaos_news_h(chaos_news_pick($e['title'], $lang)) . '</a></h3>'
			. '<p class="chaos-newsitem__text">' . chaos_news_h(chaos_news_clip(chaos_news_pick($e['text'] ?? null, $lang), 190)) . '</p></div>';
	}
	return $html . '</div><a class="chaos-btn chaos-btn--ghost" href="page?plugin=chaos&amp;p=news">' . chaos_news_h(chaos_t_in($lang, 'All the news')) . '</a></section>';
}

} // function_exists guard
