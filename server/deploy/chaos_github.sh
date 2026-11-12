#!/usr/bin/env bash
# Cinders of Chaos: the one door to GitHub for the VPS scripts (O530). The repository is private, so every access
# needs the token of the VPS: chaos-ctl.sh, chaos_update.sh, chaos_kit_update.sh and publish_client_update.sh source
# this file; nothing else on the VPS talks to GitHub. Sourced, never run. It sets no shell option.
#
# One secret: a fine-grained token of this one repository (Contents read, Metadata read, Actions read and write for
# engine-build), one line in a root-only file. The file is CHAOS_GITHUB_TOKEN_FILE, else CHAOS_ENGINE_TOKEN_FILE (the
# name of before O530), else /etc/chaos/github.token, else an existing /etc/chaos/engine-build.token. The token is
# read from the file at the moment it is used. A script that starts another one passes CHAOS_GITHUB_TOKEN_FILE on
# (exported); the defaults are the same in both. The token never goes on a command line (curl gets its config on stdin, git
# gets it from a credential helper that reads the file), never into .git/config, never into a log or the output.
#
#   chaos_gh_token_file           the path of the token file
#   chaos_gh_token_files          every file a token may sit in (what an empty github-token-set removes)
#   chaos_gh_token                the token, or nothing
#   chaos_gh_api METHOD PATH OUT [JSON]
#                                 api.github.com, the answer into the file OUT, prints the HTTP code (000: no answer);
#                                 with CHAOS_GH_NOAUTH=1 in front of the call: without the token (is the repo public?)
#   chaos_gh_git ARGS...          git with the token for github.com over https (a credential helper), no prompt
#   chaos_gh_explain CODE REPO    "word: sentence" for a refused answer, nothing for a good one. Words: private-repo
#                                 (no token, GitHub says 401 / 403 / 404), token-refused (401), no-access (403 / 404
#                                 with a token), github-unreachable
#   chaos_gh_git_why REPO         after a failed git command: the same, from one probe of the repository
#   chaos_gh_slug URL             OWNER/REPO of a github.com remote URL (https or ssh), nothing for another host
#   chaos_gh_asset_url REPO ID    prints "CODE URL": the short-lived signed address of a release asset (the token
#                                 asks for it, the address itself holds no token)
#   chaos_gh_download REPO ID FILE [MAXBYTES]
#                                 a release asset into FILE (return 0), the reason in CHAOS_GH_WHY otherwise
#   chaos_gh_asset_id REPO TAG NAME
#                                 the number of an asset of a release by tag and name, in CHAOS_GH_ID (return 0), the
#                                 reason in CHAOS_GH_WHY otherwise
#   chaos_gh_release_asset REPO TAG NAME FILE [MAXBYTES]
#                                 the same by release tag and asset name (return 0), the reason in CHAOS_GH_WHY

CHAOS_GH_TOKEN_RE='^(github_pat_[A-Za-z0-9_]{20,250}|gh[pousr]_[A-Za-z0-9]{30,250})$'
CHAOS_GH_WHY="" CHAOS_GH_ID=""

chaos_gh_token_file() {
  local f=${CHAOS_GITHUB_TOKEN_FILE:-}
  [ -n "$f" ] || f=${CHAOS_ENGINE_TOKEN_FILE:-}
  if [ -z "$f" ]; then
    f=/etc/chaos/github.token
    if [ ! -e "$f" ] && [ -e /etc/chaos/engine-build.token ]; then f=/etc/chaos/engine-build.token; fi
  fi
  printf '%s' "$f"
}

chaos_gh_token_files() {
  if [ -n "${CHAOS_GITHUB_TOKEN_FILE:-}" ]; then printf '%s\n' "$CHAOS_GITHUB_TOKEN_FILE"
  elif [ -n "${CHAOS_ENGINE_TOKEN_FILE:-}" ]; then printf '%s\n' "$CHAOS_ENGINE_TOKEN_FILE"
  else printf '%s\n%s\n' /etc/chaos/github.token /etc/chaos/engine-build.token; fi
}

