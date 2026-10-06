/**
 * Public build-time configuration, read defensively.
 *
 * `import.meta.env` only exists inside a Vite build. Reading it directly
 * throws during SSR route evaluation and under `node --test`, which is how the
 * regression tests in this directory import the API client. Going through a
 * single guarded accessor keeps one definition of "what is configured" and
 * lets the same modules load in three places: the browser bundle, the server
 * render, and the test runner.
 */
type PublicEnv = Record<string, string | boolean | undefined>;

function readEnv(): PublicEnv {
  try {
    const meta = import.meta as unknown as { env?: PublicEnv };
    return meta.env ?? {};
  } catch {
    return {};
  }
}

/** A `VITE_`-prefixed string variable, or undefined when unset. */
export function publicEnv(name: string): string | undefined {
  const value = readEnv()[name];
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed ? trimmed : undefined;
}

export function isProductionBuild(): boolean {
  if (readEnv().PROD === true) return true;
  // rolldown-vite ships a bare `import.meta.env` lookup that is left
  // unevaluated in the deployed bundle, so `PROD` can be undefined in a real
  // production build even though the code is correct. That was the production
  // failure: the API-origin fallback was gated on this check, the gate never
  // opened, and every request went to the portal's own origin and 404'd.
  // The served origin is the fallback signal — a dev server is only ever
  // reached from localhost, and any deployed origin is a production build.
  if (typeof window === "undefined") return false;
  const { hostname } = window.location;
  return hostname !== "localhost" && hostname !== "127.0.0.1" && hostname !== "::1";
}
