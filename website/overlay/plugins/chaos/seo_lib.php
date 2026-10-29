<?php
/**
 * SEO and link previews (website/README.md "SEO and social previews"): the <head> of every page gets a title of its
 * own ("Page | Cinders of Chaos"), a description, the canonical address (the clean form, without .php), robots
 * (noindex on the account, login, staff and error pages), the Open Graph and Twitter card tags WhatsApp, Discord,
 * Facebook and the others read when a link is pasted, the icon set (favicon.ico, the PNG sizes, apple-touch-icon,
 * site.webmanifest) and, on the front page, JSON-LD for the organization, the site and the game.
 *
 * How: plugin.php opens an output buffer with chaos_seo_output() as its callback before the page runs; ZnoteX renders
 * the page into it (theme_close), and at the end the callback rewrites the <head> of the HTML (chaos_seo_rewrite):
 * the shell's <title> and icon links are replaced, our tags go before </head>. Output that is not an HTML page
 * (JSON, images, redirects) passes through unchanged. Nothing here queries the database: the page already loaded
 * what the tags need ($page_filename, $page_title, $profile_data of characterprofile.php, $_GET).
 *
 * Texts: chaos_t() keys (i18n/pt-BR.php). The language is the visitor's choice (&l=, the chaos_lang cookie), else
 * the browser's, else Portuguese (chaos_seo_lang): a crawler sends no language, so a pasted link previews in
 * Portuguese. The site name and address come from config.local.php (CHAOS_SITE_URL), never from this file.
 */

require_once __DIR__ . '/i18n_lib.php';

/** The language of the tags: the explicit choice, else the browser's, else Portuguese (crawlers). */
function chaos_seo_lang(?array $get = null, ?array $cookie = null, ?array $server = null): string {
	$get = $get ?? $_GET;
	$cookie = $cookie ?? $_COOKIE;
	$server = $server ?? $_SERVER;
	$lang = isset($get['l']) ? chaos_lang_normalize((string)$get['l']) : null;
	if ($lang === null && isset($cookie['chaos_lang'])) {
		$lang = chaos_lang_normalize((string)$cookie['chaos_lang']);
	}
	if ($lang === null && isset($server['HTTP_ACCEPT_LANGUAGE'])) {
		$lang = chaos_lang_from_header((string)$server['HTTP_ACCEPT_LANGUAGE']);
	}
	return $lang ?? 'pt-BR';
}

/** The site: name, address (no trailing slash), Discord invite, a custom favicon from the admin panel. */
function chaos_seo_site(?array $config = null, ?array $server = null): array {
	$config = $config ?? (array)($GLOBALS['config'] ?? array());
	$server = $server ?? $_SERVER;
	$url = rtrim(trim((string)($config['site_url'] ?? '')), '/');
	if ($url === '' && isset($server['HTTP_HOST']) && preg_match('/^[A-Za-z0-9.:\[\]-]+$/', (string)$server['HTTP_HOST'])) {
		$https = !empty($server['HTTPS']) && strtolower((string)$server['HTTPS']) !== 'off';
		$url = ($https ? 'https://' : 'http://') . $server['HTTP_HOST'];
	}
	return array(
		'name' => (string)($config['site_title'] ?? 'Cinders of Chaos'),
		'url' => $url,
		'discord' => (string)($config['chaos']['discord_url'] ?? ''),
		'favicon' => '',
	);
}

/** Pages that must not be indexed: the account, login, staff, payment and error pages ($page_filename values). */
function chaos_seo_private_pages(): array {
	return array('login', 'logout', 'register', 'recovery', 'myaccount', 'createcharacter', 'changepassword', 'settings',
		'twofa', 'accountsettings', 'paymentlog', 'changename', 'changesex', 'protected', 'failed', 'success', 'payment',
		'buypoints', 'shop', 'ipn', 'paygol_ipn', 'pagseguro_ipn', 'pagseguro_retorno', 'payment_webhook', 'twtrNews',
		'sub', 'blank', 'mailtest', 'auctionChar', 'market', 'voting', 'page_not_found', 'page_chaos_accept',
		'page_chaos_reports', 'page_chaos_botreview', 'page_chaos_telemetry', 'page_chaos_notused', 'page_chaos_deletecharacter');
}

