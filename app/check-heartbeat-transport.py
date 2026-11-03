#!/usr/bin/env python3
"""Synthetic loopback tests only; never connects to the company server."""
import pathlib
import socket
import struct
import subprocess
import tempfile
import threading
import zlib

APP = pathlib.Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="nac-heartbeat-check-") as temp:
    executable = pathlib.Path(temp) / "check"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-module-cache-path", "/private/tmp/nac-swift-module-cache",
        *map(str, sorted((APP / "Sources/NACProtocol").glob("*.swift"))), str(APP / "Sources/HeartbeatProbe.swift"),
        str(APP / "Checks/HeartbeatTransportCheck.swift"), "-o", str(executable)], check=True)
    for mode in ["echo", "continuous", "role", "idleclose", "push", "corrupt", "timeout", "cancel"]:
        errors = []
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            listener.settimeout(5)
            port = listener.getsockname()[1]

            def peer():
                try:
                    with listener.accept()[0] as connection:
                        connection.settimeout(5)
                        for packet_index in range(3 if mode in ["continuous", "role"] else 2 if mode == "push" else 1):
                            received = bytearray()
                            while len(received) < 60:
                                chunk = connection.recv(60 - len(received))
                                if not chunk: return
                                received.extend(chunk)
                            size = struct.unpack_from("<I", received)[0]
                            assert 60 < size < 4096
                            while len(received) < size:
                                chunk = connection.recv(size - len(received))
                                if not chunk: return
                                received.extend(chunk)
                            assert received[4:8] == b"ASM5"
                            if mode in ["echo", "continuous", "role", "idleclose", "push"]:
                                if mode == "echo" or (mode == "push" and packet_index == 1):
                                    key = b"infogo"
                                    def decode(data):
                                        return bytes((((v << 4) | (v >> 4)) & 255) ^ key[i % 6] for i, v in enumerate(data))
                                    def encode(data):
                                        return bytes((((v ^ key[i % 6]) << 4) | ((v ^ key[i % 6]) >> 4)) & 255 for i, v in enumerate(data))
                                    payload = zlib.decompress(decode(received[60:]))
                                    if mode == "push":
                                        payload = b"<ASM><TradeCode>SvrMsgToAss</TradeCode><Token>synthetic-secret-must-not-display</Token></ASM>"
                                        received[20:52] = encode(b"SvrMsgToAss".ljust(32, b"\0"))
                                    else:
                                        payload = payload.replace(b"</ASM>", b"<RetCode>0</RetCode><Token>synthetic-secret-must-not-display</Token></ASM>")
                                    compressed = encode(zlib.compress(payload, 9))
                                    received = received[:60] + compressed
                                    struct.pack_into("<I", received, 0, len(received))
                                    struct.pack_into("<I", received, 56, len(payload))
                                if mode == "role":
                                    key = b"infogo"
                                    def encode_role(data):
                                        return bytes((((v ^ key[i % 6]) << 4) | ((v ^ key[i % 6]) >> 4)) & 255 for i, v in enumerate(data))
                                    payload = b"<ASM><TradeCode>RoleChanged</TradeCode></ASM>"
                                    notice = received[:60] + encode_role(zlib.compress(payload, 9))
                                    notice[20:52] = encode_role(b"RoleChanged".ljust(32, b"\0"))
                                    struct.pack_into("<I", notice, 0, len(notice))
                                    struct.pack_into("<I", notice, 56, len(payload))
                                    # Notification precedes the ACK in the same write.
                                    received = notice + received
                                connection.sendall(received[:7])
                                connection.sendall(received[7:])
                            elif mode == "corrupt":
                                received[4] ^= 255
                                connection.sendall(received)
                            else:
                                while connection.recv(4096): pass
                except Exception as error:
                    errors.append(error)

            thread = threading.Thread(target=peer, daemon=True)
            thread.start()
            subprocess.run([str(executable), str(port), mode], check=True, timeout=10)
            thread.join(6)
            assert not thread.is_alive() and not errors, errors
