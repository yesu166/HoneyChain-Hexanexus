"""Provider-level tests: error classification, bounded retry, Retry-After.

These use httpx.MockTransport against the real GoogleGeminiProvider JSON path —
no network, no key. They prove that:
- per-minute 429 is retried (max 2) and eventually succeeds,
- daily quota / auth are NEVER retried,
- the error category is classified into GeminiTurn.kind.
"""
from __future__ import annotations

import asyncio
import json

import httpx
import pytest

from app.adapters.ai.gemini import (
    CAT_AUTH,
    CAT_BAD_REQUEST,
    CAT_MODEL_NOT_FOUND,
    CAT_QUOTA,
    CAT_RATE_LIMIT,
    CAT_UNAVAILABLE,
    GeminiProviderPool,
    GoogleGeminiProvider,
    classify_status_error,
    kind_from_message,
)

TOOL_DECLARATIONS: list[dict] = []


def _success_text() -> httpx.Response:
    body = {
        "candidates": [
            {"finishReason": "STOP", "content": {"parts": [{"text": "Vanakkam!"}]}}
        ]
    }
    return httpx.Response(200, json=body)


def _error(status: int, message: str, retry_after: str | None = None) -> httpx.Response:
    body = json.dumps({"error": {"code": status, "message": message, "status": "X"}})
    headers = {"Retry-After": retry_after} if retry_after else {}
    return httpx.Response(status, text=body, headers=headers)


def _provider_with(steps, handler_counter=None) -> GoogleGeminiProvider:
    steps = list(steps)
    local = {"calls": 0}
    counter = handler_counter if handler_counter is not None else local

    def handler(request: httpx.Request) -> httpx.Response:
        index = min(counter["calls"], len(steps) - 1)
        counter["calls"] += 1
        return steps[index]

    return GoogleGeminiProvider(
        api_key="test-key",
        model="gemini-3.6-flash",
        transport=httpx.MockTransport(handler),
    )


def _run(provider: GoogleGeminiProvider):
    async def go():
        return await provider.generate(
            system="sys", contents=[], tool_declarations=TOOL_DECLARATIONS
        )

    return asyncio.run(go())


def test_per_minute_429_is_retried_then_succeeds():
    provider = _provider_with(
        [
            _error(429, "Quota exceeded ... limit: 20 ... Please retry in 2s.", "1"),
            _error(429, "Quota exceeded ... limit: 20 ... Please retry in 2s.", "1"),
            _success_text(),
        ]
    )
    turn = _run(provider)
    assert turn.text == "Vanakkam!"
    assert turn.kind == ""
    assert turn.retries == 2


def test_per_minute_429_gives_up_after_max_retries():
    counter = {"calls": 0}
    provider = _provider_with(
        [
            _error(429, "Quota exceeded ... Please retry in 2s.", "1"),
            _error(429, "Quota exceeded ... Please retry in 2s.", "1"),
            _error(429, "Quota exceeded ... Please retry in 2s.", "1"),
        ],
        handler_counter=counter,
    )
    turn = _run(provider)
    assert turn.error
    assert turn.kind == CAT_RATE_LIMIT
    assert counter["calls"] == 3
    assert turn.retries == 2  # never more than 2 automatic retries


