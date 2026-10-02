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
# Backend-produced telemetry categories.
AlertCategory = Literal[
    "telemetry",
    "device_status",
    "sequence",
    "integrity",
    "battery",
    "stale",
]
# Workflow notification categories (supply-chain events). These are produced by
# the WRITE path whenever a real state change is persisted, so the UI can show a
# workflow inbox that is always backed by a recorded event.
WorkflowEvent = Literal[
    "HARVEST_CREATED",
    "COLLECTION_ACCEPTED",
    "BATCH_CREATED",
    "LAB_REQUESTED",
    "LAB_STARTED",
    "LAB_PASS",
    "LAB_FAIL",
    "PROCESSING_STARTED",
    "PACKAGED",
    "CUSTODY_TRANSFER",
    "CUSTODY_RECEIVED",
    "MARKET_LISTED",
    "BUYER_REQUESTED",
    "BUYER_ACCEPTED",
    "HIGH_RISK_HIVE",
    "VAN_VISIT_SCHEDULED",
    "VAN_SAMPLE_RECEIVED",
    "VAN_TEST_COMPLETED",
    "QR_SUSPICIOUS",
]


class NotificationRead(BaseModel):
    notification_id: str
    hive_id: Optional[str] = None
    batch_id: Optional[str] = None
    device_id: Optional[str] = None
    # `category` widens to str because persisted notification rows may carry
    # either a telemetry category (AlertCategory) or a workflow event name
    # (WorkflowEvent). The write path only ever emits values from one of those
    # two closed sets; the read path must not 500 on a workflow row.
    category: str
    severity: AlertSeverity
    reason: str
    recommended_action: str
    source: Literal["iot", "ledger", "evidence", "system", "workflow"]
    title: str
    body: str
    created_at: datetime.datetime
    read: bool = False
    is_simulated: bool = True


class NotificationList(BaseModel):
    items: list[NotificationRead]
    unread_count: int