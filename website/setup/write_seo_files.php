<?php
/**
 * Prints robots.txt or sitemap.xml for the site (website/README.md "SEO and social previews"). Run by
 * website/install_site.sh after config.local.php, with CHAOS_SITE_URL in the environment:
 *
 *   php website/setup/write_seo_files.php robots  > <site>/robots.txt
 *   php website/setup/write_seo_files.php sitemap > <site>/sitemap.xml
 *
 * robots.txt allows the public pages, keeps crawlers off the account, login, staff and machine endpoints and the
 * internal folders, and names the sitemap. The sitemap lists the public pages in their clean form (no .php), the
 * plugin pages, every wiki guide and reference tab in both languages and the legal texts, with a priority and no
 * lastmod (the install date would be a lie). Character profiles and search results are left to the links. No
 * database: the lists come from the plugin's code and data.
 */
if (PHP_SAPI !== 'cli') {
	exit(1);
}

$what = (string)($argv[1] ?? '');
$siteUrl = rtrim(trim((string)getenv('CHAOS_SITE_URL')), '/');
if ($siteUrl === '' || preg_match('#^https?://[A-Za-z0-9.-]+(:[0-9]+)?$#', $siteUrl) !== 1) {
	fwrite(STDERR, "CHAOS_SITE_URL must be the site's public address, https://host (no path).\n");
	exit(1);
}
$overlay = dirname(__DIR__) . '/overlay';

/** The public pages of the sitemap: path (from the root, clean form) => priority. */
function chaos_seo_sitemap_pages(string $overlay): array {
	$pages = array(
		'/' => '1.0', '/downloads' => '0.9', '/highscores' => '0.8', '/onlinelist' => '0.6',
		'/guilds' => '0.6', '/serverinfo' => '0.6', '/changelog' => '0.4', '/deaths' => '0.4', '/powergamers' => '0.4',
		'/houses' => '0.3', '/team' => '0.3', '/achievements' => '0.3', '/page?p=rules' => '0.5',
	);
	foreach (array('patchnotes' => '0.7', 'leaderboards' => '0.7', 'seasons' => '0.6', 'community' => '0.5', 'chronicle' => '0.5',
		'memorial' => '0.4', 'guildwars' => '0.4', 'mentors' => '0.4', 'bazaar' => '0.5', 'creator' => '0.4', 'coins' => '0.5', 'fairplay' => '0.6', 'calendar' => '0.6', 'creators' => '0.5',
		'credits' => '0.2', 'wiki' => '0.9') as $p => $prio) {
		$pages['/page?plugin=chaos&p=' . $p] = $prio;
	}
	$pages['/page?plugin=chaos&p=wiki&l=en'] = '0.8';
	// the wiki guides and reference tabs, Portuguese and English
	$wikiLib = $overlay . '/plugins/chaos/wiki_lib.php';
	if (is_file($wikiLib)) {
		if (!function_exists('chaos_h')) {
			require_once $overlay . '/plugins/chaos/lib.php';
		}
		require_once $wikiLib;
		$topics = array();
		foreach (array_keys(chaos_wiki_guides()) as $slug) {
			$topics[] = 'guide:' . $slug;
		}
		foreach (chaos_wiki_data()['tabs'] as $tab) {
			if (isset($tab['id'])) {
				$topics[] = 'tab:' . $tab['id'];
			}
		}
		foreach ($topics as $topic) {
			$pages['/page?plugin=chaos&p=wiki&t=' . rawurlencode($topic)] = '0.6';
			$pages['/page?plugin=chaos&p=wiki&t=' . rawurlencode($topic) . '&l=en'] = '0.5';
		}
	}
	foreach (array('terms', 'privacy', 'donations') as $doc) {
		$pages['/page?plugin=chaos&p=legal&doc=' . $doc] = '0.2';
		$pages['/page?plugin=chaos&p=legal&doc=' . $doc . '&l=en'] = '0.2';
	}
	return $pages;
}

if ($what === 'robots') {
	echo "# Cinders of Chaos (written by website/install_site.sh from website/setup/write_seo_files.php)\n"
		. "User-agent: *\n"
		. "Allow: /\n"
		// the account, login and staff pages, the machine endpoints and the internal folders
		. "Disallow: /login\n"
		. "Disallow: /logout\n"
		. "Disallow: /register\n"
		. "Disallow: /recovery\n"
		. "Disallow: /myaccount\n"
		. "Disallow: /createcharacter\n"
		. "Disallow: /changepassword\n"
		. "Disallow: /settings\n"
		. "Disallow: /twofa\n"
		. "Disallow: /protected\n"
		. "Disallow: /payment\n"
		. "Disallow: /buypoints\n"
		. "Disallow: /shop\n"
		. "Disallow: /admin/\n"
		. "Disallow: /api/\n"
		. "Disallow: /engine/\n"
		. "Disallow: /install/\n"
		. "Disallow: /chaos_client_api.php\n"
		. "Disallow: /chaos_pay_webhook.php\n"
		. "Disallow: /chaos_outfit.php\n"
		. "Disallow: /page?plugin=chaos&p=accept\n"
		. "Disallow: /page?plugin=chaos&p=reports\n"
		. "Disallow: /page?plugin=chaos&p=botreview\n"
		. "Disallow: /page?plugin=chaos&p=telemetry\n"
		. "Disallow: /page?plugin=chaos&p=notused\n"
		. "Disallow: /*&q=\n"
		. "Disallow: /*?q=\n"
		. "Sitemap: " . $siteUrl . "/sitemap.xml\n";
	exit(0);
}
if ($what === 'sitemap') {
	echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
		. "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n";
	foreach (chaos_seo_sitemap_pages($overlay) as $path => $prio) {
		echo "  <url><loc>" . htmlspecialchars($siteUrl . $path, ENT_QUOTES | ENT_XML1, 'UTF-8') . "</loc>"
			. "<priority>" . $prio . "</priority></url>\n";
	}
	echo "</urlset>\n";
	exit(0);
}
fwrite(STDERR, "usage: write_seo_files.php robots|sitemap\n");
exit(2);
