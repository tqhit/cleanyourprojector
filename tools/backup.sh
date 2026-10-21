#!/usr/bin/env bash
# Save what is needed to undo everything: package lists, disabled list, properties, settings, Home.
# Writes backup/<model>-<date>/ (git-ignored: it holds the serial number and MAC address).
# Usage: tools/backup.sh <ip[:port] | adb serial>
set -eu
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tools/_adb.sh
. tools/_adb.sh "${1:-}"
OUT="backup/$(model_slug)-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
Q pm list packages -f -U > "$OUT/packages.txt"
Q pm list packages -d > "$OUT/disabled.txt"
Q pm list packages -3 > "$OUT/third-party.txt"
Q getprop > "$OUT/getprop.txt"
for ns in global secure system; do Q settings list "$ns" > "$OUT/settings-$ns.txt"; done
Q cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME > "$OUT/home.txt"
Q device_config list activity_manager > "$OUT/device_config-activity_manager.txt" || true
Q "dumpsys package dexopt" > "$OUT/dexopt.txt" || true
adb -s "$DEV" exec-out screencap -p > "$OUT/screen.png" 2>/dev/null || true
echo "saved to $OUT ($(wc -l < "$OUT/packages.txt" | tr -d ' ') packages, $(wc -l < "$OUT/disabled.txt" | tr -d ' ') already disabled)"
