<?php
/**
 * Texts of the chaos plugin pages in Portuguese (Brazil) or English (website/README.md "Languages"): the donation
 * page (coins), the Character Bazaar, the creator page and the leaderboards with the records. The wiki and the legal
 * pages have their own texts (wiki_lib.php, legal_lib.php).
 *
 *  - chaos_lang(): 'pt-BR' or 'en'. &l=pt-BR / &l=en in the URL (kept in the cookie chaos_lang for a year), else the
 *    cookie, else the browser's Accept-Language (Portuguese first -> pt-BR), else English (requests without the
 *    header: scripts, the tests).
 *  - chaos_t('English text %s', $x): the text in the page's language. The key is the English text, a sprintf
 *    pattern when it has arguments; i18n/pt-BR.php maps it to Portuguese with the same % conversions in the same
 *    order (website/tests/chaos_i18n_test.php checks every chaos_t() key of the pages).
 *  - chaos_lang_link($url): the link to the same page in the other language.
 * Proper names of the game (classes, items, Chaos Coins, the in-game menus) stay in English, as in the client.
 */

const CHAOS_LANGS = array('pt-BR', 'en');

function chaos_lang_normalize(string $lang): ?string {
	$l = strtolower(str_replace('_', '-', trim($lang)));
	if ($l === 'pt' || strncmp($l, 'pt-', 3) === 0) {
		return 'pt-BR';
	}
	if ($l === 'en' || strncmp($l, 'en-', 3) === 0) {
		return 'en';
	}
	return null;
}

/** The language of an Accept-Language header: the first language we have, in the browser's order; null if none. */
function chaos_lang_from_header(string $header): ?string {
	$best = null;
	$bestQ = -1.0;
	foreach (explode(',', $header) as $i => $part) {
		$bits = explode(';', trim($part));
		$lang = chaos_lang_normalize($bits[0]);
		if ($lang === null) {
			continue;
		}
		$q = 1.0;
		foreach (array_slice($bits, 1) as $b) {
			if (preg_match('/^\s*q=([0-9.]+)/', $b, $m)) {
				$q = (float)$m[1];
			}
		}
		if ($q > $bestQ) {
			$best = $lang;
			$bestQ = $q;
		}
	}
	return $best;
}

/** The page's language (see the file comment). $get / $cookie / $server default to the request's. */
function chaos_lang(?array $get = null, ?array $cookie = null, ?array $server = null): string {
	$fromRequest = $get === null && $cookie === null && $server === null;
	static $cached = null;
	if ($fromRequest && $cached !== null) {
		return $cached;
	}
	$get = $get ?? $_GET;
	$cookie = $cookie ?? $_COOKIE;
	$server = $server ?? $_SERVER;
	$lang = isset($get['l']) ? chaos_lang_normalize((string)$get['l']) : null;
	if ($lang !== null) {
		if ($fromRequest && !headers_sent()) {
			setcookie('chaos_lang', $lang, array('expires' => time() + 365 * 86400, 'path' => '/', 'samesite' => 'Lax'));
		}
	} else {
		$lang = isset($cookie['chaos_lang']) ? chaos_lang_normalize((string)$cookie['chaos_lang']) : null;
	}
	if ($lang === null && isset($server['HTTP_ACCEPT_LANGUAGE'])) {
		$lang = chaos_lang_from_header((string)$server['HTTP_ACCEPT_LANGUAGE']);
	}
	$lang = $lang ?? 'en';
	if ($fromRequest) {
		$cached = $lang;
	}
	return $lang;
}

/** language => [english => translation] */
function chaos_i18n_tables(): array {
	static $tables = null;
	if ($tables === null) {
		$file = __DIR__ . '/i18n/pt-BR.php';
		$tables = array('pt-BR' => is_file($file) ? (array)require $file : array());
	}
	return $tables;
}

/** The text of $en in $lang (the page's language when null), formatted with the arguments. */
function chaos_t_in(?string $lang, string $en, ...$args): string {
	$lang = $lang ?? chaos_lang();
	$tables = chaos_i18n_tables();
	$text = $en;
	if (isset($tables[$lang][$en]) && $tables[$lang][$en] !== '') {
		$text = $tables[$lang][$en];
	}
	if (!$args) {
		return $text;
	}
	try {
		return vsprintf($text, $args);
	} catch (Throwable $e) {
		return vsprintf($en, $args);
	}
}

function chaos_t(string $en, ...$args): string {
	return chaos_t_in(null, $en, ...$args);
}

/** <a> to $url in the other language. */
function chaos_lang_link(string $url, ?string $lang = null): string {
	$lang = $lang ?? chaos_lang();
	$other = $lang === 'pt-BR' ? 'en' : 'pt-BR';
	$label = $other === 'pt-BR' ? 'Português' : 'English';
	$url = preg_replace('/([?&])l=[^&]*&?/', '$1', $url);
	$url = rtrim($url, '&?');
	$sep = strpos($url, '?') === false ? '?' : '&';
	return '<a class="chaos-lang-switch" hreflang="' . $other . '" href="' . htmlspecialchars($url . $sep . 'l=' . $other, ENT_QUOTES) . '">' . $label . '</a>';
}
