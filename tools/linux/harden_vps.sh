#!/usr/bin/env bash
# Harden the Cinders of Chaos VPS (Ubuntu 24.04: the game server package and the website on one machine).
# docs/SECURITY_CHECKLIST.md says when to run it. Run as root; idempotent (a second run changes nothing).
#
# usage: sudo tools/linux/harden_vps.sh --admin-user NAME [--lock-ssh [--key-login-tested]] [--server-dir DIR]
#                                       [--site-dir DIR] [--cloudflare] [--ssh-port N] [--dry-run]
#
#   --admin-user NAME   the account you log in with over SSH (it must be in the sudo group). Default: $SUDO_USER
#   --lock-ssh          turn off password and root logins over SSH. Done only when it cannot lock you out:
#                       NAME has a valid key in ~/.ssh/authorized_keys, is in the sudo group, and a key login of NAME
#                       is in the SSH log ("Accepted publickey for NAME"), or you pass --key-login-tested after
#                       logging in with the key yourself. Otherwise it says what is missing and leaves SSH as it is.
#   --server-dir DIR    the Linux server package folder (the one with chaos.env); default: searched under /home,
#                       /opt and /srv
#   --site-dir DIR      the website folder (config.local.php); default: searched under /var/www
#   --cloudflare        the website's @ / www records go through Cloudflare's proxy: Apache takes the visitor's address
#                       from CF-Connecting-IP (mod_remoteip, Cloudflare's published ranges only), and the fail2ban
#                       web jail stays off (it would ban Cloudflare's addresses, not the visitor's)
#   --ssh-port N        default: the port sshd uses (sshd -T), else 22
#   --dry-run           print every change and command, change nothing (no root needed)
#
# What it does:
#   1. packages: ufw, fail2ban (python3-systemd), unattended-upgrades (security updates every day, never a reboot)
#   2. sysctl network hardening (/etc/sysctl.d/90-chaos-hardening.conf)
#   3. ufw: deny incoming except SSH (rate limited), 80, 443, 7171, 7172; 3306, 3307 and 8090 stay closed (local)
#   4. fail2ban: sshd, and a web jail for floods of POSTs to the login, register and recovery pages
#   5. Apache: ServerTokens Prod, ServerSignature Off, TraceEnable Off, no X-Powered-By, the PHP pages' security
#      headers also on static files (only where PHP did not send them)
#   6. checks: MariaDB and the login-screen services listen on 127.0.0.1 only; chaos.env, site.env, payments.env,
#      the RSA key and backup passphrase files are mode 600; config.local.php is not world-readable (fixed with chmod,
#      owners are never changed); no first-start-account.txt left behind
#   7. SSH (--lock-ssh): /etc/ssh/sshd_config.d/10-chaos-hardening.conf, checked with sshd -t, then a reload (open
#      sessions stay)
# It never prints a password, key or the content of an env file. HARDEN_ROOT=DIR runs it against a copy of the file
# system in DIR (tools/linux/harden_vps_test.py).
set -euo pipefail

R=${HARDEN_ROOT:-}
DRY=0
ADMIN=${SUDO_USER:-}
LOCK_SSH=0
TESTED=0
SSH_PORT=
SERVER_DIR=
SITE_DIR=
CLOUDFLARE=0
OPEN_TCP="80 443 7171 7172"
LOCAL_ONLY="3306 3307 8090"
WARN=0
CHANGED=0
SSH_STATE="not asked (--lock-ssh)"

say() { printf 'harden_vps: %s\n' "$*"; }
warn() { WARN=$((WARN + 1)); printf 'harden_vps: WARNING: %s\n' "$*"; }
die() { printf 'harden_vps: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case $1 in
		--admin-user) ADMIN=${2:-}; shift 2 ;;
		--lock-ssh) LOCK_SSH=1; shift ;;
		--key-login-tested) TESTED=1; shift ;;
		--server-dir) SERVER_DIR=${2:-}; shift 2 ;;
		--site-dir) SITE_DIR=${2:-}; shift 2 ;;
		--cloudflare) CLOUDFLARE=1; shift ;;
		--ssh-port) SSH_PORT=${2:-}; shift 2 ;;
		--dry-run) DRY=1; shift ;;
		-h|--help) sed -n '2,38p' "$0"; exit 0 ;;
		*) die "unknown option $1 (--help)" ;;
	esac
done

if [ "$DRY" = 0 ] && [ -z "$R" ] && [ "$(id -u)" != 0 ]; then
	die "run it as root (sudo), or with --dry-run"
