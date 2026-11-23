<?php
/**
 * Staff: the live map of our tester bots (page?plugin=chaos&p=botmap; O727, website/README.md "Bot live map (O727)").
 * Admin panel accounts with a character of group 4 or higher; everyone else gets "not found". Read only. The page is the shell: Leaflet 1.9.4 (cdnjs,
 * pinned by its integrity hash), assets/js/chaos-botmap-core.js and chaos-botmap.js, which ask /chaos_botmap.php for the bots every 3 seconds and for the
 * map tiles' geometry once. Our own test bots only ("Tester Xxx"): no player is ever on this map, and nothing here helps a player bot.
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../botmap_lib.php';

$accountId = function_exists('getSession') ? (int)getSession('user_id') : 0;
if (chaos_botmap_group($config, $accountId) <= 0) {
	http_response_code(404);
	$GLOBALS['page_title'] = 'Not found';
	echo '<div class="chaos-page"><div class="chaos-box"><h1 class="chaos-heading">Not found</h1><p>This page does not exist.</p></div></div>';
	return;
}
$GLOBALS['page_title'] = 'Bot Map';
$asset = static function (string $path): string {
	return chaos_h(function_exists('znote_plugin_asset') ? znote_plugin_asset('chaos', $path) : 'plugins/chaos/assets/' . $path);
};
// Leaflet 1.9.4 from cdnjs, the sha512 of the files as cdnjs publishes them (api.cdnjs.com/libraries/leaflet/1.9.4?fields=sri)
$leaflet = 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/';
$sriCss = 'sha512-h9FcoyWjHcOcmEVkxOfTLnmZFWIH0iZhZT1H2TbOq55xssQGEJHEaIm+PgoUaZbRvQTNTluNOEfb1ZRy6D3BOw==';
$sriJs = 'sha512-puJW3E/qXDqYp9IfhAI54BJEaWIfloJ7JWs7OeD5i6ruC9JZL1gERT1wjtwXFlh7CjE7ZJ+/vcRZRkIYIb6p4g==';
?>
<link rel="stylesheet" href="<?= chaos_h($leaflet) ?>leaflet.min.css" integrity="<?= chaos_h($sriCss) ?>" crossorigin="anonymous" referrerpolicy="no-referrer">
<link rel="stylesheet" href="<?= $asset('css/chaos-botmap.css') ?>">
<div class="chaos-page" id="chaos-botmap" data-endpoint="chaos_botmap.php" data-poll="<?= (int)CHAOS_BOTMAP_POLL_MS ?>">
	<div class="chaos-box">
		<h1 class="chaos-heading">Bot Map</h1>
		<p class="chaos-lead">Where our test bots are and what they are doing, live. Click a bot for its goal, the reason it chose it, its next steps and its last log lines. Our own bots only: no player appears here. A bot with no news for 2 minutes turns grey and is dropped after 10.</p>

		<div class="chaos-bm__bar">
			<p class="chaos-bm__status" id="chaos-bm-status" role="status" aria-live="polite">Loading</p>
			<label class="chaos-bm__follow"><input type="checkbox" id="chaos-bm-follow"> Follow the bot picked</label>
		</div>
		<p class="chaos-bm__error" id="chaos-bm-error" role="alert" hidden></p>
		<div class="chaos-bm__floors" id="chaos-bm-floors" role="group" aria-label="Floor"></div>

		<div class="chaos-bm__layout">
			<div class="chaos-bm__mapwrap">
				<div class="chaos-bm__map" id="chaos-bm-map" role="application" aria-label="Map of the bots"></div>
				<div class="chaos-bm__nomap" id="chaos-bm-nomap" hidden>
					<p>No map tiles have been built yet, so the bots are listed without a map. Build them from the admin app (Commands &gt; Bot map &gt; Build map) or on the server with <code>chaos-ctl.sh botmap-build</code>.</p>
				</div>
			</div>
			<aside class="chaos-bm__side" aria-label="Bots">
				<div class="chaos-bm__roster" id="chaos-bm-roster"></div>
				<p class="chaos-bm__empty" id="chaos-bm-empty" hidden>No bot is running. Start some in the admin app (Commands &gt; Testers or Bots de jornada); they show here within seconds.</p>
				<section class="chaos-bm__panel" id="chaos-bm-panel" aria-label="The bot picked" hidden>
					<h2 class="chaos-heading" id="chaos-bm-p-name"></h2>
					<p class="chaos-bm__sub"><span id="chaos-bm-p-class"></span> <span class="chaos-bm-tag" id="chaos-bm-p-state"></span></p>
					<dl class="chaos-bm__fields" id="chaos-bm-p-fields"></dl>
					<h3>Plan</h3>
					<ol class="chaos-bm__plan" id="chaos-bm-p-plan"></ol>
					<p class="chaos-bm__note" id="chaos-bm-p-noplan">No plan published.</p>
					<h3>Last logs</h3>
					<ol class="chaos-bm__log" id="chaos-bm-p-log" tabindex="0" aria-label="Log, newest at the bottom"></ol>
					<p class="chaos-bm__note" id="chaos-bm-p-nolog">Nothing logged yet.</p>
				</section>
			</aside>
		</div>
		<noscript><p class="chaos-muted">The map needs JavaScript.</p></noscript>
	</div>
</div>
<script src="<?= chaos_h($leaflet) ?>leaflet.min.js" integrity="<?= chaos_h($sriJs) ?>" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
<script src="<?= $asset('js/chaos-botmap-core.js') ?>"></script>
<script src="<?= $asset('js/chaos-botmap.js') ?>"></script>
