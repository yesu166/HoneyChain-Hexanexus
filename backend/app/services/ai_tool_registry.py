"""Validated tool registry for Ask My Bee.

Every write the assistant performs goes through an existing HoneyChain service
(HiveService, HarvestService, InspectionService, TreatmentService) scoped to the
authenticated user — Gemini supplies arguments only, never identities. Writes
additionally require an explicit `confirmed: true` in the tool call, so a
recording always passes an in-conversation confirmation first. Idempotency is
guaranteed by a deterministic server-side `client_id` derived from the request
id + tool name + arguments, so a retried transcript never records twice.
"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime
from typing import Any

import httpx

WRITE_TOOLS = {"create_hive", "create_harvest", "record_inspection", "record_treatment"}

TOOL_DECLARATIONS: list[dict[str, Any]] = [
    {
        "name": "get_my_hives",
        "description": (
            "List the hives the signed-in beekeeper can access, with id, hive_code, "
            "status and location. Use this first to resolve a hive name/number spoken "
            "by the user (e.g. 'Hive 3' or 'the forest hive') into its exact id."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "limit": {"type": "integer", "default": 100},
            },
        },
    },
    {
        "name": "get_hive",
        "description": (
            "Full detail for one hive: fields, most recent reading "
            "(temperature/humidity/weight/recorded_at) and the latest inspection."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "hive_id": {"type": "string"},
            },
            "required": ["hive_id"],
        },
    },
    {
        "name": "get_latest_iot",
        "description": (
            "Most recent sensor/telemetry data for one hive, from either a manual or "
            "IoT read. Returns the single latest reading plus recent telemetry events."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "hive_id": {"type": "string"},
            },
            "required": ["hive_id"],
        },
    },
    {
        "name": "get_inspection_history",
        "description": "Past hive inspections (what the beekeeper observed).",
        "parameters": {
            "type": "object",
            "properties": {
                "hive_id": {"type": "string"},
                "limit": {"type": "integer", "default": 10},
            },
        },
    },
    {
        "name": "get_latest_inspection",
        "description": "The newest inspection for one hive.",
        "parameters": {
            "type": "object",
            "properties": {
                "hive_id": {"type": "string"},
            },
            "required": ["hive_id"],
        },
    },
    {
        "name": "get_treatment_history",
        "description": "Treatments applied to hives (name, date, dosage, notes).",
        "parameters": {
            "type": "object",
            "properties": {
                "hive_id": {"type": "string"},
                "limit": {"type": "integer", "default": 10},
            },
        },
    },
    {
        "name": "get_harvest_history",
        "description": "Past harvests recorded by the beekeeper (quantity, honey type, date).",
        "parameters": {
            "type": "object",
            "properties": {
                "hive_id": {"type": "string"},
                "limit": {"type": "integer", "default": 10},
            },
        },
    },
    {
        "name": "get_bee_health_screening",
        "description": (
            "Runs the existing HoneyChain hive health screening for one hive using its "
            "latest readings. Returns risk level (LOW/MEDIUM/HIGH), risk score, "
            "contributing factors and a recommended action. This is an inspection "
            "priority signal, not a diagnosis."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "hive_id": {"type": "string"},
            },
            "required": ["hive_id"],
        },
    },
    {
        "name": "predict_productivity",
        "description": (
            "Predicts honey yield with the HoneyChain productivity model. The model "
            "service is not available in this deployment; returns an explicit "
            "'currently unavailable' result. Never invent a number."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "hive_id": {"type": "string"},
            },
        },
    },
    {
        "name": "get_my_notifications",
        "description": (
            "The signed-in beekeeper's alerts: telemetry stress (temperature, "
            "humidity, rapid weight loss, low activity), device battery/signal, "
            "integrity or sequence rejections, stale devices and ledger "
            "outcomes. Read-only. Report the severity and the recommended "
            "action exactly as returned — never invent an alert."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "limit": {"type": "integer", "default": 20},
            },
        },
    },
    {
        "name": "create_hive",
        "description": (
            "Register a new hive for the signed-in beekeeper. The user must first "
            "confirm what they want recorded. Do not call with confirmed=true until "
            "the user has explicitly agreed."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "hive_code": {"type": "string"},
                "location": {"type": "string"},
                "confirmed": {"type": "boolean", "default": False},
            },
            "required": ["hive_code", "confirmed"],
        },
    },
    {
        "name": "create_harvest",
        "description": (
            "Record a harvest against one hive. The user must first confirm the hive, "
            "quantity and honey type. Do not call with confirmed=true until confirmed."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "hive_id": {"type": "string"},
                "quantity_kg": {"type": "number"},
                "honey_type": {"type": "string"},
                "confirmed": {"type": "boolean", "default": False},
            },
            "required": ["hive_id", "quantity_kg", "confirmed"],
        },
    },
    {
        "name": "record_inspection",
        "description": (
            "Save what the beekeeper observed during a hive check (activity, queen, "
            "brood, food stores, pests, dead bees, condition, notes). Do not call with "
            "confirmed=true until the user has confirmed."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "hive_id": {"type": "string"},
                "activity_level": {"type": "string", "enum": ["none", "low", "normal", "high"]},
                "queen_seen": {"type": "boolean"},
                "brood_seen": {"type": "boolean"},
                "food_stores": {"type": "string", "enum": ["plenty", "enough", "low", "running_out", "none"]},
                "pests_seen": {"type": "string"},
                "dead_bees_seen": {"type": "boolean"},
                "hive_condition": {"type": "string", "enum": ["good", "fair", "poor"]},
                "observations": {"type": "string"},
                "confirmed": {"type": "boolean", "default": False},
            },
            "required": ["hive_id", "confirmed"],
        },
    },
    {
        "name": "record_treatment",
        "description": (
            "Save a treatment applied to a hive (name, active ingredient, dosage, "
            "observation). Do not call with confirmed=true until the user has confirmed."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "hive_id": {"type": "string"},
                "treatment_name": {"type": "string"},
                "active_ingredient": {"type": "string"},
                "dosage": {"type": "string"},
                "observation": {"type": "string"},
                "confirmed": {"type": "boolean", "default": False},
            },
            "required": ["hive_id", "treatment_name", "confirmed"],
        },
    },
]

_TOOL_BY_NAME = {tool["name"]: tool for tool in TOOL_DECLARATIONS}


class ToolContext:
    def __init__(
        self,
        *,
        user: Any,
        services: dict[str, Any],
        risk_engine: Any,
        request_id: str,
        settings: Any,
    ) -> None:
        self.user = user
        self.services = services
        self.risk_engine = risk_engine
        self.request_id = request_id or ""
        self.settings = settings

    def _client_id(self, tool_name: str, args: dict[str, Any]) -> str:
        digest = hashlib.sha1(
            f"{self.request_id}|{tool_name}|{json.dumps(args, sort_keys=True, default=str)}".encode("utf-8")
        ).hexdigest()
        return f"ai-{digest}"

    def _hive(self, hive_id: str) -> dict[str, Any] | None:
        return self.services["hives"].get_for_user(hive_id, user=self.user)

    # -- read tools ----------------------------------------------------------
    def _get_my_hives(self, args: dict[str, Any]) -> dict[str, Any]:
        limit = int(args.get("limit", 100))
        hives = self.services["hives"].list_for_user(user=self.user)[:limit]
        return {
            "status": "ok",
            "hives": [
                self._hive_summary(hive) for hive in hives
            ],
        }

    def _hive_summary(self, hive: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": hive.get("id"),
            "hive_code": hive.get("hive_code"),
            "status": hive.get("status"),
            "location": hive.get("location"),
        }

    def _get_hive(self, args: dict[str, Any]) -> dict[str, Any]:
        hive = self._hive(args.get("hive_id", ""))
        if hive is None:
            return {"status": "error", "error": "hive not found or not in your scope"}
        readings = self.services["hives"].readings(hive["id"], limit=20)
        latest_inspection = self.services["inspections"].latest_for_user(
            user=self.user, hive_id=hive["id"]
        )
        return {
            "status": "ok",
            "hive": hive,
            "latest_reading": readings[0] if readings else None,
            "recent_readings_count": len(readings),
            "latest_inspection": self._inspection_out(latest_inspection),
        }

    def _get_latest_iot(self, args: dict[str, Any]) -> dict[str, Any]:
        hive = self._hive(args.get("hive_id", ""))
        if hive is None:
            return {"status": "error", "error": "hive not found or not in your scope"}
        readings = self.services["hives"].readings(hive["id"], limit=5)
        telemetry = self.services["repo"].telemetry_events_for_hive(hive["id"], limit=20)
        events = [_slice(telemetry_event) for telemetry_event in telemetry]
        return {
            "status": "ok",
            "hive_id": hive["id"],
            "latest_reading": readings[0] if readings else None,
            "recent_telemetry_events": events,
        }

    def _get_inspection_history(self, args: dict[str, Any]) -> dict[str, Any]:
        hive_id = args.get("hive_id", "")
        limit = int(args.get("limit", 10))
        inspections = self.services["inspections"].list_for_user(
            user=self.user, hive_id=hive_id, limit=limit
        )
        return {
            "status": "ok",
            "inspections": [_inspection_out(i) for i in inspections],
        }

    def _get_latest_inspection(self, args: dict[str, Any]) -> dict[str, Any]:
        inspection = self.services["inspections"].latest_for_user(
            user=self.user, hive_id=args.get("hive_id", "")
        )
        return {"status": "ok", "inspection": _inspection_out(inspection)}

    def _get_treatment_history(self, args: dict[str, Any]) -> dict[str, Any]:
        hive_id = args.get("hive_id", "")
        limit = int(args.get("limit", 10))
        treatments = self.services["treatments"].list_for_user(
            user=self.user, hive_id=hive_id, limit=limit
        )
        return {"status": "ok", "treatments": [_treatment_out(t) for t in treatments]}

    def _get_harvest_history(self, args: dict[str, Any]) -> dict[str, Any]:
        hive_id = args.get("hive_id", "")
        limit = int(args.get("limit", 10))
        harvests = self.services["harvests"].list_for_user(user=self.user)
        if hive_id:
            harvests = [h for h in harvests if h.get("hive_id") == hive_id]
        return {"status": "ok", "harvests": [_slice(h) for h in harvests[:limit]]}

    def _get_bee_health_screening(self, args: dict[str, Any]) -> dict[str, Any]:
        hive = self._hive(args.get("hive_id", ""))
        if hive is None:
            return {"status": "error", "error": "hive not found or not in your scope"}
        assessment = self.risk_engine.assess(
            hive["id"], self.services["hives"].readings(hive["id"])
        )
        return {
            "status": "ok",
            "assessment": {
                "risk_level": assessment.risk_level,
                "risk_score": assessment.risk_score,
                "contributing_factors": assessment.contributing_factors,
                "recommended_action": assessment.recommended_action,
                "simulated": assessment.simulated,
            },
            "disclaimer": "inspection priority signal, not a diagnosis",
        }

    def _predict_productivity(self, args: dict[str, Any]) -> dict[str, Any]:
        product_url = (getattr(self.settings, "productivity_api_url", "") or "").strip()
        if not product_url:
            return {
                "status": "unavailable",
                "available": False,
                "reason": "the productivity model service is not deployed in this "
                "environment",
            }
        hive_id = args.get("hive_id", "")
        import httpx

        try:
            response = httpx.post(
                f"{product_url.rstrip('/')}/predict-productivity",
                json={"hive_id": hive_id},
                timeout=20.0,
            )
            response.raise_for_status()
            return {"status": "ok", "available": True, "result": response.json()}
        except Exception as exc:  # noqa: BLE001 — surfaced only as a message
            return {
                "status": "unavailable",
                "available": False,
                "reason": f"productivity service unreachable: {exc}",
            }

    def _get_my_notifications(self, args: dict[str, Any]) -> dict[str, Any]:
        try:
            limit = int(args.get("limit", 20))
            result = self.services["notifications"].list_for_user(
                self.user, limit=limit
            )
        except Exception as exc:  # noqa: BLE001 — surfaced only as a message
            return {
                "status": "error",
                "error": f"notifications unavailable: {exc}",
                "database": _is_database_failure(exc),
            }
        return {
            "status": "ok",
            "unread_count": result.get("unread_count", 0),
            "notifications": [_slice(n) for n in result.get("items", [])],
        }

    # -- write tools (confirmation-gated) --------------------------------------
    def _require_confirmation(self, args: dict[str, Any]) -> dict[str, Any]:
        return {
            "status": "needs_confirmation",
            "confirmed": False,
            "message": (
                "Call this tool again with confirmed=true only after the beekeeper "
                "explicitly agrees, restating exactly what will be recorded."
            ),
        }

    def _create_hive(self, args: dict[str, Any]) -> dict[str, Any]:
        if not args.get("confirmed"):
            return self._require_confirmation(args)
        hive_code = str(args.get("hive_code") or "").strip()
        if not hive_code:
            return {"status": "error", "error": "hive_code is required"}
        if len(hive_code) > 64:
            return {"status": "error", "error": "hive_code too long (max 64 chars)"}
        try:
            hive = self.services["hives"].create(
                beekeeper_id=self.user.user_id,
                data={
                    "hive_code": hive_code,
                    "location": args.get("location"),
                    "client_id": self._client_id("create_hive", args),
                },
            )
        except ValueError as exc:
            return {"status": "error", "error": str(exc)}
        return {"status": "ok", "hive": self._hive_summary(hive)}

    def _create_harvest(self, args: dict[str, Any]) -> dict[str, Any]:
        if not args.get("confirmed"):
            return self._require_confirmation(args)
        hive = self._hive(args.get("hive_id", ""))
        if hive is None:
            return {"status": "error", "error": "hive not found or not in your scope"}
        try:
            quantity = float(args.get("quantity_kg"))
        except (TypeError, ValueError):
            return {"status": "error", "error": "quantity_kg must be a number"}
        if not (0.05 <= quantity <= 2000):
            return {"status": "error", "error": "quantity_kg out of a plausible range (0.05-2000 kg)"}
        try:
            harvest = self.services["harvests"].create(
                beekeeper_id=self.user.user_id,
                data={
                    "hive_id": hive["id"],
                    "quantity_kg": quantity,
                    "honey_type": args.get("honey_type"),
                    "client_id": self._client_id("create_harvest", args),
                },
            )
        except ValueError as exc:
            return {"status": "error", "error": str(exc)}
        return {"status": "ok", "harvest": _slice(harvest)}

    def _record_inspection(self, args: dict[str, Any]) -> dict[str, Any]:
        if not args.get("confirmed"):
            return self._require_confirmation(args)
        hive = self._hive(args.get("hive_id", ""))
        if hive is None:
            return {"status": "error", "error": "hive not found or not in your scope"}
        fields = (
            "activity_level", "queen_seen", "brood_seen", "food_stores",
            "pests_seen", "dead_bees_seen", "hive_condition", "observations",
        )
        data = {
            "hive_id": hive["id"],
            "observations": args.get("observations"),
        }
        for field in fields:
            if field in args and args[field] is not None:
                data[field] = args[field]
        data["client_id"] = self._client_id("record_inspection", args)
        try:
            row = self.services["inspections"].create(
                beekeeper_id=self.user.user_id, data=data
            )
        except ValueError as exc:
            return {"status": "error", "error": str(exc)}
        return {"status": "ok", "inspection": _inspection_out(row)}

    def _record_treatment(self, args: dict[str, Any]) -> dict[str, Any]:
        if not args.get("confirmed"):
            return self._require_confirmation(args)
        hive = self._hive(args.get("hive_id", ""))
        if hive is None:
            return {"status": "error", "error": "hive not found or not in your scope"}
        name = str(args.get("treatment_name") or "").strip()
        if not name:
            return {"status": "error", "error": "treatment_name is required"}
        try:
            row = self.services["treatments"].create(
                beekeeper_id=self.user.user_id,
                data={
                    "hive_id": hive["id"],
                    "treatment_name": name,
                    "active_ingredient": args.get("active_ingredient"),
                    "dosage": args.get("dosage"),
                    "observation": args.get("observation"),
                    "client_id": self._client_id("record_treatment", args),
                },
            )
        except ValueError as exc:
            return {"status": "error", "error": str(exc)}
        return {"status": "ok", "treatment": _treatment_out(row)}


def _slice(row: dict[str, Any] | None) -> dict[str, Any] | None:
    """JSON-safe view (Gemini receives plain JSON in function responses)."""
    if row is None:
        return None
    out = {key: _json_safe(value) for key, value in row.items()}
    return out


def _json_safe(value: Any) -> Any:
    if isinstance(value, (datetime,)):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: _json_safe(v) for key, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(v) for v in value]
    return value


def _inspection_out(row: dict[str, Any] | None) -> dict[str, Any] | None:
    if row is None:
        return None
    keys = (
        "id", "hive_id", "beekeeper_id", "inspected_at", "activity_level",
        "queen_seen", "brood_seen", "food_stores", "pests_seen",
        "dead_bees_seen", "hive_condition", "observations", "client_id",
    )
    return {key: _json_safe(row.get(key)) for key in keys if row.get(key) is not None}


def _treatment_out(row: dict[str, Any] | None) -> dict[str, Any] | None:
    if row is None:
        return None
    keys = (
        "id", "hive_id", "beekeeper_id", "treated_at", "treatment_name",
        "active_ingredient", "dosage", "observation", "status", "client_id",
    )
    return {key: _json_safe(row.get(key)) for key in keys if row.get(key) is not None}


def execute_ai_tool(
    name: str,
    args: dict[str, Any],
    *,
    context: ToolContext,
) -> dict[str, Any]:
    """Executes a validated tool for the authenticated user.

    Arguments are validated in-process: hive ids must exist and be owned by the
    user, numbers are range-checked, and writes require `confirmed: true`. Any
    exception is translated to a structured error so the model never sees a
    traceback and never claims success that did not happen.
    """
    handler = getattr(context, f"_{name}", None)
    if handler is None:
        return {"status": "error", "error": f"unknown tool: {name}"}
    try:
        result = handler(args)
    except (KeyError, TypeError, ValueError) as exc:
        return {"status": "error", "error": str(exc)}
    except Exception as exc:  # noqa: BLE001 — tool result, not a server traceback
        return {
            "status": "error",
            "error": f"tool failed: {exc}",
            "database": _is_database_failure(exc),
        }
    return result if isinstance(result, dict) else {"status": "ok", "value": result}


def _is_database_failure(exc: Exception) -> bool:
    """Whether an unexpected exception is a database/transport failure.

    The chat service uses this flag to stop the loop and show HoneyChain's own
    "database could not complete it" message instead of feeding a dead-end
    result back to Gemini.
    """
    try:
        from postgrest.exceptions import APIError
    except Exception:  # noqa: BLE001 — import guard is advisory
        APIError = None
    if isinstance(exc, (httpx.HTTPError, ConnectionError, TimeoutError)) or (
        APIError is not None and isinstance(exc, APIError)
    ):
        return True
    lowered = str(exc).lower()
    return any(
        token in lowered
        for token in (
            "connection", "timed out", "timeout", "network",
            "postgrest", "supabase", "database",
        )
    )