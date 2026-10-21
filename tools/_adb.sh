# Shared helpers, sourced by the other tools. Takes the device as $1 (ip, ip:port or an adb serial) or $DEV.
# shellcheck shell=bash
DEV="${1:-${DEV:-}}"
[ -n "$DEV" ] || { echo "usage: $0 <projector ip[:port] or adb serial> ..." >&2; exit 2; }
# A bare IP gets :5555; a USB serial (no dots) is used as is.
case "$DEV" in *:*) ;; *.*.*.*) DEV="$DEV:5555" ;; esac
case "$DEV" in *:*) adb connect "$DEV" >/dev/null 2>&1 ;; esac
command -v adb >/dev/null || { echo "adb not found: install Android platform-tools" >&2; exit 1; }
# S: run on the device, stderr included (for commands whose result you print).
# Q: run on the device, stderr dropped (for probes).
S(){ adb -s "$DEV" shell "$@" 2>&1 | tr -d '\r'; }
Q(){ adb -s "$DEV" shell "$@" 2>/dev/null | tr -d '\r'; }
[ "$(Q echo ok)" = ok ] || { echo "cannot reach $DEV over ADB: enable USB/Network debugging and accept the prompt on the screen" >&2; exit 1; }
export ROOT=0; case "$(Q id)" in uid=0*) export ROOT=1 ;; esac
# Package names from a list file: one per line, '#' comments allowed; anything else is refused,
# because each name ends up in a shell command on the device.
pkgs(){
  local list
  list=$(sed -E 's/#.*//' "$1" | awk 'NF{print $1}')
  if printf '%s\n' "$list" | grep -vqE '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$'; then
    echo "refusing $1: contains something that is not a package name" >&2; exit 1
  fi
  printf '%s\n' "$list"
}
# Indicators from data/indicators.tsv: indicators <type> prints "value<TAB>severity<TAB>note".
indicators(){ grep -v '^#' data/indicators.tsv | awk -F'\t' -v t="$1" '$1==t{print $2"\t"$3"\t"$5}'; }
# A file name for this unit's backups: model, spaces replaced, no serial.
model_slug(){ Q getprop ro.product.model | tr 'A-Z ' 'a-z-' | tr -cd 'a-z0-9._-'; }
