"""Gemini provider behind a thin abstraction.

The backend talks to exactly one Gemini endpoint (Google's `generateContent`
REST API over httpx) — no second SDK — and exposes a narrow return shape
([GeminiTurn]) so the AI chat service stays testable with a scripted fake and
degrades gracefully (no key, outage, safety block) without ever fabricating.

Secrets stay server-side (`GEMINI_API_KEY`), never in requests from the app.

Error handling
--------------
Every failure is classified into an explicit category (rate_limit, quota,
auth, bad_request, model_not_found, unavailable, network, blocked,
max_tokens, unknown) so the UI can show an honest, distinct message instead of
a single generic "technical problem".

Retries (bounded)
-----------------
Only retryable transient categories are retried: per-minute ``rate_limit``
and ``unavailable``/``network``. Maximum 2 automatic retries. Delays follow
``Retry-After`` when the API supplies it (capped at 45s), otherwise exponential
backoff (1-2s then 3-5s). Daily ``quota`` exhaustion, auth, bad request, and
missing model are returned immediately — never retried — so we never create
retry storms against an unresolvable failure.
"""
from __future__ import annotations

import asyncio
import logging
import random
import re
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any

import httpx

logger = logging.getLogger("honeychain.ai.gemini")

# Error categories the whole pipeline (provider -> chat service -> UI) agree on.
CAT_RATE_LIMIT = "rate_limit"          # 429 per-minute; retryable, Retry-After respected
CAT_QUOTA = "quota"                    # 429 daily exhaustion; NOT retryable
CAT_AUTH = "auth"                      # 401/403; configuration problem
CAT_BAD_REQUEST = "bad_request"        # 400; the model rejected the request
CAT_MODEL_NOT_FOUND = "model_not_found"  # 404
CAT_UNAVAILABLE = "unavailable"        # 5xx provider/scale errors; retryable
CAT_NETWORK = "network"                # transport failure; retryable
CAT_BLOCKED = "blocked"                # safety refusal
CAT_MAX_TOKENS = "max_tokens"          # output truncated
CAT_UNKNOWN = "unknown"

MAX_AUTOMATIC_RETRIES = 2
_RETRY_AFTER_CAP_SECONDS = 45.0
_RETRYABLE_KINDS = {CAT_RATE_LIMIT, CAT_UNAVAILABLE, CAT_NETWORK}

# The pool normally tries each key once per request. When EVERY configured key
# fails with a retryable/transient error (e.g. Google "model high demand" 503
# spikes that hit the whole model, not one key), we pause briefly and run ONE
# more pass over the same deterministic key order before giving up. The wait is
# bounded (Retry-After honored, capped) so a single request never storms.
_POOL_RETRY_ROUNDS = 2
_POOL_RETRY_WAIT_CAP_SECONDS = 5.0


# A single function call the model decided to make (tool registry name + args).
@dataclass(frozen=True)
class GeminiToolCall:
    name: str
    args: dict[str, Any]
    # Gemini 3.x thinking models require echoing back the `id` and the
    # `thoughtSignature` on the replayed functionCall part for the tool result
    # turn, otherwise the API returns 400 (missing thought_signature).
    id: str = ""
    thought_signature: str = ""


@dataclass(frozen=True)
class GeminiTurn:
    text: str = ""
    tool_calls: tuple[GeminiToolCall, ...] = ()
    finish_reason: str = "stop"  # stop | tool | block | error
    error: str = ""
    kind: str = ""  # one of the CAT_* constants when finish_reason == "error"
    retries: int = 0  # automatic retries consumed by this turn
    retry_after: httpx.Response | None = None  # Retry-After hint for the retry loop


def classify_status_error(status: int, body: str) -> str:
    """Classify a Gemini HTTP error status+body into a CAT_* category.

    The distinguishing rule for 429 is whether this looks like the *daily*
    quota (``daily``/``per day``/``/day``) — which must not be retried — versus
    the *per-minute* free-tier throttle (``Please retry in Xs``), which is
    retryable.
    """
    lowered = (body or "").lower()
    if status in (401, 403):
        return CAT_AUTH
    if status == 404:
        return CAT_MODEL_NOT_FOUND
    if status == 429:
        if (
            "daily" in lowered
            or "per day" in lowered or "/day" in lowered
            or ("reset" in lowered and "day" in lowered)
        ):
            return CAT_QUOTA
        return CAT_RATE_LIMIT
    if status == 400:
        return CAT_BAD_REQUEST
    if status >= 500:
        return CAT_UNAVAILABLE
    return CAT_UNKNOWN


