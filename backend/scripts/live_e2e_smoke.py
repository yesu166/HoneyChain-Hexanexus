"""Live Ask My Bee E2E smoke — REAL Gemini + REAL Supabase, no mocks.

Requires the backend running on 127.0.0.1:8000 (uvicorn with backend/.env where
GEMINI_API_KEY and SUPABASE_* are set). Runs:
  1. register a temporary beekeeper
  2. login -> JWT
  3. /ai/status (enabled, configured, model)
  4. read tool: chat "Show my hives" via real Gemini
  5. write tool: chat "Create a hive ..." -> confirmation gate -> confirm ->
     real Supabase row created (verified by GET /hives read-back)
  6. cleanup: remove the created hive, beekeeper and user rows.

Prints PASS/FAIL per step; exits 0 only if every step passes.
"""
from __future__ import annotations

import os
import sys
import time
import uuid

import httpx
from dotenv import load_dotenv

HERE = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(os.path.dirname(HERE), ".env"))

BASE = os.getenv("LIVE_BASE", "http://127.0.0.1:8000/api/v1")
EMAIL = f"askbee_e2e_{int(time.time())}_{uuid.uuid4().hex[:6]}@example.com"
PASSWORD = "SmokeTest#2026!"
HIVE_CODE = f"SMOKE-{uuid.uuid4().hex[:6]}"

passed = 0


def mark(label: str, ok: bool, detail: str = "") -> None:
    global passed
    status = "PASS" if ok else "FAIL"
    print(f"[{status}] {label}" + (f" | {detail}" if detail else ""))
    if ok:
        passed += 1


def main() -> int:
    with httpx.Client(base_url=BASE, timeout=90.0) as client:
        # 1 + 2. register + login -------------------------------------------
        try:
            r = client.post(
                "/auth/register",
                json={
                    "email": EMAIL,
                    "name": "Ask Bee E2E",
                    "password": PASSWORD,
                    "role": "beekeeper",
                },
            )
            mark("register temporary beekeeper", r.status_code == 201, str(r.status_code))
            r.raise_for_status()
        except httpx.HTTPError as e:
            mark("register temporary beekeeper", False, repr(e))
            return 1

        try:
            r = client.post(
                "/auth/login",
                json={"identifier": EMAIL, "password": PASSWORD},
            )
            mark("login returns JWT", r.status_code == 200, str(r.status_code))
            r.raise_for_status()
            token = r.json()["access_token"]
        except httpx.HTTPError as e:
            mark("login returns JWT", False, repr(e))
            return 1

        headers = {"Authorization": f"Bearer {token}"}

        # 3. /ai/status -------------------------------------------------------
        try:
            r = client.get("/ai/status", headers=headers)
            body = r.json()
            ok = (
                r.status_code == 200
                and body.get("enabled") is True
                and body.get("configured") is True
                and "gemini" in (body.get("model") or "").lower()
            )
            mark(
                "ai/status enabled+configured+model",
                ok,
                f"model={body.get('model')} stt.available={body.get('stt', {}).get('available')}",
            )
        except httpx.HTTPError as e:
            mark("ai/status enabled+configured+model", False, repr(e))
            return 1

        # 4. read tool via real Gemini ---------------------------------------
        def chat(messages: list[dict]) -> dict:
            resp = client.post(
                "/ai/chat",
                json={"messages": messages, "request_id": uuid.uuid4().hex},
                headers=headers,
            )
            resp.raise_for_status()
            return resp.json()

        read_reply = None
        try:
            body = chat([{"role": "user", "content": "Show my hives"}])
            read_reply = body.get("reply", "")
            mark(
                "REAL GEMINI read tool call (get_my_hives)",
                body.get("tool_count", 0) >= 1,
                f"tool_count={body.get('tool_count')} reply='{read_reply[:120]}'",
            )
        except httpx.HTTPError as e:
            mark("REAL GEMINI read tool call (get_my_hives)", False, repr(e))
            return 1

        # 5. write tool with confirmation gate -------------------------------
        write_created = False
        try:
            def chat_or_none(messages: list[dict]) -> dict | None:
                for attempt in range(3):
                    try:
                        return chat(messages)
                    except httpx.HTTPError:
                        # transient server blip — retry once/twice
                        time.sleep(3)
                return None

            first = chat_or_none(
                [
                    {
                        "role": "user",
                        "content": f"Create a new hive with code {HIVE_CODE} at my smoke test apiary.",
                    }
                ]
            )
            gated = True
            if first is not None:
                # Safety property: nothing may be recorded before confirmation.
                probe = client.get("/hives", headers=headers)
                gated = not any(
                    h.get("hive_code") == HIVE_CODE for h in probe.json()
                )
                mark(
                    "WRITE confirmation gate: nothing recorded on first turn",
                    gated,
                    f'first_reply="{first.get("reply", "")[:140]}"',
                )
            else:
                mark("WRITE confirmation gate: nothing recorded on first turn", False, "first chat call failed")

            second = chat_or_none(
                [
                    {
                        "role": "user",
                        "content": f"Create a new hive with code {HIVE_CODE} at my smoke test apiary.",
                    },
                    {
                        "role": "assistant",
                        "content": first.get("reply", "") if first else "",
                    },
                    {"role": "user", "content": "Yes, confirm."},
                ]
            )
            mark(
                "REAL GEMINI confirmed write completes",
                second is not None and second.get("tool_count", 0) >= 1,
                f'tools={second.get("tool_count", 0) if second else "?"} reply="{ (second or {}).get("reply", "")[:140] }"',
            )
        except httpx.HTTPError as e:
            mark("REAL GEMINI confirmed write completes", False, repr(e))
            return 1

        # 6. read-back from real Supabase ------------------------------------
        try:
            r = client.get("/hives", headers=headers)
            rows = r.json()
            matched = [h for h in rows if h.get("hive_code") == HIVE_CODE]
            write_created = len(matched) == 1
            mark(
                "REAL SUPABASE read-back shows created hive",
                write_created,
                f"found {len(matched)} matching hive(s)",
            )
        except httpx.HTTPError as e:
            mark("REAL SUPABASE read-back shows created hive", False, repr(e))
            return 1

        # 7. cleanup ----------------------------------------------------------
        cleaned = True
        try:
            import supabase

            url = os.getenv("SUPABASE_URL", "")
            key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
            user_id = ""
            try:
                me = client.get("/auth/me", headers=headers)
                if me.status_code == 200:
                    user_id = me.json().get("id", "")
            except httpx.HTTPError:
                pass
            if url and key:
                sb = supabase.create_client(url, key)
                if write_created:
                    for h in matched:
                        sb.table("hives").delete().eq("id", h["id"]).execute()
                if user_id:
                    sb.table("beekeepers").delete().eq("id", user_id).execute()
                    sb.table("users").delete().eq("id", user_id).execute()
        except Exception as e:  # noqa: BLE001
            cleaned = False
            print(f"[WARN] cleanup failed: {e!r}")
        mark("cleanup removed temp rows", cleaned)

    total = 7
    print(f"\nResult: {passed}/{total} live E2E checks passed.")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())