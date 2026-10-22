#!/usr/bin/env bash
# Mail Badge Bridge installer.
# Installs the native helper and its manifest, and builds the add-on package.
# One install serves both Thunderbird and Betterbird.
#
# Usage:
#   ./install.sh                         # install
#   ./install.sh --desktop-file NAME     # launcher name, if it isn't found automatically
set -euo pipefail
cd "$(dirname "$0")"

DESKTOP_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desktop-file)
      DESKTOP_FILE="${2:?--desktop-file needs a name, e.g. thunderbird.desktop}"
      shift ;;
    --thunderbird|--betterbird) ;;  # 1.0 options; the app is detected now
    -h|--help) sed -n 2,8p "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
  shift
done

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mail-badge-bridge"
BIN="$HOME/.local/bin/mail_badge_bridge.py"

# Remember a launcher name the helper can't find by itself.
if [[ -n "$DESKTOP_FILE" ]]; then
  if [[ ! "$DESKTOP_FILE" =~ ^[A-Za-z0-9._-]+\.desktop$ ]]; then
    echo "Invalid launcher name: $DESKTOP_FILE (expected something like thunderbird.desktop)" >&2
    exit 1
  fi
  app=thunderbird
  [[ "${DESKTOP_FILE,,}" == *betterbird* ]] && app=betterbird
  mkdir -p "$CONFIG_DIR"
  conf="$CONFIG_DIR/launchers.conf"
  { grep -v "^$app *=" "$conf" 2>/dev/null || true; echo "$app = $DESKTOP_FILE"; } > "$conf.new"
  mv "$conf.new" "$conf"
fi

mkdir -p "$HOME/.local/bin"
install -m 755 helper/mail_badge_bridge.py "$BIN"

MANIFEST=$(cat <<EOF
{
  "name": "mail_badge_bridge",
  "description": "Mail Badge Bridge helper",
  "path": "$BIN",
  "type": "stdio",
  "allowed_extensions": ["mail-badge-bridge@celest-watches.com"]
}
EOF
)

# ~/.mozilla is the documented Linux location for Mozilla apps. Newer Gecko
# versions may use the XDG config folder instead, so write there too.
for dir in "$HOME/.mozilla/native-messaging-hosts" \
           "${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/native-messaging-hosts"; do
  mkdir -p "$dir"
  printf '%s\n' "$MANIFEST" > "$dir/mail_badge_bridge.json"
done

# Build the add-on package.
(cd addon && rm -f ../mail-badge-bridge.xpi \
  && python3 -m zipfile -c ../mail-badge-bridge.xpi manifest.json background.js)

# Show which launcher each installed app will badge.
for app in thunderbird betterbird; do
  command -v "$app" >/dev/null || continue
  if name=$("$BIN" --launcher "$app"); then
    printf '%-12s badge on %s\n' "${app^}:" "$name"
  else
    printf '%-12s launcher not found. Find yours and rerun with --desktop-file NAME:\n' "${app^}:"
    echo "             ls /usr/share/applications ~/.local/share/applications | grep -i bird"
  fi
done

echo "Add-on built: $(pwd)/mail-badge-bridge.xpi"
echo
echo "Next: Add-ons and Themes -> gear icon -> Install Add-on From File..."
echo "      pick mail-badge-bridge.xpi, then close your mail app and open it again."
