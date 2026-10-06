import type { InputHTMLAttributes } from "react";
import { cn } from "@/lib/utils";

export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        "flex h-11 w-full rounded-xl border border-black/10 bg-paper px-3 text-sm text-ink outline-none transition placeholder:text-muted focus:border-honey-400 focus:ring-2 focus:ring-honey-100",
        className,
      )}
      {...props}
    />
  );
}
