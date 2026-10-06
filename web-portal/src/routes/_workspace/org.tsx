import { createFileRoute } from "@tanstack/react-router";
import { OrgWorkspace } from "@/features/org/org-workspace";

export const Route = createFileRoute("/_workspace/org")({
  component: OrgWorkspace,
});
