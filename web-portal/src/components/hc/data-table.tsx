import type { ReactNode } from "react";
import { EmptyState, ErrorState, LoadingBlock } from "./query-state";

/**
 * The shape every list on this portal needs: loading, then error, and only then
 * "nothing to show".
 *
 * The order is the whole point. A hand-rolled gate that tests `rows.length`
 * before `query.error` turns a 403 into an empty table, which reads as "this
 * platform has no organizations" when the truth is that the operator was not
 * allowed to look. Every table comes through here so that mistake cannot be
 * made one screen at a time.
 */
export function QueryTable<T>({
  query,
  columns,
  rows,
  empty,
  loadingLabel,
}: {
  query: {
    isPending: boolean;
    error: unknown;
    refetch: () => unknown;
    data?: T;
  };
  columns: { key: string; label: string }[];
  rows: (data: T) => Record<string, ReactNode>[];
  empty: string;
  loadingLabel?: string;
}) {
  if (query.isPending) return <LoadingBlock label={loadingLabel} />;
  if (query.error) return <ErrorState error={query.error} onRetry={() => void query.refetch()} />;
  return <DataTable columns={columns} rows={rows((query.data ?? []) as T)} empty={empty} />;
}

export function DataTable({
  columns,
  rows,
  empty = "No records available.",
}: {
  columns: { key: string; label: string }[];
  rows: Record<string, ReactNode>[];
  empty?: string;
}) {
  if (!rows.length) return <EmptyState title={empty} />;
  return (
    <>
      <div className="hidden overflow-x-auto rounded-2xl bg-paper shadow-[var(--shadow-card)] md:block">
        <table className="min-w-full text-left text-sm">
          <thead className="bg-grove-50 text-[10px] tracking-[0.12em] text-grove-800 uppercase">
            <tr>
              {columns.map((col) => (
                <th key={col.key} className="px-4 py-3 font-bold">
                  {col.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, i) => (
              <tr key={i} className="border-t border-black/5">
                {columns.map((col) => (
                  <td key={col.key} className="px-4 py-3 align-top">
                    {row[col.key] ?? "Not available"}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="grid gap-3 md:hidden">
        {rows.map((row, i) => (
          <article key={i} className="rounded-2xl bg-paper p-4 shadow-[var(--shadow-card)]">
            {columns.map((col) => (
              <div key={col.key} className="flex items-start justify-between gap-3 py-1.5 text-sm">
                <span className="text-muted">{col.label}</span>
                <span className="max-w-[60%] text-right font-medium text-ink">
                  {row[col.key] ?? "Not available"}
                </span>
              </div>
            ))}
          </article>
        ))}
      </div>
    </>
  );
}
