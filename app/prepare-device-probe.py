#!/usr/bin/env python3
"""Prepare a truthful macOS device report for review. Never sends network requests."""
import argparse
import base64
import hashlib
import ipaddress
import json
import pathlib
import plistlib
import re
import socket
import subprocess
import time
import urllib.parse
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--server", required=True, help="Authentication server origin, e.g. http://192.0.2.10")
args = parser.parse_args()
parts = urllib.parse.urlsplit(args.server)
if parts.scheme not in ("http", "https") or not parts.hostname or parts.username or parts.password or parts.query or parts.fragment or parts.path not in ("", "/"):
    parser.error("--server must be an HTTP(S) origin")
ORIGIN = args.server.rstrip("/")


def command(*args):
    return subprocess.check_output(args, text=True).strip()


route = command("/sbin/route", "-n", "get", parts.hostname)
interface_match = re.search(r"interface:\s*(\S+)", route)
if not interface_match:
    raise RuntimeError("No route interface")
interface = interface_match.group(1)
network = command("/sbin/ifconfig", interface)
ip_match = re.search(r"\binet\s+(\d+\.\d+\.\d+\.\d+)\s+netmask\s+(0x[0-9a-f]+)", network)
mac_match = re.search(r"\bether\s+([0-9a-f:]{17})", network, re.I)
if not ip_match or not mac_match:
    raise RuntimeError("Active IPv4/MAC information unavailable; refusing to invent identity")
ip = ip_match.group(1)
mask = str(ipaddress.IPv4Address(int(ip_match.group(2), 16)))
mac = mac_match.group(1)
registry = plistlib.loads(subprocess.check_output(["/usr/sbin/ioreg", "-rd1", "-c", "IOPlatformExpertDevice", "-a"]))
hardware_id = registry[0].get("IOPlatformUUID")
if not isinstance(hardware_id, str) or not hardware_id:
    raise RuntimeError("IOPlatformUUID unavailable")
model = command("/usr/sbin/sysctl", "-n", "hw.model")
try:
    cpu = command("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string")
except subprocess.CalledProcessError:
    cpu = command("/usr/bin/uname", "-m")
fields = {
    "AgentVersion": "0.3", "ComputerName": socket.gethostname(), "DeviceName": model,
    "OS": "macOS " + command("/usr/bin/sw_vers", "-productVersion"),
    "Ip": ip, "Mac": mac, "IeVersion": "NACMac/0.3", "DiskId": hardware_id,
    "CPU": cpu, "Mark": mask,
}
xml = ET.Element("MSAC")
for name, value in fields.items():
    ET.SubElement(xml, name).text = value
# ASCII numeric references keep the original gb2312 declaration unambiguous.
raw_xml = '<?xml version="1.0" encoding="gb2312"?>' + ET.tostring(xml, encoding="unicode")
ascii_xml = raw_xml.encode("ascii", "xmlcharrefreplace")
encoded_xml = base64.b64encode(ascii_xml).decode().translate(str.maketrans({"+": ",", "=": ":", "/": "."}))
params = [("gettype", "control"), ("dev_xml", encoded_xml), ("newMobile", "1"),
          ("is_guest", "0"), ("wechatid", "0"), ("is_mobile", "0"), ("os_platform", "macOS")]
url = ORIGIN + "/access/1.0/mac/json/device/infoprocess?local_lguage_set=zh&cache=" + str(int(time.time() * 1000))
canonical = url + "".join("&" + k + "=" + urllib.parse.unquote(v) for k, v in params)
canonical = re.sub(r"^http[s]?://[^/]+", "", canonical)
canonical = re.sub(r'''[^0-9a-zA-Z=&()/.?_'"<>]''', "", canonical)
headers = {"Session-Num": hashlib.md5(canonical.encode()).hexdigest(), "Extend-Data": "ostype=mac;isclient=1",
           "Serial-Num": "123", "Referer": ORIGIN + "/", "Content-Type": "application/x-www-form-urlencoded"}
output = ROOT / "local" / "prepared-mac-device-probe.json"
output.parent.mkdir(exist_ok=True)
output.write_text(json.dumps({"method": "POST", "url": url, "headers": headers,
    "body": urllib.parse.urlencode(params), "reported_fields": fields,
    "scope": "experimental device registration/lookup; not yet submitted"}, ensure_ascii=False, indent=2))
output.chmod(0o600)
print("Prepared only; no request sent:", output)
print("Model:", model, "OS:", fields["OS"], "interface:", interface)
print("IP:", ip, "MAC:", mac[:8] + ":…", "hardware UUID:", hardware_id[:8] + "…")
print("Fields:", ", ".join(fields))
print("No account, password, token, application list or file inventory included.")
