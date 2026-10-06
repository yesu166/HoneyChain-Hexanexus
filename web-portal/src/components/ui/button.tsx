import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import type { ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-xl text-sm font-semibold transition-[background-color,box-shadow,transform] duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-honey-400 disabled:pointer-events-none disabled:opacity-50 min-h-11 px-4",
  {
    variants: {
      variant: {
        primary: "bg-grove-700 text-cream hover:bg-grove-800",
        secondary:
          "border border-black/10 bg-paper text-grove-800 hover:bg-honey-50 shadow-[var(--shadow-card)]",
        ghost: "text-grove-800 hover:bg-black/5",
        danger: "bg-red-800 text-white hover:bg-red-900",
        honey: "bg-honey-500 text-ink hover:bg-honey-600",
        link: "h-auto min-h-0 px-0 text-grove-700 underline-offset-4 hover:underline",
      },
      size: {
        default: "min-h-11 px-4",
        sm: "min-h-10 px-3 text-xs",
        lg: "min-h-12 px-5",
        icon: "size-11 p-0",
      },
    },
    defaultVariants: { variant: "primary", size: "default" },
  },
);

export function Button({
  className,
  variant,
  size,
  asChild = false,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> &
  VariantProps<typeof buttonVariants> & { asChild?: boolean }) {
  const Comp = asChild ? Slot : "button";
  return <Comp className={cn(buttonVariants({ variant, size }), className)} {...props} />;
}

export { buttonVariants };
