<?php
/**
 * The Capital Memorial: the realm firsts, the records and the fallen Hardcore characters of a season, each only with the
 * character's consent, and the archive of past seasons, read from the game server's chaos_memorial_entries
 * (memorial_lib.php). page?plugin=chaos&p=memorial (&s=<season key> for an archived season)
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once dirname(__DIR__) . '/memorial_lib.php';
$GLOBALS['page_title'] = 'The Memorial';

$seasons = chaos_memorial_seasons();
$want = (string)($_GET['s'] ?? '');
$current = $seasons ? $seasons[0]['key'] : '';
foreach ($seasons as $s) {
	if ($s['key'] === $want) {
		$current = $want;
	}
}
$season = $current !== '' ? chaos_memorial_season($current) : null;
?>
<div class="chaos-page">
	<div class="chaos-box">
		<h1 class="chaos-heading">The Ember Memorial</h1>
		<p class="chaos-lead">In the capital's Memorial the statues keep the season's realm firsts and records, and the memorial stones keep the heroes who fell in Hardcore. Every name is there by its player's choice: records and realm firsts unless the player turned them off, a fall only after a yes. In the game: Adventure &gt; Chronicle &gt; Memorial, where you can change your choice any time.</p>
		<?php if ($season === null): ?>
			<p class="chaos-empty">The Memorial is still empty.</p>
		<?php else: ?>
			<?php if (count($seasons) > 6): ?>
				<?php
				// more than six seasons: one dropdown (lib.php chaos_pick_form), the same &s= as the links, newest first
				$pickSeasons = array();
				foreach ($seasons as $s) {
					$pickSeasons[(string)$s['key']] = (string)$s['name'];
				}
				echo chaos_pick_form(array('plugin' => 'chaos', 'p' => 'memorial'), chaos_pick_select('s', 'Season', $pickSeasons, $current), 'Seasons');
				?>
			<?php elseif (count($seasons) > 1): ?>
				<p class="chaos-memorial__seasons">Seasons:
				<?php foreach ($seasons as $s): ?>
					<?php if ($s['key'] === $current): ?>
						<strong class="chaos-gold"><?= chaos_h($s['name']) ?></strong>
					<?php else: ?>
						<a href="page?plugin=chaos&amp;p=memorial&amp;s=<?= rawurlencode($s['key']) ?>"><?= chaos_h($s['name']) ?></a>
					<?php endif; ?>
				<?php endforeach; ?>
				</p>
			<?php endif; ?>
			<h2 class="chaos-subheading"><?= chaos_h($season['name']) ?><?= $current === ($seasons[0]['key'] ?? '') ? '' : ' (archive)' ?></h2>
			<?= chaos_memorial_season_html($season) ?>
		<?php endif; ?>
		<p class="chaos-note">The story of the season: <a href="page?plugin=chaos&amp;p=chronicle">the Ashen Chronicle</a>.</p>
	</div>
</div>
