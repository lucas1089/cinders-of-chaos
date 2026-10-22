<?php
// php website/tests/chaos_wiki_page_test.php : the player wiki (plugins/chaos/wiki_lib.php, pages/wiki.php) with the
// generated data (wiki/wiki_data.json, server/tools/gen_wiki_data.lua) and the guides (wiki/guides/*.md): every guide in
// both languages, their facts and links, the index, every guide, tab and entry page in both languages, breadcrumbs,
// the search (finds, escapes, accents), the 404 of an unknown topic, the "coming soon" blocks, the link rules, the
// art (an icon for every tab and entry, guide heroes, tab banners, step diagrams and callouts, every image on disk,
// with alt text and a size), and the menu, footer and home page links. Any PHP notice or warning fails the test. php-cli only, no ZnoteX, no database.
$config = array();
$GLOBALS['config'] = $config;

// failures are printed at the end: any output before a page render would stop it from setting its response code
$failed = 0;
$checks = 0;
$failures = array();
function check(bool $ok, string $what): void {
	global $failed, $checks, $failures;
	$checks++;
	if (!$ok) {
		$failed++;
		$failures[] = "FAIL: $what";
	}
}
$notices = array();
set_error_handler(static function (int $no, string $msg, string $file, int $line) use (&$notices): bool {
	$notices[] = "$msg ($file:$line)";
	return true;
});

require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/wiki_lib.php';
$repo = __DIR__ . '/../..';

function render_wiki(array $get): array {
	global $config;
	$_GET = $get;
	http_response_code(200);
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/wiki.php';
	$html = (string)ob_get_clean();
	return array($html, (int)http_response_code(), (string)($GLOBALS['page_title'] ?? ''));
}

// ---------------------------------------------------------------- the data
$data = chaos_wiki_data();
$tabIds = array_map(static function (array $t): string { return (string)$t['id']; }, $data['tabs']);
foreach (array('classes', 'spells', 'tree', 'uniques', 'sets', 'modifiers', 'orbs', 'gems', 'supports', 'rift', 'dungeons', 'bosses', 'monsters', 'store') as $want) {
	check(in_array($want, $tabIds, true), "data: tab $want");
}
check(count(chaos_wiki_index()) > 500, 'data: hundreds of entries');
check(chaos_wiki_entry('class:warrior') !== null && chaos_wiki_entry('tree:96') !== null && chaos_wiki_entry('rift:atlas') !== null, 'data: class, keystone (Hollow Vessel) and Atlas entries');
check(chaos_wiki_entry('tree:624:sentinel') !== null && chaos_wiki_entry('tree:621:ironsage') !== null, 'data: the class keystones Thorns and Overgrowth');
check(is_int($data['facts']['class.ascensionLevel'] ?? null) && ($data['facts']['class.ascensionLevel'] ?? 0) > 0, 'data: facts');
$raw = (string)file_get_contents(chaos_wiki_dir() . '/wiki_data.json');
check(strpos($raw, '"generator": "server/tools/gen_wiki_data.lua"') !== false, 'data: names its generator');
// every link of an entry goes to an entry
$dangling = 0;
foreach ($data['tabs'] as $t) {
	foreach ($t['entries'] as $e) {
		foreach ($e['sections'] as $s) {
			foreach ((array)($s['links'] ?? array()) as $l) {
				if ($l !== '' && chaos_wiki_entry((string)$l) === null) { // '' = a row without a link
					$dangling++;
				}
			}
		}
	}
}
check($dangling === 0, "data: no dangling entry links ($dangling)");

