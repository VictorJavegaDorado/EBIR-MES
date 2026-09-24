import { cleanup, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, it, vi } from "vitest";
import { MaterialRequestDialog } from "../../../../../src/frontend/src/features/replenishment-request/ui/MaterialRequestDialog";

afterEach(() => { cleanup(); vi.restoreAllMocks(); });

it("lists components and sends an idempotent material shortage request", async () => {
  const fetchMock = vi.spyOn(globalThis, "fetch")
    .mockResolvedValueOnce(new Response(JSON.stringify([{
      orderComponentId: 25, componentCode: "27920", description: "LUNA MIA",
      unitOfMeasure: "UN", theoreticalQuantity: 1, openRequestCount: 0,
    }]), { status: 200 }))
    .mockResolvedValueOnce(new Response(JSON.stringify({
      id: 41, navRequestId: 26932, state: "PENDIENTE_CREAR",
    }), { status: 201 }));
  const created = vi.fn();

  render(<MaterialRequestDialog sessionId={12}
    employee={{ employeeId: 7, fullName: "Operario piloto", navEmployeeCode: "EMP-7" }}
    onCancel={vi.fn()} onCreated={created} />);

  const dialog = await screen.findByRole("dialog", { name: /solicitar material/i });
  expect(within(dialog).getByText("27920")).toBeInTheDocument();
  await userEvent.click(within(dialog).getByRole("button", { name: /enviar solicitud/i }));

  expect(created).toHaveBeenCalledWith(26932, "27920", 1);
  const [url, request] = fetchMock.mock.calls[1];
  expect(url).toBe("/api/line-sessions/12/material-requests");
  expect(JSON.parse(String(request?.body))).toEqual({
    orderComponentId: 25, quantity: 1, employeeId: 7,
    correlationId: expect.any(String),
  });
});
