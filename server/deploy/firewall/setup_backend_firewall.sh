#!/bin/bash
# Lock the real Cinders of Chaos game server behind its gateways (docs/LAUNCH.md "Gateways and DDoS"): the game ports
# take connections from the gateways only, with per-IP limits as a second layer. Debian / Ubuntu with nftables; root.
#
# usage: sudo ./setup_backend_firewall.sh GATEWAY_IPS [--admin-ips LIST|any] [--extra-ips LIST]
#                                         [--services any|off|LIST] [--web-ports LIST] [--ssh-port N]
#                                         [--login-port N] [--game-port N] [--dry-run] [--force]
#
#   GATEWAY_IPS   the gateways' public IPv4 addresses, comma separated (a.b.c.d or a.b.c.d/nn): the same list as
#                 proxyProtocolTrusted in config.lua (prod_config.py --proxy-trusted)
#   --admin-ips   who may SSH in (a list, or "any": open to everyone, rate limited). Required: there is no default,
#                 because a wrong guess locks you out. Run over SSH with a list that leaves out your own address, it
#                 stops (--force to do it anyway)
#   --extra-ips   other machines that may reach the game ports directly, without a PROXY header: a website or status
#                 checker on another host (with proxyProtocolRequired = true the engine refuses those anyway: point
#                 them at a gateway instead, or keep proxyProtocolRequired = false). Default: none
#   --services    the login-screen services port 8090 (clientservices.py): any (default; open, 20 new connections/s
#                 per IP), off (closed: the client reaches it some other way), or a list of addresses (a reverse proxy
#                 or CDN in front, recommended)
#   --web-ports   ports of a website on this same machine, e.g. 80,443 (open to everyone, rate limited per IP).
#                 Default: none (the website runs on its own host)
#   --ssh-port 22, --login-port 7171, --game-port 7172; --dry-run prints and checks, changes nothing
#
# Idempotent: the rules live in their own table (inet chaos_backend) in /etc/nftables.d/chaos-backend.nft, which a load
# replaces as a whole; /etc/nftables.conf includes it once; nftables.service is enabled. A second run with the same
# options changes nothing. 127.0.0.1 is never filtered (the watchdog, the health check, MariaDB).
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true  # bash 5.2: "&" in a replacement stays "&"

GATEWAY_RATE=300
GATEWAY_BURST=600
EXTRA_RATE=5
EXTRA_BURST=20
WEB_RATE=20
WEB_BURST=60
SERVICES_PORT=8090

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMPLATE=$HERE/backend.nft.template
NFT_FILE=/etc/nftables.d/chaos-backend.nft
NFT_MAIN=/etc/nftables.conf

die() { echo "setup_backend_firewall: $*" >&2; exit 1; }
say() { echo "setup_backend_firewall: $*"; }

valid_ipv4() {
	local ip=$1 IFS=.
	[[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
	local part
	for part in $ip; do
		[ "$part" -le 255 ] || return 1
	done
}

valid_range() {
	local addr=${1%/*}
	if [[ $1 == */* ]]; then
		local bits=${1#*/}
		[[ $bits =~ ^[0-9]{1,2}$ ]] && [ "$bits" -le 32 ] || return 1
	fi
	valid_ipv4 "$addr"
}

valid_port() { [[ $1 =~ ^[0-9]{1,5}$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

# "a, b,c" -> "a, b, c" after checking each entry; $2 names the option for the error
address_list() {
	local out="" a
	local -a items
	IFS=', ' read -r -a items <<< "$1"
	for a in "${items[@]}"; do
		[ -n "$a" ] || continue
		valid_range "$a" || die "$2: not an IPv4 address or a.b.c.d/nn range: $a"
		out+="${out:+, }$a"
	done
	printf '%s' "$out"
}

port_list() {
	local out="" p
	local -a items
	IFS=', ' read -r -a items <<< "$1"
	for p in "${items[@]}"; do
		[ -n "$p" ] || continue
		valid_port "$p" || die "$2: bad port $p"
		out+="${out:+, }$p"
	done
	printf '%s' "$out"
}

GATEWAYS_ARG=""
ADMIN=""
EXTRA=""
SERVICES=any
WEB_PORTS=""
SSH_PORT=22
LOGIN_PORT=7171
GAME_PORT=7172
DRY=0
FORCE=0
while [ $# -gt 0 ]; do
	case $1 in
		--admin-ips) ADMIN=${2:?--admin-ips needs a value}; shift ;;
		--extra-ips) EXTRA=${2?--extra-ips needs a value}; shift ;;
		--services) SERVICES=${2:?--services needs a value}; shift ;;
		--web-ports) WEB_PORTS=${2?--web-ports needs a value}; shift ;;
		--ssh-port) SSH_PORT=${2:?}; shift ;;
		--login-port) LOGIN_PORT=${2:?}; shift ;;
		--game-port) GAME_PORT=${2:?}; shift ;;
		--dry-run) DRY=1 ;;
		--force) FORCE=1 ;;
		-h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
		-*) die "unknown option $1" ;;
		*) [ -z "$GATEWAYS_ARG" ] || die "give the gateways as one comma separated list"; GATEWAYS_ARG=$1 ;;
	esac
	shift
