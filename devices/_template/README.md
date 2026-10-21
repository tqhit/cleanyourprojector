# <Brand Model>

| | |
|---|---|
| Board | <SoC, ro.board.platform, ro.hardware> |
| Android | <version (API), build type, SELinux> |
| RAM | <physical from dmesg / what /proc/meminfo claims> |
| Display | <wm size @ Hz from dumpsys display> |
| Firmware | <vendor family, any ro.*.board.name> |
| Stock Home | <package, and anything that routes Home to it> |
| ADB | <root or not, ro.adb.secure, network port> |

## Run order

```sh
tools/scan.sh <ip>
tools/backup.sh <ip>
tools/disable.sh <ip> devices/<model>/debloat.txt
tools/harden.sh <ip>
tools/optimize.sh <ip>
tools/install-launcher.sh <ip> devices/<model>     # optional
```

## Quirks found on this unit

- <what needed care, what must not be disabled and why, what came back after a reboot>

## Measured

| | before | after |
|---|---|---|
| <main app> cold start (`am start -W`) | | |
