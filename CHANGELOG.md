# Changelog

## 1.1.0 — 2026-10-22

- Thunderbird is now the main target; Betterbird keeps working.
- One install serves both apps: the helper detects which app started it and finds that app's launcher (several distro naming schemes are checked).
- `--desktop-file NAME` now saves an override instead of editing the helper; `--thunderbird` and `--betterbird` are no longer needed.
- New `./install.sh --background`: keeps Thunderbird running headless as a user service, so the badge stays while the window is closed. It warns if email links or `.eml` files are set to open in a way that bypasses it.
- `uninstall.sh` also removes background mode and restores any launcher it replaced.

## 1.0.0 — 2026-10-15

First release.

- Add-on sums the unread count of every account's Inbox.
- Python helper shows the count as a taskbar badge (Unity LauncherEntry D-Bus API), with no extra packages.
- Badge clears when the mail app closes.
- `install.sh` supports Betterbird (default), `--thunderbird` and `--desktop-file NAME`.
- `uninstall.sh` removes the helper.
