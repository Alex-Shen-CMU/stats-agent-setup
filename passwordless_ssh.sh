#!/usr/bin/env bash
# Walk through setting up passwordless (public-key) ssh login to the servers covered by
# this repo's skills: the CMU Statistics department servers, wright, and Bridges-2.
# For each server it checks ~/.ssh/config for a working key; if there is none, it can
# generate a key pair, install it with ssh-copy-id, verify it, and add a ~/.ssh/config
# entry (Bridges-2 keys are registered with PSC instead; the script points to their docs).
# It then fills the <user_id> placeholder in the installed server skills.
#
# Usage (from your project directory, so the installed skills can be found):
#   curl -fsSL https://raw.githubusercontent.com/Alex-Shen-CMU/stats-agent-setup/main/passwordless_ssh.sh | bash
#   bash passwordless_ssh.sh [options]
#
# Options:
#   --dir PATH         project whose installed skills to update (default: current directory)
#   --skills-dir PATH  also look for skills in PATH (e.g. .claude/skills); repeatable
#   --only NAMES       comma-separated subset of: department,wright,bridges2
set -uo pipefail

TARGET="$PWD"
EXTRA_SKILL_DIRS=()
ONLY=""

die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) TARGET="${2:-}"; shift 2 ;;
    --skills-dir) EXTRA_SKILL_DIRS+=("${2:-}"); shift 2 ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null || true; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[ -d "$TARGET" ] || die "directory does not exist: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"

for cmd in ssh ssh-keygen ssh-copy-id; do
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd not found; install OpenSSH first"
done

# When piped through `curl | bash`, stdin is the script itself, so prompts (and anything
# else interactive, like ssh-copy-id's password prompt) read from the terminal.
(: < /dev/tty) 2>/dev/null || die "this script is interactive and needs a terminal"
TTY=/dev/tty

ask() {  # ask "prompt" default -> echoes answer
  local reply=""
  printf '%s' "$1" > "$TTY"
  read -r reply < "$TTY" || true
  echo "${reply:-$2}"
}

ask_yn() {  # ask_yn "question" y|n -> 0 for yes
  local hint="[y/n]" reply
  [ "$2" = y ] && hint="[Y/n]"
  [ "$2" = n ] && hint="[y/N]"
  while :; do
    reply="$(ask "$1 $hint: " "$2")"
    case "$reply" in
      y|Y|yes|Yes|YES) return 0 ;;
      n|N|no|No|NO) return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"
CONFIG_BACKED_UP=0

# ---------------------------------------------------------------- servers
# id | display name | hosts to test (first reachable one is used) | config Host patterns |
# HostName for the config block (empty: none) | skill directory names to fill (space-separated)
SERVERS=(
  "department|CMU Statistics department servers (hydra, leviathan, ghidorah)|leviathan1.stat.cmu.edu leviathan2.stat.cmu.edu ghidorah1.stat.cmu.edu hydra1.stat.cmu.edu|hydra*.stat.cmu.edu leviathan*.stat.cmu.edu ghidorah*.stat.cmu.edu||department-servers"
  "wright|wright (wright.hss.cmu.edu)|wright.hss.cmu.edu|wright wright.hss.cmu.edu|wright.hss.cmu.edu|wright claude-followup"
  "bridges2|Bridges-2 (bridges2.psc.edu)|bridges2.psc.edu|bridges2 bridges2.psc.edu|bridges2.psc.edu|bridges2"
)

# ---------------------------------------------------------------- ssh helpers
LAST_ERR=""

# check_login host [ssh options...] -> 0 key login works, 1 auth failed, 2 could not connect.
# Only public-key auth is allowed, so a password or Kerberos login doesn't count.
check_login() {
  local host="$1" rc
  shift
  LAST_ERR="$(ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
    -o PreferredAuthentications=publickey "$@" "$host" true 2>&1 >/dev/null)"
  rc=$?
  [ "$rc" -eq 0 ] && return 0
  case "$LAST_ERR" in
    *"Permission denied"*|*"Too many authentication failures"*) return 1 ;;
    *) return 2 ;;
  esac
}

# check_any "hosts" [ssh options...] -> like check_login, trying hosts until one is reachable.
# Sets CHECKED_HOST to the host that answered.
CHECKED_HOST=""
check_any() {
  local hosts="$1" h rc=2
  shift
  for h in $hosts; do
    CHECKED_HOST="$h"
    check_login "$h" "$@"
    rc=$?
    [ "$rc" -ne 2 ] && return "$rc"
  done
  return "$rc"
}

report_failure() {  # report_failure rc
  if [ "$1" -eq 2 ]; then
    echo "  Could not connect: ${LAST_ERR:-unknown error}"
    echo "  If you are off campus, connect to the CMU VPN and try again."
  else
    echo "  Key login was rejected: ${LAST_ERR:-permission denied}"
  fi
}

