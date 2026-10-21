#!/usr/bin/env bash
# Speed-ups for 1 GB projectors. All reversible (see the end of this file).
# Usage: tools/optimize.sh <ip[:port]>
set -u
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tools/_adb.sh
. tools/_adb.sh "${1:-}"
S 'settings put global window_animation_scale 0.5; settings put global transition_animation_scale 0.5; settings put global animator_duration_scale 0.5'
# Default keeps 32 cached processes, far more than ~650 MB of usable RAM holds without swapping.
S 'device_config set_sync_disabled_for_tests persistent; device_config put activity_manager max_cached_processes 12'
# Background dexopt needs idle + charging, which a projector rarely reports: apps stay interpreted.
# Compile system UI fully, and the big apps with their profiles.
for p in $(S "pm list packages -s -e" | sed 's/package://' | grep -E '^(com\.android\.(systemui|tv\.settings)|com\.droidlogic\.(android\.tv|tv\.settings|inputmethod\.remote)|com\.htc\.htcsettings|com\.softwinner\.tcorrection|com\.jm\.jmlauncher|com\.master\.apps)$'); do
  printf '%-40s speed: ' "$p"; S cmd package compile -m speed -f "$p" | tail -1
done
for p in com.gathin.tvhome com.google.android.youtube.tv com.netflix.mediaclient com.android.vending; do
  S pm list packages -e | grep -qx "package:$p" || continue
  printf '%-40s speed-profile: ' "$p"; S cmd package compile -m speed-profile -f "$p" | tail -1
done
S sm fstrim
echo "optimized"
# Undo: animation scales back to 1.0; device_config delete activity_manager max_cached_processes;
# cmd package compile --reset <package>.
