#!/usr/bin/env bash
# Read-only health and security scan of an Android projector over ADB. Changes nothing on the device.
# Usage: tools/scan.sh <ip[:port]>      (or DEV=<ip:port> tools/scan.sh)
set -u
DEV="${1:-${DEV:-}}"
[ -n "$DEV" ] || { echo "usage: tools/scan.sh <projector ip[:port]>"; exit 2; }
case "$DEV" in *:*) ;; *) DEV="$DEV:5555" ;; esac
adb connect "$DEV" >/dev/null 2>&1
S(){ adb -s "$DEV" shell "$@" 2>/dev/null | tr -d '\r'; }
[ "$(S echo ok)" = ok ] || { echo "cannot reach $DEV over ADB (enable USB/Network debugging first)"; exit 1; }

BAD=0; WARN=0
bad(){  printf '  \033[31m[BAD]\033[0m  %s\n' "$*"; BAD=$((BAD + 1)); }
warn(){ printf '  \033[33m[WARN]\033[0m %s\n' "$*"; WARN=$((WARN + 1)); }
ok(){   printf '  \033[32m[OK]\033[0m   %s\n' "$*"; }
info(){ printf '         %s\n' "$*"; }
section(){ printf '\n== %s\n' "$*"; }

section "Device"
info "model:    $(S getprop ro.product.model) / board $(S getprop ro.board.platform) / $(S getprop ro.hardware)"
info "android:  $(S getprop ro.build.version.release) (API $(S getprop ro.build.version.sdk)), $(S getprop ro.build.type)"
info "build:    $(S getprop ro.build.display.id)"
FP=$(S getprop ro.build.fingerprint)
case "$FP" in google/*) warn "fingerprint claims a Google device ($FP): certification spoofing" ;; *) info "fingerprint: $FP" ;; esac
JMBOARD=$(S getprop ro.jm.board.name)
[ -n "$JMBOARD" ] && warn "JM firmware family (ro.jm.board.name=$JMBOARD): see docs/JM-FIRMWARE-BACKDOOR.md"

section "Hardware truth"
MEMTOTAL=$(S "grep MemTotal /proc/meminfo" | awk '{print $2}')
KMEM=$(S "dmesg 2>/dev/null | grep -m1 'Memory: '" | sed -n 's/.*Memory: *[0-9]*K\/\([0-9]*\)K.*/\1/p')
if [ -n "$KMEM" ] && [ -n "$MEMTOTAL" ] && [ "$MEMTOTAL" -gt "$KMEM" ]; then
  bad "RAM is spoofed: /proc/meminfo says $((MEMTOTAL / 1024)) MB, the kernel booted with $((KMEM / 1024)) MB"
elif [ -n "$KMEM" ]; then ok "RAM: $((KMEM / 1024)) MB physical, meminfo $((MEMTOTAL / 1024)) MB"
else info "RAM: meminfo $((MEMTOTAL / 1024)) MB (dmesg not readable, cannot check for spoofing)"; fi
FPS=$(S "dumpsys display" | grep -m1 -o 'fps=[0-9.]*' | cut -d= -f2)
info "display:  $(S wm size | head -1 | awk '{print $3}') @ ${FPS:-?} Hz"
case "$FPS" in 30*|29*) warn "panel output is 30 Hz: menus will always feel choppy (video is fine)" ;; esac
[ -z "$(S ls /sys/class/rtc 2>/dev/null)" ] && info "no RTC: file times written before NTP sync show the build date"

section "Remote access"
ID=$(S id)
case "$ID" in uid=0*) bad "adb shell runs as root: anyone who reaches ADB owns the device" ;; *) ok "adb shell is not root" ;; esac
[ "$(S getprop ro.adb.secure)" = 1 ] || bad "ro.adb.secure is not 1: ADB accepts hosts without the Allow prompt"
PORT=$(S getprop service.adb.tcp.port)
[ -n "$PORT" ] && [ "$PORT" != 0 ] && warn "ADB listens on the network (port $PORT): switch debugging off when done"
SEL=$(S getenforce)
[ "$SEL" = Enforcing ] && ok "SELinux enforcing" || bad "SELinux is $SEL: root scripts run unconfined"

section "JM firmware backdoor (remote root script channel)"
TTYRC=$(S cat /system/etc/init/ttyunos.rc)
if printf '%s' "$TTYRC" | grep -q 'start ttyunos'; then
  bad "/system/etc/init/ttyunos.rc runs /data/ttyunos/*.sh as root when the network comes up"
elif [ -n "$TTYRC" ]; then ok "ttyunos.rc present but neutralized"
else ok "no ttyunos.rc"; fi
for f in ttyunos.sh v9ying.sh; do
  C=$(S cat /data/ttyunos/$f)
  printf '%s' "$C" | grep -q curl && bad "/data/ttyunos/$f downloads and runs a script: $(printf '%s' "$C" | grep -o 'http[^ "]*' | head -2 | tr '\n' ' ')"
