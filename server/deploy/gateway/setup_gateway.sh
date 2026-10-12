#!/bin/bash
# Set up (or update) a Cinders of Chaos gateway: a small DDoS-protected VPS that forwards the game ports to the real
# server with a PROXY protocol header (docs/LAUNCH.md "Gateways and DDoS"). Debian 11+ / Ubuntu 22.04+, run as root.
#
# usage: sudo ./setup_gateway.sh BACKEND_IP [--admin-ips LIST|any] [--ssh-port N] [--login-port N] [--game-port N]
#                                [--services-port N] [--maxconn N] [--dry-run]
#
#   BACKEND_IP     the real game server's IPv4 address (never published; only the gateways know it)
#   --admin-ips    addresses (a.b.c.d or a.b.c.d/nn, comma separated) allowed to SSH in; "any" keeps SSH open to
#                  everyone (rate limited). Default: any, so a first run cannot lock you out. When you run this over
#                  SSH with a list that leaves out your own address, it stops (pass --force to do it anyway).
#   --ssh-port     22; --login-port 7171; --game-port 7172 (the same ports as the server's config.lua: the login
#                  server tells the client which game port to use, and the client uses it on the gateway)
#   --services-port the login-screen services (clientservices.py, HTTP, 8090), forwarded as well so that the client's
#                  init.lua names the gateways only; 0 = not forwarded (the client then needs another address for it)
#   --maxconn      HAProxy's connection limit, 8000 (about 32 KB each)
#   --dry-run      print what would be written and check it, change nothing
#
# Idempotent: a second run with the same options changes nothing (files are rewritten only when different; HAProxy is
# reloaded, not restarted, so players stay connected). What it does:
#   1. installs haproxy and nftables (apt) when missing;
#   2. /etc/haproxy/haproxy.cfg from haproxy.cfg.template (the first original is kept as haproxy.cfg.chaos-orig),
#      checked with haproxy -c before it is used;
#   3. /etc/nftables.d/chaos-gateway.nft from gateway.nft.template, checked with nft -c, loaded, included from
#      /etc/nftables.conf and nftables.service enabled (survives a reboot);
#   4. /etc/sysctl.d/90-chaos-gateway.conf: SYN cookies, larger SYN and accept backlogs, more conntrack entries;
#   5. if ufw is active, it also allows the two game ports (both firewalls must let a packet in).
# Per source limits (edit the values below or the templates):
#   kernel: NEW_RATE new connections/s (burst NEW_BURST) and CONN_MAX open connections per IP on the game ports;
#   HAProxy: LOGIN_CUR / GAME_CUR open and LOGIN_RATE / GAME_RATE new connections per 10 s per IP and port, and a
#   silent drop above DROP_RATE per 10 s.
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true  # bash 5.2: "&" in a replacement stays "&"

NEW_RATE=10
NEW_BURST=20
CONN_MAX=24
LOGIN_CUR=8
LOGIN_RATE=20
GAME_CUR=10
GAME_RATE=15
DROP_RATE=60

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HAPROXY_TEMPLATE=$HERE/haproxy.cfg.template
NFT_TEMPLATE=$HERE/gateway.nft.template
HAPROXY_CFG=/etc/haproxy/haproxy.cfg
NFT_FILE=/etc/nftables.d/chaos-gateway.nft
NFT_MAIN=/etc/nftables.conf
SYSCTL_FILE=/etc/sysctl.d/90-chaos-gateway.conf

die() { echo "setup_gateway: $*" >&2; exit 1; }
say() { echo "setup_gateway: $*"; }

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

BACKEND=""
ADMIN=any
SSH_PORT=22
LOGIN_PORT=7171
GAME_PORT=7172
SERVICES_PORT=8090
MAXCONN=8000
DRY=0
FORCE=0
while [ $# -gt 0 ]; do
	case $1 in
		--admin-ips) ADMIN=${2:?--admin-ips needs a value}; shift ;;
		--ssh-port) SSH_PORT=${2:?}; shift ;;
		--login-port) LOGIN_PORT=${2:?}; shift ;;
		--game-port) GAME_PORT=${2:?}; shift ;;
		--services-port) SERVICES_PORT=${2:?}; shift ;;
		--maxconn) MAXCONN=${2:?}; shift ;;
		--dry-run) DRY=1 ;;
		--force) FORCE=1 ;;
		-h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
		-*) die "unknown option $1" ;;
		*) [ -z "$BACKEND" ] || die "one backend address only"; BACKEND=$1 ;;
	esac
	shift
done

