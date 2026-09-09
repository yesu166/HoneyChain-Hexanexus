"use strict";

// tracer — HoneyChain chaincode (Fabric 2.5, Node.js API).
//
// Stored records:
//   anchor:<data_hash>  -> { dataHash, txRef, committedAt, committedBy, bundleId }
//   event:<event_id>    -> { eventId, actor, action, payloadHash, at }
//
// VerifyAnchor returns the stored anchor if one exists *and* the supplied
// dataHash matches. It never infers presence from anything except real state.
//
// NOTE: not executed in this environment (no Docker / Fabric network).

const { Contract } = require("fabric-contract-api");

const ANCHOR_PREFIX = "anchor:";
const EVENT_PREFIX = "event:";

class Tracer extends Contract {
  async Init(ctx) {}

  async AnchorEvidence(ctx, dataHash, txRef, bundleId, committedBy) {
    if (!dataHash) throw new Error("dataHash is required");
    const key = ANCHOR_PREFIX + dataHash;
    const existing = await ctx.stub.getState(key);
    if (existing && existing.length > 0) {
      return "already-anchored"; // idempotent: do not overwrite
    }
    const record = Buffer.from(
      JSON.stringify({
        dataHash,
        txRef,
        bundleId,
        committedBy,
        committedAt: new Date().toISOString(),
      })
    );
    await ctx.stub.putState(key, record);
    await ctx.stub.setEvent("evidence_anchored", record);
    return "anchored";
  }

  async VerifyAnchor(ctx, dataHash) {
    const existing = await ctx.stub.getState(ANCHOR_PREFIX + dataHash);
    if (!existing || existing.length === 0) {
      return JSON.stringify({ found: false });
    }
    return JSON.stringify({
      found: true,
      ...JSON.parse(existing.toString()),
    });
  }

  async RecordEvent(ctx, eventId, actor, action, payloadHash) {
    if (!eventId) throw new Error("eventId is required");
    const record = Buffer.from(
      JSON.stringify({
        eventId,
        actor,
        action,
        payloadHash,
        at: new Date().toISOString(),
      })
    );
    await ctx.stub.putState(EVENT_PREFIX + eventId, record);
    await ctx.stub.setEvent("event_recorded", record);
    return "recorded";
  }

  async GetEvent(ctx, eventId) {
    const existing = await ctx.stub.getState(EVENT_PREFIX + eventId);
    if (!existing || existing.length === 0) {
      return JSON.stringify({ found: false });
    }
    return existing.toString();
  }
}

module.exports = Tracer;