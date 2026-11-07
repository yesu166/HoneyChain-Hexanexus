import { Link, useNavigate } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import {
  Activity,
  ArrowRight,
  Building2,
  CheckCircle2,
  Download,
  Factory,
  FlaskConical,
  Landmark,
  PackageCheck,
  ShieldCheck,
  Smartphone,
  Truck,
  type LucideIcon,
} from "lucide-react";
import { AskMyBeeGuide } from "@/components/hc/ask-my-bee-guide";
import { PublicHeader } from "@/components/hc/app-shell";
import { ProvenancePath } from "@/components/hc/timeline";
import { Button } from "@/components/ui/button";
import { useHoneyAuth } from "@/lib/hc/auth";
import { homeForRole } from "@/lib/hc/format";

type DemoEntry = {
  id: string;
  group: string;
  role: string;
  name: string;
  description: string;
  icon: LucideIcon;
  hash?: string;
};

const DEMO_ENTRIES: DemoEntry[] = [
  {
    id: "kvic",
    group: "Government & quality",
    role: "institution",
    name: "KVIC Field Officer",
    description: "Review cluster operations, field visits, sample intake and laboratory status.",
    icon: Landmark,
  },
  {
    id: "van",
    group: "Government & quality",
    role: "institution",
    name: "Mobile VAN Operations",
    description: "Go directly to visit scheduling, arrival, batch sample collection and field observations.",
    icon: Truck,
    hash: "van-operations",
  },
  {
    id: "lab",
    group: "Government & quality",
    role: "lab",
    name: "Laboratory Verification Portal",
    description: "Move a sample from queue to testing and recorded PASS or FAIL. A lab result is not blockchain proof of purity.",
    icon: FlaskConical,
  },
  {
    id: "fpo",
    group: "Supply chain",
    role: "fpo",
    name: "FPO / Collection Manager",
    description: "Follow collection, batch creation, verification and market linkage.",
    icon: Building2,
  },
  {
    id: "processor",
    group: "Supply chain",
    role: "processor",
    name: "Processor / Packager",
    description: "Inspect eligible lots, package them and record the next custody handoff.",
    icon: Factory,
  },
  {
    id: "buyer",
    group: "Supply chain",
    role: "buyer",
    name: "Buyer / Procurement",
    description: "Review available lots and their recorded laboratory and ledger status before procurement.",
    icon: PackageCheck,
  },
  {
    id: "admin",
    group: "Governance",
    role: "admin",
    name: "Platform Administrator",
    description: "Inspect online business operations, alerts and system health.",
    icon: ShieldCheck,
  },
  {
    id: "oversight",
    group: "Governance",
    role: "platform_oversight",
    name: "Platform Oversight",
    description: "Review platform-level organization and membership governance.",
    icon: Activity,
  },
];

const DEMO_GROUPS = ["Government & quality", "Supply chain", "Governance"];

const BEEKEEPER_APK_URL = "https://github.com/yesu166/HoneyChain-Hexanexus/releases/latest/download/honeychain-beekeeper.apk";

