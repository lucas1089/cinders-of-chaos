<?php
/**
 * The player wiki (website/README.md "Wiki"): page.php?plugin=chaos&p=wiki[&t=<topic>][&q=<search>][&l=en].
 * Loaded by pages/wiki.php.
 *
 *  - Reference data: wiki/wiki_data.json, generated from the game server's data files by
 *    server/tools/gen_wiki_data.lua (CI runs it with --check, so it never drifts). Tabs of entries in the Codex format:
 *    {id, name, sub, color, group, soon, icon, sections = [{h, p, cols, w, rows, links, icons}]}. The names and tables are the
 *    game's own (English); the page around them is in both languages.
 *  - Guides: wiki/guides/<slug>.<pt-BR|en>.md, short texts for players. A small Markdown subset (headings, paragraphs,
 *    lists, bold, links). {{key}} is a number of the generated facts; a block between "::: if key" and "::: end" shows
 *    only while that fact is true (a system behind an off switch reads "em breve / coming soon" instead).
 *  - Topics (&t=): guide:<slug>, tab:<tab id> or an entry id (class:warrior, spell:12, ...). Anything else is a 404.
 *  - Search (&q=): on the server, over the guides of the page's language and every entry; the query is never echoed
 *    unescaped.
 *  - Art (website/README.md "Wiki art"): the data names an icon for every tab and entry, a banner per tab and a hero
 *    image per guide (`art`); website/tools/gen_wiki_art.py draws them into assets/wiki/. Guides may add callout
 *    boxes ("> [tip|warn|note] text") and step diagrams (lines "=> icon | title | text", icon = @name of art.steps,
 *    an entry id or tab:<id>). Every image has alt text, a size and loading="lazy".
 *  - Real sprites (website/README.md "Sprite images"): a unique or set may carry `sprite` ({item: server id}) and the
 *    store's offer tables `sprites` (one per row: {item} or {outfit, addons}, false for none). Drawn from our client
 *    pair by sprite_lib.php, only when that art is ours and published; otherwise the themed icon stays.
 * Portuguese (pt-BR) by default, English with &l=en, like the legal pages.
 */

require_once __DIR__ . '/sprite_lib.php';

