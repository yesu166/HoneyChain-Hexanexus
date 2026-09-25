"""Ask My Bee backend tests.

These run against a scripted fake Gemini provider — the real Google endpoint is
never touched in the test suite (no key, no network, no SDK).
"""
from __future__ import annotations

from types import SimpleNamespace

import pytest

from app.adapters.ai.gemini import GeminiProvider, GeminiToolCall, GeminiTurn
from app.services.ai_chat_service import AIChatService


class _FakeSettings:
    gemini_api_key = "test-key"
    ai_assistant_enabled = True
    gemini_model = "fake-model"
    productivity_api_url = ""


class ScriptedProvider(GeminiProvider):
    def __init__(self, *turns: GeminiTurn):
        self.calls = []
        self._turns = list(turns)

    async def generate(self, *, system, contents, tool_declarations):
        self.calls.append(contents)
        if not self._turns:
            return GeminiTurn(text="(no more scripted turns)")
        return self._turns.pop(0)


def _turn(text: str = "", *tool_calls: GeminiToolCall) -> GeminiTurn:
    if tool_calls:
        return GeminiTurn(finish_reason="tool", tool_calls=tuple(tool_calls))
    return GeminiTurn(text=text)


def _beekeeper_user() -> SimpleNamespace:
    return SimpleNamespace(user_id="demo-beekeeper-id", role="beekeeper", org_id="")


@pytest.fixture()
def chat_service(client):
    client.app.state.settings.gemini_api_key = "test-key"

    def build(provider):
        return AIChatService(
            provider,
            client.app.state.services,
            client.app.state.risk_engine,
            client.app.state.settings,
        )

    return client, build


def _post(client, demo_token, user_text, request_id=None):
    return client.post(
        "/api/v1/ai/chat",
        headers={"Authorization": f"Bearer {demo_token}"},
        json={
            "messages": [{"role": "user", "content": user_text}],
            "request_id": request_id,
        },
    )


def test_status_requires_auth(client):
    assert client.get("/api/v1/ai/status").status_code == 401
    assert client.post("/api/v1/ai/chat", json={"messages": []}).status_code == 401


def test_status_reports_unconfigured(client, demo_token):
    client.app.state.settings.gemini_api_key = ""
    response = client.get(
        "/api/v1/ai/status", headers={"Authorization": f"Bearer {demo_token}"}
    )
    assert response.status_code == 200
    body = response.json()
    assert body["enabled"] is False
    assert body["configured"] is False
    assert body["model"] == "gemini-3.6-flash"


def test_status_reports_configured(client, demo_token, chat_service):
    _, build = chat_service
    client.app.state.ai_service = build(ScriptedProvider(_turn("hi")))
    response = client.get(
        "/api/v1/ai/status", headers={"Authorization": f"Bearer {demo_token}"}
    )
    body = response.json()
    assert body["enabled"] is True
    assert body["configured"] is True


def test_chat_plain_text_reply(client, demo_token, chat_service):
    _, build = chat_service
    provider = ScriptedProvider(_turn("Vanakkam! Hive 1 looks fine."))
    client.app.state.ai_service = build(provider)

    response = _post(client, demo_token, "how are my hives?", request_id="req-1")
    assert response.status_code == 200
    body = response.json()
    assert body["reply"] == "Vanakkam! Hive 1 looks fine."
    assert body["request_id"] == "req-1"
    assert body["tool_count"] == 0


def test_chat_transient_high_demand_shows_busy_message(client, demo_token, chat_service):
    """A transient Gemini 503 ('high demand') must warn and invite a retry,
    never masquerade as a recorded result."""
    _, build = chat_service
    provider = ScriptedProvider(
        GeminiTurn(
            error=(
                'Gemini API 503: {"error":{"code":503,"message":"This model is '
                'currently experiencing high demand.","status":"UNAVAILABLE"}}'
            )
        )
    )
    client.app.state.ai_service = build(provider)

    response = _post(client, demo_token, "create a hive to smoke test")
    assert response.status_code == 200
    reply = response.json()["reply"]
    assert "temporarily unavailable" in reply.lower() and "try again" in reply.lower()