export function LandingPage() {
  const { user, mode, loading, enterDemo } = useHoneyAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const canLaunchDemo = !loading && (!user || mode === "demo");

  const launchDemo = (role: string, hash?: string) => {
    // Clear stale query results, but let auth preserve the shared demo data when
    // the visitor explicitly switches role inside an already-open demo.
    queryClient.clear();
    const demoUser = enterDemo(role);
    const destination = homeForRole(demoUser.role);
    if (hash && destination === "/kvic") {
      void navigate({ to: "/kvic", hash });
    } else {
      void navigate({ to: destination });
    }
  };

  return (
    <div className="min-h-screen">
      <PublicHeader />
      <aside className="mx-auto max-w-7xl px-4 pt-2 md:px-8" aria-label="Demo environment notice">
        <div role="status" className="flex flex-wrap items-center gap-3 border border-honey-200 bg-honey-50 px-4 py-3 text-sm text-grove-900">
          <span className="shrink-0 border border-honey-400 bg-white px-2.5 py-1 text-[10px] font-bold tracking-[0.14em] text-grove-800">DEMO ENVIRONMENT</span>
          <p className="min-w-0 flex-1 leading-5">
            The live backend is currently unavailable. This walkthrough uses sample records; changes are temporary and are not sent to a live service.
          </p>
        </div>
      </aside>
      <main className="mx-auto max-w-7xl px-4 pb-20 md:px-8">
        <section className="relative isolate overflow-hidden rounded-lg border border-grove-900/10 bg-white shadow-none">

          <div className="relative grid gap-8 p-6 md:grid-cols-[1.05fr_0.95fr] md:gap-10 md:p-10 lg:p-12">
            <div className="flex flex-col justify-center">
              <p className="inline-flex w-fit items-center gap-2 rounded-sm border border-grove-100 bg-grove-50 px-3 py-1.5 text-[10px] font-bold tracking-[0.16em] text-grove-800 uppercase">
                <span className="h-2 w-2 rounded-sm bg-honey-500" />
                Hive-to-home traceability
              </p>
              <h1 className="mt-5 max-w-3xl font-display text-4xl leading-[1.04] tracking-tight text-ink md:text-5xl lg:text-6xl">
                Every jar has a journey.
                <span className="mt-2 block text-grove-700">Make the evidence easy to follow.</span>
              </h1>
              <p className="mt-5 max-w-2xl text-base leading-7 text-muted md:text-lg">
                A harvest moves through collection, laboratory verification, processing, packaging
                and procurement. HoneyChain connects those handoffs around one batch record, so
                people can follow what was recorded, what is verified and what is still pending.
              </p>

              <div className="mt-7 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
                {canLaunchDemo ? (
                  <Button size="lg" className="sm:min-w-56" onClick={() => launchDemo("fpo")}>
                    Start the supply-chain demo <ArrowRight size={17} />
                  </Button>
                ) : user ? (
                  <Button size="lg" asChild className="sm:min-w-56">
                    <Link to="/portals">Open your workspaces <ArrowRight size={17} /></Link>
                  </Button>
                ) : (
                  <Button size="lg" disabled>Checking session…</Button>
                )}
                <Button size="lg" variant="secondary" asChild>
                  <Link to="/passport" search={{ code: "HC-NIL-2408-01", source: "demo" }}>
                    View sample Honey Yatra Passport
                  </Link>
                </Button>
              </div>
              <p className="mt-3 max-w-xl text-xs leading-5 text-muted">
                Sample workspaces are clearly labelled and temporary. Real sign-in stays separate
                and never falls back to demo data automatically.
              </p>

              <div className="mt-7 flex flex-wrap items-center gap-x-5 gap-y-2 border-t border-black/[0.06] pt-5 text-xs font-semibold text-grove-800">
                <span className="inline-flex items-center gap-2"><CheckCircle2 size={15} className="text-grove-600" /> Batch-level history</span>
                <span className="inline-flex items-center gap-2"><CheckCircle2 size={15} className="text-grove-600" /> Lab status and custody</span>
                <span className="inline-flex items-center gap-2"><CheckCircle2 size={15} className="text-grove-600" /> Public QR passport</span>
              </div>
            </div>

            <aside className="relative flex flex-col justify-between overflow-hidden rounded-md bg-grove-800 p-5 text-white md:p-7">
              <div aria-hidden="true" className="pointer-events-none absolute -right-14 -top-12 h-52 w-52 rounded-sm border border-white/10" />
              <div aria-hidden="true" className="pointer-events-none absolute -right-4 -top-2 h-32 w-32 rounded-sm border border-white/10" />
              <div className="relative">
                <p className="text-[10px] font-bold tracking-[0.18em] text-honey-200 uppercase">One batch. Every handoff.</p>
                <h2 className="mt-3 max-w-lg font-display text-3xl leading-tight md:text-4xl">
                  From the first field record to the final product.
                </h2>
                <p className="mt-3 max-w-lg text-sm leading-6 text-white/75">
                  Each step leaves a record the next team can check. Missing evidence stays visible;
                  a status is never treated as proof of something it cannot establish.
                </p>
              </div>
              <div className="relative mt-7 rounded-md border border-white/10 bg-white/[0.06] p-4">
                <ProvenancePath current="Product" />
              </div>
              <div className="relative mt-5 grid grid-cols-2 gap-3">
                <div className="rounded-sm bg-white/[0.08] p-3">
                  <p className="text-[10px] font-bold tracking-[0.14em] text-honey-200 uppercase">Quality</p>
                  <p className="mt-1 text-sm font-semibold text-white">Lab result recorded</p>
                  <p className="mt-1 text-xs leading-5 text-white/65">Not a guarantee of chemical purity.</p>
                </div>
                <div className="rounded-sm bg-white/[0.08] p-3">
                  <p className="text-[10px] font-bold tracking-[0.14em] text-honey-200 uppercase">Ledger</p>
                  <p className="mt-1 text-sm font-semibold text-white">Anchor status shown</p>
                  <p className="mt-1 text-xs leading-5 text-white/65">Unavailable is shown plainly when offline.</p>
                </div>
              </div>
            </aside>
          </div>
        </section>

        <section aria-labelledby="beekeeper-download-title" className="mt-5 grid gap-5 border border-grove-100 bg-white p-5 md:grid-cols-[1fr_auto] md:items-center md:p-7">
          <div className="flex items-start gap-4">
            <span className="grid h-12 w-12 shrink-0 place-items-center bg-honey-100 text-grove-800">
              <Smartphone size={23} />
            </span>
            <div>
              <p className="text-[10px] font-bold tracking-[0.16em] text-grove-700 uppercase">Offline-first Android application</p>
              <h2 id="beekeeper-download-title" className="mt-1 font-display text-2xl text-ink">HoneyChain Beekeeper App</h2>
              <p className="mt-2 max-w-2xl text-sm leading-6 text-muted">
                Record hive details, inspections and harvest activity from the field. The app is designed for offline-first capture and later synchronization when the backend is available.
              </p>
              <p className="mt-2 text-xs font-semibold text-muted">Demo distribution build · Not production / Play Store signed</p>
            </div>
          </div>
          <div className="flex flex-col gap-2 sm:min-w-52">
            <Button asChild className="w-full justify-center">
              <a href={BEEKEEPER_APK_URL} target="_blank" rel="noreferrer">
                <Download size={16} /> Download Beekeeper APK
              </a>
            </Button>
            <a
              href="https://github.com/yesu166/HoneyChain-Hexanexus/releases/latest"
              target="_blank"
              rel="noreferrer"
              className="text-center text-xs font-semibold text-grove-700 underline underline-offset-4"
            >
              View GitHub release notes
            </a>
          </div>
        </section>

        <section aria-label="Traceability journey" className="mt-5 grid gap-2 rounded-md border border-black/[0.06] bg-white p-3 shadow-none sm:grid-cols-5 md:p-4">
          {[
            { number: "01", title: "Field record", detail: "Hive & harvest" },
            { number: "02", title: "Collection", detail: "FPO & batch" },
            { number: "03", title: "Lab verification", detail: "Test & result" },
            { number: "04", title: "Processing", detail: "Package & custody" },
            { number: "05", title: "Procurement", detail: "Buyer & passport" },
          ].map((stage) => (
            <div key={stage.number} className="flex items-center gap-3 rounded-sm px-3 py-3 sm:flex-col sm:items-start sm:gap-2">
              <span className="grid h-8 w-8 shrink-0 place-items-center rounded-sm bg-honey-100 text-xs font-bold text-grove-800">{stage.number}</span>
              <div>
                <p className="text-sm font-bold text-ink">{stage.title}</p>
                <p className="mt-0.5 text-xs text-muted">{stage.detail}</p>
              </div>
            </div>
          ))}
        </section>

        <section className="mt-12 grid gap-4 md:grid-cols-3">
          {[
            { icon: Building2, label: "For producer groups", title: "Less fragmented paperwork", body: "Collection and batch records stay connected as lots move to verification and markets." },
            { icon: FlaskConical, label: "For quality teams", title: "Evidence stays with the batch", body: "Test requests and recorded outcomes stay visible without confusing them with ledger proofs." },
            { icon: PackageCheck, label: "For buyers", title: "Check before procurement", body: "Buyers review available lots and recorded custody and verification before proceeding." },
          ].map((item) => (
            <article key={item.title} className="group rounded-md border border-black/[0.06] bg-white p-5 shadow-none transition duration-200 hover:border-grove-300 md:p-6">
              <span className="grid h-11 w-11 place-items-center rounded-md bg-grove-50 text-grove-800 transition group-hover:bg-honey-100"><item.icon size={21} /></span>
              <p className="mt-4 text-[10px] font-bold tracking-[0.16em] text-grove-700 uppercase">{item.label}</p>
              <h3 className="mt-2 font-display text-xl text-ink">{item.title}</h3>
              <p className="mt-2 text-sm leading-6 text-muted">{item.body}</p>
            </article>
          ))}
        </section>

        {canLaunchDemo ? (
          <section id="demo-roles" className="mt-14 scroll-mt-24">
            <div className="max-w-3xl">
              <p className="text-[10px] font-bold tracking-[0.18em] text-grove-700 uppercase">Guided demo</p>
              <h2 className="mt-2 font-display text-3xl leading-tight text-ink md:text-4xl">
                Choose a role. Follow its next step.
              </h2>
              <p className="mt-3 text-sm leading-6 text-muted">
                These entries open existing web workflows with shared sample records. Follow
                collection, government field operations, laboratory verification, processing and
                procurement. Beekeeper capture remains a separate offline-first Android app.
              </p>
            </div>

            {DEMO_GROUPS.map((group) => {
              const entries = DEMO_ENTRIES.filter((entry) => entry.group === group);
              return (
                <section key={group} className="mt-7">
                  <div className="mb-3 flex items-center gap-3">
                    <h3 className="font-display text-xl text-ink">{group}</h3>
                    <span aria-hidden="true" className="h-px flex-1 bg-black/[0.08]" />
                  </div>
                  <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                    {entries.map((entry) => {
                      const Icon = entry.icon;
                      return (
                        <article key={entry.id} className="flex min-h-52 flex-col rounded-md border border-black/[0.06] bg-white p-5 shadow-none transition duration-200 hover:-translate-y-1 hover:border-honey-300 hover:shadow-[var(--shadow-card-hover)] md:p-6">
                          <div className="flex items-start justify-between gap-3">
                            <span className="grid h-11 w-11 place-items-center rounded-md bg-honey-100 text-grove-800">
                              <Icon size={21} />
                            </span>
                            <span className="rounded-sm bg-grove-50 px-3 py-1 text-[10px] font-bold tracking-wide text-grove-700">SAMPLE DATA</span>
                          </div>
                          <h4 className="mt-4 font-display text-xl text-ink">{entry.name}</h4>
                          <p className="mt-2 flex-1 text-sm leading-6 text-muted">{entry.description}</p>
                          <Button className="mt-5 w-full justify-between" variant="secondary" onClick={() => launchDemo(entry.role, entry.hash)}>
                            Open {entry.name} <ArrowRight size={16} />
                          </Button>
                        </article>
                      );
                    })}
                  </div>
                </section>
              );
            })}
          </section>
        ) : null}

        <section className="mt-14 overflow-hidden rounded-md border border-grove-100 bg-grove-50 p-6 md:p-9">
          <div className="grid gap-5 md:grid-cols-[1fr_auto] md:items-center">
            <div>
              <p className="text-[10px] font-bold tracking-[0.18em] text-grove-700 uppercase">Public verification</p>
              <h2 className="mt-2 font-display text-2xl text-ink md:text-3xl">Have a batch code? Follow its recorded journey.</h2>
              <p className="mt-2 max-w-2xl text-sm leading-6 text-muted">
                The sample passport opens without an account. It distinguishes laboratory results
                from blockchain anchoring; neither a QR code nor a ledger entry alone proves the
                physical contents of a jar are pure.
              </p>
            </div>
            <Button asChild>
              <Link to="/passport" search={{ code: "HC-NIL-2408-01", source: "demo" }}>
                Open sample passport <ArrowRight size={16} />
              </Link>
            </Button>
          </div>
        </section>
      </main>
      <AskMyBeeGuide />
    </div>
  );
}
