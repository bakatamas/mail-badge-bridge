#!/usr/bin/env python3
"""Mail Badge Bridge - native messaging host.

Receives {"count": N} from the Thunderbird/Betterbird add-on and shows N as a
taskbar badge via the Unity LauncherEntry D-Bus signal. It works out which of
the two apps started it, so one install serves both.

Plasma removes a badge when the D-Bus connection that sent it disconnects,
so this helper keeps one session-bus connection open for its whole life
(minimal pure-Python D-Bus client, no extra packages needed)."""

import json
import os
import signal
import socket
import struct
import sys
from urllib.parse import unquote

OBJECT_PATH = "/com/celestwatches/MailBadgeBridge"

# The badge only shows on the taskbar icon whose launcher (.desktop file) name
# matches, and distros name them differently. First one found wins.
LAUNCHERS = {
    "thunderbird": ["org.mozilla.Thunderbird.desktop", "thunderbird.desktop",
                    "mozilla-thunderbird.desktop"],
    "betterbird": ["eu.betterbird.Betterbird.desktop", "betterbird.desktop"],
}
# Optional overrides, one "app = name.desktop" per line (written by install.sh).
CONFIG = os.path.join(os.environ.get("XDG_CONFIG_HOME")
                      or os.path.expanduser("~/.config"),
                      "mail-badge-bridge", "launchers.conf")


# --- which launcher to badge -----------------------------------------------

def detect_app():
    """The mail app starts this helper directly, so the parent is the app."""
    try:
        exe = os.path.basename(os.readlink(f"/proc/{os.getppid()}/exe"))
    except OSError:
        exe = ""
    return "betterbird" if "betterbird" in exe.lower() else "thunderbird"


def read_overrides():
    overrides = {}
    try:
        with open(CONFIG) as f:
            for line in f:
                app, sep, name = line.partition("=")
                if sep and not app.strip().startswith("#"):
                    overrides[app.strip().lower()] = name.strip()
    except OSError:
        pass
    return overrides


def find_launcher(app):
    """Return (launcher name, whether it was found on disk)."""
    name = read_overrides().get(app)
    if name:
        return name, True
    data_dirs = [os.environ.get("XDG_DATA_HOME")
                 or os.path.expanduser("~/.local/share")]
    data_dirs += (os.environ.get("XDG_DATA_DIRS")
                  or "/usr/local/share:/usr/share").split(":")
    candidates = LAUNCHERS.get(app, LAUNCHERS["thunderbird"])
    for name in candidates:
        for d in data_dirs:
            if os.path.isfile(os.path.join(d, "applications", name)):
                return name, True
    return candidates[0], False


# --- minimal D-Bus wire protocol (little endian) ---------------------------

class _W:
    def __init__(self):
        self.b = bytearray()

    def align(self, n):
        self.b += b"\0" * (-len(self.b) % n)

    def byte(self, v):
        self.b.append(v)

    def u32(self, v):
        self.align(4)
        self.b += struct.pack("<I", v)

    def i64(self, v):
        self.align(8)
        self.b += struct.pack("<q", v)

    def string(self, s):  # also used for object paths
        data = s.encode()
        self.u32(len(data))
        self.b += data + b"\0"

    def sig(self, s):
        self.byte(len(s))
        self.b += s.encode() + b"\0"

    def array(self, elem_align, items, write_item):
        self.u32(0)
        len_pos = len(self.b) - 4
        self.align(elem_align)
        start = len(self.b)
        for it in items:
            write_item(it)
        struct.pack_into("<I", self.b, len_pos, len(self.b) - start)


def _variant(w, sig, value):
    w.sig(sig)
    if sig in ("s", "o"):
        w.string(value)
    elif sig == "g":
        w.sig(value)
    elif sig == "x":
        w.i64(value)
    elif sig == "b":
        w.u32(1 if value else 0)
    else:
        raise ValueError(sig)


