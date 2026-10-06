/**
 * Ask My Bee — portal-side adapter helpers (pure, testable).
 *
 * HoneyChain owns the assistant: the prompt, the HoneyChain tool calls, the Gemini
 * reasoning and the answer all happen server-side (`/api/v1/ai/chat`). The
 * portal only carries a plain chat transcript and renders the reply.
 *
 * These helpers hold the parts that must stay honest and are easy to get wrong:
 *   - what the status means to a user, and
 *   - what may be sent (bounded, non-empty transcript).
 */
import type { AIChatMessage, AIChatRequest, AIStatus } from "./types";
import type { Tone } from "./format";

/** HoneyChain rejects more than 40 messages (`AIChatRequest.messages` max_length). */
export const AI_MAX_MESSAGES = 40;

export interface AiStatusCopy {
  /** True only when HoneyChain says the assistant can actually answer. */
  ready: boolean;
  label: string;
  tone: Tone;
  detail: string;
}

/**
 * Translate the backend's status into honest user-facing copy. Never promises
 * an assistant that the server has not enabled.
 */
export function aiStatusCopy(status?: AIStatus | null): AiStatusCopy {
  if (!status) {
    return {
      ready: false,
      label: "Assistant status unknown",
      tone: "neutral",
      detail: "HoneyChain has not reported whether the Ask My Bee assistant is configured.",
    };
  }
  if (status.enabled) {
    return {
      ready: true,
      label: "HiveBee assistant ready",
      tone: "ok",
      detail: status.model
        ? `Answered by the HoneyChain server-side assistant (${status.model}). It reads only your authorized HoneyChain data.`
        : "Answered by the HoneyChain server-side assistant. It reads only your authorized HoneyChain data.",
    };
  }
  if (status.configured) {
    return {
      ready: false,
      label: "Assistant temporarily unavailable",
      tone: "warn",
      detail:
        "HoneyChain has an assistant key configured but the service is not enabled right now. Try again, or use the hive guidance below.",
    };
  }
  return {
    ready: false,
    label: "Assistant not configured on this server",
    tone: "warn",
    detail:
      "This HoneyChain deployment has no assistant model configured. The hive guidance below still uses your real HoneyChain readings and alerts.",
  };
}

/**
 * Build the request body HoneyChain accepts: drop empty messages, trim content and
 * keep only the most recent [AI_MAX_MESSAGES]. Returns an empty transcript when
 * nothing usable remains — callers must not send that (the backend answers 422).
 */
export function buildAiRequest(messages: AIChatMessage[]): AIChatRequest {
  const cleaned: AIChatMessage[] = [];
  for (const message of messages) {
    const content = (message?.content || "").trim();
    if (!content) continue;
    if (message.role !== "user" && message.role !== "assistant") continue;
    cleaned.push({ role: message.role, content });
  }
  return { messages: cleaned.slice(-AI_MAX_MESSAGES) };
}

/** A transcript is submittable only when it carries at least one user turn. */
export function hasUserTurn(request: AIChatRequest): boolean {
  return request.messages.some((m) => m.role === "user" && m.content.trim().length > 0);
}
