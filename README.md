# Mail Badge Bridge

Shows the **unread count of all your inboxes** as a badge on the **Thunderbird** (or Betterbird) taskbar icon on Linux.

<!-- Add a screenshot: save it as docs/screenshot.png and uncomment the line below.
![Unread badge on the Thunderbird taskbar icon](docs/screenshot.png)
-->

## Why

Thunderbird and Betterbird have an "App icon badge" setting, but on Linux it never sends the count to the taskbar. KDE Plasma supports these badges (through the Unity LauncherEntry D-Bus API), so this project fills the gap:

- **A small add-on** adds up the unread messages in the Inbox of every account.
- **A small Python helper** (no extra packages needed) receives the number and shows it on the taskbar icon.

The badge updates as soon as mail arrives or you read something, and disappears when you close the app. To keep it while the window is closed, see [Keep the badge when the window is closed](#keep-the-badge-when-the-window-is-closed).

## Requirements

- Thunderbird or Betterbird **128 or newer**, installed natively (not as Flatpak or Snap; see [Limitations](#limitations))
- A taskbar that supports Unity LauncherEntry badges, e.g. **KDE Plasma** (for GNOME, see [Limitations](#limitations))
- Python 3

## Install

```bash
git clone https://github.com/bakatamas/mail-badge-bridge.git
cd mail-badge-bridge
./install.sh
```

One install works for both Thunderbird and Betterbird: the helper finds out which app started it. The installer prints which launcher each app will badge. If it can't find yours, pass the name directly:

```bash
ls /usr/share/applications ~/.local/share/applications | grep -i bird   # find the name
./install.sh --desktop-file thunderbird.desktop
```

A name containing "betterbird" is used for Betterbird; any other name, for Thunderbird.

Then, in your mail app:

1. Open **Add-ons and Themes → ⚙ → Install Add-on From File…**
2. Pick `mail-badge-bridge.xpi` from the project folder.
3. Close the app and open it again. (With background mode on, use this rather than its own Restart button: a restart races the background copy for your profile.)

## Keep the badge when the window is closed

The badge lives as long as the mail app runs. The icon must be **pinned** to the taskbar to show a badge with no window open.

**Betterbird** can do this by itself: in **Settings → General**, turn on **"When Betterbird is closed, move it to the tray"**.

**Thunderbird** has no tray icon on Linux, so the installer can keep it running in the background instead:

```bash
./install.sh --background
```

This adds:

- a user service, `mail-badge-bridge-thunderbird.service`, that runs Thunderbird without a window (`--headless`) and starts with your desktop session (one that starts systemd's `graphical-session.target`, as KDE Plasma and GNOME do);
- a launcher that stops the background copy while you have the window open, and starts it again when you close it (only one Thunderbird can use your profile at a time). If you had your own launcher in `~/.local/share/applications`, it's backed up and put back on uninstall.

Notes:

- Open Thunderbird from the app menu or the taskbar icon. If it's started any other way while the background copy runs (a terminal, or a custom launcher handling `mailto:` links), the request goes to the background copy and **no window opens**.
- So email links and `.eml` files must open with the standard launcher. The installer warns if they don't (typically a `userapp-Thunderbird-….desktop` entry). To fix it on KDE Plasma:
  - **Email links:** System Settings → Default Applications → Email client → **Thunderbird**.
  - **`.eml` files:** System Settings → File Associations → `message/rfc822` → move **Thunderbird** to the top.
- Thunderbird will ask to become the default mail client on every start, because it doesn't recognize the launcher as itself. Untick **"Always perform this check when starting Thunderbird"** and click **Skip Integration** (or set `mail.shell.checkDefaultClient` to `false` in the Config Editor). Clicking **Set as Default** creates a new `userapp-Thunderbird-….desktop` entry that bypasses the launcher again.
- If a Thunderbird window is already open when the background copy would start (for example, restored by your desktop at login), the background copy is skipped. It starts the next time you close a window you opened from the launcher.
- Betterbird and Thunderbird usually share the same profile, so with background mode on, Betterbird can't open that profile.
- To turn background mode off, run `./uninstall.sh`, then `./install.sh` again without the flag.

## Uninstall

Remove the add-on in **Add-ons and Themes**, then run:

```bash
./uninstall.sh
```

## Troubleshooting

**No badge at all**

- Press **Ctrl+Shift+J** in your mail app and search for `mail-badge-bridge` (type it in the console's filter box).
  - *"No such native application"* means the helper isn't installed, so run `./install.sh` again.
  - *"… badge on NAME (launcher not found)"* means the helper guessed the launcher name. Rerun the installer with `--desktop-file`.
- Check that your taskbar shows badges at all. With the mail app running, run this (replace the name with your launcher):

  ```bash
  gdbus emit --session --object-path /test \
    --signal com.canonical.Unity.LauncherEntry.Update \
    "application://org.mozilla.Thunderbird.desktop" \
    "{'count': <int64 5>, 'count-visible': <true>}"
  ```

  If no **5** appears, the taskbar icon isn't linked to that launcher. Unpin the icon, start the app from the app menu, and pin it again.
- To watch what the helper sends:

  ```bash
  dbus-monitor "interface='com.canonical.Unity.LauncherEntry'"
  ```

**Background mode**

```bash
systemctl --user status mail-badge-bridge-thunderbird.service
journalctl --user -u mail-badge-bridge-thunderbird.service
```

**Wrong number**

The count includes every folder marked as an Inbox, including a Local Folders Inbox if you have one.

## Limitations

- **Flatpak / Snap** versions of Thunderbird or Betterbird can't start the helper from inside their sandbox.
- **GNOME** doesn't show these badges out of the box. Some dock extensions do, but this hasn't been tested.
- Only tested on **KDE Plasma 6.7** (CachyOS) with Betterbird 153 and Thunderbird. Reports from other setups are very welcome.

## How it works

1. The add-on listens for unread-count changes, adds up all Inboxes, and sends the total to the helper through *native messaging*.
2. The helper checks which app started it, finds that app's launcher, keeps one D-Bus connection open and sends `com.canonical.Unity.LauncherEntry.Update` signals for the launcher.
3. When the mail app closes, the helper clears the badge. If the helper dies unexpectedly, Plasma usually removes the badge itself once the helper's D-Bus connection closes.

## Credits

Built by [Baka Tamás](https://github.com/bakatamas) together with **Claude** (Anthropic's AI assistant).

## License

[MIT](LICENSE)
