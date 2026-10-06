import { useMemo, useState } from "react";
import { PageHeader } from "@/components/hc/page-header";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/hc/query-state";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { StatusBadge } from "@/components/hc/status-badge";
import { useHoneyAuth } from "@/lib/hc/auth";
import { useHcQuery } from "@/lib/hc/query";
import { hiveRiskCopy } from "@/lib/hc/format";
import { AI_MAX_MESSAGES, aiStatusCopy, buildAiRequest, hasUserTurn } from "@/lib/hc/ai";
import type { AIChatMessage, HealthScore } from "@/lib/hc/types";

export function AskMyBeePage() {
  const { api } = useHoneyAuth();
  const hives = useHcQuery(["hives"], (hc) => hc.hives());
  const notes = useHcQuery(["notifications"], (hc) => hc.notifications());
  // The assistant itself lives in HoneyChain. This only asks whether it is usable.
  const status = useHcQuery(["ai", "status"], (hc) => hc.aiStatus());

  const [transcript, setTranscript] = useState<AIChatMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [chatError, setChatError] = useState<unknown>(null);

  const [hiveId, setHiveId] = useState("");
  const [health, setHealth] = useState<HealthScore | null>(null);
  const [healthPending, setHealthPending] = useState(false);
  const [healthError, setHealthError] = useState<unknown>(null);

  const copy = useMemo(() => aiStatusCopy(status.data), [status.data]);
  const assistantReady = copy.ready;

  const send = async () => {
    const request = buildAiRequest([...transcript, { role: "user", content: draft }]);
    if (!hasUserTurn(request)) return;
    setSending(true);
    setChatError(null);
    setTranscript(request.messages);
    setDraft("");
    try {
      const response = await api.aiChat(request);
      setTranscript((prev) => [...prev, { role: "assistant", content: response.reply }]);
    } catch (err) {
      setChatError(err);
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <PageHeader
        eyebrow="Guidance"
        title="Ask My Bee"
        description="Plain-language guidance from the HoneyChain assistant over your authorized hive readings and alerts. This is not a veterinary diagnosis and not a laboratory certificate."
      />

      <Card>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="font-display text-xl">HiveBee assistant</h3>
          <StatusBadge label={copy.label} tone={copy.tone} />
        </div>
        <p className="mt-2 text-sm leading-6 text-muted">{copy.detail}</p>

        {status.loading && !status.data ? <LoadingBlock label="Checking the assistant…" /> : null}
        {status.error ? (
          <div className="mt-3">
            <ErrorState error={status.error} onRetry={() => void status.refetch()} />
          </div>
        ) : null}
        {assistantReady ? (
          <div className="mt-4 space-y-3">
            {transcript.length ? (
              <ul className="space-y-2">
                {transcript.map((message, index) => (
                  <li
                    key={`${message.role}-${index}`}
                    className={
                      message.role === "user"
                        ? "rounded-xl bg-grove-50 px-3 py-2 text-sm"
                        : "rounded-xl bg-honey-50 px-3 py-2 text-sm"
                    }
                  >
                    <p className="text-[10px] font-bold tracking-[0.13em] text-grove-700 uppercase">
                      {message.role === "user" ? "You" : "HiveBee"}
                    </p>
                    <p className="mt-1 whitespace-pre-wrap leading-6">{message.content}</p>
                  </li>
                ))}
              </ul>
            ) : (
              <EmptyState title="Ask about a hive, a reading, or a batch." />
            )}
            <form
              className="flex flex-col gap-2 sm:flex-row"
              onSubmit={(event) => {
                event.preventDefault();
                void send();
              }}
            >
              <Input
                value={draft}
                onChange={(event) => setDraft(event.target.value)}
                placeholder="e.g. What should I check on my hives this week?"
                disabled={sending}
              />
              <Button type="submit" disabled={sending || !draft.trim()}>
                {sending ? "Asking…" : "Ask"}
              </Button>
            </form>
            {chatError ? <ErrorState error={chatError} /> : null}
            {transcript.length ? (
              <Button
                type="button"
                variant="secondary"
                onClick={() => {
                  setTranscript([]);
                  setChatError(null);
                }}
              >
                Start over
              </Button>
            ) : null}
            <p className="text-xs text-muted">
              The transcript is sent to HoneyChain, which answers from your authorized data. Up to{" "}
              {AI_MAX_MESSAGES} turns are kept in one request.
            </p>
          </div>
        ) : null}
      </Card>

      <Card>
        <h3 className="font-display text-xl">Hive guidance</h3>
        <p className="mt-1 text-sm text-muted">
          Direct guidance from this hive&apos;s recorded readings and any active alerts.
        </p>
        {hives.loading ? <LoadingBlock /> : null}
        {hives.error ? (
          <ErrorState error={hives.error} onRetry={() => void hives.refetch()} />
        ) : null}
        {/* `!hives.loading` is not enough here. `useHcQuery` maps `loading` to
            TanStack's `isPending`, which is false once the query has failed, so
            this branch used to fire *alongside* the error above: a 403 showed
            both "This action requires a different role" and "No hives are
            available to ask about yet." */}
        {!hives.error && (hives.data || []).length === 0 && !hives.loading ? (
          <div className="mt-3">
            <EmptyState title="No hives are available to ask about yet." />
          </div>
        ) : null}
        {!hives.error && (hives.data || []).length ? (
          <div className="mt-3 space-y-3">
            <select
              className="h-11 w-full rounded-xl border border-black/10 bg-paper px-3 text-sm"
              value={hiveId}
              onChange={(event) => {
                setHiveId(event.target.value);
                setHealth(null);
                setHealthError(null);
              }}
            >
              <option value="">Select a hive</option>
              {(hives.data || []).map((hive) => (
                <option key={hive.id} value={hive.id}>
                  {hive.hive_code}
                </option>
              ))}
            </select>
            <Button
              type="button"
              disabled={!hiveId || healthPending}
              onClick={async () => {
                setHealthPending(true);
                setHealthError(null);
                try {
                  setHealth(await api.hiveHealth(hiveId));
                } catch (err) {
                  setHealthError(err);
                } finally {
                  setHealthPending(false);
                }
              }}
            >
              {healthPending ? "Reading hive…" : "What should I do?"}
            </Button>
            {healthError ? <ErrorState error={healthError} /> : null}
            {health
              ? (() => {
                  const guidance = hiveRiskCopy(health);
                  const related = (notes.data?.items || [])
                    .filter((n) => n.hive_id === hiveId || n.category === "hive")
                    .slice(0, 3);
                  return (
                    <div className="space-y-3">
                      <StatusBadge label={guidance.title} tone={guidance.tone} />
                      <p className="text-sm leading-6">{guidance.detail}</p>
                      <p className="font-semibold">Next step</p>
                      <p className="text-sm leading-6">{guidance.next}</p>
                      {health.contributing_factors.length ? (
                        <ul className="list-disc pl-5 text-sm text-muted">
                          {health.contributing_factors.map((factor) => (
                            <li key={factor.factor}>
                              {factor.factor}: {factor.contribution}
                            </li>
                          ))}
                        </ul>
                      ) : null}
                      {/* The card above promises "readings and any active
                          alerts". A denied notifications request used to make
                          that block vanish silently, which is indistinguishable
                          from "this hive has no alerts". */}
                      {notes.error ? (
                        <div>
                          <p className="font-semibold">Related alerts</p>
                          <p className="mt-1 text-sm text-muted">
                            HoneyChain did not return alerts for this hive, so their absence here is
                            not a confirmation that there are none.
                          </p>
                        </div>
                      ) : related.length ? (
                        <div>
                          <p className="font-semibold">Related alerts</p>
                          <ul className="mt-1 space-y-1 text-sm">
                            {related.map((note) => (
                              <li key={note.notification_id}>{note.title}</li>
                            ))}
                          </ul>
                        </div>
                      ) : null}
                    </div>
                  );
                })()
              : null}
          </div>
        ) : null}
        <p className="mt-4 text-xs text-muted">
          Ask My Bee uses stored HoneyChain data. It is not a medical or veterinary authority.
        </p>
      </Card>
    </div>
  );
}
