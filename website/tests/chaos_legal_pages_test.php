<?php
// php website/tests/chaos_legal_pages_test.php : the legal pages (plugins/chaos/legal_lib.php, pages/legal.php) with
// the texts of docs/legal/: every text in both languages, the renderer (escaping, links, placeholders, tables), the
// page and its tabs, the footer links, the Terms checkbox of account creation and its refusal through the
// register_header view, the acceptance row, the coin numbers of the Donation Terms against shop_coins_config.lua, the
// Rules page links, and the installer copying the texts. php-cli only, no ZnoteX, a fake database.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));
$GLOBALS['config'] = $config;

class ChaosLegalFakeDb {
	public $accounts = array('newbie' => 41);
	public $inserted = array();
	public function fetchOne(string $sql, array $params = array()) {
		if (strpos($sql, 'information_schema') !== false) {
			return array('n' => 1);
		}
		if (strpos($sql, 'FROM `accounts`') !== false) {
			return isset($this->accounts[$params[0]]) ? array('id' => $this->accounts[$params[0]]) : false;
		}
		return false;
	}
	public function fetchAll(string $sql, array $params = array()) {
		return array();
	}
	public function execute(string $sql, array $params = array()) {
		$this->inserted[] = array($sql, $params);
		return true;
	}
}
$fakeDb = new ChaosLegalFakeDb();
function db() {
	global $fakeDb;
	return $fakeDb;
}
$hooks = array();
function znote_hook_register(string $hook, callable $callback, int $priority = 10): void {
	global $hooks;
	$hooks[$hook][] = $callback;
}
function t(string $k): string { return $k; }

require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/legal_lib.php';

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
$repo = __DIR__ . '/../..';

// ---------------------------------------------------------------- the texts
check(realpath(chaos_legal_dir()) === realpath($repo . '/docs/legal'), 'texts read from docs/legal/ in the repository');
foreach (chaos_legal_docs() as $doc => $titles) {
	foreach (CHAOS_LEGAL_LANGS as $lang) {
		$md = chaos_legal_text($doc, $lang);
		check(is_string($md) && strpos($md, '# ' . $titles[$lang] . "\n") === 0, "$doc.$lang: starts with its title");
		check(stripos((string)$md, 'lawyer') === false && stripos((string)$md, 'advogad') === false, "$doc.$lang: no review note in the public text");
		check(strpos((string)$md, '—') === false, "$doc.$lang: no em-dash");
		check(in_array('[NOME DO RESPONSÁVEL]', chaos_legal_placeholders((string)$md), true), "$doc.$lang: the operator placeholder");
		preg_match_all('/\]\(((?:terms|privacy|donations)\.[A-Za-z-]+\.md)\)/', (string)$md, $m);
		foreach ($m[1] as $link) {
			check(is_file($repo . '/docs/legal/' . $link) && strpos($link, '.' . $lang . '.md') !== false, "$doc.$lang: link $link exists, same language");
		}
	}
	// both languages have the same placeholders and the same number of sections
	$pt = (string)chaos_legal_text($doc, 'pt-BR');
	$en = (string)chaos_legal_text($doc, 'en');
	check(chaos_legal_placeholders($pt) === chaos_legal_placeholders($en), "$doc: the same placeholders in both languages");
	check(substr_count($pt, "\n## ") === substr_count($en, "\n## "), "$doc: the same sections in both languages");
}
check(chaos_legal_text('nope', 'en') === null && chaos_legal_text('terms', 'de') === null && chaos_legal_text('../README', 'en') === null, 'unknown text or language: null');
$readme = (string)file_get_contents($repo . '/docs/legal/README.md');
check(strpos($readme, '> **Drafts.**') !== false && strpos($readme, 'lawyer') < 400, 'docs/legal/README.md starts with the review note');
check(preg_match('/^[0-9a-f]{16}$/', chaos_legal_version()) === 1, 'version: 16 hex digits');

// the required statements
$donPt = (string)chaos_legal_text('donations', 'pt-BR');
$donEn = (string)chaos_legal_text('donations', 'en');
check(strpos($donPt, '**Doar é voluntário.**') !== false && strpos($donPt, 'não dá direito a reembolso, exceto quando a lei exigir') !== false
	&& strpos($donPt, '**A doação não é a compra de um produto.**') !== false && strpos($donPt, 'não têm valor no mundo real') !== false, 'Donation Terms (PT): voluntary, no refund, not a purchase, no real-world value');
