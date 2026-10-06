import { createFileRoute } from "@tanstack/react-router";
import { AdminWorkspace } from "@/features/admin/admin-workspace";

export const Route = createFileRoute("/_workspace/admin")({
  component: () => <AdminWorkspace panel="business" />,
});
