import { createFileRoute } from "@tanstack/react-router";
import { PassportPage } from "@/features/passport/passport-page";

export const Route = createFileRoute("/passport")({
  validateSearch: (search: Record<string, unknown>): { code?: string } => {
    if (typeof search.code === "string" && search.code) return { code: search.code };
    return {};
  },
  component: PassportPage,
});
