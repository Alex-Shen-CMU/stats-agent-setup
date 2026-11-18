#!/usr/bin/env bash
# Set up the GitHub MCP server for a Claude Code project.
#
# - Adds a "github" server to <project>/.mcp.json that reads the token from the
#   ${GITHUB_PERSONAL_ACCESS_TOKEN} environment variable (the token itself is never
#   written to .mcp.json, so that file is safe to commit).
# - Stores the token in <project>/.claude/settings.local.json (under "env"), which is
#   personal and not meant to be committed.
# - Adds .claude/settings.local.json to .gitignore if git isn't already ignoring it (opt out
#   with --no-gitignore).
# - The token is typed at a hidden prompt, so it never appears in terminal output.
# - If the github server is already configured, says so and asks whether to replace the
#   token on file.
#
# Usage (from your project directory):
#   curl -fsSL https://raw.githubusercontent.com/Alex-Shen-CMU/stats-agent-setup/main/github_mcp.sh | bash
#   bash github_mcp.sh [--dir PATH]
#
# Options:
#   --dir PATH       project to set up (default: current directory)
#   --no-gitignore   don't add .claude/settings.local.json to .gitignore
set -uo pipefail

TARGET="$PWD"
VAR_NAME="GITHUB_PERSONAL_ACCESS_TOKEN"
UPDATE_GITIGNORE=1

die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) TARGET="${2:-}"; shift 2 ;;
    --no-gitignore) UPDATE_GITIGNORE=0; shift ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null || true; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[ -d "$TARGET" ] || die "directory does not exist: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"
command -v python3 >/dev/null 2>&1 || die "python3 not found; it is needed to edit the JSON files"

# When piped through `curl | bash`, stdin is the script itself, so prompts read from the terminal.
(: < /dev/tty) 2>/dev/null || die "this script is interactive and needs a terminal"
TTY=/dev/tty

MCP_JSON="$TARGET/.mcp.json"
SETTINGS_DIR="$TARGET/.claude"
SETTINGS_JSON="$SETTINGS_DIR/settings.local.json"

# py_json: run a small python program on the two files. Values travel via the environment,
# never argv, so the token doesn't show up in `ps`.
py() { python3 -I -c "$1"; }

# ---------------------------------------------------------------- inspect existing state
HAS_SERVER=0
HAS_TOKEN=0
if [ -f "$MCP_JSON" ]; then
  MCP_JSON="$MCP_JSON" py '
import json, os, sys
try:
    d = json.load(open(os.environ["MCP_JSON"]))
except Exception as e:
    sys.exit(2)
sys.exit(0 if "github" in d.get("mcpServers", {}) else 1)
'
  case $? in
    0) HAS_SERVER=1 ;;
    2) die "$MCP_JSON exists but is not valid JSON; fix or remove it and re-run" ;;
  esac
fi
if [ -f "$SETTINGS_JSON" ]; then
  SETTINGS_JSON="$SETTINGS_JSON" VAR_NAME="$VAR_NAME" py '
import json, os, sys
try:
    d = json.load(open(os.environ["SETTINGS_JSON"]))
except Exception:
    sys.exit(2)
sys.exit(0 if d.get("env", {}).get(os.environ["VAR_NAME"]) else 1)
'
  case $? in
    0) HAS_TOKEN=1 ;;
    2) die "$SETTINGS_JSON exists but is not valid JSON; fix or remove it and re-run" ;;
  esac
fi

ask_yn() {  # ask_yn "question" y|n -> 0 for yes
  local hint="[y/N]" reply
  [ "$2" = y ] && hint="[Y/n]"
  while :; do
    printf '%s %s: ' "$1" "$hint" > "$TTY"
    read -r reply < "$TTY" || true
    reply="${reply:-$2}"
    case "$reply" in
      y|Y|yes|Yes|YES) return 0 ;;
      n|N|no|No|NO) return 1 ;;
      *) echo "Please answer y or n." > "$TTY" ;;
    esac
  done
}

if [ "$HAS_SERVER" = 1 ] && [ "$HAS_TOKEN" = 1 ]; then
  echo "The GitHub MCP server is already set up in this project ($MCP_JSON)"
  echo "and a token is stored in $SETTINGS_JSON."
  ask_yn "Replace the GitHub token on file?" n || { echo "Nothing changed."; exit 0; }
elif [ "$HAS_SERVER" = 1 ]; then
  echo "The GitHub MCP server is already in $MCP_JSON, but no token is stored in $SETTINGS_JSON."
fi

# ---------------------------------------------------------------- read the token (hidden)
echo
echo "Create a personal access token at https://github.com/settings/personal-access-tokens"
echo "(fine-grained, with access to this repository and Issues read/write), then paste it below."
echo "Input is hidden."
TOKEN=""
while [ -z "$TOKEN" ]; do
  printf 'GitHub token: ' > "$TTY"
  IFS= read -rs TOKEN < "$TTY" || die "could not read the token"
  echo > "$TTY"
  # strip stray whitespace/CR from pasting
  TOKEN="$(printf '%s' "$TOKEN" | tr -d '[:space:]')"
  [ -n "$TOKEN" ] || echo "The token cannot be empty." > "$TTY"
done

# ---------------------------------------------------------------- write the files
mkdir -p "$SETTINGS_DIR" || die "could not create $SETTINGS_DIR"

if [ "$HAS_SERVER" = 0 ]; then
  MCP_JSON="$MCP_JSON" VAR_NAME="$VAR_NAME" py '
import json, os
path = os.environ["MCP_JSON"]
try:
    d = json.load(open(path))
except FileNotFoundError:
    d = {}
d.setdefault("mcpServers", {})["github"] = {
    "type": "http",
    "url": "https://api.githubcopilot.com/mcp/",
    "headers": {"Authorization": "Bearer ${%s}" % os.environ["VAR_NAME"]},
}
with open(path, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
' || die "could not write $MCP_JSON"
  echo "Wrote GitHub MCP server to $MCP_JSON"
fi

SETTINGS_JSON="$SETTINGS_JSON" VAR_NAME="$VAR_NAME" GH_TOKEN_VALUE="$TOKEN" py '
import json, os
path = os.environ["SETTINGS_JSON"]
try:
    d = json.load(open(path))
except FileNotFoundError:
    d = {}
d.setdefault("env", {})[os.environ["VAR_NAME"]] = os.environ["GH_TOKEN_VALUE"]
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
os.chmod(path, 0o600)
' || die "could not write $SETTINGS_JSON"
unset TOKEN
echo "Stored the token in $SETTINGS_JSON (permissions 600)"

# ---------------------------------------------------------------- gitignore
# Keep the token out of git: add settings.local.json to .gitignore unless it is already
# ignored (or the user passed --no-gitignore).
if [ "$UPDATE_GITIGNORE" = 1 ] && git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ! git -C "$TARGET" check-ignore -q "$SETTINGS_JSON"; then
    GITIGNORE="$TARGET/.gitignore"
    # make sure we start on a fresh line if the file lacks a trailing newline
    [ -s "$GITIGNORE" ] && [ -n "$(tail -c1 "$GITIGNORE")" ] && echo >> "$GITIGNORE"
    echo ".claude/settings.local.json" >> "$GITIGNORE"
    echo
    echo "Note: .claude/settings.local.json was not ignored by git, so I added it to"
    echo "$GITIGNORE to keep your token from being committed."
    echo "(To skip this next time, pass --no-gitignore.)"
  fi
fi

echo
echo "Done. Restart Claude Code in this project and approve the 'github' MCP server when asked."