// ---------------------------------------------------------------- the art (website/tools/gen_wiki_art.py)
$assets = __DIR__ . '/../overlay/plugins/chaos/assets/';
$missing = array();
$haveArt = static function (string $path) use ($assets, &$missing): bool {
	$ok = chaos_wiki_asset($path) !== '' && is_file($assets . $path);
	if (!$ok) {
		$missing[] = $path;
	}
	return $ok;
};
$noIcon = 0;
foreach ($data['tabs'] as $t) {
	check(is_string($t['icon'] ?? null) && $haveArt($t['icon']), 'art: tab ' . $t['id'] . ' icon on disk');
	check(is_string($t['banner'] ?? null) && $haveArt($t['banner']), 'art: tab ' . $t['id'] . ' banner on disk');
	foreach ($t['entries'] as $e) {
		if (!is_string($e['icon'] ?? null) || !$haveArt($e['icon'])) {
			$noIcon++;
		}
	}
}
check($noIcon === 0, "art: every entry has an icon on disk ($noIcon without; " . implode(', ', array_slice($missing, 0, 3)) . ')');
$rowIcons = 0;
$badRow = 0;
foreach ($data['tabs'] as $t) {
	foreach ($t['entries'] as $e) {
		foreach ($e['sections'] as $sec) {
			foreach ((array)($sec['icons'] ?? array()) as $i => $icon) {
				$rowIcons += $icon !== '' ? 1 : 0;
				if ($icon !== '' && !$haveArt((string)$icon) || count((array)$sec['icons']) !== count((array)($sec['rows'] ?? array()))) {
					$badRow++;
				}
			}
		}
	}
}
check($rowIcons > 30 && $badRow === 0, "art: table row icons on disk, one per row ($rowIcons, $badRow bad)");
// the rifts have their own painted art (website/tools/wiki_rift_art.py), not the spell icon kit
$riftKit = array_filter(chaos_wiki_tab('rift')['entries'], static function (array $e): bool { return strpos((string)$e['icon'], 'wiki/i/k-') === 0; });
check($riftKit === array() && chaos_wiki_tab('rift')['icon'] === 'wiki/i/rx-portal.png', 'art: every rift entry has a rift icon');
check(preg_match('#^wiki/i/rm-(prefix|suffix|boon)-vitality\.png$#', (string)chaos_wiki_entry('rift:vitality')['entry']['icon']) === 1
	&& chaos_wiki_entry('rift:themes') !== null && chaos_wiki_entry('cur:riftkey')['entry']['icon'] === 'wiki/i/rk-5.png', 'art: rift modifiers, themes, keys');
foreach (array('key' => 'rk-', 'rift' => 'rx-portal', 'riftclear' => 'rx-clear', 'riftguardian' => 'rg-', 'chest' => 'rx-chest', 'atlas' => 'rx-atlas') as $step => $want) {
	check(strpos(chaos_wiki_ref_icon('@' . $step), 'wiki/i/' . $want) === 0, "art: rift step @$step");
}
$artIds = array_map(static function (array $g): string { return (string)$g['id']; }, (array)($data['art']['guides'] ?? array()));
check($artIds === array_keys(chaos_wiki_guides()), 'art: one guide art per guide, in the same order as chaos_wiki_guides()');
foreach ((array)($data['art']['guides'] ?? array()) as $g) {
	check($haveArt((string)$g['hero']) && $haveArt((string)$g['icon']), 'art: guide ' . $g['id'] . ' hero and icon on disk');
}
foreach ((array)($data['art']['steps'] ?? array()) as $name => $icon) {
	check($haveArt((string)$icon), "art: step icon @$name on disk");
}
foreach (array('tip', 'warn', 'note') as $k) {
	check(chaos_wiki_ref_icon('@' . $k) !== '', "art: callout icon $k");
}
check(chaos_wiki_asset('wiki/i/../x.png') === '' && chaos_wiki_asset('https://x.example/a.png') === '' && chaos_wiki_asset('wiki/i/x.svg') === ''
	&& chaos_wiki_asset('wiki/i/a"b.png') === '' && chaos_wiki_asset('wiki/i/k-fire-burst.png') === 'plugins/chaos/assets/wiki/i/k-fire-burst.png', 'art: only our image paths');
check(chaos_wiki_ref_icon('class:warrior') === 'img/class-warrior.png' && chaos_wiki_ref_icon('tab:spells') !== '' && chaos_wiki_ref_icon('@nope') === '' && chaos_wiki_ref_icon('nope') === '', 'art: step references');
$bytes = 0;
foreach (array('wiki/i', 'wiki/hero') as $d) {
	foreach ((array)glob($assets . $d . '/*') as $f) {
		$bytes += (int)filesize($f);
	}
}
check($bytes > 0 && $bytes < 5 * 1024 * 1024, 'art: under 5 MB in all (' . intdiv($bytes, 1024) . ' KB)');