class SessionBus:
    def __init__(self):
        self.sock = self._connect()
        self.serial = 0
        self._auth()
        self._send(1, "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello",
                   destination="org.freedesktop.DBus")

    @staticmethod
    def _connect():
        addr = os.environ.get("DBUS_SESSION_BUS_ADDRESS",
                              f"unix:path=/run/user/{os.getuid()}/bus")
        for entry in addr.split(";"):
            if not entry.startswith("unix:"):
                continue
            params = {k: unquote(v) for k, v in
                      (p.split("=", 1) for p in entry[5:].split(",") if "=" in p)}
            if "path" in params:
                target = params["path"]
            elif "abstract" in params:
                target = "\0" + params["abstract"]
            else:
                continue
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                s.connect(target)
                return s
            except OSError:
                s.close()  # try the next address, if any
        raise RuntimeError(f"cannot connect to D-Bus session bus: {addr}")

    def _auth(self):
        uid_hex = str(os.getuid()).encode().hex()
        self.sock.sendall(b"\0AUTH EXTERNAL " + uid_hex.encode() + b"\r\n")
        reply = b""
        while not reply.endswith(b"\r\n"):
            chunk = self.sock.recv(256)
            if not chunk:
                raise RuntimeError("D-Bus closed during auth")
            reply += chunk
        if not reply.startswith(b"OK"):
            raise RuntimeError(f"D-Bus auth failed: {reply!r}")
        self.sock.sendall(b"BEGIN\r\n")

    def _send(self, msg_type, path, interface, member, destination=None,
              body_sig=None, body=b""):
        self.serial += 1
        fields = [(1, "o", path), (2, "s", interface), (3, "s", member)]
        if destination:
            fields.append((6, "s", destination))
        if body_sig:
            fields.append((8, "g", body_sig))

        w = _W()

        def write_field(f):
            w.align(8)
            w.byte(f[0])
            _variant(w, f[1], f[2])

        w.byte(ord("l"))
        w.byte(msg_type)
        w.byte(0)
        w.byte(1)
        w.u32(len(body))
        w.u32(self.serial)
        w.array(8, fields, write_field)
        w.align(8)
        self.sock.sendall(bytes(w.b) + body)
        self._drain()

    def _drain(self):
        # Discard replies/signals sent to us so the socket buffer never fills.
        self.sock.setblocking(False)
        try:
            while self.sock.recv(4096):
                pass
        except BlockingIOError:
            pass
        finally:
            self.sock.setblocking(True)

    def emit_badge(self, app_uri, count):
        w = _W()
        w.string(app_uri)
        props = [("count", "x", count), ("count-visible", "b", count > 0)]

        def write_entry(p):
            w.align(8)
            w.string(p[0])
            _variant(w, p[1], p[2])

        w.array(8, props, write_entry)
        self._send(4, OBJECT_PATH, "com.canonical.Unity.LauncherEntry", "Update",
                   body_sig="sa{sv}", body=bytes(w.b))


# --- native messaging ------------------------------------------------------

def read_message():
    raw_len = sys.stdin.buffer.read(4)
    if len(raw_len) < 4:
        return None
    length = struct.unpack("@I", raw_len)[0]
    return json.loads(sys.stdin.buffer.read(length))


def main():
    # install.sh asks which launcher an app would use: --launcher thunderbird
    if len(sys.argv) == 3 and sys.argv[1] == "--launcher":
        name, found = find_launcher(sys.argv[2])
        print(name)
        sys.exit(0 if found else 1)

    app = detect_app()
    name, found = find_launcher(app)
    app_uri = "application://" + name
    # Shows up in the mail app's Error Console (Ctrl+Shift+J).
    print(f"mail-badge-bridge: {app} badge on {name}"
          + ("" if found else " (launcher not found)"), file=sys.stderr)

    # If the mail app kills the helper instead of closing stdin, still clear the badge.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    bus = SessionBus()
    try:
        while True:
            msg = read_message()
            if msg is None:
                break
            bus.emit_badge(app_uri, max(0, int(msg.get("count", 0))))
    finally:
        try:
            bus.emit_badge(app_uri, 0)  # mail app closed: hide the badge
        except OSError:
            pass


if __name__ == "__main__":
    main()
