# Security checklist (beta VPS)

Audit of 2026-10-16. Setup: one Ubuntu 24.04 VPS running the Linux server package (its own MariaDB on 127.0.0.1:3307,
user `chaos`, in a screen) and the website (Apache, PHP, Let's Encrypt). Domain on Cloudflare DNS.

Rules for every step: secrets never go into the repository, a chat, a screenshot or an issue. You type them into
GitHub and into files on the VPS yourself.

## 1. What the code already does

| Area | Protection | Where |
|---|---|---|
| Login encryption | the server can use our own RSA key (several during a rotation) and warns about the public default key | engine patch 0046, `server/tools/rsa_key.py` |
| Login encryption | the client encrypts with the key from the release secret `CHAOS_RSA_PUBLIC` | client patch 0072, `client/tools/set_rsa_key.py` |
| Session encryption | the client's XTEA key is random (it came from the clock before) | client patch 0072 |
| Password guessing in the game | 20 failures per IP or 50 per account in 10 min block it for 15 min | engine patch 0047 |
| Password guessing on the site | 5 per IP, 10 per account in 15 min; salted PBKDF2 everywhere | website/README.md "Passwords" |
| Other clients and bots | client guard (HMAC handshake, build check, module hello) | server/README.md "Client guard" |
| Releases | the package workflow fails without the key secrets unless `allow_dev_key` is ticked | `windows-package.yml` |
| Client updates | Ed25519-signed manifest, every file hash-checked | docs/LAUNCH.md "Client updates" |
| Game requests | every extended opcode validated, rate limited, fuzz tested | server/README.md "Protocol fuzz test" |
| SQL | player strings escaped, numbers checked; the fuzz test fails on an unescaped string | docs/LAUNCH.md section 10 |
| Website | CSRF tokens, CSP, HSTS, Secure + HttpOnly + SameSite=Lax cookie, denied internals | website/README.md "Web server" |
| VPS | firewall, fail2ban, security updates, sysctl, Apache headers, SSH keys only, permission checks | `tools/linux/harden_vps.sh` |

## 2. What you must do, in order

### 2.1 An SSH key (on your PC)
1. `ssh-keygen -t ed25519` (set a passphrase).
2. On the VPS, as root, make your own user if you only have root: `adduser NAME`, then `usermod -aG sudo NAME`.
3. From your PC: `ssh-copy-id NAME@VPS`.
4. Open a new terminal: `ssh NAME@VPS` (SSH must not ask for a password), then `sudo -v`.

### 2.2 Harden the VPS
Get `tools/linux/harden_vps.sh` (in the release's Linux server package, or the repository).
1. `sudo ./harden_vps.sh --admin-user NAME --dry-run`. Read what it would change.
2. `sudo ./harden_vps.sh --admin-user NAME`. Firewall, fail2ban, updates, sysctl, Apache, checks.
3. Read every WARNING and fix it (for example a file with the wrong mode, MariaDB on a public address).
4. Keep this session open. Log in with your key in a second terminal.
5. `sudo ./harden_vps.sh --admin-user NAME --lock-ssh`. Passwords and root logins over SSH end.
6. Test again in a new terminal before you close the old one. To undo: delete
   `/etc/ssh/sshd_config.d/10-chaos-hardening.conf`, then `sudo systemctl reload ssh`.

Open ports afterwards: SSH (rate limited), 80, 443, 7171, 7172. 3307 and 8090 stay local.

### 2.3 Client guard key (`CHAOS_CLIENT_KEY`)
1. On your PC: `openssl rand -hex 32`. Store it in your password manager.
2. GitHub: Settings, Secrets and variables, Actions, New repository secret. Name `CHAOS_CLIENT_KEY`, value the 64 hex
   digits.
3. On the VPS, as `chaos`: edit `chaos.env` of the server package (`nano chaos.env`). Paste it after
   `CHAOS_CLIENT_KEY=`. Mode stays 600.
4. Check after the next restart: the console says `>> Client guard: enforce, 1 key(s)` and the HMAC self-test passes.
   `server/data/logs/clientguard.log` shows `verified` for your own login.

### 2.4 Our own RSA login key (`CHAOS_RSA_PUBLIC`)
1. On the VPS, as `chaos`:
   `python3 -I server/tools/rsa_key.py gen --out "$HOME/chaos-rsa/login-$(date +%Y%m%d).pem"`.
2. It prints a fingerprint and a long number (the public modulus). The number is public, but keep it out of the repo.
3. GitHub: New repository secret (or variable) `CHAOS_RSA_PUBLIC`, value that number.
4. Never copy the `.pem` file anywhere. `rsa_key.py check --key FILE` checks it.

### 2.5 Build the release
Actions, Windows package, Run workflow:
- `server_host`: the game's DNS name (for example `play.example.org`), never the IP.
- `site_url`: `https://` and the site's name.
- `client_build`: one higher than the last release.
- `allow_dev_key`: off.

Check the release notes: "built with the official key" and "Login encryption ...: our own key". The build log
prints the RSA fingerprint; it must match step 2.4.

### 2.6 Switch the server
1. Stop the server (`./stop-server.sh`).
2. From the new Linux server package copy `server/tfs`, `server/lib/` and `server/tools/rsa_key.py` over the old
   ones. Keep `chaos.env`, `database/` and `server/data/`.
3. In `server/config.lua` add, if missing: `rsaKeyFile = os.getenv("CHAOS_RSA_KEY_FILE") or "key.pem"`.
4. In `chaos.env`: `CHAOS_RSA_KEY_FILE=/home/chaos/chaos-rsa/login-YYYYMMDD.pem,key.pem` (the full path; the new
   key first, the old default key second so old clients still log in).
5. Start in the screen (`./start-server.sh`). The console shows `RSA key 1` with the fingerprint of step 2.4, and a
   WARNING for key 2 (the default key; expected while old clients exist).
6. Players download the new client. After the update window (for example one week):
   `CHAOS_RSA_KEY_FILE=/home/chaos/chaos-rsa/login-YYYYMMDD.pem` only, then restart. No WARNING may remain.
7. Refuse old builds: `clientGuardBuilds = "N"` in `config.lua` (N = the new `client_build`).

### 2.7 Website
1. `sudo ls -l /etc/chaos/`: `site.env`, `payments.env` mode 600; `config.local.php` not world-readable.
2. `php.ini`: `expose_php = Off`, `display_errors = Off`.
3. `systemctl list-timers | grep certbot`: certificate renewal runs.
4. `curl -sI https://SITE/ | grep -i -e strict-transport -e x-frame -e server:`: HSTS and X-Frame-Options present,
   `Server: Apache` without a version.

### 2.8 Backups
1. Database every day: `mariadb/bin/mariadb-dump --no-defaults --socket="$(cat run/socket.txt)" -u "$(id -un)" chaos`
   (tools/linux/server/README.txt), for example from cron.
2. Copy the dumps off the VPS, encrypted (`age` or `gpg`). Keep the decryption key off the VPS.
3. Test a restore once on another machine.
4. Keep in your password manager: `CHAOS_CLIENT_KEY`, the updater's `update.key` (offline), the VPS root login.
   Not the RSA private key: if the VPS is lost, make a new one and build a new client.

### 2.9 Cloudflare (DNS)
- `@` and `www` (the website): proxy on (orange cloud) if you want it, SSL/TLS mode **Full (strict)**. Then run
  `sudo ./harden_vps.sh --admin-user NAME --cloudflare`, so Apache sees the visitor's real address (the site's
  login limits count per address).
- `play` (the game): **DNS only** (grey cloud), always. Cloudflare's proxy carries web traffic only.
- The `play` record shows the VPS address anyway, so the proxy does not hide the machine. Hiding it needs the
  gateways of docs/LAUNCH.md "Gateways and DDoS" and a new IP.
- Turn on "Always Use HTTPS". Leave "Development Mode" off.

### 2.10 Every week
- `sudo fail2ban-client status sshd`; `sudo ufw status`.
- Reboot when `/var/run/reboot-required` exists (after the daily save).
- Read `server/data/logs/clientguard.log` for kicks, and the console for `[Login limit]` lines.
- Delete `first-start-account.txt` once the staff password was changed in the game.

### 2.11 Key rotation (yearly, or at once after a leak)
- RSA: steps 2.4 to 2.6 with a new file name. After a leak, also ask players to change their passwords.
- Client guard: a new `CHAOS_CLIENT_KEY`; in `chaos.env` `old,new` during the window, then `new` only.
- Never put a leaked key back.

## 3. Client data protection (assessed, not enabled)

The base client can pack its files as "ENC3" (zlib plus XXTEA, `--encrypt`). The key of each file is stored in the
file's own header, next to fixed constants. Anyone with the file can decrypt it, so this is obfuscation, not
encryption. Its costs: every update must ship packed files, one unpacked file stops the client, the 600 MB
`Tibia.spr` is over its 512 MB limit, and Lua bytecode is still easy to decompile. Real encryption would need a key
inside the exe, which a debugger reads in minutes. Decision: not enabled. What protects the game is the server's
own checks, the client guard and the signed updater (integrity, not secrecy).

## 4. Limits that stay

- The 10.98 protocol: 1024-bit RSA without padding, XTEA without a MAC. Only a new transport would fix that.
- The client guard key is inside every client; a skilled attacker can extract it.
- The VPS IP is public through the `play` record. A DDoS on it stops the game until gateways are in place.
- Someone who knows an account name can block its game login for 15 minutes (50 wrong passwords from 3+ IPs).
