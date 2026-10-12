<?php
/**
 * Guild wars: the wars running now (score, terms, time left) and the history (winner, payout, end reason, the kills the
 * anti-farming rules did not count), read from the game server's chaos_guildwar tables (guildwar_lib.php). Wars are
 * declared and answered in game (Social > Guild Wars).
 * page.php?plugin=chaos&p=guildwars
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once dirname(__DIR__) . '/guildwar_lib.php';
$GLOBALS['page_title'] = 'Guild Wars';

$state = chaos_guildwar_state(time(), 25);
$html = chaos_guildwar_html($state);
?>
<div class="chaos-page">
	<div class="chaos-box">
		<h1 class="chaos-heading">Guild Wars</h1>
		<p class="chaos-lead">Guild leaders declare war in the game (Social &gt; Guild Wars): a frag limit, a duration and, if they dare, gold from the guild bank at stake. The other guild accepts or declines in the game. Members of guilds at war wear the war emblems and gain no skull for killing each other. A kill counts when the victim is a real opponent: not from the same connection or account, of level 100 or more and at least half the killer's level, and the same victim once every 30 minutes. The first guild to the frag limit wins; when the time is up the guild with more kills does. The winner takes both stakes, minus a tenth that burns.</p>
		<?php if ($html === ''): ?>
			<p class="chaos-empty">No war has been declared yet.</p>
		<?php else: ?>
			<?= $html ?>
		<?php endif; ?>
	</div>
</div>
