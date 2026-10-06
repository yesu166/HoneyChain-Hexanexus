import { cva, type VariantProps } from "class-variance-authority";
import type { HTMLAttributes } from "react";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center rounded-full px-2.5 py-1 text-[11px] font-semibold tracking-wide",
  {
    variants: {
      tone: {
        neutral: "bg-black/5 text-ink",
        ok: "bg-grove-50 text-grove-800",
        warn: "bg-honey-100 text-honey-600",
        bad: "bg-red-100 text-red-800",
        info: "bg-grove-100 text-grove-800",
        demo: "bg-honey-500 text-ink",
        live: "bg-grove-700 text-cream",
      },
    },
    defaultVariants: { tone: "neutral" },
  },
);

export function Badge({
  className,
  tone,
  ...props
}: HTMLAttributes<HTMLSpanElement> & VariantProps<typeof badgeVariants>) {
  return <span className={cn(badgeVariants({ tone }), className)} {...props} />;
}
