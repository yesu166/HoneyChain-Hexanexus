/**
 * Real, scannable Honey Yatra QR generation for the Honey Passport.
 *
 * The QR encodes a stable verification URL (see `passportVerifyUrl`) — never the
 * passport JSON — so a phone camera opens the HoneyChain portal, which then asks HoneyChain.
 *
 * `qrcode` is imported lazily and only in the browser: its platform entry point
 * does not exist on the server, and the passport page only renders a QR after
 * the identifier is known client-side.
 */
export interface QrRenderOptions {
  size?: number;
  margin?: number;
  dark?: string;
  light?: string;
}

const DEFAULTS: Required<QrRenderOptions> = {
  size: 320,
  margin: 3,
  dark: "#122018",
  light: "#fffcf6",
};

interface QrLib {
  toDataURL: (
    text: string,
    options: {
      width: number;
      margin: number;
      color: { dark: string; light: string };
      errorCorrectionLevel: "L" | "M" | "Q" | "H";
    },
  ) => Promise<string>;
}

let cached: QrLib | null = null;

async function loadQr(): Promise<QrLib> {
  if (typeof window === "undefined") {
    throw new Error("QR rendering is only available in the browser.");
  }
  if (cached) return cached;
  const mod = (await import("qrcode")) as unknown as QrLib | { default: QrLib };
  cached = "toDataURL" in mod ? mod : (mod as { default: QrLib }).default;
  if (!cached?.toDataURL) {
    throw new Error("The QR encoder could not be loaded.");
  }
  return cached;
}

/**
 * Render [payload] to a PNG data URL. Error correction level M (15%) survives
 * a printed label's smudges and a phone camera's imperfect angle.
 */
export async function qrDataUrl(
  payload: string,
  options: QrRenderOptions = {},
): Promise<string> {
  const opts = { ...DEFAULTS, ...options };
  const lib = await loadQr();
  return lib.toDataURL(payload, {
    width: opts.size,
    margin: opts.margin,
    color: { dark: opts.dark, light: opts.light },
    errorCorrectionLevel: "M",
  });
}

/** Trigger a PNG download of the QR in the browser. */
export function downloadDataUrl(dataUrl: string, filename: string): void {
  if (typeof document === "undefined") return;
  const link = document.createElement("a");
  link.href = dataUrl;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
}

/** Open the browser print dialog for the current document (printable passport). */
export function printDocument(): void {
  if (typeof window === "undefined") return;
  window.print();
}

export function safeFilename(value: string): string {
  return value.replace(/[^A-Za-z0-9._-]+/g, "-").slice(0, 80) || "honey-yatra-qr";
}
