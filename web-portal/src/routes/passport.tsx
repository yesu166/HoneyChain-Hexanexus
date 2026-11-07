import { createFileRoute } from "@tanstack/react-router";
import { PassportPage } from "@/features/passport/passport-page";

export const Route = createFileRoute("/passport")({
  validateSearch: (
    search: Record<string, unknown>,
  ): { code?: string; source?: "demo" } => {
    const code = typeof search.code === "string" && search.code ? search.code : undefined;
    const source = search.source === "demo" ? "demo" : undefined;
    return { ...(code ? { code } : {}), ...(source ? { source } : {}) };
  },
  component: PassportPage,
});
