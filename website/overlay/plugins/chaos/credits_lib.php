<?php
/**
 * The Credits page (website/README.md "Credits"): every third-party source of the game, from docs/CREDITS.md.
 * client/tools/gen_credits.py writes credits/credits_data.json from it (the same source as the game's Credits window);
 * the page shows the sections, Portuguese headings by default and English ones with &l=en. Names, authors and the
 * credit lines a licence asks for are shown as written. Loaded by pages/credits.php.
 */

if (!function_exists('chaos_credits_data')) {

/** The sections [{title, pt, note, entries: [{name, author?, licence?, credit?, use?, source?}]}]; [] without the file. */
function chaos_credits_data(?string $file = null): array {
	$file = $file ?? __DIR__ . '/credits/credits_data.json';
	$text = is_file($file) ? file_get_contents($file) : false;
	$json = $text === false ? null : json_decode((string)$text, true);
	if (!is_array($json) || !is_array($json['sections'] ?? null)) {
		return array();
	}
	$out = array();
	foreach ($json['sections'] as $s) {
		if (!is_array($s) || !is_string($s['title'] ?? null)) {
			continue;
		}
		$entries = array();
		foreach (is_array($s['entries'] ?? null) ? $s['entries'] : array() as $e) {
			if (is_array($e) && is_string($e['name'] ?? null)) {
				$entries[] = $e;
			}
		}
		$out[] = array('title' => $s['title'], 'pt' => is_string($s['pt'] ?? null) ? $s['pt'] : $s['title'],
			'note' => is_string($s['note'] ?? null) ? $s['note'] : '', 'entries' => $entries);
	}
	return $out;
}

function chaos_credits_lang(array $get): string {
	return (string)($get['l'] ?? '') === 'en' ? 'en' : 'pt-BR';
}

function chaos_credits_url(string $lang = 'pt-BR'): string {
	return 'page?plugin=chaos&p=credits' . ($lang === 'en' ? '&l=en' : '');
}

/** The page's own words. */
function chaos_credits_t(string $key, string $lang): string {
	static $t = array(
		'title'   => array('pt-BR' => 'Créditos', 'en' => 'Credits'),
		'intro'   => array('pt-BR' => 'Cinders of Chaos é feito com o trabalho destas pessoas e projetos. Obrigado!',
			'en' => 'Cinders of Chaos is made with the work of these people and projects. Thank you!'),
		'author'  => array('pt-BR' => 'Autor', 'en' => 'Author'),
		'licence' => array('pt-BR' => 'Licença', 'en' => 'Licence'),
		'use'     => array('pt-BR' => 'Usado em', 'en' => 'Used for'),
		'source'  => array('pt-BR' => 'Origem', 'en' => 'Source'),
		'other'   => array('pt-BR' => 'English', 'en' => 'Português'),
		'empty'   => array('pt-BR' => 'A lista de créditos ainda não está disponível.', 'en' => 'The credits list is not available yet.'),
	);
	return $t[$key][$lang] ?? $key;
}

/** A source link only for an https:// or http:// address, else the plain text. */
function chaos_credits_source_html(string $source): string {
	if (preg_match('~^https?://[^\s"<>]+$~', $source)) {
		return '<a href="' . chaos_h($source) . '" rel="noopener nofollow">' . chaos_h($source) . '</a>';
	}
	return chaos_h($source);
}

/** The HTML of the sections (escaped). */
function chaos_credits_render(array $sections, string $lang): string {
	if (!$sections) {
		return '<p class="chaos-empty">' . chaos_h(chaos_credits_t('empty', $lang)) . '</p>';
	}
	$html = '';
	foreach ($sections as $s) {
		$html .= '<section class="chaos-credits__section"><h2 class="chaos-heading">' . chaos_h($lang === 'en' ? $s['title'] : $s['pt']) . '</h2>';
		if ($s['note'] !== '') {
			$html .= '<p class="chaos-credits__note">' . chaos_h($s['note']) . '</p>';
		}
		if ($s['entries']) {
			$html .= '<ul class="chaos-credits__list">';
			foreach ($s['entries'] as $e) {
				$html .= '<li><strong>' . chaos_h($e['name']) . '</strong>';
				if (is_string($e['credit'] ?? null)) {
					$html .= '<div class="chaos-credits__credit">' . chaos_h($e['credit']) . '</div>';
				}
				foreach (array('author', 'licence', 'use') as $k) {
					if (is_string($e[$k] ?? null)) {
						$html .= '<div>' . chaos_h(chaos_credits_t($k, $lang)) . ': ' . chaos_h($e[$k]) . '</div>';
					}
				}
				if (is_string($e['source'] ?? null)) {
					$html .= '<div>' . chaos_h(chaos_credits_t('source', $lang)) . ': ' . chaos_credits_source_html($e['source']) . '</div>';
				}
				$html .= '</li>';
			}
			$html .= '</ul>';
		}
		$html .= '</section>';
	}
	return $html;
}

}
