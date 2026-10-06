import { createFileRoute } from "@tanstack/react-router";
import { KvicOverview } from "@/features/kvic/kvic-overview";

export const Route = createFileRoute("/_workspace/kvic")({
  component: KvicOverview,
});
