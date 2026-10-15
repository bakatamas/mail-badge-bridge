#!/usr/bin/env python3
"""Mail Badge Bridge - native messaging host.

Receives {"count": N} from the Betterbird/Thunderbird add-on and shows N as a
taskbar badge via the Unity LauncherEntry D-Bus signal.

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

# install.sh rewrites this line when you pick another mail app.
APP_URI = "application://eu.betterbird.Betterbird.desktop"
OBJECT_PATH = "/com/celestwatches/MailBadgeBridge"


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

    def emit_badge(self, count):
        w = _W()
        w.string(APP_URI)
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
    # If Betterbird kills the helper instead of closing stdin, still clear the badge.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    bus = SessionBus()
    try:
        while True:
            msg = read_message()
            if msg is None:
                break
            bus.emit_badge(max(0, int(msg.get("count", 0))))
    finally:
        try:
            bus.emit_badge(0)  # Betterbird closed: hide the badge
        except OSError:
            pass


if __name__ == "__main__":
    main()