def kind_from_message(detail: str) -> str:
    """Recover a CAT_* category from a ``Gemini API <status>: <body>`` string.

    Used as a fallback when a turn carried no explicit ``kind`` (e.g. scripted
    fakes), so the chat service never silently falls through to "unknown".
    """
    lowered = (detail or "").lower()
    if "upstream unreachable" in lowered or "connect" in lowered or "network" in lowered:
        return CAT_NETWORK
    match = re.search(r"Gemini API (\d+)", detail or "")
    if match:
        return classify_status_error(int(match.group(1)), detail or "")
    if "quota" in lowered or "rate limit" in lowered or "429" in lowered:
        return CAT_RATE_LIMIT
    if "503" in lowered or "high demand" in lowered or "unavailable" in lowered:
        return CAT_UNAVAILABLE
    if "refused" in lowered or "safety" in lowered:
        return CAT_BLOCKED
    if "too" in lowered and "short" in lowered:
        return CAT_MAX_TOKENS
    return CAT_UNKNOWN


def _retry_after_seconds(response: httpx.Response | None, body: str) -> float | None:
    """Seconds to wait from HTTP ``Retry-After`` or a ``retry in Xs`` hint.

    Returns None when the API gave no usable hint (caller uses backoff).
    """
    if response is not None:
        raw = response.headers.get("Retry-After")
        if raw:
            try:
                seconds = float(raw)
            except ValueError:
                seconds = None
            if seconds is not None and seconds >= 0:
                return min(max(seconds, 0.5), _RETRY_AFTER_CAP_SECONDS)
    match = re.search(r"retry in ([\d.]+)s", (body or "").lower())
    if match:
        return min(max(float(match.group(1)), 0.5), _RETRY_AFTER_CAP_SECONDS)
    return None


def _backoff_delay(attempt: int) -> float:
    """Exponential backoff for transient retries (1-2s then 3-5s)."""
    if attempt <= 1:
        return round(random.uniform(1.0, 2.0), 2)
    return round(random.uniform(3.0, 5.0), 2)


def _pool_retry_delay(last: GeminiTurn) -> float:
    """Pool-level pause before the bounded retry pass over all keys.

    Prefers the API's ``Retry-After`` hint (capped so a single chat request
    never stalls), otherwise falls back to a short 1-2s backoff — enough to
    ride out a transient Google "model high demand" spike.
    """
    from_headers = _retry_after_seconds(last.retry_after, last.error)
    if from_headers is not None:
        return round(min(from_headers, _POOL_RETRY_WAIT_CAP_SECONDS), 2)
    return round(random.uniform(1.0, 2.0), 2)


class GeminiProvider(ABC):
    @abstractmethod
    async def generate(
        self,
        *,
        system: str,
        contents: list[dict[str, Any]],
        tool_declarations: list[dict[str, Any]],
    ) -> GeminiTurn: ...


