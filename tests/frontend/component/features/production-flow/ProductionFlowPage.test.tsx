import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ProductionFlowPage } from "../../../../../src/frontend/src/features/production-flow/ui/ProductionFlowPage";

const line = {
  id: 40,
  code: "LINEA-TEST-01",
  name: "Línea piloto TEST",
  workCenterCode: "CT-01",
  workCenterName: "Centro TEST",
  operationalStatus: "LIBRE",
};

const order = {
  productionOrderId: 28,
  orderNumber: "FL20-02277",
  productNumber: "27979CI",
  productDescription: "Producto piloto",
  lotNumber: "FL2002277",
  targetQuantity: 10,
  goodQuantity: 0,
  reservedQuantity: 0,
  scrapQuantity: 0,
  runTimeMinutes: 36,
  state: "IMPORTADA",
  importedAtUtc: "2026-08-01T11:20:53Z",
};

const tableState = {
  lineSessionId: 12,
  orderId: 28,
  lineId: 40,
  state: "PRODUCIENDO",
  startedAtUtc: "2026-08-05T10:00:00Z",
  serverTimeUtc: new Date().toISOString(),
  productiveSeconds: 65,
  activeResources: 1,
  currentTheoreticalCapacityPerHour: 6,
  palletFormatCode: "POK",
  unitsPerPallet: 20,
  operators: [{
    employeeId: 7,
    navEmployeeCode: "EMP-7",
    fullName: "Operario piloto",
    entryAtUtc: "2026-08-05T10:00:00Z",
    productiveSeconds: 65,
    status: "PRODUCIENDO",
  }],
};

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("ProductionFlowPage", () => {
  it("shows the six operator steps without module navigation", () => {
    render(<ProductionFlowPage />);

    for (const label of ["Línea", "Orden", "Equipo", "Palés", "NAV", "Libre"]) {
      expect(screen.getAllByText(label).length).toBeGreaterThan(0);
    }
    expect(screen.getByRole("heading", { name: "Escanea la línea" })).toBeInTheDocument();
    expect(screen.queryByRole("navigation")).not.toBeInTheDocument();
  });

  it("advances from line to an exact scanned order", async () => {
    vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify(line), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([order]), { status: 200 }))
      .mockResolvedValueOnce(new Response(null, { status: 404 }));

    render(<ProductionFlowPage />);
    await userEvent.type(screen.getByRole("textbox", { name: /código de línea/i }), "linea-test-01{enter}");

    expect(await screen.findByRole("heading", { name: "Escanea la orden" })).toBeInTheDocument();
    expect(globalThis.fetch).toHaveBeenNthCalledWith(
      1,
      "/api/lines/LINEA-TEST-01",
      expect.objectContaining({ headers: { Accept: "application/json" } }),
    );
    expect(globalThis.fetch).toHaveBeenNthCalledWith(
      2,
      "/api/production-orders",
      expect.objectContaining({ headers: { Accept: "application/json" } }),
    );

    await userEvent.type(screen.getByRole("textbox", { name: /orden de fabricación/i }), "FL20-02277{enter}");
    expect(screen.getByRole("heading", { name: "Identifica operarios" })).toBeInTheDocument();
    expect(screen.getByText("FL20-02277")).toBeInTheDocument();
  });

  it("identifies an employee and clears the RFID credential immediately", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify(line), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([order]), { status: 200 }))
      .mockResolvedValueOnce(new Response(null, { status: 404 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        employeeId: 7,
        navEmployeeCode: "EMP-7",
        fullName: "Operario piloto",
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        lineSessionId: 12,
        timeEntryId: 31,
        palletReservationId: 47,
        sessionCreated: true,
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify(tableState), { status: 200 }));

    render(<ProductionFlowPage />);
    await userEvent.type(screen.getByRole("textbox", { name: /código de línea/i }), "LINEA-TEST-01{enter}");
    await screen.findByRole("heading", { name: "Escanea la orden" });
    await userEvent.type(screen.getByRole("textbox", { name: /orden de fabricación/i }), "FL20-02277{enter}");

    const rfid = screen.getByRole("textbox", { name: /lector RFID/i });
    await userEvent.type(rfid, "SYNTHETIC-CARD{enter}");

    expect(await screen.findByText("Operario piloto")).toBeInTheDocument();
    expect(rfid).toHaveValue("");
    expect(screen.queryByText("SYNTHETIC-CARD")).not.toBeInTheDocument();
    const [, request] = fetchMock.mock.calls[3];
    expect(JSON.parse(String(request?.body))).toEqual({ credential: "SYNTHETIC-CARD" });
    expect(fetchMock.mock.calls[4][0]).toBe("/api/production-workstations/start-or-join");
    expect(screen.getByText("PRODUCIENDO")).toBeInTheDocument();
    expect(screen.getByText("Tiempo productivo total").nextElementSibling?.textContent)
      .toMatch(/^00:01:0[5-9]$/);
  });

  it("recovers an active production table after rescanning line and order", async () => {
    vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify(line), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([order]), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify(tableState), { status: 200 }));

    render(<ProductionFlowPage />);
    await userEvent.type(screen.getByPlaceholderText("LINEA-TEST-01"), "LINEA-TEST-01{enter}");
    await screen.findByRole("heading", { name: "Escanea la orden" });
    await userEvent.type(screen.getByPlaceholderText("Escanea la orden"), "FL20-02277{enter}");

    expect(await screen.findByText(/recuperada desde el servidor/i)).toBeInTheDocument();
    expect(screen.getByText("PRODUCIENDO")).toBeInTheDocument();
    expect(screen.getByText("Operario piloto")).toBeInTheDocument();
    expect(screen.getByText(/Actualización automática cada 10 s/i)).toBeInTheDocument();
  });

  it("shows the effective server state and freezes a paused operator timer", async () => {
    const pausedTable = {
      ...tableState,
      state: "SIN_OPERARIOS",
      activeResources: 0,
      operators: [{
        ...tableState.operators[0],
        status: "EN_PAUSA",
      }],
    };
    vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify(line), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([order]), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify(pausedTable), { status: 200 }));

    render(<ProductionFlowPage />);
    await userEvent.type(screen.getByPlaceholderText("LINEA-TEST-01"), "LINEA-TEST-01{enter}");
    await screen.findByRole("heading", { name: "Escanea la orden" });
    await userEvent.type(screen.getByPlaceholderText("Escanea la orden"), "FL20-02277{enter}");

    expect(await screen.findByText("SIN OPERARIOS")).toBeInTheDocument();
    expect(screen.getByText(/EMP-7 · En pausa · 00:01:05/)).toBeInTheDocument();
    expect(screen.queryByText("PRODUCIENDO")).not.toBeInTheDocument();
  });

  it("starts an operator pause and refreshes the table from the server", async () => {
    const pausedTable = {
      ...tableState,
      state: "SIN_OPERARIOS",
      activeResources: 0,
      operators: [{ ...tableState.operators[0], status: "EN_PAUSA" }],
    };
    const fetchMock = vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify(line), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([order]), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify(tableState), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ id: 91, activeResources: 0 }), { status: 201 }))
      .mockResolvedValueOnce(new Response(JSON.stringify(pausedTable), { status: 200 }));

    render(<ProductionFlowPage />);
    await userEvent.type(screen.getByPlaceholderText("LINEA-TEST-01"), "LINEA-TEST-01{enter}");
    await screen.findByRole("heading", { name: "Escanea la orden" });
    await userEvent.type(screen.getByPlaceholderText("Escanea la orden"), "FL20-02277{enter}");
    await screen.findByText("Operario piloto");
    await userEvent.click(screen.getByRole("button", { name: /Pausa WC de Operario piloto/i }));

    expect(fetchMock.mock.calls[3][0]).toBe("/api/line-sessions/12/operator-stops");
    expect(JSON.parse(String(fetchMock.mock.calls[3][1]?.body))).toEqual(
      expect.objectContaining({ employeeId: 7, reason: "WC" }),
    );
    expect(await screen.findByText(/EMP-7 · En pausa · 00:01:05/)).toBeInTheDocument();
    expect(screen.getByText(/Pausa registrada/i)).toBeInTheDocument();
  });

  it("keeps NAV confirmation visibly blocked instead of simulating success", async () => {
    vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify(line), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([order]), { status: 200 }))
      .mockResolvedValueOnce(new Response(null, { status: 404 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        employeeId: 7,
        navEmployeeCode: "EMP-7",
        fullName: "Operario piloto",
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        lineSessionId: 12,
        timeEntryId: 31,
        palletReservationId: 47,
        sessionCreated: true,
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify(tableState), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        reservations: [], employees: [], supervisors: [],
      }), { status: 200 }));

    render(<ProductionFlowPage />);
    await userEvent.type(screen.getByRole("textbox", { name: /código de línea/i }), "LINEA-TEST-01{enter}");
    await screen.findByRole("heading", { name: "Escanea la orden" });
    await userEvent.type(screen.getByRole("textbox", { name: /orden de fabricación/i }), "FL20-02277{enter}");
    await userEvent.type(screen.getByRole("textbox", { name: /lector RFID/i }), "SYNTHETIC-CARD{enter}");
    await screen.findByText("Operario piloto");
    await userEvent.click(screen.getByRole("button", { name: /continuar a palés/i }));
    await screen.findByText(/completa y cierra los palés/i);
    await userEvent.click(screen.getByRole("button", { name: /revisar cierre de orden/i }));

    expect(screen.getByRole("heading", { name: /confirmación final pendiente/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /confirmar NAV y liberar línea/i })).toBeDisabled();
  });
});
