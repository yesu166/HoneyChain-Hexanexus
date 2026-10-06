import { createFileRoute } from "@tanstack/react-router";
import { PassportPage } from "@/features/passport/passport-page";

/** Public passport by path: /passport/HC-BATCH-… (shared links). */
export const Route = createFileRoute("/passport/$code")({
  component: PassportPage,
});