// ---------------------------------------------------------------- the guides
$guides = chaos_wiki_guides();
check(count($guides) >= 15, 'guides: at least 15');
foreach (array('start', 'leveling', 'classes', 'tree', 'items', 'rifts', 'dungeons', 'bosses', 'seasons', 'economy', 'social', 'pvp', 'store', 'rules', 'faq') as $slug) {
	check(isset($guides[$slug]), "guides: $slug");
}
foreach ($guides as $slug => $titles) {
	$sections = array();
	foreach (array('pt-BR', 'en') as $lang) {
		$md = chaos_wiki_guide_text($slug, $lang);
		check(is_string($md) && strpos($md, '# ' . $titles[$lang] . "\n") === 0, "$slug.$lang: starts with its title");
		$md = (string)$md;
		check(strpos($md, '—') === false && strpos($md, '–') === false, "$slug.$lang: no em-dash");
		foreach (chaos_wiki_guide_keys($md) as $key) {
			check(array_key_exists($key, $data['facts']), "$slug.$lang: fact $key exists");
		}
		check(substr_count($md, '::: if ') === substr_count($md, '::: end'), "$slug.$lang: every ::: if has its ::: end");
		preg_match_all('/\]\(([^)\s]+)\)/', $md, $m);
		foreach ($m[1] as $target) {
			check(chaos_wiki_link($target, $lang) !== '', "$slug.$lang: link $target resolves");
		}
		preg_match_all('/^=> ([^|]+?) \|/m', $md, $m);
		foreach ($m[1] as $ref) {
			check(chaos_wiki_ref_icon($ref) !== '', "$slug.$lang: step icon $ref resolves");
		}
		check(preg_match_all('/^=> /m', $md) === preg_match_all('/^=> [^|]+ \| [^|]+ \| .+$/m', $md), "$slug.$lang: every step has an icon, a title and a text");
		$sections[$lang] = substr_count($md, "\n## ");
		$html = chaos_wiki_guide_html($md, $lang);
		check(strpos($html, '{{') === false && strpos($html, ':::') === false, "$slug.$lang: no raw markers left");
		check(chaos_wiki_guide_summary($md, $lang) !== '', "$slug.$lang: has a summary");
	}
	check($sections['pt-BR'] === $sections['en'], "$slug: the same sections in both languages");
}
check(chaos_wiki_guide_summary("# T\n\n::: if class.ascensionLevel\nOne.\n::: end\n## Next\n\nTwo.", 'en') === 'One.', 'summary: one paragraph, never the next heading');
check(mb_strlen(chaos_wiki_guide_summary("# T\n\n" . str_repeat('word ', 100), 'en'), 'UTF-8') <= 221, 'summary: cut to about 220 characters');
check(chaos_wiki_conditions("::: if class.ascensionLevel\nx\n::: end\n\n## Next", 'en') === "x\n\n## Next", 'a block keeps the blank line after it');
$keys = array_keys($guides);
check(array_search('leveling', $keys, true) === array_search('progression', $keys, true) + 1, 'leveling guide: right after Progression');
foreach (array('pt-BR' => array('## Nível 8-50', '## Nível 750-1000', '## Glossário'), 'en' => array('## Level 8-50', '## Level 750-1000', '## Glossary')) as $lang => $heads) {
	$md = (string)chaos_wiki_guide_text('leveling', $lang);
	foreach ($heads as $h) {
		check(strpos($md, "\n" . $h) !== false, "leveling.$lang: has $h");
	}
	check(strpos($md, '{{rift.level10}}') !== false && strpos($md, '{{paragon.startLevel}}') !== false, "leveling.$lang: rift tiers and Paragon come from the data");
	$html = chaos_wiki_guide_html($md, $lang);
	check(strpos($html, '<script') === false && strpos($html, 'guide%3Aprogression') !== false, "leveling.$lang: escaped, links Progression");
}
$store = (string)chaos_wiki_guide_text('store', 'pt-BR') . (string)chaos_wiki_guide_text('store', 'en');
check(strpos($store, '(legal:donations)') !== false && strpos($store, 'doação voluntária') !== false && strpos($store, 'voluntary donation') !== false, 'store guide: voluntary, links the Donation Terms');

