<?php
/**
 * Downloads: the client builds and how to connect. The links come from $config['downloads'] (written from
 * CHAOS_CLIENT_WINDOWS_URL / CHAOS_CLIENT_LINUX_URL by the installer; "#download-coming-soon" until they are set)
 * and can also be edited in Admin Panel > Downloads.
 * The Unity client (beta, ROADMAP O433 phase 16) is installed by the launcher of the Windows client ("Client: Unity client
 * (beta)"), so its card always explains that; an entry `unity_client` (CHAOS_CLIENT_UNITY_URL) adds a direct link.
 * The Windows card links to the launcher setup by itself (ROADMAP O552): when download/Cinders-of-Chaos-Setup.exe exists in the
 * site folder and its .sha256 (both written by server/deploy/publish_client_update.sh) holds a valid sum for that name, the
 * button is that file, with its size and SHA-256, and it wins over the configured windows_client link.
 */
$h = static function ($v): string { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); };
// the page's language for the Unity client card (plugins/chaos/i18n_lib.php, README "Languages"); English without the plugin
if (!function_exists('chaos_t') && is_file(dirname(__DIR__, 3) . '/plugins/chaos/i18n_lib.php')) {
	require_once dirname(__DIR__, 3) . '/plugins/chaos/i18n_lib.php';
}
if (!function_exists('chaos_t')) {
	function chaos_t(string $en, ...$args): string { return $args ? vsprintf($en, $args) : $en; }
}
$entries = function_exists('znote_download_entries') ? znote_download_entries() : array();
$host = function_exists('chaos_cfg') ? (string)chaos_cfg('game_host', '') : '';
$port = function_exists('chaos_cfg') ? (int)chaos_cfg('game_port', 7171) : 7171;
// the Discord invite (CHAOS_DISCORD_URL, $config['chaos']['discord_url']): a last step when it is an https link
$discord = function_exists('chaos_cfg') ? (string)chaos_cfg('discord_url', '') : '';
$discord = preg_match('~^https://~i', $discord) ? $discord : '';
$icons = array('windows_client' => 'fa-windows', 'linux_client' => 'fa-linux', 'macos_client' => 'fa-apple');
// ZnoteX replaces the label and description of its two built-in keys; ours are written here
$about = array(
	'windows_client' => array('Windows client', 'The Cinders of Chaos client for Windows 10 and 11 (64-bit).'),
	'linux_client' => array('Linux client', 'The Cinders of Chaos client for 64-bit Linux.'),
);
// Release, date, size and SHA-256 of the files in the site's dl/ folder: dl/downloads.json, written by the admin app's
// server update (server/deploy/chaos_kit_update.sh). A link whose file name is listed there shows them.
$dlInfoFile = (string)($GLOBALS['chaos_downloads_json'] ?? (dirname(__DIR__, 3) . '/dl/downloads.json'));
$dlInfo = is_file($dlInfoFile) ? json_decode((string)file_get_contents($dlInfoFile), true) : null;
$dlFiles = (is_array($dlInfo) && isset($dlInfo['files']) && is_array($dlInfo['files'])) ? $dlInfo['files'] : array();
$fileMeta = static function (string $url) use ($dlInfo, $dlFiles): ?array {
	$name = basename((string)parse_url($url, PHP_URL_PATH));
	$f = $dlFiles[$name] ?? null;
	if (!is_array($f) || !isset($f['size']) || !preg_match('/^[0-9a-f]{64}$/', (string)($f['sha256'] ?? ''))) {
		return null;
	}
	$mb = (int)$f['size'] / 1048576;
	return array(
		'line' => 'Release ' . (int)($dlInfo['release'] ?? 0) . ' · ' . (string)($dlInfo['updated'] ?? '') . ' · '
			. number_format($mb, $mb >= 100 ? 0 : 1) . ' MB',
		'sha' => (string)$f['sha256'],
	);
};
// The launcher setup of download/ (publish_client_update.sh): shown only with the file and a valid "<64 hex>  <name>" line.
// $GLOBALS['chaos_download_dir'] moves the folder (tests).
$setup = null;
$setupDir = (string)($GLOBALS['chaos_download_dir'] ?? (dirname(__DIR__, 3) . '/download'));
$setupName = 'Cinders-of-Chaos-Setup.exe';
if (is_file($setupDir . '/' . $setupName) && is_file($setupDir . '/' . $setupName . '.sha256')) {
	$parts = preg_split('/\s+/', trim((string)strtok((string)file_get_contents($setupDir . '/' . $setupName . '.sha256'), "\n")));
	$size = (int)filesize($setupDir . '/' . $setupName);
	if (is_array($parts) && count($parts) === 2 && preg_match('/^[0-9a-f]{64}$/i', $parts[0]) && ltrim($parts[1], '*') === $setupName && $size > 0) {
		$mb = $size / 1048576;
		$setup = array('url' => 'download/' . $setupName, 'sha' => strtolower($parts[0]), 'mb' => number_format($mb, $mb >= 100 ? 0 : 1));
	}
}
?>
<div class="chaos-page">
<div class="chaos-box">
	<h1 class="chaos-heading">Download the client</h1>
	<p class="chaos-lead">Cinders of Chaos is played with its own client: the dark skin, the top menu and a window for every system (passive tree, crafting bench, rifts, leaderboards, patch notes). It is free.</p>
	<div class="chaos-dl">
		<?php $unityUrl = '';
		foreach ($entries as $e):
			if (($e['key'] ?? '') === 'unity_client') {
				$u = (string)$e['url'];
				$unityUrl = ($u !== '' && $u[0] !== '#') ? $u : '';
				continue; // drawn below, with the launcher note
			}
			if (($e['key'] ?? '') === 'windows_client' && $setup !== null): ?>
			<div class="chaos-dl__card chaos-dl__card--setup">
				<i class="fa fa-windows"></i>
				<h3><?= $h($about['windows_client'][0]) ?></h3>
				<p><?= $h(chaos_t('The installer and launcher for Windows 10 and 11 (64-bit). It installs the game into your own folder, needs no administrator rights and keeps the game up to date.')) ?></p>
				<p class="chaos-dl__meta"><?= $h(chaos_t('Cinders-of-Chaos-Setup.exe · %s MB', $setup['mb'])) ?></p>
				<p class="chaos-dl__sum">SHA-256 <code><?= $h($setup['sha']) ?></code></p>
				<a class="chaos-btn" href="<?= $h($setup['url']) ?>" rel="noopener"><?= $h(chaos_t('Download')) ?></a>
			</div>
			<?php continue; endif;
			$url = (string)$e['url'];
			$soon = ($url === '' || $url[0] === '#'); ?>
			<div class="chaos-dl__card">
				<i class="fa <?= $h($icons[$e['key']] ?? 'fa-download') ?>"></i>
				<h3><?= $h($about[$e['key']][0] ?? $e['label']) ?></h3>
				<p><?= $h($about[$e['key']][1] ?? $e['description']) ?></p>
				<?php if ($soon): ?>
					<span class="chaos-btn chaos-btn--ghost" aria-disabled="true">Coming soon</span>
				<?php else: $meta = $fileMeta($url); ?>
					<?php if ($meta !== null): ?>
						<p class="chaos-dl__meta"><?= $h($meta['line']) ?></p>
						<p class="chaos-dl__sum">SHA-256 <code><?= $h($meta['sha']) ?></code></p>
					<?php endif; ?>
					<a class="chaos-btn" href="<?= $h($url) ?>" rel="noopener">Download</a>
				<?php endif; ?>
			</div>
		<?php endforeach; ?>
			<div class="chaos-dl__card chaos-dl__card--unity">
				<i class="fa fa-cube"></i>
				<h3><?= $h(chaos_t('Unity client (beta)')) ?></h3>
				<p><?= $h(chaos_t('A second client of the same game, made with Unity, for Windows 10 and 11 (64-bit). It plays on the same server with the same account as the main client. It is a beta: some windows and effects are not finished.')) ?></p>
				<p><?= $h(chaos_t('Install the Windows client, open its launcher and choose "Unity client (beta)" next to Client. The launcher downloads it and keeps it up to date.')) ?></p>
				<?php if ($unityUrl !== ''): ?>
					<a class="chaos-btn chaos-btn--ghost" href="<?= $h($unityUrl) ?>" rel="noopener"><?= $h(chaos_t('Download')) ?></a>
				<?php endif; ?>
			</div>
	</div>