ssh_opt() {  # ssh_opt host option -> values ssh resolves for option, one per line
  ssh -G "$1" 2>/dev/null | awk -v k="$2" '$1 == k { $1 = ""; sub(/^ /, ""); print }'
}

# Identity files that ~/.ssh/config sets for host, with ~ expanded, one per line; only
# files that exist are listed. ssh drops its built-in defaults once the config names any
# IdentityFile, so the config sets them exactly when the list differs from the defaults.
configured_identities() {
  local defaults configured f
  defaults="$(ssh -G -F /dev/null "$1" 2>/dev/null | awk '$1 == "identityfile"')"
  configured="$(ssh -G "$1" 2>/dev/null | awk '$1 == "identityfile"')"
  [ "$configured" != "$defaults" ] || return 0
  sed 's/^identityfile //' <<< "$configured" |
    while IFS= read -r f; do
      f="${f/#\~/$HOME}"
      [ -f "$f" ] && echo "$f"
    done
}

# ---------------------------------------------------------------- ssh config
# Each server gets a block between marker lines at the top of ~/.ssh/config (ssh uses the
# first value it finds, so entries further down can't override it). The trailing `Host *`
# keeps any global options that followed in the original file applying to every host.
remove_config_block() {  # remove_config_block id
  [ -f "$SSH_CONFIG" ] || return 0
  local tmpf="$SSH_CONFIG.tmp.$$"
  awk -v start="# >>> passwordless_ssh.sh: $1 >>>" -v end="# <<< passwordless_ssh.sh: $1 <<<" '
    $0 == start { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip
  ' "$SSH_CONFIG" > "$tmpf" && mv "$tmpf" "$SSH_CONFIG"
}

write_config_block() {  # write_config_block id patterns hostname user keyfile
  local id="$1" patterns="$2" hostname="$3" user="$4" key="$5" tmpf="$SSH_CONFIG.tmp.$$"
  mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"
  touch "$SSH_CONFIG"
  if [ "$CONFIG_BACKED_UP" = 0 ] && [ -s "$SSH_CONFIG" ]; then
    cp -p "$SSH_CONFIG" "$SSH_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    CONFIG_BACKED_UP=1
  fi
  remove_config_block "$id"
  {
    echo "# >>> passwordless_ssh.sh: $id >>>"
    echo "Host $patterns"
    [ -n "$hostname" ] && echo "    HostName $hostname"
    echo "    User $user"
    echo "    IdentityFile ${key/#"$HOME"/\~}"
    echo "    IdentitiesOnly yes"
    echo "# Ends the block above so settings below it still apply to all hosts."
    echo "Host *"
    echo "# <<< passwordless_ssh.sh: $id <<<"
    cat "$SSH_CONFIG"
  } > "$tmpf" && mv "$tmpf" "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
}

# ---------------------------------------------------------------- skills
SKILL_DIRS=("${EXTRA_SKILL_DIRS[@]+"${EXTRA_SKILL_DIRS[@]}"}")
for d in .claude/skills .agents/skills .gemini/skills .cursor/skills .github/skills .opencode/skills; do
  SKILL_DIRS+=("$TARGET/$d" "$HOME/$d")
done

# Replace <user_id> in every Markdown file of the installed copies of a skill (SKILL.md and
# supporting files like known-issues.md) and drop the setup note that tells the agent to
# run this script.
fill_skill() {  # fill_skill skill_name user -> echoes updated files
  local name="$1" user="$2" d f tmpf
  for d in "${SKILL_DIRS[@]}"; do
    [ -d "$d/$name" ] || continue
    while IFS= read -r -d '' f; do
      grep -q '<user_id>' "$f" || continue
      tmpf="$f.tmp.$$"
      awk '
        /<!-- ssh-setup:start -->/ { skip = 1; next }
        /<!-- ssh-setup:end -->/ { skip = 0; drop_blank = 1; next }
        drop_blank && $0 == "" { drop_blank = 0; next }
        { drop_blank = 0 }
        !skip
      ' "$f" |
        sed "s/<user_id>/$user/g" > "$tmpf" && mv "$tmpf" "$f"
      echo "$f"
    done < <(find "$d/$name" -type f -name '*.md' -print0)
  done
}

# ---------------------------------------------------------------- per-server setup
RESULTS=()

finish_ok() {  # finish_ok id "skills" user message
  local files skill
  RESULTS+=("$1: $4")
  [ -n "$3" ] || return 0
  files="$(for skill in $2; do fill_skill "$skill" "$3"; done)"
  if [ -n "$files" ]; then
    echo "  Filled in user '$3' in:"
    sed 's/^/    /' <<< "$files"
  fi
}

setup_server() {
  local id name hosts patterns hostname skill
  IFS='|' read -r id name hosts patterns hostname skill <<< "$1"
  local first_host="${hosts%% *}" ids user rc key

  echo
  echo "==== $name"
  if [ "$id" = department ]; then
    echo "  All department servers share one home directory, so one key covers every node."
  fi
  if ! ask_yn "Do you have an account on $name?" n; then
    RESULTS+=("$id: skipped (no account)")
    return
  fi

  # Existing ~/.ssh/config entry with an identity file?
  ids="$(configured_identities "$first_host")"
  if [ -n "$ids" ]; then
    user="$(ssh_opt "$first_host" user)"
    echo "  Found an ssh config entry: user '$user', key $(echo $ids | sed 's/ /, /g')"
    check_any "$hosts"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      echo "  Key login to $CHECKED_HOST works."
      finish_ok "$id" "$skill" "$user" "already set up (user $user)"
      return
    fi
    report_failure "$rc"
    if [ "$rc" -eq 2 ]; then
      RESULTS+=("$id: could not connect; rerun when the server is reachable")
      return
    fi
  fi

  echo "  No valid key pair was found for $name."
  if [ "$id" = bridges2 ]; then
    # PSC doesn't take keys via ssh-copy-id; they are registered through its website.
    echo "  Bridges-2 keys must be registered with PSC rather than copied with ssh-copy-id."
    echo "  Follow PSC's instructions for adding a key:"
    echo "    https://www.psc.edu/about-using-ssh/ (\"Authenticating using a public-private key pair\")"
    echo "  Then add an entry like this to $SSH_CONFIG:"
    echo "    Host bridges2 bridges2.psc.edu"
    echo "        HostName bridges2.psc.edu"
    echo "        User <your PSC username>"
    echo "        IdentityFile <path to your private key>"
    echo "  and rerun this script with --only bridges2 to check it and fill in the skill."
    RESULTS+=("$id: no working key; follow PSC's ssh key instructions, then rerun with --only bridges2")
    return
  fi
  if ! ask_yn "Set one up now?" y; then
    RESULTS+=("$id: skipped (no key set up)")
    return
  fi

  local default_user="${user:-}"
  while :; do
    if [ -n "$default_user" ]; then
      user="$(ask "  Your username on $name [$default_user]: " "$default_user")"
    else
      user="$(ask "  Your username on $name: " "")"
    fi
    [[ "$user" =~ ^[A-Za-z_][A-Za-z0-9._-]*$ ]] && break
    echo "  Please enter a valid username."
  done

  key="$SSH_DIR/id_ed25519_$id"
  mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"
  if [ -f "$key" ]; then
    echo "  Reusing existing key $key"
    [ -f "$key.pub" ] || ssh-keygen -y -f "$key" > "$key.pub"
  else
    # No passphrase: agents run ssh non-interactively and couldn't type one.
    ssh-keygen -q -t ed25519 -N "" -C "$user@$id ($(hostname))" -f "$key" < "$TTY" ||
      { RESULTS+=("$id: FAILED (ssh-keygen)"); return; }
    echo "  Created key $key"
  fi

  echo "  Copying the public key to $user@$first_host. Enter your $name password if asked."
  ssh-copy-id -i "$key.pub" -o StrictHostKeyChecking=accept-new "$user@$first_host" < "$TTY" ||
    echo "  ssh-copy-id did not succeed."

  check_any "$hosts" -l "$user" -i "$key" -o IdentitiesOnly=yes
  rc=$?
  if [ "$rc" -ne 0 ]; then
    report_failure "$rc"
    RESULTS+=("$id: FAILED (key login did not work; key kept at $key)")
    return
  fi
  echo "  Key login to $CHECKED_HOST works."

  write_config_block "$id" "$patterns" "$hostname" "$user" "$key"
  echo "  Added an entry to $SSH_CONFIG"
  if check_any "$hosts"; then
    echo "  Verified: 'ssh $CHECKED_HOST' logs in without a password."
    finish_ok "$id" "$skill" "$user" "set up (user $user, key $key)"
  else
    report_failure $?
    RESULTS+=("$id: key works but the $SSH_CONFIG entry did not; check that file for conflicting entries")
  fi
}

echo "This script sets up passwordless ssh login to the servers your agent's skills use."
for entry in "${SERVERS[@]}"; do
  if [ -n "$ONLY" ] && [[ ",$ONLY," != *",${entry%%|*},"* ]]; then continue; fi
  setup_server "$entry"
done

echo
echo "Summary:"
for r in "${RESULTS[@]+"${RESULTS[@]}"}"; do echo "  $r"; done
[ "$CONFIG_BACKED_UP" = 1 ] && echo "  (previous ~/.ssh/config backed up next to it as config.bak.*)"
exit 0
