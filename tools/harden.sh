#!/usr/bin/env bash
# Shut every known path for the JM firmware backdoor (docs/JM-FIRMWARE-BACKDOOR.md) and keep it shut on
# every boot. Needs root ADB and the adb-remount overlay at /mnt/scratch, which JM firmware ships with.
# Originals are moved to /data/local/quarantine, never deleted. Re-run after a factory reset.
# Usage: tools/harden.sh <ip[:port]>
set -eu
cd "$(dirname "$0")/.."
. tools/_adb.sh "$1"
case "$(S id)" in uid=0*) ;; *) echo "adb shell is not root here; this script is for JM firmware with root adbd" >&2; exit 1 ;; esac
S '[ -d /mnt/scratch/overlay/system/upper ]' || { echo "no /mnt/scratch overlay: run 'adb remount' first" >&2; exit 1; }
S 'rm -rf /data/local/tmp/cyp; mkdir -p /data/local/tmp/cyp'
adb -s "$DEV" push harden/. /data/local/tmp/cyp/ >/dev/null
S 'set -e
U=/mnt/scratch/overlay/system/upper; H=/data/local/tmp/cyp; Q=/data/local/quarantine
mkdir -p $Q/overlay $Q/data $Q/ttyunos; chmod 700 $Q
# Quarantine what the vendor server pushed (first run only; later runs find nothing to move).
[ -f $U/bin/jmsu ] && mv $U/bin/jmsu $Q/overlay/jmsu
[ -f /data/local/jmsu ] && mv /data/local/jmsu $Q/data/jmsu.datacopy
[ -f /data/local/root_access.rc ] && mv /data/local/root_access.rc $Q/data/
for f in /data/install-host.sh /data/install-recovery.sh /data/install-end.sh; do [ -f $f ] && mv $f $Q/data/; done
grep -q curl /data/ttyunos/ttyunos.sh 2>/dev/null && cp -a /data/ttyunos/. $Q/ttyunos/
for p in persist.sys.jm.url persist.sys.proxy.url; do v=$(getprop $p); [ -n "$v" ] && echo "$p=$v" >> $Q/props.txt; done
chmod -R go-rwx $Q
mkdir -p $U/etc/init $U/bin
put(){ cp "$1" "$2"; chown root:"$3" "$2"; chmod "$4" "$2"; }
put $H/ttyunos.rc     $U/etc/init/ttyunos.rc     root  644
put $H/root_access.rc $U/etc/init/root_access.rc root  644
put $H/c2block.rc     $U/etc/init/c2block.rc     root  644
put $H/c2block.sh     $U/etc/c2block.sh          root  755
put $H/hosts          $U/etc/hosts               root  644
put $H/stub.sh        $U/etc/ttyunos.sh          root  644
put $H/stub.sh        $U/etc/v9ying.sh           root  644
put $H/stub.sh        $U/etc/custom.sh           root  644
put $H/upgrade.sh     $U/bin/upgrade.sh          shell 755
put $H/installxapk.sh $U/bin/installxapk.sh      shell 755
setprop ctl.stop root_access
sh $H/c2block.sh
rm -rf $H; sync; echo "overlay hardened; originals in $Q"'
for p in com.droidlogic.updater com.koushikdutta.superuser; do
  printf '%-32s ' "$p"; S pm disable-user --user 0 "$p" | tail -1
done
echo "reboot the projector, then run tools/scan.sh to confirm"
