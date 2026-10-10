<?php
// php website/tests/chaos_donation_page_test.php : the website's donation page (plugins/chaos/pages/coins.php) rendered
// with php-cli: the voluntary donation notice (English and Portuguese) before the packs, "Donate" on every button and
// no "Buy", a Pix donation from the page (mock provider, in-memory database), the thank-you after crediting, the
// history labelled "Donation". No ZnoteX, no network. Exit status 0 when every check passes.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'), 'site_url' => 'https://site.example.invalid');
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/pay/bootstrap.php';
require __DIR__ . '/chaos_pay_test_db.php';

$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}
$SESSION_USER = 0;
function getSession(string $k) { global $SESSION_USER; return $k === 'user_id' ? $SESSION_USER : null; }
function render(array $get = array(), array $post = array()): string {
	global $config;
	$_GET = $get; $_POST = $post;
	$_SERVER['REQUEST_METHOD'] = $post ? 'POST' : 'GET';
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/coins.php';
	return (string)ob_get_clean();
}
session_start();
// ZnoteX's db() over the same SQLite database (lib.php's own queries)
final class FakeZnoteDb {
	public function fetchOne(string $sql, array $p = array()) {
		if (strpos($sql, 'information_schema') !== false) { return array('n' => 1); }
		$r = $GLOBALS['TEST_DB']->rows($sql, $p); return $r[0] ?? false;
	}
	public function fetchAll(string $sql, array $p = array()) {
		$sql = str_replace('`', '', $sql);
		return $GLOBALS['TEST_DB']->rows($sql, $p);
	}
}
function db() { static $d; return $d ?? ($d = new FakeZnoteDb()); }

$db = chaos_pay_test_db();
$GLOBALS['TEST_DB'] = $db;
$state = tempnam(sys_get_temp_dir(), 'chaos_pay_page');
$GLOBALS['chaos_pay_service'] = new ChaosPayService($db, array('pix' => new ChaosPayMock('pix', 5, $state), 'paypal' => new ChaosPayMock('paypal', 5, $state)),
	chaos_pay_packs(), chaos_pay_config(), array('site_url' => 'https://site.example.invalid'), null, static function () {});

$notices = static function (string $html): bool {
	return strpos($html, chaos_h(ChaosPayService::NOTICE_EN)) !== false && strpos($html, chaos_h(ChaosPayService::NOTICE_PT)) !== false;
};
// logged out: notice, prices, no form
$html = render();
check($notices($html), 'notice (EN + PT) on the page');
check(strpos($html, 'Voluntary donation: it helps keep the server running.') < strpos($html, 'chaos-donation-packs'), 'notice before the packs');
check(strpos($html, 'R$ 74,95') !== false && strpos($html, 'US$ 14.99') !== false, 'both prices from the USD table');
check(strpos($html, '<form') === false && strpos($html, 'Log in to donate') !== false, 'no form when logged out');
check(stripos(strip_tags($html), 'buy chaos coins') === false && stripos($html, '>Buy') === false, 'no "Buy" wording');
check(strpos($html, 'thank-you for your donation') !== false, 'coins described as a thank-you');

// logged in: Donate buttons
$SESSION_USER = 77;
$html = render();
check($notices($html), 'notice when logged in');
check(substr_count($html, '>Donate R$ ') === 5 && substr_count($html, '>Donate US$ ') === 5, 'a Donate button per pack and method');
// a Pix donation from the page
$html = render(array(), array('chaos_pay_csrf' => 'wrong', 'chaos_pay_pack' => 'coins750', 'chaos_pay_method' => 'pix'));
check(strpos($html, 'The form expired') !== false, 'CSRF token checked');
$html = render(array(), array('chaos_pay_csrf' => $_SESSION['chaos_pay_csrf'], 'chaos_pay_pack' => 'coins750', 'chaos_pay_method' => 'pix'));
check(strpos($html, 'Your donation: Sack of Coins') !== false && strpos($html, '0014br.gov.bcb.pix') !== false, 'Pix code shown');
check(strpos($html, 'Cancel this donation') !== false, 'cancel link');
$db->exec("UPDATE chaos_coin_orders SET status = 'credited' WHERE id = 1");
$html = render(array('order' => '1'));
check(strpos($html, chaos_h('Thank you for your voluntary donation! You received 975 Chaos Coins as a thank-you.')) !== false, 'thanks after the donation (EN)');
check(strpos($html, chaos_h('Obrigado pela sua doação voluntária! Você recebeu 975 Chaos Coins como agradecimento.')) !== false, 'thanks after the donation (PT)');
check(strpos($html, 'Donation #1') !== false && strpos($html, 'Your donations') !== false, 'history labelled Donation');
// another account cannot see the order
$SESSION_USER = 78;
check(strpos(render(array('order' => '1')), 'Your donation:') === false, 'order of another account not shown');
// the site menu links the page (setup/chaos_setup.php adds the entry once)
$setup = (string)file_get_contents(__DIR__ . '/../setup/chaos_setup.php');
check(strpos($setup, "\$menu('Donate', 'page.php?plugin=chaos&p=coins'") !== false, 'menu entry for the donation page');
@unlink($state);
echo $failed === 0 ? "chaos_donation_page_test: OK\n" : "chaos_donation_page_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
