#!/usr/bin/env bash
# audit-env-perms.sh — read-only audit of .env file permissions and AWS key
# patterns under a given path. Never mutates anything and never prints a
# secret value in full; matches are masked.
#
# Usage: ./audit-env-perms.sh [PATH]
#   PATH defaults to the current directory.

set -euo pipefail

ROOT="${1:-.}"

if [ ! -d "$ROOT" ]; then
  echo "error: '$ROOT' is not a directory" >&2
  exit 1
fi

echo "Scanning for .env files under: $ROOT"
echo

mask_line() {
  # Replace the value after the first '=' with a fixed-length mask so the
  # key pattern that triggered the finding is visible but the secret is not.
  sed -E 's/(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16})/[MASKED_AWS_KEY]/g'
}

finding_count=0

while IFS= read -r -d '' file; do
  mode="$(stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file" 2>/dev/null || echo '???')"
  owner="$(stat -f '%Su' "$file" 2>/dev/null || stat -c '%U' "$file" 2>/dev/null || echo '???')"

  issue=""
  if [ "$mode" != "600" ] && [ "$mode" != "???" ]; then
    issue="mode=$mode (expected 600)"
  fi

  # Group- or world-readable/writable bits set (anything beyond owner rw).
  case "$mode" in
    *[1-7][0-7]|*[1-7][0-7][0-7])
      if [ -n "$issue" ]; then
        issue="$issue, group/world permission bits set"
      else
        issue="group/world permission bits set"
      fi
      ;;
  esac

  if [ -n "$issue" ]; then
    finding_count=$((finding_count + 1))
    echo "[PERMISSIONS] $file"
    echo "  owner: $owner  mode: $mode  issue: $issue"
    echo "  fix: chmod 600 \"$file\" && chown <service-user> \"$file\""
    echo
  fi

  if grep -qE 'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}' "$file" 2>/dev/null; then
    finding_count=$((finding_count + 1))
    echo "[AWS KEY PATTERN] $file"
    grep -nE 'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}' "$file" 2>/dev/null | mask_line | sed 's/^/  /'
    echo "  fix: move AWS credentials to an instance role / Secrets Manager;"
    echo "       if this key is real, deactivate and rotate it immediately"
    echo "       (see references/secrets-and-env.md)."
    echo
  fi
done < <(find "$ROOT" -type f -name ".env*" ! -name ".env.example" -print0 2>/dev/null)

echo "----------------------------------------"
if [ "$finding_count" -eq 0 ]; then
  echo "No findings. All .env files (if any) look correctly scoped and permissioned."
  exit 0
else
  echo "Findings: $finding_count"
  exit 2
fi
