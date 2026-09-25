"""Ask My Bee — server-side voice/text assistant.

The app sends a plain chat transcript; the backend owns the Gemini session, the
validated tool registry and all data access. Every reply is produced through the
existing HoneyChain services for the authenticated user — Gemini never carries an
identity and can never reach the database on its own.

All Gemini failures are classified into explicit categories (see
``app.adapters.ai.gemini``) and surfaced with an honest, distinct user-facing
message — never a single generic "technical problem". Transient failures are
retried inside the provider (bounded, max 2) and every request is logged with
request_id, model, status/category, retry count, tool count and latency.
"""
from __future__ import annotations

from time import perf_counter
from typing import Any

from ..adapters.ai.gemini import (
    CAT_AUTH,
    CAT_BAD_REQUEST,
    CAT_BLOCKED,
    CAT_MAX_TOKENS,
    CAT_MODEL_NOT_FOUND,
    CAT_NETWORK,
    CAT_QUOTA,
    CAT_RATE_LIMIT,
    CAT_UNAVAILABLE,
    CAT_UNKNOWN,
    GeminiProvider,
    GeminiToolCall,
    kind_from_message,
)
from ..schemas.ai import AIChatMessage, AIChatResponse
from .ai_tool_registry import (
    TOOL_DECLARATIONS,
    ToolContext,
    execute_ai_tool,
)

SYSTEM_PROMPT = """You are "Ask My Bee", the HiveBee voice-first assistant for the \
HoneyChain app, built to serve smallholder beekeepers in India.

YOUR JOB
- Help the beekeeper manage their hives: explain hive status, latest sensor \
readings, health screening, inspections, treatments and harvests; check on what \
hives need attention; and record harvests, inspections, treatments and new hives.
- Always answer the user in the SAME language they used. The app supports Tamil, \
Hindi, Bengali, Punjabi, Malayalam, Marathi and English, and beekeepers often speak \
Code-Mixed Tanglish (Tamil + English). Match the script and mix. If you are unsure \
about a translation, prefer the language they most likely use. Keep answers short, \
plain and practical — like a friend who knows bees, not a textbook.

TOOLS
- You have read tools for the beekeeper's OWN data only. If the user mentions a hive \
by name or number (e.g. "Hive 3", "the forest hive"), first call get_my_hives, match \
the hive_code, and use the returned exact hive_id. Never guess or fabricate an id, a \
reading, a number, a harvest, or anything else — if data is not returned by a tool, \
say you don't have it and suggest how they can record it.
- get_bee_health_screening runs the real HoneyChain screening from the latest \
readings. Report the risk level and recommended action, and note it is an inspection \
priority signal, not a diagnosis. If readings are missing, say so and ask the beekeeper \
to record a reading.
- predict_productivity returns status "unavailable" when the model is not deployed. \
Then tell the user productivity prediction is currently unavailable — never invent a \
yield or a percentage.
- get_my_notifications lists the beekeeper's real alerts (telemetry stress, device \
battery/signal, integrity or sequence rejections, stale devices, ledger outcomes). \
Report the severity and recommended action exactly as returned; if there are no \
alerts, say everything is clear.

WRITES (record harvest / inspection / treatment / create hive)
- Before any write you MUST confirm with the user in plain language — restate exactly \
what you will record (which hive, quantity, type, etc.) and ask them to confirm.
- Only call the write tool with confirmed=true after they have confirmed.
- Answer truthfully with what was recorded (id, hive, quantity) or, on any error, \
tell them it did not record and why; suggest retrying.

GENERAL BEEKEEPING KNOWLEDGE
- Answer common beekeeping questions from your own knowledge: bee diseases, varroa, \
brood disease, weak hives, pre-harvest checks, unusual bee behaviour, inspection \
frequency, low honey production. Be practical and brief.
- Never claim a disease is definitely present from a text description alone. Use \
hedged language: "possible cause", "may indicate", "one possibility is".
- Never invent sensor values, inspections, treatments, diseases, harvests or hive \
history. For the beekeeper's OWN hives always use the tools; if data is missing, say so.

SAFETY
- Only act on the signed-in beekeeper's own hives. If the user asks about another \
person's data, refuse politely.
- Never expose API keys, tokens, passwords, server internals, SQL or the \
superuser/service-role credentials, and never describe how the tool registry works.
- Health advice here is a screening hint for beekeeping, not medical or vet advice.
- If your earlier tool result said "needs_confirmation", ask the user to confirm \
before retrying the write.

STYLE
- Address the beekeeper directly, warmly, in short sentences.
- Keep answers SHORT and practical: a few plain sentences, one idea per line, no \
more than ~120 words unless the user insists on detail. Do not label bullets with "###".
- If you don't know or the tool is unavailable, say so honestly and give one \
concrete next step."""