done

[ -n "$GATEWAYS_ARG" ] || die "usage: setup_backend_firewall.sh GATEWAY_IPS --admin-ips LIST|any [--dry-run] (see the top of this file)"
[ -n "$ADMIN" ] || die "--admin-ips is required (a list of addresses, or any)"
for p in "$SSH_PORT" "$LOGIN_PORT" "$GAME_PORT"; do valid_port "$p" || die "bad port: $p"; done
[ -f "$TEMPLATE" ] || die "template not found: $TEMPLATE"

GATEWAYS=$(address_list "$GATEWAYS_ARG" GATEWAY_IPS)
[ -n "$GATEWAYS" ] || die "no gateway address"
EXTRA_LIST=$(address_list "$EXTRA" --extra-ips)
WEB_LIST=$(port_list "$WEB_PORTS" --web-ports)

if [ "$ADMIN" = any ]; then
	SSH_RULE="tcp dport $SSH_PORT ct state new limit rate 20/minute burst 10 packets accept"
else
	ADMIN_LIST=$(address_list "$ADMIN" --admin-ips)
	[ -n "$ADMIN_LIST" ] || die "--admin-ips is empty (use any to keep SSH open)"
	if [ -n "${SSH_CLIENT:-}" ] && [ "$FORCE" = 0 ]; then
		me=${SSH_CLIENT%% *}
		if valid_ipv4 "$me" && ! python3 -I -c 'import ipaddress,sys; me=ipaddress.ip_address(sys.argv[1]); sys.exit(0 if any(me in ipaddress.ip_network(n.strip(), strict=False) for n in sys.argv[2].split(",")) else 1)' "$me" "$ADMIN_LIST"; then
			die "your SSH address $me is not in --admin-ips ($ADMIN_LIST): you would lock yourself out (--force to do it anyway)"
		fi
	fi
	SSH_RULE="tcp dport $SSH_PORT ip saddr { $ADMIN_LIST } ct state new accept"
fi

NL=$'\n\t\t'
WEB_RULES="# login-screen services ($SERVICES_PORT) and website ports"
case $SERVICES in
	any)
		WEB_RULES+="${NL}tcp dport $SERVICES_PORT ct state new update @svc_rate4 { ip saddr limit rate over $WEB_RATE/second burst $WEB_BURST packets } counter drop"
		WEB_RULES+="${NL}tcp dport $SERVICES_PORT ct state new accept" ;;
	off)
		WEB_RULES+="${NL}# $SERVICES_PORT closed (--services off)" ;;
	*)
		SERVICES_LIST=$(address_list "$SERVICES" --services)
		[ -n "$SERVICES_LIST" ] || die "--services: any, off or a list of addresses"
		WEB_RULES+="${NL}tcp dport $SERVICES_PORT ip saddr { $SERVICES_LIST } ct state new accept" ;;
