#!/usr/bin/env bash
# Re-enable every package in a list, undo Private DNS and give Home back to the stock launcher.
# Usage: tools/restore.sh <ip[:port]> devices/<model>/debloat.txt [stock.launcher.package]
set -u
cd "$(dirname "$0")/.."
. tools/_adb.sh "$1"
LIST="${2:?usage: tools/restore.sh <ip> <debloat list> [stock launcher]}"
STOCK="${3:-$(S getprop persist.cyp.stock_launcher)}"
for p in $(pkgs "$LIST"); do
  printf '%-50s ' "$p"; S pm enable "$p" | tail -1
done
S settings put global private_dns_mode opportunistic
if [ -n "$STOCK" ]; then
  # harden's boot script keeps the stock launcher disabled while ours is installed: remove ours first.
  S pm uninstall com.gathin.tvhome
  S pm enable "$STOCK"
  [ -n "$(S getprop persist.sys.home.selectpkg)" ] && S setprop persist.sys.home.selectpkg "$STOCK"
  S input keyevent KEYCODE_HOME
fi
