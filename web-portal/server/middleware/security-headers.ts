/**
 * Baseline response hardening for the public portal.
 * Keep this policy deliberately compatible with the sign-in popup and the
 * portal's embedded preview; do not add a frame-deny policy here.
 */
export default async function securityHeaders(
  event: { url: URL },
  next: () => unknown | Promise<unknown>,
): Promise<unknown> {
  const result = await next();
  if (!(result instanceof Response)) return result;

  const headers = new Headers(result.headers);
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  headers.set("Permissions-Policy", "camera=(self), microphone=(self), geolocation=()");
  headers.set("X-Permitted-Cross-Domain-Policies", "none");

  // Only advertise HSTS when the request actually arrived over HTTPS.
  if (event.url.protocol === "https:") {
    headers.set("Strict-Transport-Security", "max-age=31536000");
  }

  return new Response(result.body, {
    status: result.status,
    statusText: result.statusText,
    headers,
  });
}
