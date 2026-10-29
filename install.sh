#!/usr/bin/env bash
# Install one of this repo's agent instruction templates (instructions/*.md) and its
# skills (skills/) into the current project, named for the coding agent you use.
#
# Usage (from your project directory):
#   curl -fsSL https://raw.githubusercontent.com/Alex-Shen-CMU/stats-agent-setup/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --agent codex     # skip the menu
#
# Options:
#   --agent NAME   claude | codex | gemini | cursor | copilot | opencode | other
#   --instructions NAME  instruction template from instructions/ (e.g. computational)
#   --name NAME    project name (default: name of the project directory)
#   --description TEXT   project description (default: none)
#   --dir PATH     project to install into (default: current directory)
#   --ref REF      branch, tag or commit to download (default: main)
#   --force        overwrite existing files without asking
#
# Environment overrides: AGENT_SETUP_REPO (owner/name), AGENT_SETUP_REF.
set -euo pipefail

REPO="${AGENT_SETUP_REPO:-Alex-Shen-CMU/stats-agent-setup}"
REF="${AGENT_SETUP_REF:-main}"
TARGET="$PWD"
AGENT=""
TEMPLATE=""
PROJECT_NAME=""
PROJECT_DESC=""
PROJECT_DESC_SET=0
FORCE=0

die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="${2:-}"; shift 2 ;;
    --instructions) TEMPLATE="${2:-}"; shift 2 ;;
    --name) PROJECT_NAME="${2:-}"; shift 2 ;;
    --description) PROJECT_DESC="${2:-}"; PROJECT_DESC_SET=1; shift 2 ;;
    --dir) TARGET="${2:-}"; shift 2 ;;
    --ref) REF="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null || true; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[ -d "$TARGET" ] || die "target directory does not exist: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"

# When piped through `curl | bash`, stdin is the script itself, so prompts read from the terminal.
if (: < /dev/tty) 2>/dev/null; then TTY=/dev/tty; else TTY=""; fi
ask() {  # ask "prompt" default -> echoes answer
  local reply=""
  if [ -n "$TTY" ]; then
    printf '%s' "$1" > "$TTY"
    read -r reply < "$TTY" || true
  fi
  echo "${reply:-$2}"
}

# ---------------------------------------------------------------- source files
# Use the local checkout if this script is run from one; otherwise download the repo.
SRC=""
script_path="${BASH_SOURCE[0]:-}"
if [ -n "$script_path" ] && [ -f "$script_path" ]; then
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  if [ -d "$script_dir/instructions" ] && [ -d "$script_dir/skills" ]; then
    SRC="$script_dir"
  fi
fi

if [ -z "$SRC" ]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  url="https://github.com/$REPO/archive/$REF.tar.gz"
  echo "Downloading $url"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" | tar -xz --strip-components=1 -C "$TMP" || die "could not download $url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$url" | tar -xz --strip-components=1 -C "$TMP" || die "could not download $url"
  else
    die "need curl or wget to download $REPO"
  fi
  SRC="$TMP"
fi

[ -d "$SRC/instructions" ] || die "instructions/ not found in $SRC"
[ -d "$SRC/skills" ] || die "skills/ not found in $SRC"

# ---------------------------------------------------------------- agent choice
# Each agent: instructions file name and project-level skills directory.
agent_paths() {
  case "$1" in
    claude)   echo "CLAUDE.md .claude/skills" ;;
    codex)    echo "AGENTS.md .agents/skills" ;;
    gemini)   echo "GEMINI.md .gemini/skills" ;;
    cursor)   echo "AGENTS.md .cursor/skills" ;;
    copilot)  echo "AGENTS.md .github/skills" ;;
    opencode) echo "AGENTS.md .opencode/skills" ;;
    *) return 1 ;;
  esac
}

if [ -z "$AGENT" ]; then
  [ -n "$TTY" ] || die "no terminal to prompt on; pass --agent NAME"
  cat > "$TTY" <<'EOF'
Which coding agent do you use?
  1) Claude Code
  2) OpenAI Codex
  3) Gemini CLI
  4) Cursor
  5) GitHub Copilot
  6) OpenCode
  7) Other
EOF
  case "$(ask 'Choice [1-7]: ' '')" in
    1) AGENT=claude ;;
    2) AGENT=codex ;;
    3) AGENT=gemini ;;
    4) AGENT=cursor ;;
    5) AGENT=copilot ;;
    6) AGENT=opencode ;;
    7) AGENT=other ;;
    *) die "invalid choice" ;;
  esac
fi

AGENT="$(echo "$AGENT" | tr '[:upper:]' '[:lower:]')"
if [ "$AGENT" = other ]; then
  echo "Most agents read AGENTS.md and the cross-agent .agents/skills/ directory." > "${TTY:-/dev/stderr}"
  INSTR="$(ask 'Instructions file name [AGENTS.md]: ' AGENTS.md)"
  SKILLS="$(ask 'Skills directory [.agents/skills]: ' .agents/skills)"
  AGENT_NAME="$(ask 'Agent name, used for commit prefixes and the scratch directory [agent]: ' agent)"
else
  paths="$(agent_paths "$AGENT")" || die "unknown agent: $AGENT"
  read -r INSTR SKILLS <<< "$paths"
  AGENT_NAME="$AGENT"
