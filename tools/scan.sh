#!/usr/bin/env bash
# Read-only health and security scan of any Android projector (or TV box) over ADB. Changes nothing.
# Works without root; checks that need root say so instead of guessing.
# Usage: tools/scan.sh <ip[:port] | adb serial>
set -u
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tools/_adb.sh
. tools/_adb.sh "${1:-}"

BAD=0; WARN=0
bad(){  printf '  \033[31m[BAD]\033[0m  %s\n' "$*"; BAD=$((BAD + 1)); }
warn(){ printf '  \033[33m[WARN]\033[0m %s\n' "$*"; WARN=$((WARN + 1)); }
ok(){   printf '  \033[32m[OK]\033[0m   %s\n' "$*"; }
info(){ printf '         %s\n' "$*"; }
skip(){ printf '  [SKIP] %s (needs root adb)\n' "$*"; }
section(){ printf '\n== %s\n' "$*"; }
INIT_DIRS="/system/etc/init /vendor/etc/init /odm/etc/init /product/etc/init /system_ext/etc/init"

section "Device"
PLATFORM=$(Q getprop ro.board.platform); HW=$(Q getprop ro.hardware)
info "model:    $(Q getprop ro.product.manufacturer) $(Q getprop ro.product.model) (board $PLATFORM, hw $HW)"
info "android:  $(Q getprop ro.build.version.release) (API $(Q getprop ro.build.version.sdk)), $(Q getprop ro.build.type), $(Q getprop ro.build.display.id)"
case "$HW$PLATFORM" in
  *amlogic*|*meson*|*txhd*|*t95*|*sc2*|*s4*) FAMILY=amlogic ;;
  *sun*|*allwinner*|*h713*|*tv303*) FAMILY=allwinner ;;
  *rk3*|*rockchip*) FAMILY=rockchip ;;
  *mt5*|*mt9*|*mediatek*) FAMILY=mediatek ;;
  *) FAMILY=unknown ;;
esac
info "soc family: $FAMILY"
FP=$(Q getprop ro.build.fingerprint)
case "$FP" in google/redfin*|google/sunfish*|google/bramble*|google/coral*|google/flame*)
  warn "fingerprint claims a Google phone ($FP): certification spoofing, the firmware is not what it says" ;; esac
JM=0
if [ -n "$(Q getprop ro.jm.board.name)" ] || [ -n "$(Q ls /system/etc/init/ttyunos.rc)" ]; then
  JM=1; warn "JM firmware family detected: read docs/JM-FIRMWARE-BACKDOOR.md"
fi
if Q pm list packages | grep -q -e com.google.android.apps.tv.launcherx -e com.google.android.tvlauncher; then
  info "Google TV / Android TV certified build: github.com/Gathin23/cleanyourtv covers its launcher quirks too"
fi
info "adb shell: $( [ $ROOT = 1 ] && echo root || echo "not root (some checks skipped)")"

section "Hardware truth"
MEMTOTAL=$(Q "grep MemTotal /proc/meminfo" | awk '{print $2}')
KMEM=$(Q "dmesg 2>/dev/null | grep -m1 'Memory: '" | sed -n 's/.*Memory: *[0-9]*K\/\([0-9]*\)K.*/\1/p')
if [ -n "$KMEM" ] && [ -n "$MEMTOTAL" ]; then
  if [ "$MEMTOTAL" -gt "$KMEM" ]; then bad "RAM is spoofed: /proc/meminfo says $((MEMTOTAL / 1024)) MB, the kernel booted with $((KMEM / 1024)) MB"
  else ok "RAM $((KMEM / 1024)) MB physical, meminfo $((MEMTOTAL / 1024)) MB"; fi
else
  info "RAM: /proc/meminfo $((MEMTOTAL / 1024)) MB (dmesg not readable: cannot check for spoofing)"
  case "$MEMTOTAL" in 2097152|4194304|1048576|3145728) warn "MemTotal is an exact power of two ($MEMTOTAL kB): real RAM never is, likely spoofed" ;; esac
fi
STORAGE=$(Q "df /data" | awk 'NR==2{print $2}')
[ -n "$STORAGE" ] && info "storage: /data $((STORAGE / 1024 / 1024)) GB"
FPS=$(Q "dumpsys display" | grep -m1 -o 'fps=[0-9.]*' | cut -d= -f2)
info "display:  $(Q wm size | head -1 | awk '{print $3}') @ ${FPS:-?} Hz; marketing resolution claims are about the input it accepts, this is the panel"
case "$FPS" in 30*|29*) warn "UI runs at 30 Hz: menus will always feel choppy (video is unaffected)" ;; esac
[ -z "$(Q ls /sys/class/rtc)" ] && info "no RTC: times written before NTP sync show the build date, not real dates"