[ -n "$BACKEND" ] || die "usage: setup_gateway.sh BACKEND_IP [--admin-ips LIST|any] [--dry-run] (see the top of this file)"
valid_ipv4 "$BACKEND" || die "BACKEND_IP must be an IPv4 address: $BACKEND"
for p in "$SSH_PORT" "$LOGIN_PORT" "$GAME_PORT"; do valid_port "$p" || die "bad port: $p"; done
[ "$SERVICES_PORT" = 0 ] || valid_port "$SERVICES_PORT" || die "bad --services-port: $SERVICES_PORT"
[[ $MAXCONN =~ ^[0-9]+$ ]] && [ "$MAXCONN" -ge 100 ] || die "--maxconn must be a number >= 100"
[ "$LOGIN_PORT" != "$GAME_PORT" ] || die "--login-port and --game-port must differ"
[ -f "$HAPROXY_TEMPLATE" ] && [ -f "$NFT_TEMPLATE" ] || die "templates not found next to this script ($HERE)"

ADMIN_LIST=""
if [ "$ADMIN" != any ]; then
	IFS=', ' read -r -a items <<< "$ADMIN"
	for a in "${items[@]}"; do
		[ -n "$a" ] || continue
		valid_range "$a" || die "--admin-ips: not an IPv4 address or range: $a"
		ADMIN_LIST+="${ADMIN_LIST:+, }$a"
	done
	[ -n "$ADMIN_LIST" ] || die "--admin-ips is empty (use any to keep SSH open)"
	# do not lock out the session running this
	if [ -n "${SSH_CLIENT:-}" ] && [ "$FORCE" = 0 ]; then
		me=${SSH_CLIENT%% *}
		if valid_ipv4 "$me" && ! python3 -I -c 'import ipaddress,sys; me=ipaddress.ip_address(sys.argv[1]); sys.exit(0 if any(me in ipaddress.ip_network(n.strip(), strict=False) for n in sys.argv[2].split(",")) else 1)' "$me" "$ADMIN_LIST"; then
			die "your SSH address $me is not in --admin-ips ($ADMIN_LIST): you would lock yourself out (--force to do it anyway)"
		fi
	fi
	SSH_RULE="tcp dport $SSH_PORT ip saddr { $ADMIN_LIST } ct state new accept"
	SSH_DOC="port $SSH_PORT from $ADMIN_LIST only"
else
	SSH_RULE="tcp dport $SSH_PORT ct state new limit rate 20/minute burst 10 packets accept"
	SSH_DOC="port $SSH_PORT from anywhere, at most 20 new connections a minute"
fi

if [ "$SERVICES_PORT" = 0 ]; then
	SERVICES_RULES="# login-screen services: not forwarded (--services-port 0)"
	SERVICES_DOC="not forwarded"
else
	SERVICES_RULES="tcp dport $SERVICES_PORT ct state new update @svc_rate4 { ip saddr limit rate over $NEW_RATE/second burst $NEW_BURST packets } counter drop"
	SERVICES_RULES+=$'\n\t\t'"tcp dport $SERVICES_PORT ct state new accept"
	SERVICES_DOC="$SERVICES_PORT"
fi

