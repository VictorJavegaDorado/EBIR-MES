import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { MaterialRequestStatusPanel } from "../../../../../src/frontend/src/features/replenishment-request/ui/MaterialRequestStatusPanel";

afterEach(() => { cleanup(); vi.restoreAllMocks(); });

it.each([
  ["PENDING", "Pendiente de almacén"],
  ["PREPARING", "Material en preparación"],
  ["SENT", "Material enviado"],
  ["ERROR", "Requiere revisión"],
] as const)("shows %s material requests with an unequivocal label", async (state, label) => {
  const requests = [{
    id: 41, navRequestId: 26932,
    correlationId: "11111111-2222-4333-8444-555555555555",
    componentCode: "27920", description: "LUNA MIA", quantity: 1,
    requestedAtUtc: "2026-09-24T20:57:04Z", state, navState: state,
    pickingNumber: state === "PREPARING" ? "APU21-1459" : null,
    registeredAt: null, error: state === "ERROR" ? "Sin stock" : null,
  }] as const;

  render(<MaterialRequestStatusPanel requests={[...requests]} />);

  expect(await screen.findByText(label)).toBeInTheDocument();
  expect(screen.getByText(/1 ud. · 27920/i)).toBeInTheDocument();
});
