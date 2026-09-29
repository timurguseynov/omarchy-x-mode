#!/usr/bin/env python3
"""Warm Hyprland IPC for one nest.

hyprctl pays a process start on every call, and the request socket cannot stay
open (Hyprland freezes until a connection closes). This process stays up and
opens the socket only for the length of one command. nestq speaks to it.

Protocol, one connection: a command line, then a 4-byte big-endian length and
that many body bytes.

A command is either a hyprctl invocation ("clients -j", "dispatch ...") or a
query the shell used to answer with its own python ("count foot", "geom foot",
"addrs", "active class|address|workspace", "option <key> <field>").
"""

import socket
import struct
import sys


def hypr_call(path, payload):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(path)
        sock.sendall(payload.encode())
        chunks = []
        while True:
            buf = sock.recv(65536)
            if not buf:
                break
            chunks.append(buf)
    finally:
        sock.close()
    return b"".join(chunks)


def to_payload(cmd):
    # hyprctl's "-j" is a flag on the request, not an argument of the command.
    flags = ""
    if cmd.endswith(" -j"):
        flags = "j"
        cmd = cmd[:-3].rstrip()
    return f"{flags}/{cmd}"


def clients(path):
    import json

    raw = hypr_call(path, "j/clients")
    return json.loads(raw or b"[]")


def first_line_field(text, field):
    line = text.split("\n", 1)[0]
    parts = line.split()
    idx = int(field) - 1
    if idx < 0 or idx >= len(parts):
        return ""
    return parts[idx]


def answer(hypr_sock, cmd):
    parts = cmd.split(" ", 2)
    op = parts[0]
    if op == "count" and len(parts) >= 2:
        cls = parts[1]
        n = 0
        for c in clients(hypr_sock):
            if c.get("class") == cls and c.get("mapped") and c["size"][0] > 0 and c["size"][1] > 0:
                n += 1
        return str(n).encode()
    if op == "count_listed" and len(parts) >= 2:
        cls = parts[1]
        n = sum(1 for c in clients(hypr_sock) if c.get("class") == cls and not c.get("hidden"))
        return str(n).encode()
    if op == "geom" and len(parts) >= 2:
        cls = parts[1]
        for c in clients(hypr_sock):
            if c.get("class") == cls and c.get("mapped"):
                g = len(c.get("grouped") or [])
                at, size = c["at"], c["size"]
                return f"{at[0]} {at[1]} {size[0]} {size[1]} {g}".encode()
        return b""
    if op == "addrs":
        return " ".join(c["address"] for c in clients(hypr_sock)).encode()
    if op == "active" and len(parts) >= 2:
        import json

        kind = parts[1]
        if kind == "workspace":
            raw = hypr_call(hypr_sock, "j/activeworkspace")
            data = json.loads(raw or b"{}") or {}
            return str(data.get("id", "")).encode()
        raw = hypr_call(hypr_sock, "j/activewindow")
        data = json.loads(raw or b"{}") or {}
        if kind == "class":
            return (data.get("class") or "").encode()
        if kind == "address":
            return (data.get("address") or "").encode()
        return b""
    if op == "option" and len(parts) >= 3:
        key, field = parts[1], parts[2]
        raw = hypr_call(hypr_sock, f"/getoption {key}").decode(errors="replace")
        return first_line_field(raw, field).encode()
    if op == "reserved_top":
        import json

        raw = hypr_call(hypr_sock, "j/monitors")
        mons = json.loads(raw or b"[]")
        if not mons:
            return b""
        return str(mons[0]["reserved"][1]).encode()
    body = hypr_call(hypr_sock, to_payload(cmd))
    return body


def serve(listen_path, hypr_sock):
    try:
        import os

        os.unlink(listen_path)
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(listen_path)
    server.listen(4)
    while True:
        conn, _ = server.accept()
        try:
            data = b""
            while b"\n" not in data:
                buf = conn.recv(65536)
                if not buf:
                    break
                data += buf
            cmd = data.split(b"\n", 1)[0].decode(errors="replace")
            try:
                body = answer(hypr_sock, cmd)
            except Exception as exc:
                body = f"ipc error: {exc}\n".encode()
            conn.sendall(struct.pack(">I", len(body)) + body)
        finally:
            conn.close()


if __name__ == "__main__":
    serve(sys.argv[1], sys.argv[2])
