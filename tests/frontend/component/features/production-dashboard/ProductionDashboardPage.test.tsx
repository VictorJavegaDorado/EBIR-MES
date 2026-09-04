import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ProductionDashboardPage } from "../../../../../src/frontend/src/features/production-dashboard/ui/ProductionDashboardPage";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

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
      },
      closedPallets: 3,
      latestNavState: "CONFIRMADA",
      latestLabelState: "IMPRESA",
      pendingNavOutputs: 0,
      navIssues: 0,
      pendingPrintJobs: 0,
      printIssues: 0,
    },
    {
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
    },
  ],
};

describe("ProductionDashboardPage", () => {
  it("shows every line with live production progress", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify(snapshot), { status: 200 }),
    );

    render(<ProductionDashboardPage />);

    expect(await screen.findByRole("heading", { name: "LINEA-01" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "LINEA-02" })).toBeInTheDocument();
    expect(screen.getByText("FL26-00008")).toBeInTheDocument();
    expect(screen.getByText("60 / 100 uds")).toBeInTheDocument();
    expect(screen.getByText("Operario piloto")).toBeInTheDocument();
    expect(screen.getByText("Linea disponible")).toBeInTheDocument();
    expect(screen.getByRole("progressbar")).toHaveAttribute("aria-valuenow", "60");
    expect(screen.getAllByText("Registrado").length).toBeGreaterThan(0);
  });
});
