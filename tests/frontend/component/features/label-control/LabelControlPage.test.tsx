import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { LabelControlPage } from "../../../../../src/frontend/src/features/label-control/ui/LabelControlPage";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("LabelControlPage", () => {
  it("selects an order and highlights a recovered pallet before supervised reprint", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      const url = String(input);
      if (url === "/api/label-control") {
        return Response.json({
          serverTimeUtc: "2026-09-09T08:00:00Z",
          orders: [{
            orderId: 42,
            orderNumber: "FL26-00015",
            productNumber: "27920LG",
            productDescription: "Producto piloto",
            orderState: "ABIERTA",
            lineId: 40,
            lineCode: "LINEA-TEST-01",
            lineName: "Línea piloto",
            lastPalletClosedAtUtc: "2026-09-09T07:55:00Z",
            pallets: [{
              palletId: 58,
              palletNumber: 1,
              goodQuantity: 20,
              isLast: false,
              closedAtUtc: "2026-09-09T07:55:00Z",
              navOperationId: 69,
              navState: "CONFIRMADA",
              labelId: 60,
              labelState: "IMPRESA",
              printJobId: 75,
              printState: "COMPLETADO",
              printAttempts: 1,
              hasIncident: true,
              canReprint: true,
            }],
          }],
        });
      }
      if (url === "/api/lines/40/pallet-close-options") {
        return Response.json({
          reservations: [],
          operators: [],
          supervisors: [{ id: 48, code: "SUP-48", name: "Supervisor piloto" }],
          partialReasons: [],
        });
      }
      throw new Error(`Unexpected request: ${url}`);
    });

    render(<LabelControlPage />);

    expect((await screen.findAllByText("FL26-00015")).length).toBeGreaterThan(0);
    fireEvent.click(screen.getByRole("button", { name: /Palé 1/i }));

    expect(await screen.findByText("Impresa · incidencia recuperada")).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText("Supervisor piloto")).toBeInTheDocument());
    expect(screen.getByRole("button", { name: "Reimprimir etiqueta" })).toBeEnabled();
  });

  it("blocks printing while NAV is not confirmed", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(Response.json({
      serverTimeUtc: "2026-09-09T08:00:00Z",
      orders: [{
        orderId: 43,
        orderNumber: "FL26-00016",
        productNumber: "ART-1",
        productDescription: "Producto",
        orderState: "ABIERTA",
        lineId: 40,
        lineCode: "LINEA-TEST-01",
        lineName: "Línea piloto",
        lastPalletClosedAtUtc: "2026-09-09T07:55:00Z",
        pallets: [{
          palletId: 61,
          palletNumber: 1,
          goodQuantity: 20,
          isLast: false,
          closedAtUtc: "2026-09-09T07:55:00Z",
          navOperationId: 70,
          navState: "RESULTADO_DESCONOCIDO",
          labelId: 63,
          labelState: "PENDIENTE_NAV",
          printJobId: null,
          printState: null,
          printAttempts: 0,
          hasIncident: true,
          canReprint: false,
        }],
      }],
    }));

    render(<LabelControlPage />);
    fireEvent.click(await screen.findByRole("button", { name: /Palé 1/i }));

    expect(screen.getByText(/Resuelve primero la conciliación NAV/i)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Reimprimir etiqueta" })).not.toBeInTheDocument();
  });
});