section "Remote access"
[ $ROOT = 1 ] && bad "adb shell runs as root: anyone who reaches ADB owns the device"
[ "$(Q getprop ro.adb.secure)" = 1 ] || bad "ro.adb.secure is not 1: ADB accepts computers without the Allow prompt"
PORT=$(Q getprop service.adb.tcp.port)
[ -n "$PORT" ] && [ "$PORT" != 0 ] && [ "$PORT" != -1 ] && warn "ADB listens on the network (port $PORT): switch debugging off when done"
SEL=$(Q getenforce)
case "$SEL" in Enforcing) ok "SELinux enforcing" ;; *) bad "SELinux is ${SEL:-unknown}: root services run unconfined" ;; esac
for su in /system/xbin/su /system/bin/su /sbin/su /system/xbin/daemonsu; do
  [ -n "$(Q ls $su)" ] && warn "su binary present: $su"
done
DAEMONS=$(Q "ps -A -o NAME" | grep -E -x 'jmsu|daemonsu|su|magiskd|supolicy' | sort -u | tr '\n' ' ')
[ -n "$DAEMONS" ] && warn "root daemons running: $DAEMONS"

section "Root code launched by init"
# Any init service whose program lives on /data runs code that was not part of the signed image, as whatever user
# the .rc says (usually root). Scripts in /system that curl/wget and are run by init are remote-code channels.
RC=$(Q "cat $(printf '%s/*.rc ' $INIT_DIRS) 2>/dev/null")
DATASVC=$(printf '%s\n' "$RC" | grep -E '^\s*service\s+\S+\s+(/system/bin/sh\s+)?/data/' | sed 's/^ *//')
if [ -n "$DATASVC" ]; then
  while IFS= read -r l; do bad "init runs a /data program: $l"; done <<< "$DATASVC"
else ok "no init service runs a program from /data"; fi
SCRIPTS=$(printf '%s\n' "$RC" | grep -E '^\s*service\s' | grep -oE '/(system|vendor|odm|product)[^ ]*\.sh' | sort -u)
for s in $SCRIPTS; do
  NET=$(Q cat "$s" | grep -oE '(curl|wget|busybox wget)[^|;]*https?://[^ "]*' | head -2)
  [ -n "$NET" ] && bad "$s (started by init) downloads: $(printf '%s' "$NET" | tr '\n' ' ')"
  for d in $(Q cat "$s" | grep -oE '/data/[A-Za-z0-9_./-]+' | sort -u); do
    case "$(Q stat -c %a "$d")" in 777|666|*7|*6) bad "$s uses $d, which any app can write (local root)";; esac
  done
done
while IFS=$'\t' read -r val sev note; do
  [ -n "$val" ] || continue
  printf '%s\n' "$RC" | grep -qF -- "$val" && { [ "$sev" = bad ] && bad "init: '$val' — $note" || warn "init: '$val' — $note"; }
done <<EOF
$(indicators rc)
EOF
if Q mount | grep -E ' /(system|vendor|product) type overlay' | grep -q upperdir; then
  warn "/system is an overlay (adb remount): files were added on top of the factory image"
  if [ $ROOT = 1 ]; then Q "find /mnt/scratch/overlay/*/upper -type f" | sed 's/^/           /'; fi
fi

section "Known indicators (data/indicators.tsv)"
ENABLED=$(Q pm list packages -e | sed 's/package://')
FOUND=0
while IFS=$'\t' read -r val sev note; do
  [ -n "$val" ] || continue
  printf '%s\n' "$ENABLED" | grep -qx -- "$val" || continue
  FOUND=1; [ "$sev" = bad ] && bad "$val enabled — $note" || warn "$val enabled — $note"
done <<EOF
$(indicators package)
EOF
while IFS=$'\t' read -r val sev note; do
  [ -n "$val" ] || continue
  V=$(Q getprop "$val"); [ -n "$V" ] || continue
  FOUND=1; bad "$val = $V — $note"
done <<EOF
$(indicators prop)
EOF
if [ $ROOT = 1 ]; then
  while IFS=$'\t' read -r val sev note; do
    [ -n "$val" ] || continue
    [ -n "$(Q ls "$val")" ] || continue
    FOUND=1; [ "$sev" = bad ] && bad "$val — $note" || warn "$val — $note"
  done <<EOF
$(indicators path)
EOF
else skip "known file paths under /data"; fi
[ $FOUND = 0 ] && ok "none of the known packages, properties or files"

section "Apps that can install or control apps silently"
# uid system (1000) apps from outside Google/AOSP that hold INSTALL_PACKAGES can install anything without a prompt.
for p in $(Q pm list packages -U -s -e | grep 'uid:1000$' | sed 's/package://; s/ uid:1000//' | grep -vE '^(android|com\.android\.|com\.google\.)'); do
  D=$(Q dumpsys package "$p")
  printf '%s' "$D" | grep -q 'android.permission.INSTALL_PACKAGES: granted=true' || continue
  NETW=$(printf '%s' "$D" | grep -c 'android.permission.INTERNET: granted=true')
  [ "$NETW" -gt 0 ] && info "$p — uid system, can install silently, has INTERNET" || info "$p — uid system, can install silently"
