import { useEffect, useState } from "react";
import { useSearch, useParams } from "@tanstack/react-router";
import { PublicHeader } from "@/components/hc/app-shell";
import { PageHeader } from "@/components/hc/page-header";
import { ProvenancePath, Timeline } from "@/components/hc/timeline";
import { StatusBadge } from "@/components/hc/status-badge";
import { ErrorState, LoadingBlock } from "@/components/hc/query-state";
import { QrScanner } from "@/features/passport/qr";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { demoApi } from "@/lib/hc/demo";
import { useHoneyAuth } from "@/lib/hc/auth";
import { liveApi } from "@/lib/hc/live-api";
import { readLedgerHealth, type LedgerHealth } from "@/lib/hc/blockchain";
import { AnchorStatus } from "@/components/hc/ledger-panel";
import { ApiError, type PassportResponse } from "@/lib/hc/types";
import { chainState, fmtDate, fmtNum, trustLabel } from "@/lib/hc/format";
import { extractPassportSubject } from "@/lib/hc/passport";

export function PassportPage() {
  const { mode, api } = useHoneyAuth();
  const search = useSearch({ strict: false }) as { code?: string };
  const params = useParams({ strict: false }) as { code?: string };
  // The code can arrive via ?code=… (in-app links), /passport/<code> or
  // /verify/<code> (QR target and shared links) — all are the same lookup.
  const initial = search.code || params.code || "";
  const [status, setStatus] = useState<"idle" | "loading" | "ok" | "error">("idle");
  const [passport, setPassport] = useState<PassportResponse | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [source, setSource] = useState<"live" | "demo">(mode);
  const [pendingCode, setPendingCode] = useState("");
  // Which ledger the *authoritative* API is actually using. This is public on
  // HoneyChain, so the consumer-facing page can tell the truth about whether an
  // anchor means anything.
  //
  // Three states, because the middle one used to be silently merged into the
  // worst case: "not yet answered", "the request failed", and "the API said it
  // is not distributed" are different facts. The old code sent all three to
  // `null` and then tested `!ledger?.distributed`, so a failed probe printed
  // "HoneyChain is not currently backed by a distributed ledger" — asserting
  // something about the deployment that the API had never said.
  const [ledger, setLedger] = useState<LedgerHealth | null>(null);
  const [ledgerUnreadable, setLedgerUnreadable] = useState(false);

  useEffect(() => {
    let cancelled = false;
    void liveApi
      .blockchainHealth()
      .then((payload) => {
        if (!cancelled) {
          setLedger(readLedgerHealth(payload));
          setLedgerUnreadable(false);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setLedger(null);
          setLedgerUnreadable(true);
        }
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const lookup = async (raw: string, forceDemo = false) => {
    // The canonical parser is the one covered by `client.test.ts`. The local
    // version this replaced took the last path segment of *any* string, so a
    // pasted sentence or a `honeychain://jar/<code>` payload from the Flutter app
    // resolved to the wrong identifier instead of being rejected. The parser
    // only accepts a real code, a HoneyChain URL, or a Flutter payload.
    const subject = extractPassportSubject(raw);
    const code = subject?.code || "";
    if (!code) {
      setStatus("error");
      setError(new ApiError(400, "That Honey Yatra QR did not contain a HoneyChain passport or batch code."));
      setPassport(null);
      return;
    }
    if (typeof window !== "undefined") {
      const url = new URL(window.location.href);
      url.searchParams.set("code", code);
      window.history.replaceState(null, "", url.toString());
    }
    setPendingCode(code);
    setStatus("loading");
    try {
      const useDemo = forceDemo || mode === "demo";
      const data = useDemo ? await demoApi.passport(code) : await api.passport(code);
      setPassport(data);
      setSource(useDemo ? "demo" : "live");
      setStatus("ok");
    } catch (err) {
      setPassport(null);
      setError(err);
      setStatus("error");
    }
  };

  useEffect(() => {
    if (initial) void lookup(initial);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const chain = chainState(passport?.anchor?.chain_status);
  const lab = passport?.verification?.result;
  // "Lab passed" and "anchored to a blockchain" are two different claims and
  // must not be collapsed into one word. The header states only the claim the
  // laboratory result actually supports.
  const labPassed = lab === "PASS" || (passport?.trust_tier || "").includes("lab");
  const verifiedProduct = labPassed;
  const networkFail = error instanceof ApiError && error.status === 0;

  return (
    <div className="min-h-screen">
      <PublicHeader />
      <main className="mx-auto max-w-3xl px-4 pb-16 md:px-8">
        <PageHeader
          eyebrow="Honey Yatra QR · Honey Passport"
          title="Verify a HoneyChain product"
          description="Scan a QR or enter a batch code. Decoding a QR is not verification. The passport API decides what is known."
        />
        {source === "demo" && status === "ok" ? (
          <p className="mb-4 rounded-xl bg-honey-50 px-3 py-2 text-sm text-honey-600">
            Showing labeled demo data — not a live HoneyChain passport.
          </p>
        ) : null}
        <QrScanner onCode={(code) => void lookup(code)} />
        {status === "loading" ? <LoadingBlock label="Resolving passport…" /> : null}
        {status === "error" ? (
          <div className="space-y-3">
            <ErrorState error={error} onRetry={() => pendingCode && void lookup(pendingCode)} />
            {networkFail ? (
              <Button type="button" variant="secondary" onClick={() => void lookup(pendingCode || initial, true)}>
                Look up this code in labeled demo data
              </Button>
            ) : null}
          </div>
        ) : null}
        {passport ? (
          <div className="mt-6 space-y-4">
            <Card className="overflow-hidden p-0">
              <div className={`px-5 py-4 ${verifiedProduct ? "bg-grove-800 text-cream" : "bg-honey-50 text-ink"}`}>
                <p className="text-[11px] font-bold tracking-[0.16em] uppercase">
                  {/* Says what verified, because "verified" alone on a consumer
                      page invites a blockchain guarantee the portal cannot make. */}
                  {verifiedProduct ? "Laboratory-tested product" : "HoneyChain product record"}
                </p>
                <h2 className="mt-2 font-display text-3xl">{passport.honey_type || "Honey"}</h2>
                <p className="mt-1 text-sm opacity-80">{passport.origin || "Origin not available"}</p>
              </div>
              <div className="space-y-4 p-5">
                <dl className="grid gap-3 text-sm sm:grid-cols-2">
                  <div>
                    <dt className="text-muted">Batch</dt>
                    <dd className="font-semibold">{passport.batch_code}</dd>
                  </div>
                  <div>
                    <dt className="text-muted">Quantity</dt>
                    <dd className="font-semibold">{fmtNum(passport.quantity_kg, " kg")}</dd>
                  </div>
                  <div>
                    <dt className="text-muted">Laboratory</dt>
                    <dd>
                      {lab ? (
                        <StatusBadge label={lab === "PASS" ? "Passed" : lab === "FAIL" ? "Failed" : lab} />
                      ) : (
                        "Pending verification"
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-muted">Ledger</dt>
                    <dd>
                      <Badge tone={chain.tone}>{chain.label}</Badge>
                    </dd>
                  </div>
                </dl>
                <StatusBadge label={trustLabel(passport.trust_tier)} />
                <ProvenancePath current={lab === "PASS" ? "Lab" : "Collection"} />
              </div>
            </Card>
            <Card>
              <h3 className="font-display text-xl">The journey</h3>
              <div className="mt-4">
                <Timeline
                  items={(passport.events || []).map((e) => ({
                    title: e.type.replaceAll("_", " "),
                    at: e.at,
                    actor: e.actor,
                    detail: e.detail,
                  }))}
                />
              </div>
            </Card>
            <Card>
              <h3 className="font-display text-xl">Verification</h3>
              <p className="mt-2 text-sm">
                Laboratory: {passport.verification?.result || "Not available"}
                {passport.verification?.tested_at ? ` · ${fmtDate(passport.verification.tested_at)}` : ""}
              </p>

              {/* The anchor is described together with the ledger that holds it.
                  Printing a transaction id alone, with no statement about the
                  adapter, is how a development-ledger hash ends up looking like
                  a blockchain receipt. */}
              <div className="mt-3">
                <p className="text-sm">Ledger anchor</p>
                <div className="mt-1">
                  {source === "demo" ? (
                    <Badge tone="demo">Demo record — not a live HoneyChain anchor</Badge>
                  ) : (
                    <AnchorStatus anchor={passport.anchor} health={ledger} healthUnreadable={ledgerUnreadable} />
                  )}
                </div>
                {source !== "demo" && ledgerUnreadable ? (
                  /* The probe failed, so HoneyChain's ledger is unknown here.
                     Saying "not backed by a distributed ledger" would be a
                     confident statement the API never made. */
                  <p className="mt-2 text-xs text-muted">
                    HoneyChain&apos;s blockchain status could not be read, so whether this deployment
                    uses a distributed ledger is unknown. No blockchain guarantee is offered for
                    this product.
                  </p>
                ) : source !== "demo" && !ledger?.distributed ? (
                  <p className="mt-2 text-xs text-muted">
                    HoneyChain is not currently backed by a distributed ledger, so no blockchain
                    guarantee is offered for this product.
                  </p>
                ) : null}
              </div>

              <p className="mt-3 text-sm text-muted">{passport.caveat}</p>
            </Card>
          </div>
        ) : null}
      </main>
    </div>
  );
}
