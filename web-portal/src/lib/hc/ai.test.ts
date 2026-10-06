import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  AI_MAX_MESSAGES,
  aiStatusCopy,
  buildAiRequest,
  hasUserTurn,
} from "./ai.ts";

function user(content: string) {
  return { role: "user" as const, content };
}

describe("aiStatusCopy", () => {
  it("does not promise an assistant when the status is unknown", () => {
    const copy = aiStatusCopy(null);
    assert.equal(copy.ready, false);
    assert.equal(copy.tone, "neutral");
  });

  it("is ready only when HoneyChain enables the assistant", () => {
    const copy = aiStatusCopy({ enabled: true, configured: true, model: "gemini-2.0-flash" });
    assert.equal(copy.ready, true);
    assert.equal(copy.tone, "ok");
    assert.match(copy.detail, /gemini-2\.0-flash/);
  });

  it("treats configured-but-disabled as temporarily unavailable", () => {
    const copy = aiStatusCopy({ enabled: false, configured: true, model: "" });
    assert.equal(copy.ready, false);
    assert.equal(copy.tone, "warn");
    assert.match(copy.label, /temporarily unavailable/i);
  });

  it("reports a server without an assistant model honestly", () => {
    const copy = aiStatusCopy({ enabled: false, configured: false, model: "" });
    assert.equal(copy.ready, false);
    assert.match(copy.label, /not configured/i);
  });
});

describe("buildAiRequest", () => {
  it("drops empty and whitespace-only turns", () => {
    const request = buildAiRequest([user("  "), user("hello"), user("")]);
    assert.deepEqual(request.messages, [{ role: "user", content: "hello" }]);
  });

  it("trims content and keeps the transcript bounded", () => {
    const many = Array.from({ length: AI_MAX_MESSAGES + 5 }, (_, i) => user(`m${i}`));
    const request = buildAiRequest(many);
    assert.equal(request.messages.length, AI_MAX_MESSAGES);
    assert.equal(request.messages[request.messages.length - 1].content, `m${AI_MAX_MESSAGES + 4}`);
  });

  it("ignores turns whose role the backend does not accept", () => {
    const request = buildAiRequest([
      { role: "system" as never, content: "root" },
      user("real question"),
    ]);
    assert.deepEqual(request.messages, [{ role: "user", content: "real question" }]);
  });
});

describe("hasUserTurn", () => {
  it("is false for an empty transcript", () => {
    assert.equal(hasUserTurn(buildAiRequest([])), false);
  });

  it("is false when only the assistant has spoken", () => {
    assert.equal(hasUserTurn(buildAiRequest([{ role: "assistant", content: "hi" }])), false);
  });

  it("is true once the user has asked something", () => {
    assert.equal(hasUserTurn(buildAiRequest([user("what about hive A?")])), true);
  });
});
