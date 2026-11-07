import { useState } from "react";
import { useNavigate } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { ArrowRight, Compass, X } from "lucide-react";
import { useHoneyAuth } from "@/lib/hc/auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

type GuideIntent =
  | "start"
  | "government"
  | "van"
  | "lab"
  | "collection"
  | "processing"
  | "buyer"
  | "passport"
  | "oversight";

type GuideCopy = { title: string; body: string; action: string };

const GUIDE_COPY: Record<GuideIntent, GuideCopy> = {
  start: {
    title: "Start with collection",
    body: "The FPO workspace is a clear first stop: inspect collection records, create a batch and follow the next handoff.",
    action: "Open collection workspace",
  },
  government: {
    title: "Government & KVIC operations",
    body: "The KVIC view brings together cluster status, field visits and institutional quality oversight.",
    action: "Open KVIC operations",
  },
  van: {
    title: "Mobile VAN operations",
    body: "The VAN workflow is inside KVIC Field Operations. Schedule a visit, record arrival, collect a batch sample and log the field observation.",
    action: "Go to VAN operations",
  },
  lab: {
    title: "Laboratory Verification Portal",
    body: "Lab staff move samples from queue to testing to recorded PASS or FAIL. KVIC accounts can inspect lab status in cluster oversight; result entry remains role-gated.",
    action: "Open laboratory workflow",
  },
  collection: {
    title: "FPO / Collection Manager",
    body: "Start with collection, build a batch and follow verification and market linkage.",
    action: "Open collection workspace",
  },
  processing: {
    title: "Processor / Packager",
    body: "Follow an eligible lot through packaging, QR identity and custody transfer. Missing verification stays visible.",
    action: "Open processor workspace",
  },
  buyer: {
    title: "Buyer / Procurement",
    body: "Review available lots and their recorded laboratory and ledger status before procurement.",
    action: "Open buyer workspace",
  },
  passport: {
    title: "Sample Honey Yatra Passport",
    body: "The public passport opens without an account and states when a live ledger anchor is unavailable.",
    action: "Open sample passport",
  },
  oversight: {
    title: "Platform governance",
    body: "Platform oversight and domain administration have different permissions. This guide only opens a workspace the session can access.",
    action: "Open governance workspace",
  },
};

function inferIntent(value: string): GuideIntent | null {
  const query = value.toLowerCase();
  if (/passport|qr|batch code|consumer|trace/.test(query)) return "passport";
  if (/van|mobile|field visit|sample intake/.test(query)) return "van";
  if (/lab|laboratory|test queue|certificate|pass or fail/.test(query)) return "lab";
  if (/kvic|government|cluster|institution/.test(query)) return "government";
  if (/fpo|collect|harvest|batch|collection/.test(query)) return "collection";
  if (/process|pack|package|custody/.test(query)) return "processing";
  if (/buyer|procure|market|purchase/.test(query)) return "buyer";
  if (/admin|platform|governance|oversight/.test(query)) return "oversight";
  if (/start|demo|begin|walkthrough/.test(query)) return "start";
  return null;
}