if (!function_exists('chaos_wiki_data')) {

define('CHAOS_WIKI_QUERY_MAX', 60);
define('CHAOS_WIKI_RESULTS_MAX', 40);

/** slug => [pt-BR title, en title], in reading order. The file of a guide is wiki/guides/<slug>.<lang>.md. */
function chaos_wiki_guides(): array {
	return array(
		'start'    => array('pt-BR' => 'Primeiros passos', 'en' => 'Getting started'),
		'classes'  => array('pt-BR' => 'Escolhendo uma classe', 'en' => 'Picking a class'),
		'tree'     => array('pt-BR' => 'A árvore passiva e exemplos de builds', 'en' => 'The passive tree and example builds'),
		'items'    => array('pt-BR' => 'Itens e criação', 'en' => 'Items and crafting'),
		'rifts'    => array('pt-BR' => 'Rifts e o Atlas', 'en' => 'Rifts and the Atlas'),
		'dungeons' => array('pt-BR' => 'Masmorras, a Torre e o Descent', 'en' => 'Dungeons, the Tower and the Descent'),
		'bosses'   => array('pt-BR' => 'Raids, chefes e eventos', 'en' => 'Raids, bosses and events'),
		'seasons'  => array('pt-BR' => 'Temporadas e rankings', 'en' => 'Seasons and leaderboards'),
		'economy'  => array('pt-BR' => 'A economia', 'en' => 'The economy'),
		'social'   => array('pt-BR' => 'Social: guildas, grupos e mentores', 'en' => 'Social: guilds, parties and mentors'),
		'pvp'      => array('pt-BR' => 'Regras de PvP', 'en' => 'PvP rules'),
		'store'    => array('pt-BR' => 'A loja e as doações', 'en' => 'The store and donations'),
		'rules'    => array('pt-BR' => 'Regras e denúncias', 'en' => 'Rules and reporting'),
		'faq'      => array('pt-BR' => 'Perguntas frequentes', 'en' => 'FAQ'),
	);
}

/** The words of the page around the data. */
function chaos_wiki_t(string $key, string $lang): string {
	static $words = array(
		'wiki'       => array('pt-BR' => 'Wiki', 'en' => 'Wiki'),
		'intro'      => array('pt-BR' => 'Tudo o que o jogo tem, num só lugar: guias curtos para começar e uma referência gerada a partir dos dados do servidor, sempre igual ao jogo.',
		                      'en' => 'Everything the game has, in one place: short guides to get going and a reference generated from the server data, always the same as the game.'),
		'guides'     => array('pt-BR' => 'Guias', 'en' => 'Guides'),
		'reference'  => array('pt-BR' => 'Referência', 'en' => 'Reference'),
		'refnote'    => array('pt-BR' => 'Os nomes e as tabelas da referência vêm do jogo e estão em inglês, como no cliente.',
		                      'en' => 'The reference is generated from the game data.'),
		'entries'    => array('pt-BR' => 'páginas', 'en' => 'pages'),
		'search'     => array('pt-BR' => 'Buscar na wiki', 'en' => 'Search the wiki'),
		'searchbtn'  => array('pt-BR' => 'Buscar', 'en' => 'Search'),
		'results'    => array('pt-BR' => 'Resultados para', 'en' => 'Results for'),
		'noresults'  => array('pt-BR' => 'Nada encontrado. Tente outra palavra.', 'en' => 'Nothing found. Try another word.'),
		'short'      => array('pt-BR' => 'Digite pelo menos 2 letras.', 'en' => 'Type at least 2 letters.'),
		'more'       => array('pt-BR' => 'Mostrando os primeiros resultados. Refine a busca para ver outros.', 'en' => 'Showing the first results. Narrow the search to see others.'),
		'guide'      => array('pt-BR' => 'Guia', 'en' => 'Guide'),
		'see'        => array('pt-BR' => 'Veja também', 'en' => 'See also'),
		'soon'       => array('pt-BR' => 'Em breve', 'en' => 'Coming soon'),
		'soontext'   => array('pt-BR' => 'Em breve: ainda não está aberto no jogo.', 'en' => 'Coming soon: not open in the game yet.'),
		'notfound'   => array('pt-BR' => 'Página não encontrada', 'en' => 'Page not found'),
		'notfoundp'  => array('pt-BR' => 'Esta página da wiki não existe. Volte ao índice ou use a busca.', 'en' => 'This wiki page does not exist. Go back to the index or use the search.'),
		'back'       => array('pt-BR' => 'Voltar ao índice da wiki', 'en' => 'Back to the wiki index'),
		'other'      => array('pt-BR' => 'English', 'en' => 'Português'),
		'unavailable'=> array('pt-BR' => 'A wiki ainda não está disponível.', 'en' => 'The wiki is not available yet.'),
		'next'       => array('pt-BR' => 'Próximo guia', 'en' => 'Next guide'),
		'crumbs'     => array('pt-BR' => 'Você está em', 'en' => 'You are here'),
		'tip'        => array('pt-BR' => 'Dica', 'en' => 'Tip'),
		'warn'       => array('pt-BR' => 'Atenção', 'en' => 'Watch out'),
		'note'       => array('pt-BR' => 'Nota', 'en' => 'Note'),
		'steps'      => array('pt-BR' => 'Passo a passo', 'en' => 'Step by step'),
		'step'       => array('pt-BR' => 'Passo', 'en' => 'Step'),
		'heroalt'    => array('pt-BR' => 'Arte do guia', 'en' => 'Guide art'),
		'banneralt'  => array('pt-BR' => 'Arte da seção', 'en' => 'Section art'),
		'icon'       => array('pt-BR' => 'Ícone', 'en' => 'Icon'),
	);
	return $words[$key][$lang] ?? $key;
}

/** Portuguese names of the reference tabs (the English ones come with the data). */
function chaos_wiki_tab_name(array $tab, string $lang): string {
	static $pt = array('classes' => 'Classes', 'spells' => 'Magias', 'tree' => 'Árvore passiva', 'basics' => 'Noções básicas',
		'modifiers' => 'Modificadores', 'powers' => 'Poderes lendários', 'uniques' => 'Itens únicos', 'sets' => 'Conjuntos',
		'orbs' => 'Orbes', 'gems' => 'Gemas', 'supports' => 'Suportes', 'rift' => 'Rifts', 'dungeons' => 'Masmorras',
		'bosses' => 'Chefes', 'events' => 'Eventos', 'monsters' => 'Monstros', 'materials' => 'Materiais', 'store' => 'Loja');
	$id = (string)($tab['id'] ?? '');
	return $lang === 'pt-BR' && isset($pt[$id]) ? $pt[$id] : (string)($tab['name'] ?? $id);
}

function chaos_wiki_lang(array $get): string {
	return (string)($get['l'] ?? '') === 'en' ? 'en' : 'pt-BR';
}

/** The folder of the wiki files (plugins/chaos/wiki/ on the site and in the repository). */
function chaos_wiki_dir(): string {
	return __DIR__ . '/wiki';
}

/** A wiki page. Portuguese is the default; English adds &l=en. */
function chaos_wiki_url(string $topic = '', string $lang = 'pt-BR', string $query = ''): string {
	$url = 'page.php?plugin=chaos&p=wiki';
	if ($topic !== '') {
		$url .= '&t=' . rawurlencode($topic);
	}
	if ($query !== '') {
		$url .= '&q=' . rawurlencode($query);
	}
	return $url . ($lang === 'en' ? '&l=en' : '');
}

/** The generated data: {facts, tabs}. Empty tabs when the file is missing or broken. */
function chaos_wiki_data(): array {
	static $data = null;
	if ($data === null) {
		$data = array('facts' => array(), 'tabs' => array(), 'art' => array());
		$file = chaos_wiki_dir() . '/wiki_data.json';
		$text = is_file($file) ? file_get_contents($file) : false;
		$json = $text === false ? null : json_decode($text, true);
		if (is_array($json) && isset($json['tabs']) && is_array($json['tabs'])) {
			$data = array('facts' => is_array($json['facts'] ?? null) ? $json['facts'] : array(), 'tabs' => $json['tabs'],
				'art' => is_array($json['art'] ?? null) ? $json['art'] : array());
		}
	}
	return $data;
}

/** entry id => [tab index, entry index]. */
function chaos_wiki_index(): array {
	static $index = null;
	if ($index === null) {
		$index = array();
		foreach (chaos_wiki_data()['tabs'] as $ti => $tab) {
			foreach ((array)($tab['entries'] ?? array()) as $ei => $e) {
				if (isset($e['id'])) {
					$index[(string)$e['id']] = array($ti, $ei);
				}
			}
		}
	}
	return $index;
}

function chaos_wiki_entry(string $id): ?array {
	$at = chaos_wiki_index()[$id] ?? null;
	if ($at === null) {
		return null;
	}
	$tabs = chaos_wiki_data()['tabs'];
	return array('tab' => $tabs[$at[0]], 'entry' => $tabs[$at[0]]['entries'][$at[1]]);
}

function chaos_wiki_tab(string $id): ?array {
	foreach (chaos_wiki_data()['tabs'] as $tab) {
		if ((string)($tab['id'] ?? '') === $id) {
			return $tab;
		}
	}
	return null;
}

/** The Markdown of a guide, or null when the slug, the language or the file is unknown. */
function chaos_wiki_guide_text(string $slug, string $lang): ?string {
	if (!isset(chaos_wiki_guides()[$slug]) || !in_array($lang, array('pt-BR', 'en'), true)) {
		return null;
	}
	$file = chaos_wiki_dir() . '/guides/' . $slug . '.' . $lang . '.md';
	$text = is_file($file) ? file_get_contents($file) : false;
	return $text === false ? null : str_replace("\r\n", "\n", $text);
}

/** What a topic is: ['kind' => index|guide|tab|entry, ...], or null for an unknown one (a 404). */
function chaos_wiki_resolve(string $topic): ?array {
	if ($topic === '') {
		return array('kind' => 'index');
	}
	if (strncmp($topic, 'guide:', 6) === 0) {
		$slug = substr($topic, 6);
		return isset(chaos_wiki_guides()[$slug]) ? array('kind' => 'guide', 'slug' => $slug) : null;
	}
	if (strncmp($topic, 'tab:', 4) === 0) {
		$tab = chaos_wiki_tab(substr($topic, 4));
		return $tab !== null ? array('kind' => 'tab', 'tab' => $tab) : null;
	}
	$e = chaos_wiki_entry($topic);
	return $e !== null ? array('kind' => 'entry') + $e : null;
}

// ---------------------------------------------------------------------------------------------------------------- art

/** The URL of a wiki image (a path under the plugin's assets/), or '' for a path that is not one of ours. */
function chaos_wiki_asset(string $path): string {
	if (!preg_match('#^(img|wiki/i|wiki/hero)/[a-z0-9][a-z0-9_.-]*\.(png|webp)$#i', $path) || strpos($path, '..') !== false) {
		return '';
	}
	return function_exists('znote_plugin_asset') ? (string)znote_plugin_asset('chaos', $path) : 'plugins/chaos/assets/' . $path;
}

/** An <img> of a wiki image: escaped, alt text, width and height, lazy. '' when the path is not one of ours. */
function chaos_wiki_img(string $path, string $alt, int $w, int $h, string $class, bool $lazy = true): string {
	$url = chaos_wiki_asset($path);
	if ($url === '') {
		return '';
	}
	$e = static function (string $v): string { return htmlspecialchars($v, ENT_QUOTES, 'UTF-8'); };
	return '<img class="' . $e($class) . '" src="' . $e($url) . '" alt="' . $e($alt) . '" width="' . $w . '" height="' . $h . '"'
		. ($lazy ? ' loading="lazy"' : '') . ' decoding="async">';
}

/** The small icon of an entry or a tab (its name as alt text), or ''. An entry whose `sprite` is published shows
 *  the real sprite instead (pixel art scaled by whole steps where it fits). */
function chaos_wiki_icon(array $e, int $size, string $class = 'chaos-wiki-icon'): string {
	$sprite = is_array($e['sprite'] ?? null) ? chaos_sprite_ref($e['sprite']) : null;
	if ($sprite !== null) {
		return chaos_sprite_img($sprite[0], (string)($e['name'] ?? ''), $size, $size, $class . ' chaos-sprite');
	}
	$icon = $e['icon'] ?? '';
	return is_string($icon) && $icon !== '' ? chaos_wiki_img($icon, (string)($e['name'] ?? ''), $size, $size, $class) : '';
}

/** The art of a guide: {id, icon, hero, tone, icons}, or null. */
function chaos_wiki_guide_art(string $slug): ?array {
	foreach ((array)(chaos_wiki_data()['art']['guides'] ?? array()) as $g) {
		if (is_array($g) && (string)($g['id'] ?? '') === $slug) {
			return $g;
		}
	}
	return null;
}

/** The icon path of a step or callout reference: @name (art.steps), tab:<id> or an entry id. '' = unknown. */
function chaos_wiki_ref_icon(string $ref): string {
	if (strncmp($ref, '@', 1) === 0) {
		$icon = chaos_wiki_data()['art']['steps'][substr($ref, 1)] ?? '';
		return is_string($icon) ? $icon : '';
	}
	if (strncmp($ref, 'tab:', 4) === 0) {
		$tab = chaos_wiki_tab(substr($ref, 4));
		return $tab !== null ? (string)($tab['icon'] ?? '') : '';
	}
	$e = chaos_wiki_entry($ref);
	return $e !== null ? (string)($e['entry']['icon'] ?? '') : '';
}

/** A hero or banner figure (full width, lazy unless it is the first thing on the page). */
function chaos_wiki_hero(string $path, string $alt, int $w, int $h, bool $lazy): string {
	$img = chaos_wiki_img($path, $alt, $w, $h, 'chaos-wiki-hero__img', $lazy);
	return $img === '' ? '' : '<figure class="chaos-wiki-hero">' . $img . '</figure>';
}

// ---------------------------------------------------------------------------------------------------------------- guides

/** A fact as text ("" for an unknown key). */
function chaos_wiki_fact(string $key): string {
	$facts = chaos_wiki_data()['facts'];
	if (!array_key_exists($key, $facts)) {
		return '';
	}
	$v = $facts[$key];
	if (is_bool($v)) {
		return $v ? 'true' : 'false';
	}
	return is_scalar($v) ? (string)$v : '';
}

/** The keys a guide uses ({{key}} and "::: if key"), each once. */
function chaos_wiki_guide_keys(string $md): array {
	preg_match_all('/\{\{([a-zA-Z0-9_.]+)\}\}|^::: if ([a-zA-Z0-9_.]+)\s*$/m', $md, $m);
	return array_values(array_unique(array_filter(array_merge($m[1], $m[2]), 'strlen')));
}

/** The "::: if key" blocks resolved: kept while the fact is true, else one "coming soon" line. */
function chaos_wiki_conditions(string $md, string $lang): string {
	return (string)preg_replace_callback('/^::: if ([a-zA-Z0-9_.]+)[ \t]*\n(.*?)^::: end[ \t]*$/ms', static function (array $m) use ($lang): string {
		return chaos_wiki_data()['facts'][$m[1]] ?? false ? rtrim($m[2], "\n") : '_' . chaos_wiki_t('soontext', $lang) . '_';
	}, $md);
}

/** A link target of a guide: wiki:<topic>, legal:<doc>, page:<plugin page>, a site path or https. '' = not allowed. */
function chaos_wiki_link(string $target, string $lang): string {
	if (strncmp($target, 'wiki:', 5) === 0) {
		$topic = substr($target, 5);
		return $topic === '' || chaos_wiki_resolve($topic) !== null ? chaos_wiki_url($topic, $lang) : '';
	}
	if (preg_match('/^legal:(terms|privacy|donations)$/', $target, $m)) {
		return 'page.php?plugin=chaos&p=legal&doc=' . $m[1] . ($lang === 'en' ? '&l=en' : '');
	}
	if (preg_match('/^page:([a-z]+)$/', $target, $m)) {
		return 'page.php?plugin=chaos&p=' . $m[1];
	}
	if (preg_match('#^(/(?!/)|https://)[^\s"\'<>]*$#', $target)) {
		return $target;
	}
	return '';
}

/** One line of a guide: escaped, then facts, links, bold and italics. */
function chaos_wiki_inline(string $line, string $lang): string {
	$s = htmlspecialchars($line, ENT_QUOTES, 'UTF-8');
	$s = (string)preg_replace_callback('/\{\{([a-zA-Z0-9_.]+)\}\}/', static function (array $m): string {
		return htmlspecialchars(chaos_wiki_fact($m[1]), ENT_QUOTES, 'UTF-8');
	}, $s);
	$s = (string)preg_replace_callback('/\[([^\]]+)\]\(([^)\s]+)\)/', static function (array $m) use ($lang): string {
		$url = chaos_wiki_link(html_entity_decode($m[2], ENT_QUOTES, 'UTF-8'), $lang);
		return $url === '' ? $m[1] : '<a href="' . htmlspecialchars($url, ENT_QUOTES, 'UTF-8') . '">' . $m[1] . '</a>';
	}, $s);
	$s = (string)preg_replace('/\*\*(.+?)\*\*/', '<strong>$1</strong>', $s);
	return (string)preg_replace('/(?<![\w])_(.+?)_(?![\w])/u', '<em>$1</em>', $s);
}

/** A step diagram: "=> icon | title | text" lines as a numbered flow with icons. */
function chaos_wiki_steps_html(array $steps, string $lang): string {
	$items = array();
	foreach ($steps as $i => $st) {
		$parts = array_map('trim', explode('|', $st, 3));
		$icon = chaos_wiki_ref_icon($parts[0]);
		$title = $parts[1] ?? '';
		$img = $icon !== '' ? chaos_wiki_img($icon, chaos_wiki_plain($title), 40, 40, 'chaos-wiki-steps__icon') : '';
		$items[] = '<li class="chaos-wiki-steps__step"><span class="chaos-wiki-steps__badge">' . $img
			. '<span class="chaos-wiki-steps__n" aria-hidden="true">' . ($i + 1) . '</span></span>'
			. '<span class="chaos-wiki-steps__body"><strong>' . chaos_wiki_inline($title, $lang) . '</strong>'
			. (($parts[2] ?? '') !== '' ? '<span>' . chaos_wiki_inline($parts[2], $lang) . '</span>' : '') . '</span></li>';
	}
	return '<ol class="chaos-wiki-steps" aria-label="' . htmlspecialchars(chaos_wiki_t('steps', $lang), ENT_QUOTES, 'UTF-8') . '">'
		. implode('', $items) . '</ol>';
}

/** A callout box: "> [tip|warn|note] text" (following "> " lines continue it). */
function chaos_wiki_callout_html(string $kind, array $lines, string $lang): string {
	$icon = chaos_wiki_ref_icon('@' . $kind);
	$label = chaos_wiki_t($kind, $lang);
	$img = $icon !== '' ? chaos_wiki_img($icon, $label, 32, 32, 'chaos-wiki-callout__icon') : '';
	return '<aside class="chaos-wiki-callout chaos-wiki-callout--' . $kind . '">' . $img . '<div><strong class="chaos-wiki-callout__label">'
		. htmlspecialchars($label, ENT_QUOTES, 'UTF-8') . '</strong> ' . chaos_wiki_inline(implode(' ', $lines), $lang) . '</div></aside>';
}

/** A guide as HTML: the "::: if" blocks, then headings (# is the page title), paragraphs, lists, step diagrams and
 * callout boxes. */
function chaos_wiki_guide_html(string $md, string $lang): string {
	$md = chaos_wiki_conditions($md, $lang);
	$out = array();
	$para = array();
	$list = array();
	$steps = array();
	$callout = null;
	$flush = static function () use (&$out, &$para, &$list, &$steps, &$callout, $lang): void {
		if ($para) {
			$out[] = '<p>' . chaos_wiki_inline(implode(' ', $para), $lang) . '</p>';
			$para = array();
		}
		if ($list) {
			$out[] = '<ul>' . implode('', array_map(static function (string $i) use ($lang): string {
				return '<li>' . chaos_wiki_inline($i, $lang) . '</li>';
			}, $list)) . '</ul>';
			$list = array();
		}
		if ($steps) {
			$out[] = chaos_wiki_steps_html($steps, $lang);
			$steps = array();
		}
		if ($callout !== null) {
			$out[] = chaos_wiki_callout_html($callout[0], $callout[1], $lang);
			$callout = null;
		}
	};
	foreach (explode("\n", $md) as $line) {
		$t = rtrim($line);
		if ($t === '') {
			$flush();
		} elseif (preg_match('/^=> (.+)$/', $t, $m)) {
			if ($para || $list || $callout !== null) {
				$flush();
			}
			$steps[] = $m[1];
		} elseif (preg_match('/^> \[(tip|warn|note)\] (.+)$/', $t, $m)) {
			$flush();
			$callout = array($m[1], array($m[2]));
		} elseif ($callout !== null && preg_match('/^> (.+)$/', $t, $m)) {
			$callout[1][] = $m[1];
		} elseif (preg_match('/^(#{1,3}) (.+)$/', $t, $m)) {
			$flush();
			$level = strlen($m[1]);
			$cls = $level === 1 ? ' class="chaos-heading"' : '';
			$out[] = '<h' . $level . $cls . '>' . chaos_wiki_inline($m[2], $lang) . '</h' . $level . '>';
		} elseif (preg_match('/^[-*] (.+)$/', $t, $m)) {
			if ($para) {
				$flush();
			}
			$list[] = $m[1];
		} elseif ($list && preg_match('/^\s+(.+)$/', $t, $m)) {
			$list[count($list) - 1] .= ' ' . $m[1];
		} else {
			if ($list) {
				$flush();
			}
			$para[] = trim($t);
		}
	}
	$flush();
	return implode("\n", $out);
}

/** The first paragraph of a guide as plain text, at most about 220 characters (the index cards). */
function chaos_wiki_guide_summary(string $md, string $lang): string {
	$md = chaos_wiki_conditions($md, $lang);
	foreach (preg_split('/\n\s*\n|\n(?=#)/', $md) as $block) {
		$block = trim($block);
		if ($block !== '' && $block[0] !== '#' && $block[0] !== '-' && $block[0] !== '=' && $block[0] !== '>') {
			$text = chaos_wiki_plain($block);
			if (mb_strlen($text, 'UTF-8') > 220) {
				$text = rtrim((string)preg_replace('/\s+\S*$/u', '', mb_substr($text, 0, 220, 'UTF-8')), ' ,.:;') . '…';
			}
			return $text;
		}
	}
	return '';
}

/** Markdown to plain text (facts filled in, links reduced to their text). */
function chaos_wiki_plain(string $md): string {
	$s = (string)preg_replace_callback('/\{\{([a-zA-Z0-9_.]+)\}\}/', static function (array $m): string {
		return chaos_wiki_fact($m[1]);
	}, $md);
	$s = (string)preg_replace('/\[([^\]]+)\]\([^)\s]+\)/', '$1', $s);
	$s = str_replace(array('**', '::: end'), '', $s);
	$s = (string)preg_replace('/^(#{1,3} |[-*] |::: if \S+|=> \S+ \| |> \[(tip|warn|note)\] |> )/m', '', $s);
	$s = str_replace(' | ', ': ', $s);
	$s = (string)preg_replace('/(?<![\w])_(.+?)_(?![\w])/u', '$1', $s);
	return trim((string)preg_replace('/\s+/', ' ', $s));
}

// ---------------------------------------------------------------------------------------------------------------- entries

function chaos_wiki_color(array $e): string {
	$c = (string)($e['color'] ?? '');
	return preg_match('/^#[0-9a-fA-F]{6}$/', $c) ? $c : '#d6c9ae';
}

/** An entry of the reference as HTML (every value escaped; links only to other entries). */
function chaos_wiki_entry_html(array $e, string $lang): string {
	$h = static function ($v): string { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); };
	$link = static function (string $id, string $text) use ($lang, $h): string {
		$target = chaos_wiki_entry($id);
		if ($target === null) {
			return $h($text);
		}
		$icon = chaos_wiki_icon(array('icon' => $target['entry']['icon'] ?? '', 'sprite' => $target['entry']['sprite'] ?? null, 'name' => $text), 24, 'chaos-wiki-icon chaos-wiki-icon--row');
		return $icon . '<a href="' . $h(chaos_wiki_url($id, $lang)) . '">' . $h($text) . '</a>';
	};
	$out = array();
	$icon = chaos_wiki_icon($e, 64, 'chaos-wiki-entry__icon');
	$out[] = '<div class="chaos-wiki-entry__head">' . $icon . '<h1 class="chaos-heading chaos-wiki-entry__title" style="border-left-color:' . chaos_wiki_color($e) . '">' . $h($e['name'] ?? '') . '</h1></div>';
	if (!empty($e['soon'])) {
		$out[] = '<p class="chaos-wiki-soon">' . $h(chaos_wiki_t('soontext', $lang)) . '</p>';
	}
	if ((string)($e['sub'] ?? '') !== '') {
		$out[] = '<p class="chaos-lead">' . $h($e['sub']) . '</p>';
	}
	foreach ((array)($e['sections'] ?? array()) as $s) {
		if (!is_array($s)) {
			continue;
		}
		if ((string)($s['h'] ?? '') !== '') {
			$out[] = '<h2>' . $h($s['h']) . '</h2>';
		}
		foreach ((array)($s['p'] ?? array()) as $p) {
			$out[] = '<p>' . $h($p) . '</p>';
		}
		$links = array_values((array)($s['links'] ?? array()));
		$icons = array_values((array)($s['icons'] ?? array()));
		$sprites = array_values((array)($s['sprites'] ?? array()));
		$rows = (array)($s['rows'] ?? array());
		if ($rows) {
			$cols = (array)($s['cols'] ?? array());
			$table = '<div class="chaos-wiki-scroll"><table class="chaos-table chaos-wiki-table">';
			if (implode('', array_map('strval', $cols)) !== '') {
				$table .= '<thead><tr>' . implode('', array_map(static function ($c) use ($h): string { return '<th>' . $h($c) . '</th>'; }, $cols)) . '</tr></thead>';
			}
			$table .= '<tbody>';
			foreach (array_values($rows) as $i => $row) {
				$cells = array();
				foreach (array_values((array)$row) as $ci => $cell) {
					$text = is_scalar($cell) ? (string)$cell : '';
					if ($ci === 0 && isset($links[$i]) && is_string($links[$i]) && $links[$i] !== '') {
						$cells[] = '<td>' . $link($links[$i], $text) . '</td>';
					} else {
						// a section's own icon of the row (a rift tier's key, an omen's emblem, ...)
						$icon = $ci === 0 && (is_string($icons[$i] ?? null) || is_array($sprites[$i] ?? null))
							? chaos_wiki_icon(array('icon' => $icons[$i] ?? '', 'sprite' => $sprites[$i] ?? null, 'name' => $text), 24, 'chaos-wiki-icon chaos-wiki-icon--row') : '';
						$cells[] = '<td>' . $icon . $h($text) . '</td>';
					}
				}
				$table .= '<tr>' . implode('', $cells) . '</tr>';
			}
			$out[] = $table . '</tbody></table></div>';
		} elseif ($links) {
			$items = array();
			foreach ($links as $id) {
				$target = is_string($id) ? chaos_wiki_entry($id) : null;
				if ($target !== null) {
					$items[] = '<li>' . $link($id, (string)($target['entry']['name'] ?? $id)) . '</li>';
				}
			}
			if ($items) {
				$out[] = '<ul class="chaos-wiki-see"><li class="chaos-wiki-see__label">' . $h(chaos_wiki_t('see', $lang)) . ':</li>' . implode('', $items) . '</ul>';
			}
		}
	}
	return implode("\n", $out);
}

