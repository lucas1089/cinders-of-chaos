<?php
/**
 * The legal pages (website/README.md "Legal pages"): Terms of Use, Privacy Policy and Donation Terms, in Brazilian
 * Portuguese (the version that prevails) and English. Loaded by plugin.php and pages/coins.php.
 *
 *  - The texts are the Markdown files of docs/legal/ in the repository. install_site.sh copies them to
 *    plugins/chaos/legal/ (the web server denies .md files, the page reads them). chaos_legal_render() turns the small
 *    Markdown subset they use into HTML: headings, paragraphs, lists, tables, **bold** and links. Everything is
 *    escaped; a link goes only to another legal text, a site path ("/...") or an https:// address. A placeholder the
 *    owner has not filled in yet ("[NOME DO RESPONSÁVEL]") is marked so it stands out.
 *  - Account creation: our register_form view has the checkbox "I accept the Terms of Use and the Privacy Policy"
 *    (chaos_accept_terms). Without it, our register_header view puts an error into register.php's $errors, so nothing
 *    is created (the same way as the referral code and the per-IP limit). The acceptance is recorded with the texts'
 *    version in chaos_legal_acceptance on the account.registered hook.
 *  - The donation notices before and after payment (pages/coins.php).
 */

if (!function_exists('chaos_legal_docs')) {

define('CHAOS_LEGAL_LANGS', array('pt-BR', 'en'));

define('CHAOS_LEGAL_DONATION_BEFORE_EN', 'A donation gives no right to a refund, except where the law requires one. It is not the purchase of a product: Chaos Coins are a thank-you and have no real-world value.');
define('CHAOS_LEGAL_DONATION_BEFORE_PT', 'A doação não dá direito a reembolso, exceto quando a lei exigir. Ela não é a compra de um produto: as Chaos Coins são um agradecimento e não têm valor no mundo real.');
define('CHAOS_LEGAL_DONATION_AFTER_EN', 'This was a voluntary donation, not a purchase. It gives no right to a refund, except where the law requires one.');
define('CHAOS_LEGAL_DONATION_AFTER_PT', 'Esta foi uma doação voluntária, não uma compra. Ela não dá direito a reembolso, exceto quando a lei exigir.');
define('CHAOS_LEGAL_REGISTER_ERROR', 'Please accept the Terms of Use and the Privacy Policy. / Aceite os Termos de Uso e a Política de Privacidade.');

/** doc key => [language => title]. The file of a text is "<key>.<language>.md". */
function chaos_legal_docs(): array {
	return array(
		'terms'     => array('pt-BR' => 'Termos de Uso', 'en' => 'Terms of Use'),
		'privacy'   => array('pt-BR' => 'Política de Privacidade', 'en' => 'Privacy Policy'),
		'donations' => array('pt-BR' => 'Termos de Doação', 'en' => 'Donation Terms'),
	);
}

/** The folder with the texts: plugins/chaos/legal/ on the site, else docs/legal/ of the repository (tests). */
function chaos_legal_dir(): string {
	foreach (array(__DIR__ . '/legal', __DIR__ . '/../../../../docs/legal') as $dir) {
		if (is_file($dir . '/terms.pt-BR.md')) {
			return $dir;
		}
	}
	return '';
}

/** The page of a text. Portuguese is the default; English adds &l=en. */
function chaos_legal_url(string $doc, string $lang = 'pt-BR'): string {
	return 'page.php?plugin=chaos&p=legal&doc=' . rawurlencode($doc) . ($lang === 'en' ? '&l=en' : '');
}

/** The Markdown of a text, or null when the key, the language or the file is unknown. */
function chaos_legal_text(string $doc, string $lang): ?string {
	if (!isset(chaos_legal_docs()[$doc]) || !in_array($lang, CHAOS_LEGAL_LANGS, true)) {
		return null;
	}
	$dir = chaos_legal_dir();
	$file = $dir . '/' . $doc . '.' . $lang . '.md';
	if ($dir === '' || !is_file($file)) {
		return null;
	}
	$text = file_get_contents($file);
	return $text === false ? null : str_replace("\r\n", "\n", $text);
}

/** The version the account accepted: the first 16 hex digits of the SHA-256 of the three Portuguese texts. */
function chaos_legal_version(): string {
	$all = '';
	foreach (array_keys(chaos_legal_docs()) as $doc) {
		$all .= (string)chaos_legal_text($doc, 'pt-BR') . "\n";
	}
	return substr(hash('sha256', $all), 0, 16);
}

/** The placeholders still in a text ("[NOME DO RESPONSÁVEL]"), each once, in order. */
function chaos_legal_placeholders(string $md): array {
	preg_match_all('/\[([A-ZÀ-Ý0-9][A-ZÀ-Ý0-9 ,.\/$-]*[A-ZÀ-Ý0-9$])\](?!\()/u', $md, $m);
	return array_values(array_unique($m[0]));
}

/** One line of text: escaped, then links, bold and placeholders. */
function chaos_legal_inline(string $line, string $lang): string {
	$s = htmlspecialchars($line, ENT_QUOTES, 'UTF-8');
	$s = preg_replace_callback('/\[([^\]]+)\]\(([^)\s]+)\)/', static function (array $m) use ($lang): string {
		$url = html_entity_decode($m[2], ENT_QUOTES, 'UTF-8');
		if (preg_match('/^(terms|privacy|donations)\.(pt-BR|en)\.md$/', $url, $d)) {
			$url = chaos_legal_url($d[1], $d[2]);
		} elseif (!preg_match('#^(/(?!/)|https://)[^\s"\'<>]*$#', $url)) {
			return $m[1];
		}
		return '<a href="' . htmlspecialchars($url, ENT_QUOTES, 'UTF-8') . '">' . $m[1] . '</a>';
	}, $s);
	$s = preg_replace('/\*\*(.+?)\*\*/', '<strong>$1</strong>', $s);
	return (string)preg_replace('/\[([A-ZÀ-Ý0-9][A-ZÀ-Ý0-9 ,.\/$-]*[A-ZÀ-Ý0-9$])\](?!\()/u',
		'<mark class="chaos-legal-placeholder">[$1]</mark>', $s);
}

/** The Markdown subset of docs/legal/ as HTML (every value escaped). */
function chaos_legal_render(string $md, string $lang = 'pt-BR'): string {
	$out = array();
	$para = array();
	$list = null;   // ['ul'|'ol', [items]]
	$table = null;  // rows of cells
	$flush = static function () use (&$out, &$para, &$list, &$table, $lang): void {
		if ($para) {
			$out[] = '<p>' . chaos_legal_inline(implode(' ', $para), $lang) . '</p>';
			$para = array();
		}
		if ($list) {
			$items = array_map(static function (string $i) use ($lang): string { return '<li>' . chaos_legal_inline($i, $lang) . '</li>'; }, $list[1]);
			$out[] = '<' . $list[0] . '>' . implode('', $items) . '</' . $list[0] . '>';
			$list = null;
		}
		if ($table) {
			$html = '<table class="chaos-table chaos-legal__table">';
			foreach ($table as $i => $cells) {
				$tag = $i === 0 ? 'th' : 'td';
				$html .= ($i === 0 ? '<thead>' : ($i === 1 ? '<tbody>' : '')) . '<tr>';
				foreach ($cells as $c) {
					$html .= "<$tag>" . chaos_legal_inline($c, $lang) . "</$tag>";
				}
				$html .= '</tr>' . ($i === 0 ? '</thead>' : '');
			}
			$out[] = $html . (count($table) > 1 ? '</tbody>' : '') . '</table>';
			$table = null;
		}
	};
	foreach (explode("\n", $md) as $raw) {
		$line = rtrim($raw);
		if ($line === '') {
			$flush();
			continue;
		}
		if (preg_match('/^(#{1,3}) (.+)$/', $line, $m)) {
			$flush();
			$level = strlen($m[1]);
			$class = $level === 1 ? ' class="chaos-heading"' : '';
			$out[] = "<h$level$class>" . chaos_legal_inline($m[2], $lang) . "</h$level>";
			continue;
		}
		if ($line[0] === '|') {
			if ($para || $list) {
				$flush();
			}
			if (preg_match('/^\|[\s|:-]+\|$/', $line)) {
				continue; // the separator row
			}
			$table[] = array_map('trim', explode('|', trim($line, '|')));
			continue;
		}
		if (preg_match('/^(-|\d+\.) (.+)$/', $line, $m)) {
			$kind = $m[1] === '-' ? 'ul' : 'ol';
			if ($para || $table || ($list && $list[0] !== $kind)) {
				$flush();
			}
			$list = $list ?? array($kind, array());
			$list[1][] = $m[2];
			continue;
		}
		if ($list && preg_match('/^\s{2,}(.+)$/', $line, $m)) {
			$list[1][count($list[1]) - 1] .= ' ' . $m[1]; // a list item that goes on
			continue;
		}
		if ($list || $table) {
			$flush();
		}
		$para[] = trim($line);
	}
	$flush();
	return implode("\n", $out);
}

// ---------------------------------------------------------------- account creation

function chaos_legal_register_post(): bool {
	return ($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && !empty($_POST)
		&& basename((string)($_SERVER['SCRIPT_NAME'] ?? '')) === 'register.php';
}

function chaos_legal_accepted(): bool {
	return (string)($_POST['chaos_accept_terms'] ?? '') === '1';
}

/** Called by the register_header view: a posted form without the checkbox gets an error, so nothing is created. */
function chaos_legal_add_error(): void {
	if (chaos_legal_register_post() && !chaos_legal_accepted()) {
		$GLOBALS['errors'][] = CHAOS_LEGAL_REGISTER_ERROR;
	}
}

/** Records the acceptance of the new account (account.registered hook). */
function chaos_legal_record(string $accountName, int $now): void {
	if (!function_exists('chaos_table_exists') || !chaos_table_exists('chaos_legal_acceptance')) {
		return;
	}
	$row = db()->fetchOne('SELECT `id` FROM `accounts` WHERE `name` = ? LIMIT 1;', [$accountName]);
	if (!is_array($row)) {
		return;
	}
	db()->execute('INSERT INTO `chaos_legal_acceptance` (`account_id`, `version`, `accepted_at`) VALUES (?, ?, ?);',
		[(int)$row['id'], chaos_legal_version(), $now]);
}

}

// ---------------------------------------------------------------- hooks
if (chaos_legal_register_post() && chaos_legal_accepted() && function_exists('znote_hook_register')) {
	znote_hook_register('account.registered', static function (array $data): void {
		chaos_legal_record((string)($data['name'] ?? ''), time());
	});
}
