import { createFileRoute } from "@tanstack/react-router";
import { ClusterDetail } from "@/features/kvic/cluster-detail";

export const Route = createFileRoute("/_workspace/kvic/$orgId")({
  component: ClusterDetail,
});