def test_chat_free_tier_quota_shows_rate_limit_message(
    client, demo_token, chat_service
):
    """A Gemini 429 (per-minute free-tier throttle) must say it is busy and
    invite a retry, so nobody chases a phantom bug."""
    _, build = chat_service
    provider = ScriptedProvider(
        GeminiTurn(
            error=(
                'Gemini API 429: {"error":{"code":429,"message":"You exceeded '
                'your current quota ... limit: 20, model: gemini-3.6-flash, '
                'Please retry in 15.1s","status":"RESOURCE_EXHAUSTED"}}'
            )
        )
    )
    client.app.state.ai_service = build(provider)

    response = _post(client, demo_token, "are you there?")
    assert response.status_code == 200
    reply = response.json()["reply"]
    assert "busy" in reply.lower() and "try again" in reply.lower()


def test_chat_daily_quota_shows_todays_limit_message(
    client, demo_token, chat_service
):
    """A Gemini 429 that really is *daily* quota must say so and must NOT
    promise a retry in a moment."""
    _, build = chat_service
    provider = ScriptedProvider(
        GeminiTurn(
            error=(
                'Gemini API 429: {"error":{"code":429,"message":"You exceeded '
                'your daily limit of 100 requests per day for gemini-3.6-flash.",'
                '"status":"RESOURCE_EXHAUSTED"}}'
            )
        )
    )
    client.app.state.ai_service = build(provider)

    response = _post(client, demo_token, "how are my hives?")
    assert response.status_code == 200
    reply = response.json()["reply"]
    assert "today" in reply.lower() and "try again later" in reply.lower()


def test_chat_auth_error_seen_as_configuration_problem(
    client, demo_token, chat_service
):
    """401/403 must read as a server configuration problem, not user error."""
    _, build = chat_service
    provider = ScriptedProvider(
        GeminiTurn(
            error=(
                'Gemini API 403: {"error":{"code":403,"message":"API key not '
                'valid. Please pass a valid API key.","status":"PERMISSION_DENIED"}}'
            )
        )
    )
    client.app.state.ai_service = build(provider)

    response = _post(client, demo_token, "hi")
    assert response.status_code == 200
    reply = response.json()["reply"]
    assert "not configured correctly" in reply.lower()


def test_chat_bad_request_gets_distinct_message(client, demo_token, chat_service):
    """A 400 (e.g. malformed request) must get its own honest message."""
    _, build = chat_service
    provider = ScriptedProvider(
        GeminiTurn(
            error=(
                'Gemini API 400: {"error":{"code":400,"message":"Invalid '
                'argument: bad contents.","status":"INVALID_ARGUMENT"}}'
            )
        )
    )
    client.app.state.ai_service = build(provider)

    response = _post(client, demo_token, "hello")
    assert response.status_code == 200
    reply = response.json()["reply"]
    assert "couldn't understand" in reply.lower()


def test_chat_unknown_error_gets_honest_message(client, demo_token, chat_service):
    """An unclassified failure must never fake a success — it gets an honest
    generic-tooltip, not a fabricated ok."""
    _, build = chat_service
    provider = ScriptedProvider(
        GeminiTurn(error="Gemini API 418: {'error': 'I am a teapot'}")
    )
    client.app.state.ai_service = build(provider)

    response = _post(client, demo_token, "what now?")
    assert response.status_code == 200
    reply = response.json()["reply"]
    assert "couldn't complete" in reply.lower()


