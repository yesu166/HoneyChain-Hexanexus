#!/usr/bin/env python3
"""HoneyChain E2E Fabric proof -- real production HTTP API -> real chaincode tx.

Runs ON the EC2 host next to the deployed backend (127.0.0.1:8000) and the Node
Fabric gateway (127.0.0.1:9446). Creates a real platform org + admin, a real
batch (Supabase), then anchors a real evidence bundle through the production
FastAPI code path, and independently reads the result back from the ledger
(gateway evaluate + peer CLI block fetch). Nothing is fabricated.
"""
from __future__ import annotations

import json
import os
import subprocess
import time
import urllib.error
import urllib.request

import jwt

BASE = "http://127.0.0.1:8000"
GW = "http://127.0.0.1:9446"
TN = "/home/ubuntu/honeychain/fabric-samples/test-network"
ENV = {}
OUT = {}
TS = int(time.time())
NAME = f"HoneyChain E2E Fabric Proof {TS}"
ADMIN_EMAIL = f"e2e.admin.{TS}@example.in"
PASSWORD = "Str0ngPass!42"
BATCH_CODE = f"E2E-FABRIC-{TS}"
ORDERER_CA = (
    f"{TN}/organizations/ordererOrganizations/example.com/orderers/"
    "orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
)

PEER_ENV = os.environ.copy()
PEER_ENV.update({
    "PATH": "/home/ubuntu/honeychain/fabric-samples/bin:" + os.environ.get("PATH", ""),
    "FABRIC_CFG_PATH": "/home/ubuntu/honeychain/fabric-samples/config",
    "CORE_PEER_TLS_ENABLED": "true",
    "CORE_PEER_LOCALMSPID": "Org1MSP",
    "CORE_PEER_TLS_ROOTCERT_FILE": (
        f"{TN}/organizations/peerOrganizations/org1.example.com/peers/"
        "peer0.org1.example.com/tls/ca.crt"
    ),
    "CORE_PEER_MSPCONFIGPATH": (
        f"{TN}/organizations/peerOrganizations/org1.example.com/users/"
        "Admin@org1.example.com/msp"
    ),
    "CORE_PEER_ADDRESS": "localhost:7051",
})


