import { useEffect, useMemo, useRef, useState } from "react";
import { getPalletCloseOptions } from "../../pallet-close/api/getPalletCloseOptions";
import type { PalletEmployeeOption } from "../../pallet-close/model/palletClose";
import { PalletLabelReprint } from "../../label-reprint/ui/PalletLabelReprint";
import { getLabelControl } from "../api/getLabelControl";
import type {
  LabelControlOrder,
  LabelControlPallet,
  LabelControlSnapshot,
} from "../model/labelControl";

export function LabelControlPage() {
  const [snapshot, setSnapshot] = useState<LabelControlSnapshot | null>(null);
  const [query, setQuery] = useState("");
  const [selectedOrderId, setSelectedOrderId] = useState<number | null>(null);
  const [selectedPalletId, setSelectedPalletId] = useState<number | null>(null);
  const [supervisors, setSupervisors] = useState<PalletEmployeeOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingSupervisors, setLoadingSupervisors] = useState(false);
  const [error, setError] = useState("");
  const request = useRef<AbortController | null>(null);

  const load = async () => {
    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    setLoading(true);
    setError("");
    try {
      const next = await getLabelControl(controller.signal);
      setSnapshot(next);
      setSelectedOrderId((current) =>
        current && next.orders.some((order) => order.orderId === current)
          ? current
          : next.orders[0]?.orderId ?? null);
    } catch {
      if (!controller.signal.aborted) setError("No se puede cargar el control de etiquetas.");
    } finally {
      if (request.current === controller) {
        request.current = null;
        setLoading(false);
      }
    }
  };

  useEffect(() => {
    void load();
    return () => request.current?.abort();
  }, []);

  const orders = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase("es");
    if (!normalized) return snapshot?.orders ?? [];
    return (snapshot?.orders ?? []).filter((order) =>
      [order.orderNumber, order.productNumber, order.productDescription, order.lineName]
        .some((value) => value.toLocaleLowerCase("es").includes(normalized)));
  }, [query, snapshot]);

  const selectedOrder = snapshot?.orders.find(
    (order) => order.orderId === selectedOrderId,
  ) ?? null;
  const selectedPallet = selectedOrder?.pallets.find(
    (pallet) => pallet.palletId === selectedPalletId,
  ) ?? null;

  function selectOrder(orderId: number) {
    setSelectedOrderId(orderId);
    setSelectedPalletId(null);
    setSupervisors([]);
  }

  useEffect(() => {
    if (!selectedOrder || !selectedPallet?.canReprint) return;
    const controller = new AbortController();
    setLoadingSupervisors(true);
    getPalletCloseOptions(selectedOrder.lineId, controller.signal)
      .then((options) => setSupervisors(options.supervisors))
      .catch(() => setError("No se pueden cargar los supervisores autorizadores."))
      .finally(() => setLoadingSupervisors(false));
    return () => controller.abort();
  }, [selectedOrder, selectedPallet?.palletId, selectedPallet?.canReprint]);

  return (
    <section className="label-control-page">
      <header className="label-control-heading">
        <div>
          <p className="eyebrow">Control de etiquetas</p>
          <h1>Orden, palé y estado de impresión</h1>
          <p>Localiza cualquier palé y solicita una copia sin volver a enviar su salida a NAV.</p>
        </div>
        <button type="button" onClick={() => void load()} disabled={loading}>
          {loading ? "Actualizando…" : "Actualizar estados"}
        </button>
      </header>

      {error && <div className="label-control-alert" role="alert">{error}</div>}

      <div className="label-control-layout">
        <aside className="label-order-panel" aria-label="Seleccionar orden">
          <label>
            Buscar orden o artículo
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Ej.: FL26-00015 o 27920LG"
            />
          </label>
          <div className="label-order-list">
            {orders.map((order) => (
              <button
                type="button"
                key={order.orderId}
                className={order.orderId === selectedOrderId ? "selected" : ""}
                onClick={() => selectOrder(order.orderId)}
              >
                <span>{order.lineName}</span>
                <strong>{order.orderNumber}</strong>
                <small>{order.productNumber} · {order.pallets.length} palés</small>
                {order.pallets.some((pallet) => pallet.hasIncident) && (
                  <i>Contiene incidencias</i>
                )}
              </button>
            ))}
            {!loading && orders.length === 0 && <p>No hay órdenes que coincidan.</p>}
          </div>
        </aside>

        <div className="label-pallet-panel">
          {selectedOrder ? (
            <OrderPallets
              order={selectedOrder}
              selectedPalletId={selectedPalletId}
              onSelect={setSelectedPalletId}
            />
          ) : (
            <div className="label-control-empty">Selecciona una orden para ver sus palés.</div>
          )}

          {selectedPallet && selectedOrder && (
            <PalletAction
              key={selectedPallet.palletId}
              pallet={selectedPallet}
              supervisors={supervisors}
              loadingSupervisors={loadingSupervisors}
            />
          )}
        </div>
      </div>
    </section>
  );
}

