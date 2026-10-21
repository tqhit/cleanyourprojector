#!/usr/bin/env bash
# Build the cleanyourtv launcher (upstream/cleanyourtv, MIT) with a device's config.xml, install it as Home
# and disable the stock launcher. Handles JM firmware, where Home goes through com.jm.jmlauncher and
# persist.sys.home.selectpkg instead of the normal HOME default.
# Usage: tools/install-launcher.sh <ip[:port]> devices/<model>
set -eu
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tools/_adb.sh
. tools/_adb.sh "${1:-}"
DEVDIR="${2:?usage: tools/install-launcher.sh <ip> devices/<model>}"
[ -f "$DEVDIR/config.xml" ] || { echo "$DEVDIR/config.xml missing" >&2; exit 1; }
[ -f upstream/cleanyourtv/launcher/gradlew ] || git submodule update --init

MIN=$(sed -n 's/^ *minSdk *\([0-9]*\).*/\1/p' upstream/cleanyourtv/launcher/app/build.gradle | head -1)
SDK=$(S getprop ro.build.version.sdk)
[ "$SDK" -ge "$MIN" ] || { echo "device API $SDK < launcher minSdk $MIN: cannot install" >&2; exit 1; }

# Stock Home, read before anything changes it.
if S pm list packages -e | grep -qx package:com.jm.jmlauncher; then
  STOCK=$(S getprop persist.sys.home.selectpkg); JM=1
else
  STOCK=$(S cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1 | cut -d/ -f1); JM=0
fi
[ "$STOCK" = com.gathin.tvhome ] && STOCK=$(S getprop persist.cyp.stock_launcher)
echo "stock launcher: ${STOCK:-unknown}"

BUILD=build/launcher
rm -rf "$BUILD"; mkdir -p build; cp -R upstream/cleanyourtv/launcher "$BUILD"
cp "$DEVDIR/config.xml" "$BUILD/app/src/main/res/values/config.xml"
if [ -z "${JAVA_HOME:-}" ]; then
  for j in /opt/homebrew/opt/openjdk@17 /usr/local/opt/openjdk@17 "$(/usr/libexec/java_home -v 17 2>/dev/null || true)"; do
    [ -x "$j/bin/java" ] && JAVA_HOME=$j && break
  done
fi
export JAVA_HOME="${JAVA_HOME:?install JDK 17 (brew install openjdk@17)}"
for a in "${ANDROID_HOME:-}" ~/Library/Android/sdk ~/Android/Sdk /opt/homebrew/share/android-commandlinetools; do
  [ -n "$a" ] && [ -d "$a/platforms" ] && ANDROID_HOME=$a && break
done
export ANDROID_HOME="${ANDROID_HOME:?install the Android SDK (platform 34)}"
echo "sdk.dir=$ANDROID_HOME" > "$BUILD/local.properties"
(cd "$BUILD" && PATH="$JAVA_HOME/bin:$PATH" ./gradlew assembleRelease -q --console=plain)
APK="$BUILD/app/build/outputs/apk/release/app-release.apk"

adb -s "$DEV" push "$APK" /data/local/tmp/tvhome.apk >/dev/null
OUT=$(S 'pm install -r /data/local/tmp/tvhome.apk; rm -f /data/local/tmp/tvhome.apk')
echo "$OUT"; case "$OUT" in *Success*) ;; *) echo "install failed; stock launcher untouched" >&2; exit 1 ;; esac
S cmd package compile -m speed -f com.gathin.tvhome >/dev/null

# Apps without a leanback entry (phone Netflix, vendor settings) go in through the launcher's library file.
if [ -f "$DEVDIR/library_apps.txt" ]; then
  adb -s "$DEV" push "$DEVDIR/library_apps.txt" /data/local/tmp/library_apps.txt >/dev/null
  S 'd=/data/data/com.gathin.tvhome/files; u=$(stat -c %u /data/data/com.gathin.tvhome); mkdir -p $d && cp /data/local/tmp/library_apps.txt $d/ && chown -R $u:$u $d && rm /data/local/tmp/library_apps.txt' \
    || echo "could not seed library_apps.txt (needs root adb); add those apps from the launcher's app library"
fi

[ -n "$STOCK" ] && S setprop persist.cyp.stock_launcher "$STOCK"
[ "$JM" = 1 ] && S setprop persist.sys.home.selectpkg com.gathin.tvhome
S cmd package set-home-activity com.gathin.tvhome/.MainActivity >/dev/null
if [ -n "$STOCK" ] && [ "$STOCK" != android ]; then S pm disable-user --user 0 "$STOCK"; fi
S input keyevent KEYCODE_HOME; sleep 2; S input keyevent KEYCODE_HOME; sleep 2
S dumpsys activity activities | grep -m1 topResumedActivity
echo "If Home shows the stock launcher again after a reboot, run tools/harden.sh (its boot script re-disables it)."
