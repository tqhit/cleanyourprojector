# Wanbo Vali 1 Pro

| | |
|---|---|
| Board | MediaTek MT5896 (`ro.hardware=mt5896`, `ro.board.platform=merak`), device `coorg`, 32-bit userspace (`arm`) |
| Android | 14 (API 34), `user`, release-keys, SELinux enforcing, security patch 2026-08-01 (build `UKN6.260116.148`) |
| RAM | ~2 GB (`/proc/meminfo` 1797 MB; `dmesg` not readable without root) + 1 GB zram swap |
| Display | 1920×1080 @ 60 Hz |
| Firmware | SDMC (`com.sdmc.*`) on MediaTek's TV stack; Google TV certified, fingerprint `wanbo/Vali1_Pro/coorg` matches the device |
| Stock Home | `com.google.android.apps.tv.launcherx` (Google TV); `com.google.android.tungsten.setupwraith/.RecoveryActivity` is a second HOME candidate at priority 1 |
| ADB | not root, Allow prompt required (`ro.adb.secure` on), port 5555 stays open across reboots until debugging is switched off |

## Run order

```sh
tools/scan.sh <ip>
tools/backup.sh <ip>
tools/disable.sh <ip> devices/wanbo-vali1-pro/debloat.txt     # edit the OPTIONAL section first; see setupwraith below
tools/harden.sh <ip> --dns adguard                            # optional: nothing to patch on this firmware, only Private DNS
# speed: tools/optimize.sh targets 1 GB AOSP boxes; on this unit compile by hand (see Measured)
tools/install-launcher.sh <ip> devices/wanbo-vali1-pro        # optional; read the launcher quirks first
```

## Findings on this unit

- **No backdoor or silent installer.** `tools/scan.sh`: 0 BAD. No init service runs code from `/data`, no su, no adb-remount
  overlay. Only Play Store, `com.google.android.packageinstaller`, `com.android.managedprovisioning` and
  `com.android.devicelockcontroller` hold `INSTALL_PACKAGES`. Network traffic at idle went only to Google and Netflix.
- **`com.sdmc.service` geolocates the public IP** with `http://ip-api.com/json/` (plain HTTP) in its `CountryCodeManager`, to set
  the Wi-Fi regulatory country. Its `PackageInstaller` code serves HbbTV operator apps (`HCW_OPAPP_*`, Solocoo/Freeview Play URLs)
  and the factory tool, not arbitrary downloads.
- `com.sdmc.service`, `com.sdmc.projectsettings`, `com.sdmc.keyburn` and `com.mediatek.network` run as uid system, so they hold every
  permission by default. Keep them: projector settings and the remote depend on them.
- Factory packages `com.sdmc.sdmcfactory`, `com.sdmc.test.servicemanagertest` and `mediatek.factorymenu.ui` were left enabled and never
  opened.

## Quirks found on this unit

- **Keystone, focus and screen settings are slices inside system Settings** (`com.sdmc.projectsettings` providers shown under
  Settings → Projector). `com.mediatek.trapezoidapp` ("TrapezoidDemo") also exists; keep both.
- **`com.android.devicelockcontroller` cannot be disabled**: Android 14 refuses with `SecurityException: Cannot disable a protected package`.
- **The firmware re-enabled nothing** after a reboot (22 packages disabled before and after).
- **Netflix is the TV build** (`com.netflix.ninja`): no remote-mouse helper needed.
- **Background dexopt does run** here: the main streaming apps were already `speed-profile`. 63 enabled apps stayed at `verify`, including
  `com.android.tv.settings`, `com.mediatek.tv.settings`, `com.mediatek.trapezoidapp` and `com.android.vending`.
- **Remote** ("RemoteB080", Bluetooth, `Vendor_3679_Product_b080.kl`, not readable without root). Global keys: Netflix (`BUTTON_4`)
  and the input keys go to `com.mediatek.tv.agent`, `KEYCODE_TV` and the zoom/focus keys to `com.sdmc.service`; `NOTIFICATION`
  (the gear), `BUTTON_3` (YouTube), `FEATURED_APP_1` (the Live TV button), `GUIDE`, `ALL_APPS` and `PROFILE_SWITCH` to the Google TV launcher.
  `com.sdmc.service` also reads every Bluetooth key itself (`bt_key_event`, logs vendor code 424 for Live TV), but only to wake
  the screen or close dialogs. Its key table (`res/raw/key_config.json`) has no Live TV entry.

