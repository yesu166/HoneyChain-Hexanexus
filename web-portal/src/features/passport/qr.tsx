import { useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

export function QrScanner({ onCode }: { onCode: (value: string) => void }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [error, setError] = useState<string | null>(null);
  const [manual, setManual] = useState("");
  const [scanning, setScanning] = useState(false);

  useEffect(() => {
    if (!scanning) return;
    let stream: MediaStream | null = null;
    let timer: number | undefined;
    const video = videoRef.current;
    const run = async () => {
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "environment" },
        });
        if (!video) return;
        video.srcObject = stream;
        await video.play();
        const Detector = (
          window as Window & {
            BarcodeDetector?: new (opts: { formats: string[] }) => {
              detect: (source: HTMLVideoElement) => Promise<{ rawValue: string }[]>;
            };
          }
        ).BarcodeDetector;
        if (!Detector) {
          setError("Camera decoding is not available in this browser. Enter the passport code instead.");
          return;
        }
        const detector = new Detector({ formats: ["qr_code"] });
        const tick = async () => {
          if (!video || video.readyState < 2) {
            timer = window.setTimeout(tick, 300);
            return;
          }
          const codes = await detector.detect(video);
          if (codes[0]?.rawValue) {
            onCode(codes[0].rawValue.trim());
            setScanning(false);
            return;
          }
          timer = window.setTimeout(tick, 250);
        };
        void tick();
      } catch {
        setError("Unable to open the camera. Enter the code instead.");
        setScanning(false);
      }
    };
    void run();
    return () => {
      if (timer) window.clearTimeout(timer);
      stream?.getTracks().forEach((t) => t.stop());
    };
  }, [scanning, onCode]);

  return (
    <div className="space-y-3">
      {scanning ? (
        <video
          ref={videoRef}
          className="aspect-video w-full rounded-2xl bg-grove-900 object-cover"
          muted
          playsInline
        />
      ) : null}
      <div className="flex flex-wrap gap-2">
        <Button type="button" onClick={() => setScanning(true)}>
          Scan QR
        </Button>
        {scanning ? (
          <Button variant="secondary" type="button" onClick={() => setScanning(false)}>
            Stop camera
          </Button>
        ) : null}
      </div>
      <form
        className="flex flex-col gap-2 sm:flex-row"
        onSubmit={(e) => {
          e.preventDefault();
          if (manual.trim()) onCode(manual.trim());
        }}
      >
        <Input
          value={manual}
          onChange={(e) => setManual(e.target.value)}
          placeholder="Enter batch or passport code"
        />
        <Button type="submit">Look up</Button>
      </form>
      {error ? <p className="text-sm text-red-800">{error}</p> : null}
    </div>
  );
}
