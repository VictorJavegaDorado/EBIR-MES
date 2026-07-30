import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { PalletClosePage } from "../../../../../src/frontend/src/features/pallet-close/ui/PalletClosePage";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("PalletClosePage", () => {
  it("rejects incomplete identifiers without calling the API", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch");
    render(<PalletClosePage />);

    await userEvent.click(
      screen.getByRole("button", { name: /confirmar cierre/i }),
    );

    expect(fetchMock).not.toHaveBeenCalled();
    expect(screen.getByRole("alert")).toHaveTextContent(
      "Revisa la reserva, la cantidad y los identificadores",
    );
  });

  it("submits a complete close and shows the confirmed pallet", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(
      async (_input, init) => {
        const body = JSON.parse(String(init?.body)) as {
          correlationId: string;
        };
        return new Response(
          JSON.stringify({ id: 123, correlationId: body.correlationId }),
          {
            status: 200,
            headers: { "Content-Type": "application/json" },
          },
        );
      },
    );
    render(<PalletClosePage />);

    await fillRequiredFields();
    await userEvent.click(
      screen.getByRole("button", { name: /confirmar cierre/i }),
    );

    expect(globalThis.fetch).toHaveBeenCalledTimes(1);
    const [url, init] = vi.mocked(globalThis.fetch).mock.calls[0];
    expect(url).toBe("/api/pallet-reservations/44/close");
    expect(init).toEqual(
      expect.objectContaining({
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
      }),
    );
    expect(JSON.parse(String(init?.body))).toEqual({
      goodQuantity: 20,
      closedByEmployeeId: 7,
      authorizingSupervisorId: null,
      isPartial: false,
      partialReason: null,
      correlationId: expect.any(String),
    });
    expect(await screen.findByText("Palé 123 cerrado")).toBeInTheDocument();
  });

  it("sends the selected partial reason and supervisor", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(
      async (_input, init) => {
        const body = JSON.parse(String(init?.body)) as {
          correlationId: string;
        };
        return new Response(
          JSON.stringify({ id: 124, correlationId: body.correlationId }),
          { status: 200 },
        );
      },
    );
    render(<PalletClosePage />);

    await fillRequiredFields();
    await userEvent.type(
      screen.getByRole("textbox", { name: /supervisor autorizador/i }),
      "9",
    );
    await userEvent.click(
      screen.getByRole("checkbox", { name: /cierre parcial/i }),
    );
    await userEvent.selectOptions(
      screen.getByRole("combobox", { name: /motivo del cierre parcial/i }),
      "FALTA_MATERIAL",
    );
    await userEvent.click(
      screen.getByRole("button", { name: /confirmar cierre/i }),
    );

    const [, init] = vi.mocked(globalThis.fetch).mock.calls[0];
    expect(JSON.parse(String(init?.body))).toEqual(
      expect.objectContaining({
        authorizingSupervisorId: 9,
        isPartial: true,
        partialReason: "FALTA_MATERIAL",
      }),
    );
  });

  it("reuses the correlation when an unavailable close is retried unchanged", async () => {
    vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            detail: "No se puede cerrar el palé en este momento.",
            code: "PALLET_CLOSE_UNAVAILABLE",
          }),
          { status: 503 },
        ),
      )
      .mockImplementationOnce(async (_input, init) => {
        const body = JSON.parse(String(init?.body)) as {
          correlationId: string;
        };
        return new Response(
          JSON.stringify({ id: 125, correlationId: body.correlationId }),
          { status: 200 },
        );
      });
    render(<PalletClosePage />);

    await fillRequiredFields();
    await userEvent.click(
      screen.getByRole("button", { name: /confirmar cierre/i }),
    );
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "PALLET_CLOSE_UNAVAILABLE",
    );

    await userEvent.click(
      screen.getByRole("button", { name: /reintentar cierre/i }),
    );

    expect(globalThis.fetch).toHaveBeenCalledTimes(2);
    const first = JSON.parse(
      String(vi.mocked(globalThis.fetch).mock.calls[0][1]?.body),
    ) as { correlationId: string };
    const second = JSON.parse(
      String(vi.mocked(globalThis.fetch).mock.calls[1][1]?.body),
    ) as { correlationId: string };
    expect(second.correlationId).toBe(first.correlationId);
    expect(await screen.findByText("Palé 125 cerrado")).toBeInTheDocument();
  });

  it("creates a new correlation after the request data changes", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          detail: "Cierre rechazado.",
          code: "PALLET_RESERVATION_NOT_ACTIVE",
        }),
        { status: 409 },
      ),
    );
    render(<PalletClosePage />);

    await fillRequiredFields();
    await userEvent.click(
      screen.getByRole("button", { name: /confirmar cierre/i }),
    );
    await screen.findByRole("alert");

    const quantity = screen.getByRole("textbox", {
      name: /cantidad buena/i,
    });
    await userEvent.clear(quantity);
    await userEvent.type(quantity, "19");
    await userEvent.click(
      screen.getByRole("button", { name: /confirmar cierre/i }),
    );

    const first = JSON.parse(
      String(vi.mocked(globalThis.fetch).mock.calls[0][1]?.body),
    ) as { correlationId: string };
    const second = JSON.parse(
      String(vi.mocked(globalThis.fetch).mock.calls[1][1]?.body),
    ) as { correlationId: string };
    expect(second.correlationId).not.toBe(first.correlationId);
  });
});

async function fillRequiredFields() {
  await userEvent.type(
    screen.getByRole("textbox", { name: /reserva de palé/i }),
    "44",
  );
  await userEvent.type(
    screen.getByRole("textbox", { name: /cantidad buena/i }),
    "20",
  );
  await userEvent.type(
    screen.getByRole("textbox", { name: /empleado que cierra/i }),
    "7",
  );
}
