# Mail Badge Bridge

Shows the **unread count of all your inboxes** as a badge on the **Betterbird** (or Thunderbird) taskbar icon on Linux.

<!-- Add a screenshot: save it as docs/screenshot.png and uncomment the line below.
![Unread badge on the Betterbird taskbar icon](docs/screenshot.png)
-->

## Why

Betterbird has an "App icon badge" setting, but on Linux it never sends the count to the taskbar. KDE Plasma supports these badges (through the Unity LauncherEntry D-Bus API), so this project fills the gap:

- **A small add-on** adds up the unread messages in the Inbox of every account.
- **A small Python helper** (no extra packages needed) receives the number and shows it on the taskbar icon.

The badge updates as soon as mail arrives or you read something, and disappears when you close the app.

## Requirements

- Betterbird or Thunderbird **128 or newer**, installed natively (not as Flatpak or Snap; see [Limitations](#limitations))
- A taskbar that supports Unity LauncherEntry badges, e.g. **KDE Plasma**
- Python 3

## Install

```bash
git clone https://github.com/bakatamas/mail-badge-bridge.git
cd mail-badge-bridge
./install.sh
```

For **Thunderbird**, use `./install.sh --thunderbird`. If your launcher has a different name, pass it directly:

```bash
ls /usr/share/applications ~/.local/share/applications | grep -i bird   # find the name
./install.sh --desktop-file thunderbird.desktop
```

Then, in your mail app:

1. Open **Add-ons and Themes → ⚙ → Install Add-on From File…**
2. Pick `mail-badge-bridge.xpi` from the project folder.
3. Restart the app.

## Uninstall

Remove the add-on in **Add-ons and Themes**, then run:

```bash
./uninstall.sh
```

## Troubleshooting

**No badge at all**

- Press **Ctrl+Shift+J** in your mail app and look for lines starting with `mail-badge-bridge:`.
  - *"No such native application"* means the helper isn't installed, so run `./install.sh` again.
- Check that your taskbar shows badges at all. With the mail app running, run this (replace the name with your launcher):

  ```bash
  gdbus emit --session --object-path /test \
    --signal com.canonical.Unity.LauncherEntry.Update \
    "application://eu.betterbird.Betterbird.desktop" \
    "{'count': <int64 5>, 'count-visible': <true>}"
  ```

  If no **5** appears, the taskbar icon isn't linked to that launcher. Unpin the icon, start the app from the app menu, and pin it again.
- To watch what the helper sends:

  ```bash
  dbus-monitor "interface='com.canonical.Unity.LauncherEntry'"
  ```

**Wrong number**

The count includes every folder marked as an Inbox, including a Local Folders Inbox if you have one.

## Limitations

- **Flatpak / Snap** versions of Betterbird or Thunderbird can't start the helper from inside their sandbox.
- **GNOME** doesn't show these badges out of the box. Some dock extensions do, but this hasn't been tested.
- Only tested on **Betterbird 153 + KDE Plasma 6.7** (CachyOS). Reports from other setups are very welcome.

## How it works

1. The add-on listens for unread-count changes, adds up all Inboxes, and sends the total to the helper through *native messaging*.
2. The helper keeps one D-Bus connection open and sends `com.canonical.Unity.LauncherEntry.Update` signals for your mail app's launcher.
3. When the mail app closes, the helper clears the badge. If the helper dies unexpectedly, Plasma usually removes the badge itself once the helper's D-Bus connection closes.

## Credits

Built by [Baka Tamás](https://github.com/bakatamas) together with **Claude** (Anthropic's AI assistant).

## License

[MIT](LICENSE)
