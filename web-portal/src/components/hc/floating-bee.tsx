import { useEffect, useRef } from "react";

export function FloatingBee() {
  const beeRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const bee = beeRef.current;
    if (!bee || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    let frame = 0;

    const followPointer = (event: PointerEvent) => {
      if (event.pointerType === "touch") return;

      const pointerX = event.clientX;
      const pointerY = event.clientY;
      if (frame) return;

      frame = window.requestAnimationFrame(() => {
        frame = 0;
        const size = bee.offsetWidth || 56;
        const offset = 18;
        const left = Math.max(8, Math.min(window.innerWidth - size - 8, pointerX + offset));
        const top = Math.max(8, Math.min(window.innerHeight - size - 8, pointerY + offset));

        bee.style.left = `${left}px`;
        bee.style.top = `${top}px`;
        bee.style.right = "auto";
        bee.style.bottom = "auto";
        bee.classList.add("hc-floating-bee--following");
      });
    };

    window.addEventListener("pointermove", followPointer, { passive: true });

    return () => {
      window.removeEventListener("pointermove", followPointer);
      if (frame) window.cancelAnimationFrame(frame);
    };
  }, []);

  return (
    <div ref={beeRef} className="hc-floating-bee" aria-hidden="true">
      <span className="hc-floating-bee__sprite">🐝</span>
    </div>
  );
}