done
A11Y=$(Q settings get secure enabled_accessibility_services); [ "$A11Y" != null ] && [ -n "$A11Y" ] && info "accessibility services: $A11Y"
NL=$(Q settings get secure enabled_notification_listeners); [ "$NL" != null ] && [ -n "$NL" ] && info "notification listeners: $NL"
[ "$(Q settings get secure install_non_market_apps)" = 1 ] && info "unknown sources allowed"

section "Network"
HOSTS=$(Q cat /system/etc/hosts)
UNBLOCKED=""
while IFS=$'\t' read -r val sev note; do
  [ -n "$val" ] || continue
  printf '%s\n' "$HOSTS" | grep -qE "[[:space:]]$val\$" || UNBLOCKED="$UNBLOCKED $val"
done <<EOF
$(indicators domain)
EOF
[ $JM = 1 ] && [ -n "$UNBLOCKED" ] && warn "known C2/telemetry domains not blocked in /system/etc/hosts:$UNBLOCKED"
PD=$(Q settings get global private_dns_mode)
[ "$PD" = hostname ] && ok "Private DNS: $(Q settings get global private_dns_specifier)" || info "Private DNS: ${PD:-default} (tools/harden.sh --dns adguard sets an ad-blocking resolver)"
# Map /proc/net/tcp sockets to packages by uid. Remote address shown for established, local port for listeners.
UIDMAP=$(Q pm list packages -U | sed 's/package://; s/ uid:/ /' | awk '{print $2" "$1}')
BADIPS=$(indicators ip | cut -f1)
hex2ip(){ local h=$1; [ ${#h} -eq 32 ] && h=${h:24:8}; [ ${#h} -eq 8 ] || { echo ipv6; return; }
  echo "$((16#${h:6:2})).$((16#${h:4:2})).$((16#${h:2:2})).$((16#${h:0:2}))"; }
EST=""; LIS=""
while read -r _ local remote st _ _ _ uid _; do
  case "$st" in 01|0A) ;; *) continue ;; esac
  lip=$(hex2ip "${local%%:*}"); rip=$(hex2ip "${remote%%:*}"); lport=$((16#${local##*:})); rport=$((16#${remote##*:}))
  pkg=$(printf '%s\n' "$UIDMAP" | awk -v u="$uid" '$1==u{print $2; exit}')
  [ -n "$pkg" ] || { [ "$uid" = 0 ] && pkg="root (adbd or a root daemon)" || pkg="uid $uid"; }
  if [ "$st" = 0A ]; then
    case "$lip" in 127.*) continue ;; esac
    LIS="$LIS"$'\n'"$(printf '%-6s %s' "$lport" "$pkg")"
  else
    printf '%s\n' "$BADIPS" | grep -qx "$rip" && bad "connected to known C2 $rip:$rport from $pkg"
    case "$rip" in 10.*|192.168.*|172.1[6-9].*|172.2*|172.3[01].*|127.*) continue ;; esac
    EST="$EST"$'\n'"$(printf '%-22s %s' "$rip:$rport" "$pkg")"
  fi
done <<EOF
$(Q cat /proc/net/tcp /proc/net/tcp6 | grep -v local_address)
EOF
[ -n "$LIS" ] && { info "listening on the network (port, app):"; printf '%s\n' "$LIS" | sort -u | sed '/^$/d; s/^/           /'; }
[ -n "$EST" ] && { info "internet connections (remote, app):"; printf '%s\n' "$EST" | sort -u | sed '/^$/d; s/^/           /'; }

section "Apps"
info "third-party: $(Q pm list packages -3 -e | sed 's/package://' | tr '\n' ' ')"
info "disabled packages: $(Q pm list packages -d | wc -l | tr -d ' ')"
info "home: $(Q cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1)"
SEL_HOME=$(Q getprop persist.sys.home.selectpkg); [ -n "$SEL_HOME" ] && info "home router property persist.sys.home.selectpkg = $SEL_HOME"

section "Performance"
VERIFY=$(Q "dumpsys package dexopt" | grep -c 'status=verify')
[ "$VERIFY" -gt 20 ] && warn "$VERIFY apps never AOT-compiled (status=verify): tools/optimize.sh compiles the ones in use"
ANIM=$(Q settings get global window_animation_scale); CACHED=$(Q device_config get activity_manager max_cached_processes)
info "animation scale ${ANIM/null/1.0 (default)}, max cached processes ${CACHED:-default}"
info "largest resident processes:"
Q "ps -A -o RSS,NAME" | awk 'NR>1 && $1>0' | sort -rn | head -8 | awk '{printf "           %5d MB  %s\n", $1/1024, $2}'

printf '\n%d bad, %d warnings\n' "$BAD" "$WARN"
[ "$BAD" -eq 0 ]
