<?php
/**
 * The short note shown instead of a stock ZnoteX page this server does not use (chaos_unused_pages in lib.php;
 * plugin.php sends those pages here). page?plugin=chaos&p=notused&what=store|creatures|spells|forum
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }

$notes = array(
	'store' => array('The store is in the game',
		'Chaos Coins and the store are in the game: open the Store in the client. Supporting the server is a voluntary donation on the Donate page; the game is fully playable for free.',
		array('page?plugin=chaos&p=coins' => 'Donate', 'downloads' => 'Download the client')),
	'creatures' => array('Creatures are in the game',
		'The creatures and the kill tasks are in the Bestiary of the game client.',
		array('downloads' => 'Download the client', 'serverinfo' => 'Server Info')),
	'spells' => array('Spells are in the game',
		'Every spell, with its numbers and area of effect, is in the Spellbook of the game client.',
		array('downloads' => 'Download the client', 'serverinfo' => 'Server Info')),
	'forum' => array('There is no forum here',
		'This website has no forum. Talk to other players in the game channels' . (chaos_cfg('discord_url', '') !== '' ? ' or on our Discord.' : '.'),
		array('page?plugin=chaos&p=patchnotes' => 'Patch Notes', 'page?p=rules' => 'Rules')),
);
$what = (string)($_GET['what'] ?? '');
if (!isset($notes[$what])) {
	$what = 'store';
}
list($title, $text, $links) = $notes[$what];
$discord = (string)chaos_cfg('discord_url', '');
if ($what === 'forum' && $discord !== '') {
	$links = array($discord => 'Discord') + $links;
}
$GLOBALS['page_title'] = $title;
?>
<div class="chaos-page">
	<div class="chaos-box chaos-notused">
		<h1 class="chaos-heading"><?= chaos_h($title) ?></h1>
		<p class="chaos-lead"><?= chaos_h($text) ?></p>
		<p class="chaos-notused__links">
			<?php foreach ($links as $href => $label): ?>
				<a class="chaos-tab" href="<?= chaos_h($href) ?>"><?= chaos_h($label) ?></a>
			<?php endforeach; ?>
			<a class="chaos-tab" href="./">Front page</a>
		</p>
	</div>
</div>
