#!/usr/bin/env python3
"""Exercise desktop device discovery against a synthetic loopback peer."""
import pathlib
import socket
import struct
import subprocess
import tempfile
import threading
import xml.etree.ElementTree as ET
import zlib

APP = pathlib.Path(__file__).resolve().parent
KEY = b"infogo"
HEADER = struct.Struct("<I4sIII32sII")
TRADE = b"UpdateAgentInfo"


def encode(data):
    return bytes((((value ^ KEY[index % 6]) << 4) & 255) | ((value ^ KEY[index % 6]) >> 4)
                 for index, value in enumerate(data))


def decode(data):
    return bytes(((value << 4) & 255 | value >> 4) ^ KEY[index % 6]
                 for index, value in enumerate(data))


def receive(connection, count):
    data = bytearray()
    while len(data) < count:
        chunk = connection.recv(count - len(data))
        if not chunk:
            raise EOFError("Incomplete desktop discovery request")
        data.extend(chunk)
    return bytes(data)


def send_reply(connection, scenario):
    length, magic, kind, zipped, transformed, trade, serial, size = HEADER.unpack(
        receive(connection, HEADER.size))
    assert 60 < length < 4096
    assert (magic, kind, zipped, transformed, serial) == (b"ASM5", 1, 1, 1, 7241)
    assert decode(trade).rstrip(b"\0") == TRADE
    report = zlib.decompress(decode(receive(connection, length - HEADER.size)))
    assert len(report) == size
    xml = ET.fromstring(report.decode("gbk"))
    assert xml.tag == "ASM" and xml.findtext("TradeCode") == TRADE.decode()
    assert xml.findtext("AgentID") == "" and xml.findtext("ServerID") == ""
    assert xml.findtext("UserID") == "" and xml.findtext("Token") == ""
    assert xml.findtext("SubType") == "mac" and xml.findtext("DeviceType") == "300"
    assert xml.findtext("ComputerName") == "测试 & <Mac>"
    assert xml.findtext("IP") == "192.0.2.20" and xml.findtext("MAC") == "00:01:02:03:04:05"
    assert xml.findtext("RealDiskId") == "00112233-4455-6677-8899-AABBCCDDEEFF"

    agent = {
        "missing-id": "",
        "zero-id": "<AgentID>0</AgentID>",
        "duplicate-id": "<AgentID>4831</AgentID><AgentID>4832</AgentID>",
    }.get(scenario, "<AgentID>4831</AgentID>")
    xml_trade = "HeartTest" if scenario == "wrong-trade" else TRADE.decode()
    doctype = "<!DOCTYPE ASM []>" if scenario == "doctype" else ""
    response = (f'<?xml version="1.0" encoding="gbk"?>{doctype}<ASM><TradeCode>{xml_trade}</TradeCode>'
                f'{agent}<ServerID>server-test</ServerID><Registered>-1</Registered>'
                '<Message>合成响应</Message></ASM>').encode("gbk")
    wire = encode(zlib.compress(response, 9))
    reply_serial = serial + 1 if scenario == "wrong-serial" else serial
    frame = HEADER.pack(HEADER.size + len(wire), b"ASM5", 1, 1, 1,
                        encode(TRADE.ljust(32, b"\0")), reply_serial, len(response)) + wire
    for index in range(0, len(frame), 13):
        connection.sendall(frame[index:index + 13])


with tempfile.TemporaryDirectory(prefix="nac-desktop-check-") as directory:
    executable = pathlib.Path(directory) / "check"
    sources = sorted((APP / "Sources/NACProtocol").glob("*.swift"))
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-module-cache-path",
                    "/private/tmp/nac-swift-module-cache", *map(str, sources),
                    str(APP / "Sources/DesktopDeviceDiscoveryProbe.swift"),
                    str(APP / "Checks/DesktopDeviceDiscoveryTransportCheck.swift"),
                    "-o", str(executable)], check=True)
    for scenario in ("valid", "wrong-serial", "wrong-trade", "missing-id", "zero-id", "duplicate-id", "doctype"):
        errors = []
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            listener.settimeout(5)

            def peer():
                try:
                    with listener.accept()[0] as connection:
                        connection.settimeout(5)
                        send_reply(connection, scenario)
                except Exception as error:
                    errors.append(error)

            thread = threading.Thread(target=peer, daemon=True)
            thread.start()
            subprocess.run([str(executable), str(listener.getsockname()[1]), scenario], check=True, timeout=10)
            thread.join(6)
            assert not thread.is_alive() and not errors, errors