/** The plugin pages whose body follows the visitor's language (the <html lang> is set for these). */
function chaos_seo_bilingual_pages(): array {
	return array('page_chaos_wiki', 'page_chaos_legal', 'page_chaos_credits', 'page_chaos_coins', 'page_chaos_bazaar',
		'page_chaos_creator', 'page_chaos_leaderboards', 'page_chaos_fairplay', 'page_chaos_calendar', 'page_chaos_creators');
}

/** Title (English key) and description key of the stock pages; the plugin pages set $page_title themselves. */
function chaos_seo_stock_titles(): array {
	return array(
		'highscores' => 'Highscores', 'onlinelist' => 'Players Online', 'guilds' => 'Guilds', 'topguilds' => 'Top Guilds',
		'downloads' => 'Download', 'serverinfo' => 'Server Info', 'changelog' => 'Changelog', 'deaths' => 'Latest Deaths',
		'killers' => 'Top Killers', 'powergamers' => 'Powergamers', 'houses' => 'Houses', 'house' => 'House', 'team' => 'Staff',
		'achievements' => 'Achievements', 'register' => 'Create Account', 'login' => 'Login', 'logout' => 'Logout',
		'recovery' => 'Account Recovery', 'myaccount' => 'Account', 'createcharacter' => 'Create Character',
		'changepassword' => 'Change Password', 'settings' => 'Settings', 'twofa' => 'Two-Factor Authentication',
		'faq' => 'FAQ', 'contact' => 'Contact', 'credits' => 'Credits', 'guildwar' => 'Guild Wars', 'bans' => 'Bans',
		'queststatus' => 'Quests', 'gallery' => 'Gallery', 'support' => 'Helpdesk', 'helpdesk' => 'Helpdesk',
		'characterprofile' => 'Character', 'page_rules' => 'Rules', 'page_not_found' => 'Not Found',
	);
}

/** Description keys per page (chaos_t keys; %s = the site name). */
function chaos_seo_descriptions(): array {
	return array(
		'index' => '%s: a free dark fantasy online RPG with its own client. 7 classes and 14 ascensions, a passive tree of 600+ nodes, items with rarities and crafting orbs, rifts, world bosses and seasons.',
		'highscores' => 'The top characters of %s by level, class and skill.',
		'onlinelist' => 'Who is playing %s right now.',
		'guilds' => 'The guilds of %s: members, ranks and wars.',
		'topguilds' => 'The biggest guilds of %s.',
		'downloads' => 'Download the %s client for Windows and Linux and start playing for free.',
		'serverinfo' => 'Rates, rules and settings of the %s server.',
		'changelog' => 'What changed in %s, version by version.',
		'deaths' => 'The latest deaths in %s.',
		'killers' => 'The deadliest players and monsters of %s.',
		'powergamers' => 'The characters that gained the most experience today in %s.',
		'houses' => 'The houses of %s and who owns them.',
		'team' => 'The staff of %s.',
		'achievements' => 'The achievements of %s and who earned them.',
		'register' => 'Create a free %s account and make your first character.',
		'guildwar' => 'The guild wars of %s.',
		'page_rules' => 'The rules of %s.',
		'page_chaos_patchnotes' => 'The patch notes of %s: every change to the game, newest first.',
		'page_chaos_leaderboards' => 'The weekly boards and all-time records of %s, by class.',
		'page_chaos_seasons' => 'The seasons of %s: fresh ladders, season uniques and the reward track.',
		'page_chaos_community' => 'The community goal and this week\'s world modifiers of %s.',
		'page_chaos_chronicle' => 'The Ashen Chronicle: the chapters of the running season of %s and the record of past seasons.',
		'page_chaos_memorial' => 'The Capital Memorial: realm firsts, records and the fallen of each season of %s.',
		'page_chaos_guildwars' => 'The guild wars of %s: running wars, scores and the latest results.',
		'page_chaos_mentors' => 'The mentors of %s: experienced players with free places for newcomers.',
		'page_chaos_bazaar' => 'The Character Bazaar of %s: character auctions for Chaos Coins.',
		'page_chaos_creator' => 'Creator codes of %s: support a creator with your donation.',
		'page_chaos_fairplay' => 'What the store of %s never sells: our fair-play pledge, and the time savers with their limits.',
		'page_chaos_calendar' => 'The calendar of %s: open betas, launch, seasons, patch notes and what resets.',
		'page_chaos_creators' => 'The creator program of %s: creator codes, a media kit and how to apply.',
		'page_chaos_coins' => 'Donate to %s and receive Chaos Coins for the in-game store.',
		'page_chaos_credits' => 'Every third-party source of %s: art, fonts, libraries and tools.',
		'page_chaos_wiki' => 'The %s wiki: guides for new players and a reference of classes, spells, items, rifts and bosses, generated from the game data.',
	);
}

