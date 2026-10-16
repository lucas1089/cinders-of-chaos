<?php
/**
 * The player wiki (wiki_lib.php, website/README.md "Wiki"): page?plugin=chaos&p=wiki[&t=<topic>][&q=<search>][&l=en].
 * The index (guides, reference tabs, search box), one page per guide, reference tab and entry, breadcrumbs, and the
 * search results. Portuguese by default, English with &l=en. An unknown topic is a 404. Art (wiki_lib.php): guide
 * heroes, tab banners, entry and tab icons, all lazy with alt text.
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once dirname(__DIR__) . '/wiki_lib.php';

$lang = chaos_wiki_lang($_GET);
$other = $lang === 'en' ? 'pt-BR' : 'en';
$topic = is_string($_GET['t'] ?? null) ? (string)$_GET['t'] : '';
$query = chaos_wiki_query($_GET);
$searching = isset($_GET['q']);
$found = chaos_wiki_resolve($topic);
$data = chaos_wiki_data();
$guides = chaos_wiki_guides();

$crumbs = array(array(chaos_wiki_t('wiki', $lang), $topic === '' && !$searching ? '' : chaos_wiki_url('', $lang)));
$title = chaos_wiki_t('wiki', $lang);
if ($searching) {
	$crumbs[] = array(chaos_wiki_t('search', $lang), '');
	$title = chaos_wiki_t('search', $lang);
} elseif ($found === null) {
	http_response_code(404);
	$title = chaos_wiki_t('notfound', $lang);
} elseif ($found['kind'] === 'guide') {
	$crumbs[] = array(chaos_wiki_t('guides', $lang), chaos_wiki_url('', $lang) . '#guides');
	$title = $guides[$found['slug']][$lang];
	$crumbs[] = array($title, '');
} elseif ($found['kind'] === 'tab') {
	$crumbs[] = array(chaos_wiki_t('reference', $lang), chaos_wiki_url('', $lang) . '#reference');
	$title = chaos_wiki_tab_name($found['tab'], $lang);
	$crumbs[] = array($title, '');
} elseif ($found['kind'] === 'entry') {
	$crumbs[] = array(chaos_wiki_t('reference', $lang), chaos_wiki_url('', $lang) . '#reference');
	$crumbs[] = array(chaos_wiki_tab_name($found['tab'], $lang), chaos_wiki_url('tab:' . $found['tab']['id'], $lang));
	$title = (string)($found['entry']['name'] ?? '');
	$crumbs[] = array($title, '');
}
$GLOBALS['page_title'] = $title === chaos_wiki_t('wiki', $lang) ? 'Wiki' : $title . ' - Wiki';
$here = chaos_wiki_url($searching ? '' : $topic, $other, $searching ? $query : '');
?>
<div class="chaos-page chaos-wiki" lang="<?= chaos_h($lang) ?>">
	<div class="chaos-box">
		<div class="chaos-wiki-top">
			<nav class="chaos-wiki-crumbs" aria-label="<?= chaos_h(chaos_wiki_t('crumbs', $lang)) ?>">
				<?php foreach ($crumbs as $i => $c): ?>
					<?php if ($i > 0): ?><span class="chaos-wiki-crumbs__sep" aria-hidden="true">›</span><?php endif; ?>
					<?php if ($c[1] !== ''): ?><a href="<?= chaos_h($c[1]) ?>"><?= chaos_h($c[0]) ?></a><?php else: ?><span aria-current="page"><?= chaos_h($c[0]) ?></span><?php endif; ?>
				<?php endforeach; ?>
			</nav>
			<a class="chaos-tab chaos-wiki-lang" href="<?= chaos_h($here) ?>" lang="<?= chaos_h($other) ?>"><?= chaos_h(chaos_wiki_t('other', $lang)) ?></a>
		</div>
		<form class="chaos-wiki-search" method="get" action="page" role="search">
			<input type="hidden" name="plugin" value="chaos">
			<input type="hidden" name="p" value="wiki">
			<?php if ($lang === 'en'): ?><input type="hidden" name="l" value="en"><?php endif; ?>
			<input type="search" name="q" value="<?= chaos_h($query) ?>" maxlength="<?= CHAOS_WIKI_QUERY_MAX ?>" placeholder="<?= chaos_h(chaos_wiki_t('search', $lang)) ?>" aria-label="<?= chaos_h(chaos_wiki_t('search', $lang)) ?>">
			<button type="submit" class="chaos-btn"><?= chaos_h(chaos_wiki_t('searchbtn', $lang)) ?></button>
		</form>
	</div>

	<?php if ($searching): ?>
		<div class="chaos-box chaos-wiki-results">
			<h1 class="chaos-heading"><?= chaos_h(chaos_wiki_t('results', $lang)) ?> “<?= chaos_h($query) ?>”</h1>
			<?php $res = mb_strlen($query, 'UTF-8') >= 2 ? chaos_wiki_search($query, $lang) : null; ?>
			<?php if ($res === null): ?>
				<p class="chaos-empty"><?= chaos_h(chaos_wiki_t('short', $lang)) ?></p>
			<?php elseif (!$res['results']): ?>
				<p class="chaos-empty"><?= chaos_h(chaos_wiki_t('noresults', $lang)) ?></p>
			<?php else: ?>
				<ol class="chaos-wiki-hits">
					<?php foreach ($res['results'] as $r): ?>
						<li>
							<?php $ricon = strncmp($r['topic'], 'guide:', 6) === 0 ? (string)(chaos_wiki_guide_art(substr($r['topic'], 6))['icon'] ?? '') : chaos_wiki_ref_icon($r['topic']); ?>
							<?= $ricon !== '' ? chaos_wiki_img($ricon, $r['title'], 24, 24, 'chaos-wiki-icon chaos-wiki-icon--row') : '' ?>
							<a class="chaos-wiki-hits__title" href="<?= chaos_h(chaos_wiki_url($r['topic'], $lang)) ?>"><?= chaos_h($r['title']) ?></a>
							<span class="chaos-wiki-hits__kind"><?= chaos_h($r['kind']) ?></span>
							<p><?= $r['snippet'] ?></p>
						</li>
					<?php endforeach; ?>
				</ol>
				<?php if ($res['more']): ?><p class="chaos-note"><?= chaos_h(chaos_wiki_t('more', $lang)) ?></p><?php endif; ?>
			<?php endif; ?>
		</div>

	<?php elseif ($found === null): ?>
		<div class="chaos-box">
			<h1 class="chaos-heading"><?= chaos_h(chaos_wiki_t('notfound', $lang)) ?></h1>
			<p><?= chaos_h(chaos_wiki_t('notfoundp', $lang)) ?></p>
			<a class="chaos-btn chaos-btn--ghost" href="<?= chaos_h(chaos_wiki_url('', $lang)) ?>"><?= chaos_h(chaos_wiki_t('back', $lang)) ?></a>
		</div>

	<?php elseif ($found['kind'] === 'index'): ?>
		<div class="chaos-box">
			<h1 class="chaos-heading"><?= chaos_h(chaos_wiki_t('wiki', $lang)) ?></h1>
			<p class="chaos-lead"><?= chaos_h(chaos_wiki_t('intro', $lang)) ?></p>
			<h2 class="chaos-subheading" id="guides"><?= chaos_h(chaos_wiki_t('guides', $lang)) ?></h2>
			<ul class="chaos-wiki-cards">
				<?php foreach ($guides as $slug => $titles): ?>
					<?php $md = chaos_wiki_guide_text($slug, $lang); $art = chaos_wiki_guide_art($slug); ?>
					<li class="chaos-wiki-card">
						<?php if ($art !== null): ?><a class="chaos-wiki-card__art" href="<?= chaos_h(chaos_wiki_url('guide:' . $slug, $lang)) ?>" tabindex="-1" aria-hidden="true"><?= chaos_wiki_img((string)($art['hero'] ?? ''), $titles[$lang], 960, 300, 'chaos-wiki-card__img') ?></a><?php endif; ?>
						<?= $art !== null ? chaos_wiki_img((string)($art['icon'] ?? ''), $titles[$lang], 28, 28, 'chaos-wiki-icon') : '' ?><a href="<?= chaos_h(chaos_wiki_url('guide:' . $slug, $lang)) ?>"><?= chaos_h($titles[$lang]) ?></a>
						<p><?= chaos_h($md === null ? '' : chaos_wiki_guide_summary($md, $lang)) ?></p>
					</li>
				<?php endforeach; ?>
			</ul>
			<h2 class="chaos-subheading" id="reference"><?= chaos_h(chaos_wiki_t('reference', $lang)) ?></h2>
			<?php if (!$data['tabs']): ?>
				<p class="chaos-empty"><?= chaos_h(chaos_wiki_t('unavailable', $lang)) ?></p>
			<?php else: ?>
				<?php if ($lang === 'pt-BR'): ?><p class="chaos-note"><?= chaos_h(chaos_wiki_t('refnote', $lang)) ?></p><?php endif; ?>
				<ul class="chaos-wiki-tabs">
					<?php foreach ($data['tabs'] as $tab): ?>
						<li><a href="<?= chaos_h(chaos_wiki_url('tab:' . $tab['id'], $lang)) ?>"><?= chaos_wiki_icon(array('icon' => $tab['icon'] ?? '', 'name' => chaos_wiki_tab_name($tab, $lang)), 32) ?><?= chaos_h(chaos_wiki_tab_name($tab, $lang)) ?></a>
							<span><?= count((array)($tab['entries'] ?? array())) ?> <?= chaos_h(chaos_wiki_t('entries', $lang)) ?></span></li>
					<?php endforeach; ?>
				</ul>
			<?php endif; ?>
		</div>

	<?php elseif ($found['kind'] === 'guide'): ?>
		<?php
		$md = chaos_wiki_guide_text($found['slug'], $lang);
		$slugs = array_keys($guides);
		$next = $slugs[array_search($found['slug'], $slugs, true) + 1] ?? null;
		?>
		<?php $art = chaos_wiki_guide_art($found['slug']); ?>
		<div class="chaos-box chaos-wiki-guide">
			<?php if ($art !== null): ?><?= chaos_wiki_hero((string)($art['hero'] ?? ''), chaos_wiki_t('heroalt', $lang) . ': ' . $title, 960, 300, false) ?><?php endif; ?>
			<?php if ($md === null): ?>
				<h1 class="chaos-heading"><?= chaos_h($title) ?></h1>
				<p class="chaos-empty"><?= chaos_h(chaos_wiki_t('unavailable', $lang)) ?></p>
			<?php else: ?>
				<?= chaos_wiki_guide_html($md, $lang) ?>
			<?php endif; ?>
			<?php if ($next !== null): ?>
				<p class="chaos-wiki-next"><?= chaos_h(chaos_wiki_t('next', $lang)) ?>: <a href="<?= chaos_h(chaos_wiki_url('guide:' . $next, $lang)) ?>"><?= chaos_h($guides[$next][$lang]) ?></a></p>
			<?php endif; ?>
		</div>

	<?php elseif ($found['kind'] === 'tab'): ?>
		<div class="chaos-box">
			<?= chaos_wiki_hero((string)($found['tab']['banner'] ?? ''), chaos_wiki_t('banneralt', $lang) . ': ' . $title, 960, 180, false) ?>
			<h1 class="chaos-heading"><?= chaos_h($title) ?></h1>
			<?php $group = null; ?>
			<ul class="chaos-wiki-list">
				<?php foreach ((array)($found['tab']['entries'] ?? array()) as $e): ?>
					<?php $g = (string)($e['group'] ?? ''); ?>
					<?php if ($g !== $group && $g !== ''): ?>
						<li class="chaos-wiki-list__group"><?= chaos_h(ucfirst($g)) ?></li>
					<?php endif; $group = $g; ?>
					<li class="chaos-wiki-list__item" style="border-left-color:<?= chaos_wiki_color($e) ?>">
						<?= chaos_wiki_icon($e, 32, 'chaos-wiki-icon chaos-wiki-list__icon') ?>
						<a href="<?= chaos_h(chaos_wiki_url((string)$e['id'], $lang)) ?>"><?= chaos_h($e['name'] ?? '') ?></a>
						<?php if (!empty($e['soon'])): ?><span class="chaos-wiki-badge"><?= chaos_h(chaos_wiki_t('soon', $lang)) ?></span><?php endif; ?>
						<span class="chaos-wiki-list__sub"><?= chaos_h($e['sub'] ?? '') ?></span>
					</li>
				<?php endforeach; ?>
			</ul>
		</div>

	<?php else: ?>
		<div class="chaos-box chaos-wiki-entry">
			<?= chaos_wiki_entry_html($found['entry'], $lang) ?>
		</div>
	<?php endif; ?>
</div>
