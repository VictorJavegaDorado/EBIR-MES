import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { PalletClosePage } from "../../../../../src/frontend/src/features/pallet-close/ui/PalletClosePage";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("PalletClosePage", () => {
  it("creates a valid correlation when randomUUID is unavailable", async () => {
    const originalCrypto = globalThis.crypto;
    Object.defineProperty(globalThis, "crypto", {
      configurable: true,
      value: {
        getRandomValues: originalCrypto.getRandomValues.bind(originalCrypto),
      },
    });
    vi.spyOn(globalThis, "fetch").mockImplementation(
      async (_input, init) => {
        const body = JSON.parse(String(init?.body)) as {
          correlationId: string;
        };
        return new Response(
          JSON.stringify({ id: 127, correlationId: body.correlationId }),
          { status: 200 },
        );
      },
    );

    try {
      render(<PalletClosePage />);
      await fillRequiredFields();
      await userEvent.click(
        screen.getByRole("button", { name: /confirmar cierre/i }),
      );

      const [, init] = vi.mocked(globalThis.fetch).mock.calls[0];
      const body = JSON.parse(String(init?.body)) as {
        correlationId: string;
      };
      expect(body.correlationId).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      );
    } finally {
      Object.defineProperty(globalThis, "crypto", {
        configurable: true,
        value: originalCrypto,
      });
    }
  });

  it("loads the current pallet and defaults its quantity and only employee", async () => {
    vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            reservations: [
              {
                id: 44,
                reservedQuantity: 20,
                orderNumber: "OT-100",
                productNumber: "27920LG",
                productDescription: "Producto piloto",
                productPostingGroup: "P_MATPRIMA",
                lineName: "Línea uno",
              },
            ],
            employees: [{ id: 7, code: "EMP-7", name: "Operario siete" }],
            supervisors: [
              { id: 9, code: "EMP-9", name: "Supervisora nueve" },
            ],
          }),
          { status: 200 },
        ),
      )
      .mockImplementationOnce(async (_input, init) => {
        const body = JSON.parse(String(init?.body)) as {
          correlationId: string;
        };
        return new Response(
          JSON.stringify({ id: 126, correlationId: body.correlationId }),
          { status: 200 },
        );
      });

    render(
      <PalletClosePage
        line={{
          id: 12,
          code: "L-01",
          name: "Línea uno",
          workCenterCode: "CT-01",
          workCenterName: "Centro uno",
          operationalStatus: "PRODUCIENDO",
        }}
      />,
    );

    expect(await screen.findByText(/POK.*20 unidades/i)).toBeInTheDocument();
    expect(screen.queryByRole("combobox", { name: /reserva de palé/i })).not.toBeInTheDocument();
    expect(screen.getByRole("textbox", { name: /cantidad buena/i })).toHaveValue("20");
    expect(screen.getByRole("combobox", { name: /empleado que cierra/i })).toHaveValue("7");
    await userEvent.click(
      screen.getByRole("button", { name: /cerrar palet/i }),
    );

    expect(globalThis.fetch).toHaveBeenNthCalledWith(
      1,
      "/api/lines/12/pallet-close-options",
      expect.objectContaining({
        headers: { Accept: "application/json" },
      }),
    );
    const submitted = JSON.parse(
      String(vi.mocked(globalThis.fetch).mock.calls[1][1]?.body),
    ) as { goodQuantity: number; closedByEmployeeId: number };
    expect(submitted.goodQuantity).toBe(20);
    expect(submitted.closedByEmployeeId).toBe(7);
    expect(screen.getByText("P_MATPRIMA")).toBeInTheDocument();
    expect(screen.getByText("27920LG")).toBeInTheDocument();
    expect(await screen.findByText("Palé 126 cerrado")).toBeInTheDocument();
    expect(screen.getByText(/NAV y la impresión continúan/i)).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /reimprimir etiqueta/i }),
    ).toBeInTheDocument();
  });

  it("locks the close to the selected active operator and returns to the table", async () => {
    const onCancel = vi.fn();
    const onBusyChange = vi.fn();
    const fetchMock = vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify({
        reservations: [{
          id: 44,
          reservedQuantity: 20,
          orderNumber: "OT-100",
          productNumber: "27920LG",
          productDescription: "Producto piloto",
          productPostingGroup: "P_ACABADO",
          lineName: "Línea uno",
        }],
        employees: [{ id: 7, code: "EMP-7", name: "Operario siete" }],
        supervisors: [],
      }), { status: 200 }))
      .mockImplementationOnce(async (_input, init) => {
        const body = JSON.parse(String(init?.body)) as { correlationId: string };
        return new Response(
          JSON.stringify({ id: 126, correlationId: body.correlationId }),
          { status: 200 },
        );
      });

    render(
      <PalletClosePage
        line={{
          id: 12,
          code: "L-01",
          name: "Línea uno",
          workCenterCode: "CT-01",
          workCenterName: "Centro uno",
          operationalStatus: "PRODUCIENDO",
        }}
        selectedEmployee={{ id: 7, code: "EMP-7", name: "Operario siete" }}
        onCancel={onCancel}
        onBusyChange={onBusyChange}
      />,
    );

    const employee = await screen.findByRole("group", {
      name: /empleado que cierra/i,
    });
    expect(employee).toHaveTextContent("Operario siete");
    expect(screen.queryByRole("combobox", { name: /empleado que cierra/i }))
      .not.toBeInTheDocument();
    expect(screen.getByRole("textbox", { name: /cantidad buena/i })).toHaveFocus();

    await userEvent.click(screen.getByRole("button", { name: /^cerrar palet$/i }));

    const submitted = JSON.parse(String(fetchMock.mock.calls[1][1]?.body)) as {
      closedByEmployeeId: number;
    };
    expect(submitted.closedByEmployeeId).toBe(7);
    expect(onBusyChange).toHaveBeenCalledWith(true);
    expect(onBusyChange).toHaveBeenLastCalledWith(false);
    await userEvent.click(await screen.findByRole("button", { name: /volver a la mesa/i }));
    expect(onCancel).toHaveBeenCalledOnce();
  });

  it("rejects a preselected operator missing from the active options", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(JSON.stringify({
        reservations: [{
          id: 44,
          reservedQuantity: 20,
          orderNumber: "OT-100",
          productNumber: "27920LG",
          productDescription: "Producto piloto",
          productPostingGroup: "P_ACABADO",
          lineName: "Línea uno",
        }],
        employees: [],
        supervisors: [],
      }), { status: 200 }),
    );

    render(
      <PalletClosePage
        line={{
          id: 12,
          code: "L-01",
          name: "Línea uno",
          workCenterCode: "CT-01",
          workCenterName: "Centro uno",
          operationalStatus: "PRODUCIENDO",
        }}
        selectedEmployee={{ id: 7, code: "EMP-7", name: "Operario siete" }}
      />,
    );

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "PALLET_CLOSE_EMPLOYEE_NOT_AVAILABLE",
    );
    expect(screen.getByRole("button", { name: /^cerrar palet$/i })).toBeDisabled();
  });

  it("shows a recoverable error when line options cannot be loaded", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({ code: "PALLET_CLOSE_OPTIONS_UNAVAILABLE" }),
        { status: 503 },
      ),
    );

    render(
      <PalletClosePage
        line={{
          id: 12,
          code: "L-01",
          name: "Línea uno",
          workCenterCode: "CT-01",
          workCenterName: "Centro uno",
          operationalStatus: "PRODUCIENDO",
        }}
      />,
    );

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "No se puede preparar el cierre del palet",
    );
    expect(
      screen.getByRole("button", { name: /reintentar carga/i }),
    ).toBeInTheDocument();
  });

  it("treats an edited POK quantity as a partial close without exposing reservations", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify({
        reservations: [{
          id: 44,
          reservedQuantity: 20,
          orderNumber: "OT-100",
          productNumber: "27920LG",
          productDescription: "Producto piloto",
          productPostingGroup: "P_MATPRIMA",
          lineName: "Línea uno",
        }],
        employees: [{ id: 7, code: "EMP-7", name: "Operario siete" }],
        supervisors: [],
      }), { status: 200 }))
      .mockImplementationOnce(async (_input, init) => {
        const body = JSON.parse(String(init?.body)) as { correlationId: string };
        return new Response(JSON.stringify({ id: 130, correlationId: body.correlationId }), { status: 200 });
      });

    render(<PalletClosePage line={{
      id: 12,
      code: "L-01",
      name: "Línea uno",
      workCenterCode: "CT-01",
      workCenterName: "Centro uno",
      operationalStatus: "PRODUCIENDO",
    }} />);

    const quantity = await screen.findByRole("textbox", { name: /cantidad buena/i });
    await userEvent.clear(quantity);
    await userEvent.type(quantity, "19");
    await userEvent.selectOptions(
      screen.getByRole("combobox", { name: /motivo de la cantidad distinta/i }),
      "FALTA_MATERIAL",
    );
    await userEvent.click(screen.getByRole("button", { name: /cerrar palet/i }));

    expect(screen.queryByRole("combobox", { name: /reserva de palé/i })).not.toBeInTheDocument();
    expect(JSON.parse(String(fetchMock.mock.calls[1][1]?.body))).toEqual(expect.objectContaining({
      goodQuantity: 19,
      isPartial: true,
      partialReason: "FALTA_MATERIAL",
    }));
  });

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

  it("submits a partial close without supervisor when the reason is valid", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(
      async (_input, init) => {
        const body = JSON.parse(String(init?.body)) as { correlationId: string };
        return new Response(
          JSON.stringify({ id: 128, correlationId: body.correlationId }),
          { status: 200 },
        );
      },
    );
    render(<PalletClosePage />);

    await fillRequiredFields();
    await userEvent.click(
      screen.getByRole("checkbox", { name: /cierre parcial/i }),
    );
    await userEvent.selectOptions(
      screen.getByRole("combobox", { name: /motivo del cierre parcial/i }),
      "FIN_TURNO",
    );
    await userEvent.click(
      screen.getByRole("button", { name: /confirmar cierre/i }),
    );

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(JSON.parse(String(fetchMock.mock.calls[0][1]?.body))).toEqual(
      expect.objectContaining({
        authorizingSupervisorId: null,
        isPartial: true,
        partialReason: "FIN_TURNO",
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

  it("explains that NAV must confirm the previous pallet before the next close", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          detail: "detalle interno que no debe mostrarse",
          code: "PREVIOUS_PALLET_OUTPUT_NOT_CONFIRMED",
        }),
        { status: 409 },
      ),
    );
    render(<PalletClosePage />);

    await fillRequiredFields();
    await userEvent.click(
      screen.getByRole("button", { name: /confirmar cierre/i }),
    );

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(
      "Palet cerrado. Esperando confirmación de NAV antes del siguiente.",
    );
    expect(alert).not.toHaveTextContent("detalle interno");
    expect(alert).not.toHaveTextContent("Revisa los datos");
    expect(
      screen.getByRole("button", { name: /revisa los datos para continuar/i }),
    ).toBeDisabled();
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

  it("blocks an unsafe replay after a correlation conflict", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          detail: "detalle interno que no debe mostrarse",
          code: "CORRELATION_ID_PARAMETER_MISMATCH",
        }),
        { status: 409 },
      ),
    );
    render(<PalletClosePage />);

    await fillRequiredFields();
    await userEvent.click(
      screen.getByRole("button", { name: /confirmar cierre/i }),
    );

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(
      "Los datos no coinciden con el intento de cierre original",
    );
    expect(alert).not.toHaveTextContent("detalle interno");
    expect(
      screen.getByRole("button", { name: /revisa los datos para continuar/i }),
    ).toBeDisabled();
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
