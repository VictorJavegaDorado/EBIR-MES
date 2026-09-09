import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { AppShell } from "../../../../../src/frontend/src/widgets/app-shell/ui/AppShell";

afterEach(cleanup);

describe("AppShell navigation", () => {
  it("shows production and labels without exposing dashboard in the top bar", () => {
    render(<AppShell><span>Contenido</span></AppShell>);

    expect(screen.getByRole("link", { name: "Producción" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Etiquetas" })).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Dashboard" })).not.toBeInTheDocument();
  });
});