class GoogleGeminiProvider(GeminiProvider):
    """Calls `models/{model}:generateContent` exactly as documented for Gemini
    tools/function-calling: model parts carry `functionCall`, the caller answers
    with `functionResponse` parts under role `user`.
    """

    def __init__(
        self,
        api_key: str,
        model: str,
        base_url: str = "https://generativelanguage.googleapis.com",
        timeout: float = 90.0,
        transport: httpx.AsyncBaseTransport | None = None,
        max_retries: int = MAX_AUTOMATIC_RETRIES,
    ) -> None:
        self._api_key = api_key
        self._model = model
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout
        self._transport = transport
        self._max_retries = max_retries

    @property
    def model(self) -> str:
        return self._model

    async def generate(
        self,
        *,
        system: str,
        contents: list[dict[str, Any]],
        tool_declarations: list[dict[str, Any]],
    ) -> GeminiTurn:
        url = f"{self._base_url}/v1beta/models/{self._model}:generateContent"
        payload: dict[str, Any] = {
            "system_instruction": {"parts": [{"text": system}]},
            "contents": contents,
            "tools": [{"functionDeclarations": tool_declarations}],
            "generationConfig": {
                "temperature": 0.4,
                "maxOutputTokens": 1024,
            },
        }
        headers = {"x-goog-api-key": self._api_key}
        transport = self._transport
        retries_used = 0

        for attempt in range(1, self._max_retries + 2):  # 1st + up to max_retries
            turn = await self._call_once(url, payload, headers, transport)
            if turn.kind not in _RETRYABLE_KINDS:
                return _with_retries(turn, retries_used)
            if attempt > self._max_retries:
                logger.warning(
                    "gemini gave up after %d retries kind=%s",
                    retries_used, turn.kind,
                )
                return _with_retries(turn, retries_used)
            delay = _retry_after_seconds(turn.retry_after, turn.error)
            if delay is None:
                delay = _backoff_delay(attempt)
            retries_used = attempt
            logger.warning("gemini retry #%d kind=%s delay=%.1fs", attempt, turn.kind, delay)
            await asyncio.sleep(delay)

        return GeminiTurn(finish_reason="error", error="unreachable", kind=CAT_NETWORK)

    async def _call_once(
        self,
        url: str,
        payload: dict[str, Any],
        headers: dict[str, str],
        transport: httpx.AsyncBaseTransport | None,
    ) -> GeminiTurn:
        """One non-throwing HTTP attempt. On failure it classifies the error into
        ``kind`` and carries any Retry-After hint for the retry loop.
        """
        started = time.perf_counter()
        kwargs: dict[str, Any] = {}
        if transport is not None:
            kwargs["transport"] = transport
        try:
            async with httpx.AsyncClient(timeout=self._timeout, **kwargs) as client:
                response = await client.post(url, json=payload, headers=headers)
            latency_ms = int((time.perf_counter() - started) * 1000)
            if response.status_code != 200:
                body = response.text[:500]
                kind = classify_status_error(response.status_code, body)
                logger.warning(
                    "gemini http %s kind=%s latency=%dms",
                    response.status_code, kind, latency_ms,
                )
                return GeminiTurn(
                    finish_reason="error",
                    error=f"Gemini API {response.status_code}: {body}",
                    kind=kind,
                    retry_after=response,
                )
            logger.info("gemini ok latency=%dms", latency_ms)
            try:
                data = response.json()
            except ValueError:
                return GeminiTurn(finish_reason="error", error="Gemini API: bad JSON", kind=CAT_UNKNOWN)
        except httpx.HTTPError as exc:
            logger.warning("gemini transport error: %s", exc)
            return GeminiTurn(
                finish_reason="error",
                error=f"upstream unreachable: {exc}",
                kind=CAT_NETWORK,
            )

        candidate = (data.get("candidates") or [{}])[0]
        finish_reason = (candidate.get("finishReason") or "STOP").lower()
        content = candidate.get("content") or {}
        parts = content.get("parts") or []

        tool_calls: list[GeminiToolCall] = []
        text_parts: list[str] = []
        for part in parts:
            function_call = part.get("functionCall")
            if isinstance(function_call, dict) and function_call.get("name"):
                tool_calls.append(
                    GeminiToolCall(
                        name=str(function_call["name"]),
                        args=dict(function_call.get("args") or {}),
                        id=str(function_call.get("id") or ""),
                        thought_signature=str(part.get("thoughtSignature") or ""),
                    )
                )
                continue
            if part.get("text"):
                text_parts.append(str(part["text"]))

        if finish_reason in ("safety",):
            return GeminiTurn(
                finish_reason="block",
                error="the model refused (safety block) — try rephrasing",
                kind=CAT_BLOCKED,
            )
        if tool_calls:
            return GeminiTurn(finish_reason="tool", tool_calls=tuple(tool_calls))
        text = "\n".join(text_parts).strip()
        if not text and finish_reason == "max_tokens":
            return GeminiTurn(
                finish_reason="error",
                error="response was cut off (max tokens) — ask a shorter question",
                kind=CAT_MAX_TOKENS,
            )
        success = text and finish_reason in ("stop", "max_tokens")
        if success:
            return GeminiTurn(text=text, finish_reason=finish_reason)
        error_message = (data.get("error") or {}).get("message", "")
        return GeminiTurn(
            finish_reason="error",
            error=(error_message or "Gemini API: unexpected response")[:500],
            kind=CAT_UNKNOWN,
        )