render() { # template -> stdout
	local text
	text=$(<"$1")
	if [ "$SERVICES_PORT" = 0 ]; then # drop the services block of the HAProxy template
		text=$(printf '%s\n' "$text" | sed '/^# BEGIN services$/,/^# END services$/d')
	fi
	text=${text//@SERVICES_RULES@/$SERVICES_RULES}
	text=${text//@SERVICES_PORT@/$SERVICES_PORT}
	text=${text//@BACKEND@/$BACKEND}
	text=${text//@LOGIN_PORT@/$LOGIN_PORT}
	text=${text//@GAME_PORT@/$GAME_PORT}
	text=${text//@SSH_PORT@/$SSH_PORT}
	text=${text//@SSH_RULE_DOC@/$SSH_DOC}
	text=${text//@SSH_RULE@/$SSH_RULE}
	text=${text//@MAXCONN@/$MAXCONN}
	text=${text//@LOGIN_CUR@/$LOGIN_CUR}
	text=${text//@LOGIN_RATE@/$LOGIN_RATE}
	text=${text//@GAME_CUR@/$GAME_CUR}
	text=${text//@GAME_RATE@/$GAME_RATE}
	text=${text//@DROP_RATE@/$DROP_RATE}
	text=${text//@NEW_RATE@/$NEW_RATE}
	text=${text//@NEW_BURST@/$NEW_BURST}
	text=${text//@CONN_MAX@/$CONN_MAX}
	printf '%s\n' "$text"
}

SYSCTL="# Cinders of Chaos gateway (server/deploy/gateway/setup_gateway.sh)
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_synack_retries = 3
net.core.somaxconn = 4096
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.netfilter.nf_conntrack_max = 262144"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
render "$HAPROXY_TEMPLATE" > "$TMP/haproxy.cfg"
render "$NFT_TEMPLATE" > "$TMP/chaos-gateway.nft"
printf '%s\n' "$SYSCTL" > "$TMP/sysctl.conf"
if grep -q '@[A-Z_]*@' "$TMP/haproxy.cfg" "$TMP/chaos-gateway.nft"; then
	die "a placeholder was left unreplaced: $(grep -ho '@[A-Z_]*@' "$TMP/haproxy.cfg" "$TMP/chaos-gateway.nft" | sort -u | tr '\n' ' ')"
fi

if [ "$DRY" = 1 ]; then
	say "dry run: backend $BACKEND, login $LOGIN_PORT, game $GAME_PORT, services $SERVICES_DOC, SSH: $SSH_DOC"
	if command -v haproxy >/dev/null; then
		haproxy -c -q -f "$TMP/haproxy.cfg" && say "haproxy.cfg: valid" || say "haproxy.cfg: haproxy -c FAILED"
	else
		say "haproxy not installed here: config not checked"
	fi
	if command -v nft >/dev/null && [ "$(id -u)" = 0 ]; then
		nft -c -f "$TMP/chaos-gateway.nft" && say "nft rules: valid" || say "nft rules: nft -c FAILED"
	else
		say "nft not available (or not root): rules not checked"
	fi
	echo "----- $HAPROXY_CFG"; cat "$TMP/haproxy.cfg"
	echo "----- $NFT_FILE"; cat "$TMP/chaos-gateway.nft"
	echo "----- $SYSCTL_FILE"; cat "$TMP/sysctl.conf"
	exit 0
fi

[ "$(id -u)" = 0 ] || die "run as root (sudo)"

# 1. packages
missing=()
command -v haproxy >/dev/null || missing+=(haproxy)
command -v nft >/dev/null || missing+=(nftables)
if [ ${#missing[@]} -gt 0 ]; then
	say "installing ${missing[*]}"
	DEBIAN_FRONTEND=noninteractive apt-get update -q
	DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${missing[@]}"
fi

install_if_changed() { # src dest mode -> 0 when written, 1 when already the same
	if [ -f "$2" ] && cmp -s "$1" "$2"; then
		return 1
	fi
	install -D -m "$3" "$1" "$2"
}

# 2. HAProxy
haproxy -c -q -f "$TMP/haproxy.cfg" || die "the rendered haproxy.cfg does not pass haproxy -c; nothing changed"
if [ -f "$HAPROXY_CFG" ] && [ ! -f "$HAPROXY_CFG.chaos-orig" ] && ! grep -q 'Cinders of Chaos gateway' "$HAPROXY_CFG"; then
	cp -p "$HAPROXY_CFG" "$HAPROXY_CFG.chaos-orig"
fi
if install_if_changed "$TMP/haproxy.cfg" "$HAPROXY_CFG" 0644; then
	say "wrote $HAPROXY_CFG"
	systemctl enable haproxy >/dev/null 2>&1 || true
	if systemctl is-active --quiet haproxy; then systemctl reload haproxy; else systemctl restart haproxy; fi
else
	say "$HAPROXY_CFG already up to date"
	systemctl is-active --quiet haproxy || { systemctl enable haproxy >/dev/null 2>&1 || true; systemctl restart haproxy; }
fi

# 3. nftables
nft -c -f "$TMP/chaos-gateway.nft" || die "the rendered nft rules do not pass nft -c; nothing changed"
if install_if_changed "$TMP/chaos-gateway.nft" "$NFT_FILE" 0644; then
	say "wrote $NFT_FILE"
else
	say "$NFT_FILE already up to date"
fi
nft -f "$NFT_FILE"
if [ ! -f "$NFT_MAIN" ]; then
	printf '#!/usr/sbin/nft -f\n' > "$NFT_MAIN"
fi
if ! grep -qF "include \"$NFT_FILE\"" "$NFT_MAIN"; then
	printf '\n# Cinders of Chaos gateway (setup_gateway.sh)\ninclude "%s"\n' "$NFT_FILE" >> "$NFT_MAIN"
	say "added the include to $NFT_MAIN"
fi
systemctl enable nftables >/dev/null 2>&1 || true

# 4. kernel settings
if install_if_changed "$TMP/sysctl.conf" "$SYSCTL_FILE" 0644; then
	say "wrote $SYSCTL_FILE"
fi
modprobe nf_conntrack 2>/dev/null || true
sysctl -q -p "$SYSCTL_FILE" || say "some kernel settings could not be applied (a container VPS may not allow them)"

# 5. ufw, when it is the active firewall as well
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then
	ufw allow "$LOGIN_PORT/tcp" >/dev/null
	ufw allow "$GAME_PORT/tcp" >/dev/null
	[ "$SERVICES_PORT" = 0 ] || ufw allow "$SERVICES_PORT/tcp" >/dev/null
	say "ufw is active: allowed the forwarded ports there too"
fi

say "done: $LOGIN_PORT and $GAME_PORT forward to $BACKEND with PROXY v2, services: $SERVICES_DOC; SSH: $SSH_DOC"
say "check: systemctl status haproxy; tail -f /var/log/haproxy.log (a backend that is down shows as DOWN)"
say "next: add this gateway's public IP to the server's proxyProtocolTrusted and to setup_backend_firewall.sh"