def test_chat_database_tool_failure_stops_loop_with_honest_message(
    client, demo_token, chat_service
):
    """When a tool hits a database/transport failure the loop must STOP and the
    user must see HoneyChain's own database message — not a Gemini paraphrase."""
    _, build = chat_service
    provider = ScriptedProvider(
        _turn(
            "",
            GeminiToolCall(name="get_my_hives", args={"limit": 10}),
        ),
    )
    client.app.state.ai_service = build(provider)
    original = client.app.state.services["hives"].list_for_user

    def boom(user):
        import httpx

        raise httpx.ConnectError("no route to database")

    client.app.state.services["hives"].list_for_user = boom
    try:
        response = _post(client, demo_token, "show my hives")
    finally:
        client.app.state.services["hives"].list_for_user = original
    assert response.status_code == 200
    body = response.json()
    assert "database could not complete" in body["reply"].lower()
    assert body["tool_count"] == 1
    # no second Gemini round happened after the database failure
    assert len(provider.calls) == 1


def test_chat_runs_tool_then_replies(client, demo_token, chat_service):
    _, build = chat_service
    provider = ScriptedProvider(
        _turn("", GeminiToolCall(name="get_my_hives", args={"limit": 10})),
        _turn("You have no hives yet. Want to register Hive 1?"),
    )
    client.app.state.ai_service = build(provider)

    response = _post(client, demo_token, "any hives?")
    assert response.status_code == 200
    assert response.json()["tool_count"] == 1
    assert provider.calls
    # the follow-up turn includes the functionResponse appended by the loop
    last_part = provider.calls[1][-1]["parts"][0]
    assert last_part["functionResponse"]["name"] == "get_my_hives"


def test_chat_replays_tool_call_id_and_thought_signature(client, demo_token, chat_service):
    _, build = chat_service
    provider = ScriptedProvider(
        _turn(
            "",
            GeminiToolCall(
                name="get_my_hives",
                args={"limit": 10},
                id="call_123",
                thought_signature="sig-abc",
            ),
        ),
        _turn("Here are your hives."),
    )
    client.app.state.ai_service = build(provider)

    response = _post(client, demo_token, "any hives?")
    assert response.status_code == 200
    model_part = provider.calls[1][-2]["parts"][0]
    assert model_part["functionCall"]["name"] == "get_my_hives"
    assert model_part["functionCall"]["id"] == "call_123"
    assert model_part["thoughtSignature"] == "sig-abc"


def test_chat_writes_require_confirmation(client, demo_token, chat_service):
    _, build = chat_service
    provider = ScriptedProvider(
        _turn("", GeminiToolCall(name="create_harvest", args={"hive_id": "hive-1", "quantity_kg": 5})),
        _turn("Let's record 5 kg from your hive — shall I?"),
    )
    client.app.state.ai_service = build(provider)

    response = _post(client, demo_token, "log 5kg harvest")
    assert response.status_code == 200
    call = provider.calls[1][-1]["parts"][0]["functionResponse"]["response"]
    assert call["status"] == "needs_confirmation"


def test_chat_confirmed_write_records_harvest(client, demo_token, chat_service):
    _, build = chat_service
    services = client.app.state.services
    hive = services["hives"].create(
        beekeeper_id="demo-beekeeper-id",
        data={"hive_code": "HIVE-A", "location": "Tamil Nadu"},
    )
    hive_id = hive["id"]

    provider = ScriptedProvider(
        _turn(
            "",
            GeminiToolCall(
                name="create_harvest",
                args={"hive_id": hive_id, "quantity_kg": 5.5, "confirmed": True},
            ),
        ),
        _turn("Recorded 5.5 kg from Hive HIVE-A."),
    )
    client.app.state.ai_service = build(provider)

    response = _post(client, demo_token, "yes, record it", request_id="req-9")
    assert response.status_code == 200
    call = provider.calls[1][-1]["parts"][0]["functionResponse"]["response"]
    assert call["status"] == "ok"
    assert call["harvest"]["quantity_kg"] == 5.5

    harvests = services["harvests"].list_for_user(user=_beekeeper_user())
    assert any(h.get("hive_id") == hive_id for h in harvests)
    assert response.json()["reply"] == "Recorded 5.5 kg from Hive HIVE-A."


