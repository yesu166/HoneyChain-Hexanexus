import { createFileRoute } from "@tanstack/react-router";
import { LabWorkspace } from "@/features/lab/lab-workspace";

export const Route = createFileRoute("/_workspace/lab")({
  component: LabWorkspace,
});