esac
if [ -n "$WEB_LIST" ]; then
	WEB_RULES+="${NL}tcp dport { $WEB_LIST } ct state new update @web_rate4 { ip saddr limit rate over $WEB_RATE/second burst $WEB_BURST packets } counter drop"
	WEB_RULES+="${NL}tcp dport { $WEB_LIST } ct state new accept"
fi

render() {
	local text
	text=$(<"$TEMPLATE")
	local gw="elements = { $GATEWAYS }" extra="# none (--extra-ips)"
	[ -z "$EXTRA_LIST" ] || extra="elements = { $EXTRA_LIST }"
	text=${text//@GATEWAY_ELEMENTS@/$gw}
	text=${text//@EXTRA_ELEMENTS@/$extra}
	text=${text//@SSH_RULE@/$SSH_RULE}
	text=${text//@GAME_PORTS@/$LOGIN_PORT, $GAME_PORT}
	text=${text//@GATEWAY_RATE@/$GATEWAY_RATE}
	text=${text//@GATEWAY_BURST@/$GATEWAY_BURST}
	text=${text//@EXTRA_RATE@/$EXTRA_RATE}
	text=${text//@EXTRA_BURST@/$EXTRA_BURST}
	text=${text//@WEB_RULES@/$WEB_RULES}
	printf '%s\n' "$text"
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
render > "$TMP/chaos-backend.nft"
if grep -q '@[A-Z_]*@' "$TMP/chaos-backend.nft"; then
	die "a placeholder was left unreplaced: $(grep -o '@[A-Z_]*@' "$TMP/chaos-backend.nft" | sort -u | tr '\n' ' ')"
fi

if [ "$DRY" = 1 ]; then
	say "dry run: game ports $LOGIN_PORT, $GAME_PORT from $GATEWAYS${EXTRA_LIST:+ and $EXTRA_LIST}"
	if command -v nft >/dev/null && [ "$(id -u)" = 0 ]; then
		nft -c -f "$TMP/chaos-backend.nft" && say "nft rules: valid" || say "nft rules: nft -c FAILED"
	else
		say "nft not available (or not root): rules not checked"
	fi
	echo "----- $NFT_FILE"; cat "$TMP/chaos-backend.nft"
	exit 0
fi

[ "$(id -u)" = 0 ] || die "run as root (sudo)"
if ! command -v nft >/dev/null; then
	say "installing nftables"
	DEBIAN_FRONTEND=noninteractive apt-get update -q
	DEBIAN_FRONTEND=noninteractive apt-get install -y -q nftables
fi
nft -c -f "$TMP/chaos-backend.nft" || die "the rendered rules do not pass nft -c; nothing changed"
if [ -f "$NFT_FILE" ] && cmp -s "$TMP/chaos-backend.nft" "$NFT_FILE"; then
	say "$NFT_FILE already up to date"
else
	install -D -m 0644 "$TMP/chaos-backend.nft" "$NFT_FILE"
	say "wrote $NFT_FILE"
fi
nft -f "$NFT_FILE"
[ -f "$NFT_MAIN" ] || printf '#!/usr/sbin/nft -f\n' > "$NFT_MAIN"
if ! grep -qF "include \"$NFT_FILE\"" "$NFT_MAIN"; then
	printf '\n# Cinders of Chaos backend (setup_backend_firewall.sh)\ninclude "%s"\n' "$NFT_FILE" >> "$NFT_MAIN"
	say "added the include to $NFT_MAIN"
fi
systemctl enable nftables >/dev/null 2>&1 || true

if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then
	say "ufw is active too. A packet must pass both: keep ufw's allow rules for $LOGIN_PORT, $GAME_PORT, $SERVICES_PORT and SSH"
	say "(this table narrows them), or turn ufw off (sudo ufw disable) and let this table be the firewall."
fi
say "done: $LOGIN_PORT and $GAME_PORT only from $GATEWAYS${EXTRA_LIST:+ and $EXTRA_LIST}"
say "check from a machine that is not a gateway: nc -vz -w 3 <this server's IP> $GAME_PORT must time out"
