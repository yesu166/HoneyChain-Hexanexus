import { useEffect, useRef } from "react";

export function FloatingBee() {
  const beeRef = useRef<HTMLDivElement>(null);
  const pollenRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const bee = beeRef.current;
    const pollen = pollenRef.current;
    const finePointer = window.matchMedia("(hover: hover) and (pointer: fine)").matches;
    if (!bee || !pollen || !finePointer) return;

    const root = document.documentElement;
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    root.classList.add("hc-pollen-cursor-active");

    let frame = 0;
    let lastTimestamp = 0;
    let currentX = 0;
    let currentY = 0;
    let targetX = 0;
    let targetY = 0;
    let velocityX = 0;
    let velocityY = 0;
    let initialized = false;

    const animateChase = (timestamp: number) => {
      frame = 0;
      const dt = lastTimestamp
        ? Math.min((timestamp - lastTimestamp) / 1000, 0.04)
        : 1 / 60;
      lastTimestamp = timestamp;

      // A lightly under-damped spring gives the bee a visible chase and a
      // little overshoot, instead of snapping directly onto the pollen.
      const stiffness = 34;
      const damping = 8;

      velocityX += ((targetX - currentX) * stiffness - velocityX * damping) * dt;
      velocityY += ((targetY - currentY) * stiffness - velocityY * damping) * dt;
      currentX += velocityX * dt;
      currentY += velocityY * dt;

      bee.style.left = `${currentX}px`;
      bee.style.top = `${currentY}px`;
      bee.style.right = "auto";
      bee.style.bottom = "auto";

      const bank = Math.max(-12, Math.min(12, -velocityX * 0.035));
      bee.style.setProperty("--hc-bee-bank", `${bank.toFixed(2)}deg`);

      const settled =
        Math.abs(targetX - currentX) < 0.45 &&
        Math.abs(targetY - currentY) < 0.45 &&
        Math.abs(velocityX) < 2 &&
        Math.abs(velocityY) < 2;

      if (settled) {
        currentX = targetX;
        currentY = targetY;
        velocityX = 0;
        velocityY = 0;
        bee.style.left = `${currentX}px`;
        bee.style.top = `${currentY}px`;
        bee.style.setProperty("--hc-bee-bank", "0deg");
        lastTimestamp = 0;
        return;
      }

      frame = window.requestAnimationFrame(animateChase);
    };

    const followPointer = (event: PointerEvent) => {
      if (event.pointerType === "touch") return;

      // The pollen is the cursor itself: keep it pinned to the pointer while
      // the bee follows behind with spring physics.
      pollen.style.left = `${event.clientX}px`;
      pollen.style.top = `${event.clientY}px`;
      pollen.classList.add("hc-pollen-pointer--visible");

      if (reduceMotion) return;

      const width = bee.offsetWidth || 82;
      const height = bee.offsetHeight || 66;
      targetX = Math.max(6, Math.min(window.innerWidth - width - 6, event.clientX + 22));
      targetY = Math.max(6, Math.min(window.innerHeight - height - 6, event.clientY + 14));

      if (!initialized) {
        const rect = bee.getBoundingClientRect();
        currentX = rect.left;
        currentY = rect.top;
        initialized = true;
      }

      if (!frame) {
        lastTimestamp = 0;
        frame = window.requestAnimationFrame(animateChase);
      }
    };

    const hidePollen = () => pollen.classList.remove("hc-pollen-pointer--visible");

    window.addEventListener("pointermove", followPointer, { passive: true });
    window.addEventListener("pointerleave", hidePollen);

    return () => {
      window.removeEventListener("pointermove", followPointer);
      window.removeEventListener("pointerleave", hidePollen);
      if (frame) window.cancelAnimationFrame(frame);
      root.classList.remove("hc-pollen-cursor-active");
      pollen.classList.remove("hc-pollen-pointer--visible");
    };
  }, []);

  return (
    <>
      <div ref={pollenRef} className="hc-pollen-pointer" aria-hidden="true">
        <svg viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">
          <g className="hc-pollen-bloom">
            <g fill="#F4C542" stroke="#B77916" strokeWidth="0.8">
              <ellipse cx="20" cy="9" rx="3.7" ry="6" />
              <ellipse cx="20" cy="9" rx="3.7" ry="6" transform="rotate(60 20 20)" />
              <ellipse cx="20" cy="9" rx="3.7" ry="6" transform="rotate(120 20 20)" />
              <ellipse cx="20" cy="9" rx="3.7" ry="6" transform="rotate(180 20 20)" />
              <ellipse cx="20" cy="9" rx="3.7" ry="6" transform="rotate(240 20 20)" />
              <ellipse cx="20" cy="9" rx="3.7" ry="6" transform="rotate(300 20 20)" />
            </g>
            <circle cx="20" cy="20" r="5.4" fill="#FFF0A8" stroke="#C68B1D" strokeWidth="1.1" />
            <circle cx="18.4" cy="18.2" r="1.5" fill="#FFFDF1" />
            <circle cx="20" cy="20" r="2.1" fill="#E8A827" />
            <circle cx="31.5" cy="8.5" r="1.6" fill="#F7D875" />
            <circle cx="8" cy="29" r="1.3" fill="#EAB83F" />
            <path d="M29 27L30.3 29.8L33 31L30.3 32.2L29 35L27.7 32.2L25 31L27.7 29.8L29 27Z" fill="#FFF0A8" />
          </g>
        </svg>
      </div>

      <div ref={beeRef} className="hc-floating-bee" aria-hidden="true">
        <svg
          className="hc-bee-mascot"
          viewBox="0 0 104 82"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
        >
          <g className="hc-bee-wings">
            <path
              className="hc-bee-wing hc-bee-wing--left"
              d="M43 31C26 24 23 8 34 5C47 2 54 17 52 32C49 34 46 33 43 31Z"
              fill="#FFF4D8"
              stroke="#8B6A36"
              strokeWidth="1.8"
            />
            <path
              className="hc-bee-wing hc-bee-wing--right"
              d="M55 30C61 13 78 8 83 18C88 29 72 39 56 36C54 34 54 32 55 30Z"
              fill="#FFF4D8"
              stroke="#8B6A36"
              strokeWidth="1.8"
            />
            <path d="M34 11C41 15 46 22 48 30M80 20C72 23 65 28 59 34" stroke="#D9BD82" strokeWidth="1" strokeLinecap="round" opacity=".8" />
          </g>

          <g className="hc-bee-body">
            <path d="M23 46L11 39L14 53L26 52" fill="#4C2C19" stroke="#342014" strokeWidth="1.8" strokeLinejoin="round" />
            <ellipse cx="43" cy="46" rx="25" ry="18" fill="#F5B92F" stroke="#4C2C19" strokeWidth="2.2" />
            <path d="M31 30C38 38 38 54 31 62" stroke="#4C2C19" strokeWidth="7" strokeLinecap="round" />
            <path d="M48 29C55 38 55 54 48 63" stroke="#4C2C19" strokeWidth="7" strokeLinecap="round" />
            <path d="M63 37C70 31 80 34 82 43C84 52 76 60 66 57C61 55 59 43 63 37Z" fill="#F8C94C" stroke="#4C2C19" strokeWidth="2" />
            <path d="M68 35C66 29 67 25 71 22M78 36C81 29 85 28 88 29" stroke="#4C2C19" strokeWidth="1.8" strokeLinecap="round" />
            <circle cx="70" cy="43" r="2" fill="#342014" />
            <circle cx="79" cy="43" r="2" fill="#342014" />
            <path d="M72 50C74 52 77 52 79 50" stroke="#4C2C19" strokeWidth="1.6" strokeLinecap="round" />
            <path d="M35 61L31 68M51 62L54 68" stroke="#4C2C19" strokeWidth="2.2" strokeLinecap="round" />
            <path d="M29 68L25 68M54 68L58 68" stroke="#4C2C19" strokeWidth="2.2" strokeLinecap="round" />
            <circle cx="65" cy="49" r="2.5" fill="#E88A68" opacity=".75" />
          </g>
        </svg>
      </div>
    </>
  );
}