// ---------------------------------------------------------------------------------------------------------------- search

/** Lower case without accents, one character for one (so positions match the original text). */
function chaos_wiki_norm(string $s): string {
	static $map = array('á' => 'a', 'à' => 'a', 'â' => 'a', 'ã' => 'a', 'ä' => 'a', 'é' => 'e', 'è' => 'e', 'ê' => 'e',
		'ë' => 'e', 'í' => 'i', 'ì' => 'i', 'î' => 'i', 'ï' => 'i', 'ó' => 'o', 'ò' => 'o', 'ô' => 'o', 'õ' => 'o', 'ö' => 'o',
		'ú' => 'u', 'ù' => 'u', 'û' => 'u', 'ü' => 'u', 'ç' => 'c', 'ñ' => 'n');
	return strtr(mb_strtolower($s, 'UTF-8'), $map);
}

/** The query as typed, trimmed, cut to CHAOS_WIKI_QUERY_MAX characters, control characters removed. */
function chaos_wiki_query(array $get): string {
	$q = $get['q'] ?? '';
	if (!is_string($q)) {
		return '';
	}
	$q = (string)preg_replace('/[\x00-\x1f\x7f]+/u', ' ', $q);
	if (!mb_check_encoding($q, 'UTF-8')) {
		return '';
	}
	return trim(mb_substr(trim($q), 0, CHAOS_WIKI_QUERY_MAX, 'UTF-8'));
}

