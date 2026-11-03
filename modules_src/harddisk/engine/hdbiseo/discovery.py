"""같은 와이파이에서 PC 엔진 찾기(UDP 47800). '다른 기기에서 보기'를 켰을 때만 동작."""

from __future__ import annotations

import json
import socket
import threading

DISCOVERY_PORT = 47800
MAGIC = b"HDBISEO_FIND"


def start_responder(http_port: int) -> threading.Thread:
    def loop():
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind(("", DISCOVERY_PORT))
        except OSError:
            return
        while True:
            try:
                data, addr = s.recvfrom(256)
            except OSError:
                return
            if data.strip() == MAGIC:
                reply = json.dumps({"app": "hdbiseo", "port": http_port, "pc": socket.gethostname()}).encode()
                s.sendto(reply, addr)

    t = threading.Thread(target=loop, daemon=True, name="discovery")
    t.start()
    return t


def find(timeout: float = 2.0) -> list[dict]:
    """같은 네트워크에서 엔진을 찾는다(데스크톱 포장 앱에서 사용)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.settimeout(timeout)
    found = []
    try:
        s.sendto(MAGIC, ("<broadcast>", DISCOVERY_PORT))
        while True:
            data, addr = s.recvfrom(512)
            info = json.loads(data)
            info["ip"] = addr[0]
            found.append(info)
    except (OSError, ValueError):
        pass
    finally:
        s.close()
    return found