// ---------------------------------------------------------------- the renderer and the link rules
check(chaos_wiki_link('javascript:alert(1)', 'en') === '' && chaos_wiki_link('//evil.example', 'en') === '' && chaos_wiki_link('http://x.example', 'en') === '', 'links: no javascript, protocol-relative or plain http');
check(chaos_wiki_link('wiki:nope:nope', 'en') === '' && chaos_wiki_link('wiki:class:warrior', 'en') === 'page?plugin=chaos&p=wiki&t=class%3Awarrior&l=en', 'links: wiki topics');
check(chaos_wiki_link('legal:donations', 'pt-BR') === 'page?plugin=chaos&p=legal&doc=donations' && chaos_wiki_link('legal:donations', 'en') === 'page?plugin=chaos&p=legal&doc=donations&l=en', 'links: legal texts in the same language');
$html = chaos_wiki_guide_html("# T <b>\n\nA **b** [x](javascript:alert(1)) [y](wiki:guide:faq) <script>alert(1)</script> {{nope.key}}\n\n- one\n  two\n", 'en');
check(strpos($html, '<h1 class="chaos-heading">T &lt;b&gt;</h1>') !== false, 'renderer: heading escaped');
check(strpos($html, '<script>') === false && strpos($html, '&lt;script&gt;') !== false && strpos($html, 'javascript') === false, 'renderer: no script, no javascript link');
check(strpos($html, '<a href="page?plugin=chaos&amp;p=wiki&amp;t=guide%3Afaq&amp;l=en">y</a>') !== false && strpos($html, '<strong>b</strong>') !== false, 'renderer: wiki link and bold');
check(strpos($html, '<li>one two</li>') !== false, 'renderer: list item continued');
$html = chaos_wiki_guide_html("Intro\n\n=> @key | <b>One</b> | the **first** {{rift.maxTier}}\n=> @nope | Two | x\n\n> [warn] Careful <i>\n> still\n\nAfter", 'en');
check(substr_count($html, 'class="chaos-wiki-steps__step"') === 2 && strpos($html, '<strong>&lt;b&gt;One&lt;/b&gt;</strong>') !== false
	&& strpos($html, '<strong>first</strong> ' . chaos_wiki_fact('rift.maxTier')) !== false, 'renderer: step diagram, escaped, inline marks and facts');
check(substr_count($html, 'chaos-wiki-steps__icon') === 1 && strpos($html, 'alt="&lt;b&gt;One&lt;/b&gt;"') !== false && strpos($html, 'alt="<b>') === false, 'renderer: a step without a known icon has none; the alt text escaped');
check(strpos($html, '<aside class="chaos-wiki-callout chaos-wiki-callout--warn">') !== false && strpos($html, 'Careful &lt;i&gt; still</div></aside>') !== false && strpos($html, '<p>After</p>') !== false, 'renderer: callout box, continued, escaped');
check(chaos_wiki_plain("=> @key | Title | text\n> [tip] Tip text") === 'Title: text Tip text', 'plain: steps and callouts');
check(chaos_wiki_conditions("a\n::: if nope.off\nhidden\n::: end\nb", 'en') === "a\n_Coming soon: not open in the game yet._\nb", 'a block behind a false fact reads coming soon');
check(chaos_wiki_conditions("a\n::: if class.ascensionLevel\nshown\n::: end\nb", 'pt-BR') === "a\nshown\nb", 'a block behind a true fact stays');
$entry = chaos_wiki_entry_html(array('id' => 'x', 'name' => '<i>N</i>', 'sub' => 'S&', 'color' => 'red;x:y', 'soon' => true,
	'sections' => array(array('h' => 'H', 'p' => array('<b>'), 'cols' => array('A', 'B'), 'rows' => array(array('class', '<x>')), 'links' => array('class:warrior')))), 'en');
check(strpos($entry, '&lt;i&gt;N&lt;/i&gt;') !== false && strpos($entry, 'S&amp;') !== false && strpos($entry, '<p>&lt;b&gt;</p>') !== false && strpos($entry, '<td>&lt;x&gt;</td>') !== false, 'entry: every value escaped');
check(strpos($entry, 'red;x:y') === false && strpos($entry, 'border-left-color:#d6c9ae') !== false, 'entry: a bad colour is replaced');
check(strpos($entry, '<a href="page?plugin=chaos&amp;p=wiki&amp;t=class%3Awarrior&amp;l=en">class</a>') !== false, 'entry: row link');
check(strpos($entry, 'Coming soon') !== false, 'entry: soon badge');

