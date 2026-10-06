import { createFileRoute } from "@tanstack/react-router";
import { PassportPage } from "@/features/passport/passport-page";

/** QR target: /verify/HC-BATCH-… — the public consumer verification URL. */
export const Route = createFileRoute("/verify/$code")({
  component: PassportPage,
});