# the token from its file, or nothing when the file is missing or holds no token
chaos_gh_token() {
  local f t=""
  f=$(chaos_gh_token_file)
  [ -r "$f" ] && t=$(head -c 400 "$f" 2>/dev/null | tr -d '[:space:]')
  [[ $t =~ $CHAOS_GH_TOKEN_RE ]] && printf '%s' "$t"
  return 0
}

# the config lines of curl for one api.github.com request; the token line only when there is a token
_chaos_gh_cfg() {
  local url=$1 accept=${2:-application/vnd.github+json} tok cfg
  cfg=$(printf 'url = "%s"\nheader = "Accept: %s"\nheader = "X-GitHub-Api-Version: 2022-11-28"\nheader = "User-Agent: chaos-ctl"' "$url" "$accept")
  tok=""
  [ -n "${CHAOS_GH_NOAUTH:-}" ] || tok=$(chaos_gh_token)
  [ -z "$tok" ] || cfg=$cfg$'\n'$(printf 'header = "Authorization: Bearer %s"' "$tok")
  printf '%s\n' "$cfg"
}

chaos_gh_api() {
  local m=$1 p=$2 out=$3 data=${4:-} code
  local -a ca=(-K - -sS --proto '=https' -o "$out" -w '%{http_code}' --max-time 30)
  if [ "$m" = POST ]; then ca+=(-H 'Content-Type: application/json' -d "$data"); fi
  : > "$out"
  code=$(_chaos_gh_cfg "https://api.github.com$p" | curl "${ca[@]}" 2>/dev/null) || code=${code:-000}
  printf '%s' "${code:-000}"
}

# the credential helper of git: answers only for https://github.com, reads the file at the moment git asks
# shellcheck disable=SC2016  # the helper is shell text for git, not for this shell
_CHAOS_GH_HELPER='!f() { [ "$1" = get ] || return 0; h=0; p=0; while IFS= read -r l && [ -n "$l" ]; do case $l in host=github.com) h=1;; protocol=https) p=1;; esac; done; [ "$h$p" = 11 ] || return 0; t=$(head -c 400 "$CHAOS_GH_FILE" 2>/dev/null | tr -d "[:space:]"); [ -n "$t" ] || return 0; printf "username=x-access-token\npassword=%s\n" "$t"; }; f'

chaos_gh_git() {
  if [ -n "$(chaos_gh_token)" ]; then
    CHAOS_GH_FILE=$(chaos_gh_token_file) GIT_TERMINAL_PROMPT=0 git -c credential.helper= \
      -c "credential.helper=$_CHAOS_GH_HELPER" "$@"
  else
    GIT_TERMINAL_PROMPT=0 git "$@"
  fi
}

chaos_gh_explain() {
  local code=${1:-000} repo=${2:-the repository} have=""
  [ -z "$(chaos_gh_token)" ] || have=1
  case $code in
    2??|3??) return 0 ;;
    401|403|404)
      if [ -z "$have" ]; then
        printf 'private-repo: GitHub says %s and no GitHub token is saved: %s is private. Save the token: chaos-ctl.sh github-token-set (admin app: Definir token do GitHub)' "$code" "$repo"
      elif [ "$code" = 401 ]; then
        printf 'token-refused: GitHub refused the token (401): save a new one with github-token-set'
      else
        printf 'no-access: GitHub says %s: the token does not reach %s (Contents read, Metadata read): save a new one with github-token-set' "$code" "$repo"
      fi ;;
    *) printf 'github-unreachable: HTTP %s from api.github.com' "$code" ;;
  esac
}

