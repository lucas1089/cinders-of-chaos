<?php
// php website/tests/chaos_i18n_test.php : the plugin pages in Portuguese (Brazil) or English (plugins/chaos/i18n_lib.php,
// i18n/pt-BR.php; website/README.md "Languages"): the language from &l=, the cookie and Accept-Language (English without
// any), chaos_t() with and without a translation, the language link, and the table: every chaos_t('...') key of the
// donation, bazaar, creator and leaderboards pages has a pt-BR text with the same sprintf conversions in the same
// order. php-cli only, no ZnoteX, no database.
$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) {
		$failed++;
		echo "FAIL: $what\n";
	}
}
$plugin = __DIR__ . '/../overlay/plugins/chaos';
require $plugin . '/i18n_lib.php';

// the language
check(chaos_lang(array(), array(), array()) === 'en', 'no hint: English');
check(chaos_lang(array('l' => 'pt-BR'), array(), array()) === 'pt-BR', '&l=pt-BR');
check(chaos_lang(array('l' => 'pt'), array(), array()) === 'pt-BR', '&l=pt');
check(chaos_lang(array('l' => 'en'), array('chaos_lang' => 'pt-BR'), array()) === 'en', '&l= wins over the cookie');
check(chaos_lang(array(), array('chaos_lang' => 'pt-BR'), array('HTTP_ACCEPT_LANGUAGE' => 'en-US')) === 'pt-BR', 'the cookie wins over the browser');
check(chaos_lang(array(), array(), array('HTTP_ACCEPT_LANGUAGE' => 'pt-BR,pt;q=0.9,en;q=0.8')) === 'pt-BR', 'a Brazilian browser');
check(chaos_lang(array(), array(), array('HTTP_ACCEPT_LANGUAGE' => 'en-US,en;q=0.9,pt;q=0.5')) === 'en', 'an English browser');
check(chaos_lang(array(), array(), array('HTTP_ACCEPT_LANGUAGE' => 'de-DE,de;q=0.9')) === 'en', 'another language: English');
check(chaos_lang(array('l' => 'xx'), array(), array()) === 'en', 'an unknown &l=: English');
check(chaos_lang_from_header('fr;q=0.9, pt-PT;q=0.8, en;q=0.5') === 'pt-BR', 'the highest q of the ones we have');

// the lookup
check(chaos_t_in('pt-BR', 'Cancel') === 'Cancelar', 'pt-BR text');
check(chaos_t_in('en', 'Cancel') === 'Cancel', 'English is the key');
check(chaos_t_in('pt-BR', 'Donate %s', 'R$ 5,00') === 'Doar R$ 5,00', 'formatted');
check(chaos_t_in('pt-BR', 'No such text %d', 3) === 'No such text 3', 'no translation: English, formatted');
check(chaos_t_in('pt-BR', 'The house keeps 5% here') === 'The house keeps 5% here', 'no arguments: no sprintf');
check(chaos_t('Cancel') === 'Cancel', 'the request without hints is English (the page tests)');
$link = chaos_lang_link('page.php?plugin=chaos&p=coins&l=en', 'en');
check(strpos($link, 'p=coins&amp;l=pt-BR') !== false && strpos($link, 'Português') !== false, 'the link to Portuguese');
check(strpos(chaos_lang_link('page.php?plugin=chaos&p=coins', 'pt-BR'), 'l=en') !== false, 'the link to English');

// the table
$table = require $plugin . '/i18n/pt-BR.php';
$formats = static function (string $s): string {
	preg_match_all('/%(?:%|[-+ 0#]*\d*(?:\.\d+)?([bcdeEfFgGosuxX]))/', $s, $m);
	return implode(',', array_filter($m[1], static function ($c) { return $c !== ''; }));
};
foreach ($table as $en => $pt) {
	check(is_string($pt) && $pt !== '', "a text for '$en'");
	check($formats($en) === $formats((string)$pt), "the sprintf conversions of '$en'");
}
$used = 0;
foreach (array('coins', 'bazaar', 'creator', 'leaderboards', 'fairplay', 'calendar', 'creators') as $page) {
	$tokens = token_get_all(file_get_contents($plugin . '/pages/' . $page . '.php'));
	check(strpos(file_get_contents($plugin . '/pages/' . $page . '.php'), 'chaos_lang_link(') !== false, "$page: the language link");
	for ($i = 0, $n = count($tokens); $i < $n; $i++) {
		if (!is_array($tokens[$i]) || $tokens[$i][0] !== T_STRING || $tokens[$i][1] !== 'chaos_t') {
			continue;
		}
		$j = $i + 1;
		while (is_array($tokens[$j]) && $tokens[$j][0] === T_WHITESPACE) { $j++; }
		if ($tokens[$j] !== '(') { continue; }
		$j++;
		while (is_array($tokens[$j]) && $tokens[$j][0] === T_WHITESPACE) { $j++; }
		if (is_array($tokens[$j]) && $tokens[$j][0] === T_CONSTANT_ENCAPSED_STRING) {
			$key = stripcslashes(substr($tokens[$j][1], 1, -1));
			if ($tokens[$j][1][0] === "'") {
				$key = str_replace(array("\\'", '\\\\'), array("'", '\\'), substr($tokens[$j][1], 1, -1));
			}
			$used++;
			check(isset($table[$key]), "$page: no pt-BR text for '$key'");
		}
	}
}
check($used >= 150, "the pages use their keys ($used)");

echo $failed ? "chaos_i18n_test: $failed of $checks checks failed\n" : "chaos_i18n_test: $checks checks OK\n";
exit($failed ? 1 : 0);
