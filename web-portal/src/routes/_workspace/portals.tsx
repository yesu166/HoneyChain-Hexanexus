import { createFileRoute } from "@tanstack/react-router";
import { PortalSelector } from "@/features/portals/portal-selector";

export const Route = createFileRoute("/_workspace/portals")({
  component: PortalSelector,
});