def test_chat_confirmed_harvest_is_idempotent_per_request(client, demo_token, chat_service):
    _, build = chat_service
    services = client.app.state.services
    hive = services["hives"].create(
        beekeeper_id="demo-beekeeper-id", data={"hive_code": "HIVE-B"}
    )
    hive_id = hive["id"]
    provider = ScriptedProvider(
        _turn(
            "",
            GeminiToolCall(
                name="create_harvest",
                args={"hive_id": hive_id, "quantity_kg": 2.0, "confirmed": True},
            ),
        ),
        _turn("done"),
    )
    client.app.state.ai_service = build(provider)
    _post(client, demo_token, "record it", request_id="dup-1")
    number_after_first = len(services["harvests"].list_for_user(user=_beekeeper_user()))
    # A repeated transcript (same request_id) must not create a second row.
    _post(client, demo_token, "record it", request_id="dup-1")
    number_after_retry = len(services["harvests"].list_for_user(user=_beekeeper_user()))
    assert number_after_first == number_after_retry


def test_chat_refuses_foreign_hive(client, demo_token, chat_service):
    _, build = chat_service
    provider = ScriptedProvider(
        _turn(
            "",
            GeminiToolCall(
                name="create_harvest",
                args={"hive_id": "someone-elses-hive", "quantity_kg": 3, "confirmed": True},
            ),
        ),
        _turn("That hive is not in your scope."),
    )
    client.app.state.ai_service = build(provider)
    response = _post(client, demo_token, "harvest from X")
    assert response.status_code == 200
    call = provider.calls[1][-1]["parts"][0]["functionResponse"]["response"]
    assert call["status"] == "error"
    assert "scope" in call["error"]


def test_chat_productivity_stays_honest(client, demo_token, chat_service):
    _, build = chat_service
    provider = ScriptedProvider(
        _turn("", GeminiToolCall(name="predict_productivity", args={"hive_id": "hive-1"})),
        _turn("Productivity prediction is currently unavailable."),
    )
    client.app.state.ai_service = build(provider)
    response = _post(client, demo_token, "what yield?")
    assert response.status_code == 200
    call = provider.calls[1][-1]["parts"][0]["functionResponse"]["response"]
    assert call["available"] is False
    assert "not deployed" in call["reason"]


def test_chat_health_screening_uses_risk_engine(client, demo_token, chat_service):
    _, build = chat_service
    services = client.app.state.services
    hive = services["hives"].create(
        beekeeper_id="demo-beekeeper-id", data={"hive_code": "SCREEN-1"}
    )
    services["hives"].add_reading(
        hive["id"], {"temperature_c": 45, "humidity_percent": 20, "source": "manual"}
    )
    provider = ScriptedProvider(
        _turn(
            "",
            GeminiToolCall(name="get_bee_health_screening", args={"hive_id": hive["id"]}),
        ),
        _turn("Hive SCREEN-1 is at HIGH stress risk."),
    )
    client.app.state.ai_service = build(provider)
    response = _post(client, demo_token, "screening")
    assert response.status_code == 200
    call = provider.calls[1][-1]["parts"][0]["functionResponse"]["response"]
    assert call["assessment"]["risk_level"] == "HIGH"


def test_chat_rate_limit(client, demo_token, chat_service):
    from app.api import rate_limit

    rate_limit._clients.clear()
    _, build = chat_service
    client.app.state.ai_service = build(ScriptedProvider(_turn("ok")))
    client.app.state.settings.ai_rate_limit_per_minute = 1
    headers = {"Authorization": f"Bearer {demo_token}"}
    payload = {"messages": [{"role": "user", "content": "hi"}]}

    first = client.post("/api/v1/ai/chat", headers=headers, json=payload)
    second = client.post("/api/v1/ai/chat", headers=headers, json=payload)
    assert first.status_code == 200
    assert second.status_code == 429