fi
[ -z "$ADMIN" ] || [[ $ADMIN =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "--admin-user: not a user name"
[ -z "$SSH_PORT" ] || { [[ $SSH_PORT =~ ^[0-9]{1,5}$ ]] && [ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ]; } \
	|| die "--ssh-port: 1..65535"

# run a command that changes the system (printed; not run in a dry run)
run() {
	if [ "$DRY" = 1 ]; then
		say "would run: $*"
	else
		say "run: $*"
		"$@"
	fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# write_file PATH MODE: the content comes on stdin; nothing happens when the file already has it
write_file() {
	local path=$R$1 mode=$2 tmp
	tmp=$(mktemp)
	cat > "$tmp"
	if [ -f "$path" ] && cmp -s "$tmp" "$path"; then
		say "unchanged: $1"
		rm -f "$tmp"
		return 1
	fi
	if [ "$DRY" = 1 ]; then
		say "would write $1 (mode $mode):"
		sed 's/^/    | /' "$tmp"
		rm -f "$tmp"
		return 0
	fi
	mkdir -p "$(dirname "$path")"
	chmod "$mode" "$tmp"
	mv "$tmp" "$path"
	CHANGED=$((CHANGED + 1))
	say "wrote $1"
	return 0
}

installed() { dpkg -s "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- 0. what is there
if [ -f "$R/etc/os-release" ] && ! grep -q '^ID=ubuntu' "$R/etc/os-release"; then
	warn "not Ubuntu: the package names and paths are Ubuntu 24.04's; check each step"
fi
if [ -z "$SSH_PORT" ]; then
	SSH_PORT=$( (sshd -T 2>/dev/null || true) | awk '$1 == "port" { print $2; exit }')
	SSH_PORT=${SSH_PORT:-22}
fi
say "SSH port $SSH_PORT; open to the internet: $SSH_PORT (rate limited) $OPEN_TCP; local only: $LOCAL_ONLY"

# ---------------------------------------------------------------- 1. packages
want=()
for p in ufw fail2ban python3-systemd unattended-upgrades; do
	installed "$p" || want+=("$p")
done
if [ ${#want[@]} -gt 0 ]; then
	run env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${want[@]}"
else
	say "packages already installed: ufw fail2ban python3-systemd unattended-upgrades"
fi

if write_file /etc/apt/apt.conf.d/20auto-upgrades 0644 <<'EOF'
// harden_vps.sh: package lists and security updates every day (unattended-upgrades)
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
then :; fi
if write_file /etc/apt/apt.conf.d/52chaos-unattended 0644 <<'EOF'
// harden_vps.sh: security updates only (the distribution default), never an automatic reboot: the game server
// restarts at the daily save; reboot by hand when /var/run/reboot-required exists (docs/SECURITY_CHECKLIST.md)
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
then :; fi

# ---------------------------------------------------------------- 2. sysctl
if write_file /etc/sysctl.d/90-chaos-hardening.conf 0644 <<'EOF'
# harden_vps.sh: network hardening (docs/SECURITY_CHECKLIST.md)
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.core.somaxconn = 4096
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF
then
	run sysctl -q -p /etc/sysctl.d/90-chaos-hardening.conf
fi

# ---------------------------------------------------------------- 3. firewall (ufw)
ufw_status=$( (ufw status 2>/dev/null || true) )
run ufw default deny incoming
run ufw default allow outgoing
run ufw limit "$SSH_PORT/tcp" comment "SSH (harden_vps.sh)"
for port in $OPEN_TCP; do
	run ufw allow "$port/tcp" comment "Cinders of Chaos (harden_vps.sh)"
done
for port in $LOCAL_ONLY; do
	if printf '%s\n' "$ufw_status" | grep -Eq "^$port(/tcp)?[[:space:]]+(ALLOW|LIMIT)"; then
		run ufw delete allow "$port/tcp"
		warn "port $port was open in ufw; it is local only (removed)"
	fi
done
if [ -f "$R/etc/nftables.d/chaos-backend.nft" ]; then
	say "the gateways' backend firewall (setup_backend_firewall.sh) is in place too: a packet must pass both"
fi
run ufw --force enable

# ---------------------------------------------------------------- 4. fail2ban
web_jail=0
if [ -d "$R/etc/apache2" ] && [ "$CLOUDFLARE" = 0 ]; then
	web_jail=1
fi
if write_file /etc/fail2ban/filter.d/chaos-site-forms.conf 0644 <<'EOF'
# harden_vps.sh: POSTs to the website's login, register and recovery pages (Apache combined log), with or without
# .php. The site limits failed logins itself (website/README.md "Passwords"); this stops floods before PHP.
[Definition]
failregex = ^<HOST> \S+ \S+ \[[^\]]+\] "POST /(?:index\.php/)?(?:login|register|recovery|createaccount)(?:\.php)?(?:[?/]\S*)? HTTP/[0-9.]+"
ignoreregex =
EOF
then :; fi
jail_conf() {
	cat <<EOF
# harden_vps.sh (docs/SECURITY_CHECKLIST.md). Unban: fail2ban-client set <jail> unbanip <address>
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
banaction = ufw

[sshd]
enabled = true
port = $SSH_PORT
backend = systemd
EOF
	if [ "$web_jail" = 1 ]; then
		cat <<'EOF'

[chaos-site-forms]
enabled = true
port = http,https
filter = chaos-site-forms
logpath = /var/log/apache2/*access*.log
backend = auto
findtime = 10m
maxretry = 30
EOF
	fi
}
if write_file /etc/fail2ban/jail.d/chaos.local 0644 < <(jail_conf); then
	run fail2ban-client -t
	run systemctl enable fail2ban
	run systemctl restart fail2ban
fi
[ "$web_jail" = 1 ] || say "web jail off ($([ "$CLOUDFLARE" = 1 ] && echo "--cloudflare" || echo "no Apache"))"

# ---------------------------------------------------------------- 5. Apache
if [ -d "$R/etc/apache2" ]; then
	apache_changed=0
	if write_file /etc/apache2/conf-available/chaos-security.conf 0644 <<'EOF'
# harden_vps.sh: no version in headers and error pages, no TRACE. The PHP pages send their own security headers
# (website/README.md "Web server"); "setifempty" adds the same values to static files only, never a second copy.
ServerTokens Prod
ServerSignature Off
TraceEnable Off
<IfModule mod_headers.c>
    Header always unset X-Powered-By
    Header unset X-Powered-By
    Header setifempty X-Content-Type-Options "nosniff"
    Header setifempty Referrer-Policy "strict-origin-when-cross-origin"
    Header setifempty X-Frame-Options "SAMEORIGIN"
    Header setifempty Strict-Transport-Security "max-age=31536000" "expr=%{HTTPS} == 'on'"
</IfModule>
EOF
	then apache_changed=1; fi
	if [ ! -e "$R/etc/apache2/mods-enabled/headers.load" ]; then run a2enmod -q headers; apache_changed=1; fi
	if [ ! -e "$R/etc/apache2/conf-enabled/chaos-security.conf" ]; then run a2enconf -q chaos-security; apache_changed=1; fi
	if [ "$CLOUDFLARE" = 1 ]; then
		mapfile -t ranges < <( (curl -fsS --max-time 20 https://www.cloudflare.com/ips-v4; echo
			curl -fsS --max-time 20 https://www.cloudflare.com/ips-v6) 2>/dev/null | grep -E '^[0-9a-fA-F:.]+/[0-9]{1,3}$' | sort -u || true)
		if [ ${#ranges[@]} -eq 0 ]; then
			warn "could not fetch Cloudflare's address ranges (https://www.cloudflare.com/ips-v4): mod_remoteip not set"
		else
			cf_conf() {
				echo "# harden_vps.sh --cloudflare: the visitor's address from CF-Connecting-IP, from Cloudflare's ranges only"
				echo "RemoteIPHeader CF-Connecting-IP"
				printf 'RemoteIPTrustedProxy %s\n' "${ranges[@]}"
			}
			if write_file /etc/apache2/conf-available/chaos-cloudflare.conf 0644 < <(cf_conf); then apache_changed=1; fi
			if [ ! -e "$R/etc/apache2/mods-enabled/remoteip.load" ]; then run a2enmod -q remoteip; apache_changed=1; fi
			if [ ! -e "$R/etc/apache2/conf-enabled/chaos-cloudflare.conf" ]; then run a2enconf -q chaos-cloudflare; apache_changed=1; fi
		fi
	fi
	if [ "$apache_changed" = 1 ]; then
		run apache2ctl configtest
		run systemctl reload apache2
	fi
else
	say "no Apache (/etc/apache2): web server step skipped"
fi

# ---------------------------------------------------------------- 6. checks
listeners=$( (ss -Hltn 2>/dev/null || true) | awk '{ print $4 }')
for port in $LOCAL_ONLY; do
	while IFS= read -r addr; do
		[ -n "$addr" ] || continue
		case $addr in
			127.*:"$port"|"[::1]:$port"|"localhost:$port") say "ok: port $port listens on $addr only" ;;
			*:"$port") warn "port $port listens on $addr: it must be 127.0.0.1 only (MariaDB bind-address / --bind-address, clientservices.py --host 127.0.0.1)" ;;
		esac
	done <<< "$listeners"
done
for cnf in "$R"/etc/mysql/my.cnf "$R"/etc/mysql/mariadb.conf.d/*.cnf; do
	[ -f "$cnf" ] || continue
	if grep -Eq '^[[:space:]]*bind-address[[:space:]]*=[[:space:]]*(0\.0\.0\.0|::|\*)' "$cnf"; then
		warn "${cnf#"$R"}: bind-address opens the system MariaDB to the network; set 127.0.0.1"
	fi
done

# private files: mode 600 (env and key files) or not world-readable (config.local.php, read by the web server)
check_private() {  # path max-mode-mask what
	local f=$1 mask=$2 mode
	[ -f "$f" ] || return 0
	mode=$(stat -c '%a' "$f")
	if (( 8#$mode & 8#$mask )); then
		if [ "$mask" = 077 ]; then
			run chmod go-rwx "$f"
		else
			run chmod o-rwx "$f"
		fi
		warn "${f#"$R"} was mode $mode ($3)$([ "$DRY" = 1 ] && echo ", would be fixed" || echo ", fixed")"
	else
		say "ok: ${f#"$R"} mode $mode, owner $(stat -c '%U' "$f")"
	fi
}
envs=()
for f in "$R"/etc/chaos/chaos.env "$R"/etc/chaos/site.env "$R"/etc/chaos/payments.env; do envs+=("$f"); done
if [ -n "$SERVER_DIR" ]; then
	envs+=("$R$SERVER_DIR/chaos.env")
else
	while IFS= read -r f; do envs+=("$f"); done < <(find "$R/home" "$R/opt" "$R/srv" -maxdepth 4 -name chaos.env -type f 2>/dev/null)
fi
keys=()
for f in "${envs[@]}"; do
	[ -f "$f" ] || continue
	check_private "$f" 077 "credentials"
	# the key and passphrase files it names (values only, never printed beyond their paths)
	while IFS= read -r value; do
		IFS=, read -ra parts <<< "$value"
		for p in "${parts[@]}"; do
			p=${p#"${p%%[![:space:]]*}"}
			[ -z "$p" ] && continue
			case $p in
				/*) keys+=("$R$p") ;;
				*) warn "${f#"$R"}: $p is a relative path: use an absolute one (the engine's folder decides what it means)" ;;
			esac
		done
	done < <(sed -n -E 's/^(CHAOS_RSA_KEY_FILE|CHAOS_BACKUP_PASSPHRASE_FILE|CHAOS_BACKUP_SSH_KEY)=["'\'']?([^"'\'']*)["'\'']?[[:space:]]*$/\2/p' "$f")
	if grep -Eq '^CHAOS_CLIENT_KEY=[[:space:]]*$' "$f"; then
		warn "${f#"$R"}: CHAOS_CLIENT_KEY is empty: the client guard is off (docs/SECURITY_CHECKLIST.md)"
	fi
	if [ "$(basename "$f")" = chaos.env ] && ! grep -Eq '^CHAOS_RSA_KEY_FILE=[^[:space:]]' "$f"; then
		warn "${f#"$R"}: no CHAOS_RSA_KEY_FILE: the login uses the public default RSA key (server/tools/rsa_key.py gen)"
	fi
	if [ -f "$(dirname "$f")/first-start-account.txt" ]; then
		warn "$(dirname "${f#"$R"}")/first-start-account.txt holds the first staff password: change that password in the game, then delete the file"
	fi
done
for k in "${keys[@]}"; do
	if [ -f "$k" ]; then
		check_private "$k" 077 "a private key or passphrase"
	else
		warn "${k#"$R"} (named in an env file) does not exist"
	fi
done
sites=()
if [ -n "$SITE_DIR" ]; then
	sites+=("$R$SITE_DIR/config.local.php")
else
	while IFS= read -r f; do sites+=("$f"); done < <(find "$R/var/www" -maxdepth 3 -name config.local.php -type f 2>/dev/null)
fi
for f in "${sites[@]}"; do
	check_private "$f" 007 "database password; the web server still reads it through its group or owner"
done

# ---------------------------------------------------------------- 7. SSH
ssh_conf=/etc/ssh/sshd_config.d/10-chaos-hardening.conf
if [ "$LOCK_SSH" = 1 ]; then
	missing=()
	home=
	if [ -z "$ADMIN" ]; then
		missing+=("--admin-user NAME (the account you log in with)")
	elif [ "$ADMIN" = root ]; then
		missing+=("--admin-user root: root logins are what this turns off; make a user (adduser NAME; usermod -aG sudo NAME), give it your key and use that")
	else
		home=$( (getent passwd "$ADMIN" || true) | cut -d: -f6)
		[ -n "$home" ] || missing+=("the user $ADMIN does not exist")
	fi
	if [ -n "$home" ]; then
		ak="$R$home/.ssh/authorized_keys"
		nkeys=0
		if [ -f "$ak" ]; then
			if have ssh-keygen; then
				nkeys=$( (ssh-keygen -l -f "$ak" 2>/dev/null || true) | grep -c . || true)
			else
				nkeys=$(grep -Ec '^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp[0-9]+|sk-[a-z0-9@.-]+) [A-Za-z0-9+/=]{40,}' "$ak" || true)
			fi
			if [ "$(stat -c '%a' "$ak")" != 600 ] && [ "$(stat -c '%a' "$ak")" != 644 ]; then
				missing+=("$home/.ssh/authorized_keys has mode $(stat -c '%a' "$ak") (chmod 600; sshd refuses group-writable files)")
			fi
		fi
		[ "$nkeys" -gt 0 ] || missing+=("no valid public key in $home/.ssh/authorized_keys (ssh-copy-id from your PC)")
		if ! (id -nG "$ADMIN" 2>/dev/null || true) | tr ' ' '\n' | grep -Eqx 'sudo|admin|wheel'; then
			missing+=("$ADMIN is not in the sudo group (usermod -aG sudo $ADMIN), so without root login nobody could become root")
		fi
		evidence=0
		if grep -hqs "Accepted publickey for $ADMIN from" "$R"/var/log/auth.log "$R"/var/log/auth.log.1; then
			evidence=1
		elif [ -z "$R" ] && have journalctl && journalctl -q --no-pager -t sshd -t sshd-session --since -30d 2>/dev/null \
				| grep -q "Accepted publickey for $ADMIN from"; then
			evidence=1
		fi
		if [ "$evidence" = 0 ] && [ "$TESTED" = 0 ]; then
			missing+=("no key login of $ADMIN in the SSH log: log in with your key in a new terminal (ssh -i KEY $ADMIN@HOST), then run this again (or add --key-login-tested)")
		fi
	fi
	if [ ${#missing[@]} -gt 0 ]; then
		SSH_STATE="NOT locked: ${#missing[@]} thing(s) missing (above)"
		for m in "${missing[@]}"; do warn "SSH stays open to passwords: $m"; done
	else
		if write_file "$ssh_conf" 0644 <<EOF
# harden_vps.sh --lock-ssh: keys only, no root login (docs/SECURITY_CHECKLIST.md). sshd takes the first value it reads,
# and this file sorts before the cloud image's 50-cloud-init.conf. To undo: delete this file, systemctl reload ssh.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 4
LoginGraceTime 30
X11Forwarding no
EOF
		then
			if [ "$DRY" = 0 ] && ! sshd -t; then
				rm -f "$R$ssh_conf"
				die "sshd -t refused the new settings: removed $ssh_conf, SSH unchanged"
			fi
			run systemctl reload ssh
		fi
		SSH_STATE="keys only, no root login ($ssh_conf)"
	fi
fi

# ---------------------------------------------------------------- summary
echo
say "done$([ "$DRY" = 1 ] && echo " (dry run: nothing changed)"); files written: $CHANGED; warnings: $WARN"
say "SSH: $SSH_STATE"
cat <<EOF
Test now, before you close this session:
  1. In a NEW terminal: ssh${SSH_PORT:+ -p $SSH_PORT} ${ADMIN:-USER}@HOST with your key, then sudo -v.
  2. A client logs in to the game (7171 / 7172), the website opens over https.
  3. sudo ufw status verbose; sudo fail2ban-client status; systemctl status unattended-upgrades
If the new terminal cannot log in: in this session remove $ssh_conf and run systemctl reload ssh.
EOF
