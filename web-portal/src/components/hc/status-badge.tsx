import { Badge } from "@/components/ui/badge";
import { statusTone, type Tone } from "@/lib/hc/format";

export function StatusBadge({ label, tone }: { label: string; tone?: Tone }) {
  return <Badge tone={tone || statusTone(label)}>{label.replaceAll("_", " ")}</Badge>;
}
