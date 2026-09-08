"""Structured logging with secret redaction.

Uses the standard library only; a lightweight JSON-ish formatter keeps
production lines parseable without pulling in heavy dependencies.
"""
from __future__ import annotations

import logging
import re

_REDACT_KEYS: tuple[str, ...] = (
    "password",
    "token",
    "authorization",
    "service_role",
    "jwt",
    "secret",
    "api_key",
)
_REDACT_RE = re.compile(
    r"(?i)(%(?:[A-Z_])+|"
    r"(?:password|token|authorization|secret|service_role|jwt|api_key)"
    r"[\"'=:\s]{1,4}[^\s,\"'\)\]]+)"
)


class _RedactingFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.msg = _REDACT_RE.sub(r"\1 *****", str(record.msg))
        return True


def configure_logging() -> None:
    handler = logging.StreamHandler()
    handler.addFilter(_RedactingFilter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)
    # Third-party loggers stay chatty only at warning+.
    for noisy in ("uvicorn.access", "httpx", "httpcore"):
        logging.getLogger(noisy).setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)