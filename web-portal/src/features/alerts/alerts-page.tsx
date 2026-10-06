import { PageHeader } from "@/components/hc/page-header";
import { StatusBadge } from "@/components/hc/status-badge";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/hc/query-state";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { useHcMutation, useHcQuery } from "@/lib/hc/query";
import { fmtDate } from "@/lib/hc/format";
import { useHoneyAuth } from "@/lib/hc/auth";
import { toast } from "sonner";

export function AlertsPage() {
  const { mode } = useHoneyAuth();
  const notes = useHcQuery(["notifications"], (api) => api.notifications());
  const mark = useHcMutation((api, id: string) => api.markNotificationRead(id), [["notifications"]]);

  if (notes.loading) return <LoadingBlock label="Loading alerts…" />;
  if (notes.error) return <ErrorState error={notes.error} onRetry={() => void notes.refetch()} />;

  const items = notes.data?.items || [];
  const unread = items.filter((n) => !n.read);

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Monitoring"
        title="Alerts"
        description="Only notices returned by HoneyChain. Marking as read calls the notifications API."
      />
      {items.length === 0 ? (
        <EmptyState title="No alerts right now." detail="When a hive, batch, device, or cluster needs attention, it will appear here." />
      ) : (
        <div className="space-y-3">
          {(unread.length ? unread : items).map((n) => (
            <Card key={n.notification_id}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="font-display text-lg">{n.title}</h2>
                    <StatusBadge label={n.severity} />
                  </div>
                  <p className="mt-2 text-sm leading-6">{n.body}</p>
                  <p className="mt-2 text-sm font-medium">Next: {n.recommended_action}</p>
                  <p className="mt-1 text-xs text-muted">{fmtDate(n.created_at)}</p>
                </div>
                {!n.read ? (
                  <Button
                    variant="secondary"
                    type="button"
                    disabled={mark.isPending}
                    onClick={async () => {
                      try {
                        await mark.mutateAsync(n.notification_id);
                        toast.success(
                          mode === "demo"
                            ? "Marked read in demo workspace."
                            : "Marked read.",
                        );
                      } catch (err) {
                        toast.error(err instanceof Error ? err.message : "Could not mark as read.");
                      }
                    }}
                  >
                    Mark read
                  </Button>
                ) : null}
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
