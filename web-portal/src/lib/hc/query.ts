import { useQuery, useMutation, useQueryClient, type QueryKey } from "@tanstack/react-query";
import { useHoneyAuth } from "./auth";
import type { HoneyChainApi } from "./types";

export function useHcQuery<T>(
  key: QueryKey,
  fn: (api: HoneyChainApi) => Promise<T>,
  options?: { enabled?: boolean },
) {
  const { api, mode } = useHoneyAuth();
  const query = useQuery({
    queryKey: [mode, ...key],
    queryFn: () => fn(api),
    enabled: options?.enabled ?? true,
    // The one controlled retry lives in `client.ts`, not here.
    //
    // It has to live there: that is the only layer every HoneyChain call passes
    // through, whether it comes from this hook, a mutation, or a direct
    // `liveApi` call. Retrying here as well would re-enter the whole request,
    // including its own transport retry, turning a single retry into up to
    // three extra attempts — and multiplying that across every card on a
    // dashboard is how a struggling API gets hammered.
    //
    // A 401/403/404 is a real answer and is never retried at either layer.
    retry: false,
  });
  return {
    ...query,
    loading: query.isPending,
  };
}

export function useHcMutation<TInput, TResult>(
  fn: (api: HoneyChainApi, input: TInput) => Promise<TResult>,
  invalidate: QueryKey[] = [],
) {
  const { api, mode } = useHoneyAuth();
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: TInput) => fn(api, input),
    onSuccess: async () => {
      await Promise.all(invalidate.map((key) => client.invalidateQueries({ queryKey: [mode, ...key] })));
    },
  });
}

export function useInvalidate() {
  const { mode } = useHoneyAuth();
  const client = useQueryClient();
  return (keys: QueryKey[]) =>
    Promise.all(keys.map((key) => client.invalidateQueries({ queryKey: [mode, ...key] })));
}