def _with_retries(turn: GeminiTurn, retries: int) -> GeminiTurn:
    """Attach the consumed retry count to a frozen GeminiTurn."""
    if not retries:
        return turn
    return GeminiTurn(
        text=turn.text,
        tool_calls=turn.tool_calls,
        finish_reason=turn.finish_reason,
        error=turn.error,
        kind=turn.kind,
        retries=retries,
    )


class GeminiProviderPool(GeminiProvider):
    """Rotates across independently-configured Gemini providers (one per key).

    A normal request always goes to the PRIMARY provider first. If it fails with
    a retryable transient category (per-minute 429, 5xx, network) the pool tries
    each configured fallback provider ONCE — never looping, never retrying a key
    that already failed in this request. Non-retryable failures (daily quota,
    auth, bad request, missing model, safety block) are returned immediately:
    the pool never rotates to dodge an exhausted quote or a config error.

    When only one provider is configured the pool simply delegates to it, so its
    internal bounded backoff still applies.
    """

    def __init__(self, providers: list[GoogleGeminiProvider]) -> None:
        self._providers = list(providers)

    @property
    def providers(self) -> list[GoogleGeminiProvider]:
        return self._providers

    async def generate(
        self,
        *,
        system: str,
        contents: list[dict[str, Any]],
        tool_declarations: list[dict[str, Any]],
    ) -> GeminiTurn:
        if len(self._providers) <= 1:
            return await self._providers[0].generate(
                system=system,
                contents=contents,
                tool_declarations=tool_declarations,
            )
        last_retryable: GeminiTurn | None = None
        for round_index in range(_POOL_RETRY_ROUNDS):
            for index, provider in enumerate(self._providers):
                turn = await provider.generate(
                    system=system,
                    contents=contents,
                    tool_declarations=tool_declarations,
                )
                if turn.kind == "" or turn.kind not in _RETRYABLE_KINDS:
                    if index > 0:
                        logger.info("gemini rotated to provider #%d (ok)", index)
                    return turn
                last_retryable = turn
                logger.warning(
                    "gemini provider #%d failed kind=%s (rotating)",
                    index, turn.kind,
                )
            # Every configured key failed with a retryable/transient error
            # (Google "model high demand" 503 hits the whole model, so rotating
            # keys can't help). Pause briefly, then retry the SAME deterministic
            # key order once, exactly like the error asks ("try again later").
            if round_index + 1 < _POOL_RETRY_ROUNDS and last_retryable is not None:
                delay = _pool_retry_delay(last_retryable)
                logger.warning(
                    "all %d providers failed kind=%s; pausing %.1fs then retrying",
                    len(self._providers), last_retryable.kind, delay,
                )
                await asyncio.sleep(delay)
        # Still failing after the bounded retry pass.
        return last_retryable or GeminiTurn(
            finish_reason="error", error="all Gemini providers failed", kind=CAT_NETWORK
        )


def build_gemini_provider(settings: Any) -> GeminiProvider:
    """Builds the provider pool from every configured Gemini key.

    Always returns a provider; the chat service checks `settings.gemini_api_key`
    before calling it, so an empty key set degrades to a graceful "not
    configured" reply instead of a network call. Fallback keys are only used on
    retryable transient failures, and the model configuration is never
    hardcoded in the app.
    """
    keys = list(getattr(settings, "gemini_api_keys", None) or ())
    # With a single key, keep the provider's bounded backoff retries. With a
    # pool we rotate CHANGING KEY — each key is tried exactly once per request
    # (max_retries=0), so there is no retry loop and no retry storm.
    rotate = len(keys) > 1
    providers = [
        GoogleGeminiProvider(
            api_key=key,
            model=settings.gemini_model,
            base_url=settings.google_ai_api_base,
            max_retries=0 if rotate else MAX_AUTOMATIC_RETRIES,
        )
        for key in keys
    ]
    if not providers:
        providers = [
            GoogleGeminiProvider(
                api_key="",
                model=settings.gemini_model,
                base_url=settings.google_ai_api_base,
            )
        ]
    return GeminiProviderPool(providers)