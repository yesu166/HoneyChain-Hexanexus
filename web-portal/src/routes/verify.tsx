import { createFileRoute } from "@tanstack/react-router";
import { PassportPage } from "@/features/passport/passport-page";

/** Public verification lookup: /verify (no code) shows the lookup form. */
export const Route = createFileRoute("/verify")({
  component: PassportPage,
});
