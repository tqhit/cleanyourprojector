#!/usr/bin/env bash
# Classify every package on the device so a debloat list can be written for a model nobody has done yet.
# Prints a summary and writes backup/<model>-inventory.tsv with one row per package. Changes nothing.
# The "suggest" column is a starting point, not a verdict: check anything vendor-specific with
# `adb shell dumpsys package <name>` before disabling it, and never open packages named factory/test/fac.
# Usage: tools/inventory.sh <ip[:port] | adb serial>
set -eu
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tools/_adb.sh
. tools/_adb.sh "${1:-}"
mkdir -p backup
OUT="backup/$(model_slug)-inventory.tsv"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
Q dumpsys package packages > "$TMP/dump"
Q pm list packages -d | sed 's/package://' > "$TMP/disabled"
Q pm list packages -3 | sed 's/package://' > "$TMP/third"
Q ps -A -o RSS,NAME | awk 'NR>1{print $2"\t"int($1/1024)}' > "$TMP/rss"
for c in LEANBACK_LAUNCHER LAUNCHER HOME; do
  Q cmd package query-activities --brief -a android.intent.action.MAIN -c "android.intent.category.$c" | grep -o '^ *[A-Za-z0-9_.]*/' | tr -d ' /' | sort -u > "$TMP/$c"
done
indicators package | cut -f1,2 > "$TMP/ind"

# Name patterns, first match wins (core keep, projector keep, bloat, optional, then generic TV keep). keep = the projector needs it; bloat = safe to disable on a projector;
# review = vendor code you have to look at; optional = depends on what you use.
cat > "$TMP/rules" <<'RULES'
keep	^android$|^com\.android\.(systemui|settings|providers\.(settings|media|downloads|tv|media\.module)|shell|bluetooth|networkstack|permissioncontroller|packageinstaller|inputdevices|externalstorage|webview|wifi|se|keychain|location\.fused|tv\.settings|server\.telecom|phone|inputmethod|intentresolver|ext\.|connectivity|uwb|vpndialogs|captiveportallogin|certinstaller|mtp|proxyhandler|pacprocessor|localtransport|sharedstoragebackup|backupconfirm|statementservice|modulemetadata|cts|tv\.overlay|tv\.frameworkpackagestubs|safetycenter|remoteprovisioner|sdksandbox|companiondevicemanager|dreams\.basic|htmlviewer|keychain|soundpicker|carrierconfig|emergency|nfc)
keep	^com\.google\.android\.(gms|gsf|ext\.|configupdater|packageinstaller|webview|tv\.remote|tvlauncher|apps\.tv\.launcherx|inputmethod|leanbacklauncher\.recommendations)|^com\.android\.vending$
keep	keystone|tcorrection|correction|autofocus|focus|projector|projection|gsensor|motor
bloat	^com\.android\.(printspooler|musicfx|providers\.(calendar|contacts|userdictionary)|wallpaperbackup|camera2|deskclock|gallery3d|dynsystem|hotspot2|email|calendar|contacts|dialer|mms|messaging|stk|cellbroadcast|bips|bookmarkprovider|egg|wallpaper|managedprovisioning|healthconnect|health\.connect|cameraextensions|nearby\.halfsheet|adservices|ondevicepersonalization|federatedcompute)
bloat	^com\.google\.android\.(syncadapters|feedback|partnersetup|onetimeinitializer|backuptransport|tvrecommendations|atv\.widget|landscape|apps\.tv\.dreamx|tv\.feedbackconsent|marvin)
bloat	factory|factorytest|fac$|\.fac\.|test$|\.test|demo|guide|feedback|report|analytics|stats|ota\.report|deviceinfo|deviceportal|oemservice
optional	youtube|netflix|amazon|primevideo|disney|hulu|hbo|iqiyi|vtv|fpt|tv360|chrome|browser|mxtech|vlc|kodi|spotify|katniss|assistant|voice|mediashell|chromecast|cast|airplay|airpin|dlna|miracast|mirror|screenshare|usbdisplay|quickshare|updater|upgrade|ota|music|video|gallery|filemanager|filebrowser|file
keep	tvinput|tv\.settings|tvsettings|livetv|\.tv$|hdmi|cec|inputmethod|ime|keyboard|remote|rcu|bluetooth|btservice|audio|dolby|display|systemcontrol|droidlogic$|droidlogic\.(tv|overlay|systemui|inputmethod|tvinput|android\.tv|FileBrower|videoplayer)|jmlauncher|setupwizard|setupwraith|tungsten
RULES