function OrderPallets({
  order,
  selectedPalletId,
  onSelect,
}: {
  order: LabelControlOrder;
  selectedPalletId: number | null;
  onSelect: (palletId: number) => void;
}) {
  return (
    <section className="label-order-detail">
      <header>
        <div><span>Orden seleccionada</span><strong>{order.orderNumber}</strong></div>
        <div><span>Artículo</span><strong>{order.productNumber}</strong></div>
        <p>{order.productDescription}</p>
      </header>
      <div className="label-pallet-grid">
        {order.pallets.map((pallet) => (
          <button
            type="button"
            key={pallet.palletId}
            className={`${palletTone(pallet)} ${pallet.palletId === selectedPalletId ? "selected" : ""}`}
            onClick={() => onSelect(pallet.palletId)}
          >
            <span className="pallet-number">Palé {pallet.palletNumber}</span>
            <strong>{pallet.goodQuantity} uds.</strong>
            <span>{palletStatus(pallet)}</span>
            {pallet.hasIncident && <i>Incidencia registrada</i>}
          </button>
        ))}
      </div>
    </section>
  );
}

function PalletAction({
  pallet,
  supervisors,
  loadingSupervisors,
}: {
  pallet: LabelControlPallet;
  supervisors: PalletEmployeeOption[];
  loadingSupervisors: boolean;
}) {
  if (pallet.canReprint) {
    return (
      <section className="label-action-card ready">
        <header><div><span>Palé {pallet.palletNumber}</span><strong>Etiqueta disponible</strong></div><b>IMPRESA</b></header>
        {loadingSupervisors
          ? <p>Cargando autorización de supervisor…</p>
          : <PalletLabelReprint palletId={pallet.palletId} supervisors={supervisors} />}
      </section>
    );
  }

  const navBlocked = pallet.navState !== "CONFIRMADA";
  return (
    <section className="label-action-card blocked">
      <header><div><span>Palé {pallet.palletNumber}</span><strong>{palletStatus(pallet)}</strong></div><b>REVISAR</b></header>
      <p>
        {navBlocked
          ? "La salida todavía no está confirmada en MES. Resuelve primero la conciliación NAV; no se creará una impresión duplicada."
          : "La impresión original no consta como completada. Revisa el trabajo antes de solicitar otra copia."}
      </p>
    </section>
  );
}

function palletTone(pallet: LabelControlPallet): string {
  if (
    pallet.navState === "ERROR_DEFINITIVO"
    || pallet.navState === "RESULTADO_DESCONOCIDO"
    || pallet.labelState === "ERROR"
    || pallet.printState === "ERROR"
    || pallet.printState === "RESULTADO_DESCONOCIDO"
  ) return "danger";
  if (pallet.canReprint) return pallet.hasIncident ? "recovered" : "ready";
  return "pending";
}

function palletStatus(pallet: LabelControlPallet): string {
  if (pallet.canReprint) return pallet.hasIncident ? "Impresa · incidencia recuperada" : "Impresa correctamente";
  if (pallet.navState !== "CONFIRMADA") return "Pendiente de conciliación NAV";
  if (pallet.labelState === "ERROR" || pallet.printState === "ERROR") return "Error de impresión";
  return "Impresión pendiente";
}
