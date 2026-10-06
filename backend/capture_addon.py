"""
HoneyChain packet capture addon for mitmdump.

Logs every HTTP flow that passes through the reverse proxy between the
React frontend (port 8080, via Vite proxy) and the FastAPI backend
(port 8000). Each flow is written as one JSON line to honeychain_capture.jsonl
in the same directory as this script.

Sensitive headers (Authorization, Cookie, Set-Cookie) are redacted so the
log can be shared for debugging without leaking tokens.

Run:
    mitmdump --mode reverse:http://127.0.0.1:8000 ^
             --listen-host 127.0.0.1 --listen-port 8001 ^
             -s honeychain_capture_addon.py --set flow_detail=0
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from typing import Any

LOG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "honeychain_capture.jsonl")

# Headers whose values we redact so tokens/cookies never hit the log.
REDACT_HEADERS = frozenset({
    "authorization", "proxy-authorization",
    "cookie", "set-cookie",
    "x-api-key", "x-session-token",
})

BODY_CUTOFF = 8192  # max body bytes logged per direction


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def _redact_headers(headers: Any) -> dict[str, str]:
    out: dict[str, str] = {}
    for key, val in (headers.items() if hasattr(headers, "items") else headers):
        lk = key.lower()
        if lk in REDACT_HEADERS:
            out[key] = "<redacted>"
        else:
            out[key] = val
    return out


def _safe_body(data: Any) -> Any:
    if data is None:
        return None
    try:
        raw = data.read() if hasattr(data, "read") else data
    except Exception:
        return None
    if not isinstance(raw, (bytes, bytearray, memoryview)):
        return raw
    b = bytes(raw)
    if len(b) > BODY_CUTOFF:
        b = b[:BODY_CUTOFF]
    try:
        text = b.decode("utf-8", errors="replace")
        import json as _json
        try:
            return _json.loads(text)
        except Exception:
            return text
    except Exception:
        return b.hex()


def _log(entry: dict[str, Any]) -> None:
    with open(LOG_PATH, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def _flow_record(flow: Any, direction: str) -> dict[str, Any]:
    r = flow.request
    # client_address can be a tuple (ip, port) on some mitmproxy versions
    client = getattr(flow, "client_conn", None)
    client_addr = None
    client_port = None
    if client is not None:
        if hasattr(client, "address"):
            addr = client.address
            if isinstance(addr, tuple) and len(addr) == 2:
                client_addr, client_port = addr
            else:
                client_addr = str(addr)
        elif isinstance(client, tuple):
            client_addr, client_port = client

    record: dict[str, Any] = {
        "ts": _now_iso(),
        "client_ip": client_addr,
        "client_port": client_port,
        "direction": direction,
        "method": r.method,
        "url": r.url,
        "http_version": getattr(r, "http_version", None),
        "status_code": getattr(flow.response, "status_code", None),
        "reason": getattr(flow.response, "reason", None),
        "mime_type": getattr(flow.response, "mime_type", None) or getattr(
            getattr(flow.response, "headers", {}), "get", lambda *a: None
        )("content-type"),
        "request_headers": _redact_headers(
            dict(getattr(r, "headers", {})) if hasattr(r, "headers") else {}
        ),
        "response_headers": _redact_headers(
            dict(getattr(flow.response, "headers", {})) if hasattr(flow.response, "headers") else {}
        ),
        "request_body": _safe_body(r.content) if hasattr(r, "content") else None,
        "response_body": _safe_body(flow.response.content) if hasattr(flow.response, "content") else None,
        "request_size": len(r.content) if hasattr(r, "content") else None,
        "response_size": len(flow.response.content) if hasattr(flow.response, "content") else None,
        "elapsed_ms": (
            (flow.response.timestamp_end - flow.request.timestamp_start) * 1000
            if getattr(flow.response, "timestamp_end", None) and getattr(r, "timestamp_start", None)
            else None
        ),
    }
    return record


def response(flow: Any, **kwargs: Any) -> None:
    """Called once the full response has been received."""
    try:
        rec = _flow_record(flow, direction="request-response")
        _log(rec)
        sys.stderr.write(
            f"[{rec['ts']}] {rec['method']} {rec['url']} -> {rec['status_code']} "
            f"({rec['response_size']}b, {rec['elapsed_ms']:.1f}ms)\n"
        )
        sys.stderr.flush()
    except Exception as exc:
        sys.stderr.write(f"[HoneyChain-capture ERROR] {exc}\n")
        sys.stderr.flush()


def error(flow: Any, **kwargs: Any) -> None:
    """Called when a flow fails before a response is received."""
    try:
        rec = _flow_record(flow, direction="request-error")
        rec["error"] = str(getattr(flow, "error", None))
        _log(rec)
        sys.stderr.write(f"[{rec['ts']}] {rec['method']} {rec['url']} -> ERROR: {rec.get('error')}\n")
        sys.stderr.flush()
    except Exception as exc:
        sys.stderr.write(f"[HoneyChain-capture ERROR] {exc}\n")
        sys.stderr.flush()


def done() -> None:
    sys.stderr.write(f"[HoneyChain-capture] wrote {sum(1 for _ in open(LOG_PATH, encoding='utf-8'))} records to {LOG_PATH}\n")
    sys.stderr.flush()