def test_chat_validates_request_contract(client, demo_token, chat_service):
    _, build = chat_service
    client.app.state.ai_service = build(ScriptedProvider(_turn("ok")))
    headers = {"Authorization": f"Bearer {demo_token}"}
    empty = _post(client, demo_token, "   ")
    assert empty.status_code == 422
    bad_role = client.post(
        "/api/v1/ai/chat",
        headers=headers,
        json={"messages": [{"role": "system", "content": "root"}]},
    )
    assert bad_role.status_code == 422


def test_inspection_and_treatment_tools_roundtrip(client, demo_token, chat_service):
    _, build = chat_service
    services = client.app.state.services
    hive = services["hives"].create(
        beekeeper_id="demo-beekeeper-id", data={"hive_code": "OBS-1"}
    )
    hive_id = hive["id"]
    provider = ScriptedProvider(
        _turn(
            "",
            GeminiToolCall(
                name="record_inspection",
                args={
                    "hive_id": hive_id,
                    "activity_level": "normal",
                    "queen_seen": True,
                    "pests_seen": "varroa",
                    "hive_condition": "fair",
                    "observations": "a few mites under the lid",
                    "confirmed": True,
                },
            ),
            GeminiToolCall(
                name="record_treatment",
                args={
                    "hive_id": hive_id,
                    "treatment_name": "formic acid strips",
                    "dosage": "one strip for two weeks",
                    "confirmed": True,
                },
            ),
        ),
        _turn("Saved the check and the varroa treatment."),
    )
    client.app.state.ai_service = build(provider)
    response = _post(client, demo_token, "record inspection + treatment")
    assert response.status_code == 200
    assert response.json()["tool_count"] == 2

    inspections = services["inspections"].list_for_user(user=_beekeeper_user())
    assert any(i["hive_id"] == hive_id and i.get("pests_seen") == "varroa" for i in inspections)
    treatments = services["treatments"].list_for_user(user=_beekeeper_user())
    assert any(t["hive_id"] == hive_id and t["treatment_name"].startswith("formic") for t in treatments)


# ---------------------------------------------------------------------------
# Speech providers (STT / TTS) — honest availability, nothing faked.
# ---------------------------------------------------------------------------


def _stt_payload(audio: str = "QUFBQQ=="):
    return {"audio_base64": audio, "language": "ta"}


def _tts_payload(text: str = "வணக்கம்"):
    return {"text": text, "language": "ta"}


def test_speech_and_tts_require_auth(client):
    assert client.get("/api/v1/ai/status").status_code == 401
    assert client.post("/api/v1/ai/speech-to-text", json=_stt_payload()).status_code == 401
    assert client.post("/api/v1/ai/text-to-speech", json=_tts_payload()).status_code == 401


def test_status_reports_speech_providers_unavailable_by_default(client, demo_token):
    response = client.get(
        "/api/v1/ai/status", headers={"Authorization": f"Bearer {demo_token}"}
    )
    body = response.json()
    assert body["stt"]["available"] is False
    assert body["stt"]["provider"] == "none"
    assert body["tts"]["available"] is False
    assert body["tts"]["provider"] == "none"


def test_status_reports_speech_providers_unreachable_when_configured_but_down(
    client, demo_token
):
    # Honest health-check semantics: configuration alone never reports the
    # provider as available. Point at a dead port and expect "unreachable".
    settings = client.app.state.settings
    settings.ai_stt_enabled = True
    settings.ai_stt_base_url = "http://127.0.0.1:1/stt"
    settings.ai_tts_enabled = True
    settings.ai_tts_base_url = "http://127.0.0.1:1/tts"
    response = client.get(
        "/api/v1/ai/status", headers={"Authorization": f"Bearer {demo_token}"}
    )
    body = response.json()
    assert body["stt"]["available"] is False
    assert body["stt"]["provider"] == "indic_conformer"
    assert "unreachable" in body["stt"]["detail"]
    assert body["tts"]["available"] is False
    assert body["tts"]["provider"] == "indic_f5"
    assert "unreachable" in body["tts"]["detail"]


