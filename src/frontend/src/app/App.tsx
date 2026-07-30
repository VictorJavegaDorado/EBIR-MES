import { useState } from "react";
import { LineIdentificationPage } from "../features/line-identification/ui/LineIdentificationPage";
import { PalletClosePage } from "../features/pallet-close/ui/PalletClosePage";
import { AppShell } from "../widgets/app-shell/ui/AppShell";
import type { IdentifiedLine } from "../features/line-identification/model/lineIdentification";

export function App() {
  const [activeFeature, setActiveFeature] = useState<
    "line-identification" | "pallet-close"
  >("line-identification");
  const [identifiedLine, setIdentifiedLine] = useState<IdentifiedLine | null>(
    null,
  );

  return (
    <AppShell>
      <nav className="feature-navigation" aria-label="Funcionalidades MES">
        <button
          className={activeFeature === "line-identification" ? "active" : ""}
          type="button"
          onClick={() => setActiveFeature("line-identification")}
          aria-current={
            activeFeature === "line-identification" ? "page" : undefined
          }
        >
          Identificación de línea
        </button>
        <button
          className={activeFeature === "pallet-close" ? "active" : ""}
          type="button"
          disabled={!identifiedLine}
          onClick={() => setActiveFeature("pallet-close")}
          aria-current={activeFeature === "pallet-close" ? "page" : undefined}
        >
          Cierre de palé
        </button>
      </nav>

      {activeFeature === "line-identification" ? (
        <LineIdentificationPage onLineChange={setIdentifiedLine} />
      ) : (
        <PalletClosePage line={identifiedLine!} />
      )}
    </AppShell>
  );
}
