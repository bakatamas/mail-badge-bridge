#!/usr/bin/env bash
# Mail Badge Bridge uninstaller: removes the helper and its manifests.
# Remove the add-on itself in your mail app (Add-ons and Themes).
set -euo pipefail

rm -fv "$HOME/.local/bin/mail_badge_bridge.py" \
       "$HOME/.mozilla/native-messaging-hosts/mail_badge_bridge.json" \
       "${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/native-messaging-hosts/mail_badge_bridge.json"
rm -rfv "${XDG_CONFIG_HOME:-$HOME/.config}/mail-badge-bridge"

echo "Done. Also remove the add-on in Add-ons and Themes, then close your mail app and open it again."