done
PERM=$(S stat -c %a /data/ttyunos)
[ "$PERM" = 777 ] && bad "/data/ttyunos is world-writable (777): any app can get root through it"
for f in install-host.sh install-recovery.sh install-end.sh install-recovery-v9.sh; do
  [ -n "$(S ls /data/$f)" ] && bad "/data/$f present (C2 client fetched from the vendor server)"
done
for p in persist.sys.jm.url persist.sys.proxy.url; do
  V=$(S getprop $p); [ -n "$V" ] && bad "$p = $V"
done
if [ -n "$(S pidof jmsu)" ]; then
  if S "strings /system/bin/jmsu" | grep -q 'autoload'; then bad "jmsu su-daemon running WITH remote 'autoload' (fetch + run signed scripts as root)"
  else warn "jmsu su-daemon running (root on request; no autoload in this build)"; fi
fi
UP=$(S "find /mnt/scratch/overlay/*/upper -type f 2>/dev/null")
[ -n "$UP" ] && warn "files injected into /system through the adb-remount overlay:" && printf '%s\n' "$UP" | sed 's/^/           /'
S "grep -l -a 'sys.jm.ttyunos' /system/apex/com.android.tethering/javalib/service-connectivity.jar" | grep -q . \
  && warn "framework ConnectivityService sets sys.jm.ttyunos=1 on connect (cannot be removed without reflashing)"
S "ls /data/local/install/script.log" | grep -q . && warn "C2 activity log: /data/local/install/script.log ($(S "wc -l < /data/local/install/script.log") lines)"

section "Network"
HOSTS=$(S cat /system/etc/hosts)
for d in jm.v7ying.com apk.v8ying.com jm.v9ying.com txy.jiumaoos.com appreg.clapvf.com; do
  printf '%s' "$HOSTS" | grep -q " $d$" || warn "$d not blocked in /system/etc/hosts"
done
S "iptables -S OUTPUT" | grep -q 123.207.77.74 || warn "C2 IP 123.207.77.74 not blocked by iptables"
CONNS=$(S "netstat -tnp 2>/dev/null" | grep ESTAB | grep -v -e adbd -e 'com.google' -e netd -e com.android.vending)
[ -n "$CONNS" ] && info "other established connections:" && printf '%s\n' "$CONNS" | awk '{print "           "$5"  "$7}'
LIS=$(S "netstat -tlnp 2>/dev/null" | grep LISTEN | grep -v -e adbd -e 127.0.0.1)
[ -n "$LIS" ] && warn "apps listening on the LAN:" && printf '%s\n' "$LIS" | awk '{print "           "$4"  "$7}'
PD=$(S settings get global private_dns_mode)
[ "$PD" = hostname ] && ok "Private DNS: $(S settings get global private_dns_specifier)" || info "Private DNS: ${PD:-default}"

section "Adware and silent installers"
ENABLED=$(S pm list packages -e | sed 's/package://')
has(){ printf '%s\n' "$ENABLED" | grep -qx "$1"; }
has com.smart.tv.launcher && bad "com.smart.tv.launcher enabled (ad player, SensorsData analytics, plugin loader)"
has com.master.t972 && warn "com.master.t972 (stock home) enabled: silently downloads and installs APKs from txy.jiumaoos.com"
has com.master.tv.market && warn "com.master.tv.market enabled (vendor store with xapk installer)"
has com.droidlogic.updater && warn "com.droidlogic.updater enabled: an OTA can restore the backdoor"
has com.koushikdutta.superuser && warn "com.koushikdutta.superuser enabled (root grant UI)"
for p in com.waxrain.airplaydmr2 com.bozee.usbdisplay; do has $p && warn "$p enabled (opens many LAN ports)"; done
has com.google.android.tvrecommendations && info "com.google.android.tvrecommendations enabled (ads signals provider)"
info "third-party apps: $(S pm list packages -3 -e | sed 's/package://' | tr '\n' ' ')"
info "disabled packages: $(S pm list packages -d | wc -l | tr -d ' ')"

section "Performance"
VERIFY=$(S "dumpsys package dexopt" | grep -c 'status=verify')
[ "$VERIFY" -gt 20 ] && warn "$VERIFY apps never AOT-compiled (status=verify): tools/optimize.sh compiles the ones you use"
info "animation scale: $(S settings get global window_animation_scale) / max cached processes: $(S device_config get activity_manager max_cached_processes)"
info "top resident processes (RSS):"
S "ps -A -o RSS,NAME" | sort -rn | grep -v -e '^ *0 ' | head -8 | awk '{printf "           %6d MB  %s\n", $1/1024, $2}'

printf '\n%d bad, %d warnings\n' "$BAD" "$WARN"
[ "$BAD" -eq 0 ]