def load_env(path):
    for line in open(path, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            ENV[k.strip()] = v.strip()


def emit(key, value):
    OUT[key] = value
    print(f"{key}: {value}", flush=True)


def call(method, path, token=None, body=None):
    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    data = json.dumps(body).encode("utf-8") if body is not None else None
    try:
        with urllib.request.urlopen(req, data=data, timeout=60) as r:
            raw = r.read().decode("utf-8", "replace")
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            return e.code, (json.loads(raw) if raw else None)
        except Exception:
            return e.code, {"raw": raw[:400]}
    except Exception as e:
        return -1, {"exc": str(e)}


def gw_call(method, path, body=None):
    req = urllib.request.Request(GW + path, method=method)
    req.add_header("Content-Type", "application/json")
    data = json.dumps(body).encode("utf-8") if body is not None else None
    try:
        with urllib.request.urlopen(req, data=data, timeout=60) as r:
            raw = r.read().decode("utf-8", "replace")
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            return e.code, (json.loads(raw) if raw else None)
        except Exception:
            return e.code, {"raw": raw[:400]}
    except Exception as e:
        return -1, {"exc": str(e)}


def peer_channel_info():
    p = subprocess.run(
        ["peer", "channel", "getinfo", "-c", "mychannel"],
        env=PEER_ENV, capture_output=True, text=True, timeout=60,
    )
    out = p.stdout + p.stderr
    marker = "Blockchain info: "
    idx = out.find(marker)
    if idx < 0:
        return {"error": out[-300:]}
    return json.loads(out[idx + len(marker):].strip().splitlines()[0])


def fetch_and_decode_block(number, tag):
    pb = f"/tmp/e2e_block_{tag}.pb"
    js = f"/tmp/e2e_block_{tag}.json"
    p = subprocess.run(
        ["peer", "channel", "fetch", str(number), pb, "-c", "mychannel",
         "--orderer", "localhost:7050", "--tls", "--cafile", ORDERER_CA],
        env=PEER_ENV, capture_output=True, text=True, timeout=90,
    )
    if p.returncode != 0:
        return {"error": (p.stdout + p.stderr)[-300:]}
    p2 = subprocess.run(
        ["configtxlator", "proto_decode", "--input", pb,
         "--type", "common.Block", "--output", js],
        env=PEER_ENV, capture_output=True, text=True, timeout=90,
    )
    if p2.returncode != 0:
        return {"error": (p2.stdout + p2.stderr)[-300:]}
    with open(js, "r", encoding="utf-8") as fh:
        blk = json.load(fh)
    hdr = blk.get("header", {})
    return {
        "number": hdr.get("number"),
        "previous_hash": hdr.get("previous_hash"),
        "data_hash": hdr.get("data_hash"),
        "raw_json_path": js,
        "raw_json": open(js, "r", encoding="utf-8").read(),
    }


def main() -> int:
    load_env("/home/ubuntu/honeychain/backend/.env")
    secret = ENV.get("JWT_SECRET", "")
    alg = ENV.get("JWT_ALGORITHM", "HS256")
    if not secret:
        print("NO_JWT_SECRET")
        return 1

    # ---- 0. pre-state ---------------------------------------------------
    code, h = gw_call("GET", "/health")
    emit("gw_health", f"{code} status={(h or {}).get('status')} channel={(h or {}).get('channel')} cc={(h or {}).get('chaincode')} v={(h or {}).get('chaincode_version')} seq={(h or {}).get('chaincode_sequence')}")
    code, ci = gw_call("GET", "/chaincode-info")
    emit("gw_chaincode_info", json.dumps(ci)[:400] if ci else ci)
    pre = peer_channel_info()
    emit("pre_channel_info", json.dumps(pre))
    pre_height = int(pre.get("height", 0))

    ptok = jwt.encode(
        {"sub": "e2e-fabric-proof", "role": "platform_oversight",
         "exp": int(time.time()) + 3600},
        secret, algorithm=alg,
    )

    # ---- 1. platform org + admin ---------------------------------------
    code, org = call("POST", "/api/v1/platform/organizations", ptok,
                     {"name": NAME, "client_id": f"e2e-{TS}"})
    okey = org.get("organization_key", "") if isinstance(org, dict) else ""
    emit("create_org", f"{code} key={okey}")

    code, inv = call("POST", f"/api/v1/platform/organizations/{okey}/admins", ptok, {"email": ADMIN_EMAIL})
    itok = inv.get("token", "") if isinstance(inv, dict) else ""
    emit("invite_admin", f"{code} has_token={bool(itok)}")

    phone = f"+91901{TS % 1000000:06d}"
    code, reg = call("POST", "/api/v1/auth/register", None,
                     {"email": ADMIN_EMAIL, "name": "E2E Admin", "phone": phone,
                      "password": PASSWORD, "role": "fpo", "invite_code": itok})
    emit("register_admin", f"{code} org={reg.get('org_id', '-') if isinstance(reg, dict) else '-'}")

    code, lg = call("POST", "/api/v1/auth/login", None, {"identifier": ADMIN_EMAIL, "password": PASSWORD})
    atok = lg.get("access_token", "") if isinstance(lg, dict) else ""
    emit("admin_login", f"{code} has_token={bool(atok)}")
    if not atok:
        print("NO_ADMIN_TOKEN; abort")
        return 1

    # ---- 1b. align org linkage with production convention ---------------
    # Finding: the platform invite->register flow stores the org KEY
    # ("ORG-xxxx") in users.org_id, but batches.organization_id is a uuid FK
    # (production users carry the org UUID). Realign OUR fresh test admin only.
    import supabase as _supabase

    sb = _supabase.create_client(ENV["SUPABASE_URL"], ENV["SUPABASE_SERVICE_ROLE_KEY"])
    rows = (sb.table("organizations").select("id,organization_key,status")
            .eq("organization_key", okey).execute().data)
    org_uuid = rows[0]["id"] if rows else ""
    emit("org_uuid", org_uuid)
    if org_uuid:
        sb.table("users").update({"org_id": org_uuid}).eq("email", ADMIN_EMAIL).execute()
        code, _ = call("POST", "/api/v1/platform/organizations/{}/activate".format(okey), ptok)
        emit("org_activate", code)
        code, lg2 = call("POST", "/api/v1/auth/login", None,
                         {"identifier": ADMIN_EMAIL, "password": PASSWORD})
        atok = lg2.get("access_token", "") if isinstance(lg2, dict) else atok
        code, me = call("GET", "/api/v1/auth/me", atok)
        emit("admin_org_after_fix", f"{code} org={me.get('org_id', '-') if isinstance(me, dict) else '-'}")

    # ---- 2. real batch (production DB) ---------------------------------
    code, batch = call("POST", "/api/v1/batches", atok,
                       {"batch_code": BATCH_CODE, "quantity_kg": 1.0,
                        "origin": "E2E proof origin", "honey_type": "Multiflora"})
    bid = batch.get("id", "") if isinstance(batch, dict) else ""
    emit("create_batch", f"{code} id={bid} code={batch.get('batch_code', '-') if isinstance(batch, dict) else '-'}")
    if not bid:
        print("NO_BATCH; abort")
        return 1

    # ---- 3. on-chain existence probe (before) --------------------------
    code, probe = gw_call("POST", "/evaluate", {"function": "getBatch", "args": [bid]})
    emit("onchain_getBatch_probe", f"{code} {json.dumps(probe)[:220]}")

    # ---- 4. REAL anchor via production API -----------------------------
    evidence = [{"kind": "operator_note", "value": f"E2E fabric anchor {TS}",
                 "captured_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}]
    code, bundle = call("POST", "/api/v1/evidence/bundles", atok,
                        {"entity_type": "batch", "entity_ref": bid,
                         "operator": okey or "e2e-fabric-proof",
                         "anchor": True, "evidence": evidence})
    anchor = bundle.get("anchor", {}) if isinstance(bundle, dict) else {}
    root = bundle.get("root_hash", "") if isinstance(bundle, dict) else ""
    emit("evidence_bundle", f"{code} bundle_id={bundle.get('bundle_id', '-') if isinstance(bundle, dict) else '-'} root={root}")
    emit("anchor_result", json.dumps(anchor)[:600])
    tx_hash = anchor.get("tx_hash", "") if isinstance(anchor, dict) else ""
    emit("tx_hash", tx_hash)
    emit("anchor_state", anchor.get("state") if isinstance(anchor, dict) else None)
    emit("anchor_network", anchor.get("network") if isinstance(anchor, dict) else None)

    # ---- 5. app read-back ----------------------------------------------
    code, back = call("GET", f"/api/v1/evidence/bundles/{bundle.get('bundle_id', '')}", atok)
    emit("readback_bundle", f"{code} anchor_present={bool((back or {}).get('anchor'))}")
    code, status = call("GET", "/api/v1/blockchain/status", atok)
    txs = (status or {}).get("transactions", []) if isinstance(status, dict) else []
    matching = [t for t in txs if tx_hash and t.get("tx_hash") == tx_hash]
    emit("readback_blockchain_status",
         f"{code} txs={len(txs)} matching_tx={len(matching)} "
         f"fabric_status={(status or {}).get('fabric', {}).get('status')}")
    if matching:
        emit("matching_tx_snapshot", json.dumps(matching[0])[:400])

    # ---- 6. independent ledger read-back --------------------------------
    code, ga = gw_call("POST", "/evaluate", {"function": "getAnchor", "args": [bid]})
    emit("ledger_getAnchor", f"{code} {json.dumps(ga)[:320]}")
    code, vm = gw_call("POST", "/evaluate", {"function": "verifyMerkleRoot", "args": [bid, root]})
    emit("ledger_verifyMerkleRoot", f"{code} {json.dumps(vm)[:320]}")
    code, gb2 = gw_call("POST", "/evaluate", {"function": "getBatch", "args": [bid]})
    emit("ledger_getBatch_after", f"{code} {json.dumps(gb2)[:320]}")

    # ---- 7. block-level proof -------------------------------------------
    post = peer_channel_info()
    emit("post_channel_info", json.dumps(post))
    post_height = int(post.get("height", 0))
    delta = post_height - pre_height
    emit("block_height_delta", delta)

    blocks = {}
    for n in sorted({pre_height, post_height - 1}):
        if n < pre_height:
            continue
        b = fetch_and_decode_block(n, f"b{n}")
        if "error" in b:
            blocks[str(n)] = b
        else:
            blocks[str(n)] = {
                "number": b.get("number"),
                "previous_hash": b.get("previous_hash"),
                "txid_in_block": bool(tx_hash) and (tx_hash in b["raw_json"]),
                "extends_pre_tip": b.get("previous_hash") == pre.get("currentBlockHash"),
                "is_channel_tip": b.get("data_hash") == post.get("currentBlockHash"),
            }
            del b
    emit("blocks", json.dumps(blocks))

    with open("/tmp/e2e_proof.json", "w", encoding="utf-8") as fh:
        json.dump(OUT, fh, indent=2)
    print("SAVED /tmp/e2e_proof.json")
    ok = bool(tx_hash) and delta >= 1
    print("E2E_RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
