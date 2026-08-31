import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { PalletLabelReprint } from "../../../../../src/frontend/src/features/label-reprint/ui/PalletLabelReprint";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const supervisors = [
  { id: 48, code: "664", name: "Supervisor piloto" },
];

describe("PalletLabelReprint", () => {
  it("queues one supervised copy and locks the successful request", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(
      async (_input, init) => {
        const body = JSON.parse(String(init?.body)) as { correlationId: string };
        return new Response(JSON.stringify({
          id: 19,
          palletId: 29,
          correlationId: body.correlationId,
        }), { status: 201 });
      },
    );

    render(
      <PalletLabelReprint
        palletId={29}
        supervisors={supervisors}
        defaultSupervisorId={48}
      />,
    );
    await userEvent.type(
      screen.getByRole("textbox", { name: /motivo de la copia/i }),
      "Etiqueta dañada",
    );
    await userEvent.click(
      screen.getByRole("button", { name: /reimprimir etiqueta/i }),
    );

    expect(fetchMock).toHaveBeenCalledOnce();
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/pallets/29/label-reprints",
      expect.objectContaining({ method: "POST" }),
    );
    expect(JSON.parse(String(fetchMock.mock.calls[0][1]?.body))).toEqual({
      requestedBySupervisorId: 48,
      reason: "Etiqueta dañada",
      correlationId: expect.any(String),
    });
    expect(await screen.findByText(/trabajo 19/i)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /reimprimir/i }))
      .not.toBeInTheDocument();
  });

  it("requires a reason without calling the API", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch");
    render(
      <PalletLabelReprint
        palletId={29}
        supervisors={supervisors}
        defaultSupervisorId={48}
      />,
    );

    await userEvent.click(
      screen.getByRole("button", { name: /reimprimir etiqueta/i }),
    );

    expect(fetchMock).not.toHaveBeenCalled();
    expect(screen.getByRole("alert")).toHaveTextContent(
      "REPRINT_REASON_REQUIRED",
    );
  });

  it("reuses the correlation when a safe retry is needed", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(new Response(JSON.stringify({
        code: "PALLET_LABEL_NOT_PRINTED",
      }), { status: 409 }))
      .mockImplementationOnce(async (_input, init) => {
        const body = JSON.parse(String(init?.body)) as { correlationId: string };
        return new Response(JSON.stringify({
          id: 20,
          palletId: 29,
          correlationId: body.correlationId,
        }), { status: 201 });
      });
    render(
      <PalletLabelReprint
        palletId={29}
        supervisors={supervisors}
        defaultSupervisorId={48}
      />,
    );
    await userEvent.type(
      screen.getByRole("textbox", { name: /motivo de la copia/i }),
      "No legible",
    );
    await userEvent.click(
      screen.getByRole("button", { name: /reimprimir etiqueta/i }),
    );
    await userEvent.click(
      await screen.findByRole("button", { name: /reintentar copia/i }),
    );

    const first = JSON.parse(String(fetchMock.mock.calls[0][1]?.body)) as {
      correlationId: string;
    };
    const second = JSON.parse(String(fetchMock.mock.calls[1][1]?.body)) as {
      correlationId: string;
    };
    expect(second.correlationId).toBe(first.correlationId);
    expect(await screen.findByText(/trabajo 20/i)).toBeInTheDocument();
  });
});