// ---------------------------------------------------------------- the pages
list($page, $code, $title) = render_wiki(array());
check($code === 200 && $title === 'Wiki', 'index: 200, title');
check(strpos($page, 'lang="pt-BR"') !== false && strpos($page, '>Guias</h2>') !== false && strpos($page, '>Referência</h2>') !== false, 'index: Portuguese by default');
check(strpos($page, 'href="page?plugin=chaos&amp;p=wiki&amp;l=en" lang="en">English</a>') !== false, 'index: English link');
foreach ($guides as $slug => $titles) {
	check(strpos($page, 'href="page?plugin=chaos&amp;p=wiki&amp;t=guide%3A' . $slug . '">' . chaos_h($titles['pt-BR']) . '</a>') !== false, "index: links guide $slug");
}
foreach ($tabIds as $id) {
	check(strpos($page, 'href="page?plugin=chaos&amp;p=wiki&amp;t=tab%3A' . $id . '"') !== false, "index: links tab $id");
}
check(strpos($page, 'name="q"') !== false && strpos($page, 'action="page"') !== false && strpos($page, 'name="l"') === false, 'index: search form, no language field in Portuguese');
list($page) = render_wiki(array('l' => 'en'));
check(strpos($page, 'lang="en"') !== false && strpos($page, '>Guides</h2>') !== false && strpos($page, '<input type="hidden" name="l" value="en">') !== false, 'index: English');
check(strpos($page, 't=guide%3Astart&amp;l=en"') !== false && strpos($page, 'lang="pt-BR">Português</a>') !== false, 'index (en): links keep the language, link back');

foreach ($guides as $slug => $titles) {
	foreach (array('pt-BR', 'en') as $lang) {
		list($page, $code, $title) = render_wiki($lang === 'en' ? array('t' => 'guide:' . $slug, 'l' => 'en') : array('t' => 'guide:' . $slug));
		check($code === 200 && $title === $titles[$lang] . ' - Wiki', "guide $slug.$lang: 200, title");
		check(strpos($page, '<h1 class="chaos-heading">' . chaos_h($titles[$lang]) . '</h1>') !== false, "guide $slug.$lang: heading");
		check(strpos($page, '<span aria-current="page">' . chaos_h($titles[$lang]) . '</span>') !== false
			&& strpos($page, '>' . ($lang === 'en' ? 'Guides' : 'Guias') . '</a>') !== false, "guide $slug.$lang: breadcrumbs");
		check(strpos($page, '{{') === false, "guide $slug.$lang: no raw fact");
	}
}
list($page) = render_wiki(array('t' => 'guide:rifts', 'l' => 'en'));
check(strpos($page, '<figure class="chaos-wiki-hero"><img class="chaos-wiki-hero__img" src="plugins/chaos/assets/wiki/hero/guide-rifts.webp" alt="Guide art: Rifts and the Atlas" width="960" height="300"') !== false, 'guide: hero image with alt text and size');
check(substr_count($page, 'class="chaos-wiki-steps__step"') === 6 && strpos($page, 'chaos-wiki-callout--warn') !== false, 'guide: step diagram and callout');
list($page) = render_wiki(array('t' => 'rift:tiers', 'l' => 'en'));
check(strpos($page, 'src="plugins/chaos/assets/wiki/i/rk-1.png" alt="1" width="24" height="24" loading="lazy" decoding="async">1</td>') !== false, 'entry: a key icon per rift tier row');
list($page) = render_wiki(array());
check(substr_count($page, 'class="chaos-wiki-card__img"') === count($guides) && strpos($page, 'src="plugins/chaos/assets/wiki/hero/guide-start.webp" alt="Primeiros passos" width="960" height="300" loading="lazy"') !== false, 'index: a lazy hero thumbnail per guide card');
check(strpos($page, 'src="plugins/chaos/assets/wiki/i/top-spells.png" alt="Magias" width="32" height="32" loading="lazy"') !== false, 'index: tab icons, alt text in the page language');
list($page) = render_wiki(array('t' => 'tab:spells', 'l' => 'en'));
check(strpos($page, 'wiki/hero/tab-spells.webp" alt="Section art: Spells"') !== false && substr_count($page, 'chaos-wiki-list__icon') === count(chaos_wiki_tab('spells')['entries']), 'tab: banner and an icon per entry');
list($page) = render_wiki(array('t' => 'class:warrior', 'l' => 'en'));
check(strpos($page, '<img class="chaos-wiki-entry__icon" src="plugins/chaos/assets/img/class-warrior.png" alt="Warrior" width="64" height="64" loading="lazy"') !== false, 'entry: its icon in the heading');
check(preg_match('/<img class="chaos-wiki-icon chaos-wiki-icon--row" src="plugins\/chaos\/assets\/wiki\/i\/sp-\d+\.png" alt="[^"]+" width="24" height="24" loading="lazy" decoding="async"><a href=/', $page) === 1, 'entry: spell icons in the table rows');
list($page) = render_wiki(array('q' => 'Pyre Oath', 'l' => 'en'));
check(strpos($page, 'chaos-wiki-icon--row') !== false, 'search: result icons');
list($page) = render_wiki(array('t' => 'guide:start'));
check(strpos($page, 'Próximo guia') !== false && strpos($page, 't=guide%3Aclasses"') !== false, 'guide: next guide link');