/** Plain text of an entry, for the search. */
function chaos_wiki_entry_text(array $e): string {
	$parts = array((string)($e['sub'] ?? ''));
	foreach ((array)($e['sections'] ?? array()) as $s) {
		$parts[] = (string)($s['h'] ?? '');
		foreach ((array)($s['p'] ?? array()) as $p) {
			$parts[] = (string)$p;
		}
		foreach ((array)($s['rows'] ?? array()) as $row) {
			$parts[] = implode(' ', array_map(static function ($c): string { return is_scalar($c) ? (string)$c : ''; }, (array)$row));
		}
	}
	return implode(' . ', array_filter($parts, 'strlen'));
}

/** Search results: [{topic, title, kind, snippet (HTML, escaped, the match in <mark>)}], best first, and whether more were cut. */
function chaos_wiki_search(string $q, string $lang): array {
	$nq = chaos_wiki_norm($q);
	$words = array_values(array_filter(preg_split('/\s+/u', $nq), static function (string $w): bool { return mb_strlen($w, 'UTF-8') >= 2; }));
	if (!$words) {
		return array('results' => array(), 'more' => false);
	}
	$found = array();
	$score = static function (string $title, string $text) use ($words, $nq): int {
		$nt = chaos_wiki_norm($title);
		$nx = chaos_wiki_norm($text);
		$s = 0;
		foreach ($words as $w) {
			if (mb_strpos($nt, $w, 0, 'UTF-8') !== false) {
				$s += 10;
			} elseif (mb_strpos($nx, $w, 0, 'UTF-8') !== false) {
				$s += 2;
			} else {
				return 0;
			}
		}
		if ($nt === $nq) {
			$s += 50;
		} elseif (mb_strpos($nt, $nq, 0, 'UTF-8') === 0) {
			$s += 20;
		}
		return $s;
	};
	$order = 0;
	foreach (chaos_wiki_guides() as $slug => $titles) {
		$md = chaos_wiki_guide_text($slug, $lang);
		if ($md === null) {
			continue;
		}
		$text = chaos_wiki_plain(chaos_wiki_conditions($md, $lang));
		$s = $score($titles[$lang], $text);
		if ($s > 0) {
			$found[] = array('s' => $s + 5, 'o' => $order++, 'topic' => 'guide:' . $slug, 'title' => $titles[$lang],
				'kind' => chaos_wiki_t('guide', $lang), 'text' => $text);
		}
	}
	foreach (chaos_wiki_data()['tabs'] as $tab) {
		foreach ((array)($tab['entries'] ?? array()) as $e) {
			$text = chaos_wiki_entry_text($e);
			$s = $score((string)($e['name'] ?? ''), $text);
			if ($s > 0) {
				$found[] = array('s' => $s, 'o' => $order++, 'topic' => (string)$e['id'], 'title' => (string)($e['name'] ?? ''),
					'kind' => chaos_wiki_tab_name($tab, $lang), 'text' => $text);
			}
		}
	}
	usort($found, static function (array $a, array $b): int {
		return $b['s'] <=> $a['s'] ?: $a['o'] <=> $b['o'];
	});
	$more = count($found) > CHAOS_WIKI_RESULTS_MAX;
	$out = array();
	foreach (array_slice($found, 0, CHAOS_WIKI_RESULTS_MAX) as $f) {
		$out[] = array('topic' => $f['topic'], 'title' => $f['title'], 'kind' => $f['kind'], 'snippet' => chaos_wiki_snippet($f['text'], $words));
	}
	return array('results' => $out, 'more' => $more);
}

/** About 160 characters around the first word found, escaped, that word in <mark>. */
function chaos_wiki_snippet(string $text, array $words): string {
	$h = static function (string $v): string { return htmlspecialchars($v, ENT_QUOTES, 'UTF-8'); };
	$norm = chaos_wiki_norm($text);
	$pos = false;
	$len = 0;
	foreach ($words as $w) {
		$p = mb_strpos($norm, $w, 0, 'UTF-8');
		if ($p !== false) {
			$pos = $p;
			$len = mb_strlen($w, 'UTF-8');
			break;
		}
	}
	if ($pos === false) {
		$cut = mb_substr($text, 0, 160, 'UTF-8');
		return $h($cut) . (mb_strlen($text, 'UTF-8') > 160 ? '…' : '');
	}
	$start = max(0, $pos - 60);
	$before = mb_substr($text, $start, $pos - $start, 'UTF-8');
	$match = mb_substr($text, $pos, $len, 'UTF-8');
	$after = mb_substr($text, $pos + $len, 100, 'UTF-8');
	return ($start > 0 ? '…' : '') . $h($before) . '<mark>' . $h($match) . '</mark>' . $h($after)
		. ($pos + $len + 100 < mb_strlen($text, 'UTF-8') ? '…' : '');
}

}
