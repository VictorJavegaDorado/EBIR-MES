import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SupervisorAccessGate } from "../../../../../src/frontend/src/features/supervisor-access/ui/SupervisorAccessGate";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("SupervisorAccessGate", () => {
  it("keeps labels hidden until a current supervisor RFID is accepted", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockResolvedValue(Response.json({
      employeeId: 9,
      navEmployeeCode: "SUP-09",
      fullName: "Supervisor Test",
    }));

    render(
      <SupervisorAccessGate>
        <h1>Etiquetas disponibles</h1>
      </SupervisorAccessGate>,
    );
    expect(screen.queryByText("Etiquetas disponibles")).not.toBeInTheDocument();

    const input = screen.getByLabelText(/Tarjeta RFID del supervisor/i);
    fireEvent.change(input, { target: { value: "SUPERVISOR-CARD" } });
    fireEvent.submit(input.closest("form")!);

    expect(input).toHaveValue("");
    expect(await screen.findByText("Etiquetas disponibles")).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/supervisor-access/rfid",
      expect.objectContaining({ method: "POST" }),
    );
  });

  it("rejects an RFID without a current supervisor role", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify({
      code: "RFID_SUPERVISOR_NOT_AUTHORIZED",
    }), { status: 403, headers: { "Content-Type": "application/json" } }));

    render(<SupervisorAccessGate><span>Contenido protegido</span></SupervisorAccessGate>);
    const input = screen.getByLabelText(/Tarjeta RFID del supervisor/i);
    fireEvent.change(input, { target: { value: "OPERATOR-CARD" } });
    fireEvent.submit(input.closest("form")!);

    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent(
      "La tarjeta no pertenece a un supervisor vigente.",
    ));
    expect(input).toHaveValue("");
    expect(screen.queryByText("Contenido protegido")).not.toBeInTheDocument();
  });
});