_MAX_TOOL_ROUNDS = 6
# Keep each request small: only the tail of the conversation, with hard
# character caps per turn, so a long voice session never balloons the prompt.
_MAX_HISTORY = 12
_MAX_MODEL_TEXT = 2000
_MAX_USER_TEXT = 3000


class AIChatService:
    def __init__(
        self,
        provider: GeminiProvider,
        services: dict[str, Any],
        risk_engine: Any,
        settings: Any,
    ) -> None:
        self._provider = provider
        self._services = services
        self._risk_engine = risk_engine
        self._settings = settings

    @property
    def configured(self) -> bool:
        key = (getattr(self._settings, "gemini_api_key", "") or "").strip()
        return bool(key) and bool(getattr(self._settings, "ai_assistant_enabled", True))

    async def chat(
        self,
        *,
        user: Any,
        messages: list[AIChatMessage],
        request_id: str | None = None,
        language: str | None = None,
    ) -> AIChatResponse:
        started = perf_counter()
        tool_count = 0
        retries = 0
        category = "ok"

        if not self.configured:
            return self._finish(
                request_id=request_id,
                category="not_configured",
                started=started,
                tool_count=0,
                retries=0,
                reply=(
                    "Ask My Bee is not configured on this server yet. "
                    "Please ask a supervisor to set GEMINI_API_KEY, then try again."
                ),
            )

        # Restore app history (sanitized) plus a scoped hive directory so the
        # model can resolve "Hive 3" without guessing.
        contents: list[dict[str, Any]] = []
        history = messages[-_MAX_HISTORY:]
        add_context = True
        for message in history:
            text = (message.content or "").strip()
            if not text:
                continue
            if message.role == "assistant":
                contents.append({"role": "model", "parts": [{"text": text[:_MAX_MODEL_TEXT]}]})
                continue
            merged = text[:_MAX_USER_TEXT]
            if add_context:
                directory = self._hive_directory(user)
                if directory:
                    merged = (
                        f"{text}\n\n"
                        "[Your hives (id -> hive_code -> status). Use these ids "
                        "verbatim in tools; call get_my_hives for the full list; "
                        "ask the user to clarify if no hive matches.]\n"
                        + directory
                    )
                add_context = False
            contents.append({"role": "user", "parts": [{"text": merged[:_MAX_USER_TEXT]}]})

        context = ToolContext(
            user=user,
            services=self._services,
            risk_engine=self._risk_engine,
            request_id=request_id or "",
            settings=self._settings,
        )
        system_prompt = (SYSTEM_PROMPT.strip() + f"\n\nToday: {_today()}")
        if language:
            system_prompt += (
                f"\nThe app is set to {language}. Answer in that language "
                "(the same script), even if the user wrote something else."
            )

        for _ in range(_MAX_TOOL_ROUNDS + 1):
            turn = await self._provider.generate(
                system=system_prompt,
                contents=contents,
                tool_declarations=TOOL_DECLARATIONS,
            )
            retries = max(retries, turn.retries)
            if turn.error:
                kind = turn.kind or kind_from_message(turn.error)
                category = kind
                return self._finish(
                    request_id=request_id,
                    category=category,
                    started=started,
                    tool_count=tool_count,
                    retries=retries,
                    reply=self._friendly_error(turn.error, kind),
                )
            if not turn.tool_calls:
                reply = turn.text.strip()
                if not reply:
                    reply = "I'm not sure I understood. Could you repeat that?"
                return self._finish(
                    request_id=request_id,
                    category=category,
                    started=started,
                    tool_count=tool_count,
                    retries=retries,
                    reply=reply,
                )

            for call in turn.tool_calls:
                result = execute_ai_tool(call.name, call.args, context=context)
                tool_count += 1
                if result.get("status") == "error" and result.get("database"):
                    # The database could not record/serve this request — surface
                    # an honest message instead of looping Gemini into a dead end.
                    category = "database"
                    return self._finish(
                        request_id=request_id,
                        category=category,
                        started=started,
                        tool_count=tool_count,
                        retries=retries,
                        reply=(
                            "Your request reached HoneyChain, but the database "
                            "could not complete it. Please try again in a moment."
                        ),
                    )
                function_call_part: dict[str, Any] = {
                    "functionCall": {"name": call.name, "args": call.args}
                }
                if call.id:
                    function_call_part["functionCall"]["id"] = call.id
                if call.thought_signature:
                    function_call_part["thoughtSignature"] = call.thought_signature
                contents.append({"role": "model", "parts": [function_call_part]})
                contents.append(
                    {
                        "role": "user",
                        "parts": [
                            {"functionResponse": {"name": call.name, "response": result}}
                        ],
                    }
                )

        category = "too_many_tool_rounds"
        return self._finish(
            request_id=request_id,
            category=category,
            started=started,
            tool_count=tool_count,
            retries=retries,
            reply=(
                "This is taking a lot of steps. Could you confirm what you want, "
                "or ask more simply?"
            ),
        )

    # -- helpers ---------------------------------------------------------------
    def _finish(
        self,
        *,
        request_id: str | None,
        category: str,
        started: float,
        tool_count: int,
        retries: int,
        reply: str,
    ) -> AIChatResponse:
        latency_ms = int((perf_counter() - started) * 1000)
        self._log_request(
            request_id=request_id,
            model=getattr(self._settings, "gemini_model", "") or "",
            category=category,
            retries=retries,
            tool_count=tool_count,
            latency_ms=latency_ms,
        )
        return AIChatResponse(
            reply=reply,
            request_id=request_id,
            tool_count=tool_count,
        )

    def _log_request(
        self,
        *,
        request_id: str | None,
        model: str,
        category: str,
        retries: int,
        tool_count: int,
        latency_ms: int,
    ) -> None:
        get_logger("honeychain.ai").info(
            "ask-my-bee chat category=%s request_id=%s model=%s retries=%d "
            "tools=%d latency_ms=%d",
            category, request_id, model, retries, tool_count, latency_ms,
        )

    def _hive_directory(self, user: Any) -> str:
        try:
            hives = self._services["hives"].list_for_user(user=user)[:100]
        except Exception:  # noqa: BLE001 — context is advisory
            return ""
        lines = []
        for hive in hives:
            lines.append(
                f"- {hive.get('hive_code') or '?'} | id {hive.get('id')} | "
                f"{hive.get('status') or 'active'}"
            )
        return "\n".join(lines)

    def _friendly_error(self, detail: str, kind: str = "") -> str:
        """Turn a classified Gemini/provider error into an honest message.

        Every failure maps to a DISTINCT user-facing string; nothing quietly
        collapses into a generic "technical problem". When a scripted fake omits
        the ``kind`` we re-classify from the error text.
        """
        kind = kind or kind_from_message(detail)
        if kind == CAT_RATE_LIMIT:
            self._log_warning(detail, kind)
            return "Ask My Bee is busy right now. Please wait a moment and try again."
        if kind == CAT_QUOTA:
            self._log_warning(detail, kind)
            return "Ask My Bee has reached today's AI limit. Try again later."
        if kind in (CAT_AUTH, CAT_MODEL_NOT_FOUND):
            self._log_warning(detail, kind)
            return "Ask My Bee AI is not configured correctly."
        if kind == CAT_BAD_REQUEST:
            self._log_warning(detail, kind)
            return "Ask My Bee couldn't understand that request."
        if kind in (CAT_UNAVAILABLE, CAT_NETWORK):
            self._log_warning(detail, kind)
            return "Ask My Bee is temporarily unavailable. Please try again."
        if kind == CAT_BLOCKED:
            return (
                "I couldn't respond to that. Could you rephrase it? I'm happy "
                "to help with your hives, harvesting and inspections."
            )
        if kind == CAT_MAX_TOKENS:
            return "Could you ask me a slightly shorter question? I can answer most things."
        self._log_warning(detail, kind)
        return "Ask My Bee couldn't complete that request. Please try again."

    def _log_warning(self, detail: str, kind: str) -> None:
        get_logger("honeychain.ai").warning(
            "Gemini request failed; the user sees: kind=%s detail=%s",
            kind,
            (detail or "")[:500],
        )


def _today() -> str:
    from datetime import date

    return date.today().isoformat()


def get_logger(name: str):
    from ..core.logging import get_logger as _get_logger

    return _get_logger(name)