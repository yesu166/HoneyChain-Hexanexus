import { createFileRoute } from "@tanstack/react-router";
import { AlertsPage } from "@/features/alerts/alerts-page";

export const Route = createFileRoute("/_workspace/alerts")({
  component: AlertsPage,
});