$entries = 0;
foreach ($data['tabs'] as $t) {
	list($page, $code, $title) = render_wiki(array('t' => 'tab:' . $t['id'], 'l' => 'en'));
	check($code === 200 && strpos($page, '<h1 class="chaos-heading">' . chaos_h($t['name']) . '</h1>') !== false, 'tab ' . $t['id'] . ': page');
	foreach ($t['entries'] as $e) {
		check(strpos($page, 'href="' . chaos_h(chaos_wiki_url((string)$e['id'], 'en')) . '"') !== false, 'tab ' . $t['id'] . ': links ' . $e['id']);
		foreach (array('pt-BR', 'en') as $lang) {
			list($page2, $code2, $title2) = render_wiki($lang === 'en' ? array('t' => $e['id'], 'l' => 'en') : array('t' => $e['id']));
			$ok = $code2 === 200 && $title2 === $e['name'] . ' - Wiki' && strpos($page2, chaos_h($e['name']) . '</h1>') !== false
				&& strpos($page2, 'href="' . chaos_h(chaos_wiki_url('tab:' . $t['id'], $lang)) . '"') !== false;
			check($ok, 'entry ' . $e['id'] . " ($lang): page and breadcrumb to its tab");
			preg_match_all('/<img [^>]*>/', $page2, $imgs);
			$badImg = array_filter($imgs[0], static function (string $t): bool {
				return !preg_match('/ alt="[^"]+" width="\d+" height="\d+"( loading="lazy")? decoding="async">$/', $t)
					|| (strpos($t, 'loading="lazy"') === false && strpos($t, 'chaos-wiki-hero__img') === false);
			});
			check($imgs[0] !== array() && $badImg === array(), 'entry ' . $e['id'] . " ($lang): images have alt text, a size and lazy loading");
			$entries++;
		}
	}
}
check($entries === 2 * count(chaos_wiki_index()), 'every entry rendered in both languages');
list($page) = render_wiki(array('t' => 'tab:tree'));
check(strpos($page, '<h1 class="chaos-heading">Árvore passiva</h1>') !== false && strpos($page, 'Os nomes e as tabelas') === false, 'tab: Portuguese name');

// unknown topics: 404
foreach (array('nope', 'guide:nope', 'tab:nope', 'class:', '../../config', 'guide:../start', "class:warrior\0") as $bad) {
	list($page, $code, $title) = render_wiki(array('t' => $bad));
	check($code === 404 && strpos($page, 'Página não encontrada') !== false && $title === 'Página não encontrada - Wiki', 'unknown topic ' . json_encode($bad) . ': 404');
}
list($page, $code) = render_wiki(array('t' => 'nope', 'l' => 'en'));
check($code === 404 && strpos($page, 'Page not found') !== false && strpos($page, 'Back to the wiki index') !== false, 'unknown topic (en): 404');
list($page, $code) = render_wiki(array('t' => array('x')));
check($code === 200 && strpos($page, '>Guias</h2>') !== false, 'an array topic: the index');

