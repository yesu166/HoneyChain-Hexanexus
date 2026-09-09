"""Notification/alert schemas.

Alerts are derived from real telemetry + ledger validation results, not
invented on the client. Every alert carries its source and severity so the UI
can never claim "AI detected" without the backend having produced it.
"""
from __future__ import annotations

import datetime
from typing import Literal, Optional

from pydantic import BaseModel

AlertSeverity = Literal["info", "warning", "critical", "error"]
AlertCategory = Literal[
    "telemetry",
    "device_status",
    "sequence",
    "integrity",
    "battery",
    "stale",
]


class NotificationRead(BaseModel):
    notification_id: str
    hive_id: Optional[str] = None
    batch_id: Optional[str] = None
    device_id: Optional[str] = None
    category: AlertCategory
    severity: AlertSeverity
    reason: str
    recommended_action: str
    source: Literal["iot", "ledger", "evidence", "system"]
    title: str
    body: str
    created_at: datetime.datetime
    read: bool = False
    is_simulated: bool = True


class NotificationList(BaseModel):
    items: list[NotificationRead]
    unread_count: int