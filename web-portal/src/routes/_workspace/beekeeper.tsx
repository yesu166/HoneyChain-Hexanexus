import { createFileRoute } from "@tanstack/react-router";
import { BeekeeperWorkspace } from "@/features/beekeeper/beekeeper-workspace";

export const Route = createFileRoute("/_workspace/beekeeper")({
  component: BeekeeperWorkspace,
});
