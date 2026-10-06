import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { Toaster } from "sonner";
import { HoneyAuthProvider } from "@/lib/hc/auth";

export function AuthProvider({ children }: { children: ReactNode }) {
  const [client] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 30_000,
            refetchOnWindowFocus: false,
          },
        },
      }),
  );
  return (
    <QueryClientProvider client={client}>
      <HoneyAuthProvider>
        {children}
        <Toaster richColors position="top-center" />
      </HoneyAuthProvider>
    </QueryClientProvider>
  );
}