def test_daily_quota_is_never_retried():
    counter = {"calls": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        counter["calls"] += 1
        return _error(429, "You exceeded your daily quota of 100 requests per day.")

    provider = GoogleGeminiProvider(
        api_key="test-key",
        model="gemini-3.6-flash",
        transport=httpx.MockTransport(handler),
    )
    turn = _run(provider)
    assert counter["calls"] == 1
    assert turn.kind == CAT_QUOTA
    assert turn.retries == 0


def test_auth_error_is_never_retried():
    counter = {"calls": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        counter["calls"] += 1
        return _error(403, "API key not valid. Please pass a valid API key.")

    provider = GoogleGeminiProvider(
        api_key="test-key",
        model="gemini-3.6-flash",
        transport=httpx.MockTransport(handler),
    )
    turn = _run(provider)
    assert counter["calls"] == 1
    assert turn.kind == CAT_AUTH
    assert turn.retries == 0


def test_500_is_retried_then_succeeds():
    provider = _provider_with(
        [
            httpx.Response(503, text='{"error":{"message":"high demand"}}'),
            _success_text(),
        ]
    )
    turn = _run(provider)
    assert turn.text == "Vanakkam!"
    assert turn.retries == 1


def test_classify_429_rate_vs_daily():
    assert classify_status_error(429, "Please retry in 15.1s") == CAT_RATE_LIMIT
    assert classify_status_error(429, "daily limit of 100 requests per day") == CAT_QUOTA
    assert classify_status_error(429, "limit: 20, model: gemini-3.6-flash") == CAT_RATE_LIMIT


def test_classify_other_statuses():
    assert classify_status_error(401, "x") == CAT_AUTH
    assert classify_status_error(403, "x") == CAT_AUTH
    assert classify_status_error(404, "not found") == CAT_MODEL_NOT_FOUND
    assert classify_status_error(400, "bad") == CAT_BAD_REQUEST
    assert classify_status_error(503, "high demand") == CAT_UNAVAILABLE
    assert classify_status_error(500, "boom") == CAT_UNAVAILABLE


def test_kind_from_message_fallback():
    assert kind_from_message("Gemini API 503: high demand") == CAT_UNAVAILABLE
    assert kind_from_message("Gemini API 429: quota limit") == CAT_RATE_LIMIT
    assert kind_from_message("Gemini API 403: bad key") == CAT_AUTH
    assert kind_from_message("upstream unreachable: timeout") == "network"
    assert kind_from_message("Gemini API: unexpected") == "unknown"


def _pool(*first_steps, second_steps) -> GeminiProviderPool:
    def _mk(steps, base):
        steps = list(steps)
        calls = {"n": 0}

        def handler(request: httpx.Request) -> httpx.Response:
            i = min(calls["n"], len(steps) - 1)
            calls["n"] += 1
            return steps[i]

        return GoogleGeminiProvider(
            api_key=base,
            model="gemini-3.6-flash",
            transport=httpx.MockTransport(handler),
            max_retries=0,
        ), calls

    p1, c1 = _mk(first_steps, "key-1")
    p2, c2 = _mk(second_steps, "key-2")
    return GeminiProviderPool([p1, p2]), c1, c2


def test_pool_round_robin_starts_on_key1_then_key2():
    pool, c1, c2 = _pool(
        _success_text(),
        second_steps=[_success_text()],
    )
    first = _run(pool)
    assert first.text == "Vanakkam!"
    assert c1["n"] == 1
    assert c2["n"] == 0
    second = _run(pool)
    assert second.text == "Vanakkam!"
    assert c1["n"] == 1
    assert c2["n"] == 1


def test_pool_round_robin_cycles_three_keys():
    order: list[str] = []

    def _mk(base: str) -> GoogleGeminiProvider:
        def handler(request: httpx.Request) -> httpx.Response:
            order.append(base)
            return _success_text()

        return GoogleGeminiProvider(
            api_key=base,
            model="gemini-3.6-flash",
            transport=httpx.MockTransport(handler),
            max_retries=0,
        )

    pool = GeminiProviderPool([_mk("key-1"), _mk("key-2"), _mk("key-3")])
    for _ in range(4):
        _run(pool)
    assert order == ["key-1", "key-2", "key-3", "key-1"]


def test_pool_uses_only_one_key_per_request_on_retryable_error():
    pool, c1, c2 = _pool(
        _error(503, "model high demand", "0"),
        second_steps=[_success_text()],
    )
    turn = _run(pool)
    # One request, ONE key: key-1 fails transiently and the request returns the
    # error — key-2 is never called within the same request.
    assert turn.kind == CAT_UNAVAILABLE
    assert c1["n"] == 1
    assert c2["n"] == 0
    # The NEXT request lands on key-2.
    turn2 = _run(pool)
    assert turn2.text == "Vanakkam!"
    assert c2["n"] == 1


def test_pool_one_key_per_request_on_auth_error():
    pool, c1, c2 = _pool(
        _error(403, "API key not valid."),
        second_steps=[_success_text()],
    )
    turn = _run(pool)
    assert turn.kind == CAT_AUTH
    assert c1["n"] == 1
    assert c2["n"] == 0


def test_pool_one_key_per_request_on_daily_quota():
    pool, c1, c2 = _pool(
        _error(429, "You exceeded your daily quota of 100 requests per day."),
        second_steps=[_success_text()],
    )
    turn = _run(pool)
    assert turn.kind == CAT_QUOTA
    assert c1["n"] == 1
    assert c2["n"] == 0


def test_pool_keeps_exhausting_keys_round_robin():
    pool, c1, c2 = _pool(
        _error(429, "Quota exceeded ... limit: 20", "0"),
        second_steps=[_error(429, "Quota exceeded ... limit: 20", "0")],
    )
    t1 = _run(pool)
    assert t1.kind == CAT_RATE_LIMIT
    t2 = _run(pool)
    assert t2.kind == CAT_RATE_LIMIT
    assert c1["n"] == 1
    assert c2["n"] == 1
    t3 = _run(pool)
    assert t3.kind == CAT_RATE_LIMIT
    assert c1["n"] == 2  # wrapped back to key-1


def test_pool_provider_keeps_its_bounded_backoff():
    counter = {"calls": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        counter["calls"] += 1
        if counter["calls"] <= 2:
            return _error(503, "model high demand", "0")
        return _success_text()

    provider = GoogleGeminiProvider(
        api_key="key-1",
        model="gemini-3.6-flash",
        transport=httpx.MockTransport(handler),
        max_retries=2,
    )
    pool = GeminiProviderPool([provider])
    turn = _run(pool)
    assert turn.text == "Vanakkam!"
    assert counter["calls"] == 3
    assert turn.retries == 2


def test_pool_single_provider_delegates_query():
    counter = {"calls": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        counter["calls"] += 1
        return _success_text()

    single = GoogleGeminiProvider(
        api_key="key-1",
        model="gemini-3.6-flash",
        transport=httpx.MockTransport(handler),
    )
    turn = _run(GeminiProviderPool([single]))
    assert turn.text == "Vanakkam!"
    assert counter["calls"] == 1