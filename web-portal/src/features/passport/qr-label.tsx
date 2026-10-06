import { useEffect, useState } from "react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { downloadDataUrl, printDocument, qrDataUrl, safeFilename } from "@/lib/hc/qr";
import { passportVerifyUrl } from "@/lib/hc/passport";

/**
 * The printable Honey Passport label for one REAL backend batch.
 *
 * The label is only ever rendered from a `batch_code` the API actually returned.
 * There is no fallback identifier: `qr.ts` is imported for its encoder, and
 * `passportVerifyUrl` builds the destination, so the pixels in the QR and the
 * link in the print sheet are the same code.
 *
 * The QR encodes the stable *verification URL*, never the passport JSON, so a
 * phone camera opens this portal and the portal asks HoneyChain. That keeps the
 * label correct even after the record is updated or revoked — the printed code
 * stays the same, the answer changes.
 *
 * Rendering is client-only. `qrcode`'s platform entry point does not exist on
 * the server, so the encoder is invoked from an effect and the panel shows an
 * honest "preparing" state until the image is ready.
 */
export function PassportQrLabel({
  batchCode,
  honeyType,
  origin,
  className,
}: {
  /** The authoritative `batch_code` from the backend. */
  batchCode: string;
  honeyType?: string | null;
  origin?: string | null;
  className?: string;
}) {
  const verifyUrl = passportVerifyUrl(batchCode);
  const [dataUrl, setDataUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setDataUrl(null);
    setError(null);
    void qrDataUrl(verifyUrl)
      .then((url) => {
        if (!cancelled) setDataUrl(url);
      })
      .catch(() => {
        if (!cancelled) {
          setError("The QR image could not be generated. The verification link below still works.");
        }
      });
    return () => {
      cancelled = true;
    };
  }, [verifyUrl]);

  return (
    <Card className={className}>
      <div className="flex flex-wrap items-start gap-5">
        <div className="shrink-0">
          {error ? (
            <div
              className="flex h-40 w-40 items-center justify-center rounded-xl border border-honey-200 bg-honey-50 p-3 text-center text-xs text-honey-600"
              role="img"
              aria-label={`QR code for batch ${batchCode}`}
            >
              QR unavailable
            </div>
          ) : dataUrl ? (
            <img
              src={dataUrl}
              alt={`QR code linking to the public Honey Passport for batch ${batchCode}`}
              className="h-40 w-40 rounded-xl border border-honey-200 bg-white"
              width={160}
              height={160}
            />
          ) : (
            <div
              className="h-40 w-40 animate-pulse rounded-xl bg-honey-50"
              aria-label="Preparing QR code"
            />
          )}
        </div>
        <div className="min-w-[15rem] flex-1">
          <h2 className="font-display text-xl">Honey Passport label</h2>
          <p className="mt-1 text-sm text-muted">
            Scanning this code opens the public Honey Passport for this batch. It is a lookup, not a
            guarantee: the portal asks HoneyChain and shows exactly what is on record.
          </p>
          <dl className="mt-3 space-y-1 text-sm">
            <div className="flex gap-2">
              <dt className="text-muted">Batch</dt>
              <dd className="font-semibold">{batchCode}</dd>
            </div>
            {honeyType ? (
              <div className="flex gap-2">
                <dt className="text-muted">Product</dt>
                <dd>{honeyType}</dd>
              </div>
            ) : null}
            {origin ? (
              <div className="flex gap-2">
                <dt className="text-muted">Origin</dt>
                <dd>{origin}</dd>
              </div>
            ) : null}
            <div className="flex gap-2">
              <dt className="shrink-0 text-muted">Link</dt>
              <dd className="min-w-0 break-all">
                <a className="text-grove-600 underline" href={verifyUrl}>
                  {verifyUrl}
                </a>
              </dd>
            </div>
          </dl>
          <div className="mt-4 flex flex-wrap gap-2">
            <Button
              type="button"
              variant="secondary"
              disabled={!dataUrl}
              onClick={() => dataUrl && downloadDataUrl(dataUrl, `${safeFilename(batchCode)}-passport-qr.png`)}
            >
              Download QR
            </Button>
            <Button type="button" variant="link" onClick={printDocument}>
              Print label
            </Button>
          </div>
        </div>
      </div>
    </Card>
  );
}
