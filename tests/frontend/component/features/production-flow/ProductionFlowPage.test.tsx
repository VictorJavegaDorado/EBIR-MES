import { cleanup, render, screen, waitFor, within } from "@testing-library/react";
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
  it("shows the three operator steps without module navigation", () => {
    render(<ProductionFlowPage />);

    for (const label of ["Línea", "Orden", "Trabajo"]) {
      expect(screen.getAllByText(label).length).toBeGreaterThan(0);
    }
    expect(screen.queryByText("Equipo")).not.toBeInTheDocument();
    expect(screen.queryByText("Libre")).not.toBeInTheDocument();
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
    expect(screen.getByRole("heading", { name: "Gestiona la producción" })).toBeInTheDocument();
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

  it("recovers a completed order by line so the last operator can leave", async () => {
    const completedOrder = {
      ...order,
      orderNumber: "FL26-00003",
      targetQuantity: 100,
      goodQuantity: 100,
      state: "PENDIENTE_CIERRE",
    };
    const recoveredTable = {
      ...tableState,
      orderId: completedOrder.productionOrderId,
    };
    const tableWithoutOperators = {
      ...recoveredTable,
      state: "SIN_OPERARIOS",
      activeResources: 0,
      operators: [],
    };
    const fetchMock = vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify(line), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([]), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        order: completedOrder,
        table: recoveredTable,
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ activeResources: 0 }), { status: 201 }))
      .mockResolvedValueOnce(new Response(JSON.stringify(tableWithoutOperators), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        state: "FINALIZADA",
        correlationId: "9a8b1e15-ec9a-46e5-9f3e-c159b069080b",
      }), { status: 200 }));

    render(<ProductionFlowPage />);
    await userEvent.type(screen.getByPlaceholderText("LINEA-TEST-01"), "LINEA-TEST-01{enter}");
    await screen.findByRole("heading", { name: "Escanea la orden" });
    await userEvent.type(screen.getByPlaceholderText("Escanea la orden"), "FL26-00003{enter}");

    expect(await screen.findByText(/Mesa pendiente de FL26-00003 recuperada/i))
      .toBeInTheDocument();
    expect(screen.getByText("Operario piloto")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: /Registrar salida de Operario piloto/i }));

    expect(fetchMock.mock.calls[3][0]).toBe("/api/line-sessions/12/exits");
    expect(await screen.findByText("Todavía no hay personas identificadas.")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Finalizar orden" }));

    expect(fetchMock.mock.calls[5][0]).toBe(
      "/api/production-workstations/12/complete-order",
    );
    expect(screen.getByRole("heading", { name: "Escanea la orden" })).toBeInTheDocument();
    const completion = screen.getByText(
      /Orden FL26-00003 finalizada\. Línea LINEA-TEST-01 libre para una nueva orden/i,
    );
    expect(completion).toBeInTheDocument();
    const feedback = completion.closest(".flow-feedback");
    expect(feedback).toHaveAttribute("role", "status");
    expect(feedback?.nextElementSibling).toHaveClass("flow-progress");
  });

  it("keeps the completed table visible when order completion is rejected", async () => {
    const completedOrder = {
      ...order,
      orderNumber: "FL26-00003",
      targetQuantity: 100,
      goodQuantity: 100,
      state: "PENDIENTE_CIERRE",
    };
    const tableWithoutOperators = {
      ...tableState,
      orderId: completedOrder.productionOrderId,
      state: "SIN_OPERARIOS",
      activeResources: 0,
      operators: [],
    };
    vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify(line), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([]), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        order: completedOrder,
        table: tableWithoutOperators,
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        code: "PALLET_OUTPUT_NOT_CONFIRMED",
        detail: "Todas las salidas de palé deben estar confirmadas.",
      }), { status: 409 }));

    render(<ProductionFlowPage />);
    await userEvent.type(screen.getByPlaceholderText("LINEA-TEST-01"), "LINEA-TEST-01{enter}");
    await screen.findByRole("heading", { name: "Escanea la orden" });
    await userEvent.type(screen.getByPlaceholderText("Escanea la orden"), "FL26-00003{enter}");
    await screen.findByText(/Mesa pendiente de FL26-00003 recuperada/i);

    await userEvent.click(screen.getByRole("button", { name: "Finalizar orden" }));

    expect(await screen.findByText("PALLET_OUTPUT_NOT_CONFIRMED")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Gestiona la producción" })).toBeInTheDocument();
    expect(screen.getByText("FL26-00003")).toBeInTheDocument();
    expect(screen.getByText("Todavía no hay personas identificadas.")).toBeInTheDocument();
  });

  it("advances visible times every second when the server clock is ahead", async () => {
    let monotonicTime = 1_000;
    vi.spyOn(performance, "now").mockImplementation(() => monotonicTime);
    const futureServerTable = {
      ...tableState,
      serverTimeUtc: new Date(Date.now() + 60_000).toISOString(),
    };
    vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify(line), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([order]), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify(futureServerTable), { status: 200 }));

    render(<ProductionFlowPage />);
    await userEvent.type(screen.getByPlaceholderText("LINEA-TEST-01"), "LINEA-TEST-01{enter}");
    await screen.findByRole("heading", { name: "Escanea la orden" });
    await userEvent.type(screen.getByPlaceholderText("Escanea la orden"), "FL20-02277{enter}");

    expect(await screen.findByText("00:01:05")).toBeInTheDocument();
    monotonicTime += 1_100;
    await new Promise((resolve) => window.setTimeout(resolve, 1_100));

    await waitFor(() => {
      expect(screen.getByText("00:01:06")).toBeInTheDocument();
      expect(screen.getByText(/EMP-7.*00:01:06/)).toBeInTheDocument();
    });
  });

  it("starts a new order without asking for the line again", async () => {
    vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify(line), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify([order]), { status: 200 }))
      .mockResolvedValueOnce(new Response(null, { status: 404 }));

    render(<ProductionFlowPage />);
    await userEvent.type(screen.getByPlaceholderText("LINEA-TEST-01"), "LINEA-TEST-01{enter}");
    await screen.findByRole("heading", { name: "Escanea la orden" });
    await userEvent.type(screen.getByPlaceholderText("Escanea la orden"), "FL20-02277{enter}");
    await screen.findByRole("heading", { name: "Gestiona la producción" });

    await userEvent.click(screen.getByRole("button", { name: "Nueva orden" }));

    expect(screen.getByRole("heading", { name: "Escanea la orden" })).toBeInTheDocument();
    expect(screen.getByPlaceholderText("Escanea la orden")).toHaveValue("");
    expect(screen.getByText(/Línea LINEA-TEST-01 conservada/i)).toBeInTheDocument();
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
    expect(screen.queryByRole("button", { name: /cerrar palet como/i }))
      .not.toBeInTheDocument();
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

  it("keeps pallet work and NAV background status inside the production table", async () => {
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
        reservations: [{
          id: 47,
          reservedQuantity: 20,
          orderNumber: order.orderNumber,
          productNumber: order.productNumber,
          productDescription: order.productDescription,
          productPostingGroup: "P_ACABADO",
          lineName: line.name,
        }],
        employees: [{ id: 7, code: "EMP-7", name: "Operario piloto" }],
        supervisors: [],
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        code: "PREVIOUS_PALLET_OUTPUT_NOT_CONFIRMED",
      }), { status: 409 }));

    render(<ProductionFlowPage />);
    await userEvent.type(screen.getByRole("textbox", { name: /código de línea/i }), "LINEA-TEST-01{enter}");
    await screen.findByRole("heading", { name: "Escanea la orden" });
    await userEvent.type(screen.getByRole("textbox", { name: /orden de fabricación/i }), "FL20-02277{enter}");
    await userEvent.type(screen.getByRole("textbox", { name: /lector RFID/i }), "SYNTHETIC-CARD{enter}");
    await screen.findByText("Operario piloto");
    const palletButton = screen.getByRole("button", {
      name: /cerrar palet como Operario piloto/i,
    });
    await userEvent.click(palletButton);

    const dialog = await screen.findByRole("dialog", { name: /cerrar palet/i });
    expect(within(dialog).getByRole("textbox", { name: /cantidad buena/i }))
      .toHaveValue("20");
    expect(within(dialog).getByRole("group", { name: /empleado que cierra/i }))
      .toHaveTextContent("Operario piloto");
    expect(within(dialog).queryByRole("combobox", { name: /empleado que cierra/i }))
      .not.toBeInTheDocument();
    expect(within(dialog).getByText(/NAV se procesa en segundo plano/i))
      .toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /continuar a palés/i })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /confirmar NAV/i })).not.toBeInTheDocument();

    await userEvent.click(
      within(dialog).getByRole("button", { name: /^cerrar palet$/i }),
    );
    expect(await within(dialog).findByRole("alert")).toHaveTextContent(
      "Palet cerrado. Esperando confirmación de NAV antes del siguiente.",
    );
    expect(screen.getAllByText("Operario piloto").length).toBeGreaterThan(0);
    expect(screen.getByText("Tiempo productivo total")).toBeInTheDocument();
    expect(screen.getByText(/NAV se procesa en segundo plano/i)).toBeInTheDocument();

    await userEvent.keyboard("{Escape}");
    expect(screen.queryByRole("dialog", { name: /cerrar palet/i })).not.toBeInTheDocument();
    expect(palletButton).toHaveFocus();
  });
});
