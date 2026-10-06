import { createFileRoute } from "@tanstack/react-router";
import { BuyerWorkspace } from "@/features/buyer/buyer-workspace";

export const Route = createFileRoute("/_workspace/buyer")({
  component: BuyerWorkspace,
});
