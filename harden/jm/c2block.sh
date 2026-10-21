#!/system/bin/sh
# Runs as root on every boot (see /system/etc/init/c2block.rc).
# IPs from data/indicators.tsv, written by tools/harden.sh.
while read -r ip; do
    [ -n "$ip" ] || continue
    iptables -C OUTPUT -d "$ip" -j REJECT 2>/dev/null || iptables -I OUTPUT -d "$ip" -j REJECT
done < /system/etc/cyp-block-ips
# Keep the /data hooks harmless even if something recreates them.
for f in /data/ttyunos/ttyunos.sh /data/ttyunos/v9ying.sh /data/ttyunos/custom.sh /data/local/agent.sh; do
    mkdir -p "$(dirname "$f")"
    printf '#!/system/bin/sh\nexit 0\n' > "$f"
    chown root:root "$f"; chmod 755 "$f"
done
chown root:root /data/ttyunos; chmod 755 /data/ttyunos
rm -f /data/install-host.sh /data/install-recovery.sh /data/install-end.sh /data/install-recovery-v9.sh
setprop persist.sys.jm.url ""
setprop persist.sys.proxy.url ""
# Some stock launchers (com.master.t972) lose their disabled state on every boot. While our launcher is
# installed and enabled, disable the stock one again and reopen Home.
stock=$(getprop persist.cyp.stock_launcher)
if [ -n "$stock" ] && pm list packages -e | grep -qx 'package:com.gathin.tvhome'; then
    [ -n "$(getprop persist.sys.home.selectpkg)" ] && setprop persist.sys.home.selectpkg com.gathin.tvhome
    pm disable-user --user 0 "$stock" >/dev/null 2>&1
    am force-stop "$stock"
    input keyevent KEYCODE_HOME
fi
