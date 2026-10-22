#!/usr/bin/env bash
# Close what tools/scan.sh flags, on any projector, to the extent the device allows:
#   every device:   disable enabled packages marked "bad" in data/indicators.tsv; optional ad-blocking Private DNS
#   JM firmware:    also its vendor installers/OTA, and with root adb + the /mnt/scratch overlay: neutralize the
#                   init scripts, su daemon, USB/xapk auto-install, block C2 domains (hosts) and IPs (iptables),
#                   all re-applied on every boot (docs/JM-FIRMWARE-BACKDOOR.md). Originals go to /data/local/quarantine.
# Never disables the app that currently answers Home. Re-run after a factory reset or an OTA.
# Usage: tools/harden.sh <ip[:port] | adb serial> [--dns adguard|off]
set -eu
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=tools/_adb.sh
. tools/_adb.sh "${1:-}"
DNS=""
[ "${2:-}" = --dns ] && DNS="${3:?--dns adguard|off}"

HOME_NOW=$(Q cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1 | cut -d/ -f1)
SELECTED=$(Q getprop persist.sys.home.selectpkg)
JM=0; { [ -n "$(Q getprop ro.jm.board.name)" ] || [ -n "$(Q ls /system/etc/init/ttyunos.rc)" ]; } && JM=1
ENABLED=$(Q pm list packages -e | sed 's/package://')

echo "== packages"
while IFS=$'\t' read -r pkg sev fam; do
  [ -n "$pkg" ] || continue
  printf '%s\n' "$ENABLED" | grep -qx "$pkg" || continue
  # bad: always. warn: only the vendor's own installers/OTA on that vendor's firmware; the rest is preference.
  if [ "$sev" != bad ] && ! { [ $JM = 1 ] && { [ "$fam" = jm ] || [ "$fam" = amlogic ]; }; }; then
    echo "   left alone (preference, see devices/ lists): $pkg"; continue
  fi
  if [ "$pkg" = "$HOME_NOW" ] || [ "$pkg" = "$SELECTED" ]; then
    echo "   kept: $pkg is the current Home; replace it first (tools/install-launcher.sh)"; continue
  fi
  printf '   %-46s ' "$pkg"; S pm disable-user --user 0 "$pkg" | tail -1
done <<< "$(grep -v '^#' data/indicators.tsv | awk -F'\t' '$1=="package"{print $2"\t"$3"\t"$4}')"

case "$DNS" in
  adguard) S settings put global private_dns_specifier dns.adguard-dns.com
           S settings put global private_dns_mode hostname
           echo "== Private DNS: dns.adguard-dns.com (blocks ad/tracker domains, not YouTube ads)" ;;
  off)     S settings put global private_dns_mode opportunistic; echo "== Private DNS: back to automatic" ;;
esac

[ $JM = 1 ] || { echo "== no JM firmware indicators: nothing to patch in /system. Run tools/scan.sh to confirm."; exit 0; }
if [ "$ROOT" != 1 ]; then
  echo "== JM firmware, but adb is not root here: cannot patch init scripts. Keep the projector off Wi-Fi" >&2
  echo "   or block the domains in data/indicators.tsv on your router." >&2; exit 1
fi
Q '[ -d /mnt/scratch/overlay/system/upper ]' || S remount >/dev/null 2>&1 || true
Q '[ -d /mnt/scratch/overlay/system/upper ] && echo y' | grep -q y \
  || { echo "no /mnt/scratch overlay and 'remount' failed: cannot patch /system" >&2; exit 1; }

echo "== JM firmware: patching /system through the overlay"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cp harden/jm/* "$TMP/"
{ printf '127.0.0.1       localhost\n::1             ip6-localhost\n# cleanyourprojector: data/indicators.tsv domains\n'
  grep -v '^#' data/indicators.tsv | awk -F'\t' '$1=="domain"{print "0.0.0.0 "$2}'; } > "$TMP/hosts"
grep -v '^#' data/indicators.tsv | awk -F'\t' '$1=="ip"{print $2}' > "$TMP/cyp-block-ips"
S 'rm -rf /data/local/tmp/cyp; mkdir -p /data/local/tmp/cyp' >/dev/null
adb -s "$DEV" push "$TMP/." /data/local/tmp/cyp/ >/dev/null
S 'set -e
U=/mnt/scratch/overlay/system/upper; H=/data/local/tmp/cyp; Q=/data/local/quarantine
mkdir -p $Q/overlay $Q/data $Q/ttyunos; chmod 700 $Q
# Quarantine what the vendor server pushed (first run only; later runs find nothing to move).
if [ -f $U/bin/jmsu ]; then mv $U/bin/jmsu $Q/overlay/jmsu; fi
if [ -f /data/local/jmsu ]; then mv /data/local/jmsu $Q/data/jmsu.datacopy; fi
if [ -f /data/local/root_access.rc ]; then mv /data/local/root_access.rc $Q/data/; fi
for f in /data/local/com.master.jmsu_*.apk; do if [ -f "$f" ]; then mv "$f" $Q/data/; fi; done
for f in /data/install-host.sh /data/install-recovery.sh /data/install-end.sh /data/install-recovery-v9.sh; do
  if [ -f $f ]; then mv $f $Q/data/; fi
done
if grep -q curl /data/ttyunos/ttyunos.sh 2>/dev/null; then cp -a /data/ttyunos/. $Q/ttyunos/; fi
for p in persist.sys.jm.url persist.sys.proxy.url; do v=$(getprop $p); if [ -n "$v" ]; then echo "$p=$v" >> $Q/props.txt; fi; done
chmod -R go-rwx $Q
mkdir -p $U/etc/init $U/bin
put(){ cp "$1" "$2"; chown root:"$3" "$2"; chmod "$4" "$2"; }
put $H/ttyunos.rc     $U/etc/init/ttyunos.rc     root  644
put $H/root_access.rc $U/etc/init/root_access.rc root  644
put $H/c2block.rc     $U/etc/init/c2block.rc     root  644
put $H/c2block.sh     $U/etc/c2block.sh          root  755
put $H/cyp-block-ips  $U/etc/cyp-block-ips       root  644
put $H/hosts          $U/etc/hosts               root  644
put $H/stub.sh        $U/etc/ttyunos.sh          root  644
put $H/stub.sh        $U/etc/v9ying.sh           root  644
put $H/stub.sh        $U/etc/custom.sh           root  644
put $H/upgrade.sh     $U/bin/upgrade.sh          shell 755
put $H/installxapk.sh $U/bin/installxapk.sh      shell 755
setprop ctl.stop root_access
setprop persist.sys.jm.url ""; setprop persist.sys.proxy.url ""
rm -rf $H; sync
echo "   overlay patched; originals in $Q"'
echo "== reboot the projector, then run tools/scan.sh: the overlay takes effect after a reboot"