/**
 * What the head says for one request. $ctx: page ($page_filename), script (SCRIPT_NAME), get, status (the HTTP
 * response code), page_title (the plugin pages' $GLOBALS['page_title']), profile ($profile_data of
 * characterprofile.php), lang, site (chaos_seo_site()).
 */
function chaos_seo_page(array $ctx): array {
	$site = (array)($ctx['site'] ?? chaos_seo_site());
	$lang = (string)($ctx['lang'] ?? 'pt-BR');
	$page = (string)($ctx['page'] ?? 'index');
	$script = (string)($ctx['script'] ?? '');
	$get = (array)($ctx['get'] ?? array());
	$status = (int)($ctx['status'] ?? 200);
	$pageTitle = trim((string)($ctx['page_title'] ?? ''));
	$profile = $ctx['profile'] ?? null;
	$name = $site['name'];
	$t = static function (string $en, ...$args) use ($lang): string {
		return chaos_t_in($lang, $en, ...$args);
	};
	$admin = strpos($script, '/admin/') !== false;
	$private = $admin || $status >= 400 || in_array($page, chaos_seo_private_pages(), true);
	$title = '';
	$description = '';
	$params = array();
	$path = '/' . $page;
	$type = 'website';
	$jsonld = false;
	$descriptions = chaos_seo_descriptions();
	$stock = chaos_seo_stock_titles();

	if ($page === 'index') {
		$path = '/';
		$news = isset($get['view']) || (int)($get['page'] ?? 0) > 0;
		if ($news) {
			$title = $t('News');
			$params = array('view', 'page');
		} else {
			$jsonld = !$private;
		}
		$description = $t($descriptions['index'], $name);
	} elseif ($page === 'characterprofile') {
		$charName = is_array($profile) ? trim((string)($profile['name'] ?? '')) : '';
		if ($charName !== '') {
			$level = (int)($profile['level'] ?? 0);
			$class = (string)($profile['class'] ?? '');
			$title = $charName;
			$description = $t('%s, level %d %s of %s: profile, deaths and the account\'s characters.', $charName, $level, $class, $name);
			$path = '/' . rawurlencode($charName);
			$type = 'profile';
		} else {
			$title = $t('Character');
			$description = $t('No character with this name in %s.', $name);
			$private = true;
		}
	} elseif (strncmp($page, 'page_', 5) === 0) {
		$path = '/page';
		$params = array('plugin', 'p', 'doc', 't', 's', 'l', 'what');
		if ($page === 'page_rules') {
			$params = array('p');
		}
		$title = $pageTitle !== '' ? $pageTitle : (isset($stock[$page]) ? $t($stock[$page]) : '');
		if ($title === '') {
			$title = ucwords(str_replace(array('-', '_'), ' ', substr($page, strpos($page, '_chaos_') !== false ? 11 : 5)));
		}
		if ($page === 'page_chaos_wiki' && $pageTitle !== '' && $pageTitle !== 'Wiki') {
			$topic = preg_replace('/ - Wiki$/', '', $pageTitle);
			$description = $t('%s in the %s wiki: guides and a reference generated from the game data.', $topic, $name);
		} elseif ($page === 'page_chaos_legal' && $pageTitle !== '') {
			$description = $t('%s of %s.', $pageTitle, $name);
		} elseif (isset($descriptions[$page])) {
			$description = $t($descriptions[$page], $name);
		}
	} else {
		$title = isset($stock[$page]) ? $t($stock[$page]) : ucwords(str_replace(array('-', '_'), ' ', $page));
		if ($page === 'guilds' && trim((string)($get['name'] ?? '')) !== '') {
			$guild = trim((string)$get['name']);
			$title = $t('Guild %s', $guild);
			$description = $t('The guild %s of %s: members, ranks and wars.', $guild, $name);
			$params = array('name');
		} elseif (isset($descriptions[$page])) {
			$description = $t($descriptions[$page], $name);
		}
		if ($page === 'houses') {
			$params = array('town');
		}
	}
	if ($description === '') {
		$description = $t($descriptions['index'], $name);
	}
	$fullTitle = $page === 'index' && $title === '' ? $name . ' | ' . $t('Dark fantasy online RPG') : $title . ' | ' . $name;

	$query = array();
	foreach ($params as $k) {
		if (isset($get[$k]) && is_scalar($get[$k]) && (string)$get[$k] !== '') {
			$query[$k] = (string)$get[$k];
		}
	}
	$canonical = $site['url'] !== '' && !$private ? $site['url'] . $path . ($query ? '?' . http_build_query($query, '', '&', PHP_QUERY_RFC3986) : '') : '';

	return array(
		'title' => $fullTitle,
		'og_title' => $title === '' ? $name : $title,
		'description' => $description,
		'canonical' => $canonical,
		'robots' => $private ? 'noindex, nofollow' : 'index, follow, max-image-preview:large',
		'type' => $type,
		'lang' => $lang,
		'html_lang' => in_array($page, chaos_seo_bilingual_pages(), true) ? $lang : null,
		'jsonld' => $jsonld,
		'admin' => $admin,
	);
}

