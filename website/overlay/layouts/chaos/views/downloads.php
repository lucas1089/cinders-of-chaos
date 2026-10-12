<?php
/**
 * Downloads: the client builds and how to connect. The links come from $config['downloads'] (written from
 * CHAOS_CLIENT_WINDOWS_URL / CHAOS_CLIENT_LINUX_URL by the installer; "#download-coming-soon" until they are set)
 * and can also be edited in Admin Panel > Downloads.
 */
$h = static function ($v): string { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); };
$entries = function_exists('znote_download_entries') ? znote_download_entries() : array();
$host = function_exists('chaos_cfg') ? (string)chaos_cfg('game_host', '') : '';
$port = function_exists('chaos_cfg') ? (int)chaos_cfg('game_port', 7171) : 7171;
$icons = array('windows_client' => 'fa-windows', 'linux_client' => 'fa-linux', 'macos_client' => 'fa-apple');
// ZnoteX replaces the label and description of its two built-in keys; ours are written here
$about = array(
	'windows_client' => array('Windows client', 'The Cinders of Chaos client for Windows 10 and 11 (64-bit).'),
	'linux_client' => array('Linux client', 'The Cinders of Chaos client for 64-bit Linux.'),
);
?>
<div class="chaos-page">
<div class="chaos-box">
	<h1 class="chaos-heading">Download the client</h1>
	<p class="chaos-lead">Cinders of Chaos is played with its own client: the dark skin, the top menu and a window for every system (passive tree, crafting bench, rifts, leaderboards, patch notes). It is free.</p>
	<div class="chaos-dl">
		<?php foreach ($entries as $e):
			$url = (string)$e['url'];
			$soon = ($url === '' || $url[0] === '#'); ?>
			<div class="chaos-dl__card">
				<i class="fa <?= $h($icons[$e['key']] ?? 'fa-download') ?>"></i>
				<h3><?= $h($about[$e['key']][0] ?? $e['label']) ?></h3>
				<p><?= $h($about[$e['key']][1] ?? $e['description']) ?></p>
				<?php if ($soon): ?>
					<span class="chaos-btn chaos-btn--ghost" aria-disabled="true">Coming soon</span>
				<?php else: ?>
					<a class="chaos-btn" href="<?= $h($url) ?>" rel="noopener">Download</a>
				<?php endif; ?>
			</div>
		<?php endforeach; ?>
	</div>
</div>

<div class="chaos-box">
	<h2 class="chaos-heading">How to start</h2>
	<ol class="chaos-steps">
		<li><a href="register.php">Create an account</a>, then <a href="createcharacter.php">create a character</a>: Warrior, Ranger, Mystic or Thief.</li>
		<li>Download the client for your system and unpack it into a folder of your choice.</li>
		<li>Start the client and log in with your account<?php if ($host !== ''): ?> (server <code><?= $h($host) ?></code>, port <code><?= (int)$port ?></code>; already set in the client)<?php endif; ?>.</li>
		<li>Your character wakes up on the tutorial island. Five stations teach you to fight, cast, spend a passive point and craft. Character > Services > Leave Tutorial leaves at any time.</li>
	</ol>
</div>
</div>
