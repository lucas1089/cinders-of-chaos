<?php
// php website/tests/chaos_notused_page_test.php : the stock pages this server does not use (lib.php chaos_unused_pages,
// pages/notused.php): which scripts are sent away, and the short note for each. php-cli only, no database.
$config = array('chaos' => array('discord_url' => ''));
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';

$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$pages = chaos_unused_pages();
foreach (array('shop.php' => 'store', 'buypoints.php' => 'store', 'creatures.php' => 'creatures', 'spells.php' => 'spells', 'forum.php' => 'forum') as $script => $what) {
	check(($pages[$script] ?? '') === $what, "$script -> $what");
}
foreach (array('houses.php', 'house.php', 'index.php', 'guilds.php', 'page.php', 'highscores.php') as $kept) {
	check(!isset($pages[$kept]), "$kept stays");
}

$render = static function (array $get): string {
	global $config;
	$_GET = $get;
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/notused.php';
	return (string)ob_get_clean();
};
$html = $render(array('what' => 'store'));
check(strpos($html, 'The store is in the game') !== false && strpos($html, 'p=coins') !== false, 'store note links Donate');
check(strpos($html, 'fully playable for free') !== false, 'store note: voluntary donation wording');
check(strpos($render(array('what' => 'forum')), 'no forum') !== false, 'forum note');
check(strpos($render(array('what' => 'forum')), 'Discord') === false, 'no Discord link without a Discord URL');
check(strpos($render(array('what' => 'creatures')), 'Bestiary') !== false, 'creatures note');
check(strpos($render(array('what' => 'spells')), 'Spellbook') !== false, 'spells note');
check(strpos($render(array('what' => '<script>')), '<script>') === false, 'unknown value: no echo, the store note');
$config['chaos']['discord_url'] = 'https://discord.example.org/x';
$GLOBALS['config'] = $config;
check(strpos($render(array('what' => 'forum')), 'href="https://discord.example.org/x"') !== false, 'forum note links the Discord');

echo $failed === 0 ? "chaos_notused_page_test: OK\n" : "chaos_notused_page_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
