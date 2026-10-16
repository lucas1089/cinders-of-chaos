<?php
/**
 * Community: the server-wide goal (its bar, the stage buffs open now, the top contributors), this week's world
 * modifiers and the latest news, read from the game server's chaos_community_* tables (community_lib.php).
 * page?plugin=chaos&p=community
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once dirname(__DIR__) . '/community_lib.php';
$GLOBALS['page_title'] = 'Community';

// tests pin the clock with $chaos_page_now (the goal rows are per week)
$state = chaos_community_state(isset($chaos_page_now) ? (int)$chaos_page_now : time(), 10);
$block = chaos_community_block_html($state, true);
?>
<div class="chaos-page">
	<div class="chaos-box">
		<h1 class="chaos-heading">Community goal</h1>
		<p class="chaos-lead">Everything the world does feeds the Great Brazier: monsters slain, rifts sealed, invasion waves repelled, world bosses slain, crafting orbs used and gold given to the Brazier in the temple. At 25%, 50%, 75% and 100% a blessing lights up for everyone online. Each character's part is capped per day; the top contributors earn a title, and everyone past the threshold a reward.</p>
		<?php if ($block === ''): ?>
			<p class="chaos-empty">The Brazier has not been lit yet.</p>
		<?php else: ?>
			<?= $block ?>
		<?php endif; ?>
		<p class="chaos-note">In the game: Adventure &gt; Community.</p>
	</div>
</div>
