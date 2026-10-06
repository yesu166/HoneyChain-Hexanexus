import { createFileRoute } from "@tanstack/react-router";
import { BatchDetailPage } from "@/features/batch/batch-detail";

export const Route = createFileRoute("/_workspace/batches/$batchId")({
  component: BatchDetailPage,
});
