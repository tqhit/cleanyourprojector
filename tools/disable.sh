#!/usr/bin/env bash
# Disable every package in a list for user 0 (never uninstalls). Undo with tools/restore.sh <same list>.
# Usage: tools/disable.sh <ip[:port]> devices/<model>/debloat.txt
set -u
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tools/_adb.sh
. tools/_adb.sh "${1:-}"
LIST="${2:?usage: tools/disable.sh <ip> <debloat list>}"
PKGS=$(pkgs "$LIST") || exit 1
for p in $PKGS; do
  printf '%-50s %s\n' "$p" "$(S pm disable-user --user 0 "$p" | tail -1)"
done
echo "disabled now: $(S pm list packages -d | wc -l | tr -d ' ') packages"
