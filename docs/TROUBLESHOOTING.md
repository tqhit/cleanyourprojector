# Troubleshooting

## Connecting

- **`adb connect` says "No route to host" on macOS while the port is open**: macOS Local Network privacy is blocking the
  terminal. Allow it under System Settings → Privacy & Security → Local Network, or use the Python `adb-shell` client
  (see cleanyourtv's `tools/tv.py`).
- **Port 5555 closed**: some firmware only opens it while *Network debugging* / *ADB over network* is on, and closes it on
  reboot. Google TV builds may offer only *Wireless debugging*: pair with `adb pair <ip>:<port>` using the on-screen code,
  then `adb tcpip 5555`.
- **No "Allow USB debugging?" prompt and you still get a shell**: `ro.adb.secure` is not 1. Anyone on the network has the
  same access; switch debugging off when done.
- **`adb install` hangs**: a confirmation is waiting on screen (often behind the screensaver). Wake the screen, or push the
  APK and run `pm install -r` from `adb shell`.

## Disabling

- **Run `pm` one command per call.** Chained commands can stop silently after the first.
- **A package comes back enabled after a reboot.** Some firmware rebuilds a package's record at boot (look for
  `pm_critical_info` in `logcat -b events`) or re-enables a list of its own. Note it in the device README. For a stock
  launcher, `tools/harden.sh` on JM firmware re-disables it at boot while the replacement launcher is installed.
- **Everything is refused** (`SecurityException`, `DELETE_FAILED_INTERNAL_ERROR`, `pm hide` "succeeds" but nothing
  changes): the firmware blocks it. Check with `pm list packages -d`, not exit codes. Fall back to Private DNS / router
  blocking.
- **Never open packages named factory, test, fac, AT** (`com.fb`, `*factorytest*`, `mediatek.factorymenu.ui`): on some boards
  opening one flips a factory flag that breaks keys or Play services. `dumpsys package <name>` tells you what it is.
- **Undo one package**: `adb shell pm enable <package>`. Undo a list: `tools/restore.sh`.

## Home and launcher

- **`set-home-activity` prints Success and Home does not change.** Look at what Home actually starts:
  `logcat -c; input keyevent KEYCODE_HOME; logcat -d | grep 'START u0'`. JM firmware routes Home through
  `com.jm.jmlauncher` (category `HOME.JM`), which reads `persist.sys.home.selectpkg`. Google TV can route it to
  `setupwraith`. Never disable the router itself.
- **An app is missing from the launcher**: it has no leanback entry (phone apps such as the phone Netflix build, vendor
  settings apps). Add it to `devices/<model>/library_apps.txt` or through the launcher's app library.
- **Projector settings disappeared**: the vendor settings app is usually the only way to keystone/zoom/focus and to reach
  Developer options. Keep it as a dock tile.

## Hardening

- **`tools/harden.sh` says no overlay**: JM firmware ships with `/mnt/scratch` already set up by the vendor's own
  `adb remount`. Elsewhere, `adb root && adb remount` may create it, but on locked bootloaders it fails: block at the router.
- **Never wipe from the stock recovery on T950S/JM units.** A second unit's recovery mounts the `factory` partition
  (`mmcblk0p4`, autofocus/keystone calibration and keys) as `/sdcard` while looking for update packages, so a wipe there
  may take the calibration with it. Reported in #2, deliberately not tested.
- **`skipping malformed recovery.lk line: back_door` in the recovery log is harmless**: it is recovery's own remote key map
  (`/sbin/recovery.kl`), not the firmware backdoor (#2).
- **Generic system images (GSI) do not boot on JM T950S firmware.** SELinux is left out of the kernel and the vendor stripped
  SELinux calls from `init`, `servicemanager` and others, so a standard system image aborts early (#2). This repo cleans
  the stock system instead of replacing it.
- **After a factory reset the backdoor is back**: the overlay is wiped. Keep the projector off Wi-Fi, enable debugging,
  run `tools/harden.sh`, reboot, `tools/scan.sh`, then reconnect.

## Screens and checks

- **Screenshots of video apps come back black or as blocks**: DRM (`FLAG_SECURE`). Check the foreground app with
  `dumpsys activity activities | grep topResumedActivity`, or read the UI with `uiautomator dump`.
- **HDMI/Live TV screenshots are empty**: the video plane is not captured; same check as above.
- **File dates all show one day at boot**: the device has no RTC; times before NTP sync are the build date.