chaos_gh_git_why() {
  local repo=${1:-} body code
  [ -n "$repo" ] || return 0
  body=$(mktemp) || return 0
  code=$(chaos_gh_api GET "/repos/$repo" "$body")
  rm -f "$body"
  if [ "$code" = 200 ] && [ -n "$(chaos_gh_token)" ]; then
    printf 'no-access: git was refused although GitHub knows %s: the token needs Contents read (chaos-ctl.sh github-token-status)' "$repo"
  else
    chaos_gh_explain "$code" "$repo"
  fi
}

chaos_gh_slug() {
  local u=${1:-} s
  case $u in
    https://github.com/*|ssh://git@github.com/*|git@github.com:*) ;;
    *) return 0 ;;
  esac
  s=${u#*github.com[:/]}
  s=${s%/}
  s=${s%.git}
  [[ $s =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && printf '%s' "$s"
  return 0
}

chaos_gh_asset_url() {
  local repo=$1 id=$2 res
  [[ $id =~ ^[0-9]{1,15}$ ]] || { printf '000 '; return 0; }
  res=$(_chaos_gh_cfg "https://api.github.com/repos/$repo/releases/assets/$id" application/octet-stream \
    | curl -K - -sS --proto '=https' -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 30 2>/dev/null) || res=${res:-000 }
  printf '%s' "${res:-000 }"
}

chaos_gh_download() {
  local repo=$1 id=$2 file=$3 max=${4:-8589934592} code url rest
  CHAOS_GH_WHY=""
  read -r code url rest <<< "$(chaos_gh_asset_url "$repo" "$id")"
  if [ "$code" != 302 ] && [ "$code" != 301 ] || [[ ${url:-} != https://* ]] || [[ ${url:-} == *'"'* ]]; then
    CHAOS_GH_WHY=$(chaos_gh_explain "${code:-000}" "$repo")
    [ -n "$CHAOS_GH_WHY" ] || CHAOS_GH_WHY="download-failed: GitHub answered $code without an address for asset $id"
    return 1
  fi
  # the signed address is a bearer for this one asset for a few minutes: it goes to curl on stdin, never into a log
  if printf 'url = "%s"\n' "$url" | curl -K - -fL --proto '=https' --proto-redir '=https' --retry 3 --retry-delay 5 \
    --max-filesize "$max" -sS -o "$file" 2>/dev/null; then
    return 0
  fi
  CHAOS_GH_WHY="download-failed: the download of asset $id of $repo failed"
  return 1
}

chaos_gh_asset_id() {
  local repo=$1 tag=$2 name=$3 body code
  CHAOS_GH_WHY="" CHAOS_GH_ID=""
  body=$(mktemp) || { CHAOS_GH_WHY="no temporary file"; return 1; }
  code=$(chaos_gh_api GET "/repos/$repo/releases/tags/$tag" "$body")
  if [ "$code" != 200 ]; then
    CHAOS_GH_WHY=$(chaos_gh_explain "$code" "$repo")
    if [ "$code" = 404 ] && [ -n "$(chaos_gh_token)" ]; then CHAOS_GH_WHY="no-release: no release $tag in $repo, or the token does not reach it"; fi
    rm -f "$body"
    return 1
  fi
  CHAOS_GH_ID=$(python3 -I - "$body" "$name" <<'PY' 2>/dev/null
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding='utf-8'))
    for a in data.get('assets') or []:
        if a.get('name') == sys.argv[2] and isinstance(a.get('id'), int):
            print(a['id'])
            break
except Exception:
    pass
PY
)
  rm -f "$body"
  if [ -z "$CHAOS_GH_ID" ]; then CHAOS_GH_WHY="no-asset: release $tag of $repo has no $name"; return 1; fi
  return 0
}

chaos_gh_release_asset() {
  local repo=$1 tag=$2 name=$3 file=$4 max=${5:-8589934592}
  chaos_gh_asset_id "$repo" "$tag" "$name" || return 1
  chaos_gh_download "$repo" "$CHAOS_GH_ID" "$file" "$max"
}
