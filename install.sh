#!/usr/bin/env bash
# Mail Badge Bridge installer.
# Installs the native helper and its manifest, and builds the add-on package.
# One install serves both Thunderbird and Betterbird.
#
# Usage:
#   ./install.sh                         # install
#   ./install.sh --background            # also keep Thunderbird running in the background
#   ./install.sh --desktop-file NAME     # launcher name, if it isn't found automatically
set -euo pipefail
cd "$(dirname "$0")"

BACKGROUND=""
DESKTOP_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --background) BACKGROUND=1 ;;
    --desktop-file)
      DESKTOP_FILE="${2:?--desktop-file needs a name, e.g. thunderbird.desktop}"
      shift ;;
    --thunderbird|--betterbird) ;;  # 1.0 options; the app is detected now
    -h|--help) sed -n 2,9p "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
  shift
done

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mail-badge-bridge"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mail-badge-bridge"
BIN="$HOME/.local/bin/mail_badge_bridge.py"
WRAPPER="$HOME/.local/bin/mail-badge-bridge-launch"
SERVICE="mail-badge-bridge-thunderbird.service"

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

if [[ -n "$BACKGROUND" ]]; then
  TB=$(command -v thunderbird) || { echo "--background needs Thunderbird, which isn't installed." >&2; exit 1; }
  LAUNCHER=$("$BIN" --launcher thunderbird) || {
    echo "--background needs Thunderbird's launcher; rerun with --desktop-file NAME." >&2; exit 1; }

  # The launcher starts Thunderbird through a wrapper that stops the
  # background copy first: only one Thunderbird can use the profile at a time.
  cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
# Mail Badge Bridge: opens the Thunderbird window. The background copy stops
# while the window is open and starts again when it closes.
exec 9>"\${XDG_RUNTIME_DIR:-/tmp}/mail-badge-bridge-launch.lock"
if ! flock -n 9; then
  # The window is already open: pass the request (e.g. a mailto: link) to it.
  exec "$TB" "\$@"
fi
systemctl --user stop $SERVICE
"$TB" "\$@"
systemctl --user start $SERVICE
EOF
  chmod 755 "$WRAPPER"

  # Override the launcher under the same name, so the badge still matches it.
  # Keep a launcher you made yourself, to put back on uninstall.
  mkdir -p "$APPS_DIR" "$STATE_DIR"
  local_launcher="$APPS_DIR/$LAUNCHER"
  if [[ -f "$local_launcher" ]] && ! grep -q "$WRAPPER" "$local_launcher"; then
    cp "$local_launcher" "$STATE_DIR/$LAUNCHER.backup"
  fi
  src="$STATE_DIR/$LAUNCHER.backup"
  if [[ ! -f "$src" ]]; then
    src=""
    IFS=: read -ra data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for d in "${data_dirs[@]}"; do
      [[ -f "$d/applications/$LAUNCHER" ]] && src="$d/applications/$LAUNCHER" && break
    done
  fi
  [[ -n "$src" ]] || { echo "Can't find $LAUNCHER to copy." >&2; exit 1; }
  sed -E -e "s|^Exec=[^ ]+|Exec=$WRAPPER|" -e '/^DBusActivatable=/d' "$src" > "$local_launcher"

  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/$SERVICE" <<EOF
[Unit]
Description=Thunderbird in the background (Mail Badge Bridge)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
# If a window is already open (e.g. restored at login), a second Thunderbird
# would only hand over to it and exit, so don't start one.
ExecCondition=/bin/sh -c '! pgrep -u %U -x thunderbird >/dev/null'
ExecStart=$TB --headless
Restart=on-failure
RestartSec=10

[Install]
WantedBy=graphical-session.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable "$SERVICE"
  if systemctl --user is-active --quiet "$SERVICE"; then
    :  # already running from an earlier install
  elif pgrep -u "$(id -u)" -x thunderbird >/dev/null; then
    echo "Thunderbird is open. Close it, then run: systemctl --user start $SERVICE"
    echo "(From now on, closing the window does this for you.)"
  else
    systemctl --user start "$SERVICE"
  fi
  echo "Background mode on: $SERVICE"

  # Email links and .eml files must open through this launcher, or they go to
  # the background copy and no window opens. Only warn: defaults are the user's.
  if command -v xdg-mime >/dev/null; then
    for pair in "x-scheme-handler/mailto:Email links (mailto:)" "message/rfc822:.eml files"; do
      handler=$(xdg-mime query default "${pair%%:*}" 2>/dev/null || true)
      if [[ -n "$handler" && "$handler" != "$LAUNCHER" ]]; then
        echo "Warning: ${pair#*:} open with $handler, so in background mode no window opens."
        echo "         Make Thunderbird the default for them in your system settings."
      fi
    done
  fi
fi

echo "Add-on built: $(pwd)/mail-badge-bridge.xpi"
echo
echo "Next: Add-ons and Themes -> gear icon -> Install Add-on From File..."
echo "      pick mail-badge-bridge.xpi, then close your mail app and open it again."
