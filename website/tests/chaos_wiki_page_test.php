<?php
// php website/tests/chaos_wiki_page_test.php : the player wiki (plugins/chaos/wiki_lib.php, pages/wiki.php) with the
// generated data (wiki/wiki_data.json, server/tools/gen_wiki_data.lua) and the guides (wiki/guides/*.md): every guide in
// both languages, their facts and links, the index, every guide, tab and entry page in both languages, breadcrumbs,
// the search (finds, escapes, accents), the 404 of an unknown topic, the "coming soon" blocks, the link rules, and the
// menu, footer and home page links. Any PHP notice or warning fails the test. php-cli only, no ZnoteX, no database.
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

// ---------------------------------------------------------------- the guides
$guides = chaos_wiki_guides();
check(count($guides) >= 14, 'guides: at least 14');
foreach (array('start', 'classes', 'tree', 'items', 'rifts', 'dungeons', 'bosses', 'seasons', 'economy', 'social', 'pvp', 'store', 'rules', 'faq') as $slug) {
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
$store = (string)chaos_wiki_guide_text('store', 'pt-BR') . (string)chaos_wiki_guide_text('store', 'en');
check(strpos($store, '(legal:donations)') !== false && strpos($store, 'doação voluntária') !== false && strpos($store, 'voluntary donation') !== false, 'store guide: voluntary, links the Donation Terms');

// ---------------------------------------------------------------- the renderer and the link rules
check(chaos_wiki_link('javascript:alert(1)', 'en') === '' && chaos_wiki_link('//evil.example', 'en') === '' && chaos_wiki_link('http://x.example', 'en') === '', 'links: no javascript, protocol-relative or plain http');
check(chaos_wiki_link('wiki:nope:nope', 'en') === '' && chaos_wiki_link('wiki:class:warrior', 'en') === 'page.php?plugin=chaos&p=wiki&t=class%3Awarrior&l=en', 'links: wiki topics');
check(chaos_wiki_link('legal:donations', 'pt-BR') === 'page.php?plugin=chaos&p=legal&doc=donations' && chaos_wiki_link('legal:donations', 'en') === 'page.php?plugin=chaos&p=legal&doc=donations&l=en', 'links: legal texts in the same language');
$html = chaos_wiki_guide_html("# T <b>\n\nA **b** [x](javascript:alert(1)) [y](wiki:guide:faq) <script>alert(1)</script> {{nope.key}}\n\n- one\n  two\n", 'en');
check(strpos($html, '<h1 class="chaos-heading">T &lt;b&gt;</h1>') !== false, 'renderer: heading escaped');
check(strpos($html, '<script>') === false && strpos($html, '&lt;script&gt;') !== false && strpos($html, 'javascript') === false, 'renderer: no script, no javascript link');
check(strpos($html, '<a href="page.php?plugin=chaos&amp;p=wiki&amp;t=guide%3Afaq&amp;l=en">y</a>') !== false && strpos($html, '<strong>b</strong>') !== false, 'renderer: wiki link and bold');
check(strpos($html, '<li>one two</li>') !== false, 'renderer: list item continued');
check(chaos_wiki_conditions("a\n::: if nope.off\nhidden\n::: end\nb", 'en') === "a\n_Coming soon: not open in the game yet._\nb", 'a block behind a false fact reads coming soon');
check(chaos_wiki_conditions("a\n::: if class.ascensionLevel\nshown\n::: end\nb", 'pt-BR') === "a\nshown\nb", 'a block behind a true fact stays');
$entry = chaos_wiki_entry_html(array('id' => 'x', 'name' => '<i>N</i>', 'sub' => 'S&', 'color' => 'red;x:y', 'soon' => true,
	'sections' => array(array('h' => 'H', 'p' => array('<b>'), 'cols' => array('A', 'B'), 'rows' => array(array('class', '<x>')), 'links' => array('class:warrior')))), 'en');
check(strpos($entry, '&lt;i&gt;N&lt;/i&gt;') !== false && strpos($entry, 'S&amp;') !== false && strpos($entry, '<p>&lt;b&gt;</p>') !== false && strpos($entry, '<td>&lt;x&gt;</td>') !== false, 'entry: every value escaped');
check(strpos($entry, 'red;x:y') === false && strpos($entry, 'border-left-color:#d6c9ae') !== false, 'entry: a bad colour is replaced');
check(strpos($entry, '<a href="page.php?plugin=chaos&amp;p=wiki&amp;t=class%3Awarrior&amp;l=en">class</a>') !== false, 'entry: row link');
check(strpos($entry, 'Coming soon') !== false, 'entry: soon badge');

// ---------------------------------------------------------------- the pages
list($page, $code, $title) = render_wiki(array());
check($code === 200 && $title === 'Wiki', 'index: 200, title');
check(strpos($page, 'lang="pt-BR"') !== false && strpos($page, '>Guias</h2>') !== false && strpos($page, '>Referência</h2>') !== false, 'index: Portuguese by default');
check(strpos($page, 'href="page.php?plugin=chaos&amp;p=wiki&amp;l=en" lang="en">English</a>') !== false, 'index: English link');
foreach ($guides as $slug => $titles) {
	check(strpos($page, 'href="page.php?plugin=chaos&amp;p=wiki&amp;t=guide%3A' . $slug . '">' . chaos_h($titles['pt-BR']) . '</a>') !== false, "index: links guide $slug");
}
foreach ($tabIds as $id) {
	check(strpos($page, 'href="page.php?plugin=chaos&amp;p=wiki&amp;t=tab%3A' . $id . '"') !== false, "index: links tab $id");
}
check(strpos($page, 'name="q"') !== false && strpos($page, 'action="page.php"') !== false && strpos($page, 'name="l"') === false, 'index: search form, no language field in Portuguese');
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
check(strpos($page, 'href="page.php?plugin=chaos&amp;p=wiki&amp;q=Pyre%20Oath" lang="pt-BR"') !== false, 'search page: language link keeps the query');
list($page) = render_wiki(array('q' => 'a'));
check(strpos($page, 'Digite pelo menos 2 letras.') !== false, 'search page: too short');
list($page) = render_wiki(array('q' => str_repeat('x', 500)));
check(strpos($page, str_repeat('x', CHAOS_WIKI_QUERY_MAX + 1)) === false && strpos($page, 'Nada encontrado') !== false, 'search page: query cut, nothing found');
check(chaos_wiki_query(array('q' => array('x'))) === '' && chaos_wiki_query(array('q' => "\xff\xfe")) === '', 'search: arrays and bad UTF-8 ignored');

// ---------------------------------------------------------------- links to the wiki, sources
$src = (string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/pages/wiki.php');
check(strpos($src, "if (!isset(\$config)) { http_response_code(403);") !== false, 'no direct access');
$locale = include __DIR__ . '/../overlay/layouts/chaos/locale/en.php';
check(strpos((string)$locale['void.footer.copyright'], '<a href="page.php?plugin=chaos&amp;p=wiki">Wiki</a>') !== false, 'footer links the wiki');
check(strpos((string)file_get_contents(__DIR__ . '/../setup/chaos_setup.php'), "\$menu('Wiki', 'page.php?plugin=chaos&p=wiki'") !== false, 'menu entry');
check(strpos((string)file_get_contents(__DIR__ . '/../overlay/layouts/chaos/views/index.php'), 'href="page.php?plugin=chaos&amp;p=wiki">Read the guide</a>') !== false, 'home page button');
$css = (string)file_get_contents(__DIR__ . '/../overlay/layouts/chaos/assets/css/chaos.css');
check(strpos($css, '.chaos-wiki-search') !== false && strpos($css, '.chaos-wiki-scroll') !== false, 'layout styles');
$ci = (string)file_get_contents($repo . '/.github/workflows/ci.yml');
check(strpos($ci, 'gen_wiki_data.lua --check') !== false, 'CI checks the generated data');
check(strpos((string)file_get_contents($repo . '/CLAUDE.md'), 'gen_wiki_data.lua') !== false, 'CLAUDE.md lists the generator');

check($notices === array(), 'no PHP notices or warnings: ' . implode(' | ', array_slice($notices, 0, 3)));
restore_error_handler();
echo $failures ? implode("\n", $failures) . "\n" : '';
echo $failed === 0 ? "chaos_wiki_page_test: OK ($checks checks)\n" : "chaos_wiki_page_test: $failed of $checks failed\n";
exit($failed === 0 ? 0 : 1);
