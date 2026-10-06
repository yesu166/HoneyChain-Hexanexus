import { createFileRoute } from "@tanstack/react-router";
import { AskMyBeePage } from "@/features/ask/ask-my-bee";

export const Route = createFileRoute("/_workspace/ask-my-bee")({
  component: AskMyBeePage,
});