export function AskMyBeeGuide() {
  const [open, setOpen] = useState(false);
  const [question, setQuestion] = useState("");
  const [suggestion, setSuggestion] = useState<GuideIntent | null>(null);
  const [notice, setNotice] = useState("");
  const [reply, setReply] = useState(
    "Hi! I'm Ask My Bee 🐝 Tell me what you want to explore and I'll point you to the right HoneyChain screen.",
  );
  const { user, mode, loading, enterDemo } = useHoneyAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const liveSession = Boolean(user && mode !== "demo");

  const ask = (value: string) => {
    setQuestion(value);
    setNotice("");
    const intent = inferIntent(value);
    if (!intent) {
      setSuggestion(null);
      setReply(
        'I’m your website guide, not a live AI conversation. Try “VAN”, “lab portal”, “KVIC clusters”, “collection”, “procurement” or “sample passport”.',
      );
      return;
    }
    setSuggestion(intent);
    setReply(GUIDE_COPY[intent].body);
  };

  const go = (intent: GuideIntent) => {
    if (loading) return;

    if (intent === "passport") {
      void navigate({
        to: "/passport",
        search: { code: "HC-NIL-2408-01", source: "demo" },
      });
      setOpen(false);
      return;
    }

    let role = "fpo";
    let destination: "/kvic" | "/lab" | "/org" | "/processor" | "/buyer" | "/admin" | "/admin/platform" = "/org";
    let hash: string | undefined;

    if (intent === "government") {
      role = "institution";
      destination = "/kvic";
    } else if (intent === "van") {
      role = "institution";
      destination = "/kvic";
      hash = "van-operations";
    } else if (intent === "lab") {
      const heldRoles = user?.roles?.length ? user.roles : user ? [user.role] : [];
      if (
        liveSession &&
        heldRoles.includes("institution") &&
        !heldRoles.includes("admin") &&
        !heldRoles.includes("lab")
      ) {
        role = "institution";
        destination = "/kvic";
        hash = "lab-oversight";
      } else {
        role = "lab";
        destination = "/lab";
      }
    } else if (intent === "processing") {
      role = "processor";
      destination = "/processor";
    } else if (intent === "buyer") {
      role = "buyer";
      destination = "/buyer";
    } else if (intent === "oversight") {
      const heldRoles = user?.roles?.length ? user.roles : user ? [user.role] : [];
      if (
        liveSession &&
        heldRoles.includes("platform_oversight") &&
        !heldRoles.includes("admin")
      ) {
        role = "platform_oversight";
        destination = "/admin/platform";
      } else {
        role = "admin";
        destination = "/admin";
      }
    }

    if (liveSession && user) {
      const heldRoles = user.roles?.length ? user.roles : [user.role];
      const allowedRoles: Record<string, string[]> = {
        "/kvic": ["institution", "admin", "platform_oversight"],
        "/lab": ["lab", "admin"],
        "/org": ["fpo", "admin"],
        "/processor": ["processor", "admin"],
        "/buyer": ["buyer", "admin"],
        "/admin/platform": ["platform_oversight", "admin"],
        "/admin": ["admin"],
      };

      if (!(allowedRoles[destination] ?? []).some((candidate) => heldRoles.some((heldRole) => heldRole === candidate))) {
        setNotice("Your live session wasn’t changed. Open Workspaces to see the areas this account may enter.");
        setSuggestion(null);
        void navigate({ to: "/portals" });
        return;
      }
    } else {
      queryClient.clear();
      enterDemo(role);
    }

    if (destination === "/kvic" && hash) {
      void navigate({ to: "/kvic", hash });
    } else if (destination === "/kvic") {
      void navigate({ to: "/kvic" });
    } else if (destination === "/lab") {
      void navigate({ to: "/lab" });
    } else if (destination === "/org") {
      void navigate({ to: "/org" });
    } else if (destination === "/processor") {
      void navigate({ to: "/processor" });
    } else if (destination === "/buyer") {
      void navigate({ to: "/buyer" });
    } else if (destination === "/admin/platform") {
      void navigate({ to: "/admin/platform" });
    } else {
      void navigate({ to: "/admin" });
    }
    setOpen(false);
  };

  return (
    <div className="fixed bottom-24 right-4 z-[70] flex flex-col items-end gap-3 md:bottom-5 md:right-5">
      {open ? (
        <section
          role="dialog"
          aria-label="Ask My Bee website guide"
          className="hc-bee-panel w-[min(22rem,calc(100vw-2rem))] overflow-hidden rounded-3xl border border-grove-900/10 bg-white"
        >
          <header className="flex items-start justify-between gap-3 bg-grove-800 p-4 text-white">
            <div className="flex items-center gap-3">
              <span className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-honey-300">
                <BeeGraphic />
              </span>
              <div>
                <p className="font-display text-xl">Ask My Bee</p>
                <p className="mt-0.5 text-xs text-white/70">Your HoneyChain tour guide</p>
              </div>
            </div>
            <button
              type="button"
              onClick={() => setOpen(false)}
              aria-label="Close Ask My Bee"
              className="rounded-lg p-1.5 text-white/70 hover:bg-white/10 hover:text-white"
            >
              <X size={18} />
            </button>
          </header>

          <div className="space-y-4 p-4">
            <p className="text-sm leading-6 text-ink">{reply}</p>
            {suggestion ? (
              <div className="rounded-2xl border border-grove-100 bg-grove-50 p-3">
                <p className="text-[10px] font-bold tracking-[0.14em] text-grove-700 uppercase">
                  Suggested destination
                </p>
                <p className="mt-1 font-semibold text-ink">{GUIDE_COPY[suggestion].title}</p>
                <Button
                  className="mt-3 w-full justify-between"
                  onClick={() => go(suggestion)}
                  disabled={loading}
                >
                  {GUIDE_COPY[suggestion].action}
                  <ArrowRight size={16} />
                </Button>
              </div>
            ) : null}
            {notice ? (
              <p role="status" className="rounded-xl bg-honey-50 p-3 text-xs leading-5 text-honey-600">
                {notice}
              </p>
            ) : null}

            <div>
              <p className="mb-2 text-[10px] font-bold tracking-[0.14em] text-muted uppercase">Try one</p>
              <div className="flex flex-wrap gap-2">
                {[
                  ["VAN operations", "Where is the VAN workflow?"],
                  ["Lab portal", "Show me laboratory verification"],
                  ["KVIC", "Where are the KVIC clusters?"],
                  ["Passport", "Open the sample passport"],
                ].map(([label, prompt]) => (
                  <button
                    key={label}
                    type="button"
                    onClick={() => ask(prompt)}
                    className="rounded-full border border-black/10 bg-white px-3 py-2 text-xs font-semibold text-grove-800 transition hover:border-honey-400 hover:bg-honey-50"
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>

            <form
              onSubmit={(event) => {
                event.preventDefault();
                ask(question);
              }}
              className="flex gap-2"
            >
              <Input
                aria-label="Ask where to find a HoneyChain workflow"
                value={question}
                onChange={(event) => setQuestion(event.target.value)}
                placeholder="Where do I find the lab portal?"
              />
              <Button
                type="submit"
                variant="secondary"
                aria-label="Find a workflow"
                disabled={!question.trim()}
              >
                <Compass size={17} />
              </Button>
            </form>
            <p className="text-[11px] leading-5 text-muted">
              I help you explore screens. I’m not a live AI chat; hive-health guidance belongs in the
              connected assistant or offline-first beekeeper app.
            </p>
          </div>
        </section>
      ) : null}

      <button
        type="button"
        aria-label={open ? "Close Ask My Bee guide" : "Open Ask My Bee guide"}
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
        className="group inline-flex min-h-14 items-center gap-3 rounded-full border border-grove-900/10 bg-white px-3 py-2 text-left shadow-[var(--shadow-card-hover)] transition duration-200 hover:-translate-y-1 hover:border-honey-400 focus-visible:outline-none"
      >
        <span className="hc-bee-flight grid h-10 w-12 place-items-center rounded-full bg-honey-100">
          <BeeGraphic />
        </span>
        <span className="pr-2">
          <span className="block text-sm font-bold text-grove-800">Ask My Bee</span>
          <span className="block text-[11px] text-muted">Need a little help?</span>
        </span>
        <span className="mr-1 grid h-8 w-8 place-items-center rounded-full bg-grove-800 text-white transition group-hover:bg-grove-700">
          <ArrowRight size={15} />
        </span>
      </button>
    </div>
  );
}

function BeeGraphic() {
  return (
    <svg viewBox="0 0 64 52" width="42" height="34" aria-hidden="true">
      <g className="hc-bee-wing">
        <ellipse cx="23" cy="13" rx="8" ry="6" fill="#d9f3f3" stroke="#65a5a3" strokeWidth="1.2" />
      </g>
      <g className="hc-bee-wing hc-bee-wing--right">
        <ellipse cx="39" cy="13" rx="8" ry="6" fill="#d9f3f3" stroke="#65a5a3" strokeWidth="1.2" />
      </g>
      <ellipse cx="31" cy="29" rx="17" ry="13" fill="#f5bd35" stroke="#6f4b12" strokeWidth="1.4" />
      <path d="M23 18 Q19 29 23 39 L28 41 Q24 29 29 18Z" fill="#25382b" />
      <path d="M34 17 Q30 29 34 40 L40 39 Q36 28 40 19Z" fill="#25382b" />
      <circle cx="43" cy="26" r="2" fill="#17261d" />
      <circle cx="49" cy="28" r="2" fill="#17261d" />
      <path d="M44 33 Q47 36 50 32" fill="none" stroke="#17261d" strokeWidth="1.4" strokeLinecap="round" />
      <path d="M15 28 L9 30 L15 33Z" fill="#6f4b12" />
      <circle cx="43" cy="31" r="3" fill="#f39b89" opacity=".8" />
    </svg>
  );
}
