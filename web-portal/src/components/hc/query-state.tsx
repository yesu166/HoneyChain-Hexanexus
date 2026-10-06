import type { ReactNode } from "react";
import { describeApiError } from "@/lib/hc/client";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

export function LoadingBlock({ label = "Loading…" }: { label?: string }) {
  return (
    <div className="space-y-3" role="status" aria-live="polite">
      <div className="flex items-center gap-2 text-sm text-muted">
        <span className="h-2 w-2 animate-pulse rounded-full bg-honey-500" />
        {label}
      </div>
      <Skeleton className="h-24 w-full" />
      <div className="grid gap-3 sm:grid-cols-3">
        <Skeleton className="h-20" />
        <Skeleton className="h-20" />
        <Skeleton className="h-20" />
      </div>
    </div>
  );
}

export function EmptyState({
  title,
  detail,
  action,
}: {
  title: string;
  detail?: string;
  action?: ReactNode;
}) {
  return (
    <div className="rounded-2xl border border-dashed border-black/15 bg-black/[0.02] px-4 py-10 text-center">
      <p className="font-semibold text-ink">{title}</p>
      {detail ? <p className="mt-1 text-sm text-muted">{detail}</p> : null}
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}

export function ErrorState({
  error,
  onRetry,
}: {
  error: unknown;
  onRetry?: () => void;
}) {
  const { title, detail } = describeApiError(error);
  return (
    <div className="rounded-2xl border border-red-200 bg-red-50 px-4 py-5 text-red-950">
      <p className="font-semibold">{title}</p>
      <p className="mt-1 text-sm">{detail}</p>
      {onRetry ? (
        <Button className="mt-3" variant="secondary" type="button" onClick={onRetry}>
          Try again
        </Button>
      ) : null}
    </div>
  );
}

export function QueryGate<T>({
  loading,
  error,
  data,
  empty,
  emptyTitle,
  emptyDetail,
  loadingLabel,
  onRetry,
  children,
}: {
  loading: boolean;
  error: unknown;
  data: T | undefined;
  empty?: (data: T) => boolean;
  emptyTitle?: string;
  emptyDetail?: string;
  loadingLabel?: string;
  onRetry?: () => void;
  children: (data: T) => ReactNode;
}) {
  if (loading) return <LoadingBlock label={loadingLabel} />;
  if (error) return <ErrorState error={error} onRetry={onRetry} />;
  if (data === undefined || data === null || empty?.(data)) {
    return (
      <EmptyState
        title={emptyTitle || "No records available."}
        detail={emptyDetail || "Nothing has been returned from HoneyChain for this view yet."}
      />
    );
  }
  return <>{children(data)}</>;
}

/**
 * Wording for a status summary whose inputs may have failed.
 *
 * A screen that says "nothing needs attention" on the strength of a request
 * that was denied is a false all-clear, so an unreadable input yields
 * "could not be confirmed" rather than a clean bill of health.
 */
export function attentionSummary({
  count,
  errored,
  clean,
  counted,
}: {
  count: number;
  errored: boolean;
  clean: string;
  counted: (n: number) => string;
}): { title: string; tone: "ok" | "warn" | "bad" } {
  if (count > 0) return { title: counted(count), tone: "warn" };
  if (errored) {
    return {
      title: "Status could not be confirmed — HoneyChain did not return the data for this check",
      tone: "bad",
    };
  }
  return { title: clean, tone: "ok" };
}
