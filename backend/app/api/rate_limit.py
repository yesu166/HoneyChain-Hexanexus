from __future__ import annotations

import time
from collections import defaultdict, deque
from typing import Deque

_clients: dict[str, Deque[float]] = defaultdict(deque)


def check_rate(client_key: str, *, limit_per_minute: int) -> bool:
    now = time.monotonic()
    window_start = now - 60.0
    window = _clients[client_key]
    while window and window[0] < window_start:
        window.popleft()
    if len(window) >= max(1, limit_per_minute):
        return False
    window.append(now)
    return True