/** The icon files (paths from the web root) the head and site.webmanifest name. */
function chaos_seo_icons(): array {
	$img = '/layouts/chaos/assets/img/';
	return array(
		'ico' => '/favicon.ico',
		'png32' => $img . 'favicon-32x32.png',
		'png16' => $img . 'favicon-16x16.png',
		'apple' => $img . 'apple-touch-icon.png',
		'android192' => $img . 'android-chrome-192x192.png',
		'android512' => $img . 'android-chrome-512x512.png',
		'og' => $img . 'og-image-1200x630.jpg',
		'manifest' => '/site.webmanifest',
	);
}

const CHAOS_SEO_THEME_COLOR = '#0d0b0e';

/** JSON-LD of the front page: the organization, the site and the game. No ratings, no reviews. */
function chaos_seo_jsonld(array $site, array $seo): string {
	$icons = chaos_seo_icons();
	$org = array('@type' => 'Organization', 'name' => $site['name'], 'url' => $site['url'] . '/',
		'logo' => $site['url'] . $icons['android512']);
	if ($site['discord'] !== '' && preg_match('#^https://#', $site['discord'])) {
		$org['sameAs'] = array($site['discord']);
	}
	$graph = array(
		$org,
		array('@type' => 'WebSite', 'name' => $site['name'], 'url' => $site['url'] . '/',
			'inLanguage' => array('pt-BR', 'en')),
		array('@type' => 'VideoGame', 'name' => $site['name'], 'url' => $site['url'] . '/',
			'image' => $site['url'] . $icons['og'], 'description' => $seo['description'],
			'genre' => 'MMORPG', 'playMode' => 'MultiPlayer', 'applicationCategory' => 'Game',
			'operatingSystem' => 'Windows, Linux', 'isAccessibleForFree' => true, 'inLanguage' => array('pt-BR', 'en')),
	);
	$json = json_encode(array('@context' => 'https://schema.org', '@graph' => $graph),
		JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP);
	return '<script type="application/ld+json">' . $json . '</script>' . "\n";
}

