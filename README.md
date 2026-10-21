# cleanyourprojector

Debloat, de-backdoor and speed up cheap Android projectors over Wi-Fi. No root needed for the basics, nothing uninstalled,
everything reversible.

Budget Android projectors (T950S, HY300-class, "4K Smart Projector" listings) often ship firmware that is worse than bloated.
The first unit tested here, a **KAW K670**, downloads shell scripts over plain HTTP and runs them as root every time it
connects to Wi-Fi; the vendor server used that channel to install an ad player, push a second root daemon into `/system`
and uninstall competing apps. It also reports 2 GB of RAM while having 1 GB. Details: [docs/JM-FIRMWARE-BACKDOOR.md](docs/JM-FIRMWARE-BACKDOOR.md).

[Tiếng Việt](README.vi.md)

## What it does

| Tool | |
|---|---|
| `tools/scan.sh <ip>` | **Read-only** report: backdoor indicators, spoofed RAM, root ADB, SELinux, adware, silent installers, LAN listeners, uncompiled apps |
| `tools/disable.sh <ip> <list>` | `pm disable-user` every package in a device list |
| `tools/restore.sh <ip> <list>` | re-enable them, undo Private DNS, give Home back to the stock launcher |
| `tools/harden.sh <ip>` | close the JM backdoor and every route back (init scripts, su daemon, OTA, USB auto-install, C2 hosts/IP), re-applied on each boot; originals quarantined |
| `tools/optimize.sh <ip>` | fewer cached processes, faster animations, AOT-compile the apps the projector never compiled |
| `tools/install-launcher.sh <ip> devices/<model>` | build and install the [cleanyourtv](https://github.com/Gathin23/cleanyourtv) Apple-TV-style launcher with a per-device config, including JM's `HOME.JM` routing |

## Quick start

On the projector: enable Developer options and USB debugging. Then, on a computer on the same network:

```sh
git clone --recurse-submodules https://github.com/tqhit/cleanyourprojector
cd cleanyourprojector
tools/scan.sh 192.168.1.50
```

Read the report, then follow `devices/<model>/README.md`, or paste [PROMPT.md](PROMPT.md) into Claude Code and let it walk
through your unit. Needs `adb`; the launcher build also needs JDK 17 and the Android SDK (platform 34).

**When you are done, switch USB debugging off.** On JM firmware ADB is root and needs no confirmation, so anyone on your
network who reaches port 5555 owns the projector.

## Devices

| Device | Firmware | Notes |
|---|---|---|
| [KAW K670](devices/kaw-k670/) | JM, Amlogic T950S, Android 13 | backdoor, 1 GB RAM reported as 2 GB, Home via `com.jm.jmlauncher` |

Add yours: copy a device folder, keep it free of personal data (serial, MAC, Wi-Fi name, account names), open a PR.

## Limits

- A factory reset restores the firmware backdoor (the fixes live in the adb-remount overlay that a reset wipes). Re-run
  `tools/harden.sh` before putting the projector back on Wi-Fi.
- The framework-level trigger cannot be removed without reflashing. The only complete fix is to keep the projector off the
  network and play from an HDMI streaming stick, which is also the biggest speed upgrade.
- Netflix on these units is usually the phone build; it needs the vendor's remote-mouse helper to be usable with a remote.

## Credits

Built on [cleanyourtv](https://github.com/Gathin23/cleanyourtv) by Gathin (MIT), included as a submodule for the launcher
and as the model for this repo's approach. cleanyourprojector is an independent project, not affiliated with cleanyourtv.

MIT license.
