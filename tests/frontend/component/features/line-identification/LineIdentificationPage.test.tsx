import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { LineIdentificationPage } from "../../../../../src/frontend/src/features/line-identification/ui/LineIdentificationPage";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("LineIdentificationPage", () => {
  it("requires a line code without calling the API", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch");
    render(<LineIdentificationPage />);

    await userEvent.click(
      screen.getByRole("button", { name: /consultar línea/i }),
    );

    expect(fetchMock).not.toHaveBeenCalled();
    expect(screen.getByRole("alert")).toHaveTextContent(
      "Introduce el código de la línea",
    );
  });

  it("normalizes the code and shows an identified line", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          id: 12,
          code: "L-01",
          name: "Línea uno",
          workCenterCode: "CT-01",
          workCenterName: "Mecanizado",
          operationalStatus: "LIBRE",
        }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      ),
    );
    render(<LineIdentificationPage />);

    await userEvent.type(
      screen.getByRole("textbox", { name: /línea de fabricación/i }),
      "  l-01  ",
    );
    await userEvent.click(
      screen.getByRole("button", { name: /consultar línea/i }),
    );

    expect(globalThis.fetch).toHaveBeenCalledWith(
      "/api/lines/L-01",
      expect.objectContaining({ headers: { Accept: "application/json" } }),
    );
    expect(await screen.findByText("Línea uno")).toBeInTheDocument();
    expect(screen.getByText("Mecanizado")).toBeInTheDocument();
    expect(screen.getByText("LIBRE")).toBeInTheDocument();
  });

  it("shows the safe API error and its functional code", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          detail: "No existe una línea configurada con el código L-99.",
          code: "LINE_NOT_FOUND",
        }),
        {
          status: 404,
          headers: { "Content-Type": "application/problem+json" },
        },
      ),
    );
    render(<LineIdentificationPage />);

    await userEvent.type(
      screen.getByRole("textbox", { name: /línea de fabricación/i }),
      "L-99",
    );
    await userEvent.click(
      screen.getByRole("button", { name: /consultar línea/i }),
    );

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(
      "No existe una línea configurada con el código L-99.",
    );
    expect(alert).toHaveTextContent("LINE_NOT_FOUND");
  });

  it("shows an unavailable message when the request cannot reach the API", async () => {
    vi.spyOn(globalThis, "fetch").mockRejectedValue(new TypeError("network"));
    render(<LineIdentificationPage />);

    await userEvent.type(
      screen.getByRole("textbox", { name: /línea de fabricación/i }),
      "L-01",
    );
    await userEvent.click(
      screen.getByRole("button", { name: /consultar línea/i }),
    );

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("No se puede contactar con el servicio");
    expect(alert).toHaveTextContent("LINE_IDENTIFICATION_UNAVAILABLE");
  });
});
