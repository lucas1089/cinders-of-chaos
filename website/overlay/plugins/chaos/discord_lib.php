<?php
/**
 * Discord announcements, the sender (website/README.md "Discord announcements"; server/README.md "Discord
 * announcements"). The game server writes events to chaos_discord_queue (data/scripts/chaos/discord.lua); this worker
 * posts them to Discord channel webhooks as embeds in the brand colours, and adds the Character Bazaar's new listings
 * and sales from chaos_bazaar_log. Run by discord_worker.php (cron or server/deploy/chaos-discord.timer), never by the
 * game: the game loop never waits on HTTP.
 *
 * Configuration (environment only; no webhook URL or token in the repository):
 *   CHAOS_DISCORD_WEBHOOK_<CHANNEL>   the webhook of a channel: RECORDS, BOSSES, PLAYERS, ANNOUNCE, STATUS, BAZAAR
 *   CHAOS_DISCORD_WEBHOOK_DEFAULT     every channel without its own
 *   CHAOS_DISCORD_OFF                 event kinds not to post, comma separated (e.g. bazaar_list,level)
 *   CHAOS_DISCORD_NAME                the name shown on the posts (default "Cinders of Chaos")
 *   CHAOS_SITE_URL                    links of the bazaar posts
 * Only https://discord.com/api/webhooks/<id>/<token> (and discordapp.com) URLs are taken.
 *
 * Rate limits: at most maxPerRun posts a run; at least spacingMs between two posts to one webhook; a 429 answer sets
 * the row (and the rest of that webhook's rows this run) back by its retry_after; X-RateLimit-Remaining 0 waits for
 * X-RateLimit-Reset-After. Failures retry with a growing delay, maxAttempts times. Posts never ping anyone
 * (allowed_mentions parse = []), so a character name cannot mention @everyone.
 * Database: ChaosPayDb (pay/Db.php): mysqli on the site, PDO SQLite in the tests; the SQL is the subset both understand.
 */

