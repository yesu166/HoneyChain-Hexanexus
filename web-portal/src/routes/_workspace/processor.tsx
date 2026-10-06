import { createFileRoute } from "@tanstack/react-router";
import { ProcessorWorkspace } from "@/features/processor/processor-workspace";

export const Route = createFileRoute("/_workspace/processor")({
  component: ProcessorWorkspace,
});
