"""Derived alerts from telemetry + ledger/integrity outcomes.

Alerts are created ONLY from evaluation of real data (telemetry bands,
sequence/integrity rejections, stale device state). The notification
repository row is labeled by source (iot / ledger / evidence / system) and
severity; UIs surface exactly what the backend produced.

Rule bands used for hive telemetry (mirrors the risk engine's own bands so
the two never disagree):
  temperature_c  : [15.0, 38.0)   -> cold/heat stress outside
  humidity_percent: [35.0, 80.0]  -> too dry/wet outside
  hive_weight_kg  : drop > 8% vs previous accepted reading -> rapid weight loss
  bee_activity    : < 25 -> low activity
  battery_percent : < 20 -> battery low
  signal_strength : < -90 -> weak signal
  stale           : no event for STALE_SECONDS
"""
from __future__ import annotations

from typing import Any

from ..db.supabase import Repository

STALE_SECONDS = 60 * 6  # 6 minutes without telemetry => stale


class NotificationService:
    def __init__(self, repo: Repository) -> None:
        self._repo = repo
        self._last_weight: dict[str, float] = {}

    # ------------------------------------------------------- evaluators
    def evaluate(self, device: dict[str, Any], row: dict[str, Any]) -> bool:
        """Evaluate one accepted telemetry event and raise alerts. Returns
        True if at least one alert was created."""
        hive_id = row.get("hive_id")
        if not hive_id:
            return False
        payload = row.get("payload") or {}
        created = False
        for alert in self._telemetry_alerts(hive_id, device, row, payload):
            self._create(alert)
            created = True
        return created

    def _telemetry_alerts(
        self, hive_id: str, device: dict[str, Any], row: dict[str, Any], payload: dict[str, Any]
    ) -> list[dict[str, Any]]:
        alerts: list[dict[str, Any]] = []

        temp = payload.get("temperature_c")
        if temp is not None:
            if temp >= 38.0:
                alerts.append(self._mk(hive_id, device, "telemetry", "warning", "High temperature",
                                        f"Hive {hive_id} temp {temp}°C exceeds 38°C. Possible heat stress.",
                                        "Inspect hive, add ventilation, shade the apiary in peak heat."))
            elif temp < 15.0:
                alerts.append(self._mk(hive_id, device, "telemetry", "warning", "Low temperature",
                                        f"Hive {hive_id} temp {temp}°C below 15°C. Colony may be at risk.",
                                        "Insulate the hive and check cluster activity."))

        hum = payload.get("humidity_percent")
        if hum is not None:
            if hum > 80.0:
                alerts.append(self._mk(hive_id, device, "telemetry", "warning", "High humidity",
                                        f"Hive {hive_id} humidity {hum}% above 80%. Condensation risk.",
                                        "Check ventilation and hive floor moisture."))
            elif hum < 35.0:
                alerts.append(self._mk(hive_id, device, "telemetry", "info", "Low humidity",
                                        f"Hive {hive_id} humidity {hum}% below 35%. Forage may be scarce.",
                                        "Monitor water source availability for bees."))

        weight = payload.get("hive_weight_kg")
        if weight is not None:
            prev = self._last_weight.get(hive_id)
            if prev and prev > 0:
                drop = (prev - weight) / prev
                if drop > 0.08:
                    alerts.append(self._mk(hive_id, device, "telemetry", "critical", "Rapid weight loss",
                                            f"Hive {hive_id} weight dropped {drop:.0%} since last reading. Possible robbing or queen loss.",
                                            "Physical inspection required; check for robbing, swarm, or disease."))
            self._last_weight[hive_id] = weight

        activity = payload.get("bee_activity")
        if activity is not None and activity < 25.0:
            alerts.append(self._mk(hive_id, device, "telemetry", "warning", "Low bee activity",
                                    f"Hive {hive_id} activity {activity:.0f} is very low.",
                                    "Inspect colony strength; consider requeening or merging weak colonies."))

        battery = payload.get("battery_percent")
        if battery is not None and battery < 20.0:
            alerts.append(self._mk(hive_id, device, "battery", "warning", "Device battery low",
                                    f"Device {device['device_name']} battery at {battery:.0f}%.",
                                    "Replace/recharge the battery before telemetry loss."))

        signal = payload.get("signal_strength")
        if signal is not None and signal < -90.0:
            alerts.append(self._mk(hive_id, device, "device_status", "info", "Weak signal",
                                    f"Device {device['device_name']} signal {signal:.0f} dBm. Telemetry may lag.",
                                    "Check device placement or connectivity."))

        return alerts

    def note_rejected(self, device: dict[str, Any], category: str, detail: str, *, title: str = "") -> None:
        """Record an integrity/sequence rejection (e.g. bad signature, gap,
        duplicate replay). Alert surfaces the problem to the operator."""
        hive_id = device.get("assigned_hive_id")
        if hive_id:
            reason = title or category.replace("_", " ").capitalize()
            self._create(
                self._mk(hive_id, device, "sequence" if category == "sequence" else "integrity",
                         "error", reason, detail,
                         "Review device firmware/config; re-provision identity if signature invalid.")
            )

    def stale_devices(self) -> list[dict[str, Any]]:
        """Lazily flag devices whose last event is older than STALE_SECONDS."""
        from datetime import datetime, timezone

        now = datetime.now(timezone.utc)
        flagged = []
        for dev in self._repo.list_iot_devices():
            last = dev.get("last_seen")
            if not last:
                continue
            try:
                last_dt = datetime.fromisoformat(str(last).replace("Z", "+00:00"))
            except ValueError:
                continue
            if (now - last_dt).total_seconds() > STALE_SECONDS:
                self._create(
                    self._mk(dev.get("assigned_hive_id"), dev, "stale", "info", "Telemetry stale",
                             f"{dev['device_name']} last seen {last}. No telemetry for 6+ minutes.",
                             "Check device connectivity before trusting its data.")
                )
                flagged.append(dev["device_id"])
        return flagged

    def _mk(self, hive_id: str, device: dict[str, Any], category: str, severity: str,
            title: str, body: str, recommended_action: str) -> dict[str, Any]:
        return {
            "hive_id": hive_id,
            "batch_id": None,
            "device_id": device.get("device_id"),
            "category": category,
            "severity": severity,
            "reason": title,
            "recommended_action": recommended_action,
            "source": "iot",
            "title": title,
            "body": body,
            "organization_id": device.get("organization_id", ""),
            "is_simulated": bool(device.get("is_simulated", True)),
        }

    def _create(self, alert: dict[str, Any]) -> dict[str, Any]:
        from .iot_service import _now_iso

        row = {
            "notification_id": None,
            "created_at": _now_iso(),
            "read": False,
            **alert,
        }
        return self._repo.add_notification(row)

    # ------------------------------------------------------- read side
    def list_for_user(self, user: Any, *, limit: int = 50) -> list[dict[str, Any]]:
        if user.role in ("admin", "institution"):
            rows = self._repo.list_notifications()
        elif user.role == "beekeeper":
            # beekeeper: alerts only for hives the user owns
            beekeeper_id = user.user_id
            hives = [h for h in self._repo.list_hives(beekeeper_id)]
            hive_ids = {h["id"] for h in hives}
            rows = [n for n in self._repo.list_notifications() if n.get("hive_id") in hive_ids]
        else:
            rows = self._repo.list_notifications(org_id=user.org_id)
        rows.sort(key=lambda r: str(r.get("created_at", "")), reverse=True)
        unread = sum(1 for r in rows if not r.get("read"))
        return {
            "items": rows[:limit],
            "unread_count": unread,
        }

    def mark_read(self, notification_id: str, *, user: Any = None) -> dict[str, Any] | None:
        row = self._repo.get_notification(notification_id)
        if row is None:
            return None
        if user is not None:
            if user.role in ("admin", "institution"):
                pass
            elif user.role == "beekeeper":
                hive_ids = {h["id"] for h in self._repo.list_hives(user.user_id)}
                if row.get("hive_id") not in hive_ids:
                    raise PermissionError("notification is not in your scope")
            elif row.get("organization_id") and row.get("organization_id") != user.org_id:
                raise PermissionError("notification is not in your scope")
        return self._repo.mark_notification_read(notification_id)


def build_notifications(repo: Repository) -> NotificationService:
    return NotificationService(repo)