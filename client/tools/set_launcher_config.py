#!/usr/bin/env python3
"""Write launcher.json for the game launcher (O314, launcher/README.md) from an assembled client's init.lua.

  python3 -I client/tools/set_launcher_config.py GAME_DIR [--game Chaos.exe] [--feed URL | --no-feed] [--embed FILE]
  python3 -I client/tools/set_launcher_config.py --embed FILE --manifest URL --public-key HEX [--feed URL | --no-feed]

Reads Services.update (manifest, publicKey, baseline) of GAME_DIR/init.lua, so the launcher and the in-game updater
always use the same manifest, the same Ed25519 public key and the same baseline, and writes GAME_DIR/launcher.json.
It also writes "feed", the website's launcher feed (news and changelog, website/README.md "Launcher feed"): by default
the same site as the manifest, https://<site>/chaos_launcher_feed.php. --feed URL sets another https address,
--no-feed writes an empty one (the launcher then hides the News and Changelog panels).
Run it after set_update_config.py and before the pack is built (the pack hides init.lua). Exit 2 and no file when the
updater is off in init.lua (no manifest or key): such a package needs no launcher.
"""
import argparse, json, os, re, sys

NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')


def field(block, name):
    m = re.search(r'\n\s*%s = ("([^"\n]*)"|(\d+))' % re.escape(name), '\n' + block)
    if not m:
        return ''
    return m.group(2) if m.group(2) is not None else m.group(3)


def read_update(init_text):
    block = re.search(r'\n  update = \{\n(.*?)\n  \}', init_text, re.S)
    if not block:
        sys.exit('init.lua has no Services.update block (is base patch 0031 applied?)')
    b = block.group(1)
    return field(b, 'manifest'), field(b, 'publicKey'), field(b, 'baseline')


FEED_NAME = 'chaos_launcher_feed.php'
FEED_URL = re.compile(r'https://[A-Za-z0-9.-]+(:\d+)?/[A-Za-z0-9._~/-]*(\?[A-Za-z0-9._~=&%-]*)?')


def default_feed(manifest):
    """https://site/updates/live/manifest.json -> https://site/chaos_launcher_feed.php"""
    origin = re.match(r'https://[A-Za-z0-9.-]+(:\d+)?', manifest).group(0)
    return origin + '/' + FEED_NAME


LINK_KEYS = ('discord', 'site', 'wiki', 'signup')


def make_config(manifest, public_key, baseline, game='Chaos.exe', feed=None, links=None):
    if not re.fullmatch(r'https://[A-Za-z0-9.-]+(:\d+)?/[A-Za-z0-9._~/-]*manifest\.json', manifest):
        sys.exit('manifest: an https:// URL ending in manifest.json')
    if not re.fullmatch(r'[0-9a-f]{64}', public_key):
        sys.exit('publicKey: 64 lowercase hex digits')
    if not NAME.match(game):
        sys.exit('--game: a plain file name')
    cfg = {'manifest': manifest, 'public_key': public_key, 'game': game}
    if baseline != '':
        cfg['baseline'] = int(baseline)
    feed = default_feed(manifest) if feed is None else feed
    if feed != '' and not FEED_URL.fullmatch(feed):
        sys.exit('--feed: an https:// URL without spaces')
    cfg['feed'] = feed
    # the link buttons of the window: a key left out derives from the site; '' hides the button (O552)
    for k, v in sorted((links or {}).items()):
        if k not in LINK_KEYS or (v != '' and not FEED_URL.fullmatch(v)):
            sys.exit('--%s: an https:// URL without spaces (or empty to hide the button)' % k)
        cfg.setdefault('links', {})[k] = v
    return json.dumps(cfg, indent=1, sort_keys=True) + '\n'


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('game_dir', nargs='?')
    ap.add_argument('--game', default='Chaos.exe')
    g = ap.add_mutually_exclusive_group()
    g.add_argument('--feed', help='launcher feed URL (default: chaos_launcher_feed.php on the manifest\'s site)')
    g.add_argument('--no-feed', action='store_true', help='no News and Changelog panels')
    for k in LINK_KEYS:
        ap.add_argument('--' + k, help='link of the %s button of the launcher window (empty hides it)' % k)
    ap.add_argument('--embed', help='also write the same text to FILE (launcher/embedded.json), which build.rs compiles into the '
                                    'launcher so it can install itself from anywhere (O552); never committed')
    ap.add_argument('--manifest', help='without GAME_DIR: the manifest address (the workflow input update_manifest)')
    ap.add_argument('--public-key', help='without GAME_DIR: the update public key (the workflow input update_public_key)')
    a = ap.parse_args(argv)
    if a.game_dir is None:
        if not (a.embed and a.manifest and a.public_key):
            ap.error('without GAME_DIR the tool needs --embed FILE, --manifest URL and --public-key HEX')
        text = make_config(a.manifest, a.public_key, '', a.game, '' if a.no_feed else a.feed,
                           {k: getattr(a, k) for k in LINK_KEYS if getattr(a, k) is not None})
        with open(a.embed, 'w', encoding='utf-8') as f:
            f.write(text)
        print(f'{a.embed}: manifest {a.manifest}, key {a.public_key[:16]}... (built into the launcher)')
        return 0
    with open(os.path.join(a.game_dir, 'init.lua'), encoding='utf-8') as f:
        manifest, key, baseline = read_update(f.read())
    if not manifest or not key:
        print('updater is off in init.lua (no manifest or publicKey): no launcher.json', file=sys.stderr)
        return 2
    links = {k: getattr(a, k) for k in LINK_KEYS if getattr(a, k) is not None}
    text = make_config(manifest, key, baseline, a.game, '' if a.no_feed else a.feed, links)
    with open(os.path.join(a.game_dir, 'launcher.json'), 'w', encoding='utf-8') as f:
        f.write(text)
    if a.embed:
        with open(a.embed, 'w', encoding='utf-8') as f:
            f.write(text)
    print(f'{a.game_dir}/launcher.json: manifest {manifest}, key {key[:16]}...'
          + (f', baseline {baseline}' if baseline != '' else '')
          + (f', feed {json.loads(text)["feed"] or "off"}'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
