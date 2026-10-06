import { useMemo, useRef, useState } from "react";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { PageHeader } from "@/components/hc/page-header";
import { HeroStatus, KpiCard } from "@/components/hc/kpi";
import { QueryTable } from "@/components/hc/data-table";
import { StatusBadge } from "@/components/hc/status-badge";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/hc/query-state";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useHcMutation, useHcQuery } from "@/lib/hc/query";
import { fmtDate, fmtNum, hiveRiskCopy } from "@/lib/hc/format";
import { useHoneyAuth } from "@/lib/hc/auth";
import { toast } from "sonner";

export function BeekeeperWorkspace() {
  const { mode } = useHoneyAuth();
  const hives = useHcQuery(["hives"], (api) => api.hives());
  const harvests = useHcQuery(["harvests"], (api) => api.harvests());
  const notes = useHcQuery(["notifications"], (api) => api.notifications());
  const [selected, setSelected] = useState<string>("");
  const hiveId = selected || hives.data?.[0]?.id || "";
  const readings = useHcQuery(["hives", hiveId, "readings"], (api) => api.hiveReadings(hiveId), {
    enabled: Boolean(hiveId),
  });
  const health = useHcQuery(["hives", hiveId, "health"], (api) => api.hiveHealth(hiveId), {
    enabled: Boolean(hiveId),
  });

  const [hiveCode, setHiveCode] = useState("");
  const [location, setLocation] = useState("");
  const [qty, setQty] = useState("5");
  const [honeyType, setHoneyType] = useState("Multifloral");
  const [temp, setTemp] = useState("33");
  const [hum, setHum] = useState("55");
  const [weight, setWeight] = useState("18");
  const hiveRetryKey = useRef(crypto.randomUUID());
  const harvestRetryKey = useRef(crypto.randomUUID());

  const createHive = useHcMutation((api, body: { hive_code: string; location?: string; client_id?: string }) => api.createHive(body), [["hives"]]);
  const createHarvest = useHcMutation(
    (api, body: { hive_id: string; quantity_kg: number; honey_type?: string; client_id?: string }) => api.createHarvest(body),
    [["harvests"]],
  );
  const addReading = useHcMutation(
    (api, body: { hive_id: string; temperature_c: number; humidity_percent: number; weight_kg: number }) =>
      api.addReading(body.hive_id, {
        temperature_c: body.temperature_c,
        humidity_percent: body.humidity_percent,
        weight_kg: body.weight_kg,
      }),
    [["hives", hiveId, "readings"], ["hives", hiveId, "health"]],
  );

  const chart = useMemo(
    () =>
      [...(readings.data || [])].reverse().map((r) => ({
        t: fmtDate(r.recorded_at),
        temperature: r.temperature_c,
        humidity: r.humidity_percent,
        weight: r.weight_kg,
      })),
    [readings.data],
  );

  const copy = health.data ? hiveRiskCopy(health.data) : null;
  const latest = readings.data?.[0];
  const savedNote = mode === "demo" ? "Saved in demo workspace. This was not sent to HoneyChain." : "Saved to HoneyChain.";

  if (hives.loading && !hives.data) return <LoadingBlock label="Loading your hives…" />;
  if (hives.error) return <ErrorState error={hives.error} onRetry={() => void hives.refetch()} />;

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="Beekeeper"
        title="My hives"
        description="Simple hive health, harvests, and what to do next. This is guidance from HoneyChain readings — not a veterinary diagnosis."
      />

      {copy ? (
        <HeroStatus tone={copy.tone === "ok" ? "ok" : copy.tone === "bad" ? "bad" : "warn"} title={copy.title} detail={`${copy.detail} Next: ${copy.next}`} />
      ) : health.error ? (
        /* Previously this fell through to "Choose a hive" even when a hive was
           already selected, which blamed the beekeeper for an API failure. */
        <ErrorState error={health.error} onRetry={() => void health.refetch()} />
      ) : (
        <HeroStatus title="Choose a hive" detail="Select a hive to see temperature, humidity, and any recommended visit." />
      )}

      <div className="grid gap-3 sm:grid-cols-3">
        <KpiCard label="My hives" value={fmtNum(hives.data?.length)} />
        <KpiCard label="Harvests recorded" value={fmtNum(harvests.data?.length)} />
        <KpiCard label="Unread alerts" value={fmtNum(notes.data?.unread_count)} />
      </div>

      {(hives.data || []).length === 0 ? (
        <EmptyState title="No hives have been registered yet." detail="Add a hive code used in your yard." />
      ) : (
        <div className="flex gap-2 overflow-x-auto pb-1">
          {(hives.data || []).map((h) => (
            <button
              key={h.id}
              type="button"
              onClick={() => setSelected(h.id)}
              className={`min-h-11 shrink-0 rounded-full px-4 text-sm font-semibold ${
                hiveId === h.id ? "bg-grove-700 text-cream" : "bg-paper text-ink shadow-[var(--shadow-card)]"
              }`}
            >
              {h.hive_code}
            </button>
          ))}
        </div>
      )}

      {hiveId ? (
        <div className="grid gap-4 lg:grid-cols-[1.1fr_0.9fr]">
          <Card>
            <h2 className="font-display text-xl">Current conditions</h2>
            {readings.loading ? (
              <LoadingBlock />
            ) : readings.error ? (
              /* Same trap as the harvest table: without this, a failed reading
                 request claims the hive has never been measured. */
              <ErrorState error={readings.error} onRetry={() => void readings.refetch()} />
            ) : latest ? (
              <dl className="mt-4 grid grid-cols-3 gap-3">
                <div>
                  <dt className="text-xs text-muted">Temperature</dt>
                  <dd className="font-display text-2xl tabular-nums">{fmtNum(latest.temperature_c, "°C")}</dd>
                </div>
                <div>
                  <dt className="text-xs text-muted">Humidity</dt>
                  <dd className="font-display text-2xl tabular-nums">{fmtNum(latest.humidity_percent, "%")}</dd>
                </div>
                <div>
                  <dt className="text-xs text-muted">Weight</dt>
                  <dd className="font-display text-2xl tabular-nums">{fmtNum(latest.weight_kg, " kg")}</dd>
                </div>
              </dl>
            ) : (
              <EmptyState title="No readings have been recorded for this hive yet." />
            )}
            {copy ? (
              <div className="mt-4">
                <StatusBadge label={copy.title} tone={copy.tone} />
                <p className="mt-2 text-sm">{copy.next}</p>
                {health.data?.simulated ? (
                  <p className="mt-2 text-xs text-muted">This health score is marked simulated by the API.</p>
                ) : null}
              </div>
            ) : null}
            {chart.length ? (
              <div className="mt-4 h-52">
                <ResponsiveContainer>
                  <LineChart data={chart}>
                    <CartesianGrid strokeDasharray="3 3" stroke="rgba(28,25,21,0.08)" />
                    <XAxis dataKey="t" hide />
                    <YAxis width={32} />
                    <Tooltip />
                    <Line dataKey="temperature" stroke="#C8881A" dot={false} name="Temp °C" />
                    <Line dataKey="humidity" stroke="#2F5D3A" dot={false} name="Humidity %" />
                    <Line dataKey="weight" stroke="#1C1915" dot={false} name="Weight kg" />
                  </LineChart>
                </ResponsiveContainer>
              </div>
            ) : null}
          </Card>
          <Card>
            <h2 className="font-display text-xl">Record an inspection</h2>
            <p className="mt-1 text-sm text-muted">Enter what you measured. HoneyChain will not invent readings.</p>
            <form
              className="mt-4 space-y-3"
              onSubmit={async (e) => {
                e.preventDefault();
                try {
                  await addReading.mutateAsync({
                    hive_id: hiveId,
                    temperature_c: Number(temp),
                    humidity_percent: Number(hum),
                    weight_kg: Number(weight),
                  });
                  toast.success(savedNote);
                } catch (err) {
                  toast.error(err instanceof Error ? err.message : "Could not save reading.");
                }
              }}
            >
              <Label>
                Temperature °C
                <Input className="mt-1" type="number" step="0.1" value={temp} onChange={(e) => setTemp(e.target.value)} />
              </Label>
              <Label>
                Humidity %
                <Input className="mt-1" type="number" step="0.1" value={hum} onChange={(e) => setHum(e.target.value)} />
              </Label>
              <Label>
                Weight kg
                <Input className="mt-1" type="number" step="0.1" value={weight} onChange={(e) => setWeight(e.target.value)} />
              </Label>
              <Button className="w-full" type="submit" disabled={addReading.isPending}>
                {addReading.isPending ? "Saving…" : "Save reading"}
              </Button>
            </form>
          </Card>
        </div>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <h2 className="font-display text-xl">Add a hive</h2>
          <form
            className="mt-4 space-y-3"
            onSubmit={async (e) => {
              e.preventDefault();
              try {
                await createHive.mutateAsync({ hive_code: hiveCode, location: location || undefined, client_id: hiveRetryKey.current });
                hiveRetryKey.current = crypto.randomUUID();
                setHiveCode("");
                setLocation("");
                toast.success(savedNote);
              } catch (err) {
                toast.error(err instanceof Error ? err.message : "Could not add hive.");
              }
            }}
          >
            <Label>
              Hive code
              <Input className="mt-1" value={hiveCode} onChange={(e) => setHiveCode(e.target.value)} required />
            </Label>
            <Label>
              Location
              <Input className="mt-1" value={location} onChange={(e) => setLocation(e.target.value)} />
            </Label>
            <Button className="w-full" type="submit" disabled={createHive.isPending}>
              Add hive
            </Button>
          </form>
        </Card>
        <Card>
          <h2 className="font-display text-xl">Record a harvest</h2>
          <form
            className="mt-4 space-y-3"
            onSubmit={async (e) => {
              e.preventDefault();
              if (!hiveId) return;
              try {
                await createHarvest.mutateAsync({
                  hive_id: hiveId,
                  quantity_kg: Number(qty),
                  honey_type: honeyType,
                  client_id: harvestRetryKey.current,
                });
                harvestRetryKey.current = crypto.randomUUID();
                toast.success(savedNote);
              } catch (err) {
                toast.error(err instanceof Error ? err.message : "Could not record harvest.");
              }
            }}
          >
            <Label>
              Quantity kg
              <Input className="mt-1" type="number" min="0.1" step="0.1" value={qty} onChange={(e) => setQty(e.target.value)} />
            </Label>
            <Label>
              Honey type
              <Input className="mt-1" value={honeyType} onChange={(e) => setHoneyType(e.target.value)} />
            </Label>
            <Button className="w-full" type="submit" disabled={!hiveId || createHarvest.isPending}>
              Record harvest
            </Button>
          </form>
        </Card>
      </div>

      <section>
        <h2 className="mb-3 font-display text-xl">Recent harvests</h2>
        {/* A denied harvest request previously rendered as
            "No harvests have been recorded yet.", telling a beekeeper their
            season's work does not exist. QueryTable checks the error first. */}
        <QueryTable
          query={harvests}
          loadingLabel="Loading harvests…"
          empty="No harvests have been recorded yet."
          columns={[
            { key: "hive", label: "Hive" },
            { key: "qty", label: "Quantity" },
            { key: "type", label: "Type" },
            { key: "when", label: "When" },
          ]}
          rows={(data) =>
            (data || []).map((h) => ({
              hive: (hives.data || []).find((x) => x.id === h.hive_id)?.hive_code || h.hive_id,
              qty: fmtNum(h.quantity_kg, " kg"),
              type: h.honey_type || "Not specified",
              when: fmtDate(h.harvested_at),
            }))
          }
        />
      </section>
    </div>
  );
}