## Clean launcher on this unit

Tested with Chromecast receiver and phone casting kept. Order matters:

1. **Forget and rejoin Wi-Fi first** (Settings → Network & Internet). Networks saved during first setup belong to setupwraith
   (`dumpsys wifi | grep -o 'cname=[^ ]*'` → `com.google.android.tungsten.setupwraith`), and disabling it deletes them. After rejoining
   they belong to `android.uid.system`.
2. Disable `com.google.android.tungsten.setupwraith` (it is in `debloat.txt`). Otherwise its `.RecoveryActivity` takes Home once the
   Google TV launcher is off.
3. Install the launcher, start it, disable `com.google.android.apps.tv.launcherx`, then `cmd package set-home-activity` last. Check
   `dumpsys activity activities | grep mFocusedApp` after pressing Home from inside an app.
4. Enable both key services. A reinstall or a force-stop of the launcher switches them off, so do this after every reinstall:
   `settings put secure enabled_accessibility_services com.gathin.tvhome/.InputKeyService:com.gathin.tvhome/.HomeKeyService`
   and `settings put secure accessibility_enabled 1`.

What happened:

- **Chromecast kept working with setupwraith disabled**, unlike the Chromecast-hardware case in upstream's TROUBLESHOOTING:
  `cast_shell` logs `Imported client auth private key` and `MdnsAppFilter: Done announcing.` after a reboot. Casting from a phone app worked.
- **Buttons the Google TV launcher answered** are brought back by `config.xml`: the gear is Linux `KEY_F19` (scancode 189,
  `settings_key_scancodes`), YouTube is `BUTTON_3` (190), and the **Live TV** button is `KEYCODE_FEATURED_APP_1` (297, Google's "Free TV"
  key). It is not `KEYCODE_GUIDE`. In `getevent` it shows as `KEY_GRAPHICSEDITOR` (429), but a `scan:429` entry
  does not fire.
- **Remapping on the TV**: the Google TV launcher's "Remote buttons" screen and hold-to-change go away with it. The stock
  clean launcher has no on-TV remap: edit `app_keys` and reinstall, or add the feature as a personal launcher patch
  (see [`patches/`](../../patches/)). On this unit, a local patch added both back (Launcher settings → Remote buttons, or hold a
  mapped button). It needs the key services enabled.
- **`reduced_motion` must be false** here. With it on, the ambient glow faded out after a Home press and did not come back. The MT5896 has
  no trouble with the full animations.
- `persist.cyp.stock_launcher` cannot be set without root, so pass the stock launcher to `tools/restore.sh` as its third argument:
  `tools/restore.sh <ip> devices/wanbo-vali1-pro/debloat.txt com.google.android.apps.tv.launcherx`.
- Before a factory reset, re-enable setupwraith and the Google TV launcher (the restore command above does both).

## Measured (one unit)

Cold start with `am start -W` after `am force-stop`, first launch / then two repeat launches, before and after debloat and compiling.

| | before | after |
|---|---|---|
| Netflix (`com.netflix.ninja`) | 1012 / 484, 490 ms | 946 / 480, 490 ms |
| YouTube | 2885 / 885, 713 ms | 1350 / 764, 519 ms |
| Disney+ (regional build, since replaced) | 2241 / 1258, 882 ms | 3191 / 1165, 878 ms |
| Prime Video | 1660 / 691, 704 ms | 1980 / 644, 624 ms |
| Home launcher RSS | `launcherx` 233 MB + `launcherx:coreservices` 111 MB | `com.gathin.tvhome` 129 MB |
| MemAvailable at Home | 564 MB | 628 MB |

Apart from YouTube's first launch, the differences are within run-to-run noise: the streaming apps were already compiled. Compiling
helped the never-compiled Settings, keystone and input apps, which were not timed beforehand. Animation scales were set to 0.5. Cached processes were left at the default
(2 GB RAM). The panel and the 4K-capable SoC are not the limit. Wi-Fi and the streaming apps' own start-up are.