// ---------------------------------------------------------------- search
$r = chaos_wiki_search('Hollow Vessel', 'en');
check(($r['results'][0]['topic'] ?? '') === 'tree:96', 'search: Hollow Vessel first');
$r = chaos_wiki_search('energy shield', 'en');
check(strpos($r['results'][0]['snippet'] ?? '', '<mark>') !== false, 'search: the match marked in the snippet');
$topics = array_column(chaos_wiki_search('ascensao', 'pt-BR')['results'], 'topic');
check(in_array('guide:classes', $topics, true), 'search: without accents finds "ascensão"');
$topics = array_column(chaos_wiki_search('RIFT ATLAS', 'en')['results'], 'topic');
check(($topics[0] ?? '') === 'rift:atlas' && in_array('guide:rifts', $topics, true), 'search: case-insensitive, guides too');
check(chaos_wiki_search('zzqxv', 'en')['results'] === array(), 'search: nothing found');
$r = chaos_wiki_search('the', 'en');
check(count($r['results']) === CHAOS_WIKI_RESULTS_MAX && $r['more'] === true, 'search: capped');
list($page, $code, $title) = render_wiki(array('q' => '<script>alert("x")</script> hollow', 'l' => 'en'));
check($code === 200 && strpos($page, '<script>') === false && strpos($page, '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; hollow') !== false, 'search page: the query escaped (title and field)');
list($page) = render_wiki(array('q' => '"><img src=x onerror=alert(1)>'));
check(strpos($page, '<img') === false && strpos($page, '&quot;&gt;&lt;img') !== false, 'search page: attribute break-out escaped');
list($page) = render_wiki(array('q' => 'Pyre Oath', 'l' => 'en'));
check(strpos($page, 'Results for') !== false && strpos($page, 't=tree%3A108&amp;l=en">Pyre Oath</a>') !== false, 'search page: finds Pyre Oath');
check(strpos($page, 'href="page?plugin=chaos&amp;p=wiki&amp;q=Pyre%20Oath" lang="pt-BR"') !== false, 'search page: language link keeps the query');
list($page) = render_wiki(array('q' => 'a'));
check(strpos($page, 'Digite pelo menos 2 letras.') !== false, 'search page: too short');
list($page) = render_wiki(array('q' => str_repeat('x', 500)));
check(strpos($page, str_repeat('x', CHAOS_WIKI_QUERY_MAX + 1)) === false && strpos($page, 'Nada encontrado') !== false, 'search page: query cut, nothing found');
check(chaos_wiki_query(array('q' => array('x'))) === '' && chaos_wiki_query(array('q' => "\xff\xfe")) === '', 'search: arrays and bad UTF-8 ignored');

// ---------------------------------------------------------------- links to the wiki, sources
$src = (string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/pages/wiki.php');
check(strpos($src, "if (!isset(\$config)) { http_response_code(403);") !== false, 'no direct access');
$locale = include __DIR__ . '/../overlay/layouts/chaos/locale/en.php';
check(strpos((string)$locale['void.footer.copyright'], '<a href="page?plugin=chaos&amp;p=wiki">Wiki</a>') !== false, 'footer links the wiki');
check(strpos((string)file_get_contents(__DIR__ . '/../setup/chaos_setup.php'), "\$menu('Wiki', 'page?plugin=chaos&p=wiki'") !== false, 'menu entry');
check(strpos((string)file_get_contents(__DIR__ . '/../overlay/layouts/chaos/views/index.php'), 'href="page?plugin=chaos&amp;p=wiki">Read the guide</a>') !== false, 'home page button');
$css = (string)file_get_contents(__DIR__ . '/../overlay/layouts/chaos/assets/css/chaos.css');
check(strpos($css, '.chaos-wiki-search') !== false && strpos($css, '.chaos-wiki-scroll') !== false, 'layout styles');
check(strpos($css, '.chaos-wiki-steps') !== false && strpos($css, '.chaos-wiki-callout') !== false && strpos($css, '.chaos-wiki-hero__img') !== false, 'layout styles: wiki art');
$ci = (string)file_get_contents($repo . '/.github/workflows/ci.yml');
check(strpos($ci, 'gen_wiki_data.lua --check') !== false, 'CI checks the generated data');
check(strpos($ci, 'gen_wiki_art.py --check') !== false, 'CI checks the wiki art');
check(strpos((string)file_get_contents($repo . '/CLAUDE.md'), 'gen_wiki_data.lua') !== false, 'CLAUDE.md lists the generator');

check($notices === array(), 'no PHP notices or warnings: ' . implode(' | ', array_slice($notices, 0, 3)));
restore_error_handler();
echo $failures ? implode("\n", $failures) . "\n" : '';
echo $failed === 0 ? "chaos_wiki_page_test: OK ($checks checks)\n" : "chaos_wiki_page_test: $failed of $checks failed\n";
exit($failed === 0 ? 0 : 1);