</div>

<div class="chaos-box">
	<h2 class="chaos-heading"><?= $h(chaos_t('How to start')) ?></h2>
	<ol class="chaos-steps">
		<li><?= chaos_t('<a href="register">Create an account</a>, then <a href="createcharacter">create a character</a>: Warrior, Ranger, Mystic or Thief. The Necromancer, the Monk and the Templar open for the whole account once one of its characters reaches level 200.') ?></li>
		<?php if ($setup !== null): ?>
		<li><?= $h(chaos_t('On Windows, download the setup, run it and start the game from the launcher. On Linux, download the client and unpack it into a folder of your choice.')) ?></li>
		<?php else: ?>
		<li><?= $h(chaos_t('Download the client for your system and unpack it into a folder of your choice.')) ?></li>
		<?php endif; ?>
		<li><?= $h(chaos_t('Start the game and log in with your account.')) ?><?php if ($host !== ''): ?> <?= chaos_t('Server %s, port %s: already set in the game.', '<code>' . $h($host) . '</code>', '<code>' . (int)$port . '</code>') ?><?php endif; ?></li>
		<li><?= $h(chaos_t('Your character starts at level 8 in the Cinderhold temple, wearing its class kit. On the first login, System > Helper > Auto setup sets heals, potions and the attack rotation in one click.')) ?></li>
		<li><?= $h(chaos_t('Follow the main quest (Adventure > Main Quest) and the Next Goals card: they lead you through the world step by step.')) ?></li>
		<?php if ($discord !== ''): ?>
		<li><?= chaos_t('Join the community on %s: news, records, world bosses and help.', '<a href="' . $h($discord) . '" rel="noopener">Discord</a>') ?></li>
		<?php endif; ?>
	</ol>
</div>
</div>