/** The tags that go before </head>. */
function chaos_seo_head(array $seo, array $site): string {
	$h = static function ($v): string { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); };
	$out = '<meta name="robots" content="' . $h($seo['robots']) . '">' . "\n";
	if (!empty($seo['admin'])) {
		return $out;
	}
	$icons = chaos_seo_icons();
	$url = $site['url'];
	$image = $url !== '' ? $url . $icons['og'] : $icons['og'];
	$locale = $seo['lang'] === 'pt-BR' ? 'pt_BR' : 'en_US';
	$other = $seo['lang'] === 'pt-BR' ? 'en_US' : 'pt_BR';
	$out .= '<meta name="description" content="' . $h($seo['description']) . '">' . "\n";
	if ($seo['canonical'] !== '') {
		$out .= '<link rel="canonical" href="' . $h($seo['canonical']) . '">' . "\n";
	}
	$out .= '<meta name="theme-color" content="' . CHAOS_SEO_THEME_COLOR . '">' . "\n"
		. '<meta property="og:site_name" content="' . $h($site['name']) . '">' . "\n"
		. '<meta property="og:type" content="' . $h($seo['type']) . '">' . "\n"
		. '<meta property="og:title" content="' . $h($seo['og_title']) . '">' . "\n"
		. '<meta property="og:description" content="' . $h($seo['description']) . '">' . "\n"
		. ($seo['canonical'] !== '' ? '<meta property="og:url" content="' . $h($seo['canonical']) . '">' . "\n" : '')
		. '<meta property="og:locale" content="' . $locale . '">' . "\n"
		. '<meta property="og:locale:alternate" content="' . $other . '">' . "\n"
		. '<meta property="og:image" content="' . $h($image) . '">' . "\n"
		. (strncmp($image, 'https://', 8) === 0 ? '<meta property="og:image:secure_url" content="' . $h($image) . '">' . "\n" : '')
		. '<meta property="og:image:type" content="image/jpeg">' . "\n"
		. '<meta property="og:image:width" content="1200">' . "\n"
		. '<meta property="og:image:height" content="630">' . "\n"
		. '<meta property="og:image:alt" content="' . $h($site['name'] . ' - ' . chaos_t_in($seo['lang'], 'Dark fantasy online RPG')) . '">' . "\n"
		. '<meta name="twitter:card" content="summary_large_image">' . "\n"
		. '<meta name="twitter:title" content="' . $h($seo['og_title']) . '">' . "\n"
		. '<meta name="twitter:description" content="' . $h($seo['description']) . '">' . "\n"
		. '<meta name="twitter:image" content="' . $h($image) . '">' . "\n"
		. '<link rel="icon" href="' . $h($icons['ico']) . '" sizes="any">' . "\n"
		. '<link rel="icon" type="image/png" sizes="32x32" href="' . $h($site['favicon'] !== '' ? $site['favicon'] : $icons['png32']) . '">' . "\n"
		. '<link rel="icon" type="image/png" sizes="16x16" href="' . $h($icons['png16']) . '">' . "\n"
		. '<link rel="apple-touch-icon" sizes="180x180" href="' . $h($icons['apple']) . '">' . "\n"
		. '<link rel="manifest" href="' . $h($icons['manifest']) . '">' . "\n";
	if (!empty($seo['jsonld']) && $url !== '') {
		$out .= chaos_seo_jsonld($site, $seo);
	}
	return $out;
}