def test_status_reports_speech_provider_healthy_when_probe_succeeds(
    client, demo_token, monkeypatch
):
    from app.api.routes import ai as ai_routes
    from app.schemas.ai import SpeechProviderStatus

    settings = client.app.state.settings
    settings.ai_stt_enabled = True
    settings.ai_stt_base_url = "http://speech-service:8000"

    async def _fake_probe(base_url, provider):
        return SpeechProviderStatus(
            provider=provider, available=True, detail="service healthy and model loaded"
        )

    monkeypatch.setattr(ai_routes, "probe_speech_health", _fake_probe)
    response = client.get(
        "/api/v1/ai/status", headers={"Authorization": f"Bearer {demo_token}"}
    )
    body = response.json()
    assert body["stt"]["available"] is True
    assert body["stt"]["provider"] == "indic_conformer"
    assert body["tts"]["available"] is False  # still disabled in the config


def test_stt_rejects_invalid_audio_base64(client, demo_token):
    headers = {"Authorization": f"Bearer {demo_token}"}
    settings = client.app.state.settings
    settings.ai_stt_enabled = True
    settings.ai_stt_base_url = "http://127.0.0.1:1"
    response = client.post(
        "/api/v1/ai/speech-to-text",
        headers=headers,
        json=_stt_payload(audio="not-base64!!!"),
    )
    assert response.status_code == 422
    assert "not valid base64" in response.json()["detail"]


def test_stt_and_tts_unconfigured_return_503(client, demo_token):
    headers = {"Authorization": f"Bearer {demo_token}"}
    settings = client.app.state.settings
    settings.ai_stt_enabled = False
    settings.ai_tts_enabled = False

    stt = client.post("/api/v1/ai/speech-to-text", headers=headers, json=_stt_payload())
    assert stt.status_code == 503
    assert "not configured" in stt.json()["detail"]

    tts = client.post("/api/v1/ai/text-to-speech", headers=headers, json=_tts_payload())
    assert tts.status_code == 503
    assert "not configured" in tts.json()["detail"]


def test_stt_and_tts_unreachable_return_503(client, demo_token):
    headers = {"Authorization": f"Bearer {demo_token}"}
    settings = client.app.state.settings
    settings.ai_stt_enabled = True
    settings.ai_stt_base_url = "http://127.0.0.1:1"
    settings.ai_tts_enabled = True
    settings.ai_tts_base_url = "http://127.0.0.1:1"

    stt = client.post("/api/v1/ai/speech-to-text", headers=headers, json=_stt_payload())
    assert stt.status_code == 503
    assert "unreachable" in stt.json()["detail"]

    tts = client.post("/api/v1/ai/text-to-speech", headers=headers, json=_tts_payload())
    assert tts.status_code == 503
    # Per-language failure wording (language "ta" => "Tamil voice playback ...").
    assert "Tamil voice playback is temporarily unavailable." in tts.json()["detail"]

    tts_hi = client.post(
        "/api/v1/ai/text-to-speech",
        headers=headers,
        json={"text": "नमस्ते", "language": "hi"},
    )
    assert tts_hi.status_code == 503
    assert "Hindi voice playback is temporarily unavailable." in tts_hi.json()["detail"]


def test_chat_notifications_tool_returns_real_alerts(client, demo_token, chat_service):
    _, build = chat_service
    provider = ScriptedProvider(
        _turn("", GeminiToolCall(name="get_my_notifications", args={"limit": 10})),
        _turn("No alerts right now — your hives look clear."),
    )
    client.app.state.ai_service = build(provider)
    response = _post(client, demo_token, "any alerts?")
    assert response.status_code == 200
    assert response.json()["tool_count"] == 1
    call = provider.calls[1][-1]["parts"][0]["functionResponse"]["response"]
    assert call["status"] == "ok"
    assert "unread_count" in call
    assert "notifications" in call