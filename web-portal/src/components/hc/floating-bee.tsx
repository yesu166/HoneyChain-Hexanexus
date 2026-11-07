import { useEffect, useRef } from "react";

export function FloatingBee() {
  const beeRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const bee = beeRef.current;
    if (!bee || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    let frame = 0;
    let roamTimer: number | undefined;

    const onPointerMove = (event: PointerEvent) => {
      if (event.pointerType === "touch") return;
      const x = event.clientX;
      const y = event.clientY;
      if (frame) return;

      frame = window.requestAnimationFrame(() => {
        frame = 0;
        const size = bee.offsetWidth || 42;
        const left = Math.max(8, Math.min(window.innerWidth - size - 8, x + 18));
        const top = Math.max(8, Math.min(window.innerHeight - size - 8, y + 18));
        bee.style.left = `${left}px`;
        bee.style.top = `${top}px`;
        bee.classList.remove("hc-floating-bee--roaming");
      });
    };

    const onScroll = () => {
      bee.classList.add("hc-floating-bee--roaming");
      if (roamTimer !== undefined) window.clearTimeout(roamTimer);
      roamTimer = window.setTimeout(() => {
        bee.classList.remove("hc-floating-bee--roaming");
        roamTimer = undefined;
      }, 1200);
    };

    window.addEventListener("pointermove", onPointerMove, { passive: true });
    window.addEventListener("scroll", onScroll, { passive: true });

    return () => {
      window.removeEventListener("pointermove", onPointerMove);
      window.removeEventListener("scroll", onScroll);
      if (frame) window.cancelAnimationFrame(frame);
      if (roamTimer !== undefined) window.clearTimeout(roamTimer);
    };
  }, []);

  return (
    <div ref={beeRef} className="hc-floating-bee" aria-hidden="true">
      <span className="hc-floating-bee__sprite">
        <svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg">
          <ellipse cx="25" cy="17" rx="10" ry="6" fill="#F7E9C3" stroke="#173B27" strokeWidth="2" transform="rotate(-24 25 17)" />
          <ellipse cx="39" cy="17" rx="10" ry="6" fill="#F7E9C3" stroke="#173B27" strokeWidth="2" transform="rotate(24 39 17)" />
          <ellipse cx="32" cy="35" rx="15" ry="18" fill="#F3B735" stroke="#173B27" strokeWidth="2.5" />
          <path d="M24 22C27 27 27 43 24 48M40 22C37 27 37 43 40 48" stroke="#173B27" strokeWidth="5" strokeLinecap="round" />
          <circle cx="27" cy="31" r="2" fill="#173B27" />
          <circle cx="37" cy="31" r="2" fill="#173B27" />
          <path d="M28 40C30 42 34 42 36 40" stroke="#173B27" strokeWidth="1.8" strokeLinecap="round" />
          <path d="M24 18L20 12M40 18L44 12" stroke="#173B27" strokeWidth="1.8" strokeLinecap="round" />
        </svg>
      </span>
    </div>
  );
}
