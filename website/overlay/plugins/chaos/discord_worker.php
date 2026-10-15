<?php
/**
 * Discord announcements, the sender (discord_lib.php; website/README.md "Discord announcements"). Posts the rows the
 * game server queued in chaos_discord_queue, and the Character Bazaar's new listings and sales, to the channel webhooks
 * of the environment (CHAOS_DISCORD_WEBHOOK_<CHANNEL>). Run it from the installed site as the web server's user:
 *
 *   * * * * * www-data set -a; . /etc/chaos/discord.env; php <site>/plugins/chaos/discord_worker.php --site <site>  (cron)
 *   or server/deploy/chaos-discord.service + .timer (every minute, EnvironmentFile=/etc/chaos/discord.env)
 *
 * --loop [--interval S] keeps running (every S seconds, default 20) instead of one run. Without any webhook set it does
 * nothing (the queued rows wait).
 */
if (PHP_SAPI !== 'cli') {
	http_response_code(404);
	exit;
}
$opts = getopt('', array('site:', 'loop', 'interval:'));
$site = rtrim((string)($opts['site'] ?? dirname(__DIR__, 2)), '/');
if (!is_file($site . '/config.local.php')) {
	fwrite(STDERR, "No config.local.php in $site (pass --site <the website folder>).\n");
	exit(2);
}
$config = array();
require $site . '/config.local.php';
$GLOBALS['config'] = $config;
require_once __DIR__ . '/lib.php';
require_once __DIR__ . '/discord_lib.php';

[$hooks, $off, $name, $siteUrl] = ChaosDiscordWorker::settingsFromEnv(getenv());
if (!$hooks) {
	exit(0); // no webhook set (CHAOS_DISCORD_WEBHOOK_<CHANNEL>): Discord is off, the rows wait
}
$interval = max(5, (int)($opts['interval'] ?? 20));
do {
	try {
		$worker = new ChaosDiscordWorker(ChaosPayMysqli::fromConfig($config), $hooks, $off, $name, $siteUrl);
		$s = $worker->run(time());
		foreach ($worker->log as $line) {
			echo gmdate('H:i:s') . " discord: $line\n";
		}
		if ($s['sent'] + $s['failed'] + $s['queued'] > 0) {
			echo gmdate('H:i:s') . sprintf(" discord: %d sent, %d queued from the bazaar, %d failed, %d to retry, %d without a webhook\n",
				$s['sent'], $s['queued'], $s['failed'], $s['retry'], $s['nohook']);
		}
	} catch (Throwable $e) {
		fwrite(STDERR, gmdate('H:i:s') . ' discord round failed: ' . $e->getMessage() . "\n");
		if (!isset($opts['loop'])) {
			exit(1);
		}
	}
	if (isset($opts['loop'])) {
		sleep($interval);
	}
} while (isset($opts['loop']));
