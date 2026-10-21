# Shared helpers, sourced by the other tools. Expects DEV (ip[:port]) as $1 or in the environment.
DEV="${1:-${DEV:-}}"
[ -n "$DEV" ] || { echo "usage: $0 <projector ip[:port]> ..." >&2; exit 2; }
case "$DEV" in *:*) ;; *) DEV="$DEV:5555" ;; esac
adb connect "$DEV" >/dev/null 2>&1
S(){ adb -s "$DEV" shell "$@" 2>&1 | tr -d '\r'; }
[ "$(S echo ok)" = ok ] || { echo "cannot reach $DEV over ADB (enable USB/Network debugging first)" >&2; exit 1; }
# Package names from a list file: one per line, '#' comments allowed; anything else is refused.
pkgs(){
  local list
  list=$(sed -E 's/#.*//' "$1" | awk 'NF{print $1}')
  if printf '%s\n' "$list" | grep -vqE '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$'; then
    echo "refusing $1: contains something that is not a package name" >&2; exit 1
  fi
  printf '%s\n' "$list"
}
