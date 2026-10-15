#!/usr/bin/env bash
# Mail Badge Bridge installer.
# Installs the native helper and its manifest, and builds the add-on package.
#
# Usage:
#   ./install.sh                         # Betterbird (default)
#   ./install.sh --thunderbird           # Thunderbird
#   ./install.sh --desktop-file NAME     # any launcher, e.g. thunderbird.desktop
set -euo pipefail
cd "$(dirname "$0")"

DESKTOP_FILE="eu.betterbird.Betterbird.desktop"
case "${1:-}" in
  "") ;;
  --thunderbird) DESKTOP_FILE="org.mozilla.Thunderbird.desktop" ;;
  --desktop-file)
    DESKTOP_FILE="${2:?--desktop-file needs a name, e.g. thunderbird.desktop}" ;;
  -h|--help) sed -n 2,8p "$0"; exit 0 ;;
  *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
esac

# Reject odd names: they would break the sed edit below.
if [[ ! "$DESKTOP_FILE" =~ ^[A-Za-z0-9._-]+\.desktop$ ]]; then
  echo "Invalid launcher name: $DESKTOP_FILE (expected something like thunderbird.desktop)" >&2
  exit 1
fi

# Warn if the launcher can't be found: the badge only shows on a matching icon.
found=""
for d in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications; do
  [[ -f "$d/$DESKTOP_FILE" ]] && found="$d/$DESKTOP_FILE" && break
done
if [[ -z "$found" ]]; then
  echo "Warning: $DESKTOP_FILE not found in the usual folders."
  echo "         The badge needs the exact launcher name. Find yours with:"
  echo "         ls /usr/share/applications ~/.local/share/applications | grep -i bird"
fi

BIN="$HOME/.local/bin/mail_badge_bridge.py"
mkdir -p "$HOME/.local/bin"
sed "s|^APP_URI = .*|APP_URI = \"application://$DESKTOP_FILE\"|" \
  helper/mail_badge_bridge.py > "$BIN"
chmod 755 "$BIN"

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

echo "Helper installed for: $DESKTOP_FILE"
echo "Add-on built:         $(pwd)/mail-badge-bridge.xpi"
echo
echo "Next: Add-ons and Themes -> gear icon -> Install Add-on From File..."
echo "      pick mail-badge-bridge.xpi, then restart your mail app."