/** The page's HTML with its <head> rewritten; anything that is not an HTML page comes back unchanged. */
function chaos_seo_rewrite(string $html, array $seo, array $site): string {
	$headEnd = stripos($html, '</head>');
	$headStart = stripos($html, '<head');
	if ($headStart === false || $headEnd === false || $headEnd < $headStart) {
		return $html;
	}
	$head = substr($html, $headStart, $headEnd - $headStart);
	$h = static function ($v): string { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); };
	if (empty($seo['admin'])) {
		// the shell's title and icon links, and any description or robots tag already there, give way to ours
		$head = preg_replace('#<title>.*?</title>#is', '<title>' . $h($seo['title']) . '</title>', $head, 1);
		$head = preg_replace('#[ \t]*<link\b[^>]*\brel=(["\'])(?:shortcut icon|icon|apple-touch-icon|manifest)\1[^>]*>[ \t]*\r?\n?#i', '', $head);
		$head = preg_replace('#[ \t]*<meta\b[^>]*\bname=(["\'])(?:description|robots)\1[^>]*>[ \t]*\r?\n?#i', '', $head);
	}
	$html = substr($html, 0, $headStart) . $head . chaos_seo_head($seo, $site) . substr($html, $headEnd);
	if (!empty($seo['html_lang'])) {
		$html = preg_replace('#<html\b([^>]*)\blang=(["\'])[^"\']*\2#i', '<html$1lang="' . $h($seo['html_lang']) . '"', $html, 1);
	}
	return $html;
}

/** The context of the running request, from the globals the page left. */
function chaos_seo_context(): array {
	$profile = null;
	if (isset($GLOBALS['profile_data']) && is_array($GLOBALS['profile_data'])) {
		$p = $GLOBALS['profile_data'];
		$profile = array('name' => (string)($p['name'] ?? ''), 'level' => (int)($p['level'] ?? 0),
			'class' => function_exists('vocation_id_to_name') ? (string)vocation_id_to_name((int)($p['vocation'] ?? 0)) : '');
	}
	$site = chaos_seo_site();
	if (function_exists('theme_option') && function_exists('theme_css_url') && function_exists('theme_active') && theme_active() === 'chaos') {
		$custom = theme_css_url(theme_option('favicon'));
		if ($custom !== '' && $custom !== 'layouts/chaos/assets/img/favicon.png') {
			$site['favicon'] = (strncmp($custom, '/', 1) === 0 || preg_match('~^(https?:)?//~i', $custom)) ? $custom : '/' . $custom;
		}
	}
	return array(
		'page' => (string)($GLOBALS['page_filename'] ?? 'index'),
		'script' => (string)($_SERVER['SCRIPT_NAME'] ?? ''),
		'get' => $_GET,
		'status' => (int)http_response_code(),
		'page_title' => (string)($GLOBALS['page_title'] ?? ''),
		'profile' => $profile,
		'lang' => chaos_seo_lang(),
		'site' => $site,
	);
}

/** True for a request whose output may be an HTML page (the machine endpoints never are). */
function chaos_seo_wanted(array $server): bool {
	$script = strtolower(basename((string)($server['SCRIPT_FILENAME'] ?? '')));
	return !in_array($script, array('chaos_client_api.php', 'chaos_pay_webhook.php', 'chaos_outfit.php', 'chaos_launcher_feed.php'), true);
}

/** The output buffer callback (plugin.php): the page with its head rewritten, or the output as it was. */
function chaos_seo_output(string $buffer): string {
	try {
		if (stripos($buffer, '<head') === false || stripos($buffer, '</head>') === false) {
			return $buffer;
		}
		foreach (headers_list() as $header) {
			if (stripos($header, 'content-type:') === 0 && stripos($header, 'text/html') === false) {
				return $buffer;
			}
		}
		$ctx = chaos_seo_context();
		return chaos_seo_rewrite($buffer, chaos_seo_page($ctx), $ctx['site']);
	} catch (Throwable $e) {
		error_log('[chaos seo] ' . $e->getMessage());
		return $buffer;
	}
}
