<?php
/**
 * The legal texts (legal_lib.php): page?plugin=chaos&p=legal&doc=terms|privacy|donations[&l=en]. Portuguese by
 * default (the version that prevails), English with &l=en. Linked from the footer, the account creation form, the
 * donation page and the Rules page.
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once dirname(__DIR__) . '/legal_lib.php';

$docs = chaos_legal_docs();
$doc = (string)($_GET['doc'] ?? '');
if (!isset($docs[$doc])) {
	$doc = 'terms';
}
$lang = (string)($_GET['l'] ?? '') === 'en' ? 'en' : 'pt-BR';
$other = $lang === 'en' ? 'pt-BR' : 'en';
$md = chaos_legal_text($doc, $lang);
$GLOBALS['page_title'] = $docs[$doc][$lang];
?>
<div class="chaos-page">
	<div class="chaos-box chaos-legal" id="chaos-legal" lang="<?= chaos_h($lang) ?>">
		<p class="chaos-tabs chaos-legal__nav">
			<?php foreach ($docs as $key => $titles): ?>
				<a class="chaos-tab<?= $key === $doc ? ' is-active' : '' ?>" href="<?= chaos_h(chaos_legal_url($key, $lang)) ?>"><?= chaos_h($titles[$lang]) ?></a>
			<?php endforeach; ?>
			<a class="chaos-tab" href="<?= chaos_h(chaos_legal_url($doc, $other)) ?>" lang="<?= chaos_h($other) ?>"><?= $other === 'en' ? 'English' : 'Português' ?></a>
		</p>
		<?php if ($md === null): ?>
			<h1 class="chaos-heading"><?= chaos_h($docs[$doc][$lang]) ?></h1>
			<p class="chaos-empty"><?= $lang === 'en' ? 'This text is not available yet.' : 'Este texto ainda não está disponível.' ?></p>
		<?php else: ?>
			<?= chaos_legal_render($md, $lang) ?>
		<?php endif; ?>
	</div>
</div>
