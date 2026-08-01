import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ProductionOrderSelectionPage } from "../../../../../src/frontend/src/features/production-order-selection/ui/ProductionOrderSelectionPage";

const order = {
  productionOrderId: 28,
  orderNumber: "FL20-02277",
  productNumber: "27979CI",
  productDescription: "ESPEJO GRAYCE TWIN",
  lotNumber: "FL2002277",
  targetQuantity: 10,
  goodQuantity: 0,
  reservedQuantity: 0,
  scrapQuantity: 0,
  runTimeMinutes: 36,
  state: "IMPORTADA",
  importedAtUtc: "2026-08-01T11:20:53Z",
};

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("ProductionOrderSelectionPage", () => {
  it("lists NAV lot and selects an order", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify([order]), { status: 200 }),
    );
    const onOrderChange = vi.fn();
    render(
      <ProductionOrderSelectionPage selectedOrder={null} onOrderChange={onOrderChange} />,
    );

    expect(await screen.findByText("FL20-02277")).toBeInTheDocument();
    expect(screen.getByText("FL2002277")).toBeInTheDocument();
    expect(screen.getByText("36 min/ud.")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: /seleccionar orden/i }));
    expect(onOrderChange).toHaveBeenCalledWith(order);
    expect(globalThis.fetch).toHaveBeenCalledWith(
      "/api/production-orders",
      expect.objectContaining({ headers: { Accept: "application/json" } }),
    );
  });

  it("filters by lot without another API request", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify([order]), { status: 200 }),
    );
    render(
      <ProductionOrderSelectionPage selectedOrder={null} onOrderChange={vi.fn()} />,
    );
    await screen.findByText("FL20-02277");

    await userEvent.type(
      screen.getByRole("textbox", { name: /buscar por orden/i }),
      "NO-EXISTE",
    );
    expect(screen.getByText("No hay órdenes que coincidan")).toBeInTheDocument();
    expect(globalThis.fetch).toHaveBeenCalledTimes(1);
  });

  it("shows a safe error and retries", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(
        JSON.stringify({ code: "PRODUCTION_ORDER_SELECTION_UNAVAILABLE" }),
        { status: 503 },
      ))
      .mockResolvedValueOnce(new Response(JSON.stringify([order]), { status: 200 }));
    render(
      <ProductionOrderSelectionPage selectedOrder={null} onOrderChange={vi.fn()} />,
    );

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "PRODUCTION_ORDER_SELECTION_UNAVAILABLE",
    );
    await userEvent.click(screen.getByRole("button", { name: /reintentar/i }));
    expect(await screen.findByText("FL20-02277")).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
