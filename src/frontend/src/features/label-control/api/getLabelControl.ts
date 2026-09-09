import type { LabelControlSnapshot } from "../model/labelControl";

export async function getLabelControl(
  signal?: AbortSignal,
): Promise<LabelControlSnapshot> {
  const response = await fetch("/api/label-control", {
    headers: { Accept: "application/json" },
    signal,
  });
  if (response.ok) return (await response.json()) as LabelControlSnapshot;
  throw new Error("No se puede consultar el historial de etiquetas.");
}
