#!/usr/bin/env bash
# Mail Badge Bridge uninstaller: removes the helper, its manifests, and
# background mode if it was set up.
# Remove the add-on itself in your mail app (Add-ons and Themes).
set -euo pipefail

APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mail-badge-bridge"
WRAPPER="$HOME/.local/bin/mail-badge-bridge-launch"
SERVICE="mail-badge-bridge-thunderbird.service"

# Background mode. Stopping the service lets Thunderbird shut down cleanly.
if [[ -f "$HOME/.config/systemd/user/$SERVICE" ]]; then
  systemctl --user disable --now "$SERVICE" || true
  rm -fv "$HOME/.config/systemd/user/$SERVICE"
  systemctl --user daemon-reload || true
fi
# Remove the launchers pointing at the wrapper, then restore any we replaced.
for f in "$APPS_DIR"/*.desktop; do
  [[ -f "$f" ]] && grep -q "$WRAPPER" "$f" && rm -fv "$f"
done
for backup in "$STATE_DIR"/*.desktop.backup; do
  [[ -f "$backup" ]] || continue
  name=$(basename "$backup" .backup)
  mv -v "$backup" "$APPS_DIR/$name"
done
rm -rf "$STATE_DIR"

rm -fv "$WRAPPER" \
       "$HOME/.local/bin/mail_badge_bridge.py" \
       "$HOME/.mozilla/native-messaging-hosts/mail_badge_bridge.json" \
       "${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/native-messaging-hosts/mail_badge_bridge.json"
rm -rfv "${XDG_CONFIG_HOME:-$HOME/.config}/mail-badge-bridge"

echo "Done. Also remove the add-on in Add-ons and Themes, then close your mail app and open it again."
