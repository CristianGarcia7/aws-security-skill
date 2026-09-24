#!/usr/bin/env bash
# install.sh — install or uninstall the secure-app-baseline skill for one or
# more AI coding agents (Claude Code, Codex CLI, OpenCode, Pi, Kiro).
#
# The skill is copied, not symlinked, because symlink support is not
# documented for every agent. Copying always works.
#
# Usage:
#   ./install.sh                        Install globally, for all agents.
#   ./install.sh --project <dir>        Install into <dir>, for all agents.
#   ./install.sh --agents claude,codex  Install for only the named agents.
#   ./install.sh --uninstall            Remove the skill (same target rules).
#   ./install.sh --help                 Show this help.
#
# Works with bash 3.2 (macOS default) and Linux. Never uses sudo.

set -euo pipefail

SKILL_NAME="secure-app-baseline"

# Resolve the directory this script lives in, so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SKILL="$SCRIPT_DIR/skills/$SKILL_NAME"

PROJECT_DIR=""
AGENTS="claude,codex,opencode,pi,kiro"
UNINSTALL=0

usage() {
  cat <<'EOF'
install.sh — install or uninstall the secure-app-baseline skill for one or
more AI coding agents (Claude Code, Codex CLI, OpenCode, Pi, Kiro).

The skill is copied, not symlinked, because symlink support is not
documented for every agent. Copying always works.

Usage:
  ./install.sh                        Install globally, for all agents.
  ./install.sh --project <dir>        Install into <dir>, for all agents.
  ./install.sh --agents claude,codex  Install for only the named agents.
  ./install.sh --uninstall            Remove the skill (same target rules).
  ./install.sh --help                 Show this help.

Works with bash 3.2 (macOS default) and Linux. Never uses sudo.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || fail "--project requires a directory"
      PROJECT_DIR="$2"
      shift 2
      ;;
    --agents)
      [ $# -ge 2 ] || fail "--agents requires a value"
      AGENTS="$2"
      shift 2
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1 (see --help)"
      ;;
  esac
done

if [ -n "$PROJECT_DIR" ]; then
  [ -d "$PROJECT_DIR" ] || fail "--project directory does not exist: $PROJECT_DIR"
  BASE_DIR="$(cd "$PROJECT_DIR" && pwd)"
else
  BASE_DIR="$HOME"
fi

[ -f "$SOURCE_SKILL/SKILL.md" ] || fail "source skill not found at $SOURCE_SKILL"

# Map each requested agent name to its base folder (claude/codex/opencode/pi
# use .claude or .agents; kiro uses .kiro). Deduplicate the resulting folder
# list, since several agents share the same folder.
FOLDERS=""

add_folder() {
  local folder="$1"
  case " $FOLDERS " in
    *" $folder "*) ;; # already present
    *) FOLDERS="$FOLDERS $folder" ;;
  esac
}

OLD_IFS="$IFS"
IFS=','
for agent in $AGENTS; do
  case "$agent" in
    claude) add_folder ".claude" ;;
    codex) add_folder ".agents" ;;
    opencode) add_folder ".agents" ;;
    pi) add_folder ".agents" ;;
    kiro) add_folder ".kiro" ;;
    "") ;;
    *) IFS="$OLD_IFS"; fail "unknown agent: $agent (use claude, codex, opencode, pi, kiro)" ;;
  esac
done
IFS="$OLD_IFS"

[ -n "$FOLDERS" ] || fail "no valid agents resolved from: $AGENTS"

is_ours() {
  # $1 = path to an existing directory. Returns success only if it looks
  # like our own skill (has SKILL.md with the right name in frontmatter).
  local dir="$1"
  [ -f "$dir/SKILL.md" ] || return 1
  grep -Eq '^name: *secure-app-baseline *$' "$dir/SKILL.md" 2>/dev/null
}

remove_target() {
  # $1 = target skill directory path (e.g. ~/.claude/skills/secure-app-baseline)
  local target="$1"
  if [ -L "$target" ]; then
    rm "$target"
  elif [ -d "$target" ]; then
    if is_ours "$target"; then
      rm -rf "$target"
    else
      fail "refusing to remove $target: it does not look like our secure-app-baseline skill"
    fi
  fi
}

for folder in $FOLDERS; do
  SKILLS_DIR="$BASE_DIR/$folder/skills"
  TARGET="$SKILLS_DIR/$SKILL_NAME"

  if [ "$UNINSTALL" -eq 1 ]; then
    if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
      remove_target "$TARGET"
      echo "removed: $TARGET"
    else
      echo "skip (not installed): $TARGET"
    fi
    continue
  fi

  mkdir -p "$SKILLS_DIR"
  remove_target "$TARGET"
  cp -R "$SOURCE_SKILL" "$TARGET"
  echo "installed: $TARGET"
done

echo
if [ "$UNINSTALL" -eq 1 ]; then
  echo "Uninstall done. Restart your agent to stop seeing the skill."
else
  echo "Install done. Restart your agent to pick up the skill."
fi
