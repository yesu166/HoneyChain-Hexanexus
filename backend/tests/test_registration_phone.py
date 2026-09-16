from __future__ import annotations

import uuid

REG = "/api/v1/auth/register"


def _register(client, email: str, phone: str = ""):
    return client.post(
        REG,
        json={
            "email": email,
            "name": "Phone Test",
            "phone": phone,
            "password": "Password!123",
            "role": "beekeeper",
        },
    )


def test_blank_phone_does_not_collide_with_existing_blank_phone_users(client):
    """The users table legitimately holds many rows with phone == ''.

    Registering a phone-less user must not collide with them: querying the
    phone column with "" used to match an unrelated account and returned
    "user already exists" for every phone-less signup (live Supabase bug).
    """
    first = _register(client, f"p1-{uuid.uuid4().hex[:10]}@x.io", phone="")
    assert first.status_code == 201, first.text
    second = _register(client, f"p2-{uuid.uuid4().hex[:10]}@x.io", phone="")
    assert second.status_code == 201, second.text


def test_duplicate_real_phone_is_rejected(client):
    phone = f"+9198{uuid.uuid4().int % 10**8:08d}"
    first = _register(client, f"a-{uuid.uuid4().hex[:10]}@x.io", phone=phone)
    assert first.status_code == 201, first.text
    second = _register(client, f"b-{uuid.uuid4().hex[:10]}@x.io", phone=phone)
    assert second.status_code == 409, second.text