check(strpos($donEn, '**Donating is voluntary.**') !== false && strpos($donEn, 'no right to a refund, except where the law requires one') !== false
	&& strpos($donEn, '**A donation is not the purchase of a product.**') !== false && strpos($donEn, 'have no real-world value') !== false, 'Donation Terms (EN): the same');
$priv = (string)chaos_legal_text('privacy', 'pt-BR');
foreach (array('LGPD', 'Encarregado', 'Mercado Pago', 'PayPal', 'reCAPTCHA', 'Cookies', 'Transferência internacional', 'ANPD', 'Crianças') as $w) {
	check(strpos($priv, $w) !== false, "Privacy Policy mentions $w");
}
$terms = (string)chaos_legal_text('terms', 'pt-BR');
foreach (array('Lei e foro', 'Código de Defesa do Consumidor', '/page.php?p=rules', 'Wipes', 'bots', 'dinheiro real') as $w) {
	check(strpos($terms, $w) !== false, "Terms mention $w");
}

// the retention numbers in the policy are the code's numbers
$guard = (string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/register_guard.php');
$recov = (string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/recovery_lib.php');
check(strpos($guard, '$now - 86400') !== false && strpos($priv, 'Apagados depois de 1 dia') !== false, 'registrations: 1 day');
check(strpos($recov, '86400') !== false, 'recovery requests: 1 day');
$recap = (string)file_get_contents($repo . '/server/data/scripts/chaos/deathrecap_config.lua');
check((bool)preg_match('/\bkeep\s*=\s*5\b/', $recap) && strpos($priv, 'últimas 5 mortes') !== false, 'death recap: the last 5');
$rotate = (string)file_get_contents($repo . '/server/deploy/chaos.logrotate');
check(substr_count($rotate, 'rotate 14') === 2 && strpos($rotate, 'clientguard.log') !== false && strpos($priv, '| 14 dias |') !== false, 'logs: 14 days, the client guard log too');
$backup = (string)file_get_contents($repo . '/server/tools/backup.sh');
check(strpos($backup, 'CHAOS_BACKUP_KEEP_DAYS:-14') !== false || strpos($backup, 'KEEP_DAYS:=14') !== false || preg_match('/KEEP_DAYS[^\n]*14/', $backup) === 1, 'backups: 14 days on the server');

// the coin numbers of the Donation Terms are the server's packs
foreach (chaos_coin_packs() as $p) {
	check((bool)preg_match('/^\| ' . preg_quote($p['name'], '/') . '[^|]*\| ' . $p['total'] . ' \|/m', $donPt), 'Donation Terms (PT): ' . $p['name'] . ' = ' . $p['total']);
	check((bool)preg_match('/^\| ' . preg_quote($p['name'], '/') . '[^|]*\| ' . $p['total'] . ' \|/m', $donEn), 'Donation Terms (EN): ' . $p['name'] . ' = ' . $p['total']);
}
$coinCfg = chaos_coin_settings();
check(strpos($donPt, $coinCfg['first_bonus_pct'] . '% a mais') !== false && strpos($donEn, $coinCfg['first_bonus_pct'] . '% more') !== false, 'first donation bonus from the config');
check(strpos($donPt, 'até ' . $coinCfg['first_bonus_max'] . ' Chaos Coins a mais') !== false && strpos($donEn, 'up to ' . $coinCfg['first_bonus_max'] . ' extra Chaos Coins') !== false, 'the cap of the first donation bonus from the config');
$pay = chaos_pay_config();
check(strpos($donPt, $pay['expire_minutes'] . ' minutos') !== false && strpos($donPt, 'até ' . $pay['max_per_hour'] . ' por hora') !== false, 'expiry and hourly limit from the config');

// ---------------------------------------------------------------- the renderer
$html = chaos_legal_render("# Title <b>\n\nA **bold** line\ngoes on & on. <script>alert(1)</script>\n\n- one [NOME DO RESPONSÁVEL]\n  continued\n- [Privacy](privacy.en.md)\n\n1. first\n2. [bad](javascript:alert(1)) [site](/page?p=rules) [ext](https://example.invalid/x) [http](http://example.invalid)\n\n| A | B |\n|---|---|\n| x | [PREÇO EM R$] |\n");
check(strpos($html, '<h1 class="chaos-heading">Title &lt;b&gt;</h1>') !== false, 'heading escaped');
check(strpos($html, '<p>A <strong>bold</strong> line goes on &amp; on. &lt;script&gt;alert(1)&lt;/script&gt;</p>') !== false, 'paragraph joined, bold, escaped');
check(strpos($html, '<script>') === false, 'no script');
check(strpos($html, '<li>one <mark class="chaos-legal-placeholder">[NOME DO RESPONSÁVEL]</mark> continued</li>') !== false, 'placeholder marked, item continued');
check(strpos($html, '<a href="page?plugin=chaos&amp;p=legal&amp;doc=privacy&amp;l=en">Privacy</a>') !== false, 'a link to another text goes to its page');
check(strpos($html, 'javascript') === false && strpos($html, '<li>first</li>') !== false, 'javascript: link dropped');
check(strpos($html, '<a href="/page?p=rules">site</a>') !== false && strpos($html, '<a href="https://example.invalid/x">ext</a>') !== false, 'site path and https kept');
check(strpos($html, 'http://example.invalid') === false && strpos($html, ' http</li>') !== false, 'plain http: only the text stays');
check(strpos($html, '<ol>') !== false && strpos($html, '<ul>') !== false, 'both list kinds');
check(strpos($html, '<thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>x</td><td><mark class="chaos-legal-placeholder">[PREÇO EM R$]</mark></td></tr></tbody></table>') !== false, 'table');
check(chaos_legal_placeholders('[Rules](/x) [NOME] [ok] [A]') === array('[NOME]'), 'placeholders: caps only, not links, not one letter');

// ---------------------------------------------------------------- the page
function render_legal(array $get): string {
	global $config;
	$_GET = $get;
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/legal.php';
	return (string)ob_get_clean();
}
$page = render_legal(array('doc' => 'privacy'));
check(strpos($page, 'lang="pt-BR"') !== false && strpos($page, '<h1 class="chaos-heading">Política de Privacidade</h1>') !== false, 'privacy page in Portuguese by default');
check($GLOBALS['page_title'] === 'Política de Privacidade', 'page title');
check(strpos($page, 'class="chaos-tab is-active" href="page?plugin=chaos&amp;p=legal&amp;doc=privacy"') !== false, 'active tab');
check(strpos($page, 'href="page?plugin=chaos&amp;p=legal&amp;doc=privacy&amp;l=en" lang="en">English</a>') !== false, 'English link');
check(strpos($page, '<mark class="chaos-legal-placeholder">[E-MAIL DO ENCARREGADO]</mark>') !== false, 'placeholders marked on the page');
check(strpos($page, '<table') !== false, 'retention table');
$page = render_legal(array('doc' => 'donations', 'l' => 'en'));
check(strpos($page, '<h1 class="chaos-heading">Donation Terms</h1>') !== false && strpos($page, 'lang="pt-BR">Português</a>') !== false, 'English donation terms, link back');
$page = render_legal(array('doc' => '../../config'));
check(strpos($page, '<h1 class="chaos-heading">Termos de Uso</h1>') !== false, 'unknown doc: the Terms');
$src = (string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/pages/legal.php');
check(strpos($src, "if (!isset(\$config)) { http_response_code(403);") !== false, 'no direct access');

// ---------------------------------------------------------------- footer, Rules page, installer
$locale = include __DIR__ . '/../overlay/layouts/chaos/locale/en.php';
$footer = (string)($locale['void.footer.copyright'] ?? '');
check(strpos($footer, '&copy; {year} {site}') === 0, 'footer keeps the copyright');
foreach (array('terms', 'privacy', 'donations') as $doc) {
	check(strpos($footer, 'href="page?plugin=chaos&amp;p=legal&amp;doc=' . $doc . '"') !== false, "footer links $doc");
}
$rules = (string)file_get_contents(__DIR__ . '/../setup/rules.bbcode');
foreach (array('terms', 'privacy', 'donations') as $doc) {
	check(strpos($rules, '[url=/page?plugin=chaos&p=legal&doc=' . $doc . ']') !== false, "Rules page links $doc (root-relative: ZnoteX's BBCode allows only / and http(s))");
}
check(strpos($rules, '[b]7. Penalties[/b]') !== false && strpos($rules, 'mute 60 minutes, then mute 24 hours, then ban 7 days') !== false, 'the ladder on the Rules page');
check(strpos($rules, 'appeals channel') !== false, 'appeals on the Rules page');
$install = (string)file_get_contents(__DIR__ . '/../install_site.sh');
check(strpos($install, 'cp "$REPO/docs/legal/$doc.$lang.md" "$SITE/plugins/chaos/legal/"') !== false && strpos($install, 'chaos_legal_placeholders') !== false, 'installer copies the texts and warns about placeholders');
check(strpos((string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/plugin.php'), "require_once __DIR__ . '/legal_lib.php';") !== false, 'plugin loads legal_lib');
check(strpos((string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/install.sql'), 'CREATE TABLE IF NOT EXISTS `chaos_legal_acceptance`') !== false, 'install.sql creates the acceptance table');

// ---------------------------------------------------------------- account creation: the checkbox
$_POST = array();
$_SERVER['REQUEST_METHOD'] = 'GET';
$_SERVER['SCRIPT_NAME'] = '/register.php';
$config['use_captcha'] = false;
$config['countries'] = array('pl' => 'Poland', 'se' => 'Sweden', 'br' => 'Brazil', 'us' => 'USA', 'gb' => 'UK');
class Token { public static function create(): void { echo '<input type="hidden" name="token" value="t">'; } }
ob_start();
include __DIR__ . '/../overlay/layouts/chaos/views/register_form.php';
$form = (string)ob_get_clean();
check(strpos($form, '<input type="checkbox" name="chaos_accept_terms" value="1">') !== false, 'the checkbox, unchecked');
check(strpos($form, 'I accept the <a href="page?plugin=chaos&amp;p=legal&amp;doc=terms&amp;l=en"') !== false
	&& strpos($form, 'href="page?plugin=chaos&amp;p=legal&amp;doc=privacy&amp;l=en"') !== false, 'links to the Terms and the Privacy Policy');
check(strpos($form, 'Li e aceito os <a href="page?plugin=chaos&amp;p=legal&amp;doc=terms"') !== false && strpos($form, 'Under 18') !== false, 'Portuguese text and the under-18 note');
check(strpos($form, 'name="selected"') !== false && strpos($form, 'name="token"') !== false, 'the stock rules choice and the token stay');
check(strpos($form, '</li>', strpos($form, 'chaos-accept-terms')) < strpos($form, 'type="submit"'), 'checkbox before the submit button');
$header = function (): array {
	$GLOBALS['errors'] = array();
	ob_start();
	include __DIR__ . '/../overlay/layouts/chaos/views/register_header.php';
	ob_end_clean();
	return $GLOBALS['errors'];
};
check($header() === array(), 'GET: no error');
$_SERVER['REQUEST_METHOD'] = 'POST';
$_POST = array('username' => 'newbie', 'selected' => '1');
check($header() === array(CHAOS_LEGAL_REGISTER_ERROR), 'POST without the checkbox: refused');
$_POST['chaos_accept_terms'] = 'yes';
check($header() === array(CHAOS_LEGAL_REGISTER_ERROR), 'only the value 1 counts');
$_POST['chaos_accept_terms'] = '1';
check($header() === array(), 'POST with the checkbox: no error');
ob_start();
include __DIR__ . '/../overlay/layouts/chaos/views/register_form.php';
check(strpos((string)ob_get_clean(), 'value="1" checked>') !== false, 'stays checked after another error');
// the register guard and the referral code still add their errors next to ours
$GLOBALS['chaos_register_error'] = 'Too many accounts';
require __DIR__ . '/../overlay/plugins/chaos/register_guard.php';
unset($_POST['chaos_accept_terms']);
check($header() === array('Too many accounts', CHAOS_LEGAL_REGISTER_ERROR), 'the per-IP limit and the Terms both refuse');
$_SERVER['SCRIPT_NAME'] = '/createcharacter.php';
check($header() === array(), 'other pages: no Terms check');

// the acceptance is recorded on account.registered (hook registered only for an accepted register.php post)
$_SERVER['SCRIPT_NAME'] = '/register.php';
$_POST = array('username' => 'newbie', 'chaos_accept_terms' => '1');
$hooks = array();
include __DIR__ . '/../overlay/plugins/chaos/legal_lib.php';
check(count($hooks['account.registered'] ?? array()) === 1, 'hook registered for an accepted post');
$hooks['account.registered'][0](array('name' => 'newbie', 'email' => 'x@example.invalid'));
$row = end($fakeDb->inserted);
check(is_array($row) && strpos($row[0], 'INSERT INTO `chaos_legal_acceptance`') === 0 && $row[1][0] === 41 && $row[1][1] === chaos_legal_version() && $row[1][2] > 0, 'acceptance row: account, version, time');
check(count($row[1]) === 3, 'no IP stored');
$hooks = array();
$_POST = array('username' => 'newbie');
include __DIR__ . '/../overlay/plugins/chaos/legal_lib.php';
check(empty($hooks['account.registered']), 'no hook without the checkbox');

echo $failed === 0 ? "chaos_legal_pages_test: $checks checks OK\n" : "chaos_legal_pages_test: $failed of $checks failed\n";
exit($failed === 0 ? 0 : 1);