PKGS=$(Q pm list packages -U | sed 's/package://; s/ uid:/\t/')
printf 'package\tsuggest\tstate\tsource\tuid\tpartition\trss_mb\tleanback\tlauncher\thome\tflags\treason\n' > "$OUT"
while IFS=$'\t' read -r pkg uid; do
  [ -n "$pkg" ] || continue
  BLOCK=$(awk -v p="  Package [$pkg]" 'index($0,p)==1{f=1; print; next} f && /^  Package \[/{exit} f' "$TMP/dump")
  part=$(printf '%s' "$BLOCK" | sed -n 's/.*codePath=\/\([a-z_]*\)\/.*/\1/p' | head -1)
  flags=""
  for perm in INSTALL_PACKAGES:install DELETE_PACKAGES:delete RECEIVE_BOOT_COMPLETED:boot SYSTEM_ALERT_WINDOW:overlay WRITE_SECURE_SETTINGS:securesettings INTERNET:net RECORD_AUDIO:mic CAMERA:camera ACCESS_FINE_LOCATION:location READ_LOGS:logs PACKAGE_USAGE_STATS:usage; do
    printf '%s' "$BLOCK" | grep -q "android.permission.${perm%%:*}: granted=true" && flags="$flags,${perm##*:}"
  done
  printf '%s' "$BLOCK" | grep -q 'BIND_ACCESSIBILITY_SERVICE' && flags="$flags,a11y"
  printf '%s' "$BLOCK" | grep -q 'PERSISTENT' && flags="$flags,persistent"
  state=enabled; grep -qx "$pkg" "$TMP/disabled" && state=disabled
  src=system; grep -qx "$pkg" "$TMP/third" && src=user
  rss=$(awk -v p="$pkg" '$1==p{print $2; exit}' "$TMP/rss")
  lb=$(grep -qx "$pkg" "$TMP/LEANBACK_LAUNCHER" && echo y || true)
  la=$(grep -qx "$pkg" "$TMP/LAUNCHER" && echo y || true)
  ho=$(grep -qx "$pkg" "$TMP/HOME" && echo y || true)
  sev=$(awk -F'\t' -v p="$pkg" '$1==p{print $2; exit}' "$TMP/ind")
  if [ -n "$sev" ]; then suggest=bloat; reason="data/indicators.tsv ($sev)"
  else
    suggest=$(awk -F'\t' -v p="$pkg" '{ if (p ~ $2) { print $1; exit } }' "$TMP/rules")
    reason="name pattern"
    if [ -z "$suggest" ]; then
      suggest=review; reason="vendor package"
      case "$pkg" in com.android.*|com.google.*) reason="AOSP/Google, not in the known lists" ;; esac
    fi
  fi
  [ "$ho" = y ] && [ "$suggest" != keep ] && { suggest=review; reason="claims HOME: replace it before disabling"; }
  case "$uid:$flags" in 1000:*install*) [ "$suggest" = review ] && reason="$reason; uid system + INSTALL_PACKAGES: can install silently" ;; esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$pkg" "$suggest" "$state" "$src" "$uid" "$part" "${rss:-}" "$lb" "$la" "$ho" "${flags#,}" "$reason" >> "$OUT"
done <<< "$PKGS"

for s in bloat review optional keep; do
  N=$(awk -F'\t' -v s="$s" 'NR>1 && $2==s && $3=="enabled"' "$OUT" | wc -l | tr -d ' ')
  printf '\n== %s (%s enabled)\n' "$s" "$N"
  [ "$s" = keep ] && { echo "   (not listed; see the file)"; continue; }
  awk -F'\t' -v s="$s" 'NR>1 && $2==s && $3=="enabled"{printf "   %-48s %-7s %4s MB  %s\n", $1, $4, ($7==""?"-":$7), $11}' "$OUT"
done
echo; echo "full table: $OUT"