if (!class_exists('ChaosDiscordWorker')) {

require_once __DIR__ . '/pay/Db.php';

final class ChaosDiscordWorker {
	public const KINDS = array('record', 'first', 'worldboss_spawn', 'worldboss_kill', 'ascended_kill', 'cinderheart_kill',
		'level', 'season_start', 'season_end', 'status_up', 'status_down', 'status_restart', 'bazaar_list', 'bazaar_sale', 'drop');
	/** Embed colours: the site's palette (layouts/chaos/assets/css/chaos.css). */
	public const COLORS = array(
		'record' => 0xD9A53A, 'first' => 0xF6CF72, 'worldboss_spawn' => 0xB8160F, 'worldboss_kill' => 0xE03A1E,
		'ascended_kill' => 0xE03A1E, 'cinderheart_kill' => 0x8A1010, 'level' => 0xD9A53A, 'season_start' => 0xF6CF72,
		'season_end' => 0xA87420, 'status_up' => 0xD9A53A, 'status_down' => 0x574D52, 'status_restart' => 0xA87420,
		'bazaar_list' => 0xA87420, 'bazaar_sale' => 0xD9A53A, 'drop' => 0xF6CF72,
	);
	public const CHANNELS = array('records', 'bosses', 'players', 'announce', 'status', 'bazaar', 'drops', 'default');

	private ChaosPayDb $db;
	/** @var array<string,string> channel => webhook URL ('default' for the rest) */
	private array $hooks;
	private array $off;
	private string $name;
	private string $siteUrl;
	/** @var callable(string $url, string $json): array{0:int,1:array,2:string} status, lower-case headers, body */
	private $http;
	/** @var callable(int $ms): void */
	private $sleep;
	public int $maxPerRun = 20;
	public int $spacingMs = 600;
	public int $maxAttempts = 5;
	public int $keepDays = 14;
	public array $log = array();

	public function __construct(ChaosPayDb $db, array $hooks, array $off = array(), string $name = 'Cinders of Chaos',
			string $siteUrl = '', ?callable $http = null, ?callable $sleep = null) {
		$this->db = $db;
		$this->hooks = $hooks;
		$this->off = array_fill_keys($off, true);
		$this->name = $name !== '' ? $name : 'Cinders of Chaos';
		$this->siteUrl = rtrim($siteUrl, '/');
		$this->http = $http ?? array(self::class, 'post');
		$this->sleep = $sleep ?? static function (int $ms): void { usleep($ms * 1000); };
	}

	/** True for a Discord webhook URL (nothing else is ever posted to). */
	public static function validHook(string $url): bool {
		return (bool)preg_match('~^https://(?:ptb\.|canary\.)?(?:discord|discordapp)\.com/api/webhooks/\d{5,30}/[A-Za-z0-9_\-]{20,100}$~', $url);
	}

	/** [hooks, off kinds, name, site url] from an environment array (getenv() on the server). */
	public static function settingsFromEnv(array $env): array {
		$hooks = array();
		foreach (self::CHANNELS as $ch) {
			$url = trim((string)($env['CHAOS_DISCORD_WEBHOOK_' . strtoupper($ch)] ?? ''));
			if ($url !== '' && self::validHook($url)) {
				$hooks[$ch] = $url;
			}
		}
		$off = array();
		foreach (explode(',', (string)($env['CHAOS_DISCORD_OFF'] ?? '')) as $k) {
			$k = trim($k);
			if (in_array($k, self::KINDS, true)) {
				$off[] = $k;
			}
		}
		return array($hooks, $off, trim((string)($env['CHAOS_DISCORD_NAME'] ?? '')), trim((string)($env['CHAOS_SITE_URL'] ?? '')));
	}

	public function hookFor(string $channel): ?string {
		return $this->hooks[$channel] ?? ($this->hooks['default'] ?? null);
	}

	/** The webhook body of a queue row. */
	public function payload(array $row): array {
		$fields = json_decode((string)($row['fields'] ?? '[]'), true);
		$embedFields = array();
		foreach (is_array($fields) ? $fields : array() as $fl) {
			if (!is_array($fl) || !isset($fl['name'], $fl['value'])) {
				continue;
			}
			$embedFields[] = array('name' => mb_substr((string)$fl['name'], 0, 256), 'value' => mb_substr((string)$fl['value'], 0, 1024),
				'inline' => !empty($fl['inline']));
			if (count($embedFields) >= 10) {
				break;
			}
		}
		$embed = array(
			'title' => mb_substr((string)$row['title'], 0, 256),
			'description' => mb_substr((string)$row['body'], 0, 4000),
			'color' => self::COLORS[(string)$row['kind']] ?? 0xD9A53A,
			'footer' => array('text' => $this->name),
			'timestamp' => gmdate('Y-m-d\TH:i:s\Z', (int)$row['created_at']),
		);
		if ($embedFields) {
			$embed['fields'] = $embedFields;
		}
		if (!empty($row['url'])) {
			$embed['url'] = (string)$row['url'];
		}
		return array('username' => $this->name, 'embeds' => array($embed), 'allowed_mentions' => array('parse' => array()));
	}

	public function queue(string $kind, string $channel, string $title, string $body, array $fields, int $now): void {
		$this->db->exec('INSERT INTO `chaos_discord_queue` (`created_at`, `kind`, `channel`, `title`, `body`, `fields`) VALUES (?, ?, ?, ?, ?, ?);',
			array($now, $kind, $channel, $title, $body, json_encode($fields)));
	}

	private function state(string $k): ?int {
		$rows = $this->db->rows('SELECT `v` FROM `chaos_discord_state` WHERE `k` = ?;', array($k));
		return $rows ? (int)$rows[0]['v'] : null;
	}

	private function setState(string $k, int $v): void {
		if ($this->db->exec('UPDATE `chaos_discord_state` SET `v` = ? WHERE `k` = ?;', array($v, $k)) === 0
			&& $this->state($k) === null) {
			$this->db->exec('INSERT INTO `chaos_discord_state` (`k`, `v`) VALUES (?, ?);', array($k, $v));
		}
	}

	/**
	 * New Character Bazaar listings and sales since the last run (chaos_bazaar_log 'list' / 'sold'), as queue rows.
	 * The first run only notes where the log is (no flood of old auctions). Returns the number queued.
	 */
	public function scanBazaar(int $now): int {
		$cursor = $this->state('bazaar_log');
		if ($cursor === null) {
			$max = $this->db->rows('SELECT MAX(`id`) AS `m` FROM `chaos_bazaar_log`;');
			$this->setState('bazaar_log', (int)($max[0]['m'] ?? 0));
			return 0;
		}
		$rows = $this->db->rows('SELECT `g`.`id`, `g`.`action`, `l`.`id` AS `lid`, `l`.`player_name`, `l`.`level`, `l`.`vocation`,
			`l`.`min_price`, `l`.`buyout`, `l`.`current_bid`, `l`.`ends_at`
			FROM `chaos_bazaar_log` `g` JOIN `chaos_bazaar_listings` `l` ON `l`.`id` = `g`.`listing_id`
			WHERE `g`.`id` > ? AND `g`.`action` IN (\'list\', \'sold\') ORDER BY `g`.`id` LIMIT 50;', array($cursor));
		$n = 0;
		$last = $cursor;
		$link = $this->siteUrl !== '' ? "\n" . $this->siteUrl . '/page?plugin=chaos&p=bazaar' : '';
		foreach ($rows as $r) {
			$last = max($last, (int)$r['id']);
			$kind = $r['action'] === 'sold' ? 'bazaar_sale' : 'bazaar_list';
			if (isset($this->off[$kind])) {
				continue;
			}
			$who = sprintf('%s, level %d %s', $r['player_name'], (int)$r['level'],
				function_exists('chaos_class_name') ? chaos_class_name((int)$r['vocation']) : 'character');
			if ($kind === 'bazaar_list') {
				$fields = array(array('name' => 'Minimum bid', 'value' => (int)$r['min_price'] . ' coins', 'inline' => true));
				if ((int)$r['buyout'] > 0) {
					$fields[] = array('name' => 'Buyout', 'value' => (int)$r['buyout'] . ' coins', 'inline' => true);
				}
				$fields[] = array('name' => 'Ends', 'value' => gmdate('Y-m-d H:i', (int)$r['ends_at']) . ' UTC', 'inline' => true);
				$this->queue($kind, 'bazaar', 'Character Bazaar: new auction', $who . ' is up for auction.' . $link, $fields, $now);
			} else {
				$this->queue($kind, 'bazaar', 'Character Bazaar: sold', $who . ' was sold.' . $link,
					array(array('name' => 'Price', 'value' => (int)$r['current_bid'] . ' coins', 'inline' => true)), $now);
			}
			$n++;
		}
		if ($last !== $cursor) {
			$this->setState('bazaar_log', $last);
		}
		return $n;
	}

	/** One run: the bazaar scan (when its tables exist), then up to maxPerRun posts, then the cleanup. Counts. */
	public function run(int $now, bool $bazaar = true): array {
		$stats = array('queued' => 0, 'sent' => 0, 'failed' => 0, 'retry' => 0, 'nohook' => 0, 'off' => 0);
		if ($bazaar) {
			try {
				$stats['queued'] = $this->scanBazaar($now);
			} catch (Throwable $e) {
				$this->log[] = 'bazaar scan skipped: ' . $e->getMessage();
			}
		}
		$rows = $this->db->rows('SELECT * FROM `chaos_discord_queue` WHERE `status` = \'new\' AND `next_at` <= ? ORDER BY `id` LIMIT ?;',
			array($now, $this->maxPerRun));
		$lastPost = array();
		$blocked = array(); // webhook => resume time (429 or no requests left)
		foreach ($rows as $row) {
			$id = (int)$row['id'];
			$kind = (string)$row['kind'];
			if (isset($this->off[$kind])) {
				$this->db->exec('UPDATE `chaos_discord_queue` SET `status` = \'off\' WHERE `id` = ?;', array($id));
				$stats['off']++;
				continue;
			}
			$url = $this->hookFor((string)$row['channel']);
			if ($url === null) {
				$this->db->exec('UPDATE `chaos_discord_queue` SET `status` = \'nohook\' WHERE `id` = ?;', array($id));
				$stats['nohook']++;
				continue;
			}
			if (isset($blocked[$url])) {
				$this->db->exec('UPDATE `chaos_discord_queue` SET `next_at` = ? WHERE `id` = ?;', array($blocked[$url], $id));
				$stats['retry']++;
				continue;
			}
			if (isset($lastPost[$url])) {
				$wait = $this->spacingMs - (int)((microtime(true) - $lastPost[$url]) * 1000);
				if ($wait > 0) {
					($this->sleep)($wait);
				}
			}
			[$status, $headers, $body] = ($this->http)($url, (string)json_encode($this->payload($row)));
			$lastPost[$url] = microtime(true);
			if ($status >= 200 && $status < 300) {
				$this->db->exec('UPDATE `chaos_discord_queue` SET `status` = \'sent\', `sent_at` = ?, `attempts` = `attempts` + 1, `error` = \'\' WHERE `id` = ?;',
					array($now, $id));
				$stats['sent']++;
				if (isset($headers['x-ratelimit-remaining']) && (int)$headers['x-ratelimit-remaining'] === 0) {
					$blocked[$url] = $now + max(1, (int)ceil((float)($headers['x-ratelimit-reset-after'] ?? 1)));
				}
				continue;
			}
			if ($status === 429) {
				$data = json_decode((string)$body, true);
				$after = (float)($data['retry_after'] ?? ($headers['retry-after'] ?? 5));
				$blocked[$url] = $now + max(1, (int)ceil($after));
				$this->db->exec('UPDATE `chaos_discord_queue` SET `next_at` = ?, `error` = ? WHERE `id` = ?;',
					array($blocked[$url], 'rate limited', $id));
				$stats['retry']++;
				continue;
			}
			$attempts = (int)$row['attempts'] + 1;
			$error = substr('HTTP ' . $status . ' ' . trim((string)$body), 0, 250);
			// 4xx other than 429: the webhook or the body is wrong; trying again will not help much, but a deleted and
			// recreated webhook can come back, so the same attempts apply
			if ($attempts >= $this->maxAttempts) {
				$this->db->exec('UPDATE `chaos_discord_queue` SET `status` = \'failed\', `attempts` = ?, `error` = ? WHERE `id` = ?;',
					array($attempts, $error, $id));
				$stats['failed']++;
			} else {
				$this->db->exec('UPDATE `chaos_discord_queue` SET `attempts` = ?, `next_at` = ?, `error` = ? WHERE `id` = ?;',
					array($attempts, $now + 60 * (2 ** ($attempts - 1)), $error, $id));
				$stats['retry']++;
			}
		}
		$this->db->exec('DELETE FROM `chaos_discord_queue` WHERE `status` IN (\'sent\', \'off\') AND `created_at` < ?;',
			array($now - $this->keepDays * 86400));
		$this->db->exec('DELETE FROM `chaos_discord_queue` WHERE `status` IN (\'failed\', \'nohook\') AND `created_at` < ?;',
			array($now - 2 * $this->keepDays * 86400));
		return $stats;
	}

	/** The default HTTP POST (curl when loaded, else a stream). Returns [status, lower-case headers, body]. */
	public static function post(string $url, string $json): array {
		$headers = array();
		if (function_exists('curl_init')) {
			$ch = curl_init($url);
			curl_setopt_array($ch, array(
				CURLOPT_POST => true, CURLOPT_POSTFIELDS => $json, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 10,
				CURLOPT_CONNECTTIMEOUT => 5, CURLOPT_HTTPHEADER => array('Content-Type: application/json', 'User-Agent: chaos-discord/1'),
				CURLOPT_PROTOCOLS => CURLPROTO_HTTPS | CURLPROTO_HTTP, CURLOPT_FOLLOWLOCATION => false,
				CURLOPT_HEADERFUNCTION => static function ($c, string $line) use (&$headers): int {
					$p = strpos($line, ':');
					if ($p !== false) {
						$headers[strtolower(trim(substr($line, 0, $p)))] = trim(substr($line, $p + 1));
					}
					return strlen($line);
				},
			));
			$body = curl_exec($ch);
			$status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
			curl_close($ch);
			return array($body === false ? 0 : $status, $headers, $body === false ? '' : (string)$body);
		}
		$ctx = stream_context_create(array('http' => array('method' => 'POST', 'timeout' => 10, 'ignore_errors' => true,
			'header' => "Content-Type: application/json\r\nUser-Agent: chaos-discord/1\r\n", 'content' => $json)));
		$body = @file_get_contents($url, false, $ctx);
		$status = 0;
		foreach ($http_response_header ?? array() as $line) {
			if (preg_match('~^HTTP/\S+\s+(\d{3})~', $line, $m)) {
				$status = (int)$m[1];
			} elseif (($p = strpos($line, ':')) !== false) {
				$headers[strtolower(trim(substr($line, 0, $p)))] = trim(substr($line, $p + 1));
			}
		}
		return array($status, $headers, $body === false ? '' : (string)$body);
	}
}

} // class_exists guard
