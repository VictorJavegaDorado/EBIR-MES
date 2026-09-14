import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ProductionDashboardPage } from "../../../../../src/frontend/src/features/production-dashboard/ui/ProductionDashboardPage";

const freeLine = {
  lineId: 2,
  lineCode: "LINEA-02",
  lineName: "Linea libre",
  workCenterCode: "CT-01",
  workCenterName: "Fabricacion",
  operationalState: "LIBRE",
  blockReason: null,
  updatedAtUtc: "2026-09-04T10:00:00Z",
  order: null,
  table: null,
  closedPallets: 0,
  latestNavState: null,
  latestLabelState: null,
  pendingNavOutputs: 0,
  navIssues: 0,
  pendingPrintJobs: 0,
  printIssues: 0,
  theoreticalUnitsToDate: 0,
  resourceSeconds: 0,
  supervisorNavEmployeeCode: null,
  supervisorName: null,
};

const snapshot = {
  serverTimeUtc: "2026-09-04T10:00:00Z",
  lines: [
    {
      lineId: 1,
      lineCode: "LINEA-01",
      lineName: "Linea uno",
      workCenterCode: "CT-01",
      workCenterName: "Fabricacion",
      operationalState: "PRODUCIENDO",
      blockReason: null,
      updatedAtUtc: "2026-09-04T10:00:00Z",
      order: {
        productionOrderId: 36,
        orderNumber: "FL26-00008",
        productNumber: "27920LG",
        productDescription: "Producto piloto",
        lotNumber: "LOTE-08",
        targetQuantity: 100,
        goodQuantity: 60,
        reservedQuantity: 20,
        scrapQuantity: 0,
        runTimeMinutes: 10,
        state: "ABIERTA",
        importedAtUtc: "2026-09-04T09:00:00Z",
      },
      table: {
        lineSessionId: 40,
        orderId: 36,
        lineId: 1,
        state: "PRODUCIENDO",
        startedAtUtc: "2026-09-04T09:30:00Z",
        serverTimeUtc: "2026-09-04T10:00:00Z",
        productiveSeconds: 1800,
        activeResources: 2,
        currentTheoreticalCapacityPerHour: 12,
        palletFormatCode: "POK",
        unitsPerPallet: 20,
        operators: [{
          employeeId: 7,
          navEmployeeCode: "EMP-7",
          fullName: "Operario piloto",
          entryAtUtc: "2026-09-04T09:30:00Z",
          productiveSeconds: 1800,
          status: "PRODUCIENDO",
        }],
        theoreticalUnitsToDate: 0,
        resourceSeconds: 0,
      },
      closedPallets: 3,
      latestNavState: "CONFIRMADA",
      latestLabelState: "IMPRESA",
      pendingNavOutputs: 0,
      navIssues: 0,
      pendingPrintJobs: 0,
      printIssues: 0,
      theoreticalUnitsToDate: 50,
      resourceSeconds: 1800,
      supervisorNavEmployeeCode: "412",
      supervisorName: "Ana Pérez Soler",
    },
    freeLine,
  ],
};

const supervisors = [{
  navEmployeeCode: "412",
  fullName: "Ana Pérez Soler",
  lines: [{ lineId: 1, lineCode: "LINEA-01", lineName: "Linea uno" }],
}];

function mockApi(snapshotBody: unknown, supervisorsBody: unknown = supervisors) {
  return vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
    const url = String(input);
    const body = url.includes("/api/production-dashboard/supervisors") ? supervisorsBody : snapshotBody;
    return Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));
  });
}

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  window.history.replaceState(null, "", "/dashboard");
});

describe("ProductionDashboardPage", () => {
  it("shows every line with live production progress", async () => {
    mockApi(snapshot);

    render(<ProductionDashboardPage />);

    expect(await screen.findByRole("heading", { name: "LINEA-01" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "LINEA-02" })).toBeInTheDocument();
    expect(screen.getByText("FL26-00008")).toBeInTheDocument();
    expect(screen.getByText("de 100 uds")).toBeInTheDocument();
    expect(screen.getByText("Operario piloto")).toBeInTheDocument();
    expect(screen.getByText("Línea disponible")).toBeInTheDocument();
    expect(screen.getByRole("progressbar")).toHaveAttribute("aria-valuenow", "60");
    expect(screen.getByText("120 %")).toBeInTheDocument();
    expect(screen.getByRole("img", { name: /semáforo de productividad: verde/i })).toBeInTheDocument();
    expect(screen.getByText("1,00")).toBeInTheDocument();
    expect(screen.getByText("TIEMPO GLOBAL DE MESA")).toBeInTheDocument();
    expect(screen.getAllByText("Registrado").length).toBeGreaterThan(0);
    expect(screen.getByText("Sin acción · dentro de ritmo.")).toBeInTheDocument();
    expect(screen.getByRole("combobox", { name: /jefe de línea/i })).toHaveValue("");
    expect(screen.getByText("Vista").nextElementSibling?.textContent).toBe("Toda la planta");
  });

  it("filters by the supervisor in the URL and shows only the assigned lines", async () => {
    window.history.replaceState(null, "", "/dashboard?jefe=412");
    const filtered = { ...snapshot, lines: [snapshot.lines[0]], supervisor: supervisors[0] };
    const fetchMock = mockApi(filtered);

    render(<ProductionDashboardPage />);

    expect(await screen.findByRole("heading", { name: "LINEA-01" })).toBeInTheDocument();
    expect(fetchMock.mock.calls.some(([input]) =>
      String(input) === "/api/production-dashboard?supervisor=412")).toBe(true);
    expect(screen.getByText("Ana Pérez Soler")).toBeInTheDocument();
    expect(screen.getByText("Mis líneas")).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "LINEA-02" })).not.toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getByRole("combobox", { name: /jefe de línea/i })).toHaveValue("412"));
  });

  it("changes the supervisor from the selector and keeps it in the URL", async () => {
    const fetchMock = mockApi(snapshot);

    render(<ProductionDashboardPage />);
    await screen.findByRole("heading", { name: "LINEA-01" });
    await screen.findByRole("option", { name: /Ana Pérez Soler/ });
    await userEvent.selectOptions(screen.getByRole("combobox", { name: /jefe de línea/i }), "412");

    await waitFor(() => expect(fetchMock.mock.calls.some(([input]) =>
      String(input) === "/api/production-dashboard?supervisor=412")).toBe(true));
    expect(window.location.search).toBe("?jefe=412");
  });

  it("switches to the plant overview when more than six lines are visible", async () => {
    const many = {
      ...snapshot,
      lines: Array.from({ length: 8 }, (_, index) => ({
        ...freeLine,
        lineId: index + 10,
        lineCode: `LINEA-${index + 10}`,
        supervisorName: index < 4 ? "Ana Pérez Soler" : "Luis Gil Font",
        supervisorNavEmployeeCode: index < 4 ? "412" : "577",
      })),
    };
    mockApi(many);

    render(<ProductionDashboardPage />);

    expect(await screen.findByRole("heading", { name: "LINEA-10" })).toBeInTheDocument();
    expect(document.querySelectorAll(".dashboard-tile")).toHaveLength(8);
    expect(document.querySelectorAll(".dashboard-line-card")).toHaveLength(0);
    expect(screen.getAllByText("Ana").length).toBe(4);
  });
});