fi

# ---------------------------------------------------------------- instructions template
templates=()
for f in "$SRC"/instructions/*.md; do [ -f "$f" ] && templates+=("$(basename "$f" .md)"); done
[ "${#templates[@]}" -gt 0 ] || die "no instruction templates found in $SRC/instructions"

if [ -z "$TEMPLATE" ]; then
  if [ "${#templates[@]}" -eq 1 ]; then
    TEMPLATE="${templates[0]}"
  else
    [ -n "$TTY" ] || die "no terminal to prompt on; pass --instructions NAME"
    echo "Which agent instructions do you want?" > "$TTY"
    for i in "${!templates[@]}"; do echo "  $((i + 1))) ${templates[$i]}" > "$TTY"; done
    n="$(ask "Choice [1-${#templates[@]}]: " '')"
    case "$n" in ''|*[!0-9]*) die "invalid choice" ;; esac
    [ "$n" -ge 1 ] && [ "$n" -le "${#templates[@]}" ] || die "invalid choice"
    TEMPLATE="${templates[$((n - 1))]}"
  fi
fi
TEMPLATE="${TEMPLATE%.md}"
TEMPLATE_FILE="$SRC/instructions/$TEMPLATE.md"
[ -f "$TEMPLATE_FILE" ] || die "unknown instructions: $TEMPLATE (available: ${templates[*]})"
echo "Using instructions: $TEMPLATE" > "${TTY:-/dev/stderr}"

default_name="$(basename "$TARGET")"
[ -n "$PROJECT_NAME" ] || PROJECT_NAME="$(ask "Project name [$default_name]: " "$default_name")"
[ "$PROJECT_DESC_SET" = 1 ] || PROJECT_DESC="$(ask 'Project description (optional): ' '')"

# ---------------------------------------------------------------- install
# Fill the <agent> placeholder and point references to CLAUDE.md at the renamed instructions file.
rename_refs() {
  local f tmpf
  for f in "$@"; do
    tmpf="$f.tmp.$$"
    sed -e "s|<agent>|$AGENT_NAME|g" -e "s|CLAUDE\.md|$INSTR|g" "$f" > "$tmpf" && mv "$tmpf" "$f"
  done
}

confirm_overwrite() {  # confirm_overwrite path -> 0 to overwrite
  [ "$FORCE" = 1 ] && return 0
  [ -n "$TTY" ] || return 1
  case "$(ask "$1 already exists. Overwrite? [y/N]: " n)" in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

# Fill the template's placeholders; drop the description line (and the blank after it) if empty.
render_instructions() {  # render_instructions out_path
  local line skip_blank=0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$skip_blank" = 1 ]; then
      skip_blank=0
      [ -z "$line" ] && continue
    fi
    if [ "$line" = "<optional project description>" ] && [ -z "$PROJECT_DESC" ]; then
      skip_blank=1
      continue
    fi
    line="${line//"<optional project name>"/"$PROJECT_NAME"}"
    line="${line//"<optional project description>"/"$PROJECT_DESC"}"
    line="${line//"<agent>"/"$AGENT_NAME"}"
    line="${line//"<path>"/"$SKILLS/<skill-name>"}"
    printf '%s\n' "$line"
  done < "$TEMPLATE_FILE" > "$1"
}

RENDERED="$(mktemp)"
trap 'rm -rf "${TMP:-}" "$RENDERED"' EXIT
render_instructions "$RENDERED"

installed=()
skipped=()

instr_path="$TARGET/$INSTR"
mkdir -p "$(dirname "$instr_path")"
if [ -e "$instr_path" ] && [ "$FORCE" != 1 ]; then
  choice="s"
  if [ -n "$TTY" ]; then
    choice="$(ask "$INSTR already exists. [a]ppend, [o]verwrite or [s]kip? [s]: " s)"
  fi
  case "$choice" in
    a|A) { echo; cat "$RENDERED"; } >> "$instr_path"; installed+=("$INSTR (appended)") ;;
    o|O) cp "$RENDERED" "$instr_path"; installed+=("$INSTR") ;;
    *) skipped+=("$INSTR") ;;
  esac
else
  cp "$RENDERED" "$instr_path"
  installed+=("$INSTR")
fi

mkdir -p "$TARGET/$SKILLS"
for skill_src in "$SRC"/skills/*/; do
  name="$(basename "$skill_src")"
  dest="$TARGET/$SKILLS/$name"
  if [ -e "$dest" ]; then
    if confirm_overwrite "$SKILLS/$name"; then rm -rf "$dest"; else skipped+=("$SKILLS/$name"); continue; fi
  fi
  cp -R "$skill_src" "$dest"
  while IFS= read -r -d '' f; do rename_refs "$f"; done < <(find "$dest" -type f -name '*.md' -print0)
  installed+=("$SKILLS/$name")
done

echo
echo "Installed into $TARGET for agent: $AGENT (instructions: $TEMPLATE)"
for x in "${installed[@]+"${installed[@]}"}"; do echo "  + $x"; done
for x in "${skipped[@]+"${skipped[@]}"}"; do echo "  - skipped $x (already exists)"; done
