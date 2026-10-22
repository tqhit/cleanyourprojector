# KAW K670

| | |
|---|---|
| Board | Amlogic T950S (`txhd2`), `t950s_be311`, `ro.jm.board.name=W5`, sold as "Smart project" |
| Android | 13 (API 33), `userdebug`, armeabi-v7a, SELinux **disabled** |
| RAM | **1 GB** physical (`dmesg: Memory: 654336K/1048576K`); `/proc/meminfo` patched to say 2 GB |
| Display | 1280×720, one mode at 30 Hz |
| Firmware | JM (jiumaoos) — carries the backdoor in [docs/JM-FIRMWARE-BACKDOOR.md](../../docs/JM-FIRMWARE-BACKDOOR.md) |
| Stock Home | `com.master.t972`, reached through `com.jm.jmlauncher` |

## Run order

```sh
tools/scan.sh <ip>                                         # read-only report
tools/disable.sh <ip> devices/kaw-k670/debloat.txt         # edit the OPTIONAL sections first
tools/harden.sh <ip> --dns adguard                         # close the backdoor, reboot, scan again
tools/optimize.sh <ip>
tools/install-launcher.sh <ip> devices/kaw-k670            # optional, replaces com.master.t972
```

## Quirks found on this unit

- **adbd runs as root with no Allow prompt** (`ro.adb.secure` empty, `service.adb.root=1`). Switch debugging off when done:
  *Projector → Other Setting → Developer Options*.
- **Home routing.** The framework's home intent is `android.intent.category.HOME.JM`, answered only by `com.jm.jmlauncher`,
  which then starts the HOME app named in `persist.sys.home.selectpkg`. `cmd package set-home-activity` alone does nothing;
  `tools/install-launcher.sh` sets the property. Never disable `com.jm.jmlauncher`.
- **`com.master.t972` comes back on every boot.** PackageManager logs `pm_critical_info: Package com.master.t972 was user id 0 but
  is now user ... android.uid.system` and rebuilds its record, dropping the disabled state. The boot script installed by
  `tools/harden.sh` disables it again while `com.gathin.tvhome` is present, so it may flash for a second after power-on.
- **`com.master.t972` is a silent installer**: `POST http://txy.jiumaoos.com/official/detail/apkInfo`, downloads the returned URL
  and installs it with `PackageInstaller` as uid system. Blocked by the hardened `/system/etc/hosts`.
- **Keystone app phones home**: `com.softwinner.tcorrection` (persistent, needed for keystone/autofocus) reports to
  `appreg.clapvf.com/report_machine_info` and `txy.jiumaoos.com/netflix/dataSave`. Keep the app, block the hosts.
- **Netflix is the phone build** (`com.netflix.mediaclient`); the TV build needs a Netflix-certified device. It has no leanback
  entry (`library_apps.txt` adds it to the launcher) and D-pad focus does not move on its screens, so keep
  `com.master.accessibility` (remote mouse) enabled if you use Netflix.
- **No RTC.** Every boot starts at the build time (`2026-09-11 20:53` here) until NTP syncs; file times from early boot are not real dates.
- **Apps were never AOT-compiled** (`status=verify`): background dexopt needs idle + charging. `tools/optimize.sh` compiles them.
- Do not use *Other Setting → Reset Setting*: a factory reset wipes `/mnt/scratch` and brings the backdoor back. If you must,
  keep it off Wi-Fi until `tools/harden.sh` has run again.

## Reported on a sibling unit (#2), not yet checked on the K670

Same board (`t950s_be311`, `W5`), sold unbranded as "HD & AI Projector, 65W". From @doz10us's audit:

- **Hardware:** Wi-Fi/BT SeekWave SV6160LITE on USB (`3607:6621`); accelerometer MSA321; USB-Ethernet drivers built in
  (RTL8152, AX88179), so a USB-Ethernet adapter should work as wired LAN (untested); Widevine likely L3; no USB device
  mode, so network ADB is the only way in. Kernel is 32-bit ARM with SELinux left out.
- **Keystone without the vendor app:** `setprop persist.vendor.hwc.keystone "x1 y1 x2 y2 x3 y3 x4 y4"`, the four corners in
  1920×1080 space, applied live by the vendor HWC. `com.softwinner.tcorrection` also does sensor-based auto keystone, so keep it.
- **Focus motor:** write `2,1` / `1,1` to `/sys/devices/platform/motor0/motor_ctrl` to drive it, `0,1` to stop; end stops at
  `motor_limiter` and `motor_limiter1`.
- **Remote:** F+ / F− send Linux key codes 636 / 635 and the mouse button 637, mapped in the vendor `.kl` to non-standard
  labels (`MOTOR_FR`, `MOTOR_FF`, `MOUSE`).
- **Calibration and keys** in `/mnt/vendor/factory` (`AutoFocus/`, `HDCP_RX14_KEY`, `avb_persist`) are world-writable (0777).
  `tools/scan.sh` reports it; don't chmod them blindly, the projector's own services write there.
- **Do not wipe from the stock recovery** and do not expect a GSI to boot: see [TROUBLESHOOTING](../../docs/TROUBLESHOOTING.md#hardening).

## Measured (one unit)

| | before | after |
|---|---|---|
| YouTube cold start | 4.45 s | 4.35 s |
| Netflix cold start | 4.67 s | 4.11 s |
| Home launcher PSS | `t972` 23–49 MB | `com.gathin.tvhome` 17 MB |
| Cached processes allowed | 32 | 12 |

The ceiling is the hardware (1 GB RAM, 4× 1.46 GHz, 30 Hz panel). The largest real upgrade is an HDMI streaming stick with the
projector taken off Wi-Fi, which also leaves the firmware backdoor without a network.
